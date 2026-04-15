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
var _ally2: Node2D
var _enemy1: Node2D
var _enemy2: Node2D
var _enemy3: Node2D
var _enemy4: Node2D


func get_teams_config() -> Array:
	_player = $"Entities/Units/Player"
	_playerB = $"Entities/Units/PlayerB"
	_playerC = $"Entities/Units/PlayerC"
	_ally1 = $"Entities/Units/Ally1"
	_ally2 = $"Entities/Units/Ally2"
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
	set_unit_skills(_player as Unit, [_sk_rule_strike, _sk_wedge, _sk_stone, _sk_read_water, _sk_pile_bind])
	set_unit_skills(_playerB as Unit, [_sk_mallet, _sk_guard])
	set_unit_skills(_playerC as Unit, [_sk_staff, _sk_survey])
	set_unit_skills(_enemy1 as Unit, [_sk_lunge])
	set_unit_skills(_enemy2 as Unit, [_sk_pull])
	set_unit_skills(_enemy3 as Unit, [_sk_crush])
	set_unit_skills(_enemy4 as Unit, [_sk_lunge])

	# ── 覆盖属性值（数值.md 正式数据）──
	setup_unit_stats(_player as Unit, "李春", 130, 24, 100, 8, Enums.Element.NONE, 0, true)
	setup_unit_stats(_playerB as Unit, "工匠", 110, 18, 90, 9, Enums.Element.NONE, 0, false)
	setup_unit_stats(_playerC as Unit, "测量工", 80, 12, 85, 10, Enums.Element.NONE, 0, false)
	setup_unit_stats(_ally1 as Unit, "队友", 100, 10, 100, 10, Enums.Element.METAL, 0, false)
	setup_unit_stats(_ally2 as Unit, "队友2", 100, 10, 100, 10, Enums.Element.WOOD, 0, false)
	setup_unit_stats(_enemy1 as Unit, "暗涌", 68, 17, 100, 10, Enums.Element.WATER, 2, false)
	setup_unit_stats(_enemy2 as Unit, "火鸟", 75, 14, 100, 10, Enums.Element.FIRE, 2, false)
	setup_unit_stats(_enemy3 as Unit, "坍岸泥流", 92, 15, 100, 10, Enums.Element.EARTH, 2, false)
	setup_unit_stats(_enemy4 as Unit, "暗涌2", 68, 17, 100, 10, Enums.Element.WATER, 2, false)
