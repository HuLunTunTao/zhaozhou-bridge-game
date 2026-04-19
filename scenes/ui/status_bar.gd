extends HBoxContainer
## 底部状态栏：左侧头像+信息区，右侧 1移动+5技能 固定槽位。
## 所有 UI 组件在 status_bar.tscn 中静态定义，脚本仅负责数据绑定。

signal skill_button_pressed(index: int)
signal move_button_pressed
signal keyword_clicked(keyword: String)

const KEYWORD_TOOLTIP_SCENE := preload("res://scenes/ui/keyword_tooltip.tscn")
const TOOLTIP_MOUSE_OFFSET := Vector2(14.0, -8.0)

const COLOR_HERO := Color(0.15, 0.22, 0.55, 0.9)
const COLOR_HERO_DEFAULT := Color(0.25, 0.22, 0.4, 0.7)  # 淡蓝色，默认显示主角时使用
const COLOR_ALLY := Color(0.15, 0.45, 0.2, 0.9)
const COLOR_ENEMY := Color(0.5, 0.15, 0.15, 0.9)
const COLOR_DEFAULT := Color(0.12, 0.12, 0.15, 0.9)
const MAX_SKILLS := 5

# AI辅助生成， Kimi Code，2026-04-19

const BG_YELLOW := preload("res://assets/face_background/yellow.png")
const BG_GREEN := preload("res://assets/face_background/green.png")
const BG_RED := preload("res://assets/face_background/red.png")
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
var _tooltip: PanelContainer = null
var _tooltip_title: Label = null
var _tooltip_body: RichTextLabel = null

# 头像动画播放状态：当 unit_data.portrait 缺省时，从 Visual 的朝右 idle 动画里循环采帧。
var _portrait_frames: SpriteFrames = null
var _portrait_anim: StringName = &""
var _portrait_frame_idx: int = 0
var _portrait_accum: float = 0.0

@onready var _portrait: TextureRect = %Portrait
@onready var _portrait_bg: TextureRect = %PortraitBg
@onready var _name_label: Label = %NameLabel
@onready var _atk_label: Label = %AtkLabel
@onready var _actions_label: Label = %ActionsLabel
@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp_label: Label = %HpLabel
@onready var _ap_bar: ProgressBar = %ApBar
@onready var _ap_label: Label = %ApLabel
@onready var _cur_elem_logo: Label = %CurElemLogo
@onready var _cur_elem_value: Label = %CurElemValue
@onready var _inn_elem_logo: Label = %InnElemLogo
@onready var _inn_elem_value: Label = %InnElemValue
@onready var _buff_label: Label = %BuffValue

@onready var _slots: Array[Button] = [%Slot0, %Slot1, %Slot2, %Slot3, %Slot4, %Slot5]


func _ready() -> void:
	_ensure_tooltip()
	clear_unit()


func _ensure_tooltip() -> void:
	if _tooltip != null:
		return
	_tooltip = KEYWORD_TOOLTIP_SCENE.instantiate()
	add_child(_tooltip)
	_tooltip_title = _tooltip.get_node("VBox/Title") as Label
	_tooltip_body = _tooltip.get_node("VBox/Body") as RichTextLabel


func _process(delta: float) -> void:
	if _tooltip != null and _tooltip.visible:
		_position_tooltip_at_mouse()
	_advance_portrait_animation(delta)


func _on_move_pressed() -> void:
	move_button_pressed.emit()


func _on_skill_pressed(index: int) -> void:
	skill_button_pressed.emit(index)


func _on_desc_meta_clicked(meta: Variant) -> void:
	keyword_clicked.emit(str(meta))


func _on_desc_meta_hover_started(meta: Variant) -> void:
	var keyword := str(meta)
	var desc := DescriptionFormatter.get_description(keyword)
	if desc.is_empty():
		return
	_ensure_tooltip()
	_tooltip_title.text = keyword
	_tooltip_body.text = desc
	_tooltip.reset_size()
	_tooltip.visible = true
	_tooltip.move_to_front()
	_position_tooltip_at_mouse()


func _on_desc_meta_hover_ended(_meta: Variant) -> void:
	if _tooltip != null:
		_tooltip.visible = false


