#!/usr/bin/env bash
set -euo pipefail

export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

DST=/root/fcitx5-android

echo "=== [1/4] Sync from Windows ==="
bash /mnt/e/APP-Project/memeboard/sync-memeboard.sh

echo ""
echo "=== [2/4] Verify source label ==="
grep 'Category("片"' "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/picker/PickerData.kt
grep 'Category("平"' "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/picker/PickerData.kt

echo ""
echo "=== [3/4] Clean all build caches ==="
rm -rf "$DST"/app/build
rm -rf "$DST"/app/.cxx
rm -rf "$DST"/.gradle
rm -rf "$DST"/build
echo "All caches cleaned"

echo ""
echo "=== [4/4] Build x86_64 --rerun-tasks ==="
cd "$DST"
/opt/gradle-9.6.1/bin/gradle :app:assembleDebug -PbuildABI=x86_64 --console=plain --no-daemon --rerun-tasks \
  -Dsun.net.client.defaultConnectTimeout=10000 -Dsun.net.client.defaultReadTimeout=15000 2>&1 | tail -30

echo ""
echo "=== BUILD EXIT: $? ==="

# Copy APK to dist
cp -f "$DST"/app/build/outputs/apk/debug/org.fcitx.fcitx5.android-*-x86_64-debug.apk /mnt/e/APP-Project/memeboard/dist/ 2>/dev/null || echo "(APK copy to dist skipped or failed)"
echo "Done"