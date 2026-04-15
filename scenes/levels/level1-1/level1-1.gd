extends BaseLevel
## 第一关《踏勘洨河》

# ── 预加载技能 ──
var _sk_staff: SkillData = preload("res://data/skills/sw_staff_end_strike.tres")
var _sk_survey: SkillData = preload("res://data/skills/sw_field_measure_site.tres")
var _sk_mallet: SkillData = preload("res://data/skills/cg_mallet_strike.tres")
var _sk_guard: SkillData = preload("res://data/skills/cg_guard_the_works.tres")
var _sk_lunge: SkillData = preload("res://data/skills/dc_hidden_current_lunge.tres")
var _sk_pull: SkillData = preload("res://data/skills/wp_spiral_pull.tres")
var _sk_crush: SkillData = preload("res://data/skills/bmw_crumbling_bank_crush.tres")
var _sk_timber: SkillData = preload("res://data/skills/dlp_drifting_timber_crash.tres")

# ── 预加载敌方单位数据 ──
var _ud_dark_current: UnitData = preload("res://data/units/dark_current.tres")
var _ud_whirl_pool: UnitData = preload("res://data/units/whirl_pool.tres")
var _ud_mud_wraith: UnitData = preload("res://data/units/bank_mud_wraith.tres")
var _ud_drift_log: UnitData = preload("res://data/units/drift_log_pack.tres")

# ── 敌方队伍索引 ──
const ENEMY_TEAM := 2

# ── 敌方颜色 ──
const COLOR_DARK_CURRENT := Color(0.3, 0.4, 0.9)    # 蓝 - 暗涌（水）
const COLOR_WHIRL_POOL := Color(0.6, 0.3, 0.9)       # 紫蓝 - 水旋（水/控制）
const COLOR_MUD_WRAITH := Color(0.7, 0.5, 0.25)      # 棕 - 坍岸泥流（土）
const COLOR_DRIFT_LOG := Color(0.5, 0.65, 0.2)       # 黄绿 - 浮木群（木）

# ── 单位引用 ──
var _li_chun: Node2D
var _survey_a: Node2D
var _survey_b: Node2D
var _craftsman_a: Node2D
var _craftsman_b: Node2D

# ── 勘测点 ──
var _survey_points: Array[SurveyPointTile] = []
var _survey_completed_count: int = 0


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/LiChun"
	_survey_a = $"Entities/Units/SurveyWorkerA"
	_survey_b = $"Entities/Units/SurveyWorkerB"
	_craftsman_a = $"Entities/Units/CraftsmanA"
	_craftsman_b = $"Entities/Units/CraftsmanB"
	return [
		{
			"name": "玩家队伍",
			"faction": "好人",
			"controller": "player",
			"units": [_li_chun],
		},
		{
			"name": "辅助队伍",
			"faction": "好人",
			"controller": "player",
			"units": [_survey_a, _survey_b, _craftsman_a, _craftsman_b],
		},
		{
			"name": "敌方",
			"faction": "坏人",
			"controller": "ai",
			"units": [],
		},
	]


