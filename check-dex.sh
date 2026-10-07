#!/usr/bin/env bash
APK=/root/fcitx5-android/app/build/outputs/apk/debug/org.fcitx.fcitx5.android-6998502-x86_64-debug.apk
echo "=== dex files ==="
unzip -l "$APK" 2>/dev/null | grep '.dex' | awk '{print $4}' | head -10
echo "=== symbol_katakana ==="
for d in $(unzip -l "$APK" 2>/dev/null | grep '.dex' | awk '{print $4}'); do
  c=$(unzip -p "$APK" "$d" 2>/dev/null | strings -n 5 | grep -c 'symbol_katakana')
  echo "$d: $c"
done
echo "=== checking all dexs together ==="
unzip -p "$APK" "*.dex" 2>/dev/null | strings -n 5 | grep -c 'symbol_katakana'