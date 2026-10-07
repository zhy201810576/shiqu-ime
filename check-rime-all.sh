#!/usr/bin/env bash
RIME_APK=$(ls /root/fcitx5-android/plugin/rime/build/outputs/apk/debug/*.apk 2>/dev/null | head -1)
echo "=== All rime-data files in APK ==="
unzip -l "$RIME_APK" 2>/dev/null | grep "rime-data" | head -40
echo ""
echo "=== Total rime-data files ==="
unzip -l "$RIME_APK" 2>/dev/null | grep "rime-data" | wc -l
echo ""
echo "=== wanxiang files ==="
unzip -l "$RIME_APK" 2>/dev/null | grep "wanxiang" | head -10
echo "=== wanxiang count ==="
unzip -l "$RIME_APK" 2>/dev/null | grep "wanxiang" | wc -l
echo ""
echo "=== Source rime-ice dir exists? ==="
ls -la /root/fcitx5-android/plugin/rime/src/main/cpp/rime-ice/cn_dicts/ 2>&1 | head -5