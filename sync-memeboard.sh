#!/usr/bin/env bash
set -euo pipefail
SRC=/mnt/e/APP-Project/memeboard/fcitx5-android
DST=/root/fcitx5-android
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/memeboard/*.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/memeboard/
# GIF 重编码器（NeuQuant / LZW / AnimatedGifEncoder）
mkdir -p "$DST"/app/src/main/java/org/fcitx/fcitx5/android/memeboard/gif
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/memeboard/gif/*.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/memeboard/gif/
cp -f "$SRC"/app/src/test/java/org/fcitx/fcitx5/android/memeboard/*.kt \
      "$DST"/app/src/test/java/org/fcitx/fcitx5/android/memeboard/
# 语音纠错评测样本采集器测试（link 包 JVM 单测）
mkdir -p "$DST"/app/src/test/java/org/fcitx/fcitx5/android/link
cp -f "$SRC"/app/src/test/java/org/fcitx/fcitx5/android/link/*.kt \
      "$DST"/app/src/test/java/org/fcitx/fcitx5/android/link/
# 符号面板新增分类图标（片假名 / 平假名 drawable vector）
cp -f "$SRC"/app/src/main/res/drawable/symbol_katakana.xml \
      "$DST"/app/src/main/res/drawable/symbol_katakana.xml
cp -f "$SRC"/app/src/main/res/drawable/symbol_hiragana.xml \
      "$DST"/app/src/main/res/drawable/symbol_hiragana.xml
# PickerData（符号/颜文字数据）
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/picker/PickerData.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/picker/PickerData.kt
# 依赖目录与 app 依赖声明（android-gif-drawable）
cp -f "$SRC"/gradle/libs.versions.toml "$DST"/gradle/libs.versions.toml
cp -f "$SRC"/app/build.gradle.kts "$DST"/app/build.gradle.kts
# settings.gradle.kts 注册 :plugin:csc 模块（漏同步则 WSL 里 csc 插件无法被构建）
cp -f "$SRC"/settings.gradle.kts "$DST"/settings.gradle.kts
# 语音引擎（进程内 SpeechEngine + 控制器，取代旧桥接预热器）
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/link/AsrEngineController.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/link/AsrEngineController.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/link/SpeechEngine.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/link/SpeechEngine.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/link/AsrRescore.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/link/AsrRescore.kt
# 中文数字→阿拉伯数字归一化（ITN），AsrRescore.kt 引用，漏同步会导致 :app 编译失败
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/link/CnNumberNormalizer.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/link/CnNumberNormalizer.kt
# 语音纠错评测样本采集器（Step 0：攒真实 ASR 错误样本）
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/link/AsrEvalCollector.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/link/AsrEvalCollector.kt
# 端侧 CSC 纠错引擎（MacBERT4CSC ONNX：分词器 / 推理 / 控制器）。
# AsrRescore.kt 引用这些类，漏同步会导致 :app 编译失败（unresolved reference MacBert4CscController / CscCorrection）。
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/link/MacBertTokenizer.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/link/MacBertTokenizer.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/link/MacBert4CscEngine.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/link/MacBert4CscEngine.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/link/MacBert4CscController.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/link/MacBert4CscController.kt
# 端侧 CSC 模型插件（MacBERT4CSC INT8 ONNX + vocab；模型用 rsync 增量同步，119MB 大文件）
mkdir -p "$DST"/plugin/csc/src/main/res/xml
mkdir -p "$DST"/plugin/csc/src/main/res/values
mkdir -p "$DST"/plugin/csc/src/main/res/values-zh-rCN
mkdir -p "$DST"/plugin/csc/src/main/assets/csc
cp -f "$SRC"/plugin/csc/build.gradle.kts                          "$DST"/plugin/csc/build.gradle.kts
cp -f "$SRC"/plugin/csc/proguard-rules.pro                        "$DST"/plugin/csc/proguard-rules.pro
cp -f "$SRC"/plugin/csc/src/main/AndroidManifest.xml              "$DST"/plugin/csc/src/main/AndroidManifest.xml
cp -f "$SRC"/plugin/csc/src/main/res/xml/plugin.xml               "$DST"/plugin/csc/src/main/res/xml/plugin.xml
cp -f "$SRC"/plugin/csc/src/main/res/values/strings.xml           "$DST"/plugin/csc/src/main/res/values/strings.xml
cp -f "$SRC"/plugin/csc/src/main/res/values-zh-rCN/strings.xml    "$DST"/plugin/csc/src/main/res/values-zh-rCN/strings.xml
# 空数据描述符（同 asr）：让 DataManager 把 csc 登记为已加载插件，否则「检测到插件更改」永不消失
cp -f "$SRC"/plugin/csc/src/main/assets/descriptor.json           "$DST"/plugin/csc/src/main/assets/descriptor.json
rsync -a "$SRC"/plugin/csc/src/main/assets/csc/ "$DST"/plugin/csc/src/main/assets/csc/
# JNI 桥（native-lib.cpp，含 CSC/ASR 相关 JNI；需随 Windows 侧同步）
cp -f "$SRC"/app/src/main/cpp/native-lib.cpp \
      "$DST"/app/src/main/cpp/native-lib.cpp
# ORT C API 头文件（MacBERT4CSC 经 native-lib 用 dlopen 复用 sherpa 的 libonnxruntime.so）
mkdir -p "$DST"/app/src/main/cpp/onnxruntime
cp -f "$SRC"/app/src/main/cpp/onnxruntime/*.h \
      "$DST"/app/src/main/cpp/onnxruntime/
cp -f "$SRC"/app/src/main/cpp/CMakeLists.txt "$DST"/app/src/main/cpp/CMakeLists.txt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/input/FcitxInputMethodService.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/input/FcitxInputMethodService.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/ui/main/settings/SettingsRoute.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/ui/main/settings/SettingsRoute.kt
cp -f "$SRC"/app/src/main/java/org/fcitx/fcitx5/android/ui/main/MainFragment.kt \
      "$DST"/app/src/main/java/org/fcitx/fcitx5/android/ui/main/MainFragment.kt
cp -f "$SRC"/app/src/main/res/values/strings.xml \
      "$DST"/app/src/main/res/values/strings.xml
cp -f "$SRC"/app/src/main/res/values-zh-rCN/strings.xml \
      "$DST"/app/src/main/res/values-zh-rCN/strings.xml
cp -f "$SRC"/app/src/main/res/values-zh-rTW/strings.xml \
      "$DST"/app/src/main/res/values-zh-rTW/strings.xml
cp -f "$SRC"/build-logic/convention/src/main/kotlin/Versions.kt \
      "$DST"/build-logic/convention/src/main/kotlin/Versions.kt
# 应用图标：桥接入口剪影 + 贴纸风 launcher（含删除 adaptive XML 回退 legacy PNG）
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  mkdir -p "$DST"/app/src/main/res/drawable-"$d"
  cp -f "$SRC"/app/src/main/res/drawable-"$d"/ic_memeboard_bridge.png \
        "$DST"/app/src/main/res/drawable-"$d"/ic_memeboard_bridge.png
  mkdir -p "$DST"/app/src/main/res/mipmap-"$d"
  rsync -a --delete "$SRC"/app/src/main/res/mipmap-"$d"/ "$DST"/app/src/main/res/mipmap-"$d"/
done
rm -f "$DST"/app/src/main/res/mipmap-anydpi-v26/ic_launcher*.xml
echo "=== sync done ==="
