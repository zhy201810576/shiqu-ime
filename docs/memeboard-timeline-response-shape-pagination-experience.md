# MemeBoard 图库时间线响应结构与分页加载经验

本文档总结 MemeBoard（fcitx5-android 集成 MT Photos）本轮「图库时间线接口响应结构 vs API 文档不符」的排查与「分页加载」落地经验。面向集成 MT Photos OpenAPI 的 Android/Kotlin 开发者，涉及 kotlinx.serialization、OkHttp、RecyclerView 分页、WSL 构建与 ADB 真机部署。

## 一、背景与问题现象

用户反馈：图库面板默认显示「最近使用」，但「最近使用」为空时没有回退到图库；且即使回退到图库，面板也几乎不显示图片（只出现 1 张 / 「未找到照片」）。

排查链路：

1. 抓 `adb logcat`，看到 `galleryFiles -> 1` —— `filesInTimelineV2` 只「解析出」1 个文件。
2. 读 SharedPreferences（`run-as`）发现用户在图库选择器里勾选了图库 id=5「表情包」。
3. 加 `peekBody` 日志打印响应体头部，才定位到真正的根因：**响应结构根本不是 API 文档描述的那样**。

## 二、关键发现

### 2.1 响应结构 vs API 文档严重不符

OpenAPI 文档（`docs/api-spec.md`）声称 `GET /gateway/filesInTimelineV2` 返回**顶层扁平数组**：

```json
[{"id":1,"MD5":"...","fileName":"...","tokenAt":"...","fileType":"..."}, ...]
```

**实际返回**的是「对象包裹 + 按天分组」结构：

```json
{"result":[
  {"day":"2026-09-03","addr":"","list":[
    {"id":39300,"status":2,"fileType":"PNG","width":1436,"height":1992,"MD5":"a349a8b7..."},
    {"id":39290,"status":2,"fileType":"JPEG","width":287,"height":250,"MD5":"276e707b..."}
  ]}
]}
```

关键差异：

- 顶层是 `{result: [...]}` 对象，不是数组。
- `result` 里是**按天分组**的对象，文件列表在每组的 `list` 字段里（不是顶层扁平）。
- 这个结构**与 search / tagFiles 的响应一致**（`MtFileListResponse` 的 `result` 分组形态），所以应该复用同一套 `parseFilesResponse` 解析。

### 2.2 文件对象没有 fileName 字段

`filesInTimelineV2` 返回的文件对象只有 `id / status / fileType / width / height / MD5`，**没有 `fileName`**。

但这不影响展示：缩略图用 `thumbUrl(md5)`、下载用 `downloadPreview(id, md5, ...)` 都只依赖 `MD5`。`fileName` 仅在 `guessExt` 猜扩展名时用，缺失时回退到 `Content-Type`。所以模型里 `fileName` 保持空字符串、`filter { it.md5.isNotEmpty() }` 即可。

### 2.3 「流式加载」的真实语义 = 分页加载，不是 JSON 流式解析

用户口中的「流式加载」指的是：**不要一次性加载/显示所有图片，初始显示一批，下滑时自动加载更多**。

这其实是 UI 层的分页逻辑，并非数据层的 JSON 流式解析：

- `submitFiles` 只 `submit(files.take(200))`（初始 200 张）。
- `RecyclerView.OnScrollListener` 在 `findLastVisibleItemPosition() >= itemCount - 12` 时触发 `loadMore()`，`adapter.append` 增量追加下一批 200 张。
- 缩略图由 Coil 懒加载（只加载可见项）。

## 三、正确实现

### 3.1 数据层：复用 parseFilesResponse 统一解析

`galleryFiles` 最终回退为一次性读元数据 + 复用统一解析：

