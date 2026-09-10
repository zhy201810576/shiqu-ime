# MemeBoard 表情包发送归一化经验（240×240 / 静图 ≤500KB / 动图 ≤1MB）

## 背景与目标

MemeBoard（拾趣输入法，fcitx5-android 分支）从 MT Photos 拉取表情包发送到微信/QQ 时，图片尺寸与体积不固定。需求是发送前统一归一化：

- **尺寸**：统一等比缩放到最长边 240px（正方形图正好 240×240，横幅/竖幅保持比例不裁切）
- **静图**：单张 ≤500KB
- **动图（GIF）**：单张 ≤1MB

## 核心方案

发送链路原本是「下载预览图 → 直接发送」。改造为「下载 → 归一化 → 发送」，在下载之后、发送之前插入一个统一处理步骤，所有入口（主面板、搜索页、分享）复用。

关键文件：

- `MemeBoardImageProcessor.kt` —— 归一化调度（静图缩放压缩 + GIF 缩放重编码），`suspend fun prepare(file, mime): Pair<File, String>`
- `gif/NeuQuant.kt`、`gif/LZWEncoder.kt`、`gif/AnimatedGifEncoder.kt` —— 纯 Java GIF 编码器

接入点只需一行，把 `download()` 改成「下载 + prepare」：

```kotlin
private suspend fun download(file: MtFile): Pair<File, String> {
    val local = repository.download(file)
    val mime = guessMime(local.extension)
    return MemeBoardImageProcessor.prepare(local, mime)
}
```

## 静图处理（Bitmap 原生 API，零依赖）

1. `BitmapFactory.Options.inJustDecodeBounds` 先读尺寸，快速路径：已 ≤240 且 ≤500KB 直接原样返回（避免无谓重编码）。
2. 按 2 的幂算 `inSampleSize` 降采样，防止解码超大图 OOM。
3. `Bitmap.createScaledBitmap` 等比缩放到最长边 240（`filter=true` 高质量）。
4. 判断 `bitmap.hasAlpha()`：
   - 有透明 → 编码为 **WebP**（支持 alpha、体积小）
   - 无透明 → 编码为 **JPEG**（兼容性最好）
5. 质量循环压缩：quality 从 90 起，每次 -15，直到体积 ≤500KB 或到达 30 下限。240×240 的图几乎总在第一轮就达标。

## 动图处理（难点：Android 原生无法重编码 GIF）

Android（尤其 minSdk 23）没有 GIF 重编码 API，只能「解码 + 缩帧 + 重新编码」：

- **解码**：引入 `pl.droidsonroids.gif:android-gif-drawable:1.2.29`（社区最成熟，AAR 自带各 ABI 的 so，开箱即用）。
  - `GifDrawable(file)` 构造，`intrinsicWidth/Height` 取尺寸，`numberOfFrames` 取帧数，`seekToFrame(i)` + `currentFrame` 取帧 Bitmap，`getFrameDuration(i)` 取帧延迟（ms）。
- **编码**：自实现 Kevin Weiner 的公开领域 GIF 编码器（纯 Java，零额外依赖）：
  - `NeuQuant` —— 神经网络颜色量化（RGB → 256 色调色板），注意输入是 **BGR 字节序**、调色板输出时再换回 RGB。
  - `LZWEncoder` —— LZW 压缩，注意 `clearFlg` 分支要先重置 `nBits` 再算 `maxcode`。
  - `AnimatedGifEncoder` —— 帧延迟单位是 1/100 秒（`setDelay(ms)` 内部 `ms/10`）；`setRepeat(0)` 无限循环。

### 体积达标策略（超 1MB 时逐级降级）

1. 全帧 + `sample=10` 标准量化
2. 降帧率（每 2 帧取 1）
3. 降帧率 + 降色（`sample=30` 增大量化采样间隔）

### 帧数/内存保护

- `MAX_GIF_FRAMES=60`：超过 60 帧均匀抽帧，避免耗时与内存爆炸。
- 每帧缩放后独立 `Bitmap`，编码完统一 `recycle()`。

### 透明背景处理

表情包 GIF 常见透明底。重编码时若不做处理，透明像素会被量化成某种实色，背景变丑。方案：提取像素时把 `alpha < 128` 的像素标记，量化后统一映射到**调色板索引 0**，并把 0 设为 transparent index（`hasTransparent → transIndex=0`，GCE 里写 transparency flag）。

## 坑与教训

### 1. 新增依赖后 WSL 构建永久卡死（aboutlibraries 联网）

新增 `android-gif-drawable` 后，构建卡在 `:app:prepareLibraryDefinitionsDebug`，CPU 100% idle、日志长时间无进展。根因：`com.mikepenz.aboutlibraries` 插件在新依赖的 SPDX license 定义缓存未命中时，通过 `URL.openStream()` 联网下载（SSL read），该连接**没有 socket 超时**，网络不通时永久阻塞（不是失败，是挂起）。即使配置 `fetchRemoteLicense=false` 也拦不住 SPDX license 元数据下载。

排查：`jcmd <gradle-daemon-pid> Thread.print` / `jstack` 线程转储，卡住线程栈显示 `LicenseUtil.loadSpdxLicense → URL.openStream → SocketDispatcher.read0`。

修复：给 gradle 加 JVM 系统属性 `-Dsun.net.client.defaultConnectTimeout=10000 -Dsun.net.client.defaultReadTimeout=15000`，让下载快速失败后 aboutlibraries 跳过该 license（元数据缺失不影响 APK 功能）。已固化进 `build-memeboard.sh` 与 `build-release.sh`。

### 2. 同步脚本需覆盖子目录与 gradle 文件

`sync-memeboard.sh` 原本只 `cp memeboard/*.kt`（顶层），新增的 `gif/` 子目录不会被带上。需补 `mkdir -p + cp gif/*.kt`，并同步 `gradle/libs.versions.toml`、`app/build.gradle.kts`。

### 3. WEBP deprecated warning

`Bitmap.CompressFormat.WEBP` 在 API 30+ 标记 deprecated（推荐 `WEBP_LOSSY`）。功能正常，仅 warning；如需消除，用 `Build.VERSION.SDK_INT` 判断，API 30+ 用 `WEBP_LOSSY`。

## 构建与验证

- 构建链：Windows 源码 → `sync-memeboard.sh` / `build-release.sh` 同步到 WSL `/root/fcitx5-android` → Gradle 构建（需 `danger-full-access` 与 root）。
- 验证：x86_64 debug 编译通过；arm64-v8a release 签名打包通过（`SIGN_KEY_PWD` 从环境变量读，keystore 见 `keystore/README.md`）。
- 真机（小米15，`b68a5ae7`）：`adb install -r` 覆盖安装成功，透明 PNG / 动图 GIF 实机测试通过。

## 可复用要点速查

- GIF 重编码三件套（NeuQuant + LZW + AnimatedGifEncoder）是 public domain 经典实现，可独立复用。
- `android-gif-drawable` 的 `currentFrame` 是内部复用 Bitmap，缩放前必须 `createScaledBitmap` 拷贝。
- 处理放在 `withContext(Dispatchers.IO)`，避免阻塞主线程；失败降级原图，保证发送不中断。
- 临时文件写到原缓存同层（`send_<md5>.<ext>`），FileProvider 的 `cache-path memeboard/` 已覆盖该路径，无需改配置。