func _position_tooltip_at_mouse() -> void:
	if _tooltip == null:
		return
	var vp_size := get_viewport_rect().size
	var mouse := get_viewport().get_mouse_position()
	var tsize := _tooltip.size
	# 默认在鼠标右上方，若超出屏幕再翻转到左侧/下方
	var pos := Vector2(
		mouse.x + TOOLTIP_MOUSE_OFFSET.x,
		mouse.y - tsize.y + TOOLTIP_MOUSE_OFFSET.y
	)
	if pos.x + tsize.x > vp_size.x:
		pos.x = mouse.x - tsize.x - TOOLTIP_MOUSE_OFFSET.x
	if pos.y < 0.0:
		pos.y = mouse.y + 16.0
	pos.x = clampf(pos.x, 0.0, maxf(0.0, vp_size.x - tsize.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, vp_size.y - tsize.y))
	_tooltip.global_position = pos


# ─────────────────────────────────────────────
# 公开接口
# ─────────────────────────────────────────────

func show_unit(unit: Node2D, is_active: bool = false) -> void:
	_current_unit = unit
	var stats: CombatStats = unit.combat_stats if unit is Unit and unit.combat_stats != null else null

	if stats:
		_name_label.text = stats.unit_name
		_atk_label.text = "攻击力 %d" % stats.base_atk
		# 头像：优先 unit_data.portrait（静态），否则播放朝右 idle 动画。
		_setup_portrait(unit)
		_portrait_bg.texture = _get_portrait_bg(unit)

		_hp_bar.max_value = stats.max_hp
		_hp_bar.value = stats.current_hp
		_hp_label.text = "%d/%d" % [stats.current_hp, stats.max_hp]
		_update_hp_color(stats)

		_ap_bar.max_value = stats.ap_max
		_ap_bar.value = stats.ap_current
		_ap_label.text = "%d/%d" % [stats.ap_current, stats.ap_max]

		_update_element(_cur_elem_logo, _cur_elem_value, stats.current_element, stats.current_element_amount)
		_update_element(_inn_elem_logo, _inn_elem_value, stats.innate_element, stats.innate_element_amount)

		# 行动次数显示：不需要时隐藏以节省空间。
		if not stats.is_hero and stats.camp == Enums.Camp.ALLY:
			var parts: Array[String] = []
			if stats.move_limit >= 0:
				parts.append("移动:%d/%d" % [maxi(stats.move_limit - stats.moves_used, 0), stats.move_limit])
			if stats.skill_limit >= 0:
				parts.append("技能:%d/%d" % [maxi(stats.skill_limit - stats.skills_used, 0), stats.skill_limit])
			_actions_label.text = " ".join(parts) if not parts.is_empty() else ""
			_actions_label.visible = not parts.is_empty()
		else:
			_actions_label.text = ""
			_actions_label.visible = false
	else:
		_name_label.text = unit.name
		_atk_label.text = ""
		_clear_portrait_animation()
		_portrait.texture = null
		_portrait_bg.texture = null
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
	if _tooltip != null:
		_tooltip.visible = false
	_clear_portrait_animation()
	_portrait.texture = null
	_portrait_bg.texture = null
	_name_label.text = "--"
	_atk_label.text = ""
	_hp_bar.value = 0
	_hp_label.text = ""
	_ap_bar.value = 0
	_ap_label.text = ""
	_actions_label.text = ""
	_actions_label.visible = false
	_buff_label.text = "无"
	_clear_elements()
	_set_panel_color(COLOR_DEFAULT)
	for i in range(_slots.size()):
		_set_slot(i, false, "", "", true)


# ─────────────────────────────────────────────
# 内部方法
# ─────────────────────────────────────────────

func _setup_portrait(unit: Node2D) -> void:
	# 静态肖像优先；否则从 Visual 拉朝右 idle 动画来循环播放。
	var data: UnitData = unit.unit_data if unit is Unit else null
	if data and data.portrait:
		_clear_portrait_animation()
		_portrait.texture = data.portrait
		return
	var visual: UnitVisual = null
	if unit is Unit:
		visual = unit.get_node_or_null("Visual") as UnitVisual
	if visual == null or visual.sprite_frames == null:
		_clear_portrait_animation()
		_portrait.texture = null
		return
	var anim: StringName = visual.get_idle_right_anim_name()
	if anim == StringName(""):
		_clear_portrait_animation()
		_portrait.texture = null
		return
	_portrait_frames = visual.sprite_frames
	_portrait_anim = anim
	_portrait_frame_idx = 0
	_portrait_accum = 0.0
	_portrait.texture = _portrait_frames.get_frame_texture(anim, 0)


