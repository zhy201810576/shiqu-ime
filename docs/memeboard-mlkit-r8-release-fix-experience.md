# MemeBoard ML Kit 手写 release 打包与 R8 混淆修复经验

> 面向：需要把 fcitx5-android（或其 fork）打包成正式 release 版、并集成了 Google ML Kit（或 Firebase Components）的 Android/Kotlin 开发者。
> 关键词：R8、proguard、ML Kit Digital Ink、Firebase Components、DependencyCycleException、-dontoptimize、release 打包、WSL2。

## 背景与目标

本次为拾趣输入法（MemeBoard，fcitx5-android fork）打包正式 release 版本，上传小米 15 真机使用。相比上一次 release（9 月 4 日），本次新增两项功能：

1. **88 分类颜文字**：picker 面板数据从硬编码改为 assets JSON 加载，新增标签栏滑动 + 🔍 搜索入口。
2. **ML Kit 中日双语手写**：手写引擎从 gpen 搜狗桥接（闭源）迁移到 Google ML Kit Digital Ink Recognition，一个引擎覆盖中文（`zh-Hani-CN`）与日文（`ja`）。

fcitx5-android 的 release 构建默认开启 `isMinifyEnabled = true` + `isShrinkResources = true`，proguard 走 `proguard-android-optimize.txt`（optimize 模式），且项目的 `proguard-rules.pro` 里只有 `-dontobfuscate`（关类名混淆，**但不关优化**）。首次把 ML Kit 打进去后，一连触发了两个 R8 混淆崩溃，正是本文要沉淀的核心教训。

## 经验一：release 同步脚本必须覆盖所有改动文件

原有 `build-release.sh` 的同步清单只覆盖了 memeboard 图库模块（`memeboard/*.kt` + 少量框架文件），本次新增功能的文件都不在清单里，导致工作副本 `/root/fcitx5-android` 落后于本地源码：

- 颜文字：`input/picker/*.kt`、`assets/kaomoji_data.json`、`AndroidManifest.xml`（注册 `KaomojiSearchActivity`）、`input/bar/ui/TitleUi.kt`。
- ML Kit 手写：`link/MlKitHandwritingClient.kt`、`input/handwriting/*.kt`、`gradle/libs.versions.toml`（`mlkit-digital-ink-recognition` 依赖）、`app/build.gradle.kts`。

**做法**：用 `git status --short` 拿到权威改动清单，把 `M`（修改）+ `??`（新增）文件全部纳入同步（目录用 `rsync -a`，单文件用 `cp -f`），并显式删除工作副本残留的已弃用文件（本例是 `link/GpenHandwritingClient.kt`）。同步清单尤其要覆盖：

- `build-logic/convention/src/main/kotlin/Versions.kt`（版本号）
- 三处 `strings.xml`（values / values-zh-rCN / values-zh-rTW）
- `gradle/libs.versions.toml` + `app/build.gradle.kts`（依赖）
- `app/proguard-rules.pro`（混淆规则）
- `AndroidManifest.xml`

## 经验二：ML Kit 在 R8 release 下的两个崩溃（核心）

### 崩溃 1：手写板一打开就 NPE

```
java.lang.NullPointerException: Attempt to read from field
'com.google.mlkit.vision.digitalink.recognition.internal.zzl
 com.google.mlkit.vision.digitalink.recognition.internal.zzk.zza'
on a null object reference in method
'void org.fcitx.fcitx5.android.input.handwriting.HandwritingOverlayView.<init>(...)'
```

触发路径：工具栏铅笔 → `HandwritingOverlayView.<init>` → `MlKitHandwritingClient.prepare()` → `DigitalInkRecognition.getClient(...)`。

根因：R8 的 optimization pass 破坏了 digital-ink 库内部单例 holder `zzk.zza`。

### 崩溃 2：应用启动即闪退

```
java.lang.RuntimeException: Unable to get provider com.google.mlkit.common.internal.MlKitInitProvider:
com.google.firebase.components.DependencyCycleException: Unsatisfied dependency for component
Component<[class com.google.mlkit.vision.digitalink.recognition.internal.zzk]>{
  deps=[
    Dependency{anInterface=class com.google.mlkit.common.sdkinternal.ExecutorSelector, type=required},
    Dependency{anInterface=class com.google.mlkit.vision.digitalink.recognition.internal.zzl, type=required}
  ]}: class com.google.mlkit.common.sdkinternal.ExecutorSelector
```

触发路径：`MlKitInitProvider`（ContentProvider，进程启动即初始化）→ `ComponentRuntime` 构建组件依赖图时发现 `ExecutorSelector` 组件缺失。

