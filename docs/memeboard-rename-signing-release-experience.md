# MemeBoard（拾趣输入法）改名 + 签名 + release 打包经验

> 面向：需要给 fcitx5-android 或其 fork 做「改名、release 签名、正式打包」的 Android/Kotlin 开发者。
> 场景：自用 + 开源、不上架、WSL2 构建链、DSH 沙箱开发环境。

## 1. 改名：只动显示名，绝不动 applicationId

### 结论
App 显示名只改 `strings.xml` 里的 `app_name_release` / `app_name_debug`，**`applicationId` 保持 `org.fcitx.fcitx5.android` 不动**。

### 为什么不能动 applicationId
之前踩过坑：IME 组件包名与类包名不一致（debug 加过 `.debug` 后缀）导致系统报 `unrecognized IME ID`、无法设为默认输入法。所以改名只换「显示名」，不动包名。

### 改哪几处
- `app/src/main/res/values-zh-rCN/strings.xml`（简体）
- `app/src/main/res/values-zh-rTW/strings.xml`（繁体）
- `app/src/main/res/values/strings.xml`（英文兜底）

各改两行：`app_name_release` 和 `app_name_debug`（自用可去掉「(调试)」后缀，因为 debug/release 同 applicationId 不同签名，本就无法共存，靠图标区分）。

## 2. release 签名

### 2.1 生成 keystore（keytool）
```bash
keytool -genkeypair -keystore release.keystore -alias shiqu \
  -keyalg RSA -keysize 2048 -validity 36500 \
  -storepass <pwd> -keypass <pwd> \
  -dname "CN=Shiqu IME, O=Memeboard, C=CN"
```
- 自用自签：RSA 2048 + 36500 天（约 100 年）即可。
- 密码用 `openssl rand -hex 16`（32 字符纯十六进制，无特殊字符，脚本里好处理）。
- keystore 与密码**务必备份**：丢失后无法覆盖升级（签名不一致 → 必须卸载重装）。

### 2.2 主程序 / 插件（fcitx5-android 仓库内）
签名走 `AndroidAppConventionPlugin` 的 `signingConfigs.fromProjectEnv(target)`，只需构建时注入环境变量：
```
SIGN_KEY_FILE=<keystore 绝对路径>
SIGN_KEY_PWD=<密码>
SIGN_KEY_ALIAS=shiqu
```
支持 `SIGN_KEY_BASE64`（base64 内联）或 `SIGN_KEY_FILE`（文件路径）两种。

### 2.3 独立桥项目（gpen-bridge / asr-bridge）
它们的 `app/build.gradle.kts` 原本**没有 release 签名配置**（只有 `isMinifyEnabled=false`），需手动加：
```kotlin
signingConfigs {
    create("release") {
        storeFile = System.getenv("SIGN_KEY_FILE")?.let { File(it) }
        storePassword = System.getenv("SIGN_KEY_PWD")
        keyAlias = System.getenv("SIGN_KEY_ALIAS")
        keyPassword = System.getenv("SIGN_KEY_PWD")
    }
}
buildTypes {
    release {
        isMinifyEnabled = false
        signingConfig = signingConfigs.getByName("release")
    }
}
```

### ⚠️ 关键坑：`java.io.File` 解析失败
第一版写成 `java.io.File(it)`，Gradle 报 `Unresolved reference 'io'`。
**原因**：在 Gradle Kotlin DSL 里 `java` 被 `Project` 的 `java` 扩展（JavaPluginExtension）遮蔽，`java.io.File` 无法解析。
**解法**：文件顶部 `import java.io.File`，然后用 `File(it)`。

## 3. release 构建（WSL2）

### 3.1 必须用 root
构建链在 WSL 的 `/root/fcitx5-android`（主程序）、`/root/gpen-bridge`、`/root/asr-bridge`（桥）。
WSL 默认用户是 `coder`，访问 `/root` 会 `Permission denied`。必须：
```bash
wsl -u root bash /mnt/e/.../build-release.sh
```
否则 `cd /root/fcitx5-android` 失败，gradle 在错误目录跑（报 `does not contain a Gradle build`）。

