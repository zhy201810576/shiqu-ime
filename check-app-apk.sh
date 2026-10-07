#!/usr/bin/env bash
APK=/root/fcitx5-android/app/build/outputs/apk/debug/org.fcitx.fcitx5.android-6998502-x86_64-debug.apk
echo "=== opencc (should have rime-ice emoji data) ==="
unzip -l "$APK" 2>/dev/null | grep "opencc" | head -15 || echo "NONE"
echo "=== rime-data schemas ==="
unzip -l "$APK" 2>/dev/null | grep ".schema.yaml" | head -10 || echo "NONE"
echo "=== PickerData check (search for katakana) ==="
unzip -p "$APK" classes*.dex 2>/dev/null | strings | grep "symbol_katakana" | head -3 || echo "NOT IN DEX"
echo "=== PickerData check (search for 片) ==="
unzip -p "$APK" classes*.dex 2>/dev/null | strings | grep -c "片" 2>/dev/null || echo "0"