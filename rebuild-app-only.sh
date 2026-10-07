#!/usr/bin/env bash
set -euo pipefail

export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

SRC=/mnt/e/APP-Project/memeboard/fcitx5-android
DST=/root/fcitx5-android

echo "=== [1/3] Sync + verify PickerData label ==="
bash /mnt/e/APP-Project/memeboard/sync-memeboard.sh
echo "WSL PickerData label check:"
grep 'Category.*片\|Category.*平' "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/picker/PickerData.kt || echo "LABEL NOT FOUND!"

echo "=== [2/3] Clean Kotlin build cache ==="
# Clean Kotlin compiled output to force full recompilation
rm -rf "$DST"/app/build/tmp/kotlin-classes
rm -rf "$DST"/app/build/intermediates
rm -rf "$DST"/app/build/outputs
echo "Kotlin cache cleaned"

echo "=== [3/3] Build app x86_64 ==="
cd "$DST"
/opt/gradle-9.6.1/bin/gradle :app:assembleDebug -PbuildABI=x86_64 --console=plain --no-daemon \
  -Dsun.net.client.defaultConnectTimeout=10000 -Dsun.net.client.defaultReadTimeout=15000
echo "=== exit: $? ==="

echo "=== Copy to dist ==="
cp -f "$DST"/app/build/outputs/apk/debug/org.fcitx.fcitx5.android-*-x86_64-debug.apk /mnt/e/APP-Project/memeboard/dist/
echo "Done"