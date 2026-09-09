# MemeBoard：IME 按目标 App 差异化发送策略（QQ 定向分享）

> 面向：需要在 Android 输入法（IME）里「把图片/文件发给当前聊天 App」的 Kotlin 开发者。
> 核心结论：**别假设所有目标 App 的发送能力一致**——用 `currentInputEditorInfo.packageName` 识别当前输入目标，按包名走不同的发送路径，而不是对每种 App 硬试同一套 fallback。

## 一、背景与问题

MemeBoard 是 fcitx5-android 的一个扩展面板，从 MT Photos 拉表情包，点一下发给当前聊天框。最初实现里，点图统一走同一条发送链路：

```
commitContent 直发 → 失败则复制到剪贴板 → 用户长按粘贴
```

在微信 / 笔记 / 群晖 Chat / Telegram 里这条链路工作良好（`InputConnectionCompat.commitContent` 返回 true，图片无缝进输入框）。

但在 QQ 里三种方式**全部失败**：

1. **commitContent 直发**：QQ 的输入连接不支持 `commitContent`，返回 false；
2. **剪贴板粘贴**：QQ 对图片剪贴板粘贴支持极差，基本贴不上；
3. **系统分享面板**：IME 是后台服务，直接 `startActivity` 跨 App 分享会被 HyperOS「后台启动限制」拦截（logcat 出现 `Abort background activity starts`，`result code=102`）。

于是用户每次在 QQ 里点图都「发不出去」，体验崩坏，还容易误操作。

## 二、关键技术：识别当前输入目标 App

IME 里拿到「用户正在哪个 App 里打字」有两个可靠来源：

```kotlin
// 首选：EditorInfo.packageName，最直接
val pkg = currentInputEditorInfo.packageName

// 兜底：binding uid → PackageNameCache（fcitx5-android 已有）
val pkg2 = pkgNameCache.forUid(currentInputBinding.uid)
```

封装成一个方法，供业务层调用：

```kotlin
/** 当前输入目标 App 的包名（用于识别 QQ 等需要特殊处理的目标）。 */
fun currentTargetPackage(): String? =
    currentInputEditorInfo.packageName?.takeIf { it.isNotBlank() }
        ?: pkgNameCache.forUid(currentInputBinding.uid)
```

要点：

- `EditorInfo.packageName` 在绝大多数场景非空且准确，直接优先用；
- 用 `takeIf { it.isNotBlank() }` 做空串兜底，再 fallback 到 uid 映射；
- `PackageNameCache.forUid()` 会处理 sharedUserId 的情况（`substringBeforeLast(':')` 剥离 uid 后缀）。

## 三、按目标 App 差异化发送

识别到包名后，在发送入口处做**前置判断**，而不是在失败后再补救：

```kotlin
private fun send(file: MtFile) {
    // QQ 不支持 commitContent 直发，剪贴板粘贴也很容易失效（误操作高频），
    // 因此检测到当前目标是 QQ 时强制走「分享」路径，避免用户误点后发不出去。
    if (isQQTarget()) {
        Toast.makeText(service, R.string.memeboard_qq_share_hint, Toast.LENGTH_SHORT).show()
        share(file)
        return
    }
    // 其它 App 继续走无缝直发
    service.commitImage(...)
}

private fun isQQTarget(): Boolean {
    val pkg = service.currentTargetPackage() ?: return false
    return pkg == "com.tencent.mobileqq" || pkg == "com.tencent.tim"
}
```

设计要点：

1. **白名单前置拦截，而非失败后兜底**：在 `send()` 一开始就判断，命中 QQ 直接改道，用户体验是「点图立刻弹分享面板 + toast 提示」，而不是「点了没反应、再试、再失败」。
2. **toast 明示改道原因**：用户看到分享面板弹出时，配一句「QQ 不支持直接发图，已自动改为分享」，避免困惑。
3. **覆盖所有发送入口**：`send()` 是统一入口，点图和长按菜单里的「发送」都会走它，一次判断覆盖全部路径。

## 四、让分享在 QQ 里真正能弹出来

即使识别对了、改道分享了，IME 直接 `startActivity` 仍会被 HyperOS 后台启动限制拦掉。完整方案分两层：

1. **透明桥 Activity**：IME 先启动一个自己的前台 Activity（`MemeBoardShareActivity`，`Theme.Translucent.NoTitleBar` + `noHistory`），由它在 `onCreate` 里立刻 `startActivity` 发起 `ACTION_SEND`，把「后台服务发起的跨 App 跳转」变成「前台 Activity 发起的跳转」，绕过限制。
2. **用户授权「后台弹出界面」**：HyperOS 还需要用户在「设置 → 应用 → 小企鹅 → 权限 → 后台弹出界面」里手动开启，否则桥 Activity 也会被拦。

分享用 **FileProvider** 授权（`FLAG_GRANT_READ_URI_PERMISSION` + `ClipData.newUri`），不写相册，避免图库污染。

## 五、可复用要点总结

| # | 经验 | 说明 |
|---|------|------|
| 1 | 发送能力因 App 而异 | 不要假设 `commitContent` 对所有目标都有效；微信系/Telegram 支持，QQ 不支持 |
| 2 | 用包名识别目标 | `currentInputEditorInfo.packageName` 是首选，`PackageNameCache` 兜底 |
| 3 | 前置拦截优于失败兜底 | 在入口判断目标类型直接改道，比「尝试→失败→降级」体验更好 |
| 4 | 明示改道原因 | toast 告诉用户「为什么这次弹的是分享面板」，避免误操作困惑 |
| 5 | 后台服务不能直接跨 App 跳转 | HyperOS/部分 ROM 会拦 `startActivity`，用透明桥 Activity + 「后台弹出界面」授权 |
| 6 | 分享不写相册 | FileProvider 授权即可，避免 `Pictures/` 图库堆积 |

## 六、验证方法

1. 构建 arm64 debug APK，`adb install -r` 安装到真机；
2. 切换到 QQ 聊天窗口，切出 MemeBoard 键盘，点一张图；
3. 预期：立刻弹出系统分享面板（而非发不出去），toast 显示「QQ 不支持直接发图，已自动改为分享」；
4. 切回微信再点图，确认仍走无缝直发（行为未回归）。
