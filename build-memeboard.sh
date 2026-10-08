#!/usr/bin/env bash
set -uo pipefail
# 构建前先同步 Windows 侧源码到 /root 工作副本（含 CSC 引擎 + 插件 + settings 等新增文件，漏同步会导致编译失败）
bash /mnt/e/APP-Project/memeboard/sync-memeboard.sh || { echo "!! 同步失败，终止构建" >&2; exit 1; }
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
cd /root/fcitx5-android
ABI="${1:-x86_64}"
echo "=== build ABI=$ABI ==="
# 给 JVM 设 socket 超时：新增依赖后 aboutlibraries 会联网下载 SPDX license 定义，
# 网络不通时会永久阻塞（无默认超时），设超时让它快速失败后跳过，构建继续。
/opt/gradle-9.6.1/bin/gradle :app:assembleDebug :plugin:csc:assembleDebug -PbuildABI="$ABI" --console=plain --no-daemon \
  -Dsun.net.client.defaultConnectTimeout=10000 \
  -Dsun.net.client.defaultReadTimeout=15000
echo "=== build exit: $? ==="
ls -la /root/fcitx5-android/app/build/outputs/apk/debug/ 2>/dev/null
ls -la /root/fcitx5-android/plugin/csc/build/outputs/apk/debug/ 2>/dev/null
