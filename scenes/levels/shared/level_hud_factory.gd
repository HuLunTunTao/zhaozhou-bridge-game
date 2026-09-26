class_name LevelHudFactory
extends RefCounted

## 关卡 HUD 小部件纯工厂（Step 4.9 删重复代码）。
## 把 1-1 / 1-2 的任务提示条与 1-3 / 1-4 的常驻状态面板的建控件样板收编成一处。
## 所有函数 static、不挂宿主关卡；调用方自行 add_child 到 gui。


## 顶部居中任务提示条（MissionHint）：米色文字 + 深色描边，鼠标穿透。
static func create_mission_hint_label() -> Label:
	var label := Label.new()
	label.name = "MissionHint"
	label.anchors_preset = Control.PRESET_TOP_WIDE
	label.offset_top = 36
	label.offset_bottom = 66
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.1))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## 左上角次级状态提示（1-1 勘测点清单 / 1-2 参数点进度）：浅色文字 + 深色描边，鼠标穿透。
static func create_side_hint_label(hint_name: String, offset_bottom: int) -> Label:
	var label := Label.new()
	label.name = hint_name
	label.anchors_preset = Control.PRESET_TOP_LEFT
	label.offset_left = 18
	label.offset_top = 84
	label.offset_right = 320
	label.offset_bottom = offset_bottom
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.08))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## 左上角常驻状态面板（BBCode RichTextLabel）：offset_right / offset_bottom 按关卡内容调。
static func create_status_panel(panel_name: String, offset_right: int, offset_bottom: int) -> RichTextLabel:
	var panel := RichTextLabel.new()
	panel.name = panel_name
	panel.bbcode_enabled = true
	panel.fit_content = true
	panel.scroll_active = false
	panel.autowrap_mode = TextServer.AUTOWRAP_OFF
	panel.anchors_preset = Control.PRESET_TOP_LEFT
	panel.offset_left = 18
	panel.offset_top = 84
	panel.offset_right = offset_right
	panel.offset_bottom = offset_bottom
	panel.add_theme_font_size_override("normal_font_size", 16)
	panel.add_theme_color_override("default_color", Color(0.96, 0.94, 0.88))
	panel.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.08))
	panel.add_theme_constant_override("outline_size", 3)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel
