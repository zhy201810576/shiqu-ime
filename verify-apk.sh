#!/usr/bin/env bash
APK=/root/fcitx5-android/app/build/outputs/apk/debug/org.fcitx.fcitx5.android-6998502-x86_64-debug.apk
echo "=== opencc rime-ice ==="
unzip -l "$APK" 2>/dev/null | grep -E "emoji.json|emoji.txt|others.txt" | grep opencc | head -5
echo "=== 片 in dex ==="
unzip -p "$APK" classes*.dex 2>/dev/null | strings -n 2 | grep '片' | wc -l
echo "=== 平 in dex ==="
unzip -p "$APK" classes*.dex 2>/dev/null | strings -n 2 | grep '平' | wc -l