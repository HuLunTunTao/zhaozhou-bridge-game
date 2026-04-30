# 移动端适配踩坑记录

本文记录把 Godot 项目跑到 iOS / Android 真机时遇到的几个坑，以及最终的修法。

## 1. `OS.get_name()` 在 iPad 上返回 `"iOS"`

不是 bug —— iOS 真机上就是 `"iOS"`，macOS 才是 `"macOS"`。
但 Godot 编辑器里跑 iOS 远程调试时容易被误以为是 Mac 环境。

判断"运行在移动端"建议用更稳的：

```gdscript
if OS.has_feature("mobile"):
    ...
```

`mobile` 这个 feature tag 在 iOS / Android 上为 true，桌面端为 false，跨平台一致。
`OS.get_name()` 用于打 log 区分系统时仍然 OK。

## 2. iOS / Android 上 `MODE_FULLSCREEN` 是空操作

iOS / Android 反正一直是全屏，没有"窗口"概念。`window.mode = MODE_FULLSCREEN` 在真机上不会触发任何状态变化。

**真正决定渲染目标尺寸的是 `window.size`**：

```gdscript
window.size = target_size           # 渲染缓冲尺寸
DisplayServer.window_set_size(...)  # 兜底底层 API
window.mode = Window.MODE_FULLSCREEN  # 桌面端有用，移动端空操作
```

如果只设 `MODE_FULLSCREEN` 不设 `window.size`，iOS 会沿用上次的 `window.size`（比如用户在调试时点过 1920×1080 preset），造成**渲染缓冲 1920×1080 → 系统拉伸到 iPad 2360×1640 屏幕 → 模糊**。

修法（[scripts/settings.gd::_apply_window_settings](../scripts/settings.gd)）：fullscreen 分支也要先设 `window.size = target_size`。

## 3. `stretch/aspect` 必须显式声明

项目 `display/window/stretch/aspect` 在不同 Godot 版本默认值不一定是 `keep`，移动端各设备宽高比千差万别（iPad 1.44:1，iPhone 2.16:1，安卓 19.5:9...），不显式声明会出现：

- 部分机型上图像被拉伸变形
- 部分机型上 UI 错位

固定写在 [project.godot](../project.godot)：

```
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
```

`keep` = 保持游戏的 16:9，长宽比不匹配时自动 letterbox / pillarbox。

## 4. autoload 不会热重载

修改 `Settings`（autoload）的代码后，**必须停止游戏 → 重启**才会生效。
F5 触发的是 game restart，不是 editor restart，autoload 会重新实例化，所以一次 F5 足够。但只 reload 当前场景（F6）不够。

调试期间观察到"代码改了行为没变"，第一反应应该是 autoload 没重启，而不是逻辑出错。
设置面板（`SettingsPanel`）这种 `.tscn` 实例化的节点反而会随用随读，每次打开都用最新代码。

## 5. iPad 远程调试时的 window.size 黏性

用户在 iPad 上点 PC 端的分辨率 preset（比如 1920×1080），`window.size = (1920, 1080)` 会**真的**传到 iOS 渲染层，且**不会**自动恢复到设备屏幕。

后续即使切到「移动端自适应 / fullscreen」，如果代码没显式重写 `window.size`，错值会一直持续。

修法：「移动端自适应」在 iOS / Android 分支必须把 `window_width / window_height` 重写为 `DisplayServer.screen_get_size(0)` 的值，再调 `apply_settings()`。

## 6. 移动端必备的项目设置

- `display/window/handheld/orientation = 4`（sensor_landscape，根据陀螺仪在两种 landscape 之间翻转）
- `display/window/stretch/mode = "canvas_items"` + `stretch/aspect = "keep"`
- `Settings.RESOLUTION_PRESETS` 加上常见移动设备分辨率 preset，让设计师在桌面端能快速预览移动布局
- 设置面板加「移动端自适应」选项，导出包跑到真机时一键校准 `window.size = 屏幕尺寸`

## 验证方法

iPad / Android 真机上：

1. 重启游戏
2. 设置 → 选「移动端自适应」→ 应用
3. 控制台应打 `[Settings] 分辨率: 2360x1640`（或设备真实屏幕尺寸）
4. 渲染清晰，按 16:9 居中 + 上下黑边 letterbox

若控制台仍打 1920×1080（或其他错值），说明 `window.size` 被某处覆盖了 —— 检查是否 autoload 没重启，或 `_apply_window_settings` 的 fullscreen 分支没设 size。
