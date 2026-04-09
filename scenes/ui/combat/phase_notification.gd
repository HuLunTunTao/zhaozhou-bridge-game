extends Control
## 化势提示：屏幕中央短暂闪现化势名称。

class_name PhaseNotification

var _label: Label


func _ready() -> void:
	# 全屏覆盖，不拦截输入
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	_label.add_theme_constant_override("outline_size", 4)
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_label.visible = false
	add_child(_label)


## 显示化势名称，短暂停留后淡出。
func show_phase(phase_name: String, category_name: String = "") -> void:
	var text := phase_name
	if category_name != "":
		text = "%s · %s" % [category_name, phase_name]
	_label.text = text
	_label.visible = true
	_label.modulate = Color.WHITE

	var tween := create_tween()
	tween.tween_interval(0.8)
	tween.tween_property(_label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): _label.visible = false)