```kotlin
suspend fun galleryFiles(galleryIds: List<Long>): List<MtFile> = withContext(Dispatchers.IO) {
    val url = buildString {
        append(root()).append("/gateway/filesInTimelineV2")
        if (galleryIds.isNotEmpty()) append("?galleryIds=").append(galleryIds.joinToString("_"))
    }
    val req = Request.Builder().url(url).header("x-api-key", apiKey).get().build()
    val files = httpClient.newCall(req).execute().use { resp ->
        if (!resp.isSuccessful) throw IllegalStateException("request failed: HTTP " + resp.code)
        val body = resp.body?.string() ?: return@withContext emptyList()
        parseFilesResponse(json.decodeFromString<MtFileListResponse>(body))
    }
    Timber.d("MemeBoard galleryFiles %s -> %d", url.removePrefix(root()), files.size)
    files
}
```

`parseFilesResponse` 兼容 `{list:[...]}` 与 `{result:[分组|扁平]}` 两种形态（与 search/tagFiles 共用）。

### 3.2 图库范围 = 设置中勾选的图库

「全部」视图加载的是**已选图库**（`MemeBoardPrefs.getGalleryIds`），未勾选才拉全部图库：

```kotlin
suspend fun loadGalleries(): List<MtFile> {
    val galleryIds = MemeBoardPrefs.getGalleryIds(context).toList()
    return client().galleryFiles(galleryIds)
}
```

顶部 chip 增加「全部」（默认高亮，`viewMode == BROWSE && selectedTagId == null`），点击回到浏览全部图库。

## 四、踩坑记录

### 4.1 kotlinx.serialization 的 decodeToSequence 无法解析「对象包裹的数组」

`Json.decodeToSequence` 只能流式解析**顶层 JSON 数组** `[...]`。遇到 `{"result":[...]}` 对象包裹时会失败/解析出空。

曾尝试用 `PushbackInputStream` 手动跳过 `{"result":` 前缀再 `decodeToSequence<MtResultGroup>`，结果报 JSON 解析错误。

**结论**：对象包裹的分组响应，直接用 `decodeFromString` + 兼容模型一次性解析最稳妥。元数据 JSON 通常只有几 MB（几万张图的元数据），OOM 风险低；真正的大头是图片缩略图，由 Coil 懒加载，不需要也不应该由 JSON 层承担「流式」。

### 4.2 okio 的 `Source.inputStream()` 扩展在部分版本不存在

想用 `resp.body.source().inputStream()` 从当前位置构造 InputStream 时，`import okio.inputStream` 编译报 `Unresolved reference 'inputStream'`——项目所用 okio 版本没有这个扩展。不要依赖它；直接用 `ResponseBody.byteStream()` / `string()`。

### 4.3 加载失败异常堆栈丢失

原 `showLoadFailed` 只弹 toast、不打堆栈，导致 JSON 解析异常被吞掉，只能看到「加载失败」而看不到原因。排查时务必先给加载失败路径补 `Timber.e(e, "...")`，否则每次都要靠 `peekBody` 打印响应体盲猜。

## 五、可复用要点速查

1. **先抓响应体，再信 API 文档**：用 `Timber.d` 打印 `resp.peekBody(2048).string()` 确认真实结构；`filesInTimelineV2` 实际是 `{result:[{day,list:[...]}]}`，不是文档写的扁平数组。
2. 分组响应统一走 `parseFilesResponse`（`MtFileListResponse` + `MtResultGroup`），别为每个接口各写一套扁平解析。
3. 文件对象可能没有 `fileName`，靠 `MD5` 做内容指纹即可；`filter { md5.isNotEmpty() }` 兜底。
4. 「分页加载」在 UI 层做：初始 `take(200)` + 下滑 `append` 下一批；缩略图靠 Coil 懒加载，不要在图库元数据层追求 JSON 流式。
5. `decodeToSequence` 只认顶层数组，对象包裹的响应用它必踩坑。
6. 加载失败路径务必打堆栈日志，否则排查成本翻倍。
7. 覆盖安装判断签名：先 `dumpsys package` 看 `versionName`（release 固定 `1.0.0`、debug 是 build 号），同签名才 `install -r`，否则需卸载重装。
