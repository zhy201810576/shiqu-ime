# MemeBoard 颜文字面板工具栏滑动与搜索上屏经验

本文总结拾趣输入法（MemeBoard / fcitx5-android fork）接入 6.2 万条颜文字数据集、实现分类标签栏滑动 + 搜索功能过程中的三个关键坑与解法，面向需要改造 fcitx5-android picker 面板或实现「IME 内跨 Activity 上屏」的 Kotlin/Android 开发者。

## 背景与目标

- 数据源：`ekohrt/emoticon_kaomoji_dataset`（62,000 条），清洗去重后得到 **15,560 个颜文字、88 个分类**，中文标签映射。
- 目标：离线打包进 APK（1.4MB `assets/kaomoji_data.json`），颜文字面板展示核心情绪分类 + 可滑动标签栏 + 🔍 搜索入口。
- 参考 MemeBoard 表情包搜索弹窗（`MemeBoardSearchActivity`）的设计：独立 Activity 而非 Dialog，避免 IME 焦点冲突。

## 经验一：TitleUi.addExtension 的 showTitle=false 宽度约束陷阱（工具栏空白根因）

### 现象

颜文字面板工具栏（分类标签栏）完全空白，且**波及 Emoji / 符号面板**（三个面板共享 `PickerTabsUi`）。

### 根因

`TitleUi.addExtension()` 添加扩展栏时：

```kotlin
add(view, lParams(matchConstraints, dp(40)) {
    centerVertically()
    if (showTitle) {
        endOfParent(dp(5))
    } else {
        centerHorizontally()   // 只有居中约束，无 start/end 宽度约束
    }
})
```

`showTitle=false` 时，扩展栏只有 `centerHorizontally()`（即 start=end=parent 中心），宽度 `matchConstraints`(0) 无法解析。

- 原始 `PickerTabsUi.root` 是 `ConstraintLayout`，它作为扩展栏时 MATCH_CONSTRAINT 会 **fallback 到 wrap_content**，侥幸正常显示。
- 换成 `HorizontalScrollView` 后**不 fallback** → 宽度解析为 0 → 空白。

### 修复

给 `showTitle=false` 分支补上明确的水平边界：

```kotlin
} else {
    startOfParent()
    endOfParent()
}
```

## 经验二：ConstraintLayout chain 在 HorizontalScrollView 内测量失败（第二层根因）

### 现象

修好 `TitleUi` 约束后，工具栏**仍然空白**，Emoji 面板的图标标签也不显示。

### 根因

`PickerTabsUi.tabContainer` 原本是 `ConstraintLayout`，标签用 constraint chain（`startOfParent`/`after`/`before`/`endOfParent`）排列。放进 `HorizontalScrollView` 后，滚动视图以 **UNSPECIFIED（无限宽）** 测量子视图，constraint chain 在这种模式下无法解析 → 每个标签宽度被解析为 0。

### 修复

`tabContainer` 从 `ConstraintLayout` 改为 **`LinearLayout(HORIZONTAL)`**，标签用 `LinearLayout.LayoutParams(WRAP_CONTENT, MATCH_PARENT)`：

```kotlin
private val tabContainer = horizontalLayout { }   // splitties DSL = LinearLayout(HORIZONTAL)

override val root = HorizontalScrollView(ctx).apply {
    isHorizontalScrollBarEnabled = false
    addView(tabContainer, ViewGroup.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT,
        ViewGroup.LayoutParams.MATCH_PARENT
    ))
}

tabs.forEach { tabUi ->
    tabContainer.add(tabUi.root, LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT,
        ViewGroup.LayoutParams.MATCH_PARENT
    ))
}
```

LinearLayout 在滚动视图的 UNSPECIFIED 宽度下测量可靠，标签总宽度正确，超出屏幕即可水平滑动。

> 教训：`HorizontalScrollView` 的子容器用 `LinearLayout`，不要用 `ConstraintLayout` chain。

## 经验三：跨 Activity 搜索上屏的时机选择

### 现象

搜索弹窗点击结果后，文本**不立即上屏**，要重新点颜文字面板按钮才上屏。

### 根因

搜索 Activity 打开时，输入焦点从目标 App 输入框切到搜索框 `EditText`，`PickerWindow` 被 detach。点击结果 `finish()` 后焦点回到目标 App，但 `PickerWindow.onAttached` **不会重新触发**（只有用户再次点颜文字按钮才触发），所以挂在静态桥 `KaomojiPendingCommit.text` 上的文本一直没被消费。

### 修复

上屏时机从 `PickerWindow.onAttached` 移到 **`FcitxInputMethodService.onStartInputView`**（焦点回到目标 App 输入框时必然触发）：

```kotlin
override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
    Timber.d("onStartInputView: restarting=$restarting")
    // 消费颜文字搜索页返回的待上屏文本：焦点回到目标 App 时立即上屏
    KaomojiPendingCommit.text?.let { text ->
        KaomojiPendingCommit.text = null
        commitText(text)
    }
    postFcitxJob { focus(true) }
    // ...
}
```

搜索 Activity 点击结果只需：`KaomojiPendingCommit.text = kaomoji; finish()`。

> 教训：IME 内跨 Activity 上屏，消费时机应挂在 `onStartInputView`（焦点回归事件），而不是面板的 attach/detach 生命周期——Activity 切换会打乱 attach 状态。

## 搜索入口设计要点

- 独立 Activity（`KaomojiSearchActivity`，singleTask + DialogTheme + adjustResize），顶部锚定 55% 高度，`EditText` + `ListView`，本地搜索防抖 200ms。
- 静态桥 `object KaomojiPendingCommit { @Volatile var text: String? = null }` 在 Activity 与 IME 服务间传递文本（同进程）。
- 分类标签栏第一个标签固定为 `🔍`（`SEARCH_TAB_LABEL`），点击打开搜索 Activity；`PickerWindow` 标签点击回调里检测 `label == SEARCH_TAB_LABEL` 分支。
- 12 个核心情绪分类（开心/爱心/害羞/悲伤/哭泣/生气/亲亲/激动/惊讶/烦恼/坏笑/其他）+ 🔍，其余 76 个分类通过搜索访问。

## 颜文字密度

`PickerPageUi.Density.Low`（emoticon 专用）从 4 列×3 行（12/页）改为 **6 列×4 行（24/页）**，文本 19f→16f，布局更紧凑：

```kotlin
// emoticon: 6/6/6, no backspace (compact layout)
Low(24, 6, 4, 16f, true, false)
```

## 同步脚本注意

WSL2 构建链的同步脚本（`sync-kaomoji.sh`）需要额外包含被修改的非 picker 目录文件：

- `input/bar/ui/TitleUi.kt`（扩展栏约束修复）
- `input/FcitxInputMethodService.kt`（onStartInputView 上屏）
- `AndroidManifest.xml`（新 Activity 注册）

只同步 picker 目录会漏掉框架层改动，导致「改了本地但 WSL 里还是旧代码」的假象。

## 可复用要点速查

1. `TitleUi.addExtension` 的 `showTitle=false` 分支要给 `startOfParent()+endOfParent()`，否则非 ConstraintLayout 扩展栏宽度为 0。
2. `HorizontalScrollView` 子容器用 `LinearLayout`，禁用 `ConstraintLayout` chain。
3. IME 跨 Activity 上屏挂在 `onStartInputView`，不挂面板 onAttached。
4. 改 picker 面板时同步脚本要带上框架层文件（TitleUi/FcitxInputMethodService/Manifest）。
5. 验证工具栏问题先看「Emoji 面板是否也空白」——共享 `PickerTabsUi` 的话，一处改动影响三个面板。
