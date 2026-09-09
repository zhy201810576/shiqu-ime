# MemeBoard 图库替代相册 + 搜索提示（searchTips）开发经验

本文档总结 MemeBoard（fcitx5-android 集成 MT Photos）两次功能改造的经验：
1. **图库（Gallery）替代相册（Album）**作为表情包数据源；
2. **搜索提示（searchTips）**输入联想。

面向需要集成 MT Photos OpenAPI 的 Android/Kotlin 开发者，涉及 kotlinx.serialization、OkHttp、IME 焦点窗口、WSL 构建与 ADB 真机安装。

## 一、背景与核心语义

- **图库（Gallery）** 是 MT Photos 的存储层单元，一个图库对应一个实际存储位置（NAS 目录/挂载点），通过 `GET /gateway/myGalleryList` 获取，含 `id / name / forUpload`。
- **相册（Album）** 是用户在图库之上手动整理的虚拟视图，通过 `GET /api-album` 获取。

MemeBoard 最初用「相册」承载表情包（用户需先在 MT Photos 里手动建相册、归类）。用户提出：**为表情包建一个专用图库，直接按图库读取全部文件即可，不再依赖相册**。这更简单——图库是「文件夹/存储」层面，天然适合当表情包的容器。

结论：把表情包面板的数据源从相册切换到图库，相册相关链路（`albumList / albumFiles / syncAlbumAutoLink` 及设置入口）全部移除。

## 二、图库替代相册实现

### 2.1 关键接口：`GET /gateway/filesInTimelineV2`

用于「列出图库内所有文件（时间线）」，官方 OpenAPI 定义：

- 参数（query，均可选）：
  - `galleryIds`：多个图库 ID，用**下划线**分隔（如 `1_2_3`）；不传 = 全部图库。
  - `galleryId`：单个图库 ID。
  - `_t`：时间戳。
- 响应：顶层 **array**，元素 `{ id, MD5, fileName, tokenAt, fileType }`。

```kotlin
@OptIn(ExperimentalSerializationApi::class)
suspend fun galleryFiles(galleryIds: List<Long>): List<MtFile> = withContext(Dispatchers.IO) {
    val url = buildString {
        append(root()).append("/gateway/filesInTimelineV2")
        if (galleryIds.isNotEmpty()) append("?galleryIds=").append(galleryIds.joinToString("_"))
    }
    val req = Request.Builder().url(url).header("x-api-key", apiKey).get().build()
    httpClient.newCall(req).execute().use { resp ->
        if (!resp.isSuccessful) throw IllegalStateException("request failed: HTTP " + resp.code)
        resp.body?.byteStream()?.use { s -> json.decodeToSequence<MtFile>(s).toList() } ?: emptyList()
    }
}
```

要点：图库文件列表可能很大（几万张），沿用 `decodeToSequence` 流式解析防 OOM（与相册 `albumFiles` 同款模式）。

### 2.2 数据层切换

- Repository 新增 `loadGalleries()`：`galleryIds` 为空 → 加载全部图库，否则加载已选图库。
- Window 浏览模式（未选标签时）从 `loadAlbums()` 改为 `loadGalleries()`。
- 设置界面只保留「图库 + 标签」选择器，图库未选时摘要显示「全部图库」。

## 三、搜索提示（searchTips）实现

### 3.1 关键接口：`POST /gateway/searchTips`

- 请求体：`{ key: string, type?: "people" | "tag" | "llm_tag" }`，`type` 不传返回全部。
- 响应：array，元素 `{ id, name, type }`。

**关键坑：`id` 是 `oneOf(number | string)` 联合类型。** 若模型里把 `id` 声明为 `Long`，遇到字符串 id 会反序列化崩溃；声明为 `String`，遇到数字 id 同样崩溃。最稳妥的做法是**模型里根本不声明 `id`**（`ignoreUnknownKeys=true` 会自动忽略），只保留 `name` 和 `type`——联想展示/点击只用 `name`，`type` 用于区分前缀：

