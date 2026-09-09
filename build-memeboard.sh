#!/usr/bin/env bash
set -uo pipefail
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
cd /root/fcitx5-android
ABI="${1:-x86_64}"
echo "=== build ABI=$ABI ==="
/opt/gradle-9.6.1/bin/gradle :app:assembleDebug -PbuildABI="$ABI" --console=plain --no-daemon
echo "=== build exit: $? ==="
ls -la /root/fcitx5-android/app/build/outputs/apk/debug/ 2>/dev/null
