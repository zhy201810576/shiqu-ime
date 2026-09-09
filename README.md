# 拾趣输入法 · Shiqu IME

> **拾取趣味，一触即发。** 基于 fcitx5-android 的 Android 输入法，内置表情包 / 贴纸图库直发、颜文字、离线语音与手写输入。

一个 Android 输入法项目：从自建的 **MT Photos**（mtmt.tech）图库拉取图片/表情包，通过输入法直接发送到当前输入框（支持富文本直发，不支持时自动降级到剪贴板）。

本仓库现在包含两个交付物：

1. **fcitx5-android 集成版（fork）** —— `fcitx5-android/`，把 MemeBoard 图库面板并进成熟输入法生态（拼音/主题/插件生态 + 图库发图）。⭐ 当前主线
2. **独立轻量 PoC** —— `android/`，最早的验证 Demo（IME + Compose）。

## fcitx5-android 集成版（fork）

> 在官方 fcitx5-android 基础上新增「MemeBoard 图库面板」，点工具栏 🖼 图标即可从 MT Photos 拉图并发送。

### 集成内容

- 键盘工具条新增 **🖼 图库按钮**（`ic_memeboard`），位于剪贴板与更多之间。
- 新增 `memeboard/` 包：
  - `MtPhotosClient.kt` —— MT Photos API 客户端（auth_code 20h 缓存 / 时间线 / 搜索 / 缩略图 / 原图下载）。
  - `MemeBoardPrefs.kt` —— 服务端地址（明文）+ API Key（Keystore AES/GCM 加密）。
  - `MemeBoardWindow.kt` —— 图库窗口（`InputWindow.ExtendedInputWindow`，搜索 + 3 列缩略图网格 + 设置/刷新）。
  - `MemeBoardAdapter.kt` —— 缩略图网格（Coil3 加载，点击发送 / 长按分享）。
  - `MemeBoardSettingsFragment.kt` —— MT Photos 接口设置页（服务端地址 / API Key / 状态 / 测试连接），已并入小企鹅输入法主设置列表（Android 分类下）。
- `FcitxInputMethodService` 新增 `commitImage`（commitContent → 剪贴板兜底）与 `shareImage`（ACTION_SEND 系统分享）。
- 新增 `FileProvider`（`${applicationId}.memeboard.fileprovider`，`cache-path memeboard/`）用于跨 App 授予图片读取权限。

### 构建（WSL2，Linux 构建链）

fcitx5-android 是 C++ 源码编译项目，需在 Linux/WSL2 构建：

```bash
# WSL 内需：JDK 21、Android SDK（NDK 28.0.13004108 / CMake 3.31.6 / platform-36 / build-tools 36.x）
# 额外系统依赖：extra-cmake-modules gettext pkg-config
cd fcitx5-android
bash download-models.sh   # 首次构建前先下载语音模型 + 万象词库（约 600MB，未进 git）
./gradlew :app:assembleDebug -PbuildABI=x86_64   # 模拟器 x86_64；真机换 arm64-v8a
# 产物：app/build/outputs/apk/debug/org.fcitx.fcitx5.android-*-x86_64-debug.apk
```

> 版本：Gradle 9.6.1、AGP 9.3.1、Kotlin 2.4.10、compileSdk 36。
> 注意：本 fork 已移除 debug 构建的 `applicationIdSuffix = ".debug"`，applicationId 固定为 `org.fcitx.fcitx5.android`——否则系统对 IME 组件报 `unrecognized IME ID`，导致无法在系统 UI 中设为默认输入法。
> 许可：fcitx5-android 为 LGPL-2.1，fork 需保留其许可。

### 使用步骤（集成版）

1. 安装 APK，系统设置启用「小企鹅输入法（调试）」并设为默认。
2. 任意输入框唤出键盘 → 展开工具条 → 点 🖼 打开 MemeBoard 图库。
3. 配置入口有二：键盘图库面板点「设置」，或打开小企鹅输入法 → 设置 → MemeBoard；填写 MT Photos 服务端地址 + API Key（Keystore 加密存储），可点「测试连接」验证。
4. 搜索/刷新拉图，点击发送，长按走系统分享。

### 验证状态（集成版）

