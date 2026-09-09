#!/usr/bin/env bash
# 拾趣输入法 (MemeBoard) release 打包脚本 —— 在 WSL2 内以 root 执行
# 用法: wsl -u root bash /mnt/e/APP-Project/memeboard/build-release.sh [abi]
#   abi 默认 arm64-v8a，可选 arm64-v8a / x86_64 / x86 / armeabi-v7a
#   注意：工作副本位于 /root/fcitx5-android，必须用 root（默认 coder 用户无 /root 权限）
set -uo pipefail

SRC=/mnt/e/APP-Project/memeboard/fcitx5-android
DST=/root/fcitx5-android
ABI="${1:-arm64-v8a}"

echo "=== [1/4] 同步源码（完整：memeboard + picker 颜文字 + ML Kit 手写 + 语音 + 框架层 + 依赖 + 版本号）==="

# ---- 删除本地已删除、工作副本还残留的文件 ----
rm -f "$DST"/app/src/main/java/org/fcitx/fcitx5/android/link/GpenHandwritingClient.kt
rm -f "$DST"/app/src/main/java/org/fcitx/fcitx5/android/link/AsrkbExternalInputSession.kt
rm -f "$DST"/app/src/main/java/org/fcitx/fcitx5/android/link/BridgePrewarmer.kt
rm -rf "$DST"/app/src/main/aidl
rm -rf "$DST"/app/src/main/java/com

# ---- 目录级 rsync（新增目录 + 多文件目录，自动带新增/覆盖修改）----
for d in \
  app/src/main/java/org/fcitx/fcitx5/android/link \
  app/src/main/java/org/fcitx/fcitx5/android/input/handwriting \
  app/src/main/java/org/fcitx/fcitx5/android/input/voice \
  app/src/main/java/org/fcitx/fcitx5/android/input/picker \
  app/src/main/java/org/fcitx/fcitx5/android/memeboard \
  app/src/main/java/jaygoo \
  ; do
  mkdir -p "$DST/$d"
  rsync -a "$SRC/$d/" "$DST/$d/"
done

# memeboard 单元测试
mkdir -p "$DST"/app/src/test/java/org/fcitx/fcitx5/android/memeboard/
rsync -a "$SRC"/app/src/test/java/org/fcitx/fcitx5/android/memeboard/ \
        "$DST"/app/src/test/java/org/fcitx/fcitx5/android/memeboard/

# ---- 单文件 cp（框架层 + 依赖 + 资源）----
cp -f "$SRC"/app/build.gradle.kts                                   "$DST"/app/build.gradle.kts
cp -f "$SRC"/settings.gradle.kts                                    "$DST"/settings.gradle.kts
cp -f "$SRC"/app/proguard-rules.pro                                 "$DST"/app/proguard-rules.pro
cp -f "$SRC"/gradle/libs.versions.toml                              "$DST"/gradle/libs.versions.toml
cp -f "$SRC"/build-logic/convention/src/main/kotlin/Versions.kt     "$DST"/build-logic/convention/src/main/kotlin/Versions.kt
cp -f "$SRC"/build-logic/convention/src/main/kotlin/AndroidAppConventionPlugin.kt \
      "$DST"/build-logic/convention/src/main/kotlin/AndroidAppConventionPlugin.kt
cp -f "$SRC"/build-logic/convention/src/main/kotlin/AndroidPluginAppConventionPlugin.kt \
      "$DST"/build-logic/convention/src/main/kotlin/AndroidPluginAppConventionPlugin.kt

cp -f "$SRC"/app/src/main/AndroidManifest.xml                       "$DST"/app/src/main/AndroidManifest.xml
cp -f "$SRC"/app/src/main/res/xml/input_method.xml                  "$DST"/app/src/main/res/xml/input_method.xml
cp -f "$SRC"/app/src/main/res/values/strings.xml                    "$DST"/app/src/main/res/values/strings.xml
cp -f "$SRC"/app/src/main/res/values-zh-rCN/strings.xml             "$DST"/app/src/main/res/values-zh-rCN/strings.xml
cp -f "$SRC"/app/src/main/res/values-zh-rTW/strings.xml             "$DST"/app/src/main/res/values-zh-rTW/strings.xml
cp -f "$SRC"/app/src/main/assets/kaomoji_data.json                  "$DST"/app/src/main/assets/kaomoji_data.json

cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/core/Fcitx.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/core/Fcitx.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/data/prefs/AppPrefs.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/data/prefs/AppPrefs.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/FcitxInputMethodService.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/FcitxInputMethodService.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/bar/KawaiiBarComponent.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/bar/KawaiiBarComponent.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/bar/ui/TitleUi.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/bar/ui/TitleUi.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/bar/ui/idle/ButtonsBarUi.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/bar/ui/idle/ButtonsBarUi.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/candidates/horizontal/HorizontalCandidateComponent.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/candidates/horizontal/HorizontalCandidateComponent.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/keyboard/BaseKeyboard.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/keyboard/BaseKeyboard.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/keyboard/CommonKeyActionListener.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/keyboard/CommonKeyActionListener.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/keyboard/KeyAction.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/keyboard/KeyAction.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/keyboard/KeyboardWindow.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/keyboard/KeyboardWindow.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/keyboard/SpaceLongPressBehavior.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/keyboard/SpaceLongPressBehavior.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/status/StatusAreaEntryUi.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/status/StatusAreaEntryUi.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/ui/main/MainFragment.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/ui/main/MainFragment.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/ui/main/settings/SettingsRoute.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/ui/main/settings/SettingsRoute.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/utils/AppUtil.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/utils/AppUtil.kt
cp -f "$SRC"/app/src/test/java/org/fcitx/fcitx5/android/ThemeSerializationTest.kt \
      "$DST"/app/src/test/java/org/fcitx/fcitx5/android/ThemeSerializationTest.kt

