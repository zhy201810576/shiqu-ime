#!/usr/bin/env bash
# 桥接 APK（gpen 手写）release 打包脚本 —— 在 WSL2 内以 root 执行
# 用法: wsl -u root bash /mnt/e/APP-Project/memeboard/build-bridges-release.sh
#   注意：工作副本位于 /root/gpen-bridge，必须用 root
#   （asr 语音已迁移为进程内插件 plugin/asr，随主程序 build-release.sh 打包）
set -uo pipefail

SRC=/mnt/e/APP-Project/memeboard

export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# ---- 签名（与主程序 / rime 插件共用同一个 shiqu keystore）----
export SIGN_KEY_FILE="${SIGN_KEY_FILE:-/mnt/e/APP-Project/memeboard/keystore/release.keystore}"
# 签名密码从环境变量读取，禁止硬编码（避免开源后签名密钥泄漏）：
#   运行前先执行  export SIGN_KEY_PWD='你的密码'
if [ -z "${SIGN_KEY_PWD:-}" ]; then
  echo "!! 请先设置环境变量 SIGN_KEY_PWD（签名密码），例如：export SIGN_KEY_PWD='...'"
  exit 1
fi
export SIGN_KEY_ALIAS="${SIGN_KEY_ALIAS:-shiqu}"

echo "=== [1/3] 同步 build.gradle.kts（签名配置）==="
cp -f "$SRC"/gpen-bridge/app/build.gradle.kts /root/gpen-bridge/app/build.gradle.kts
echo "sync done"

echo "=== [2/3] build gpen-bridge release ==="
cd /root/gpen-bridge
/opt/gradle-9.6.1/bin/gradle :app:assembleRelease --console=plain --no-daemon
echo "=== gpen exit: $? ==="

echo "=== [3/3] 产物 ==="
ls -la /root/gpen-bridge/app/build/outputs/apk/release/ 2>/dev/null || echo "无 gpen release 产物"
