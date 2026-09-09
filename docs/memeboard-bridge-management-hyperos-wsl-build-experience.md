# MemeBoard 桥接服务管理 + HyperOS 链式启动适配 + WSL 提权构建经验

本文总结把 gpen-bridge / asr-bridge 两个「独立隐藏 APK」纳入 fcitx5 输入法统一管理的完整经验，涵盖 HyperOS 系统适配研判、桥接服务管理页实现、RunningHub 生图做图标，以及最关键的 WSL 构建提权踩坑。

## 背景

在小米 15（Android 16 / SDK 36 / HyperOS 3.0 / arm64-v8a）真机使用中，gpen-bridge（手写）与 asr-bridge（语音）是两个独立的隐藏 APP（无 launcher 图标）。用户痛点：

1. 权限要去系统「应用管理」里单独设置，不方便；
2. 设备重启后需要手动到「应用管理」里启动桥服务。

用户希望「像 rime 一样在输入法插件管理里注册 + 重启后自动拉起」。

## 结论先行：为什么桥不能像 rime 那样进插件管理

- **rime 是 fcitx5 的 native addon**：`librime` 是 C++ 引擎，通过 plugin APK 的 `nativeLibraryDir` 注入进**输入法进程内**运行，所以出现在「插件管理」（`AddonListFragment`，列出 native 层 `getFcitxAddons()`）里。
- **gpen / asr 是跨进程 AIDL 桥**：引擎跑在独立进程（gpen 因搜狗 SDK 闭源 + 授权锁定包名 `com.yuyan.pinyin.offline.release` + 仅 arm64；asr 因 sherpa-onnx 模型 259MB），输入法通过 `bindService` 远程调用。永远不可能变成进程内 native addon。
- gpen 包名被搜狗授权锁死，连 fcitx5 的 plugin APK 前缀（`org.fcitx.fcitx5.android.plugin.*`）都改不了。

所以正确路线是「在输入法内做管理页 + 启动预热」，而非硬塞进插件列表。

## 经验 1：WSL 构建提权 —— 用 `sandbox_permissions` 而非 UAC（本次最大踩坑）

### 现象

`wsl.exe` 报 `E_ACCESS_DENIED`，具体是 `Wsl/Service/CreateInstance/E_ACCESS_DENIED` 或 `Wsl/EnumerateDistros/Service/E_ACCESS_DENIED`。

### 诊断关键

- `wsl.exe --version` 正常（这是本地读版本，不经过 WSL 服务），但 `wsl.exe -l -v` 报 `E_ACCESS_DENIED`（要访问 LxssManager 服务）。
- 这**不是**「WSL 内用户权限」问题——之前 OpenViking 记的「`wsl -u root` 提权」解决的是 WSL 内 coder 用户访问不了 `/root/fcitx5-android`，属于更上层。而这次是 Windows 层访问 WSL 服务实例被拒，`-u root` 解决不了。

### 错误尝试

用 `Start-Process -Verb RunAs`（Windows UAC 提权）——结果是 UAC 弹窗用户看不到、进程卡死。根因：DSH 进程跑在受限的 window station（session 1 但非交互窗口站），UAC 弹窗无法呈现给用户。

### 正确解法

用 shell 工具的 `sandbox_permissions` 参数提权（这是 DSH 沙箱的提权通道，不是 Windows UAC）：

```json
// shell 工具调用
{
  "command": "wsl.exe -u root bash -lc \"...\"",
  "sandbox_permissions": "danger-full-access",
  "justification": "访问 WSL 服务（LxssManager）创建实例需要系统级权限，需 danger-full-access"
}
```

关键点：
- 触发方式是「先正常跑一次，看到 `[sandbox: escalation available — retry with sandbox_permissions]` 提示后，再带 `sandbox_permissions` + `justification` 重试完全相同的命令」。
- 需要的最窄更宽模式是 `danger-full-access`（`workspace-write` 不够）。
- 审批策略为 `ask` 时，这个重试会触发审批提示，用户点确认即可。

### 后台构建的坑

`wsl.exe -u root bash -lc "... nohup ... &"` 这种单行内嵌后台，在 wsl.exe 传参时 `nohup` + `&` 容易被吞，导致后台任务根本没起来（日志不生成、无 gradle 进程）。正确做法是把构建逻辑写进 WSL 内的独立脚本（`cat > /root/run-build.sh << EOF`），再 `nohup /root/run-build.sh > log 2>&1 &`。

### 构建脚本同步的路径坑

Windows 侧的 `res/mipmap*` 是**平级的 `mipmap-mdpi` / `mipmap-hdpi` / `mipmap-xxhdpi` 等目录，没有统一的 `mipmap/` 父目录**。同步脚本里写 `rsync .../res/mipmap/` 会报 `change_dir failed: No such file or directory`。正确写法是逐个密度目录同步：

```bash
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  mkdir -p "$DST/app/src/main/res/mipmap-$d"
  rsync -a --delete "$SRC/app/src/main/res/mipmap-$d/" "$DST/app/src/main/res/mipmap-$d/"
done
```

## 经验 2：HyperOS 链式启动管控是「重启后桥起不来」的根因

查小米 HyperOS 官方适配文档（skill: xiaomi-hyperos-system-adaptation），关键一条 `pId=1596`（MIUI12 照明弹说明）：

> **链式启动**：应用 A 启动应用 B 的 Activity/Service/Provider 会被记录为链式启动。**除 Activity 外的调用，在 B 未存活时均会默认拒绝，B 存活时才允许。**

翻译到本场景：输入法（A）`bindService` 拉起桥（B），桥进程没在运行时，HyperOS 默认拒绝这次绑定。这就是「重启后必须手动启动桥」的真正原因——不是代码没写好，是系统在 bindService 层就拦了。`BIND_AUTO_CREATE` 也没用。

