class_name ProgressPanel
extends CanvasLayer

signal closed

const SKILL_TYPE_NAMES := {
	Enums.SkillType.ATTACK: "攻击",
	Enums.SkillType.ASSIST: "辅助",
	Enums.SkillType.INTERACT: "交互",
	Enums.SkillType.ASSIST_INTERACT: "辅助",
}

const CARD_BG := Color(0.94, 0.89, 0.77, 0.92)
const CARD_BG_HOVER := Color(0.88, 0.8, 0.65, 0.95)
const CARD_BORDER := Color(0.35, 0.25, 0.15, 0.7)
const CARD_BORDER_SELECTED := Color(0.55, 0.35, 0.12, 1.0)
const CARD_BORDER_LOCKED := Color(0.45, 0.4, 0.34, 0.55)
const CARD_BG_LOCKED := Color(0.84, 0.8, 0.72, 0.75)
const TEXT_INK := Color(0.15, 0.09, 0.05, 1)
const TEXT_INK_MUTED := Color(0.4, 0.32, 0.22, 1)
const TEXT_INK_LOCKED := Color(0.55, 0.48, 0.4, 1)
const TEXT_ACCENT := Color(0.55, 0.35, 0.12, 1)

@export var show_debug_controls := false

@onready var level_list: VBoxContainer = %LevelList
@onready var equipped_count_label: Label = %EquippedCountLabel
@onready var skill_list: GridContainer = %SkillList
@onready var debug_row: HBoxContainer = %DebugRow
@onready var unlock_all_button: Button = %UnlockAllButton
@onready var reset_button: Button = %ResetButton
@onready var preset_box: OptionButton = %PresetBox

var _card_map: Dictionary = {}


func _ready() -> void:
	layer = 96
	Progress.progress_changed.connect(_rebuild, CONNECT_REFERENCE_COUNTED)
	_rebuild()
	for button in find_children("*", "BaseButton", true, false):
		UiSounds.bind_button(button as BaseButton)
	debug_row.visible = show_debug_controls


func _unhandled_input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		_close()


func _rebuild() -> void:
	_rebuild_levels()
	_rebuild_skills()
	_rebuild_debug_presets()


func _rebuild_levels() -> void:
	for child in level_list.get_children():
		child.queue_free()
	for row in Progress.get_level_summary():
		var label := Label.new()
		var state := "未解锁"
		var level_name := str(row["level_name"])
		if row["completed"]:
			state = "已完成"
		elif row["unlocked"]:
			state = "已解锁"
		label.text = "%s  %s" % [level_name, state]
		var growth_ids := Progress.get_level_growth_choice_ids(level_name)
		if not growth_ids.is_empty():
			var growth_names: Array[String] = []
			for growth_id in growth_ids:
				growth_names.append(Progress.get_growth_option_name(growth_id))
			label.text += "  成长:%s" % "、".join(growth_names)
		level_list.add_child(label)


func _rebuild_skills() -> void:
	_card_map.clear()
	for child in skill_list.get_children():
		child.queue_free()
	var equipped_ids := Progress.get_equipped_skill_ids()
	equipped_count_label.text = "已装备 %d / %d" % [equipped_ids.size(), Progress.get_effective_max_equipped()]

	for skill_id in Progress.get_unlocked_skill_ids():
		var skill := Progress.get_skill_resource(skill_id)
		if skill == null:
			continue
		var is_locked := Progress.is_stage_limited_skill(skill_id)
		var is_selected := skill_id in equipped_ids
		var card := _build_skill_card(skill, is_selected, is_locked)
		skill_list.add_child(card)
		_card_map[skill_id] = card


