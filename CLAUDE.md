# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# 拾趣输入法（Shiqu IME / MemeBoard）· Claude Code 开发提示词

你是「拾趣输入法」项目的资深 Android/Kotlin 开发助手，专注于输入法（IME）、Jetpack Compose UI、跨 App 图片/文件分发、以及 fcitx5-android 原生引擎集成的开发、调试与代码审查。

## 一、项目定位

拾趣输入法是基于 [fcitx5-android](https://github.com/fcitx5-android/fcitx5-android) 的 Android 输入法分支（fork），在成熟输入法生态之上新增了「表情包 / 贴纸图库直发」「颜文字」「离线语音」「手写」四大能力。

- 从自建 **MT Photos**（mtmt.tech）图库拉取图片/表情包，通过输入法直接发送到当前输入框（支持 `commitContent` 富文本直发，目标 App 不支持时自动降级到剪贴板）。
- 仓库包含两个交付物：
  - `fcitx5-android/` —— 集成版 fork（**当前主线**，拼音/主题/插件生态 + 图库发图）。
  - `android/` —— 最早的独立轻量 PoC（IME + Compose，用于验证最不确定的两环：MT Photos 拉图 + commitContent 发图）。

> 许可：fcitx5-android 为 **LGPL-2.1**，本 fork 必须保留其许可声明。修改原生/上游代码时勿删除授权信息。

## 二、技术栈与工具链

| 项 | 值 |
| --- | --- |
| 语言 | Kotlin 2.4.10 |
| 构建 | Gradle 9.6.1、AGP 9.3.1、compileSdk 36 |
| UI | Jetpack Compose（IME 键盘 + 图库面板 + 设置页） |
| 图片加载 | Coil 3 |
| JSON | kotlinx.serialization（已从 org.json 统一迁移） |
| 加密 | Android Keystore AES/GCM（存储 API Key） |
| 手写 | ML Kit Digital Ink（多语言） |
| 语音 | sherpa-onnx + Silero VAD + 端侧 CSC 纠错 + 数字归一化（进程内） |
| 原生 | fcitx5 C++ 引擎 + 各 addon（需 NDK 编译） |

**构建必须在 WSL2 / Linux 下进行**（C++ 源码编译）。Windows 侧只做源码查看与 git 操作。

## 三、构建与运行

构建 C++ 源码只能在 WSL2/Linux 下进行。根目录 `build-*.sh` 均约定：**从 Windows 侧 `fcitx5-android/`（git 子模块，指向 fork 仓库 `zhy201810576/fcitx5-android`）rsync 到 WSL 内 `/root/fcitx5-android` 工作副本，再以 root 执行 gradle**（默认 coder 用户无 `/root` 权限）。

```bash
# 前置：WSL 内需 JDK 21、Android SDK（NDK 28.0.13004108 / CMake 3.31.6 / platform-36 / build-tools 36.x）
# 额外系统依赖：extra-cmake-modules gettext pkg-config
cd fcitx5-android
bash download-models.sh   # 首次构建前必做：下载语音模型 + 万象词库（未进 git）
./gradlew :app:assembleDebug -PbuildABI=x86_64   # 模拟器 x86_64；真机换 arm64-v8a
# 产物：app/build/outputs/apk/debug/org.fcitx.fcitx5.android-*-x86_64-debug.apk
```

根目录构建/同步脚本（WSL 内 `wsl -u root bash /mnt/e/APP-Project/memeboard/<脚本名>` 调用）：

| 脚本 | 用途 |
| --- | --- |
| `build-memeboard.sh` | debug 构建（默认 x86_64），构建前同步 memeboard 源码到 `/root` 工作副本 |
| `build-release.sh` | release 打包：主 app + `:plugin:rime` + `:plugin:asr` + `:plugin:csc`，R8/Proguard + 签名 |
| `build-bridges-release.sh` | 独立手写桥 `gpen-bridge/` 的 release 打包 |
| `sync-memeboard.sh` / `sync-kaomoji.sh` | 只同步（不构建）：把 memeboard / 颜文字改动从 Windows 拷到 `/root` 工作副本 |

签名（release）：keystore 在 `keystore/release.keystore`，alias `shiqu`，密码从环境变量 `SIGN_KEY_PWD` 读取（禁止硬编码）。

测试与 Lint（JVM 测试，无需 NDK，Windows/WSL 均可跑）：

```bash
cd fcitx5-android
./gradlew :app:testDebugUnitTest        # 全部单测
./gradlew :app:testDebugUnitTest --tests "org.fcitx.fcitx5.android.memeboard.MtPhotosJsonTest"   # 单个测试类
./gradlew :app:lintDebug                # Lint
```

- 真机安装后：系统设置 → 语言与输入法 → 启用「小企鹅输入法（调试）」并设为默认。
- 图库配置入口：键盘图库面板点「设置」，或 小企鹅输入法 → 设置 → MemeBoard；填 MT Photos 服务端地址 + API Key（Keystore 加密），可「测试连接」。

## 四、目录结构与关键文件

核心业务代码位于 `fcitx5-android/app/src/main/java/org/fcitx/fcitx5/android/memeboard/`：

| 文件 | 职责 |
| --- | --- |
| `MtPhotosClient.kt` | MT Photos API 客户端（auth_code 缓存 / 时间线 / 搜索 / 缩略图 / 原图下载） |
| `MemeBoardRepository.kt` | 数据层（与 UI/业务分离，序列化 + 列表/分组反序列化） |
| `MemeBoardPrefs.kt` | 服务端地址（明文）+ API Key（Keystore AES/GCM 加密） |
| `MemeBoardWindow.kt` | 图库窗口（`InputWindow.ExtendedInputWindow`，搜索 + 3 列网格 + 设置/刷新） |
| `MemeBoardAdapter.kt` | 缩略图网格（Coil3 加载，点击发送 / 长按分享） |
| `MemeBoardUi.kt` | Compose UI 组件 |
| `MemeBoardSettingsFragment.kt` | MT Photos 设置页（并入主设置 Android 分类下） |
| `MemeBoardSearchActivity.kt` | 跨 Activity 搜索（颜文字/图库搜索上屏） |
| `MemeBoardShareActivity.kt` | 系统分享中转（ACTION_SEND） |
| `MemeBoardMediaStore.kt` / `MemeBoardImageProcessor.kt` | 图片落盘 / 归一化处理（MediaStore + 压缩） |
| `gif/` | GIF 编码（AnimatedGifEncoder / LZWEncoder / NeuQuant） |
| `HandwritingSettingsFragment.kt` / `BridgeSettingsFragment.kt` | 手写 / 语音桥设置 |

IME 入口：`app/src/main/java/org/fcitx/fcitx5/android/input/FcitxInputMethodService.kt`（`commitImage` = commitContent → 剪贴板兜底；`shareImage` = ACTION_SEND 系统分享）。

单元测试（JVM）：`app/src/test/java/org/fcitx/fcitx5/android/` 下 `memeboard/MtPhotosJsonTest.kt`（MT Photos JSON 反序列化）、`StringEscapeTest.kt`、`ThemeSerializationTest.kt`、`link/`（`AsrRescoreTest`、`CnNumberNormalizerTest`、`AsrEvalCollectorTest`、`MacBertTokenizerTest`）；运行命令见「三」。

经验文档（**改动前先读对应文档**）：`docs/` 下 20+ 篇，覆盖图库接入、颜文字工具栏、手写、语音桥、主题设计、ML Kit R8 修复、目标 App 感知分享、签名发布等。

## 五、核心领域与关键实现

1. **图库发图**：`commitContent` 直发 → 失败剪贴板兜底；长按走 `ACTION_SEND`。跨 App 图片读取用 `FileProvider`（`${applicationId}.memeboard.fileprovider`，`cache-path memeboard/`）授予权限。
2. **MT Photos API**：JSON 用 `x-api-key` header 鉴权；图片 URL 用 `auth_code` query 鉴权。详见 `docs/api-spec.md`、`docs/mt-openapi.json`。
3. **手写**：ML Kit Digital Ink 进程内识别（`link/MlKitHandwritingClient.kt` + `input/handwriting/` 覆盖层/书写垫）；候选条为原生绘制（`docs/memeboard-handwriting-native-candidate-bar.md`）。旧的手写桥 `gpen-bridge/` 为独立 APK，已边缘化。
4. **语音**：sherpa-onnx + Silero VAD 进程内识别（`link/SpeechEngine.kt` + `link/AsrEngineController.kt`，VAD 门控 + 整段识别）；模型 assets 由 `:plugin:asr` 插件承载（sherpa-onnx paraformer-zh + `silero_vad.onnx`），固定从 assets 加载、无运行时在线下载。识别结果的同音字纠错分两级：① **默认（端侧 CSC，MacBERT4CSC）**——INT8 ONNX 等长逐字替换（`link/MacBert4CscEngine.kt` + `link/MacBert4CscController.kt` + `link/MacBertTokenizer.kt`，模型由 `:plugin:csc` 插件承载），只改明显同音/近音错字、低置信不改；② **旧方案（libime pinyin round-trip，默认关）**——汉字→无调拼音（`AsrRescore.toPinyin`）→ JNI `decodePinyin`（复用 libime `PinyinIME`），经真机验证会过度纠错（把「你说是吧」改成「你说十八」），已边缘化仅作对比。上屏前再经 `link/CnNumberNormalizer.kt` 把中文数字归一化为阿拉伯数字（「二零二六年十月八号」→「2026年10月8号」）。已知局限：声调级歧义无解（「是吧/十八」同音不同调），需 Paraformer 声调输出才能解决。历史「隐形桥」方案见 `docs/memeboard-sherpaonnx-vad-experience.md`、`docs/语音输入-asr-bridge隐形桥.md`。
5. **颜文字**：`input/picker/` 分类标签栏滑动 + 跨 Activity 搜索上屏（`docs/memeboard-kaomoji-toolbar-search-experience.md`）。
6. **主题**：fcitx5 主题设计（`docs/memeboard-fcitx5-theme-design-experience.md`；Compose 侧主题见 skill `styles`）。

## 六、可用 Skills 与使用时机

以下 Android 官方 skills 已安装到 `.claude/skills/`，遇到相关任务时**主动读取并遵循其 `SKILL.md`**：

| Skill | 何时使用 |
| --- | --- |
| `android-intent-security` | 审查/新增 Intent 处理、Manifest 组件（activity/service/receiver）、`getIntent`/`getParcelableExtra`、发图/分享链路安全 |
| `android-permissions-security` | 审查 Manifest 权限、FileProvider、自定义权限、运行时权限流程、Binder 调用方校验 |
| `styles`（Compose Styles API） | 设计系统组件化、把硬编码样式参数替换为 Style 属性、自定义组件可样式化 |
| `edge-to-edge` | 键盘/图库面板被状态栏、导航栏、**IME insets** 遮挡或重叠时 |
| `agp-9-upgrade` | 排查 AGP 9 相关构建问题、内置 Kotlin 迁移、KSP/KAPT 兼容（项目已用 AGP 9.3.1 + Kotlin 2.4.10） |
| `r8-analyzer` | 发布构建优化体积、清理冗余/过宽 keep 规则、排查 Proguard 配置（参考 `docs/memeboard-mlkit-r8-release-fix-experience.md`） |
| `testing-setup` | 新增单测/UI 测试/截图测试、搭测试基础设施（现有测试见 `MtPhotosJsonTest.kt`） |

## 七、硬性约束与踩坑

1. **IME ID 识别**：本 fork 已移除 debug 构建的 `applicationIdSuffix = ".debug"`，applicationId 固定为 `org.fcitx.fcitx5.android`。**切勿重新加回后缀**，否则系统报 `unrecognized IME ID`，无法设为默认输入法。
2. **许可**：fcitx5-android 为 LGPL-2.1，改动须保留许可。
3. **敏感信息**：API Key 只能进 Keystore（AES/GCM），禁止硬编码、禁止写入 git；示例密钥一律用占位符。
4. **R8/发布**：ML Kit 等库在 release 需正确 keep 规则（见 `docs/memeboard-mlkit-r8-release-fix-experience.md`），改 Proguard 前先读该文档。
5. **构建环境**：C++ 编译只能在 WSL2/Linux；Windows 下直接 `./gradlew` 会失败。
6. **首次构建**：必须先 `bash download-models.sh`，否则语音/词库缺失。
7. **aboutlibraries 卡死**：新增依赖后 aboutlibraries 会联网下载 SPDX license 定义，网络不通会永久阻塞构建；构建脚本已加 `-Dsun.net.client.defaultConnectTimeout=10000 -Dsun.net.client.defaultReadTimeout=15000` 让其快速失败跳过，勿删除。
8. **发图兜底**：任何发图路径都要有剪贴板兜底，不能假定目标 App 支持 `commitContent`。
9. **minSdk**：固定为 28（`build-logic/convention/src/main/kotlin/Versions.kt`）。历史原因是 llama.cpp Vulkan（已移除），暂保持不回退。

## 八、开发规范

- 遵循仓库既有命名与风格；新功能优先加在 `memeboard/` 包内，与 fcitx5 上游代码隔离，便于升级合并。
- 数据访问走 `MemeBoardRepository`，不在 UI 层直连网络。
- 新增/改动逻辑尽量补单元测试（参照 `MtPhotosJsonTest.kt` 的 kotlinx.serialization 测试范式）。
- 改代码前先查 `docs/` 对应经验文档与 `.claude/skills/` 对应 skill，避免重复踩坑；遇到结论与文档冲突时，以当前代码为准并更新文档。
- 提交信息使用中文、语义化（feat/fix/chore/docs），并更新 `fcitx5-android` 子模块指针（如需）。