- [x] fork 在 WSL2 全量构建成功（fcitx5 原生引擎 5.1.22 + 全部 addon 编译通过）
- [x] APK 安装、IME 启用并绑定输入框（logcat 确认 onBindInput/onStartInput 无崩溃）
- [x] 键盘工具条出现 🖼 MemeBoard 按钮（视觉确认）
- [x] 点 🖼 打开图库面板（标题/搜索框/设置/刷新/未配置提示齐全）
- [x] 主设置列表出现 MemeBoard 入口，设置页正确渲染（状态 / 服务器地址 / API Key / 测试连接）
- [x] 服务器地址输入框带 URL 提示、API Key 输入框密码遮挡（视觉确认）
- [x] 键盘图库面板的「设置」按钮改为跳转到同一设置页
- [ ] MT Photos 实际拉图与发图（需你的服务端地址 + API Key，机制与 PoC 完全一致）

## 背景与结论

调研结论见 [docs/breakthrough-analysis.md](docs/breakthrough-analysis.md)：

- fcitx5-android 的「插件系统」只能加载 C++ 输入引擎 / 后台 Service / 处理剪贴板文本，**没有 UI 扩展点，也没有发图 IPC 通道**，不是突破口。
- 可行路线是 fork 后在 App 内加图库面板；本仓库先做**独立轻量输入法 PoC** 验证最不确定的两环（MT Photos 拉图 + commitContent 发图），随后按计划 **fork fcitx5-android 集成**。

## 已实现

- **MT Photos API 客户端**（`data/MtPhotosClient.kt`）：`api_key → auth_code`（24h 缓存）、图库列表、最近文件/时间线/搜索、缩略图 URL、原图下载。
- **输入法服务**（`MemeBoardImeService.kt`）：IME + Compose 键盘；完整实现了 Compose 在 IME 里需要的三个 owner（Lifecycle / ViewModelStore / SavedStateRegistry，挂到 `window.decorView`），并正确处理 SavedStateRegistry 的 performAttach/performRestore 顺序。
- **图库面板**（`ui/StickerPanel.kt`）：搜索框 + 缩略图网格（Coil 加载）+ 点击发送 / 长按分享。
- **发送（三种路径）**：点击 = `commitContent` 直发，失败自动剪贴板兜底并收起键盘；长按 = `ACTION_SEND` 系统分享面板选微信/QQ 好友直发。
- **配置界面**（`ConfigActivity.kt`）：服务端地址 / API Key / 图库 ID，API Key 用 Android Keystore AES/GCM 加密存储（`data/Prefs.kt`），含测试连接与崩溃日志复制。
- **稳定性**：`CrashHandler` 全局崩溃捕获（写 `files/crash.log`）；`onEvaluateFullscreenMode=false` 禁用全屏提取模式；键盘固定 300dp 非全屏。

## 关键 API（MT Photos）

| 用途 | 端点 |
| --- | --- |
| 换取 auth_code（24h） | `POST /auth/auth_code` body `{"api_key":"sk_live_..."}` |
| 图库列表 | `GET /gateway/myGalleryList` |
| 最近文件 | `GET /gateway/recentFiles?galleryIds=...` |
| 全部文件 | `GET /gateway/filesInTimelineV2` |
| 搜索 | `POST /gateway/search` body `{"key":"..."}` |
| 缩略图 | `GET /gateway/h220/{md5}?auth_code=...` |
| 原图 | `GET /gateway/file/{id}/{md5}?type=ori&auth_code=...` |

JSON API 用 `x-api-key` header 鉴权；图片 URL 用 `auth_code` query 鉴权。完整接口见 [docs/api-spec.md](docs/api-spec.md)。

## 构建

工具链：JDK 17+、Android SDK（compileSdk 36）、Gradle 9.3.1、AGP 8.13.2、Kotlin 2.4.10。

```bash
cd android
# 设置 ANDROID_HOME 或确保 local.properties 里 sdk.dir 正确
./gradlew assembleDebug
# 产物：app/build/outputs/apk/debug/app-debug.apk
```

## 使用步骤

1. 安装 APK，打开「MemeBoard IME」进入配置界面。
2. 填写 MT Photos 服务端地址（如 `http://192.168.1.10:8063`）、API Key、图库 ID（可选），点「测试连接」。
3. 系统设置 → 语言与输入法 → 启用 MemeBoard IME 并设为默认。
4. 在任意输入框切换到本输入法，点「图库」选图发送。

## 验证状态

- [x] debug APK 构建、安装成功
- [x] IME 被系统识别并设为默认（`ime list -a` 正确）
- [x] 配置界面完整渲染，配置可保存、可测试连接
- [x] IME + Compose 集成无崩溃（键盘固定 300dp、非全屏、无闪退）
- [x] MT Photos 拉图 + 图库面板 + 点击发送 / 长按系统分享（真机验证通过）

## 已知修复（本 fork）

