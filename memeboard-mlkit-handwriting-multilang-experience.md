# MemeBoard（拾趣输入法）手写输入：ML Kit 中日双语手写 + 弃用 gpen 桥

## 背景与决策动机

拾趣输入法（fcitx5-android fork）原手写方案是 **gpen 桥接 APK**（搜狗手写 SDK），存在一串历史包袱：

- **闭源**：搜狗手写 SDK 非开源；
- **包名绑定**：`libhandwriting.so` 硬编码 4 个授权包名（`com.yuyan.pinyin.*`）；
- **服务器计数授权**：RSA/PKCS7 验签 + SogouAuth 服务器计数；
- **arm64-only**：无 x86/x86_64，模拟器需 ARM 翻译层。

同时新增「日语手写」需求：搜狗中文手写对日文异体字（気/円/図/読/語/様）识别存疑。经调研与实测，改用 **Google ML Kit Digital Ink Recognition**，一个引擎统一中日双语手写，彻底取代 gpen 桥。

## 结论先行

- ML Kit Digital Ink Recognition 支持 300+ 语言 / 25+ 书写系统，**中文（`zh-Hani-CN`）与日语（`ja`）手写识别率均高**，候选符合预期（真机 + 模拟器双重确认）。
- 手写识别并入主 app，**gpen-bridge 插件包不再需要安装**，安装形态从 4 包（主 app + rime + gpen-bridge + asr-bridge）降为 3 包。
- 识别 100% 设备端、笔迹不出设备；但模型走 GMS 运行时按需下载，**首次需联网 + 设备具备 GMS**，无 GMS 的纯国产 ROM / 非 Google Play 模拟器镜像不可用。

## 关键认知（本方案最大的坑）

### 1. 包名带 `.recognition` 后缀

ML Kit `digital-ink-recognition:19.0.0` 的公共 API 实际包名是：

```
com.google.mlkit.vision.digitalink.recognition.*   ← Ink / DigitalInkRecognition / DigitalInkRecognizer 等
com.google.mlkit.vision.digitalink.common.*        ← RecognitionResult / RecognitionCandidate
```

**不是**文档代码片段里常见的 `com.google.mlkit.vision.digitalink.*`（少了 `.recognition`）。官方文档的示例省略了 import，容易踩坑。首次编译报 20+ 个 `Unresolved reference`。

### 2. 语言码

- 日语：**`ja`**（不是 `ja-JP`）
- 中文简体：**`zh-Hani-CN`**（不是 `zh-CN`）

`fromLanguageTag` 对错误码会返回 null 或抛 `MlKitException`，需判空处理。

### 3. 模型机制（GMS 门槛）

- 依赖：`com.google.mlkit:digital-ink-recognition:19.0.0`（unbundled，无 bundle 变体）。
- 模型由 `RemoteModelManager` 运行时走 Google Play Services 下载，**每语言约 20MB**；识别离线，但首次下载必须联网 + GMS。
- SDK 是 Apache-2.0，但模型是 Google 专有、运行时下载，不随源码分发——对「开源」只影响分发层，不影响自用。

### 4. 确认真实包名/签名的方法

用 `javap` 反编译 aar 的 `classes.jar`，比猜包名可靠：

```bash
unzip -o digital-ink-recognition-19.0.0.aar classes.jar -d /tmp/x
javap -cp /tmp/x/classes.jar com.google.mlkit.vision.digitalink.recognition.Ink
# 确认：Ink.builder() / Ink.Stroke.builder() / Ink.Point.create(float,float,long)
```

## 集成实现

### 架构

