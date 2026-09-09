# MemeBoard 语音输入：asr-bridge 隐形语音桥开发经验

> 阶段 4：把第三方 BiBi「说点啥」语音 APP 替换为纯自研、全开源、完全离线的隐形桥接服务。
> 项目：fcitx5-android 分支（MemeBoard），自用 + 开源，不上架、不商业。

## 一、背景与目标

- 语音输入原本对接第三方 APP「BiBi（说点啥）」（包名 com.brycewg.asrkb）的 AIDL。
- 目标：像 gpen 手写桥一样，做成无桌面图标、通过 AIDL 供输入法静默调用的隐形服务，摆脱第三方依赖，并在设置中沿用现有语音配置。

## 二、技术选型（关键结论）

- 解包 BiBi APK 发现其识别引擎是 sherpa-onnx（Apache-2.0）+ onnxruntime + TenVAD 降噪，全部开源。
- 模型选型是最大的坑：先用了 zipformer 流式双语模型 sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20，结果对字节跳动 Doubao 语音合成 2.0 生成的普通话识别为空；而 BiBi 能识别。
- 复盘 BiBi 的 dex（SenseVoiceResolvedModel、sherpa-onnx-qnn-*-sense-voice）确认：BiBi 用的是 SenseVoice（阿里 FunAudioLLM 开源）。
- 换用 SenseVoice 后，同一段 Doubao 语音识别为「你好，我是一段语音识别测试音频，感谢您的配合。」，一字不差。

## 三、模型与依赖

- sherpa-onnx 依赖（JitPack）：com.github.k2-fsa.sherpa-onnx:sherpa-onnx:v1.13.5，settings 加 maven { url = uri("https://jitpack.io") }。
- 模型：sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17，文件为 model.int8.onnx（239 MB）+ tokens.txt，支持普通话/粤语/英/日/韩，带标点。
- 下载 URL 注意：int8 在日期之前（...int8-2024-07-17.tar.bz2），写错日期位置会 404。
- 模型 license：apache-2.0，可自由打包，无 gpen 那种闭源/包名授权/服务器计数问题。

## 四、sherpa-onnx Android API 的坑

1. Kotlin 类禁用 Java setter：OnlineTransducerModelConfig 等是 Kotlin data class（带 Kotlin metadata），Kotlin 编译器会拒绝 setEncoder(...) 报 Unresolved reference，必须用属性语法 transducer.encoder = ...。
2. 结果对象用 .text 属性而非 .getText()（同理）。
3. SenseVoice 是离线模型，用 OfflineRecognizer(AssetManager, OfflineRecognizerConfig)，配置链：OfflineSenseVoiceModelConfig（model/language=""/useInverseTextNormalization=true）→ OfflineModelConfig（senseVoice/tokens/numThreads/debug）→ OfflineRecognizerConfig（modelConfig），结果在 recognizer.getResult(stream).text。
4. Parcel.writeException 要 Exception 而非 Throwable。
5. AAPT2 压缩 200MB+ 的 onnx 极慢，androidResources { noCompress += "onnx" } 跳过二次压缩。

## 五、Binder 协议（与 BiBi 完全一致，客户端只改绑定目标）

- 服务端描述符固定 com.brycewg.asrkb.aidl.IExternalSpeechService；transact 码：startPcmSession=+6、writePcm=+7、finishPcm=+8、getInputRequirements=+9。
- 回调描述符 com.brycewg.asrkb.aidl.ISpeechCallback：onState=+0、onPartial=+1、onFinal=+2、onError=+3、onAmplitude=+4。
- getInputRequirements 返回 0 即可让客户端跳过纠错协商，直接开始推流。
- 客户端（MemeBoard）端改造只有三处：绑定 ComponentName、AndroidManifest 的 queries 包可见性、文案。

## 六、模型缓存（体验关键）

- 服务每次 onCreate 重载 239MB 模型要 10 秒，不可接受。
- 解决：companion object 里 @Volatile private var cachedRecognizer，进程级复用；服务对象重建（unbind→onDestroy→onCreate）但进程未死时，第二次起瞬时 ready。

## 七、构建与下载环境（Windows + DSH 沙箱）

- 下载大文件：Windows 的 curl 走 schannel 报 SEC_E_NO_CREDENTIALS；Git 自带 curl 也一样。用 anaconda/WSL 的 Python urllib（OpenSSL 后端）下载 GitHub release 大文件最稳。
- 构建：PowerShell 后端调 wsl.exe 会被拒（E_ACCESSDENIED）。用 Git Bash 的 bash 工具 + wsl.exe 驱动 WSL 构建。
- 路径转换：Git Bash 会把 /mnt/e/... 转成 D:/Git/mnt/e/...，加 MSYS_NO_PATHCONV=1 禁用。
- 后台构建：nohup ... & 会随 wsl.exe 会话退出被杀；用 setsid ... & 脱离进程组。
- tar/git 命令被沙箱拒绝时，改用 Python 的 tarfile/urllib。

## 八、模拟器验证

- Intel AVD 需 Google Play 镜像（自带 libndk_translation）跑 arm64；但 sherpa-onnx AAR 自带 x86_64，模拟器可原生跑（primaryCpuAbi=x86_64）。
- Host Mic 开关：Extended Controls → Microphone → Enable Host Microphone Access 必须开，否则模拟器录到静音、识别为空；「虚拟耳机」对语音测试无用。
- 音频回灌不可行：模拟器「扬声器→麦克风」无回环，把 mp3 推进去播放也录不进去，只能真人对着主机麦克风说话。
- 模拟器 x86_64 上 SenseVoice 识别 4.7s 音频约需 4s（慢），真机 arm64 会快。

## 九、产物与状态

- dist/asr-bridge-arm64-x86_64-debug.apk（约 307 MB，双 ABI，无图标，AIDL 服务）。
- dist/fcitx5-memeboard-x86_64-debug.apk（绑定 asr-bridge）。
- 已验证：绑定、SenseVoice 加载（缓存后瞬时）、PCM 推流、波形回调、官方 test_wavs 与 Doubao 语音识别全部正确。