# rime 插件（release 也要打）
cp -f "$SRC"/plugin/rime/src/main/cpp/CMakeLists.txt              "$DST"/plugin/rime/src/main/cpp/CMakeLists.txt
cp -f "$SRC"/plugin/rime/src/main/cpp/default.yaml                "$DST"/plugin/rime/src/main/cpp/default.yaml
cp -f "$SRC"/lib/plugin-base/src/debug/AndroidManifest.xml        "$DST"/lib/plugin-base/src/debug/AndroidManifest.xml

# asr 语音模型插件（进程内引擎读它的 assets；模型用 rsync 增量同步）
cp -f "$SRC"/plugin/asr/build.gradle.kts                          "$DST"/plugin/asr/build.gradle.kts
cp -f "$SRC"/plugin/asr/proguard-rules.pro                        "$DST"/plugin/asr/proguard-rules.pro
cp -f "$SRC"/plugin/asr/src/main/AndroidManifest.xml              "$DST"/plugin/asr/src/main/AndroidManifest.xml
cp -f "$SRC"/plugin/asr/src/main/res/xml/plugin.xml               "$DST"/plugin/asr/src/main/res/xml/plugin.xml
cp -f "$SRC"/plugin/asr/src/main/res/values/strings.xml           "$DST"/plugin/asr/src/main/res/values/strings.xml
cp -f "$SRC"/plugin/asr/src/main/res/values-zh-rCN/strings.xml    "$DST"/plugin/asr/src/main/res/values-zh-rCN/strings.xml
cp -f "$SRC"/plugin/asr/src/main/assets/descriptor.json           "$DST"/plugin/asr/src/main/assets/descriptor.json
mkdir -p "$DST"/plugin/asr/src/main/assets
rsync -a "$SRC"/plugin/asr/src/main/assets/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/" \
      "$DST"/plugin/asr/src/main/assets/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/"

# 应用图标：桥接入口剪影 + 贴纸风 launcher（含删除 adaptive XML 回退 legacy PNG）
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  mkdir -p "$DST"/app/src/main/res/drawable-"$d"
  rsync -a "$SRC"/app/src/main/res/drawable-"$d"/ "$DST"/app/src/main/res/drawable-"$d"/
  mkdir -p "$DST"/app/src/main/res/mipmap-"$d"
  rsync -a --delete "$SRC"/app/src/main/res/mipmap-"$d"/ "$DST"/app/src/main/res/mipmap-"$d"/
done
rm -f "$DST"/app/src/main/res/mipmap-anydpi-v26/ic_launcher*.xml
echo "sync done"

export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# ---- 签名（自用自签；keystore 持久保存在 Windows 侧）----
export SIGN_KEY_FILE="${SIGN_KEY_FILE:-/mnt/e/APP-Project/memeboard/keystore/release.keystore}"
# 签名密码从环境变量读取，禁止硬编码（避免开源后签名密钥泄漏）：
#   运行前先执行  export SIGN_KEY_PWD='你的密码'
if [ -z "${SIGN_KEY_PWD:-}" ]; then
  echo "!! 请先设置环境变量 SIGN_KEY_PWD（签名密码），例如：export SIGN_KEY_PWD='...'"
  exit 1
fi
export SIGN_KEY_ALIAS="${SIGN_KEY_ALIAS:-shiqu}"
# ---- 固定版本号（覆盖 git describe）----
export BUILD_VERSION_NAME=1.0.0

echo "=== [2/4] 检查 keystore ==="
if [ -f "$SIGN_KEY_FILE" ]; then
  echo "keystore OK: $SIGN_KEY_FILE"
else
  echo "!! 未找到 keystore: $SIGN_KEY_FILE（请先运行 keystore 生成步骤）"
fi

echo "=== [3/4] assembleRelease ABI=$ABI ==="
cd "$DST"
/opt/gradle-9.6.1/bin/gradle :app:assembleRelease :plugin:rime:assembleRelease :plugin:asr:assembleRelease -PbuildABI="$ABI" --console=plain --no-daemon
echo "=== gradle exit: $? ==="

echo "=== [4/4] 产物 ==="
ls -la "$DST"/app/build/outputs/apk/release/ 2>/dev/null || echo "无主程序 release 产物"
ls -la "$DST"/plugin/rime/build/outputs/apk/release/ 2>/dev/null || echo "无 rime 插件 release 产物"
ls -la "$DST"/plugin/asr/build/outputs/apk/release/ 2>/dev/null || echo "无 asr 插件 release 产物"
