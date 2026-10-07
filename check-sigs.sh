#!/usr/bin/env bash
APP_APK=$(ls /root/fcitx5-android/app/build/outputs/apk/debug/org.fcitx.fcitx5.android-*-x86_64-debug.apk 2>/dev/null | head -1)
RIME_APK=$(ls /root/fcitx5-android/plugin/rime/build/outputs/apk/debug/*.apk 2>/dev/null | head -1)

echo "=== Main app signature ==="
unzip -p "$APP_APK" META-INF/*.RSA 2>/dev/null | keytool -printcert 2>&1 | grep -E "Owner|SHA256"

echo ""
echo "=== Rime plugin signature ==="
unzip -p "$RIME_APK" META-INF/*.RSA 2>/dev/null | keytool -printcert 2>&1 | grep -E "Owner|SHA256"