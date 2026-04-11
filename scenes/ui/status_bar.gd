extends HBoxContainer
## 底部状态栏：左侧头像+信息区，右侧 1移动+5技能 固定槽位。
## 所有 UI 组件在 status_bar.tscn 中静态定义，脚本仅负责数据绑定。

signal skill_button_pressed(index: int)
signal move_button_pressed

const COLOR_HERO := Color(0.15, 0.22, 0.55, 0.9)
const COLOR_HERO_DEFAULT := Color(0.25, 0.22, 0.4, 0.7)  # 淡蓝色，默认显示主角时使用
const COLOR_ALLY := Color(0.15, 0.45, 0.2, 0.9)
const COLOR_ENEMY := Color(0.5, 0.15, 0.15, 0.9)
const COLOR_DEFAULT := Color(0.12, 0.12, 0.15, 0.9)
const MAX_SKILLS := 5
const _STATUS_NAMES: Dictionary = {
	"rend": "裂伤",
	"fracture_step": "陷裂",
	"silt_lock": "壅水",
	"weakened": "攻衰",
	"brittle": "脆裂",
	"scorch_mark": "灼痕",
	"overgrow_bind": "蔓缚",
	"cold_damp": "湿寒",
	"smothered": "闷熄",
	"open_fissure": "开隙",
	"steady_step": "稳步",
	"slowed_step": "迟步",
	"hindered_step": "迟滞",
	"guarded_cover": "护持",
}

var _current_unit: Node2D = null

@onready var _portrait: TextureRect = %Portrait
@onready var _name_label: Label = %NameLabel
@onready var _actions_label: Label = %ActionsLabel
@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp_label: Label = %HpLabel
@onready var _ap_bar: ProgressBar = %ApBar
@onready var _ap_label: Label = %ApLabel
@onready var _cur_elem_logo: Label = %CurElemLogo
@onready var _cur_elem_value: Label = %CurElemValue
@onready var _inn_elem_logo: Label = %InnElemLogo
@onready var _inn_elem_value: Label = %InnElemValue
@onready var _buff_label: Label = %BuffLabel

@onready var _slots: Array[Button] = [%Slot0, %Slot1, %Slot2, %Slot3, %Slot4, %Slot5]


func _ready() -> void:
	clear_unit()


func _on_move_pressed() -> void:
	move_button_pressed.emit()


func _on_skill_pressed(index: int) -> void:
	skill_button_pressed.emit(index)


# ─────────────────────────────────────────────
# 公开接口
# ─────────────────────────────────────────────

func show_unit(unit: Node2D, is_active: bool = false) -> void:
	_current_unit = unit
	var stats: CombatStats = unit.combat_stats if unit is Unit and unit.combat_stats != null else null

	if stats:
		_name_label.text = stats.unit_name
		# 头像：从 unit_data.portrait 读取
		var data: UnitData = unit.unit_data if unit is Unit else null
		_portrait.texture = data.portrait if data and data.portrait else null

		_hp_bar.max_value = stats.max_hp
		_hp_bar.value = stats.current_hp
		_hp_label.text = "%d/%d" % [stats.current_hp, stats.max_hp]
		_update_hp_color(stats)

		_ap_bar.max_value = stats.ap_max
		_ap_bar.value = stats.ap_current
		_ap_label.text = "%d/%d" % [stats.ap_current, stats.ap_max]

		_update_element(_cur_elem_logo, _cur_elem_value, stats.current_element, stats.current_element_amount)
		_update_element(_inn_elem_logo, _inn_elem_value, stats.innate_element, stats.innate_element_amount)

		# 行动次数显示：
		# 不使用 visible=false 隐藏，而是设为透明色。
		# 原因：visible=false 会导致 VBoxContainer 重新布局，使不同单位的信息区高度不一致。
		# 保持节点始终 visible=true + 透明色可以让布局高度固定。
		if not stats.is_hero and stats.camp == Enums.Camp.ALLY:
			var parts: Array[String] = []
			if stats.move_limit >= 0:
				parts.append("移动:%d/%d" % [maxi(stats.move_limit - stats.moves_used, 0), stats.move_limit])
			if stats.skill_limit >= 0:
				parts.append("技能:%d/%d" % [maxi(stats.skill_limit - stats.skills_used, 0), stats.skill_limit])
			_actions_label.text = " ".join(parts) if not parts.is_empty() else " "
			_actions_label.self_modulate = Color.WHITE
		else:
			# 主角或敌方：保留占位空间但文字透明
			_actions_label.text = " "
			_actions_label.self_modulate = Color.TRANSPARENT
	else:
		_name_label.text = unit.name
		_portrait.texture = null
		_hp_bar.value = 0
		_hp_label.text = ""
		_ap_bar.value = 0
		_ap_label.text = ""
		_actions_label.text = " "
		_actions_label.self_modulate = Color.TRANSPARENT

	_update_buffs(stats)
	_set_panel_color(_get_faction_color(unit, is_active))
	_update_slots(unit, is_active, stats)