func get_wave_config() -> Dictionary:
	return {
		1: [
			{"unit_data": _ud_dark_current, "cell": Vector2i(8, -4), "team_index": ENEMY_TEAM,
			 "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT},
			{"unit_data": _ud_dark_current, "cell": Vector2i(10, -3), "team_index": ENEMY_TEAM,
			 "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT},
		],
		2: [
			{"unit_data": _ud_dark_current, "cell": Vector2i(6, -5), "team_index": ENEMY_TEAM,
			 "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT},
		],
		3: [
			{"unit_data": _ud_whirl_pool, "cell": Vector2i(9, -2), "team_index": ENEMY_TEAM,
			 "skills": [_sk_pull], "color": COLOR_WHIRL_POOL},
		],
		4: [
			{"unit_data": _ud_mud_wraith, "cell": Vector2i(5, -3), "team_index": ENEMY_TEAM,
			 "skills": [_sk_crush], "color": COLOR_MUD_WRAITH},
		],
		5: [
			{"unit_data": _ud_dark_current, "cell": Vector2i(11, -4), "team_index": ENEMY_TEAM,
			 "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT},
			{"unit_data": _ud_drift_log, "cell": Vector2i(7, -6), "team_index": ENEMY_TEAM,
			 "skills": [_sk_timber], "color": COLOR_DRIFT_LOG},
		],
		7: [
			{"unit_data": _ud_whirl_pool, "cell": Vector2i(8, -2), "team_index": ENEMY_TEAM,
			 "skills": [_sk_pull], "color": COLOR_WHIRL_POOL},
		],
	}


func get_objectives_text() -> Dictionary:
	var survey_status := " (%d/%d)" % [_survey_completed_count, _survey_points.size()] if _survey_points.size() > 0 else ""
	return {
		"victory": [
			"- 完成 3 个勘测点%s" % survey_status,
			"- 李春在候选桥位执行「相水定址」",
			"- 至少 1 名测量工进入撤离区并结束回合",
		],
		"defeat": [
			"- 李春倒下",
			"- 两名测量工全部倒下",
			"- 超过第 10 回合仍未完成撤离",
		],
	}


func check_defeat() -> String:
	# 李春倒下
	if not is_instance_valid(_li_chun):
		return "李春倒下"
	var lc := _li_chun as Unit
	if lc.combat_stats and not lc.combat_stats.is_alive():
		return "李春倒下"
	# 两名测量工全部倒下
	var a_dead := not is_instance_valid(_survey_a) or not (_survey_a as Unit).combat_stats.is_alive()
	var b_dead := not is_instance_valid(_survey_b) or not (_survey_b as Unit).combat_stats.is_alive()
	if a_dead and b_dead:
		return "两名测量工全部倒下"
	# 超过第 10 回合
	if round_number > 10:
		return "超过第 10 回合仍未完成撤离"
	return ""


func check_victory() -> bool:
	# 条件 1：完成所有勘测点
	var surveys_done := _survey_completed_count >= _survey_points.size() and _survey_points.size() > 0
	# 条件 2：李春在候选桥位执行「相水定址」（待实现）
	var bridge_done := false
	# 条件 3：至少 1 名测量工进入撤离区并结束回合（待实现）
	var evac_done := false
	return surveys_done and bridge_done and evac_done


func _on_level_ready() -> void:
	# ── 将友方单位移动到地图左上角 ──
	_place_friendlies_top_left()

	# ── 李春 ──
	set_unit_skills(_li_chun as Unit, Progress.get_battle_skill_resources(GameState.selected_level))
	setup_unit_stats(_li_chun as Unit, "李春", 130, 24, 100, 8, Enums.Element.NONE, 0, true)

	# ── 测量工 ──
	set_unit_skills(_survey_a as Unit, [_sk_staff, _sk_survey])
	setup_unit_stats(_survey_a as Unit, "测量工", 80, 12, 85, 10)

	set_unit_skills(_survey_b as Unit, [_sk_staff, _sk_survey])
	setup_unit_stats(_survey_b as Unit, "测量工", 80, 12, 85, 10)

	# ── 工匠 ──
	set_unit_skills(_craftsman_a as Unit, [_sk_mallet, _sk_guard])
	setup_unit_stats(_craftsman_a as Unit, "工匠", 110, 18, 90, 9)

	set_unit_skills(_craftsman_b as Unit, [_sk_mallet, _sk_guard])
	setup_unit_stats(_craftsman_b as Unit, "工匠", 110, 18, 90, 9)
	_apply_persistent_growth_effects()

	# ── 勘测点 ──
	# _setup_survey_points() # todo: 根据地图设置勘测点
	skill_executed.connect(_on_skill_executed)


func _place_friendlies_top_left() -> void:
	var used_rect: Rect2i = tilemap.get_used_rect()
	var top_left_tile := used_rect.position + Vector2i(2, 3)
	var anchor := _nearest_walkable(top_left_tile)
	var units: Array[Node2D] = [_li_chun, _survey_a, _survey_b, _craftsman_a, _craftsman_b]
	var offsets: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(2, 0),
		Vector2i(0, 2),
		Vector2i(1, 1),
		Vector2i(2, 2),
	]
	var occupied: Array[Vector2i] = []
	for i in range(units.size()):
		var cell := _nearest_walkable(anchor + offsets[i])
		while cell in occupied:
			cell = _nearest_walkable(cell + Vector2i(1, 0))
		occupied.append(cell)
		(units[i] as Unit).set_cell(cell, tilemap)


func _nearest_walkable(target: Vector2i) -> Vector2i:
	if movement_manager.get_movement_cost(target) != TileType.IMPASSABLE:
		return target
	for radius in range(1, 6):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var candidate := target + Vector2i(dx, dy)
				if movement_manager.get_movement_cost(candidate) != TileType.IMPASSABLE:
					return candidate
	return target


func _get_ai_context() -> Dictionary:
	return {
		"escort_units": [_survey_a, _survey_b],
	}


func get_post_level_growth_options() -> Array[Dictionary]:
	return [
		{"id": "growth_training_mobilize", "name": "操练与动员", "description": "全体我方最大生命值 +10，行动力上限 +5"},
		{"id": "growth_maps_measures", "name": "习图记尺", "description": "李春基础攻击力 +4，规尺击伤害倍率 +0.05"},
		{"id": "growth_river_master", "name": "请益河工", "description": "李春获得束桩缓波，可替换规尺击或木楔勘岸"},
		{"id": "growth_stone_reinforce", "name": "备石加固", "description": "工匠的捍作护行持续时间 +1 回合"},
	]


func _apply_persistent_growth_effects() -> void:
	if Progress.has_growth_option("growth_training_mobilize"):
		for unit in get_friendly_units():
			apply_unit_growth_bonus(unit, 10, 0, 5)
	if Progress.has_growth_option("growth_maps_measures"):
		var hero_unit := get_hero_unit()
		apply_unit_growth_bonus(hero_unit, 0, 4, 0)
		modify_unit_skill(hero_unit, "lc_rule_strike", {"damage_ratio": 1.05})
	if Progress.has_growth_option("growth_stone_reinforce"):
		for unit in get_friendly_units():
			if unit.combat_stats.unit_name == "工匠":
				modify_unit_skill(unit, "cg_guard_the_works", {"duration_turns": 3})
