# MemeBoard P3 工程化优化经验（统一 JSON + Repository 拆分 + 测试）

> 主题：fcitx5-android（MemeBoard）图库面板的 P3 级工程化改造——统一 JSON 解析、数据层拆分、单元测试、发布合规，以及一个既有测试过时问题的修复。
> 背景：P0/P1/P2 已完成性能与健壮性优化，本轮聚焦可维护性、可测试性与开源合规。

## 一、统一 JSON 解析（org.json → kotlinx.serialization）

原代码混用 `org.json`（手动 `optString`/`optLong` 循环解析）与 `kotlinx.serialization`（仅 albumFiles 流式解析）。统一后响应解析全部走 serialization：

1. **数据类加 `@Serializable` + 默认值**：`MtGallery`/`MtAlbum`/`MtTag` 原来只是 data class，加 `@Serializable` 并给所有字段默认值（`= 0`/`= ""`），否则反序列化遇到缺失字段会抛 `MissingFieldException`。

2. **字段名大小写兼容用 `@JsonNames`**：MT Photos 实际响应的 md5 字段可能为大写 `"MD5"` 或小写 `"md5"`。用
   ```kotlin
   @SerialName("MD5") @JsonNames("md5") val md5: String = ""
   ```
   同时兼容两种（`@SerialName` 是主名/序列化名，`@JsonNames` 是额外反序列化别名）。

3. **可选请求字段用 `explicitNulls = false`**：
   ```kotlin
   Json { ignoreUnknownKeys = true; explicitNulls = false }
   ```
   配合 `@Serializable data class MtSearchRequest(val searchType: String? = null, ...)`，null 字段序列化时自动省略（等价于原来的「非空才 put」），避免输出 `"searchType":null`。

4. **响应体统一取字符串**：把 `executeObject`/`executeArray` 合并为一个 `executeBody(req): String`，各方法用 `json.decodeFromString<T>(...)` 反序列化。文件列表响应 `{list:[...]}` 或 `{result:[{day,list,ids}]}` 用 nullable 字段 + `parseFilesResponse` 展开，精确保持原「list 优先，否则 result 分组」语义。

5. **流式解析加 `@OptIn`**：`decodeToSequence`（防大 JSON OOM）是 `ExperimentalSerializationApi`，函数上加 `@OptIn(ExperimentalSerializationApi::class)` 消除 warning。

## 二、Repository 拆分（数据层提取）

`MemeBoardWindow` 从 324 行涨到 500 行后，把数据访问下沉到 `MemeBoardRepository(context)`：

- **Repository 职责**：`client()` 工厂、`getAuthCode()`/`invalidateAuthCode()`、`tagList()`、`loadAlbums()`（并发 + 去重）、`loadTagFiles()`、`search()`、`download()`（md5 缓存命中）、收藏/最近的读写。
- **Window 职责**：UI 初始化、`viewMode`/`selectedTagId` 状态、`launchLoad` 加载编排（Job 取消 + loading）、事件处理、发送/分享、错误分类。

收益：Window 降到 ~380 行；数据层可独立测试、可复用；关注点分离（fcitx5-android 的 InputWindow 本身就是 controller，不必强上 ViewModel，Repository 已足够）。

## 三、补单元测试（纯逻辑可测）

JVM 单测目录 `app/src/test/` 已有 JUnit 4 + kotlinx.serialization 基础。为 memeboard 新增 `MtPhotosJsonTest`，覆盖零依赖纯逻辑：

- `guessMime`：扩展名 → MIME（含大小写、默认 jpeg）。
- `MtFile` 反序列化：大写 `MD5` 与小写 `md5` 两种。
- `List<MtGallery>` 反序列化：缺省布尔字段默认 false。
- `MtFileListResponse`：`list` 形态与 `result` 分组形态两种。
- 请求体序列化：`explicitNulls=false` 时 null 字段省略；非空字段正常输出。

> 注意：依赖 Android 的纯逻辑（Keystore 加解密、SharedPreferences 的收藏/最近）无法 JVM 单测，只能留作 instrumented test；JVM 单测只覆盖「无 Android 依赖」的纯函数与数据类。

## 四、既有测试过时问题（版本迁移）

跑测试发现 `ThemeSerializationTest.version2` 一直失败，根因是**测试数据过时**而非代码 bug：

- `CustomThemeSerializer.CURRENT_VERSION` 已从 `"2.0"` 升到 `"2.1"`，2.1 新增了 `candidateTextColor`/`candidateLabelColor`/`candidateCommentColor` 三个必填字段。
- 但该测试的 JSON 还停在 `"version":"2.0"`，且缺这三个字段 → 先报 `AssertionError`（migrated 断言失败），改版本号后又报 `MissingFieldException`（缺必填字段）。

修复要**两步**：① 把测试 JSON 的版本号同步为当前版本；② 补齐该版本新增的必填字段。判断字段值可从迁移策略 `MigrationStrategy("2.1")` 反推（candidateTextColor = keyTextColor、candidateLabelColor = keyTextColor、candidateCommentColor = altKeyTextColor）。

## 五、可复用要点

1. 混用 org.json 与 serialization 时，统一方向是「解析全 serialization」，字段兼容用 `@JsonNames`、可选字段用 `explicitNulls=false`。
2. 反序列化数据类所有字段给默认值，否则缺字段抛 `MissingFieldException`。
3. 数据层下沉用 Repository 而非强行 ViewModel，适配「Window 即 controller」的既有架构。
4. 单测只覆盖无 Android 依赖的纯函数/数据类；依赖 Keystore/SharedPreferences 的留给 instrumented test。
5. 「版本号升级后测试过时」是常见坑：改测试要同时改版本号 + 补齐新增必填字段，字段值从迁移策略反推。
