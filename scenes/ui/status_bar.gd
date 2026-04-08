extends HBoxContainer
## 底部状态栏：左侧头像+信息区，右侧 1移动+5技能 固定槽位。
## 字体规则：基础字号 16px，缩小用 scale，保持像素字体清晰。

signal skill_button_pressed(index: int)
signal move_button_pressed

const COLOR_HERO := Color(0.15, 0.22, 0.55, 0.9)
const COLOR_ALLY := Color(0.15, 0.45, 0.2, 0.9)
const COLOR_ENEMY := Color(0.5, 0.15, 0.15, 0.9)
const COLOR_DEFAULT := Color(0.12, 0.12, 0.15, 0.9)
const MAX_SKILLS := 5
const FONT_BASE := 16
## 每个操作按钮的固定宽度。
const BTN_WIDTH := 100

var _current_unit: Node2D = null

var _portrait: ColorRect
var _name_label: Label
var _actions_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _ap_bar: ProgressBar
var _ap_label: Label
## 槽位 0 = 移动, 槽位 1~5 = 技能
var _slots: Array[Button] = []

const ELEMENT_NAMES: Dictionary = {
	Enums.Element.NONE: "",
	Enums.Element.METAL: "金",
	Enums.Element.WOOD: "木",
	Enums.Element.WATER: "水",
	Enums.Element.FIRE: "火",
	Enums.Element.EARTH: "土",
}


func _ready() -> void:
	_build_ui()
	clear_unit()


func _build_ui() -> void:
	add_theme_constant_override("separation", 4)

	# ── 左侧：头像占位 ──
	_portrait = ColorRect.new()
	_portrait.custom_minimum_size = Vector2(68, 68)
	_portrait.color = Color(0.2, 0.2, 0.3, 0.6)
	add_child(_portrait)

	# ── 中间：信息区 ──
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(180, 0)
	info.add_theme_constant_override("separation", 2)
	add_child(info)

	_name_label = _make_label(Color.WHITE, 1.0)
	info.add_child(_name_label)

	_actions_label = _make_label(Color(0.65, 0.75, 0.9), 0.5)
	info.add_child(_actions_label)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 4)
	info.add_child(hp_row)
	var hp_prefix := _make_label(Color(0.9, 0.4, 0.4), 0.5)
	hp_prefix.text = "HP"
	hp_row.add_child(hp_prefix)
	_hp_bar = _make_progress_bar(Color(0.2, 0.8, 0.3))
	hp_row.add_child(_hp_bar)
	_hp_label = _make_label(Color(0.85, 0.85, 0.85), 0.5)
	hp_row.add_child(_hp_label)

	var ap_row := HBoxContainer.new()
	ap_row.add_theme_constant_override("separation", 4)
	info.add_child(ap_row)
	var ap_prefix := _make_label(Color(0.4, 0.6, 0.9), 0.5)
	ap_prefix.text = "AP"
	ap_row.add_child(ap_prefix)
	_ap_bar = _make_progress_bar(Color(0.3, 0.5, 0.9))
	ap_row.add_child(_ap_bar)
	_ap_label = _make_label(Color(0.85, 0.85, 0.85), 0.5)
	ap_row.add_child(_ap_label)

	add_child(VSeparator.new())

	# ── 右侧：6 个固定槽位（移动 + 5技能），始终占位 ──
	for i in range(1 + MAX_SKILLS):
		var btn := _create_slot_button()
		if i == 0:
			btn.pressed.connect(func(): move_button_pressed.emit())
		else:
			var idx := i - 1
			btn.pressed.connect(func(): _on_skill_pressed(idx))
		add_child(btn)
		_slots.append(btn)


func _make_label(color: Color, scale_factor: float) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", FONT_BASE)
	lbl.add_theme_color_override("font_color", color)
	if scale_factor != 1.0:
		lbl.scale = Vector2(scale_factor, scale_factor)
	return lbl


func _make_progress_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(100, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = 100
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.15)
	bg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _create_slot_button() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(BTN_WIDTH, 0)
	btn.size_flags_horizontal = Control.SIZE_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 标题（16px）
	var title_label := Label.new()
	title_label.name = "Title"
	title_label.add_theme_font_size_override("font_size", FONT_BASE)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_label.offset_top = 2
	btn.add_child(title_label)

	# 描述（10px fusion-pixel 字体，适合小空间）
	var desc_label := Label.new()
	desc_label.name = "Desc"
	var desc_font := load("res://assets/font/fusion-pixel-10px-proportional-zh_hans.otf")
	desc_label.add_theme_font_override("font", desc_font)
	desc_label.add_theme_font_size_override("font_size", 10)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	desc_label.offset_top = 20
	desc_label.offset_left = 2
	desc_label.offset_right = -2
	btn.add_child(desc_label)

	return btn