func clear_unit() -> void:
	_current_unit = null
	_portrait.texture = null
	_name_label.text = "--"
	_hp_bar.value = 0
	_hp_label.text = ""
	_ap_bar.value = 0
	_ap_label.text = ""
	_actions_label.text = " "
	_actions_label.self_modulate = Color.TRANSPARENT
	_buff_label.text = ""
	_buff_label.visible = false
	_clear_elements()
	_set_panel_color(COLOR_DEFAULT)
	for i in range(_slots.size()):
		_set_slot(i, false, "", "", true)


# ─────────────────────────────────────────────
# 内部方法
# ─────────────────────────────────────────────

func _update_hp_color(stats: CombatStats) -> void:
	var ratio := float(stats.current_hp) / float(stats.max_hp) if stats.max_hp > 0 else 0.0
	var fill := _hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		if ratio > 0.6:
			fill.bg_color = Color(0.2, 0.8, 0.3)
		elif ratio > 0.3:
			fill.bg_color = Color(0.9, 0.75, 0.2)
		else:
			fill.bg_color = Color(0.9, 0.2, 0.2)


func _update_element(logo_label: Label, value_label: Label, element: Enums.Element, amount: int) -> void:
	logo_label.text = str(ElementDefs.LOGOS.get(element, "?"))
	logo_label.add_theme_color_override("font_color", ElementDefs.get_color(element))
	if element != Enums.Element.NONE and amount > 0:
		value_label.text = "x%d" % amount
	else:
		value_label.text = "--"


func _clear_elements() -> void:
	_update_element(_cur_elem_logo, _cur_elem_value, Enums.Element.NONE, 0)
	_update_element(_inn_elem_logo, _inn_elem_value, Enums.Element.NONE, 0)


func _update_buffs(stats: CombatStats) -> void:
	if stats == null or stats.statuses.is_empty():
		_buff_label.text = ""
		_buff_label.visible = false
		return
	var parts: Array[String] = []
	for s in stats.statuses:
		var sname: String = _STATUS_NAMES.get(s.status_id, s.status_id)
		parts.append("%s(%d)" % [sname, s.remaining_turns])
	_buff_label.text = " ".join(parts)
	_buff_label.visible = true


func _update_slots(unit: Node2D, is_active: bool, stats: CombatStats) -> void:
	for i in range(_slots.size()):
		_set_slot(i, false, "", "", true)

	if not is_active or stats == null:
		return

	var move_disabled := not stats.can_move() or stats.ap_current <= 0
	_set_slot(0, true, "移动", "消耗AP移动\n每格%dAP" % stats.move_cost_per_tile, move_disabled)

	var data: UnitData = unit.unit_data if unit is Unit else null
	if data == null:
		return
	for i in range(mini(data.skills.size(), MAX_SKILLS)):
		var skill: SkillData = data.skills[i]
		var desc := skill.description if skill.description != "" else "消耗 %dAP" % skill.ap_cost
		_set_slot(i + 1, true, skill.skill_name, desc, not stats.can_use_skill(skill), skill.damage_element, skill.attach_amount)


func _set_slot(index: int, active: bool, title: String, desc: String, disabled_flag: bool, element: Enums.Element = Enums.Element.NONE, attach_amount: int = 0) -> void:
	var btn := _slots[index]
	if active:
		btn.modulate = Color.WHITE
		btn.disabled = disabled_flag
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var t := btn.get_node_or_null("Title") as Label
		if t:
			t.text = title
			if element != Enums.Element.NONE:
				t.add_theme_color_override("font_color", ElementDefs.get_color(element))
			else:
				t.add_theme_color_override("font_color", Color.WHITE)
		var et := btn.get_node_or_null("ElemTag") as Label
		if et:
			var tag := ElementDefs.element_tag(element, attach_amount)
			et.text = tag
			if tag != "":
				et.add_theme_color_override("font_color", ElementDefs.get_color(element))
		var d := btn.get_node_or_null("Desc") as Label
		if d:
			d.text = desc
	else:
		btn.modulate = Color(1, 1, 1, 0)
		btn.disabled = true
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_faction_color(unit: Node2D, is_active: bool = false) -> Color:
	var stats: CombatStats = unit.combat_stats if unit is Unit and unit.combat_stats != null else null
	if stats:
		if stats.is_hero:
			return COLOR_HERO if is_active else COLOR_HERO_DEFAULT
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
