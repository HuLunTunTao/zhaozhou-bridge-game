extends BaseLevel
## 第一关《踏勘洨河》

# ── 预加载李春技能 ──
var _sk_rule_strike: SkillData = preload("res://data/skills/lc_rule_strike.tres")
var _sk_wedge: SkillData = preload("res://data/skills/lc_wedge_bank_probe.tres")
var _sk_stone: SkillData = preload("res://data/skills/lc_cast_stone_arrest_flow.tres")
var _sk_read_water: SkillData = preload("res://data/skills/lc_read_water_fix_site.tres")

var _li_chun: Node2D


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/LiChun"
	return [
		{
			"name": "玩家队伍",
			"faction": "好人",
			"controller": "player",
			"units": [_li_chun],
		},
	]


func _on_level_ready() -> void:
	_assign_skills(_li_chun, [_sk_rule_strike, _sk_wedge, _sk_stone, _sk_read_water])
	_set_stats(_li_chun, "李春", 130, 24, 100, 8, Enums.Element.NONE, 0, true)


func _assign_skills(unit: Node2D, skills: Array) -> void:
	if not unit is Unit:
		return
	var u := unit as Unit
	if u.unit_data:
		u.unit_data = u.unit_data.duplicate()
		var typed: Array[SkillData] = []
		for s in skills:
			typed.append(s)
		u.unit_data.skills = typed


func _set_stats(unit: Node2D, uname: String, hp: int, atk: int, ap: int, move_cost: int, elem: Enums.Element, elem_amt: int, is_hero_flag: bool) -> void:
	if not unit is Unit:
		return
	var u := unit as Unit
	if u.combat_stats == null:
		return
	var s := u.combat_stats
	s.unit_name = uname
	s.max_hp = hp
	s.current_hp = hp
	s.base_atk = atk
	s.ap_max = ap
	s.ap_current = ap
	s.move_cost_per_tile = move_cost
	s.innate_element = elem
	s.innate_element_amount = elem_amt
	s.current_element = elem
	s.current_element_amount = elem_amt
	s.is_hero = is_hero_flag
