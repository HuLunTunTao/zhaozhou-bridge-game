class_name GrowthChoicePanel
extends CanvasLayer

signal options_confirmed(option_ids: Array[String])

const CARD_BG := Color(0.13, 0.15, 0.19, 0.96)
const CARD_BG_HOVER := Color(0.16, 0.19, 0.24, 0.96)
const CARD_BORDER := Color(0.28, 0.32, 0.38, 1.0)
const CARD_BORDER_SELECTED := Color(0.82, 0.68, 0.35, 1.0)

var panel_title := "结算成长"
var options: Array[Dictionary] = []
var required_selection_count := 2

var _selected_ids: Array[String] = []
var _card_map: Dictionary = {}  # option_id -> PanelContainer
var _hint_label: Label
var _confirm_button: Button


func _ready() -> void:
	layer = 98
	_build_ui()


func _unhandled_input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0.75)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(blocker)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780.0, 440.0)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -390.0
	panel.offset_top = -220.0
	panel.offset_right = 390.0
	panel.offset_bottom = 220.0
	var panel_bg := StyleBoxFlat.new()
	panel_bg.content_margin_left = 24
	panel_bg.content_margin_top = 18
	panel_bg.content_margin_right = 24
	panel_bg.content_margin_bottom = 18
	panel_bg.bg_color = Color(0.09, 0.10, 0.13, 0.97)
	panel_bg.border_width_left = 1
	panel_bg.border_width_top = 1
	panel_bg.border_width_right = 1
	panel_bg.border_width_bottom = 1
	panel_bg.border_color = Color(0.30, 0.35, 0.40, 1)
	panel_bg.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_bg)
	add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
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
	_hint_label.add_theme_font_size_override("font_size", 12)
	layout.add_child(_hint_label)
	_refresh_hint()

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	layout.add_child(grid)

	for option in options:
		var option_id := str(option.get("id", ""))
		var card := _build_card(option, false)
		grid.add_child(card)
		_card_map[option_id] = card

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


func _build_card(option: Dictionary, selected: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(340, 100)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_card_style(card, selected)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# 标题行
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.text = str(option.get("name", ""))
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	header.add_child(name_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	if selected:
		var sel_label := Label.new()
		sel_label.text = "● 已选"
		sel_label.add_theme_font_size_override("font_size", 11)
		sel_label.add_theme_color_override("font_color", CARD_BORDER_SELECTED)
		header.add_child(sel_label)

	# 描述
	var desc_label := Label.new()
	desc_label.text = str(option.get("description", ""))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.70, 0.73, 0.78))
	vbox.add_child(desc_label)

	var option_id := str(option.get("id", ""))
	card.gui_input.connect(_on_card_input.bind(option_id))
	card.mouse_entered.connect(_on_card_hover.bind(option_id, true))
	card.mouse_exited.connect(_on_card_hover.bind(option_id, false))

	return card


func _apply_card_style(card: PanelContainer, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	if selected:
		style.bg_color = Color(0.15, 0.17, 0.22, 0.98)
		style.border_color = CARD_BORDER_SELECTED
		style.set_border_width_all(2)
	else:
		style.bg_color = CARD_BG
		style.border_color = CARD_BORDER
		style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", style)


func _on_card_input(event: InputEvent, option_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if option_id in _selected_ids:
			_selected_ids.erase(option_id)
		else:
			_selected_ids.append(option_id)
		if _selected_ids.size() > required_selection_count:
			_selected_ids.remove_at(0)
		_refresh_all_cards()
		_refresh_hint()


func _on_card_hover(option_id: String, entered: bool) -> void:
	var card: PanelContainer = _card_map.get(option_id)
	if card == null:
		return
	if entered and option_id not in _selected_ids:
		var hover_style := (card.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
		hover_style.bg_color = CARD_BG_HOVER
		card.add_theme_stylebox_override("panel", hover_style)
	elif not entered:
		_apply_card_style(card, option_id in _selected_ids)


func _refresh_all_cards() -> void:
	# 重建所有卡片内容以更新选中状态标签
	var grid: GridContainer = null
	for card_id in _card_map:
		var card: PanelContainer = _card_map[card_id]
		if grid == null:
			grid = card.get_parent() as GridContainer
		break
	if grid == null:
		return

	var old_cards := _card_map.duplicate()
	_card_map.clear()

	for option in options:
		var option_id := str(option.get("id", ""))
		var old_card: PanelContainer = old_cards.get(option_id)
		var selected := option_id in _selected_ids
		var new_card := _build_card(option, selected)
		if old_card:
			var idx := old_card.get_index()
			grid.remove_child(old_card)
			old_card.queue_free()
			grid.add_child(new_card)
			grid.move_child(new_card, idx)
		else:
			grid.add_child(new_card)
		_card_map[option_id] = new_card


func _refresh_hint() -> void:
	if _hint_label != null:
		var remaining := required_selection_count - _selected_ids.size()
		if remaining > 0:
			_hint_label.text = "选择 %d 个成长效果（还需选 %d 个）" % [required_selection_count, remaining]
			_hint_label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.74))
		else:
			_hint_label.text = "已选择 %d 个成长效果，点击确认" % required_selection_count
			_hint_label.add_theme_color_override("font_color", CARD_BORDER_SELECTED)
	if _confirm_button != null:
		_confirm_button.disabled = _selected_ids.size() != required_selection_count


func _on_confirm_pressed() -> void:
	if _selected_ids.size() != required_selection_count:
		return
	options_confirmed.emit(_selected_ids.duplicate())
	queue_free()
