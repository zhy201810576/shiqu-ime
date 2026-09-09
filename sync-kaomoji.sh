#!/usr/bin/env bash
set -euo pipefail
SRC=/mnt/e/APP-Project/memeboard/fcitx5-android
DST=/root/fcitx5-android

# 同步 picker 目录（颜文字改进）
mkdir -p "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/picker/
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/picker/*.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/picker/

# 同步 assets（颜文字数据文件）
mkdir -p "$DST"/app/src/main/assets/
cp -f "$SRC"/app/src/main/assets/kaomoji_data.json \
      "$DST"/app/src/main/assets/kaomoji_data.json

# 同步其他常用文件（来自 sync-memeboard.sh）
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/memeboard/*.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/memeboard/ 2>/dev/null || true
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/link/BridgePrewarmer.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/link/BridgePrewarmer.kt 2>/dev/null || true
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/FcitxInputMethodService.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/FcitxInputMethodService.kt 2>/dev/null || true
cp -f "$SRC"/app/src/main/res/values/strings.xml \
      "$DST"/app/src/main/res/values/strings.xml 2>/dev/null || true
cp -f "$SRC"/app/src/main/res/values-zh-rCN/strings.xml \
      "$DST"/app/src/main/res/values-zh-rCN/strings.xml 2>/dev/null || true

# 同步 AndroidManifest（新 Activity 注册需要）
cp -f "$SRC"/app/src/main/AndroidManifest.xml \
      "$DST"/app/src/main/AndroidManifest.xml 2>/dev/null || true

# 同步 TitleUi（扩展栏宽度约束修复）
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/bar/ui/TitleUi.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/bar/ui/TitleUi.kt 2>/dev/null || true

echo "=== kaomoji sync done ==="
