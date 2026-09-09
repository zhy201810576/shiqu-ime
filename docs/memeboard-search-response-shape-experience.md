# MemeBoard：MT Photos 搜索响应结构不一致 + 搜索页目标 App 快照

> 面向：集成 MT Photos OpenAPI、以及在 IME 里做「跨 Activity 传递输入目标」的 Kotlin/Android 开发者。
> 两条经验：① `searchCLIPV2` 实际响应与 OpenAPI 文档不一致，导致「能搜到但解析出 0 条」；② 独立搜索 Activity 要在启动那一刻快照「当前输入目标 App」的包名。

## 一、背景

MemeBoard 搜索页（独立 Activity）从 MT Photos 拉图，用户反馈「LLM 搜索只能命中固定词汇，『哈哈大笑』这种语义词搜不到」。而同样的词在 MT Photos 官方前端里能搜到。

排查经历了两轮错误的假设（先怀疑请求参数、再怀疑接口门控），最终用 logcat 抓服务端原始响应才定位到真凶——**服务端其实返回了结果，是客户端解析器把它们丢掉了**。

## 二、经验 1：searchCLIPV2 响应结构不一致（真凶）

### 2.1 现象与日志

```text
MemeBoard resp /gateway/searchCLIPV2 => {"result":[{"id":37436,"fileName":"IMG_20220327_205141.gif",...,"MD5":"1f105705...",...},...
MemeBoard clipSearch '哈哈大笑' -> 0   ← 服务端有结果，客户端解析出 0 条
```

### 2.2 根因

MT Photos 的「文件列表」接口返回的 `result` 字段有**两种形态**：

| 接口 | `result` 形态 |
|------|--------------|
| `searchCLIPV2` | **扁平文件数组** `[{id,fileName,MD5,...}]` |
| `searchV2` / `tagFiles` | **分组数组** `[{day,list|files}]` |

官方 OpenAPI 里 `searchCLIPV2` 的 200 响应写的是 `{list:[...], totalCount}`，与实际返回的 `{result:[...]}` 又对不上——这已经是第三次踩「OpenAPI 与实际响应不一致」的坑了。

我们原本的解析器只按分组结构展开（`result[].list ?: result[].files`），把扁平文件数组的元素当成分组对象去取 `list`/`files`，自然取不到任何文件。

### 2.3 修复：一个模型兼容两种形态

给分组模型补上文件字段，用「是否有 md5/id」判定元素是文件还是分组：

```kotlin
@Serializable
data class MtResultGroup(
    @SerialName("id") val id: Long = 0,
    @SerialName("MD5") @JsonNames("md5") val md5: String = "",
    @SerialName("fileName") val fileName: String = "",
    val list: List<MtFile>? = null,
    val files: List<MtFile>? = null,
) {
    /** 该元素本身是否为一个文件（扁平结构），而非分组容器。 */
    val isFile: Boolean get() = md5.isNotEmpty() || fileName.isNotEmpty() || id != 0L
}

private fun parseFilesResponse(resp: MtFileListResponse): List<MtFile> {
    val files = resp.list
        ?: resp.result?.flatMap { group ->
            if (group.isFile) listOf(MtFile(group.id, group.md5, group.fileName))
            else group.list ?: group.files ?: emptyList()
        }
        ?: emptyList()
    return files.filter { it.md5.isNotEmpty() }
}
```

### 2.4 请求侧的正确姿势（顺便澄清）

前端调 `searchCLIPV2` 时请求体带 `searchType: "CLIP"`、`count: 200`；服务端按配置自动选择 LLM 描述向量或 CLIP 向量。前端**不调用** `CLIP_status` 前置门控——若先查 `CLIP_status`，在「配了 LLM 但没配独立 CLIP 服务」时会误判不可用、降级成普通搜索。

结论：直接走 `searchCLIPV2`，只在真正失败/空结果时回退 `searchV2`。

## 三、经验 2：搜索页目标 App 包名快照

### 3.1 问题

主图库面板能通过 `service.currentTargetPackage()` 拿到当前输入目标（QQ 等）。但搜索页是**独立 Activity**，它一启动，IME 就重新绑定到搜索页自己的 EditText，此时再取 `currentTargetPackage()` 拿到的已经是输入法自身，不再是 QQ。

### 3.2 修复：启动那一刻快照，经 Intent 传递

```kotlin
// MemeBoardWindow.openSearch()：此刻 IME 还绑定在 QQ 上
service.startActivity(
    Intent(service, MemeBoardSearchActivity::class.java).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        putExtra(MemeBoardSearchActivity.EXTRA_TARGET_PACKAGE, service.currentTargetPackage())
    }
)

// MemeBoardSearchActivity：读取快照，据此判断
targetPackage = intent.getStringExtra(EXTRA_TARGET_PACKAGE)
```

搜索页据此在「点结果」时判断 QQ，走分享而非复制剪贴板（QQ 里剪贴板贴不上图片）。

## 四、可复用要点

| # | 经验 | 说明 |
|---|------|------|
| 1 | 先抓响应，再怀疑请求 | 「搜不到」时别急着改请求参数；先 logcat 看服务端返回，很可能服务端有结果、是解析丢了 |
| 2 | 同名字段多形态要兼容 | MT Photos 的 `result` 既有扁平数组也有分组数组；模型加 `isFile` 判定一网打尽 |
| 3 | OpenAPI 与实际响应反复不一致 | 已第三次踩坑，务必以真实响应 + 前端 JS 为准 |
| 4 | 跨 Activity 传输入目标要快照 | IME 重新绑定后 `currentTargetPackage()` 会变；必须在启动新 Activity 那一刻取值并随 Intent 传递 |
| 5 | 前置门控慎用 | 服务端能自动判断能力时（如 CLIP/LLM 向量），客户端别多做「状态探测」导致误判降级 |

## 五、验证方法

1. 构建 arm64 debug APK，`adb -s <serial> install -r`；
2. QQ 聊天里搜「哈哈大笑」→ 应返回语义匹配结果（`clipSearch '...' -> N` 中 N > 0）；
3. 微信等其它 App 里点结果 = 复制剪贴板；QQ 里点结果 = 弹系统分享面板。
