#!/usr/bin/env bash
RIME_APK=$(ls /root/fcitx5-android/plugin/rime/build/outputs/apk/debug/*.apk 2>/dev/null | head -1)
echo "Rime plugin APK: $RIME_APK"
echo ""
echo "=== rime-ice cn_dicts ==="
unzip -l "$RIME_APK" 2>/dev/null | grep -E "rime-ice.*cn_dicts.*\.yaml" | head -5
echo ""
echo "=== rime-ice schema ==="
unzip -l "$RIME_APK" 2>/dev/null | grep -E "rime-ice.*\.schema\.yaml" | head -5
echo ""
echo "=== rime-ice lua ==="
unzip -l "$RIME_APK" 2>/dev/null | grep -E "rime-ice.*lua" | head -5
echo ""
echo "=== rime-ice total files ==="
unzip -l "$RIME_APK" 2>/dev/null | grep "rime-ice" | wc -l
echo ""
echo "=== default.yaml schema_list ==="
unzip -p "$RIME_APK" "assets/usr/share/rime-data/default.yaml" 2>/dev/null | head -10