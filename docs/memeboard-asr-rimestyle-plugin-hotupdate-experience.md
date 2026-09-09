# MemeBoard 语音桥 rime 式插件化 + 模型热更新经验总结

> 适用场景：fcitx5-android（拾趣输入法）语音输入从「独立跨进程桥」改造为「进程内引擎 + 模型插件」，并支持在线检测更新 / 下载新语音模型。
> 关键结论：引擎内嵌输入法进程后，彻底摆脱小米 HyperOS 的链式启动 / 自启动 / 省电保活限制；语音随用随起、零保活配置。

## 一、背景与目标

- 原方案：语音引擎跑在独立 `asr-bridge` APK，输入法通过 `bindService` + AIDL 跨进程调用。
- 痛点：HyperOS 链式启动管控（pId=1596）——「应用 A 拉起应用 B 的 Service，B 未存活时默认拒绝」。桥进程一旦被清后台/重启，`bindService` 被拦，用户必须手动去应用管理拉起。
- 方案 B（rime 式插件化）：把 sherpa-onnx 引擎**内嵌进输入法进程**，模型放在一个 fcitx5 插件 APK 里。无跨进程 bindService → 链式启动管控彻底失效。

## 二、最终架构

```
主程序（sherpa-onnx 引擎，进程内）
   ├─ 优先读 已下载模型（externalFilesDir/asr-models/，在线更新）
   └─ 回退读 插件 assets（出厂模型，plugin/asr）
```

- 主程序 `app` 直接依赖 `com.github.k2-fsa.sherpa-onnx:sherpa-onnx:v1.13.5`（需在 `settings.gradle.kts` 加 jitpack 仓库）。
- 新建 `plugin/asr` 模型插件：包名 `org.fcitx.fcitx5.android.plugin.asr`，只装 230MB SenseVoice 模型 assets，无 Service、无 native lib，像 rime 一样出现在「插件管理」列表。
- `AsrkbSpeechClient` 从 AIDL/Binder 重写为直接调进程内 `SpeechEngine`；录音、上屏、覆盖层、音频焦点保留，删除纠错协商（SenseVoice 离线模型不支持）。

## 三、关键实现细节

### 1. 纯模型插件（无 fcitx 数据、无 native lib）的落地要点

- 插件必须在 `assets/` 放一个**静态空 `descriptor.json`**：`{"sha256":"<sha256 of empty string>","files":{},"symlinks":{}}`。否则 `DataManager.sync()` 读到空 descriptor 会 `continue`，插件进不了 `loadedPlugins`（只出现在 detected，列表里显示「需要重载」）。
- 不需要应用 `data-descriptor` gradle 插件（手写静态 descriptor.json 更简单，也避免 hashing 230MB 大文件）。
- 模型文件不写进 descriptor.json，所以 `sync()` 不会把它当 fcitx 数据拷进 dataDir；引擎直接 `createPackageContext(pkg,0).assets` 读。
- 插件 `build.gradle.kts` 用 `app-convention` + `plugin-app-convention` + `build-metadata`；依赖 `lib:plugin-base`（它提供 AboutActivity + `org.fcitx.fcitx5.android.plugin.MANIFEST` intent-filter，用于插件发现）。
- 模型 assets 要 `androidResources { noCompress += "onnx" }`（跳过 AAPT2 二次压缩，sherpa-onnx 才能 mmap 读取）。

### 2. sherpa-onnx 双来源加载（assets vs 文件路径）

`sherpa-onnx` 的 `OfflineRecognizer` 构造：

```kotlin
class OfflineRecognizer(assetManager: AssetManager? = null, val config: OfflineRecognizerConfig)
// assetManager == null → 内部走 newFromFile（文件路径加载）
// assetManager != null → 内部走 newFromAsset（assets 加载）
```

- 从 assets：`OfflineRecognizer(assetManager, config)`，config 里 `model`/`tokens` 是 assets 相对路径。
- 从文件：`OfflineRecognizer(assets=null, config)`，config 里 `model`/`tokens` 是文件绝对路径。
- **踩坑**：不能写 `OfflineRecognizer(config)`（单参数）——第一个位置参数是 `assetManager`，会类型不匹配。必须 `OfflineRecognizer(assets, config)`（assets 为 null 时自动走文件模式），或用命名参数 `OfflineRecognizer(config = config)`。

### 3. 模型热更新（AsrModelManager）

- 出厂模型在插件 assets 兜底；下载的新模型存 `context.getExternalFilesDir(null)/asr-models/`（应用专属外部目录，**无需存储权限**）。
- 下载流程：临时目录下载 → **SHA-256 校验** → 校验通过后原子 rename 到最终位置 → 写版本文件。
- 加载逻辑：优先已下载模型，缺失/失败回退出厂模型；切换来源后要 `SpeechEngine.invalidateCache()`（清进程级 recognizer 缓存）+ 重新 load。
- 网络用 OkHttp 同步 `execute()`（在 `Dispatchers.IO` 协程里），流式下载回传进度。

### 4. 检测更新的两种实现

