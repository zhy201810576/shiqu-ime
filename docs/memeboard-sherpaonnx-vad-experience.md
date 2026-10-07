# MemeBoard sherpa-onnx VAD 接入经验（语音静音/噪声幻觉修复）

> 拾趣输入法语音输入「长按空格不说话也出字（一会儿中文一会儿英文）」的根因分析与 Silero VAD 修复实践。

> ⚠️ 注：识别引擎已于 2026-10 从 SenseVoice 切换为 Paraformer（`sherpa-onnx-paraformer-zh-2024-03-09`，解决多音字/近音字混淆），VAD 门控机制不变；下文关于 SenseVoice 的描述仅作历史记录。

## 一、背景与问题

- **现象**：长按空格但不说话，松手后仍识别出文本，且一会儿中文、一会儿英文。
- **根因（三层叠加）**：
  1. **无 VAD**：录音链路（`AsrkbSpeechClient` 的 AudioRecord 循环）只把 PCM 原样缓冲，`SpeechEngine.finish()` 只判「有没有录到帧」，整段音频（含纯静音/环境底噪）原样喂给 SenseVoice；
  2. **SenseVoice 无静音类别**：端到端模型对任意波形都强制解码出一个「最像」的文本序列（幻觉），不像传统 HMM 有 filler/silence 建模 + 置信度门控；
  3. **语言自动检测漂移**：`sv.language = ""` 让 SenseVoice 自带 LID 在无稳定声学证据的噪声上随机横跳，所以中英文乱出。

## 二、方案

接入 sherpa-onnx 自带的 **Silero VAD**，在送 SenseVoice 之前切掉静音/噪声段；全程无语音段则直接返回 null（不上屏）。

## 三、关键实现

### 1. sherpa-onnx 1.13.5 VAD Kotlin API（务必核对版本签名）

在 `com.k2fsa.sherpa.onnx` 包内：

```kotlin
data class SileroVadModelConfig(
    var model: String = "", var threshold: Float = 0.5F,
    var minSilenceDuration: Float = 0.25F, var minSpeechDuration: Float = 0.25F,
    var windowSize: Int = 512, var maxSpeechDuration: Float = 5.0F)

data class VadModelConfig(
    var sileroVadModelConfig: SileroVadModelConfig = SileroVadModelConfig(),
    var tenVadModelConfig: TenVadModelConfig = TenVadModelConfig(),
    var sampleRate: Int = 16000, var numThreads: Int = 1,
    var provider: String = "cpu", var debug: Boolean = false)

class SpeechSegment(val start: Int, val samples: FloatArray)
class Vad(assetManager: AssetManager? = null, var config: VadModelConfig)
// Vad 方法：acceptWaveform / empty / front / pop / flush / isSpeechDetected / release
```

- **字段名是 `sileroVadModelConfig`（不是 `sileroVad`）**，易踩坑；
- `Vad(assetManager, config)`：assetManager 传 null 走 `newFromFile`，传非空走 `newFromAsset`（与 `OfflineRecognizer` 双来源一致）；
- `SpeechSegment.samples` 是 Kotlin 属性（非 getSamples()）。

### 2. VAD 模型来源

`siler_vad.onnx`（约 629KB）**固定从 asr 插件 assets 加载**，不参与 `AsrModelManager` 在线更新（小且稳定）。`SpeechEngine` 构造新增 `vadAssets: AssetManager?` 参数，`fromDir` 也传入插件 assets（SenseVoice 与 VAD 可不同来源）。

### 3. Session 内切段 + 拼接识别

- 每个识别会话（一次长按）创建**独立 `Vad` 实例**（有状态，不能跨会话复用）；
- `accept()` 按 512 样本窗口把 PCM 对齐后喂 VAD，`while (!vad.empty())` 收集完成的语音段；
- `finish()` 先 `flush()` 强制产出尾部段，收集全部段后**拼接（段间插 0.2s 静音防粘连）一次识别**；`segments.isEmpty()` 则返回 null 不上屏；
- 样本 `copyOf()` 防御（避免 pop 后 native 缓冲区复用）；
- **降级兜底**：VAD 构造失败 → `vad = null` → 退回整段识别，语音功能不因 VAD 不可用而退化。

### 4. VAD 参数（针对「长按说话」场景）

threshold 0.5 / minSpeechDuration 0.25s（滤短噪声）/ minSilenceDuration 0.5s（容忍句内停顿）/ maxSpeechDuration 20s（长按长说）/ windowSize 512。

### 5. .gitignore 例外

仓库 `*.onnx` 全忽略（大模型超 GitHub 100MB 限制走 download-models.sh）。VAD 模型小，加例外随仓库分发：

```
*.onnx
*.gram
!plugin/asr/src/main/assets/silero_vad.onnx
```

## 四、踩坑记录

- **下载 silero_vad.onnx**：Windows 下 curl/Invoke-WebRequest 走 schannel 报 `SEC_E_NO_CREDENTIALS`，改用 anaconda 的 Python `urllib`（OpenSSL 后端）下载成功；
- **DSH 沙箱捕获子进程输出受限**：pwsh 调 Python 的 stdout/stderr 会被 `StandardErrorEncoding` 报错拦截。解法：Python 脚本把结果写日志文件，再用 read 工具读；
- **WSL 构建**：沿用既有经验——`wsl.exe -u root` + `/opt/gradle-9.6.1/bin/gradle`，改动先 cp 到 `/root/fcitx5-android` 副本，后台构建写独立脚本 + nohup，aboutlibraries 卡住加 socket 超时 JVM 参数。

## 五、验证

- Kotlin 编译预检 `:app:compileReleaseKotlin` ✅ BUILD SUCCESSFUL（确认 VAD API 引用无误）；
- 完整打包 `:app:assembleRelease :plugin:asr:assembleRelease` ✅ 2m11s，`unzip -l` 确认 `assets/silero_vad.onnx` 已入 asr 插件 APK；
- 实机（小米15）覆盖安装后验证通过：长按空格不说话 → 提示「未检测到语音」且不上屏，正常说话识别照常。