### 3.2 sync 脚本要覆盖改动文件
构建前需把 Windows 侧改动同步到 WSL 工作副本。`sync-memeboard.sh` 原先只同步 memeboard 的 `.kt` 和 strings.xml，**漏了 `Versions.kt`（版本号）和 `values-zh-rTW`（繁体改名）**，已补上：
```bash
cp -f "$SRC"/build-logic/convention/src/main/kotlin/Versions.kt "$DST"/build-logic/convention/src/main/kotlin/
cp -f "$SRC"/app/src/main/res/values-zh-rTW/strings.xml "$DST"/app/src/main/res/values-zh-rTW/
```

### 3.3 版本号
- `Versions.kt`：`baseVersionName`（显示版本）+ `baseVersionCode`（versionCode = baseVersionCode*10 + abiId）。
- `buildVersionName` 默认走 `git describe --tags --long --always`，会覆盖 baseVersionName。**要固定版本号，构建时 export `BUILD_VERSION_NAME=1.0.0`**。

### 3.4 构建脚本
- `build-release.sh`：sync + 注入 `SIGN_KEY_*` / `BUILD_VERSION_NAME` + `:app:assembleRelease :plugin:rime:assembleRelease`。
- `build-bridges-release.sh`：sync 两个桥的 build.gradle.kts + 各自 `assembleRelease`。

### 3.5 R8 混淆
release 默认 `isMinifyEnabled=true` + `shrinkResources`。fcitx5-android 自带的 proguard 规则已覆盖 MemeBoard 依赖（kotlinx.serialization / Room / Coil / AIDL），本次一次通过。但**首次跑要留意**，若报 keep 缺失再针对性补。

## 4. 产物核验（apksigner）
```bash
apksigner verify --print-certs <apk>
# 预期：Signer #1 certificate DN: CN=Shiqu IME, O=Memeboard, C=CN
```
四个 APK 的 SHA-256 应一致，确认统一签名。
产物名：主程序/插件因 `archivesName=$applicationId-$versionName` 为 `org.fcitx.fcitx5.android-1.0.0-arm64-v8a-release.apk`；独立桥项目是默认 `app-release.apk`，复制时需重命名（如 `gpen-bridge-arm64-release.apk`）。

## 5. release 内嵌调试开关（原生自带，无需新写）
fcitx5-android 自带 release 调试三件套，**不被 `BuildConfig.DEBUG` 门控**：
1. 设置 → 开发者 → 「详细日志」开关（`verbose_log`）：release 下 `Timber.setupForest(verbose)` 也会从 ConciseTree 切 VerboseTree，输出完整日志。
2. 设置 → 开发者 → 「实时日志」（`LogActivity`）：读 logcat 流。
3. release 独有崩溃捕获（`FcitxApplication.kt` 的 `if (!BuildConfig.DEBUG)`）：崩溃瞬间自动弹日志界面 + 堆栈，10 秒内连续崩溃直接退出避免崩溃循环。

## 6. DSH 沙箱环境要点
- Windows 侧有 JDK 21 keytool（`D:\Java\jdk-21.0.12.1\bin\keytool.exe`），keystore 可在 Windows 侧生成。
- DSH workspace-write 沙箱下：执行工作区外程序（java/keytool）报「拒绝访问」，访问 WSL 报 `E_ACCESS_DENIED`——**两者都需 `danger-full-access`**。

## 7. 可复用要点清单
1. 改名只改 `app_name`，`applicationId` 永远不动（IME 识别依赖它）。
2. keystore 用 `openssl rand -hex 16` 密码，RSA 2048 + 100 年，务必备份。
3. 独立 Gradle 项目加签名用环境变量注入，别硬编码路径（Windows/WSL 路径不同）。
4. Gradle Kotlin DSL 里用 `import java.io.File` + `File(it)`，别写 `java.io.File`。
5. WSL 构建必须 `wsl -u root`（工作副本在 /root）。
6. sync 脚本要覆盖所有改动的文件（尤其 build-logic 下的 `Versions.kt`）。
7. 固定版本号要 export `BUILD_VERSION_NAME`（否则被 git describe 覆盖）。
8. 产物用 `apksigner verify --print-certs` 核验统一签名。
