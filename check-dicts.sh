#!/usr/bin/env bash
echo "=== rime-ice cn_dicts ==="
ls /root/fcitx5-android/plugin/rime/src/main/cpp/rime-ice/cn_dicts/ 2>&1
echo ""
echo "=== rime-ice en_dicts ==="
ls /root/fcitx5-android/plugin/rime/src/main/cpp/rime-ice/en_dicts/ 2>&1
echo ""
echo "=== rime-ice lua ==="
ls /root/fcitx5-android/plugin/rime/src/main/cpp/rime-ice/lua/ 2>&1
echo ""
echo "=== rime-ice schema files ==="
ls /root/fcitx5-android/plugin/rime/src/main/cpp/rime-ice/*.yaml /root/fcitx5-android/plugin/rime/src/main/cpp/rime-ice/*.txt 2>&1
echo ""
echo "=== wanxiang has cn_dicts? ==="
ls /root/fcitx5-android/plugin/rime/src/main/cpp/wanxiang/cn_dicts/ 2>&1
echo ""
echo "=== RIME APK cn_dicts ==="
RIME_APK=$(ls /root/fcitx5-android/plugin/rime/build/outputs/apk/debug/*.apk 2>/dev/null | head -1)
unzip -l "$RIME_APK" 2>/dev/null | grep "cn_dicts" | head -10
echo ""
echo "=== RIME APK lua (non-wanxiang) ==="
unzip -l "$RIME_APK" 2>/dev/null | grep "lua/" | grep -v "wanxiang" | head -10