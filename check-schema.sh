#!/usr/bin/env bash
RIME_APK=$(ls /root/fcitx5-android/plugin/rime/build/outputs/apk/debug/*.apk 2>/dev/null | head -1)
echo "=== rime_ice schema files in APK ==="
unzip -l "$RIME_APK" 2>/dev/null | grep -E "rime_ice|melt_eng|radical_pinyin|symbols_v" | head -10
echo ""
echo "=== Total lua files (all) ==="
unzip -l "$RIME_APK" 2>/dev/null | grep "lua/" | wc -l
echo ""
echo "=== rime_ice key files check ==="
for f in rime_ice.schema.yaml rime_ice.dict.yaml melt_eng.schema.yaml melt_eng.dict.yaml radical_pinyin.schema.yaml radical_pinyin.dict.yaml symbols_v.yaml rime_ice_phrase.txt; do
  unzip -l "$RIME_APK" 2>/dev/null | grep -q "$f" && echo "  FOUND: $f" || echo "  MISSING: $f"
done