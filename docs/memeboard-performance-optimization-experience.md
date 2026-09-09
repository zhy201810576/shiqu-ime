# MemeBoard 图库面板性能优化与 Coil3 集成经验

> 主题：fcitx5-android（MemeBoard）图库面板的 P0/P1/P2 性能优化落地，以及 Coil 3.2.0 集成踩坑、DSH 沙箱下 WSL 构建链的坑。
> 背景：MemeBoard 是 fcitx5-android fork，从自建 MT Photos 拉取表情包/图片直发聊天 App。核心功能闭环后，本轮做性能与健壮性升级。

## 一、Coil 3.2.0 集成 API 细节（最容易踩的坑）

Coil 3 的 API 与 Coil 2 差异很大，很多"看起来像 class 的"其实是顶层函数或成员函数。以下结论均从 `.wsl/coilcore`、`.wsl/coilnet` 源码逐一核对（Coil 3.2.0）：

1. **`OkHttpNetworkFetcherFactory` 是顶层函数，不是 class**（`@JvmName("factory")`）。它有一组重载：
   - `OkHttpNetworkFetcherFactory()` 无参
   - `OkHttpNetworkFetcherFactory(callFactory: Call.Factory)` —— 传 **OkHttpClient 实例**
   - `OkHttpNetworkFetcherFactory(callFactory: () -> Call.Factory, cacheStrategy, connectivityChecker)` —— 传 lambda
   - **没有 `Lazy<Call.Factory>` 重载**。想复用自定义 OkHttpClient 就传实例：`OkHttpNetworkFetcherFactory(callFactory = MtPhotosClient.httpClient)`。传 `lazy { ... }` 会编译失败。

2. **Coil 3 默认无磁盘缓存**。必须显式配置 `DiskCache`：
   ```kotlin
   ImageLoader.Builder(context)
       .components { add(OkHttpNetworkFetcherFactory(callFactory = myOkHttp)) }
       .diskCache {
           DiskCache.Builder()
               .directory(cacheDir.resolve("images").toOkioPath())  // 或 File 版扩展
               .maxSizeBytes(100L * 1024 * 1024)
               .build()
       }
       .build()
   ```
   `DiskCache.Builder.directory(Path)` 是成员方法；另有 `coil3.disk.directory(File)` 顶层扩展（jvmCommonMain）。`toOkioPath()` 来自 `okio.Path.Companion.toOkioPath`。

3. **`listener` 是 `ImageRequest.Builder` 的成员函数，不是顶层扩展**。在 `load(url, loader) { ... }` 的 builder lambda 里直接调用 `listener(onError = { _, _ -> ... })`，**不要** `import coil3.request.listener`（会 unresolved reference）。

4. **Coil 的 OkHttpNetworkFetcherFactory 默认自己 new OkHttpClient**，不会用你的全局单例。要让自定义拦截器（如 auth_code 过期自愈）对图片请求生效，必须把 callFactory 显式传进去。

5. **`decodeToSequence` 需要 `@OptIn(ExperimentalSerializationApi::class)`**（流式解析大 JSON 时），否则编译 warning。

## 二、图库面板性能优化方案（P0/P1/P2）

### P0 · 性能硬伤（真机肉感最明显）

1. **auth_code 缓存失效**：`MtPhotosClient` 每次 `new` 导致实例级 `cachedAuthCode` 永远命中不了。解法——把 auth_code 缓存提升为 **companion object 级**（`@Volatile` + `synchronized` 双重检查 + 按 `server\u0000apiKey` 做 cacheKey），跨实例共享，20h 缓存真正生效。
2. **OkHttpClient 频繁重建**：每次 `new MtPhotosClient` 都 new 连接池/线程池。解法——OkHttpClient 提升为 companion 单例（`by lazy`）。
3. **缩略图无磁盘缓存**：加 Coil `DiskCache`（见上文）。
4. **相册串行加载**：`albumIds.forEach { sync + albumFiles }` 是 2N 次串行请求。解法——`coroutineScope { albumIds.map { async { ... } }.awaitAll().flatten() }` 并发，单个相册失败 `runCatching` 降级为空不影响整体。
5. **发送重复下载**：`downloadPreview` 改为 md5 内容寻址缓存命中（`listFiles { it.name.startsWith("$md5.") }` 命中即复用）。

### P1 · 健壮性

1. **auth_code 过期自愈**：OkHttpClient 加 interceptor，图片 URL 返回 401/403 时清空 auth_code 缓存；adapter 图片加载失败回调 + Window 侧 30s 节流自动重载换新 code。
2. **loading + 竞态取消**：统一 `launchLoad` 入口，`loadJob?.cancel()` 取消旧任务，`ViewAnimator` 增加 loading 子视图。
3. **错误分类**：`IOException` → 网络提示；`HTTP 401/403` → 鉴权提示；其他 → 通用提示。

### P2 · 最近使用 + 收藏

- 收藏/最近使用用 `kotlinx.serialization` 把 `List<MtFile>` 序列化为 JSON 存 SharedPreferences；md5 作为内容指纹去重。
- 最近使用 `touchRecent`：去重 + 插头部 + 限量 50。
- UI：标签栏最前固定「收藏」「最近」两个 chip；长按图片弹操作菜单（发送/分享/收藏↔取消）。

## 三、DSH 沙箱 + WSL 构建链的坑

1. **DSH 沙箱会拦截外部程序**：`wsl.exe`/`cmd.exe` 报 `E_ACCESSDENIED`（Wsl/Service/CreateInstance）或 `file access denied under workspace-write mode`，表象像"WSL 服务挂了/权限不足"，实际是**沙箱拦截**。解法——shell 工具带 `sandbox_permissions: "danger-full-access"` + justification 升级重试（会触发审批）。

2. **WSL 默认用户非 root**：`ls /root` 报 Permission denied，导致误判 `/root/fcitx5-android` 目录不存在。解法——`wsl.exe -d Ubuntu-22.04 -u root bash -lc '...'` 显式 `-u root`。

3. **PowerShell 调用 wsl.exe 的编码坑**：
   - `2>&1` 可能触发 `StandardErrorEncoding is only supported when standard error is redirected`；
   - bash 命令里的 `2>/dev/null` 会被 PowerShell 误解析成路径（`E:\dev\null`）。
   - 解法——bash 命令用**单引号**整体包裹，避免 PowerShell 转义；外层不要叠 `2>&1`。

4. **编译验证策略**：先 `:app:compileDebugKotlin` 快速验证 Kotlin（约 1 分钟），通过后再 `:app:assembleDebug` 跑 C++ 全量（本项目增量约 1 分钟）。

5. **copy-files.sh 增量同步**：构建目录在 WSL 的 `/root/fcitx5-android`（完整 clone），Windows 改动通过 `copy-files.sh` 按文件清单 cp/rsync 同步过去，改完一个文件只 cp 那一个即可快速迭代。

## 可复用要点

1. Coil 3 的 `OkHttpNetworkFetcherFactory` 是顶层函数、`callFactory` 传 `Call.Factory` 实例、`listener` 是成员函数——查源码比猜 API 快。
2. 实例级缓存若对象频繁 new 就形同虚设，跨实例共享要提升到 companion（带 cacheKey + 双重检查锁）。
3. 网络重资源（OkHttpClient/ImageLoader/DiskCache）必须单例化 + 显式磁盘缓存。
4. DSH 沙箱拦截外部程序时，用 `danger-full-access` 升级重试，别误判成环境故障。
5. WSL 构建永远 `-u root`；bash 命令单引号包裹规避 PowerShell 转义。
