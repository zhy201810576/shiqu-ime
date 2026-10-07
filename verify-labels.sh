#!/usr/bin/env bash
APK=$(ls /root/fcitx5-android/app/build/outputs/apk/debug/org.fcitx.fcitx5.android-*-x86_64-debug.apk 2>/dev/null | head -1)
echo "APK: $APK"
echo ""
echo "=== 片 count in dex ==="
unzip -p "$APK" classes*.dex 2>/dev/null | strings -e S -n 2 | grep -c 片
echo ""
echo "=== 平 count in dex ==="
unzip -p "$APK" classes*.dex 2>/dev/null | strings -e S -n 2 | grep -c 平
echo ""
echo "=== 片 context ==="
unzip -p "$APK" classes*.dex 2>/dev/null | strings -e S -n 2 | grep 片
echo ""
echo "=== 平 context ==="
unzip -p "$APK" classes*.dex 2>/dev/null | strings -e S -n 2 | grep 平