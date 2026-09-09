# MemeBoard：fcitx5-android 集成 MT Photos 表情包输入法开发经验

## 项目定位
可扩展 Android 输入法：从自建 MT Photos（mtmt.tech）拉取贴纸/表情包/emoji，直接发送到微信/QQ 等聊天应用。自用优先 + 开源（不上架、不商业），核心是与 MT Photos 融合。

## 演进路线
PoC 验证 → fork fcitx5-android 集成 MemeBoard 窗口（模拟器验证通过）→ 画廊多轮迭代（搜索/标签/相册/画廊/压缩）→ 规划融合拼音/语音/手写。

## 关键经验

### 1. fcitx5-android 集成架构
- 经典 Views + splitties（非 Compose）。
- 扩展点：InputWindow.ExtendedInputWindow；MemeBoard 窗口挂到 windowManager.view，与 KeyboardWindow 互斥。
- 工具条：KawaiiBar（IdleUi / ButtonsBarUi / titleUi），高度 40dp。

### 2. IME 焦点限制的通用解法
- 现象：IME 主窗口 FLAG_NOT_FOCUSABLE，面板里的 EditText 无法获得输入焦点。
- 解法：自定义 Dialog，类型 TYPE_APPLICATION_ATTACHED_DIALOG，加 FLAG_ALT_FOCUSABLE_IM，token 取 service.window.window.decorView.windowToken；定位用 decorView.getLocationOnScreen 补偿偏移。

### 3. MT Photos API 反向工程
- 鉴权：x-api-key 请求头；图片 URL 需 auth_code。
- 实际响应与官方 OpenAPI 不一致：search/tag 返回 result:[{day,list,ids}]，分组文件列表字段是 list 而非 files；文件 md5 可能为小写 md5；galleryIds 参数未选时传 all、选中时用下划线 join；searchV2 的 searchType 枚举为 v1=综合 / fileName / filePath / OCR / exifDesc / CLIP。
- 方法：解析用户前端 JS（photo.grayzhao.com/static/js/main.*.js）还原真实字段。
- 教训：以实际响应为准，OpenAPI 仅作参考。

### 4. 构建链（WSL2）
- 环境：JDK 21、Android SDK /opt/android-sdk（NDK 28.0.13004108、CMake 3.31.6）、Gradle 9.6.1。
- Windows 源码同步到 WSL 用 .wsl/copy-files.sh。
- 后台构建：nohup wsl.exe ... build.sh :app:assembleDebug > log 2>&1 &（直接后台 shell 工具会死，必须 nohup + bash）。

### 5. 模拟器坑
- adb：D:/Android SDK/platform-tools/adb.exe；模拟器 ASUS_AI2401_A x86_64。
- 重启后默认输入法复位为系统拼音（ROM bug）：settings put secure default_input_method org.fcitx.fcitx5.android/.input.FcitxInputMethodService。
- 大 JSON（timeline 2.5MB）导致 SystemUI ANR：改用 kotlinx.serialization decodeToSequence 流式解析并分批加载（200/批）。

### 6. 融合选型（拼音/语音/手写）
- 拼音：rime-wanxiang 万象拼音（CC BY 4.0）。fcitx5-android 的 plugin/rime 插件已内置 librime/opencc/rime-stroke 引擎，只需部署万象方案到 data/rime。
- 语音：BiBi（说点啥）AIDL（Apache 2.0）。协议为 fxliang 的 IVoiceInputProvider / IVoiceInputCallback（isAvailable / getPreferredConfig / configure / startSession / feedAudio / endStream / cancelSession / stopSession；onReady / onVolumeLevel / onPartialResult / onSegmentFinal / onSessionEnded / onError）。官方 master 无此 AIDL，需自行加入 fork。
- 手写：语燕 gpen（讯飞 libgpen_handwriter.so + 搜狗中文模型，BSD-3 外壳），识别最好、移植最快，但 so 仅 arm64-v8a（x86_64 模拟器无法测试，需真机）；备选 OpenWnn（armeabi legacy）、ML Kit Digital Ink、ONNX。

## 可复用要点
1. IME 焦点限制 → ATTACHED_DIALOG + ALT_FOCUSABLE_IM 方案。
2. 第三方 API 以实际响应 + 前端 JS 为准，别盲信文档。
3. 大 JSON 流式解析（decodeToSequence）防 OOM/ANR。
4. WSL2 长任务用 nohup 后台化。
5. 专有 so（讯飞 gpen、搜狗模型）开源发布需在 README 声明来源与授权边界。
