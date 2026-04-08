extends BaseLevel
## 测试关卡：验证战斗系统（Phase 3~5）。
##   - 玩家队伍（好人阵营）：2个单位，带攻击技能
##   - 贼人队伍（坏人阵营）：2个单位，带水属性

# 预加载技能
var _sk_rule_strike: SkillData = preload("res://data/skills/lc_rule_strike.tres")
var _sk_wedge: SkillData = preload("res://data/skills/lc_wedge_bank_probe.tres")
var _sk_stone: SkillData = preload("res://data/skills/lc_cast_stone_arrest_flow.tres")
var _sk_staff: SkillData = preload("res://data/skills/sw_staff_end_strike.tres")
var _sk_lunge: SkillData = preload("res://data/skills/dc_hidden_current_lunge.tres")

# 保存节点引用（get_teams_config 在 reparent 之前调用）
var _player: Node2D
var _playerB: Node2D
var _ally1: Node2D
var _ally2: Node2D
var _enemy1: Node2D
var _enemy2: Node2D


func get_teams_config() -> Array:
	_player = $"Entities/Units/Player"
	_playerB = $"Entities/Units/PlayerB"
	_ally1 = $"Entities/Units/Ally1"
	_ally2 = $"Entities/Units/Ally2"
	_enemy1 = $"Entities/Units/Enemy1"
	_enemy2 = $"Entities/Units/Enemy2"
	return [
		{
			"name": "玩家队伍",
			"faction": "好人",
			"controller": "player",
			"units": [_player, _playerB],
		},
		{
			"name": "盟友队伍",
			"faction": "好人",
			"controller": "ai",
			"units": [_ally1, _ally2],
		},
		{
			"name": "贼人队伍",
			"faction": "坏人",
			"controller": "ai",
			"units": [_enemy1, _enemy2],
		},
	]


func _on_level_ready() -> void:
	# 运行时创建几个大范围测试技能
	var sk_big_diamond := _make_skill("大范围菱形", Enums.SkillType.ATTACK,
		OffsetPresets.diamond(1, 4), OffsetPresets.diamond(0, 2), 10, 0.5)
	var sk_cross3 := _make_skill("长十字", Enums.SkillType.ATTACK,
		OffsetPresets.diamond(1, 3), OffsetPresets.cross(3), 15, 0.8)
	var sk_line := _make_skill("四方直线", Enums.SkillType.ATTACK,
		OffsetPresets.lines_4dir(5), OffsetPresets.SINGLE, 10, 1.0)
	var sk_heal_area := _make_skill("范围治疗", Enums.SkillType.ASSIST,
		OffsetPresets.diamond(0, 3), OffsetPresets.cross(1), 20, 0.0)

	_assign_skills(_player, [sk_big_diamond, sk_cross3, sk_line, sk_heal_area, _sk_stone])
	_assign_skills(_playerB, [_sk_staff])
	_assign_skills(_enemy1, [_sk_lunge])
	_assign_skills(_enemy2, [_sk_lunge])

	# 标记主角
	if _player is Unit and _player.combat_stats:
		_player.combat_stats.is_hero = true


func _make_skill(sname: String, stype: Enums.SkillType,
	cast: Array[Vector2i], effect: Array[Vector2i],
	ap: int, ratio: float) -> SkillData:
	var sk := SkillData.new()
	sk.skill_id = sname
	sk.skill_name = sname
	sk.skill_type = stype
	sk.ap_cost = ap
	sk.damage_ratio = ratio
	sk.damage_element = Enums.Element.NONE
	sk.cast_offsets = cast
	sk.effect_offsets = effect
	return sk


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