func _build_skill_card(skill: SkillData, selected: bool, locked: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_card_style(card, selected, locked)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# 标题行
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.text = skill.skill_name
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", TEXT_INK if not locked else TEXT_INK_LOCKED)
	header.add_child(name_label)

	var type_badge := _make_badge(SKILL_TYPE_NAMES.get(skill.skill_type, ""), Color(0.45, 0.55, 0.7))
	header.add_child(type_badge)

	if skill.damage_element != Enums.Element.NONE:
		var elem_badge := _make_badge(ElementDefs.element_logo(skill.damage_element), ElementDefs.get_color(skill.damage_element))
		header.add_child(elem_badge)

	if locked:
		var lock_badge := _make_badge("关卡限定", Color(0.55, 0.45, 0.3))
		header.add_child(lock_badge)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var ap_label := Label.new()
	ap_label.text = "AP %d" % skill.ap_cost
	ap_label.add_theme_font_size_override("font_size", 10)
	ap_label.add_theme_color_override("font_color", TEXT_ACCENT if not locked else TEXT_INK_LOCKED)
	header.add_child(ap_label)

	# 描述
	var desc_label := Label.new()
	desc_label.text = skill.description
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 10)
	desc_label.add_theme_color_override("font_color", TEXT_INK_MUTED if not locked else TEXT_INK_LOCKED)
	vbox.add_child(desc_label)

	if not locked:
		var indicator := Label.new()
		indicator.text = "● 已装配" if selected else ""
		indicator.add_theme_font_size_override("font_size", 9)
		indicator.add_theme_color_override("font_color", CARD_BORDER_SELECTED)
		indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vbox.add_child(indicator)

	if not locked:
		card.gui_input.connect(_on_card_input.bind(skill.skill_id))
		card.mouse_entered.connect(_on_card_hover.bind(skill.skill_id, true))
		card.mouse_exited.connect(_on_card_hover.bind(skill.skill_id, false))

	return card


func _make_badge(text: String, color: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(color.r, color.g, color.b, 0.18)
	badge_style.border_color = Color(color.r, color.g, color.b, 0.5)
	badge_style.set_border_width_all(1)
	badge_style.set_corner_radius_all(3)
	badge_style.content_margin_left = 4
	badge_style.content_margin_right = 4
	badge_style.content_margin_top = 1
	badge_style.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", badge_style)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", color)
	badge.add_child(label)
	return badge


func _apply_card_style(card: PanelContainer, selected: bool, locked: bool) -> void:
	var style := StyleBoxFlat.new()
	if locked:
		style.bg_color = CARD_BG_LOCKED
		style.border_color = CARD_BORDER_LOCKED
	elif selected:
		style.bg_color = Color(0.98, 0.91, 0.76, 0.96)
		style.border_color = CARD_BORDER_SELECTED
	else:
		style.bg_color = CARD_BG
		style.border_color = CARD_BORDER
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(5)
	card.add_theme_stylebox_override("panel", style)


func _on_card_input(event: InputEvent, skill_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var is_equipped := Progress.is_skill_equipped(skill_id)
		var ok := Progress.set_skill_equipped(skill_id, not is_equipped)
		if not ok:
			Notify.notify("最多装配 %d 个自选技能" % Progress.get_effective_max_equipped(), Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)


func _on_card_hover(skill_id: String, entered: bool) -> void:
	var card: PanelContainer = _card_map.get(skill_id)
	if card == null:
		return
	var is_equipped := Progress.is_skill_equipped(skill_id)
	if entered and not is_equipped:
		var hover_style := (card.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
		hover_style.bg_color = CARD_BG_HOVER
		card.add_theme_stylebox_override("panel", hover_style)
	elif not entered:
		_apply_card_style(card, is_equipped, false)


func _rebuild_debug_presets() -> void:
	if preset_box.item_count > 0:
		return
	preset_box.add_item("测试预设")
	preset_box.add_item("第一关后")
	preset_box.add_item("第二关后")
	preset_box.add_item("第三关后")


func _on_unlock_all_pressed() -> void:
	Progress.unlock_all_progress()
	Notify.notify("已解锁全部章节与技能", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.0)


func _on_reset_pressed() -> void:
	Progress.reset_progress()
	Notify.notify("进度已重置", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.0)


func _on_apply_preset_pressed() -> void:
	match preset_box.selected:
		1:
			Progress.apply_debug_stage_preset("关卡1-2")
		2:
			Progress.apply_debug_stage_preset("关卡1-3")
		3:
			Progress.apply_debug_stage_preset("关卡1-4")
		_:
			return
	Notify.notify("测试预设已应用", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.0)


func _on_close_pressed() -> void:
	_close()


func _close() -> void:
	closed.emit()
	queue_free()