1. **移除 debug 的 `applicationIdSuffix=".debug"`**：否则 IME 组件名变成长格式（类包 `org.fcitx.fcitx5.android` ≠ 应用包 `org.fcitx.fcitx5.android.debug`），系统 `setInputMethod` 报 `unrecognized IME ID`，表现为「选择默认输入法窗口选不了」。
2. **禁用动态 subtype 同步**（`core/Fcitx.kt` 的 `SubtypeManager.syncWith`）：部分定制 ROM 对 `setAdditionalInputMethodSubtypes`/`setExplicitlyEnabledInputMethodSubtypes` 处理异常，会回滚 `enabled_input_methods`（选完默认又被踢出）。fcitx5 打字不依赖系统 subtype，已禁用并加注释说明。
3. **`switchInputMethod` 加 try-catch**（`input/FcitxInputMethodService.kt`）：subtype 切换失败不再让 IME 进程崩溃。
4. **移除 `input_method.xml` 的静态 `<subtype>`**：让 fcitx5 与内置输入法一致使用「隐式 subtype（-1）」，避免无 `subtypeId` 的静态 subtype 在部分 ROM 上引起 subtype 匹配异常。
5. **移除 IME service 的 `directBootAware`**：让 fcitx5 在用户解锁后才启动（`isDirectBootMode=false`），不再参与锁屏阶段的 direct-boot 生命周期切换。
6. **关闭 `supportsSwitchingToNextInputMethod`**：保守设置，规避部分 ROM 对「可循环切换 IME」在开机解锁时的特殊回退处理。真机如需要语言切换键可恢复为 `true`。
7. **补充 `android.permission.INTERNET`**：fcitx5-android 官方清单不含网络权限，而 MemeBoard 的 OkHttp/Coil 拉图与「测试连接」需要联网；缺失时请求抛 `SecurityException: Permission denied (missing INTERNET permission?)`。已加入 manifest 并实测「测试连接」成功。

## 模拟器「重启后无法设为默认」说明

在 ASUS 定制模拟器镜像上有一个**系统级限制**（非 APP 问题）：

- 重启并**解锁后**（`onUnlockedUser`），系统会在 fcitx5 引擎 ready 之前就把它停掉并切回内置「雷电输入法」，导致 `default_input_method` 回退、fcitx5 引导页再次弹出。
- 系统「选择输入法」对话框点选 fcitx5 时，只切换当前输入法、**不写入默认设置**，因此选完重启又失效。

**workaround（解锁后执行一次即可，本次会话内一直有效）**：

```bash
adb shell settings put secure default_input_method "org.fcitx.fcitx5.android/.input.FcitxInputMethodService"
```

真机（标准 ROM）不会出现这两个问题。

## 后续方向

fork fcitx5-android 集成已完成主线目标，剩余：

1. **真机联调**：用你的 MT Photos 服务端地址 + API Key 在集成版上实测拉图/发图（机制与 PoC 一致，尚未实机跑）。
2. **生产化**：auth_code 自动刷新、缩略图/原图磁盘缓存、图库分页、发送兼容白名单。
3. **生态深化**：相册/收藏/标签浏览、最近使用置顶、跟随 fcitx5 主题配色。
4. **上游跟进**：fork 需持续跟进 fcitx5-android 上游更新（LGPL-2.1）。

## 许可与第三方声明

本仓库是 fcitx5-android 的 fork，继承其 **LGPL-2.1** 许可，源码随本仓库提供；MemeBoard 新增代码同样按 LGPL-2.1 发布。

集成的第三方引擎 / 模型及其授权边界（开源发布前需留意）：

| 组件 | 来源 | 许可 | 说明 |
| --- | --- | --- | --- |
| fcitx5-android | 上游 fork | LGPL-2.1 | 输入法框架本体 |
| 万象拼音方案 | rime-wanxiang | CC BY 4.0（需署名） | 拼音词库 + 语言模型 |
| 语燕手写（gpen） | 语燕输入法 | BSD-3 外壳，**内含讯飞 `libgpen_handwriter.so` + 搜狗中文模型（专有，仅 arm64-v8a）** | 手写识别；闭源 so 需单独说明来源与授权边界，不得随 LGPL 源码无声明再分发 |
| 语音（asr-bridge） | sherpa-onnx + SenseVoice | 见各模型自身许可 | 离线语音识别 |
| BiBi「说点啥」 | 第三方独立 APP | Apache 2.0（AIDL 协议） | 语音桥接，非本仓库内置 |

> 专有组件（讯飞 gpen so、搜狗模型）不属于 LGPL 范围，对外分发时需在分发物中明确其来源与授权边界；本仓库默认**不内置**这些专有二进制，仅保留调用外壳与集成说明。
