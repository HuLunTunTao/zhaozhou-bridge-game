extends CanvasLayer
## 全局通知管理器（自动加载单例）。
## 用法：
##   Notify.notify("操作成功")
##   Notify.notify("警告", Notify.Position.TOP_LEFT, Notify.Style.WARNING)
##   Notify.notify("错误", Notify.Position.CENTER, Notify.Style.ERROR, 5.0)

enum Position {
	TOP_LEFT,
	TOP_RIGHT,
	BOTTOM_LEFT,
	BOTTOM_RIGHT,
	TOP_CENTER,
	BOTTOM_CENTER,
	CENTER,
}

enum Style {
	INFO,
	SUCCESS,
	WARNING,
	ERROR,
}

const STYLE_COLORS: Dictionary = {
	Style.INFO:    Color(0.15, 0.2, 0.3, 0.94),
	Style.SUCCESS: Color(0.12, 0.28, 0.18, 0.94),
	Style.WARNING: Color(0.35, 0.3, 0.1, 0.94),
	Style.ERROR:   Color(0.35, 0.12, 0.12, 0.94),
}

const STYLE_BORDER_COLORS: Dictionary = {
	Style.INFO:    Color(0.4, 0.55, 0.8, 1),
	Style.SUCCESS: Color(0.3, 0.75, 0.45, 1),
	Style.WARNING: Color(0.85, 0.75, 0.3, 1),
	Style.ERROR:   Color(0.85, 0.3, 0.3, 1),
}

const STYLE_ICON: Dictionary = {
	Style.INFO:    "ℹ",
	Style.SUCCESS: "✔",
	Style.WARNING: "⚠",
	Style.ERROR:   "✖",
}

const STYLE_ICON_COLORS: Dictionary = {
	Style.INFO:    Color(0.5, 0.7, 1.0, 1),
	Style.SUCCESS: Color(0.4, 0.9, 0.5, 1),
	Style.WARNING: Color(1.0, 0.9, 0.4, 1),
	Style.ERROR:   Color(1.0, 0.4, 0.4, 1),
}

const DEFAULT_DURATION := 3.0
const FADE_TIME := 0.2
const MARGIN := 6.0
const SPACING := 4.0

var _stacks: Dictionary = {}  # Position -> Array[Control]
var _root: Control
var _vp_size: Vector2


func _ready() -> void:
	layer = 95
	_vp_size = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)
	_root = Control.new()
	_root.name = "NotificationRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	for pos: int in Position.values():
		_stacks[pos] = []


func notify(
	text: String,
	pos: Position = Position.TOP_RIGHT,
	style: Style = Style.INFO,
	duration: float = DEFAULT_DURATION
) -> void:
	var popup := _create_popup(text, style, pos)
	_root.add_child(popup)

	await get_tree().process_frame

	_stacks[pos].append(popup)
	_position_popup(popup, pos)

	# 滑入 + 淡入
	var slide_offset := _get_slide_offset(pos)
	popup.position += slide_offset
	popup.modulate.a = 0.0
	var tween_in := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween_in.tween_property(popup, "position", popup.position - slide_offset, FADE_TIME)
	tween_in.tween_property(popup, "modulate:a", 1.0, FADE_TIME)

	await get_tree().create_timer(duration).timeout

	# 滑出 + 淡出
	var tween_out := create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween_out.tween_property(popup, "position", popup.position + slide_offset, FADE_TIME)
	tween_out.tween_property(popup, "modulate:a", 0.0, FADE_TIME)
	await tween_out.finished

	_stacks[pos].erase(popup)
	popup.queue_free()
	_reposition_stack(pos)


func _get_slide_offset(pos: Position) -> Vector2:
	match pos:
		Position.TOP_LEFT, Position.BOTTOM_LEFT:
			return Vector2(-20, 0)
		Position.TOP_RIGHT, Position.BOTTOM_RIGHT:
			return Vector2(20, 0)
		Position.TOP_CENTER:
			return Vector2(0, -15)
		Position.BOTTOM_CENTER:
			return Vector2(0, 15)
		Position.CENTER:
			return Vector2(0, -10)
	return Vector2.ZERO


