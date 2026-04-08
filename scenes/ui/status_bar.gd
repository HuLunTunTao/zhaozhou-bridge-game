extends HBoxContainer
## 底部状态栏：左侧显示单位信息，右侧显示技能按钮。

signal skill_button_pressed(skill: SkillData)

const COLOR_HERO := Color(0.2, 0.3, 0.7, 0.8)
const COLOR_ALLY := Color(0.3, 0.7, 0.3, 0.8)
const COLOR_ENEMY := Color(0.7, 0.3, 0.3, 0.8)
const COLOR_DEFAULT := Color(0.15, 0.15, 0.15, 0.8)
const MAX_SKILLS := 5

var _name_label: Label
var _hp_label: Label
var _ap_label: Label
var _element_label: Label
var _actions_label: Label
var _skill_buttons: Array[Button] = []
var _spacer: Control
var _current_unit: Node2D = null

## 五行属性中文名。
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
	# 左侧信息标签
	_name_label = Label.new()
	add_child(_name_label)
	_add_separator()
	_hp_label = Label.new()
	add_child(_hp_label)
	_add_separator()
	_ap_label = Label.new()
	add_child(_ap_label)
	_add_separator()
	_element_label = Label.new()
	add_child(_element_label)
	_add_separator()
	_actions_label = Label.new()
	add_child(_actions_label)

	# 弹性空间推右
	_spacer = Control.new()
	_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_spacer)

	# 右侧5个技能按钮
	for i in range(MAX_SKILLS):
		var btn := Button.new()
		btn.visible = false
		btn.custom_minimum_size = Vector2(60, 0)
		var idx := i
		btn.pressed.connect(func(): _on_skill_pressed(idx))
		add_child(btn)
		_skill_buttons.append(btn)


func _add_separator() -> void:
	var sep := VSeparator.new()
	add_child(sep)


## 显示单位信息。is_active=true 时显示技能按钮。
func show_unit(unit: Node2D, is_active: bool = false) -> void:
	_current_unit = unit
	var stats: CombatStats = unit.combat_stats if unit is Unit and unit.combat_stats != null else null

	if stats:
		_name_label.text = stats.unit_name
		_hp_label.text = "HP:%d/%d" % [stats.current_hp, stats.max_hp]
		_ap_label.text = "AP:%d/%d" % [stats.ap_current, stats.ap_max]

		# 属性显示
		if stats.current_element != Enums.Element.NONE:
			_element_label.text = "%s×%d" % [ELEMENT_NAMES.get(stats.current_element, "?"), stats.current_element_amount]
			_element_label.visible = true
		else:
			_element_label.text = ""
			_element_label.visible = false

		# 行动次数（非主角的己方单位显示，-1表示无限不显示）
		if not stats.is_hero and stats.camp == Enums.Camp.ALLY:
			var parts: Array[String] = []
			if stats.move_limit >= 0:
				parts.append("移动:%d/%d" % [stats.move_limit - stats.moves_used, stats.move_limit])
			if stats.skill_limit >= 0:
				parts.append("技能:%d/%d" % [stats.skill_limit - stats.skills_used, stats.skill_limit])
			_actions_label.text = " ".join(parts)
			_actions_label.visible = not parts.is_empty()
		else:
			_actions_label.text = ""
			_actions_label.visible = false
	else:
		# 没有 combat_stats 时显示基本信息（unit_data 未分配）
		_name_label.text = unit.name
		_hp_label.text = "MP:%d" % unit.movement_points
		_ap_label.text = "格:%s" % str(unit.cell)
		_element_label.visible = false
		_actions_label.visible = false

	# 面板背景色
	_set_panel_color(_get_faction_color(unit))

	# 技能按钮
	_update_skill_buttons(unit, is_active, stats)


## 清空状态栏。
func clear_unit() -> void:
	_current_unit = null
	_name_label.text = "--"
	_hp_label.text = ""
	_ap_label.text = ""
	_element_label.visible = false
	_actions_label.visible = false
	_set_panel_color(COLOR_DEFAULT)
	for btn in _skill_buttons:
		btn.visible = false


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
		(panel as PanelContainer).add_theme_stylebox_override("panel", style)


func _update_skill_buttons(unit: Node2D, is_active: bool, stats: CombatStats) -> void:
	# 隐藏所有按钮
	for btn in _skill_buttons:
		btn.visible = false

	if not is_active or stats == null:
		return

	var data: UnitData = unit.unit_data if unit is Unit else null
	if data == null:
		return

	for i in range(mini(data.skills.size(), MAX_SKILLS)):
		var skill: SkillData = data.skills[i]
		var btn := _skill_buttons[i]
		btn.text = skill.skill_name
		btn.visible = true
		btn.disabled = not stats.can_use_skill(skill)


func _on_skill_pressed(index: int) -> void:
	if _current_unit == null:
		return
	var data: UnitData = _current_unit.unit_data if _current_unit is Unit else null
	if data and index < data.skills.size():
		skill_button_pressed.emit(data.skills[index])
