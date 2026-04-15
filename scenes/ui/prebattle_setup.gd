class_name PrebattleSetup
extends Control

const SKILL_TYPE_NAMES := {
	Enums.SkillType.ATTACK: "攻击",
	Enums.SkillType.ASSIST: "辅助",
	Enums.SkillType.INTERACT: "交互",
	Enums.SkillType.ASSIST_INTERACT: "辅助",
}

const CARD_BG := Color(0.13, 0.15, 0.19, 0.96)
const CARD_BG_HOVER := Color(0.16, 0.19, 0.24, 0.96)
const CARD_BORDER := Color(0.28, 0.32, 0.38, 1.0)
const CARD_BORDER_SELECTED := Color(0.82, 0.68, 0.35, 1.0)
const CARD_BORDER_LOCKED := Color(0.45, 0.50, 0.56, 0.6)
const CARD_BG_LOCKED := Color(0.10, 0.11, 0.14, 0.96)

@onready var title_label: Label = %Title
@onready var level_label: Label = %LevelLabel
@onready var equipped_count_label: Label = %EquippedCountLabel
@onready var card_grid: GridContainer = %CardGrid
@onready var continue_button: Button = %ContinueButton

var _transitioning := false
var _card_map: Dictionary = {}  # skill_id -> PanelContainer


func _ready() -> void:
	level_label.text = "当前关卡：%s" % GameState.selected_level
	title_label.text = "战前技能装配"
	Progress.progress_changed.connect(_rebuild, CONNECT_REFERENCE_COUNTED)
	for button in find_children("*", "BaseButton", true, false):
		UiSounds.bind_button(button as BaseButton)
	_rebuild()
	UiSounds.play_popup()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()


func _rebuild() -> void:
	_card_map.clear()
	for child in card_grid.get_children():
		child.queue_free()

	var equipped_ids := Progress.get_equipped_skill_ids()
	var effective_max := Progress.get_effective_max_equipped()
	equipped_count_label.text = "已装配 %d / %d" % [equipped_ids.size(), effective_max]

	for skill_id in Progress.get_unlocked_skill_ids():
		var skill := Progress.get_skill_resource(skill_id)
		if skill == null:
			continue
		var is_locked := Progress.is_stage_limited_skill(skill_id)
		var is_selected := skill_id in equipped_ids
		var card := _build_card(skill, is_selected, is_locked)
		card_grid.add_child(card)
		_card_map[skill_id] = card

	continue_button.disabled = equipped_ids.size() != effective_max


func _build_card(skill: SkillData, selected: bool, locked: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_card_style(card, selected, locked, skill.damage_element)

	# --- 内部布局 ---
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# 第一行：技能名 + 标签
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.text = skill.skill_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color.WHITE if not locked else Color(0.6, 0.63, 0.68))
	header.add_child(name_label)

	# 类型标签
	var type_badge := _make_badge(SKILL_TYPE_NAMES.get(skill.skill_type, ""), Color(0.45, 0.55, 0.7))
	header.add_child(type_badge)

	# 元素标签
	if skill.damage_element != Enums.Element.NONE:
		var elem_badge := _make_badge(
			ElementDefs.element_logo(skill.damage_element),
			ElementDefs.get_color(skill.damage_element)
		)
		header.add_child(elem_badge)

	# 关卡限定标签
	if locked:
		var lock_badge := _make_badge("关卡限定", Color(0.55, 0.45, 0.3))
		header.add_child(lock_badge)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	# AP 消耗
	var ap_label := Label.new()
	ap_label.text = "AP %d" % skill.ap_cost
	ap_label.add_theme_font_size_override("font_size", 12)
	ap_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.40) if not locked else Color(0.5, 0.5, 0.5))
	header.add_child(ap_label)

	# 描述
	var desc_label := Label.new()
	desc_label.text = skill.description
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.74) if not locked else Color(0.45, 0.48, 0.52))
	vbox.add_child(desc_label)

	# 选中指示器
	if not locked:
		var indicator := Label.new()
		indicator.text = "● 已装配" if selected else ""
		indicator.add_theme_font_size_override("font_size", 10)
		indicator.add_theme_color_override("font_color", CARD_BORDER_SELECTED)
		indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vbox.add_child(indicator)

	# 点击事件
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
	badge_style.content_margin_left = 5
	badge_style.content_margin_right = 5
	badge_style.content_margin_top = 1
	badge_style.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", badge_style)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color)
	badge.add_child(label)
	return badge


func _apply_card_style(card: PanelContainer, selected: bool, locked: bool, element: Enums.Element) -> void:
	var style := StyleBoxFlat.new()

	if locked:
		style.bg_color = CARD_BG_LOCKED
		style.border_color = CARD_BORDER_LOCKED
	elif selected:
		style.bg_color = Color(0.14, 0.16, 0.21, 0.98)
		style.border_color = CARD_BORDER_SELECTED
	else:
		style.bg_color = CARD_BG
		style.border_color = CARD_BORDER

	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(6)

	# 左侧元素色条
	if not locked and element != Enums.Element.NONE:
		style.border_width_left = 4
		style.border_color = style.border_color  # 保持整体边框色
		# 用 content margin 模拟左侧色条效果
		style.content_margin_left = 2

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
		# rebuild 时会重新设置样式，这里简单恢复
		var skill := Progress.get_skill_resource(skill_id)
		if skill:
			_apply_card_style(card, is_equipped, false, skill.damage_element)


func _on_continue_button_pressed() -> void:
	if _transitioning or Progress.get_equipped_skill_ids().size() != Progress.get_effective_max_equipped():
		return
	_transitioning = true
	GameState.transition_to_scene(GameState.pending_battle_scene)


func _on_back_button_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true
	GameState.transition_to_scene("res://scenes/menu/main_menu.tscn")