func _set_slot(index: int, active: bool, title: String, desc: String, disabled_flag: bool) -> void:
	var btn := _slots[index]
	if active:
		btn.modulate = Color.WHITE
		btn.disabled = disabled_flag
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var t := btn.get_node_or_null("Title") as Label
		if t:
			t.text = title
		var d := btn.get_node_or_null("Desc") as Label
		if d:
			d.text = desc
	else:
		# 隐形占位：透明 + 不可交互
		btn.modulate = Color(1, 1, 1, 0)
		btn.disabled = true
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_unit(unit: Node2D, is_active: bool = false) -> void:
	_current_unit = unit
	var stats: CombatStats = unit.combat_stats if unit is Unit and unit.combat_stats != null else null

	if stats:
		_name_label.text = stats.unit_name
		if stats.current_element != Enums.Element.NONE:
			_name_label.text += "  %s×%d" % [ELEMENT_NAMES.get(stats.current_element, "?"), stats.current_element_amount]

		_hp_bar.max_value = stats.max_hp
		_hp_bar.value = stats.current_hp
		_hp_label.text = "%d/%d" % [stats.current_hp, stats.max_hp]
		var hp_ratio := float(stats.current_hp) / float(stats.max_hp) if stats.max_hp > 0 else 0.0
		var hp_fill := _hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if hp_fill:
			if hp_ratio > 0.6:
				hp_fill.bg_color = Color(0.2, 0.8, 0.3)
			elif hp_ratio > 0.3:
				hp_fill.bg_color = Color(0.9, 0.75, 0.2)
			else:
				hp_fill.bg_color = Color(0.9, 0.2, 0.2)

		_ap_bar.max_value = stats.ap_max
		_ap_bar.value = stats.ap_current
		_ap_label.text = "%d/%d" % [stats.ap_current, stats.ap_max]

		if not stats.is_hero and stats.camp == Enums.Camp.ALLY:
			var parts: Array[String] = []
			if stats.move_limit >= 0:
				parts.append("移动:%d/%d" % [maxi(stats.move_limit - stats.moves_used, 0), stats.move_limit])
			if stats.skill_limit >= 0:
				parts.append("技能:%d/%d" % [maxi(stats.skill_limit - stats.skills_used, 0), stats.skill_limit])
			_actions_label.text = " ".join(parts)
			_actions_label.visible = not parts.is_empty()
		else:
			_actions_label.text = ""
			_actions_label.visible = false
	else:
		_name_label.text = unit.name
		_hp_bar.value = 0
		_hp_label.text = ""
		_ap_bar.value = 0
		_ap_label.text = ""
		_actions_label.visible = false

	_set_panel_color(_get_faction_color(unit))
	_update_slots(unit, is_active, stats)


func clear_unit() -> void:
	_current_unit = null
	_name_label.text = "--"
	_hp_bar.value = 0
	_hp_label.text = ""
	_ap_bar.value = 0
	_ap_label.text = ""
	_actions_label.visible = false
	_set_panel_color(COLOR_DEFAULT)
	for i in range(_slots.size()):
		_set_slot(i, false, "", "", true)


func _update_slots(unit: Node2D, is_active: bool, stats: CombatStats) -> void:
	# 先全部设为隐形占位
	for i in range(_slots.size()):
		_set_slot(i, false, "", "", true)

	if not is_active or stats == null:
		return

	# 槽位 0: 移动
	var move_disabled := not stats.can_move() or stats.ap_current <= 0
	_set_slot(0, true, "移动", "消耗AP移动\n每格%dAP" % stats.move_cost_per_tile, move_disabled)

	# 槽位 1~5: 技能
	var data: UnitData = unit.unit_data if unit is Unit else null
	if data == null:
		return
	for i in range(mini(data.skills.size(), MAX_SKILLS)):
		var skill: SkillData = data.skills[i]
		var desc := skill.description if skill.description != "" else "消耗 %dAP" % skill.ap_cost
		_set_slot(i + 1, true, skill.skill_name, desc, not stats.can_use_skill(skill))


func _get_faction_color(unit: Node2D) -> Color:
	var stats: CombatStats = unit.combat_stats if unit is Unit and unit.combat_stats != null else null
	if stats:
		if stats.is_hero:
			return COLOR_HERO
		match stats.camp:
			Enums.Camp.ALLY:
				return COLOR_ALLY
			Enums.Camp.ENEMY:
				return COLOR_ENEMY
	return COLOR_DEFAULT


func _set_panel_color(color: Color) -> void:
	var panel := get_parent()
	while panel and not panel is PanelContainer:
		panel = panel.get_parent()
	if panel is PanelContainer:
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.border_color = Color(0.3, 0.35, 0.5, 0.6)
		style.set_border_width_all(1)
		style.set_corner_radius_all(2)
		(panel as PanelContainer).add_theme_stylebox_override("panel", style)


func _on_skill_pressed(index: int) -> void:
	skill_button_pressed.emit(index)