- **`MlKitHandwritingClient`**（object，单例）：`Language` 枚举（`CHINESE("zh-Hani-CN")` / `JAPANESE("ja")`）+ `ConcurrentHashMap<String, DigitalInkRecognizer>` 缓存双模型，切换语言秒就绪（已下载过的模型不复下）。
- **笔迹数据复用**：现有手写板 `HandwritingPadView` 的 `x,y` 成对 + `-1,0` 分笔编码直接复用；`buildInk()` 按分隔符拆成 `Ink.Stroke`，时间戳用递增值表达笔画顺序（原始数据无时间戳，对单字识别影响小）。
- **候选注入复用**：识别结果 `List<String>` 走现有 `KawaiiBarComponent.showExternalCandidates` → fcitx5 原生候选栏，与拼音候选同位置同样式，点选上屏零改动复用。

### 语言切换

- 存储：`MemeBoardPrefs.handwriting_language`（`"zh"` / `"ja"`，默认 `"zh"`）。
- UI：手写设置页 `ListPreference`（中文/日文）。
- 读取：`HandwritingOverlayView` 进板时 `when(getHandwritingLanguage()) { "ja" -> JAPANESE; else -> CHINESE }`，`prepare(language)` + `recognize(language, points)`。

## gpen 清理清单

| 动作 | 对象 |
|---|---|
| 删除 | `link/GpenHandwritingClient.kt` |
| 删除 | `aidl/com/yuyan/handwriting/aidl/IHandwritingService.aidl` |
| 删条目 | `BridgeSettingsFragment` 的 `BridgeInfo(R.string.bridge_gpen, ...)`（只留 asr） |
| 删 target | `BridgePrewarmer` 的 gpen `Target(...)`（只留 asr） |
| 删声明 | `AndroidManifest.xml` `<queries>` 里 `com.yuyan.pinyin.offline.release` 包可见性 |
| 改注释 | `app/build.gradle.kts` 的 AIDL 注释（`aidl = true` 保留，asr 仍用 AIDL） |
| 改注释 | `FcitxInputMethodService` 预热注释（gpen/asr → 仅 asr） |

**asr 语音桥完整保留**（`com.memeboard.asrbridge` 的 AIDL、预热、管理页均不受影响）。

## 验证过程

模拟器（emulator-5554，Google Play 镜像含 GMS，`x86_64,arm64-v8a` + `libndk_translation`）：

1. arm64 APK 通过翻译层加载 `libdigitalink.so` 成功；
2. 日语模型：`dl.google.com/handwriting/models/lstm.japanese.tflite_5x144...` 下载完成；
3. 中文模型：`zh-Hani-CN` 三个文件（QRNN + LSTM tflite + FST）下载完成；
4. 识别日志实证：`Loaded tflite model` → `Loading TfRecognizer` → `lang: zh_cn` / `ja` → `inkhash` 多次 + `LabeledInkCurveProcessor returned N timesteps`，全程无 `recognize failed`。

## 可复用要点

1. **一个引擎多语言**：ML Kit digital ink 用语言码区分模型，`ConcurrentHashMap` 按 tag 缓存 recognizer，切换语言无需重下已缓存模型。
2. **先抓包名再写代码**：第三方 SDK 文档示例常省略 import，落地前用 `javap`/`unzip -l` 反编译确认真实包名与方法签名，避免 `Unresolved reference` 返工。
3. **GMS 是硬门槛**：ML Kit digital ink 模型无法 bundle，必须先确认目标设备有 GMS；无 GMS 环境需换方案（如 Rime 手写或自打包开源模型）。
4. **候选注入可复用**：外部识别源的候选词走 `showExternalCandidates` 注入原生候选栏，与 native 引擎候选同位置同样式，切换引擎零 UI 改动。
5. **完整打包先拉 submodule**：fcitx5-android 的 C++ 源码（fcitx5/libime/prebuilt 等）是 git submodule，`assembleDebug` 前必须 `git submodule update --init`；只编 Kotlin 不需要。
6. **WSL 构建要点**：wrapper 下载 Gradle 发行版常超时（services.gradle.org 被墙），用 `/opt/gradle-9.6.1` 本地解压版绕过；`gradlew` 被 Windows 改成 CRLF 会导致 `sh\r` 报错，需 `sed -i 's/\r$//' gradlew`。