func _create_popup(text: String, style: Style, pos: Position) -> PanelContainer:
	var is_bar := pos in [Position.TOP_CENTER, Position.BOTTOM_CENTER]
	var is_center := pos == Position.CENTER

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# StyleBox — 根据位置调整样式
	var sb := StyleBoxFlat.new()
	sb.bg_color = STYLE_COLORS[style]
	sb.border_color = STYLE_BORDER_COLORS[style]

	if is_center:
		# 中间：更大、更圆润、更突出
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 20.0
		sb.content_margin_right = 20.0
		sb.content_margin_top = 12.0
		sb.content_margin_bottom = 12.0
		# 加阴影
		sb.shadow_color = Color(0, 0, 0, 0.4)
		sb.shadow_size = 4
	elif is_bar:
		# 横幅：宽、扁、小圆角
		sb.set_border_width_all(1)
		sb.border_width_top = 0 if pos == Position.TOP_CENTER else 1
		sb.border_width_bottom = 0 if pos == Position.BOTTOM_CENTER else 1
		sb.set_corner_radius_all(0)
		sb.content_margin_left = 12.0
		sb.content_margin_right = 12.0
		sb.content_margin_top = 5.0
		sb.content_margin_bottom = 5.0
	else:
		# 角落：紧凑
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 8.0
		sb.content_margin_right = 8.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0

	# 左侧加一条样式色彩条
	if not is_bar:
		sb.border_width_left = 3
		sb.border_color = STYLE_BORDER_COLORS[style]

	panel.add_theme_stylebox_override("panel", sb)

	# 内容：图标 + 文字
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 6 if is_center else 4)

	# 图标
	var icon_label := Label.new()
	icon_label.text = STYLE_ICON[style]
	icon_label.add_theme_color_override("font_color", STYLE_ICON_COLORS[style])
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_center:
		icon_label.add_theme_font_size_override("font_size", 32)
		icon_label.scale = Vector2(0.75, 0.75)
	else:
		icon_label.add_theme_font_size_override("font_size", 16)
		icon_label.scale = Vector2(0.75, 0.75)
	hbox.add_child(icon_label)

	# 文字（RichTextLabel 支持 BBCode）
	var text_label := RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.add_theme_color_override("default_color", Color.WHITE)
	if is_center:
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_label.custom_minimum_size.x = 360.0
		text_label.add_theme_font_size_override("normal_font_size", 16)
	elif is_bar:
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_label.custom_minimum_size.x = _vp_size.x - MARGIN * 2 - 40.0
		text_label.add_theme_font_size_override("normal_font_size", 12)
	else:
		text_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		text_label.custom_minimum_size.x = 180.0
		text_label.add_theme_font_size_override("normal_font_size", 12)
	text_label.text = text
	hbox.add_child(text_label)

	panel.add_child(hbox)

	# 横幅模式：设定宽度撑满
	if is_bar:
		panel.custom_minimum_size.x = _vp_size.x - MARGIN * 2

	return panel


func _position_popup(popup: Control, pos: Position) -> void:
	var popup_size := popup.size
	var stack_offset := _get_stack_offset(pos, popup)

	match pos:
		Position.TOP_LEFT:
			popup.position = Vector2(MARGIN, MARGIN + stack_offset)
		Position.TOP_RIGHT:
			popup.position = Vector2(_vp_size.x - popup_size.x - MARGIN, MARGIN + stack_offset)
		Position.BOTTOM_LEFT:
			popup.position = Vector2(MARGIN, _vp_size.y - popup_size.y - MARGIN - stack_offset)
		Position.BOTTOM_RIGHT:
			popup.position = Vector2(_vp_size.x - popup_size.x - MARGIN, _vp_size.y - popup_size.y - MARGIN - stack_offset)
		Position.TOP_CENTER:
			popup.position = Vector2((_vp_size.x - popup_size.x) / 2.0, MARGIN + stack_offset)
		Position.BOTTOM_CENTER:
			popup.position = Vector2((_vp_size.x - popup_size.x) / 2.0, _vp_size.y - popup_size.y - MARGIN - stack_offset)
		Position.CENTER:
			popup.position = Vector2((_vp_size.x - popup_size.x) / 2.0, (_vp_size.y - popup_size.y) / 2.0 + stack_offset)


func _get_stack_offset(pos: Position, current_popup: Control) -> float:
	var offset := 0.0
	for item: Control in _stacks[pos]:
		if item == current_popup:
			break
		offset += item.size.y + SPACING
	return offset


func _reposition_stack(pos: Position) -> void:
	for item: Control in _stacks[pos]:
		_position_popup(item, pos)
