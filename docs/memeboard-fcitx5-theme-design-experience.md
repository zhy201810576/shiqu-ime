# MemeBoard (fcitx5-android) 自定义主题设计与 ADB 部署经验

> 面向需要为 fcitx5-android（含 MemeBoard fork）设计自定义键盘主题、并部署到真机的 Android/Kotlin 开发者。
> 覆盖主题序列化格式、手写 `theme.json`、RunningHub 生成背景图、ADB 推送部署四条主线。

## 1. 背景与目标

为 fcitx5-android 输入法设计一套自定义键盘主题，最终交付**可导入的 zip 主题包**，并通过 **ADB 直接推送到小米15 真机**（无需走应用内 SAF 文件选择器）。

交付物：
- 纯色主题 `AquaBlush.zip`（仅 `theme.json`）
- 带背景图主题 `AquaBlushBG.zip`（`theme.json` + 2 张背景图）
- ADB 推送到 `/sdcard/Android/data/org.fcitx.fcitx5.android/files/theme/`

## 2. fcitx5-android 主题系统架构

### 2.1 Theme 抽象类：21 个颜色槽 + 背景图 + 深浅色

主题本质是一个 `Theme` 对象（`data/theme/Theme.kt`），由三部分构成：

- **21 个颜色槽**（`backgroundColor`、`barColor`、`keyboardColor`、`keyBackgroundColor`、`keyTextColor`、`candidateTextColor`、`candidateLabelColor`、`candidateCommentColor`、`altKeyBackgroundColor`、`altKeyTextColor`、`accentKeyBackgroundColor`、`accentKeyTextColor`、`keyPressHighlightColor`、`keyShadowColor`、`popupBackgroundColor`、`popupTextColor`、`spaceBarColor`、`dividerColor`、`clipboardEntryColor`、`genericActiveBackgroundColor`、`genericActiveForegroundColor`）
- **可选背景图** `backgroundImage: CustomBackground?`
- **`isDark: Boolean`**（决定系统导航栏图标明暗）

### 2.2 三种主题类型

| 类型 | 说明 | 关键文件 |
|------|------|---------|
| `Builtin` | 内置预设（Material/Pixel/DeepBlue/AMOLED/Nord/Monokai 等 9 套），硬编码在 `ThemePreset.kt` | `ThemePreset.kt` |
| `Monet` | Material You 动态取色（基于系统壁纸） | `ThemeMonet.kt` |
| `Custom` | 自定义主题，可导入/导出为 zip | `ThemeFilesManager.kt` |

### 2.3 存储与导入导出

- 存储目录：`getExternalFilesDir(null)/theme/` → `/sdcard/Android/data/<package>/files/theme/`
- 主题文件：`<name>.json`（`ThemeFilesManager.saveThemeFiles`）
- 导出：`exportTheme` 打包 zip（json + cropped png + src png）
- 导入：`importTheme` 解压 → 找 `.json` → 反序列化 → 改写图片路径为绝对路径 → 落盘

## 3. theme.json 序列化格式（核心）

### 3.1 颜色值编码：有符号 32 位整数

**颜色不是 hex 字符串，而是 `0xAARRGGBB` 作为有符号 32 位整数（Int）的十进制表示。**

换算公式：无符号值 `U = 0xAARRGGBB`；若 `U >= 2^31`，有符号值 `= U - 2^32`。

实测对照（来自 `ThemeSerializationTest`）：

| 色值 | 十进制 | 说明 |
|------|--------|------|
| `0xFF2D2D2D` | `-13816531` | 深灰 |
| `0xFF000000` | `-16777216` | 黑 |
| `0xFFFFFFFF` | `-1` | 白 |
| `0x1F000000` | `520093696` | 12% 黑（按下高亮，正数因为 A=0x1F < 0x80）|
| `0x00000000` | `0` | 全透明 |
| `0x8CFFFFFF` | `-1929379841` | 55% 白 |

> 踩坑：`0x8CFFFFFF = 2365587455`（不是 2365599455）。手工把「`0x8C000000 + 0xFFFFFF`」相加时极易算错，务必用脚本计算，勿心算。

### 3.2 字段名与 version

- 字段名 = `Theme.Custom` 属性名（kotlinx.serialization 默认行为）
- **必须带 `"version": "2.1"`**（`CustomThemeSerializer.CURRENT_VERSION`）。缺失会 fallback 到 `1.0` 走迁移链。
- 完整字段 = 24 个属性 + `version` = 25 个 key

### 3.3 backgroundImage 结构

```json
"backgroundImage": {
  "croppedFilePath": "...",   // 无默认值，必须
  "srcFilePath": "...",        // 无默认值，必须
  "brightness": 80,            // 默认 70，可省略
  "cropRect": null,            // nullable 无默认值，必须显式（可 null）
  "cropRotation": 0            // 默认 0，可省略
}
```

`cropRect` 用自定义 `RectSerializer`，序列化为 `{bottom,left,right,top}`；`null` 表示不裁切，`toDrawable()` 整图显示。

### 3.4 迁移机制

`CustomThemeSerializer` 是 `JsonTransformingSerializer`：序列化时 `addVersion()`，反序列化时读 version → 按 `strategies` 链迁移 → `removeVersion()`。迁移链 `1.0 → 2.0 → 2.1`。

## 4. 手写主题 JSON 完整清单

### 4.1 纯色主题

`backgroundImage: null`，zip 只含一个 `<name>.json`。最简单可靠。

### 4.2 带背景图主题

