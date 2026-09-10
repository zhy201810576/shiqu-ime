#!/usr/bin/env bash
set -euo pipefail
SRC=/mnt/e/APP-Project/memeboard/fcitx5-android
DST=/root/fcitx5-android
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/memeboard/*.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/memeboard/
# GIF 重编码器（NeuQuant / LZW / AnimatedGifEncoder）
mkdir -p "$DST"/app/src/main/java/org/fcitx/fcitx5/android/memeboard/gif
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/memeboard/gif/*.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/memeboard/gif/
cp -f "$SRC"/app/src/test/java/org/fcitx/fcitx5/android/memeboard/*.kt \
      "$DST"/app/src/test/java/org/fcitx/fcitx5/android/memeboard/
# 依赖目录与 app 依赖声明（android-gif-drawable）
cp -f "$SRC"/gradle/libs.versions.toml "$DST"/gradle/libs.versions.toml
cp -f "$SRC"/app/build.gradle.kts "$DST"/app/build.gradle.kts
# 语音引擎（进程内 SpeechEngine + 控制器，取代旧桥接预热器）
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/link/AsrEngineController.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/link/AsrEngineController.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/link/SpeechEngine.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/link/SpeechEngine.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/FcitxInputMethodService.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/FcitxInputMethodService.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/ui/main/settings/SettingsRoute.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/ui/main/settings/SettingsRoute.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/ui/main/MainFragment.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/ui/main/MainFragment.kt
cp -f "$SRC"/app/src/main/res/values/strings.xml \
      "$DST"/app/src/main/res/values/strings.xml
cp -f "$SRC"/app/src/main/res/values-zh-rCN/strings.xml \
      "$DST"/app/src/main/res/values-zh-rCN/strings.xml
cp -f "$SRC"/app/src/main/res/values-zh-rTW/strings.xml \
      "$DST"/app/src/main/res/values-zh-rTW/strings.xml
cp -f "$SRC"/build-logic/convention/src/main/kotlin/Versions.kt \
      "$DST"/build-logic/convention/src/main/kotlin/Versions.kt
# 应用图标：桥接入口剪影 + 贴纸风 launcher（含删除 adaptive XML 回退 legacy PNG）
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  mkdir -p "$DST"/app/src/main/res/drawable-"$d"
  cp -f "$SRC"/app/src/main/res/drawable-"$d"/ic_memeboard_bridge.png \
        "$DST"/app/src/main/res/drawable-"$d"/ic_memeboard_bridge.png
  mkdir -p "$DST"/app/src/main/res/mipmap-"$d"
  rsync -a --delete "$SRC"/app/src/main/res/mipmap-"$d"/ "$DST"/app/src/main/res/mipmap-"$d"/
done
rm -f "$DST"/app/src/main/res/mipmap-anydpi-v26/ic_launcher*.xml
echo "=== sync done ==="