```kotlin
@Serializable
data class MtSearchTip(val name: String = "", val type: String = "")
```

### 3.2 UI 交互

- 搜索框加 `TextWatcher`，`afterTextChanged` 里**防抖 300ms**（`delay(300)`，每次新输入先 `cancel()` 旧 Job）再请求 `searchTips`，避免每个字符都打请求。
- 用 `ListView` + `ArrayAdapter` 展示提示，带类型前缀（`人物 · xxx` / `标签 · xxx` / `智能 · xxx`）。
- 点击提示 → 直接 `doSearch(tip.name)`。
- Dialog `setOnDismissListener` 里记得 `tipJob?.cancel()`，防止关闭后还在请求。

### 3.3 编译坑：`dp()` 的 receiver 类型不匹配

在 `ArrayAdapter.getView()` 匿名对象里裸调 `dp(14)` 会编译失败，因为 `dp()` 是 `Context.dp()` / `View.dp()` 的扩展，而匿名对象的 `this` 既不是 Context 也不是 View：

```
Unresolved reference. None of the following candidates is applicable because of a receiver type mismatch
```

修复：显式指定 receiver，如 `service.dp(14)`（service 是 Context）或 `view.dp(14)`。

## 四、构建与真机部署

### 4.1 WSL 提权编译

- WSL 报 `E_ACCESS_DENIED` 时，根因是 `LxssManager` 服务处于 `Stopped`。需用 `sandbox_permissions=danger-full-access` 提权后 `Start-Service LxssManager`（普通权限会报 `Cannot open 'LxssManager' service`）。
- 构建必须 `wsl.exe -u root`（默认用户访问 `/root` 会 Permission denied）。
- Windows 源码与 WSL 副本 `/root/fcitx5-android` 是两份，改动需先经 `/mnt/e` 挂载 `cp` 同步。
- 构建命令：`cd /root/fcitx5-android && /opt/gradle-9.6.1/bin/gradle :app:assembleDebug -PbuildABI=x86_64|arm64-v8a --console=plain --no-daemon`。
- 产物 `app/build/outputs/apk/debug/org.fcitx.fcitx5.android-<commit>-<abi>-debug.apk`，cp 回 `dist/` 重命名为 `fcitx5-memeboard-<abi>-debug.apk`。

### 4.2 ADB 真机安装

- 有多设备时务必 `adb -s <serial>` 指定，避免误装到模拟器（真机 `b68a5ae7`，模拟器 `emulator-5554`）。
- 覆盖安装用 `install -r`，会**保留应用数据**（MemeBoard 的服务器地址 / API Key / 图库选择都不丢）。
- HyperOS 首次安装会被 `INSTALL_FAILED_USER_RESTRICTED` 拦截，需在手机端开启「USB 安装」开关；覆盖更新通常无需再开。
- 验证：`adb -s <serial> shell "dumpsys package org.fcitx.fcitx5.android | grep -E 'versionName|lastUpdateTime'"`。

## 五、可复用要点速查

1. 图库/相册语义分离：存储层用 Gallery（`filesInTimelineV2`），整理层用 Album，表情包场景直接用图库。
2. `filesInTimelineV2` 的 `galleryIds` 是下划线分隔，空参=全部图库；响应是顶层 array，用流式解析。
3. `searchTips` 的 `id` 是 `oneOf(number|string)`，用「不声明该字段」规避反序列化崩溃。
4. 搜索联想 = TextWatcher + 防抖 300ms + ListView；关闭 Dialog 时 cancel 请求 Job。
5. 匿名对象里调 `dp()` 需显式 receiver（`service.dp()`）。
6. 提权 + `wsl -u root` 是 fcitx5-android 构建的硬性要求；`adb -s` + `install -r` 是真机安全部署的硬性要求。
