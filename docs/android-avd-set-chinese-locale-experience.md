# Android AVD 模拟器设置系统语言为中文经验

## 场景

需要在 Android Studio 的 AVD（Android Virtual Device）模拟器上把系统语言切换为简体中文，用于输入法（如 fcitx5）等本地化场景测试。

## 环境

- 设备：`emulator-5554`
- 系统：Android 16（API 36）
- 镜像：Google APIs x86_64（`sdk_gphone64_x86_64`）

## 正确做法

1. 写入系统语言设置项（Android 10+ 走 Settings Provider，而非旧属性）：

   ```bash
   adb shell settings put system system_locales zh-CN
   ```

2. 重启模拟器使设置生效：

   ```bash
   adb reboot
   ```

3. 等待开机完成（`sys.boot_completed=1`）后验证。

## 坑点

### 1. `persist.sys.locale` 在 Android 16 已只读

```bash
adb shell setprop persist.sys.locale zh-CN
# 报错：Failed to set property 'persist.sys.locale' to 'zh-CN'.
```

现代系统（Android 10+）实际读取 settings 里的 `system_locales` 配置项，`persist.sys.locale` 已废弃且只读，只需写 `system_locales` 即可。

### 2. `ro.product.locale` 是只读产品默认值

它由镜像构建时固定（如 `en-US`），**不会**随语言切换而改变。不要用它判断当前语言，否则会误判为「没生效」。

### 3. PowerShell 下截屏二进制重定向会失败

```bash
adb exec-out screencap -p > file.png
# 报错：StandardOutputEncoding is only supported when standard output is redirected
# 结果：file.png 为 0 字节
```

改用两步：

```bash
adb shell screencap -p /sdcard/x.png
adb pull /sdcard/x.png ./x.png
```

### 4. 无图像能力的模型如何验证界面语言

当前模型不支持直接读图时，用 modlens 视觉桥读取截图即可识别界面文字语言。

## 验证

```bash
adb shell settings get system system_locales   # 返回 zh-CN
adb shell getprop sys.boot_completed            # 返回 1 表示开机完成
```

再打开设置界面（`adb shell am start -a android.settings.SETTINGS`）确认菜单为中文。

## 一句话总结

AVD 设置中文：`settings put system system_locales zh-CN` + 重启；`persist.sys.locale` 已废弃只读、`ro.product.locale` 是固定默认值，均不要用于判断当前语言。