func _clear_portrait_animation() -> void:
	_portrait_frames = null
	_portrait_anim = &""
	_portrait_frame_idx = 0
	_portrait_accum = 0.0


func _advance_portrait_animation(delta: float) -> void:
	if _portrait_frames == null or _portrait_anim == StringName(""):
		return
	var frame_count := _portrait_frames.get_frame_count(_portrait_anim)
	if frame_count <= 0:
		return
	var speed := _portrait_frames.get_animation_speed(_portrait_anim)
	if speed <= 0.0:
		return
	var duration := _portrait_frames.get_frame_duration(_portrait_anim, _portrait_frame_idx) / speed
	if duration <= 0.0:
		return
	_portrait_accum += delta
	while _portrait_accum >= duration:
		_portrait_accum -= duration
		_portrait_frame_idx = (_portrait_frame_idx + 1) % frame_count
		duration = _portrait_frames.get_frame_duration(_portrait_anim, _portrait_frame_idx) / speed
		if duration <= 0.0:
			break
	_portrait.texture = _portrait_frames.get_frame_texture(_portrait_anim, _portrait_frame_idx)


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
		_buff_label.text = "无"
		return
	var parts: Array[String] = []
	for s in stats.statuses:
		var sname: String = _STATUS_NAMES.get(s.status_id, s.status_id)
		parts.append("%s(%d)" % [sname, s.remaining_turns])
	_buff_label.text = " ".join(parts)


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
		var ratio := "x%.1f" % skill.damage_ratio if skill.damage_ratio > 0.0 else ""
		_set_slot(i + 1, true, skill.skill_name, desc, not stats.can_use_skill(skill), skill.damage_element, skill.attach_amount, ratio)


func _set_slot(index: int, active: bool, title: String, desc: String, disabled_flag: bool, element: Enums.Element = Enums.Element.NONE, attach_amount: int = 0, ratio: String = "") -> void:
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
		var d := btn.get_node_or_null("Desc") as RichTextLabel
		if d:
			d.text = "[center]%s[/center]" % DescriptionFormatter.format(desc)
			if not d.meta_clicked.is_connected(_on_desc_meta_clicked):
				d.meta_clicked.connect(_on_desc_meta_clicked)
			if not d.meta_hover_started.is_connected(_on_desc_meta_hover_started):
				d.meta_hover_started.connect(_on_desc_meta_hover_started)
			if not d.meta_hover_ended.is_connected(_on_desc_meta_hover_ended):
				d.meta_hover_ended.connect(_on_desc_meta_hover_ended)
		_ensure_ratio_label(btn).text = ratio
	else:
		btn.modulate = Color(1, 1, 1, 0)
		btn.disabled = true
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ensure_ratio_label(btn).text = ""


func _ensure_ratio_label(btn: Button) -> Label:
	var r := btn.get_node_or_null("Ratio") as Label
	if r == null:
		r = Label.new()
		r.name = "Ratio"
		r.anchor_left = 0.0
		r.anchor_right = 1.0
		r.anchor_top = 1.0
		r.anchor_bottom = 1.0
		r.offset_left = 2.0
		r.offset_right = -2.0
		r.offset_top = -12.0
		r.offset_bottom = -1.0
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r.add_theme_font_override("font", Fonts.PIXEL_10)
		r.add_theme_font_size_override("font_size", 10)
		r.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.9))
		btn.add_child(r)
	return r


func _get_portrait_bg(unit: Node2D) -> Texture2D:
	if unit is Unit and unit.combat_stats != null:
		var stats: CombatStats = unit.combat_stats
		if stats.is_hero:
			return BG_YELLOW
		match stats.camp:
			Enums.Camp.ALLY:
				return BG_GREEN
			Enums.Camp.ENEMY:
				return BG_RED
	return null


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