- **GitHub 源**：`GET api.github.com/repos/k2-fsa/sherpa-onnx/releases/tags/asr-models`，列 asset，按名字里的日期（`...int8-YYYY-MM-DD.tar.bz2`）找最新，比对本地日期。
- **ModelScope 源**：`GET modelscope.cn/api/v1/models/{repo}/repo/files?Revision=master&Root=`，返回每个文件的 `Name`/`Sha256`，比对 model 文件 SHA。

## 四、引擎选型结论

### Vosk vs SenseVoice（对语音输入法）

| 维度 | Vosk | SenseVoice |
|------|------|-----------|
| 底层 | Kaldi | 阿里 FunAudioLLM + onnxruntime |
| 识别方式 | 流式（边听边出字） | 非流式（整段缓冲后识别） |
| 中文准确率 | 中规中矩（模型偏老） | 高（连合成语音都能识别） |
| 多语言 | 每语种单独模型 | 单模型自动检测中英日韩粤 |
| 标点 | 无（需后处理） | 内置 ITN |
| 模型体积 | 小（~42MB） | 大（int8 ~228MB） |

**结论**：输入法「长按说话 → 松手上屏」场景，SenseVoice 明显更合适——准确率、标点、多语言都是刚需；「非流式」不是缺点（松手才要结果）。

### SenseVoice 集成进 FunASR ≠ 必须用 FunASR

- `SenseVoice` 是模型，`FunASR` 是阿里官方的 **Python/服务端** 推理框架（`from funasr import AutoModel`），torch 依赖无法上移动端。
- **sherpa-onnx 是官方 README「优秀三方工作」里钦定的移动端部署最佳实践**（「支持在 iOS、Android、Raspberry Pi 等平台使用 SenseVoice」）。两者跑同一份 ONNX，只是推理引擎不同。

## 五、模型源（官方 vs ModelScope，格式差异）

- **官方 iic/SenseVoiceSmall（ModelScope）**：PyTorch 格式（model.pt + am.mvn + 词表），sherpa-onnx **加载不了**。
- **sherpa-onnx 格式的 onnx**（我们要的 `model.int8.onnx` + `tokens.txt`）：
  - GitHub Releases：`k2-fsa/sherpa-onnx` 的 `asr-models` tag，`...int8-2024-07-17.tar.bz2`（tar.bz2 需解压，App 内麻烦）。
  - HuggingFace：`csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx`（单文件直链，需代理）。
  - ModelScope：`poloniumrock/SenseVoiceSmallOnnx`（第三方镜像，sherpa-onnx 格式，国内直连免代理）。
- **ModelScope 下载直链格式**：`https://modelscope.cn/models/{owner}/{repo}/resolve/master/{file}`；文件 SHA 从 API 拿（字段名大写 `Name`/`Sha256`，LFS 大文件 resolve 会 302 重定向，OkHttp 默认跟随）。
- ModelScope 上 `model.int8.onnx` SHA256 = `c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51`（与插件出厂模型同一份）。

## 六、踩坑记录

1. `OfflineRecognizer(config)` 单参数调用报 `Argument type mismatch: OfflineRecognizerConfig but AssetManager? expected` → 第一个位置参数是 assetManager，要传 null 或命名参数。
2. 纯模型插件没有 `descriptor.json` → 插件被 `DataManager.sync()` 静默 skip（不进 loadedPlugins）。
3. sherpa-onnx 需 proguard `-keep class com.k2fsa.sherpa.onnx.** { *; }`（配合已有的 `-dontobfuscate`/`-dontoptimize`）防 R8 缩略掉 JNI 绑定。
4. 主程序加 sherpa-onnx 依赖要在 `settings.gradle.kts` 的 `dependencyResolutionManagement` 加 jitpack 仓库（FAIL_ON_PROJECT_REPOS 模式下项目级仓库被禁）。
5. 删 `app/src/main/aidl`、`app/src/main/java/com` 目录后，`build-release.sh` 的 rsync 目录列表要同步移除，否则 rsync 源目录不存在会报错。
6. 模型来源切换（下载新模型）后必须清 `cachedRecognizer`，否则进程级缓存会阻止新模型生效。

## 七、部署与验证

- WSL 编译验证链：`wsl -u root bash /mnt/e/.../copy-files.sh`（同步）→ `gradle :plugin:asr:assembleDebug` / `:app:assembleRelease`（签名 env SIGN_KEY_*）。
- 产物：主程序 arm64 release 63.7MB + asr 插件 239MB；`adb -s <serial> install -r` 覆盖安装（同签名）。
- 部署顺序：先装 asr 插件（模型），再装主程序；卸载旧 `com.memeboard.asrbridge`。

## 八、可复用要点

- 跨进程服务被厂商链式启动管控拦 → 若引擎栈开源（无闭源 SDK/包名授权），优先考虑**内嵌进程 + 模型/资源放插件 APK**，从根上消除保活问题。
- 大模型（230MB）从「打进主包」拆成「插件 assets + 在线下载目录」双层：出厂兜底 + 热更新，主包不膨胀。
- 移动端离线 ASR 选型：非流式高精度模型（SenseVoice）对「说完整段再上屏」的输入法更合适，而非流式 Vosk。
- 模型托管源要区分「模型格式」（PyTorch vs onnx）与「推理框架」（FunASR vs sherpa-onnx），别只认仓库名。
