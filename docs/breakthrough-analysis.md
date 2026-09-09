# MT Photos × 输入法表情包：突破口调研

> 目标：做一个输入法 App，支持从 MT Photos（自建图库）收发"表情包/图片"。

## 结论摘要

1. 用户说的 **MTPhoto** 实为 **MT Photos**（https://mtmt.tech ，杭州相册家科技有限公司），一个带完整 REST API 的照片管理系统。
2. fcitx5-android **有插件系统**，但插件只能做三件事：加载 C++ 输入引擎（fcitx5 addon）、提供后台 Service（hasService）、处理剪贴板**文本**（IClipboardEntryTransformer）。**没有 UI 扩展点，也没有发图/commitContent 的 IPC 通道**。
3. 因此"通过 fcitx5-android 插件发图"走不通；真正可行的突破口是 **fork fcitx5-android**（参考 fxliang/fcitx5-androidrime 的做法），在 app 内部新增一个**图库面板（Compose）**，集成 MT Photos API 拉图 + 发送。
4. 发图有两条技术路线：**commitContent（无缝，体验好）** 与 **剪贴板（兜底，全兼容）**。

---

## 1. fcitx5-android 插件系统能力边界

来源：fcitx5-android 仓库源码 + DeepWiki 7.4-plugin-system。

- 插件是独立 APK，通过 `org.fcitx.fcitx5.android.plugin.MANIFEST` intent 被发现。
- 每个插件提供 `res/xml/plugin.xml` 元数据：`apiVersion`（当前 "1"）、`domain`、`description`、`hasService`。
- 插件核心用途：封装**原生 fcitx5 addon**（anthy/rime/hangul/jyutping/unikey 等输入引擎），经 `fcitx_addon_factory_instance` 动态加载 .so。
- `hasService=true` 时插件可提供后台 Service，经 `plugin.SERVICE` intent 绑定。
- IPC：插件反向绑定 `IFcitxRemoteService`，可注册 `IClipboardEntryTransformer`，在剪贴板**文本**变动时被回调 `transform(clipboardText)`。
- IPC 权限为 `protectionLevel="signature"`：插件必须与主程序**同签名**。
- 键盘 UI（`InputView.kt`、Picker Windows、剪贴板/emoji/符号面板）都在主 app 的 Compose 代码里，**不是插件可扩展点**。

**结论**：插件系统是"输入引擎 + 后台服务 + 剪贴板文本钩子"的扩展面，不是"图库面板 + 发图"的扩展面。

---

## 2. MT Photos API 关键链路

来源：https://mtmt.tech/docs/guide/api_key/ 与 https://mtmt.tech/api/（gateway 为前端主入口）。

鉴权模型：

1. 用户创建 **API Key**（`sk_live_...`，拥有当前账号全部权限）。
2. 用 `POST /auth/auth_code`，body `{"api_key":"sk_live_xxx"}` 换取 `auth_code`（**24 小时有效**，需缓存并自动刷新）。
3. 访问图片 URL 时带 `?auth_code=<URL编码后的值>`。

关键端点（具体以 mtmt.tech/api 最新文档为准）：

| 端点 | 用途 |
| --- | --- |
| `POST /auth/auth_code` | api_key 换 auth_code（24h） |
| `POST /gateway/memory` | 按日期/回忆查照片（返回 cover md5 + ids） |
| `POST /gateway/areaFilesMD5` | 批量由 ids 查文件 id + MD5 |
| `GET /gateway/h220/{md5}` | 小缩略图 |
| `GET /gateway/file/{id}/{md5}` | 大预览图 / 原图（`&type=ori`） |
| `GET /gateway/fileDownload/{id}/{md5}` | 下载原始文件 |
| `/gateway/...` 其他 | 相册、标签、搜索、收藏、分享等 |

---

## 3. 发图两条技术路线（关键决策）

### 路线 A：commitContent / InputContentInfoCompat（推荐）

- 输入法通过 `InputConnectionCompat.commitContent(inputConnection, editorInfo, inputContentInfo, flags, opts)` 提交 `image/*` 内容。
- 需要目标 App 通过 `EditInfo.contentMimeTypes` 声明支持（聊天类 App 大多支持，Gboard 贴纸/GIF 即此机制）。
- 输入法需提供图片内容（ContentProvider / 临时授权 URI），并调用 `InputContentInfoCompat.requestPermission()`。
- 体验：点选即发送，无需切剪贴板粘贴。

### 路线 B：剪贴板兜底

- 输入法把图片写入系统剪贴板（`ClipData` + `image/*` URI），用户手动粘贴。
- 全 App 兼容，但多一步操作；适合作为 A 失败时的降级。

---

## 4. 推荐架构与落地步骤

分层：

1. **MT Photos 客户端层**（Kotlin + OkHttp/Retrofit + Coil）：登录配置、auth_code 缓存与自动刷新、gateway 查询、缩略图/原图加载。
2. **图库面板 UI 层**（Compose）：键盘工具条加一个「图库/表情」入口 → 全屏/半屏面板 → 网格缩略图 → 点选。
3. **发送层**：commitContent 优先，剪贴板兜底。
4. **配置层**：服务端地址 + API Key 设置界面（Keystore 加密存储）。

落地步骤（先 PoC 后集成）：

1. 先做**独立轻量 Android 输入法 Demo**（继承 InputMethodService + Compose 面板），验证最不确定的两环：MT Photos 鉴权/取图 + commitContent 发图。
2. 跑通后再决定：fork fcitx5-android 集成（UI 完善、生态复用），或保持独立输入法（体量小、维护轻）。
3. 处理 auth_code 自动刷新、图片缓存、目标 App 兼容性白名单。

---

## 5. 风险与难点

- MT Photos 的 `auth_code` 仅 24h，需缓存 + 到期自动重换。
- API Key 权限极大，存储必须用 Android Keystore 加密，禁止明文。
- commitContent 的兼容性需按目标 App 实测（微信/QQ/钉钉/Telegram 等表现不一）。
- fork fcitx5-android 的构建门槛高（NDK + CMake + 大量 git submodule），且需持续跟进上游更新。
- 表情包体积与网络：面板需缩略图 + 按需加载原图，避免内存/流量失控。