根因：`ExecutorSelector` 在 `com.google.mlkit.common.sdkinternal` 包（**common 库**，不是 digitalink 包），它的组件注册代码被 R8 优化误删，导致 Firebase 组件依赖图不完整。

### 根因与关键认知

1. **`-dontobfuscate` 只关类名重命名，不关 optimization**。R8 的字段优化、死代码消除、内联仍然会破坏「依赖反射 / 服务文件 / 组件依赖注入 / 内部单例」的第三方库。ML Kit 与 Firebase Components 就是典型受害者。
2. **第一次只 keep `com.google.mlkit.vision.digitalink.**` 不够**——崩溃点从 digitalink 包转移到了 `com.google.mlkit.common.**`。必须 keep 整个 `com.google.mlkit.**`。
3. 堆栈里的 `r8-map-id-xxxx` 是 R8 产物的标识，见到它就说明这是混淆/优化后的包，问题大概率出在 proguard 规则上。

### 修复（`app/proguard-rules.pro`）

```proguard
# ML Kit Digital Ink Recognition + Firebase Components
# R8 会误删通过 META-INF/services 反射加载的组件注册类（ComponentRegistrar），
# 且 optimization 会破坏内部单例（zzk.zza）与组件依赖图（ExecutorSelector）。
-keep class com.google.mlkit.** { *; }
-keep class com.google.firebase.components.** { *; }
-keep class * extends com.google.firebase.components.ComponentRegistrar { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.firebase.**

# 关闭 R8 优化：避免第三方库（ML Kit / Firebase / Coil 等）内部单例与反射注册被破坏
-dontoptimize
```

要点：

- `-keep class * extends com.google.firebase.components.ComponentRegistrar { *; }` 保住通过服务文件加载的组件注册实现，防止组件工厂代码被 shrinking/optimization 删除。
- `-dontoptimize` 是「一劳永逸」的关键：与项目既有 `-dontobfuscate` 搭配后，R8 退化为纯 shrinker（删未使用代码 + 资源压缩照常），不再做破坏性代码优化。代价是 APK 变大——主程序从 48 MB 增至 51.9 MB（约 +3.9 MB），自用/开源场景可接受。

## 经验三：同签名 release 可用 `-r` 覆盖升级，无需卸载

设备上已装的是 9 月 4 日的同签名 release（versionCode 1002 / versionName 1.0.0，与本包一致），因此：

```powershell
adb -s b68a5ae7 install -r dist/fcitx5-memeboard-arm64-release.apk
adb -s b68a5ae7 install -r dist/fcitx5-rime-arm64-release.apk
```

直接 `Success`，且 MT Photos 服务器地址 / API Key / 图库标签选择全部保留。

**对比**：若是从 debug 签名切换到 release 签名（签名不一致），`install -r` 会报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，必须先 `adb uninstall` 再装。判断签名是否一致的捷径：`dumpsys package <pkg> | grep versionCode` 看 versionCode，再用 `apksigner verify --print-certs` 对比 SHA-256。

## 验证与排查方法

1. 崩溃排查：`adb logcat -d -b crash`（Android 10+ 有独立 crash 缓冲区，比主 logcat 更干净），重点看 `FATAL EXCEPTION` 段首行的异常类型与 `Caused by`。
2. 签名核验：`apksigner verify --print-certs <apk>`，确认主程序与插件（rime）是同一证书（本例 `CN=Shiqu IME`，SHA-256 `55b5f681…`）。
3. 版本核验：`aapt dump badging <apk> | head -2` 看 `versionCode` / `versionName`。
4. 修复后验证：`am force-stop` + `monkey -p <pkg> 1` 拉起进程，再 `logcat -d -b crash` 确认无 `MlKitInitProvider` / `DependencyCycleException`。

## 可复用要点

1. **release 首次接入新第三方库，务必先在真机/模拟器跑一遍**，别想当然认为 debug 通过 release 就通过——R8 混淆只影响 release。
2. **ML Kit（尤其 Digital Ink）必须显式 keep**：`-keep class com.google.mlkit.** { *; }` + keep `ComponentRegistrar`，必要时 `-dontoptimize`。
3. **`-dontobfuscate ≠ -dontoptimize`**：两者要分开想。想彻底避免 R8 破坏库，两个都要关（或至少关闭 optimization）。
4. **keep 规则要覆盖到依赖的完整包树**：报错在 `common` 包却只 keep `vision.digitalink` 包是踩坑重灾区。
5. **同步脚本要随功能演进**：每次新增/改动源码文件，同步清单都要补，否则「构建成功」打出来的却是旧代码。
6. 排查崩溃先看 `r8-map-id` 是否出现——出现则优先怀疑 proguard/R8，而非业务代码。
