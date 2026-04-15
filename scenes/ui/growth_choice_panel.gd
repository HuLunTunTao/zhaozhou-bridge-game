class_name GrowthChoicePanel
extends CanvasLayer

signal options_confirmed(option_ids: Array[String])

var panel_title := "回合成长"
var options: Array[Dictionary] = []
var required_selection_count := 2

var _selected_ids: Array[String] = []
var _option_buttons: Dictionary = {}
var _hint_label: Label
var _confirm_button: Button


func _ready() -> void:
	layer = 98
	_build_ui()


func _unhandled_input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0.72)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(blocker)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760.0, 420.0)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -380.0
	panel.offset_top = -210.0
	panel.offset_right = 380.0
	panel.offset_bottom = 210.0
	var panel_bg := StyleBoxFlat.new()
	panel_bg.content_margin_left = 18
	panel_bg.content_margin_top = 14
	panel_bg.content_margin_right = 18
	panel_bg.content_margin_bottom = 14
	panel_bg.bg_color = Color(0.11, 0.13, 0.16, 0.96)
	panel_bg.border_width_left = 1
	panel_bg.border_width_top = 1
	panel_bg.border_width_right = 1
	panel_bg.border_width_bottom = 1
	panel_bg.border_color = Color(0.35, 0.4, 0.45, 1)
	panel.add_theme_stylebox_override("panel", panel_bg)
	add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)

	var title := Label.new()
	title.text = panel_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	layout.add_child(title)

	var separator_top := HSeparator.new()
	layout.add_child(separator_top)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(_hint_label)
	_refresh_hint()

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	layout.add_child(grid)

	for option in options:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 132.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.text = "%s\n%s" % [option.get("name", ""), option.get("description", "")]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		button.pressed.connect(_on_option_pressed.bind(str(option.get("id", ""))))
		grid.add_child(button)
		_option_buttons[str(option.get("id", ""))] = button
		UiSounds.bind_button(button)
		_apply_option_style(button, false)

	var separator_bottom := HSeparator.new()
	layout.add_child(separator_bottom)

	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(action_row)

	_confirm_button = Button.new()
	_confirm_button.text = "确认选择"
	_confirm_button.disabled = true
	_confirm_button.pressed.connect(_on_confirm_pressed)
	action_row.add_child(_confirm_button)
	UiSounds.bind_button(_confirm_button)


func _on_option_pressed(option_id: String) -> void:
	if option_id in _selected_ids:
		_selected_ids.erase(option_id)
	else:
		_selected_ids.append(option_id)
	if _selected_ids.size() > required_selection_count:
		_selected_ids.remove_at(0)
	_refresh_hint()


func _refresh_hint() -> void:
	if _hint_label != null:
		_hint_label.text = "结束本回合前，选择 %d 个成长效果  当前 %d / %d" % [required_selection_count, _selected_ids.size(), required_selection_count]
	if _confirm_button != null:
		_confirm_button.disabled = _selected_ids.size() != required_selection_count
	for option_id in _option_buttons.keys():
		var button := _option_buttons.get(option_id) as Button
		if button != null:
			_apply_option_style(button, option_id in _selected_ids)


func _on_confirm_pressed() -> void:
	if _selected_ids.size() != required_selection_count:
		return
	options_confirmed.emit(_selected_ids.duplicate())
	queue_free()


func _apply_option_style(button: Button, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.18, 0.22, 0.98) if selected else Color(0.14, 0.16, 0.2, 0.95)
	style.border_color = Color(0.82, 0.68, 0.35, 1.0) if selected else Color(0.32, 0.37, 0.42, 1.0)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_top = 10
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, style)
