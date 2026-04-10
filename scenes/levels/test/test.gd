extends BaseLevel
## 测试关卡：验证完整战斗系统（技能、化势、buff/debuff、击退/拖拽）。
## 8 个单位：3 玩家 + 1 盟友AI + 4 敌方AI

# ── 预加载所有正式技能 ──
var _sk_rule_strike: SkillData = preload("res://data/skills/lc_rule_strike.tres")
var _sk_wedge: SkillData = preload("res://data/skills/lc_wedge_bank_probe.tres")
var _sk_stone: SkillData = preload("res://data/skills/lc_cast_stone_arrest_flow.tres")
var _sk_read_water: SkillData = preload("res://data/skills/lc_read_water_fix_site.tres")
var _sk_pile_bind: SkillData = preload("res://data/skills/lc_pile_bind_wave.tres")
var _sk_mallet: SkillData = preload("res://data/skills/cg_mallet_strike.tres")
var _sk_guard: SkillData = preload("res://data/skills/cg_guard_the_works.tres")
var _sk_staff: SkillData = preload("res://data/skills/sw_staff_end_strike.tres")
var _sk_survey: SkillData = preload("res://data/skills/sw_field_measure_site.tres")
var _sk_lunge: SkillData = preload("res://data/skills/dc_hidden_current_lunge.tres")
var _sk_pull: SkillData = preload("res://data/skills/wp_spiral_pull.tres")
var _sk_crush: SkillData = preload("res://data/skills/bmw_crumbling_bank_crush.tres")

# ── 保存节点引用（get_teams_config 在 reparent 之前调用）──
var _player: Node2D
var _playerB: Node2D
var _playerC: Node2D
var _ally1: Node2D
var _enemy1: Node2D
var _enemy2: Node2D
var _enemy3: Node2D
var _enemy4: Node2D


func get_teams_config() -> Array:
	_player = $"Entities/Units/Player"
	_playerB = $"Entities/Units/PlayerB"
	_playerC = $"Entities/Units/PlayerC"
	_ally1 = $"Entities/Units/Ally1"
	_enemy1 = $"Entities/Units/Enemy1"
	_enemy2 = $"Entities/Units/Enemy2"
	_enemy3 = $"Entities/Units/Enemy3"
	_enemy4 = $"Entities/Units/Enemy4"
	return [
		{
			"name": "玩家队伍",
			"faction": "好人",
			"controller": "player",
			"units": [_player, _playerB, _playerC],
		},
		{
			"name": "盟友队伍",
			"faction": "好人",
			"controller": "ai",
			"units": [_ally1],
		},
		{
			"name": "贼人队伍",
			"faction": "坏人",
			"controller": "ai",
			"units": [_enemy1, _enemy2, _enemy3, _enemy4],
		},
	]


func _on_level_ready() -> void:
	# 测试关卡专用：敌人一轮内最多走 4 步，便于观察镜头跟随效果。
	ai_max_move_steps = 4
	# ── 分配正式技能 ──
	_assign_skills(_player, [_sk_rule_strike, _sk_wedge, _sk_stone, _sk_read_water, _sk_pile_bind])
	_assign_skills(_playerB, [_sk_mallet, _sk_guard])
	_assign_skills(_playerC, [_sk_staff, _sk_survey])
	_assign_skills(_enemy1, [_sk_lunge])
	_assign_skills(_enemy2, [_sk_pull])
	_assign_skills(_enemy3, [_sk_crush])
	_assign_skills(_enemy4, [_sk_lunge])

	# ── 覆盖属性值（数值.md 正式数据）──
	_set_stats(_player, "李春", 130, 24, 100, 8, Enums.Element.NONE, 0, true)
	_set_stats(_playerB, "工匠", 110, 18, 90, 9, Enums.Element.NONE, 0, false)
	_set_stats(_playerC, "测量工", 80, 12, 85, 10, Enums.Element.NONE, 0, false)
	_set_stats(_ally1, "队友", 100, 10, 100, 10, Enums.Element.NONE, 0, false)
	_set_stats(_enemy1, "暗涌", 68, 17, 100, 10, Enums.Element.WATER, 2, false)
	_set_stats(_enemy2, "水旋", 75, 14, 100, 10, Enums.Element.WATER, 2, false)
	_set_stats(_enemy3, "坍岸泥鬼", 92, 15, 100, 10, Enums.Element.EARTH, 2, false)
	_set_stats(_enemy4, "暗涌2", 68, 17, 100, 10, Enums.Element.WATER, 2, false)


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