配套三篇文档形成完整链条：

- `pId=1624` 自启动权限：手机默认应用不可自启动，隐藏 APP 更不会开机自启。
- `pId=1607` 进程清理：锁屏清理/上滑清理会杀桥进程；FAQ#3 明确「被用户杀后要引导用户在安全中心打开自启动开关」。
- `pId=1628` Powerkeeper 省电策略：后台长时间不用会被限制/kill，需设为「无限制」。

**对方案的修正**：仅做「启动预热」不足以保证拉起——桥未存活时 bindService 可能被链式启动管控拒绝，预热必须做但必须容错（绑定失败静默降级）。管理页必须引导用户开自启动 + 省电策略设无限制。

## 经验 3：桥接服务管理页 + 预热器实现

### 预热器 `BridgePrewarmer`（object）

- `prewarm(context)`：后台线程 `bindService` 拉起两个桥（`BIND_AUTO_CREATE`），触发引擎预加载（gpen 复制模型+加载 so、asr 加载 259MB 模型），消除首次手写/语音的 1~2 秒延迟，并保持绑定让桥进程常驻。
- 幂等（`@Volatile prewarmed` 标志），绑定失败静默降级（try-catch + 日志），不影响后续 `GpenHandwritingClient` / `AsrkbSpeechClient` 的按需绑定。
- `release()`：unbind 全部连接；`isPrewarmed()` / `activeConnectionCount()` 供管理页查询。
- 接入点：`FcitxInputMethodService.onCreate()` 里 `lifecycleScope.launch(Dispatchers.IO) { BridgePrewarmer.prewarm(this@...) }`，`onDestroy()` 里 `release()`。

### 管理页 `BridgeSettingsFragment`

- 两张卡片显示 gpen/asr 的「是否安装 + 版本」（`PackageManager.getPackageInfo`，TIRAMISU 用 `PackageInfoFlags.of(0)`）。
- 「打开自启动设置」：优先跳 HyperOS 自启动管理页，带降级：

```kotlin
private fun openAutostartSettings(packageName: String) {
    val miuiAutostart = Intent().apply {
        component = ComponentName(
            "com.miui.securitycenter",
            "com.miui.permcenter.autostart.AutoStartManagementActivity"
        )
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
        data = Uri.fromParts("package", packageName, null)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    val canResolve = runCatching {
        packageManager.resolveActivity(miuiAutostart, 0) != null
    }.getOrDefault(false)
    runCatching { startActivity(if (canResolve) miuiAutostart else fallback) }
        .recoverCatching { startActivity(fallback) }
}
```

- 关键：manifest `<queries>` 里必须声明 `<package android:name="com.miui.securitycenter" />`，否则 Android 11+ `resolveActivity` 返回 null，永远降级。
- 「桥接服务控制」分类：显示预热状态 + 「立即预热」「释放桥接」手动按钮，便于排查。

## 经验 4：RunningHub 生图做 Android 图标

### launcher 图标（可爱贴纸风）

- RH `image2_generate`，1:1、2k，生成完整圆角贴纸图（笑脸键盘 + 贴纸 + 渐变背景）。
- 落地：缩放成 mdpi~xxxhdpi 五密度，覆盖 `ic_launcher*.png`；**必须删除 `mipmap-anydpi-v26/ic_launcher*.xml`**（adaptive icon），否则 Android 8+ 会用旧的灰键盘 adaptive icon 覆盖贴纸 PNG。
- 删 adaptive 后回退 legacy PNG，`app_icon` 的 resValue 别名（`@mipmap/ic_launcher`）仍有效。

### 设置入口图标（单色剪影）

- 设置列表入口图标会被 `setTint()`（`PreferenceScreen.kt` 的 `setIcon` 用 `styledColor(colorControlNormal)`）染成主题单色，所以只能用单色剪影，多彩贴纸风会被 tint 毁掉。
- RH 生成「白底黑剪影」→ Pillow 阈值处理转成「透明背景 + 黑色前景」的 RGBA PNG（`gray.point(lambda p: 255 if p < THRESH else 0)` 做 alpha mask），才能被 tint 正确染色。
- 剪影语义要明确：第一次生成「双气泡+桥」被误读成「耳机」，改成「双圆节点 + 连接横杆」才符合「桥接两服务」语义。
- 处理脚本存本地（`resize_launcher.py` / `process_bridge.py`），可复现。

### 视觉核验

当前模型无法直接读图时，用 modlens 视觉桥（`read_image` 触发）核验生成结果；modlens CLI 无运行时时（Node < 22.19），可依赖 harness 的 `read_image` 通道。

## 可复用要点

1. **WSL 构建 E_ACCESS_DENIED → 用 shell 工具的 `sandbox_permissions: danger-full-access` 提权，不是 UAC `-Verb RunAs`**（UAC 弹窗在 DSH 受限窗口站看不到）。
2. **WSL 后台构建 → 写独立脚本再 `nohup`，不要在单行 `wsl.exe -lc "... &"` 里内嵌后台**。
3. **Android `res/mipmap*` 是平级密度目录，没有 `mipmap/` 父目录**，rsync 要逐个密度目录。
4. **HyperOS 链式启动管控（pId=1596）**：A 拉 B 的 Service，B 未存活时默认拒绝——bindService 层就拦，预热必须容错 + 引导用户开自启动/省电无限制。
5. **设置入口图标会被 setTint 染成单色**，要用「透明背景 + 单色前景」剪影，不能多彩。
6. **删 adaptive icon XML 回退 legacy PNG** 才能让自定义贴纸图标在 Android 8+ 生效。
7. **RH 生图是串行位图**，一次一张；语义图标要多试几版 prompt 直到视觉核验无误。
