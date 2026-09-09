# MemeBoard 手写候选词接入 fcitx5 原生候选栏经验

## 背景与目标

MemeBoard（fcitx5-android fork）集成手写输入时，手写识别走的是外部桥接 APK（语燕 gpen-bridge，AIDL 远程调用），识别结果最初在手写覆盖层内部自己画一行候选词。

用户诉求：手写候选词要像 rime 拼音一样，显示在 fcitx5 原生候选栏（键盘最上方，与中州韵候选词同一位置、同一样式）。

## 关键认知：为什么 rime 候选词能在候选栏，手写不能

- rime 是 fcitx5 原生引擎（addon）：fcitx5-rime 以 InputMethodEngine 身份运行在 fcitx5 core 内，候选词走 native 管道 → CandidateListEvent → Android 候选栏组件（KawaiiBar）。
- 手写是外部桥：独立 APK + AIDL，不是 fcitx5 引擎，识别结果只能通过远程调用返回给输入法，fcitx5 没有「外部程序注入候选词」的公开 API。

## 核心方案：Android 层注入外部候选词（不改 native）

结论：fcitx5 候选栏的 Android 端组件（HorizontalCandidateComponent）是被动渲染的，可以绕过 native 直接驱动它。改动 4 个文件：

### 1. HorizontalCandidateComponent（候选词组件）

外部候选词点击回调：非空时点击不再走 fcitx.select，而是回调（由外部源 commitText 上屏）。

    var externalCandidateClickListener: ((CandidateWord) -> Unit)? = null

点击处理：

    holder.itemView.setOnClickListener {
        val external = externalCandidateClickListener
        if (external != null) external(holder.candidate)
        else fcitx.launchOnReady { it.select(holder.idx) }
    }

供外部源提交候选词（复用内部 fillStyle 布局逻辑）：

    fun submitCandidates(candidates: Array<CandidateWord>) {
        onCandidateUpdate(FcitxEvent.CandidateListEvent.Data(candidates.size, candidates))
    }

### 2. KawaiiBarComponent（候选栏）

    fun showExternalCandidates(candidates: List<String>, onSelect: (String) -> Unit) {
        val words = candidates.map { CandidateWord("", it, "") }.toTypedArray()
        horizontalCandidate.externalCandidateClickListener = { word -> onSelect(word.text) }
        horizontalCandidate.submitCandidates(words)
        barStateMachine.push(CandidatesUpdated, CandidateEmpty to words.isEmpty())
    }

    fun clearExternalCandidates() {
        horizontalCandidate.externalCandidateClickListener = null
        horizontalCandidate.submitCandidates(emptyArray())
        barStateMachine.push(CandidatesUpdated, CandidateEmpty to true)
    }

### 3. 状态机（KawaiiBarStateMachine）

候选栏有 Idle/Candidate/Title 三态。注入候选词后必须 push CandidatesUpdated 事件（CandidateEmpty=false）才能切到 Candidate 态显示候选词；清空时 push CandidateEmpty=true 回 Idle 态。

### 4. 手写覆盖层 + KeyboardWindow

- KeyboardWindow 把手写的 bar: KawaiiBarComponent 通过构造函数传给 HandwritingOverlayView。
- 手写 overlay 移除自带候选词行，识别结果调用 bar.showExternalCandidates(candidates) { commit(it) }。
- 退出/onDetach 时调用 bar.clearExternalCandidates()，否则候选栏残留手写候选词、且原生点击逻辑未恢复。

## 关键架构认知

- InputView 布局：ConstraintLayout 中 kawaiiBar.view（候选栏+工具栏，顶部）在 windowManager.view（键盘窗口）上方。手写 overlay 是 addView 到 KeyboardWindow.keyboard_view（键盘按键区），本来就不覆盖候选栏——所以候选栏一直可见，只是之前手写没往里面塞候选词。
- 这个「Android 层驱动候选栏组件」的思路，对任何「外部输入源（手写/语音/OCR）想复用 fcitx5 候选栏」都适用，不必改 C++。

## 手写笔迹灵敏度修复

原代码用贝塞尔拟合，且「凑满 4 个采样点才画第一笔」，导致落笔初期、快速短划、慢速书写时「写了没笔迹」。

修复：改为「落笔即画点、移动逐点连线」，宽度随书写速度变化（慢粗快细），采样点距离小于阈值（touchSlop）时跳过。

## 手写参数化设置页

- 笔迹粗细（6~24dp）、移动灵敏度（1~5 档）用 SeekBarPreference 存入 SharedPreferences。
- HandwritingPadView 每次 beginStroke 时 refreshPrefs() 读取最新参数，改动即时生效。
- 灵敏度映射：档位 1..5 → 采样阈值 1.6/1.2/0.8/0.5/0.3px（档位越大越灵敏）。

## 布局迭代轨迹

1. 候选词行 + 手写板 + 底部按钮行（初始）
2. 候选词 + 按钮合并为顶部菜单栏，手写板 weight 1
3. 候选词真正接入原生候选栏，手写板 + 右侧竖排按钮
4. 最终：手写区占满全部空间，右侧竖排三键「返回 / 清空 / 退格」

## 踩坑记录

1. copy-files.sh 遗漏新改文件 → WSL 编译报 Unresolved reference。改 fcitx5 原始文件（非 MemeBoard 新增文件）时，务必确认它在同步脚本清单里。
2. wsl.exe 必须 -d Ubuntu-22.04 显式指定发行版，否则进到别的（跑 nexus/docker 的）环境。
3. setsid 后台构建需 sleep 缓冲，否则 wsl.exe 退出瞬间把刚 fork 的 gradle 进程带走（日志为空、无进程）。
4. HyperOS 3.0 force-stop fcitx5 后默认输入法 fallback 回搜狗，需重新 ime set。
5. HyperOS「USB 安装」开关需手动开启，setprop persist.security.adbinstall 被系统拒绝。
6. 首次装包时 INSTALL_FAILED_USER_RESTRICTED 常是手机弹确认框没点，重试即可。