关键约束（`importTheme` 源码）：
- **`croppedFilePath` 与 `srcFilePath` 必须用不同文件名**——首次导入时 `overwrite=false`，若两字段同名会触发 `FileAlreadyExistsException`（第二次 copy 到同一路径且不允许覆盖）。
- zip 内图片文件名必须与 json 引用一致，`extract().find { it.name == ... }` 按文件名匹配。
- `brightness` 控制暗化：`DarkenColorFilter(100 - brightness)`，`80` = 仅暗化 20%，适合高亮度柔和背景。

### 4.3 命名与编码

- `name` 不能与 `BuiltinThemes` 冲突（否则 `exception_theme_name_clash`）
- 文件 UTF-8 **无 BOM**（否则 `readText()` 读到 BOM 导致 JSON 解析失败）

## 5. 用 RunningHub 生成键盘背景图

- 工具：`runninghub_image2_generate`（appId 2047518389953896450），`aspectRatio=16:9`、`resolution=2k`
- 背景图要点：**柔和、低对比、中间留白充足、无文字/人物/水印**（键盘文字要盖在上面）
- 生成耗时约 80s；`waitForResult=true` 易触发 MCP 层超时，改 `waitForResult=false` + `runninghub_query_task` 轮询更稳
- API 会限流（`api queue limit reached`），遇到稍后重试即可

## 6. ADB 推送到真机的关键坑

### 6.1 直接 push 原始 json 会被跳过（核心坑）

`listThemes()` 里有背景图存在性校验：

```kotlin
if (theme.backgroundImage != null) {
    if (!File(theme.backgroundImage.croppedFilePath).exists() ||
        !File(theme.backgroundImage.srcFilePath).exists()) return null  // 静默跳过
}
```

zip 里的 json 存的是**相对文件名**，直接 push 后 `File("AquaBlush-cropped.png")` 是相对 app 进程 cwd，找不到 → 主题被跳过。

**解法**：push 前把 `croppedFilePath`/`srcFilePath` 改写成**绝对路径**：

```
/storage/emulated/0/Android/data/org.fcitx.fcitx5.android/files/theme/AquaBlush-cropped.png
```

（`importTheme` 内部正是用 `File(dir, name).path` 生成绝对路径）

### 6.2 目录与权限

- 包名：`org.fcitx.fcitx5.android`（debug 构建去掉了 `.debug` 后缀）
- 主题目录：`/sdcard/Android/data/org.fcitx.fcitx5.android/files/theme/`（`/sdcard` 是 `/storage/emulated/0` 的符号链接）
- 实测 `adb shell` **可直接写**该目录（`SHELL_WRITABLE`，文件落为 `rw-rw-rw-`），无需 `run-as`
- `run-as org.fcitx.fcitx5.android` 也可用（debug 构建 debuggable=true，uid `u0_a451`）

### 6.3 刷新机制

- `ThemeManager.customThemes` 是 object 初始化时读一次的内存缓存
- `refreshThemes()` 在 `ThemeListFragment.onCreateView` 时调用（用户打开主题设置页）
- 推送后 `am force-stop` 最彻底：下次重启 `ThemeManager` 重新 `listThemes()`

## 7. 环境踩坑

### 7.1 modlens 读图

- `read_image` 报 `model does not declare image input`（模型无图像输入）→ 改用 `modlens_read_image` 工具读参考图
- `modlens` CLI 运行时不可用（node 版本 < 22.19 floor），但 harness 内置的 `modlens_read_image` 工具可用

### 7.2 node https 下载（Windows schannel TLS 问题）

下载 RunningHub 结果图（腾讯云 COS）时：
- `Invoke-WebRequest` 报 `Authentication failed`
- `curl.exe` 报 `schannel: SEC_E_NO_CREDENTIALS`

**解法**：用 node 的 `https` 模块 + `{ rejectUnauthorized: false }`：

```js
const https=require('https'),fs=require('fs');
https.get(url,{rejectUnauthorized:false},r=>{r.pipe(fs.createWriteStream(out));});
```

### 7.3 PowerShell 十六进制溢出

`[Convert]::ToUInt32('8CFFFFFF',16)` 判断正负时，`0x80000000` 字面量会溢出成负数 `-2147483648`，导致比较恒真。**改用十进制常量 `2147483648`/`4294967296` 判断**，或用 node 交叉验证。

## 8. 可复用要点总结

1. fcitx5 主题颜色 = `0xAARRGGBB` 有符号十进制，用脚本算勿心算。
2. 手写 json 必带 `version:"2.1"`、UTF-8 无 BOM、`name` 不撞内置主题。
3. `backgroundImage.cropRect` 是 nullable 无默认值，必须显式写（`null` 合法）；`brightness`/`cropRotation` 有默认值可省略。
4. 带背景图主题：`croppedFilePath` 与 `srcFilePath` **不能同名**（否则导入 FileAlreadyExists）。
5. ADB 部署带背景图主题：json 里的图片路径必须是**绝对路径**，否则 `listThemes` 静默跳过。
6. 推送后 `am force-stop` 触发重扫；theme 目录 shell 可写，debug 包可直接 push。
7. Windows 下载 COS/HTTPS 资源：node https + `rejectUnauthorized:false` 绕过 schannel TLS 报错。
8. RunningHub 生图用 `waitForResult=false` + 轮询，避免 MCP 层超时与 API 限流。

## 附：验证通过的主题参数

配色映射（参考图「青绿毛皮 + 蓝眼 + 红背带/爱心 + 白胸毛」）：
- 强调键 `#4FB8AE`（青绿毛皮主体色）
- 激活态 `#5FA8D9`（蓝眼睛）
- 候选序号 `#E5677B`（红色爱心点缀）
- 键面白 `#FFFFFF` + 键盘底 `#ECF5F3`（浅色氛围）
- 带背景图版：`keyboardColor=0`（透背景）、键面半透明白 `0x66FFFFFF`、无阴影 `keyShadowColor=0`、`brightness=80`
