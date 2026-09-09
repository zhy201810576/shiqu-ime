# MemeBoard 语音/手写隐形桥：arm64 引擎在 Intel 模拟器运行与桥接 APK 模式

> 适用场景：Android 输入法集成闭源/第三方引擎、Intel 电脑上跑 arm64-only 的 so、把第三方完整 APP 改造成隐形后台服务。

## 一、背景

MemeBoard（fcitx5-android 分支）需要融合三种输入能力：拼音（rime-wanxiang）、语音（BiBi AIDL）、手写（语燕 gpen）。其中手写 gpen 是搜狗闭源 SDK，语音 BiBi 是第三方完整 APP。本文记录两个关键突破：**Intel AVD 跑 arm64 so** 与 **隐形桥接 APK 模式**，以及 BiBi 引擎的解包调研结论。

## 二、Intel AVD 运行 arm64-only 引擎（最关键）

### 问题
搜狗手写 SDK（libSogouShell.so 等 4 个 so）只提供 arm64-v8a，无 x86/x86_64 版本。Intel PC 的 Android Studio AVD 默认 x86_64 镜像会报 so 加载失败。

### 解法：Google Play 系统镜像
- 必须选择 **Google Play** 标签的系统镜像（而非 AOSP），它内置了 ARM 翻译层 `libndk_translation.so`。
- AOSP 镜像没有这个文件，装 arm64 APK 会 `INSTALL_FAILED_NO_MATCHING_ABIS` 或运行即崩。

### 验证命令
```bash
adb shell getprop ro.dalvik.vm.native.bridge
# 期望输出：libndk_translation.so（有值即支持 arm64 翻译）

adb shell getprop ro.product.cpu.abilist
# 期望同时含 x86_64 和 arm64-v8a
```

### 实测环境
- 镜像：sdk_gphone64_x86_64，Android 16 (API 36)，Google Play 镜像
- 结果：搜狗 4 个 arm64 so 全部加载成功，识别正常（画横线出候选「一 是 到 天 给 开 真 得」）

### 衍生坑：AVD 屏幕坐标
1080x2400 @420dpi 的 AVD 与老 1080x1920 不同，用 PIL 亮度扫描定位工具栏图标坐标（cy≈1500，手写按钮 cx≈788，候选行 cy≈1624）再 tap，避免点到错误按键。

## 三、隐形桥接 APK 模式（无 LAUNCHER + AIDL）

### 动机
gpen 手写 SDK 授权绑定硬编码包名 `com.yuyan.pinyin.{online,offline}.{release,debug}`，JNI 符号固定为 `Java_com_yuyan_inputmethod_core_HandWriting_*`，无法直接移植进 `org.fcitx.fcitx5.android`。

### 方案：桥接 APK（仿 BiBi AIDL）
1. 独立 APK，`applicationId` 用授权包名 `com.yuyan.pinyin.offline.release`。
2. Manifest **不声明 LAUNCHER Activity** → 桌面无图标，纯后台服务。
3. 暴露 AIDL：`IHandwritingService { String[] recognize(in int[] points); String getStatus(); }`，包 `com.yuyan.handwriting.aidl`，服务 `com.yuyan.handwriting.HandwritingService`。
4. 主 APK 通过 `bindService(ComponentName("com.yuyan.pinyin.offline.release", ...))` 静默拉起。

### 关键实现细节
- JNI 类必须保持原包名 `com.yuyan.inputmethod.core.HandWriting`（符号名锁定），但 APK 自己的 `namespace` 可以不同。
- `System.loadLibrary("handwriting")` → dlopen `libhwInterface.so`（SONAME 为 `libsogou_interface.so`）→ DT_NEEDED 自动拉 `libSogouShell.so` + `libgpen_handwriter.so`。
- 笔画格式：x,y Int 对，笔迹分隔 `-1,0`；调用链 `reset() → inputHWPoints(intArray) → getCandidates()[0]`。
- assets `hw/` 模型需拷贝到 `getExternalFilesDir("hw")`。

### 验证"隐形 APK 已装"
桌面看不到图标 ≠ 没装。验证命令：
```bash
adb shell pm list packages | grep yuyan   # 看到包名即已装
adb shell pidof com.yuyan.pinyin.offline.release  # 有 PID 即服务活着
adb shell dumpsys package <pkg> | grep -E "primaryCpuAbi|versionName"
```

### 重要区分：隐形桥 vs 第三方 APP
- **gpen 桥**：自研隐形服务 APK，无图标，被输入法静默绑定。
- **BiBi（说点啥）**：第三方完整 APP，有 LAUNCHER 图标（`com.brycewg.asrkb/.ui.SettingsActivity`），需单独安装。两者"看不到 APP"是两种完全不同的原因。

## 四、BiBi 语音引擎解包调研（为 asr-bridge 铺路）

解包 `bibi-4.4.2-arm64.apk` 的结论：

### 本地引擎（全 Apache-2.0 开源）
- `libonnxruntime.so`（21MB）— ONNX Runtime 推理
- `libsherpa-onnx-jni.so`（4.6MB）— sherpa-onnx 语音识别框架（Apache-2.0）
- `assets/vad/ten-vad.onnx`（324KB）— 腾讯 TenVAD 断句
- `assets/denoiser/gtcrn_simple.onnx`（523KB）— GTCRN 降噪
- ASR 大模型（SenseVoice 中文等）**运行时下载**，不在 APK 内

### 云端引擎（需 API key）
- 阿里 DashScope（Qwen3-Omni/ASR/TTS）、Gemini、Cohere 等，全需 key
- 根目录 `qwen.tiktoken` 用于云端 token 计数

### 关键结论
BiBi 的识别核心 sherpa-onnx + SenseVoice 模型**全开源、无授权绑定、无服务器计数**，比 gpen 搜狗 SDK 干净得多。**可以直接做纯自研、纯离线、纯开源的隐形语音桥（asr-bridge）**，沿用 BiBi 的 AIDL 协议，主 APK 只改绑定目标包名即可。

## 五、gpen 手写桥端到端验证记录

- 产物（arm64）：gpen-bridge 17.5MB、memeboard 62MB、rime 420MB。
- 触发 UX：展开工具栏 → 点铅笔图标 → 手写板（画布 + 候选栏 + 清空/⌫/退出）。
- 空格长按仍绑定语音，不占用。
- 日志标签：`GpenBridge` / `GpenLink`；关键行 `GpenBridge: engine status: ok`。
- 搜狗本地授权直接通过（无需联网激活），识别→候选→上屏全链路验证通过。

## 六、可复用要点速查

1. **Intel 跑 arm64 so**：Google Play 镜像 + `libndk_translation.so`，用 `getprop ro.dalvik.vm.native.bridge` 验证。
2. **隐形服务 APK**：无 LAUNCHER + AIDL 服务 + `bindService(ComponentName)` 静默拉起。
3. **授权绑定包名**：`applicationId` 用授权名，JNI 类保持原包名（符号锁定），`namespace` 可不同。
4. **so 依赖链**：`System.loadLibrary` → SONAME → DT_NEEDED 自动级联。
5. **分析第三方 APK 引擎**：解包看 `lib/*.so` + `assets/` + dex 字符串搜 `https://`、`.onnx`、`apiKey`。
6. **验证隐形 APK**：`pm list packages` + `pidof` + `dumpsys package`，而非看桌面图标。
7. **Android 16 后台服务限制**：`am startservice` 报 "app is in background uid null"，需前台 bindService 触发。
8. **AVD 坐标**：新分辨率先用 PIL 亮度扫描定位 UI 元素，再 tap。
