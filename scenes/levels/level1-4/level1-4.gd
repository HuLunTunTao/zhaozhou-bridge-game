extends BaseLevel
## 第四关《敞肩试汛》

const PLAYER_TEAM := 0
const ENEMY_TEAM := 1

var _li_chun: Unit
var _craftsmen: Array[Unit] = []
var _stone_carriers: Array[Unit] = []
var _boss: Unit

var _overall_stability := 12
var _left_pier_stability := 6
var _right_pier_stability := 6
var _pending_enemy_resolution := false
var _boss_base_atk := 24

var _left_pier: Vector2i
var _right_pier: Vector2i
var _watch_point: Vector2i
var _side_arch_cells: Dictionary = {}
var _side_arch_states := {
	"left_front": "closed",
	"left_back": "closed",
	"right_front": "closed",
	"right_back": "closed",
}

var _hero_data: UnitData = preload("res://data/units/hero_li_chun.tres")
var _hero_visual: PackedScene = preload("res://scenes/unit/visual/human/li_chun/li_chun_visual.tscn")
var _survey_data: UnitData = preload("res://data/units/survey_worker.tres")
var _craftsman_data: UnitData = preload("res://data/units/craftsman_guard.tres")

# 第四关敌方单位（独立 .tres）
var _flood_spear_data: UnitData = preload("res://data/units/flood_spear.tres")
var _siltmare_data: UnitData = preload("res://data/units/siltmare.tres")
var _pier_gnawer_data: UnitData = preload("res://data/units/pier_gnawer.tres")
var _driftwood_data: UnitData = preload("res://data/units/flood_driftwood_pack.tres")
var _wrathful_flood_data: UnitData = preload("res://data/units/wrathful_flood.tres")

# 友军技能（复用）
var _staff: SkillData = preload("res://data/skills/sw_staff_end_strike.tres")
var _mallet: SkillData = preload("res://data/skills/cg_mallet_strike.tres")
var _guard: SkillData = preload("res://data/skills/cg_guard_the_works.tres")

# 漂木群技能（复用现有 dlp_drifting_timber_crash，设计稿的 fdp_driftwood_surge 属后续步骤）
var _timber: SkillData = preload("res://data/skills/dlp_drifting_timber_crash.tres")

# 第四关敌方技能（独立 .tres）
var _torrent_ram: SkillData = preload("res://data/skills/fs_torrent_ram.tres")
var _mire_steps: SkillData = preload("res://data/skills/sm_mire_steps.tres")
var _gnaw_pier: SkillData = preload("res://data/skills/pg_gnaw_pier.tres")
var _overturn_bridge: SkillData = preload("res://data/skills/wf_overturn_bridge.tres")


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/Player" as Unit
	return [
		{
			"name": "守桥队",
			"faction": "好人",
			"controller": "player",
			"units": [_li_chun],
		},
		{
			"name": "洪灾",
			"faction": "坏人",
			"controller": "ai",
			"units": [],
		},
	]


func get_wave_config() -> Dictionary:
	return {
		3: [
			{"unit_data": _make_unit_data(_pier_gnawer_data, "桥台噬者", 116, 22, 90, 10, Enums.Element.EARTH, 2), "cell": _nearest_walkable(_left_pier + Vector2i(-2, 0)), "team_index": ENEMY_TEAM, "skills": [_gnaw_pier]},
		],
		5: [
			{"unit_data": _make_unit_data(_siltmare_data, "泥沙魇", 84, 18, 90, 10, Enums.Element.EARTH, 2), "cell": _watch_point + Vector2i(0, -2), "team_index": ENEMY_TEAM, "skills": [_mire_steps]},
		],
		6: [
			{"unit_data": _make_unit_data(_driftwood_data, "漂木群·洪水版", 58, 20, 100, 10, Enums.Element.WOOD, 2), "cell": _side_arch_cells["left_front"] + Vector2i(0, -2), "team_index": ENEMY_TEAM, "skills": [_timber]},
		],
		7: [
			{"unit_data": _make_unit_data(_pier_gnawer_data, "桥台噬者", 116, 22, 90, 10, Enums.Element.EARTH, 2), "cell": _nearest_walkable(_right_pier + Vector2i(2, 0)), "team_index": ENEMY_TEAM, "skills": [_gnaw_pier]},
		],
		9: [
			{"unit_data": _make_unit_data(_driftwood_data, "漂木群·洪水版", 58, 20, 100, 10, Enums.Element.WOOD, 2), "cell": _side_arch_cells["right_front"] + Vector2i(0, -2), "team_index": ENEMY_TEAM, "skills": [_timber]},
		],
	}


func get_objectives_text() -> Dictionary:
	return {
		"victory": [
			"- 开启更多小拱以减轻洪压",
			"- 保护左右桥台与整桥稳定值",
			"- 击退怒水",
		],
		"defeat": [
			"- 李春倒下",
			"- 左右桥台任一崩溃",
			"- 整桥稳定值归零",
			"- 超过第 15 回合",
		],
	}


func check_victory() -> bool:
	return _boss != null and _boss.combat_stats != null and not _boss.combat_stats.is_alive()


func check_defeat() -> String:
	if _li_chun == null or _li_chun.combat_stats == null or not _li_chun.combat_stats.is_alive():
		return "李春倒下"
	if _overall_stability <= 0:
		return "整桥稳定值耗尽"
	if _left_pier_stability <= 0:
		return "左桥台崩毁"
	if _right_pier_stability <= 0:
		return "右桥台崩毁"
	if round_number > 15:
		return "超过第 15 回合"
	return ""


func _on_level_ready() -> void:
	_setup_anchor_cells()
	_setup_li_chun()
	_spawn_allies()
	_spawn_enemies()
	team_turn_started.connect(_on_stage_team_turn_started)
	unit_hp_changed.connect(_on_stage_hp_changed)
	Notify.notify("李春与运石工可开启小拱；运石工可抢修桥台", Notify.Position.TOP_CENTER, Notify.Style.INFO, 3.0)


func _on_unit_moved() -> void:
	if selected_unit == null or not (selected_unit is Unit):
		return
	var unit := selected_unit as Unit
	_try_open_side_arch(unit)
	_try_repair_pier(unit)


func _on_skill_executed(caster: Unit, skill: SkillData, cast_cell: Vector2i, _exec_result: SkillExecutor.ExecuteResult) -> void:
	if caster != _li_chun:
		return
	if skill.skill_id != "lc_guide_flood_open_arch":
		return
	for arch_key in _side_arch_cells.keys():
		if cast_cell == _side_arch_cells[arch_key]:
			_open_arch(arch_key, "导汛开肩")


func _on_stage_team_turn_started(team_index: int) -> void:
	if team_index == ENEMY_TEAM:
		_pending_enemy_resolution = true
		_sync_boss_pressure()
	elif team_index == PLAYER_TEAM and _pending_enemy_resolution:
		_pending_enemy_resolution = false
		_resolve_enemy_pressure()
		_sync_boss_pressure()


func _on_stage_hp_changed(unit: Unit, old_hp: int, new_hp: int) -> void:
	if unit != _boss or new_hp >= old_hp:
		return
	var damage := old_hp - new_hp
	var cap := _boss_damage_cap()
	if damage > cap:
		unit.combat_stats.current_hp = old_hp - cap
		unit.refresh_overhead_bars()


func _setup_anchor_cells() -> void:
	var anchor := _li_chun.cell
	_watch_point = _nearest_walkable(anchor + Vector2i(0, -1))
	_left_pier = _nearest_walkable(anchor + Vector2i(-4, 0))
	_right_pier = _nearest_walkable(anchor + Vector2i(4, 0))
	_side_arch_cells = {
		"left_front": _nearest_walkable(anchor + Vector2i(-3, -1)),
		"left_back": _nearest_walkable(anchor + Vector2i(-2, 2)),
		"right_front": _nearest_walkable(anchor + Vector2i(3, -1)),
		"right_back": _nearest_walkable(anchor + Vector2i(2, 2)),
	}


func _setup_li_chun() -> void:
	_li_chun.apply_runtime_setup(_hero_data, _hero_visual, Color(1, 0.85, 0, 1))
	set_unit_skills(_li_chun, Progress.get_battle_skill_resources(GameState.selected_level))
	setup_unit_stats(_li_chun, "李春", 138, 26, 105, 8, Enums.Element.NONE, 0, true)


func _spawn_allies() -> void:
	_craftsmen = [
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 120, 20, 95, 9), _nearest_walkable(_left_pier + Vector2i(0, -1)), [_mallet, _guard]),
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 120, 20, 95, 9), _nearest_walkable(_right_pier + Vector2i(0, -1)), [_mallet, _guard]),
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 120, 20, 95, 9), _nearest_walkable(_watch_point + Vector2i(0, 1)), [_mallet, _guard]),
	]
	_stone_carriers = [
		_spawn_ally(_make_unit_data(_survey_data, "运石工", 92, 14, 95, 9), _nearest_walkable(_side_arch_cells["left_back"] + Vector2i(-1, 1)), [_staff]),
		_spawn_ally(_make_unit_data(_survey_data, "运石工", 92, 14, 95, 9), _nearest_walkable(_side_arch_cells["right_back"] + Vector2i(1, 1)), [_staff]),
	]
	_apply_persistent_growth_effects()


func _apply_persistent_growth_effects() -> void:
	if Progress.has_growth_option("growth_training_mobilize"):
		for unit in get_friendly_units():
			apply_unit_growth_bonus(unit, 10, 0, 5)
	if Progress.has_growth_option("growth_maps_measures"):
		apply_unit_growth_bonus(get_hero_unit(), 0, 4, 0)
		modify_unit_skill(get_hero_unit(), "lc_rule_strike", {"damage_ratio": 1.05})
	if Progress.has_growth_option("growth_stone_reinforce"):
		for craftsman in _craftsmen:
			modify_unit_skill(craftsman, "cg_guard_the_works", {"duration_turns": 3})
	if Progress.has_growth_option("growth_drawing_discipline"):
		apply_unit_growth_bonus(get_hero_unit(), 0, 4, 0)
		modify_unit_skill(get_hero_unit(), "lc_divider_mark_arc", {"damage_ratio": 0.95})
	if Progress.has_growth_option("growth_center_hold"):
		for craftsman in _craftsmen:
			apply_unit_growth_bonus(craftsman, 10, 2, 0)
	if Progress.has_growth_option("growth_balance_method"):
		apply_unit_growth_bonus(get_hero_unit(), 0, 0, 5)
		modify_unit_skill(get_hero_unit(), "lc_inkline_balance_arch", {"cooldown_turns": 1})
	if Progress.has_growth_option("growth_joint_finish"):
		apply_unit_growth_bonus(get_hero_unit(), 0, 4, 0)
	if Progress.has_growth_option("growth_team_hold"):
		for craftsman in _craftsmen:
			apply_unit_growth_bonus(craftsman, 10, 0, 0)
		for carrier in _stone_carriers:
			apply_unit_growth_bonus(carrier, 0, 0, 5)


func _spawn_enemies() -> void:
	_boss = _spawn_enemy(_make_unit_data(_wrathful_flood_data, "怒水", 360, 24, 1, 99, Enums.Element.WATER, 2), _watch_point + Vector2i(0, -3), [_overturn_bridge], preload("res://scenes/unit/visual/monster/洪峰/洪峰_visual.tscn"))
	_spawn_enemy(_make_unit_data(_flood_spear_data, "洪锋", 98, 24, 90, 10, Enums.Element.WATER, 2), _watch_point + Vector2i(0, -1), [_torrent_ram], preload("res://scenes/unit/visual/monster/洪峰/洪峰_visual.tscn"))
	_spawn_enemy(_make_unit_data(_flood_spear_data, "洪锋", 98, 24, 90, 10, Enums.Element.WATER, 2), _right_pier + Vector2i(1, -1), [_torrent_ram], preload("res://scenes/unit/visual/monster/洪峰/洪峰_visual.tscn"))
	_spawn_enemy(_make_unit_data(_siltmare_data, "泥沙魇", 84, 18, 90, 10, Enums.Element.EARTH, 2), _side_arch_cells["left_front"] + Vector2i(-1, 0), [_mire_steps], preload("res://scenes/unit/visual/monster/泥沙魇/泥沙魇_visual.tscn"))


func _try_open_side_arch(unit: Unit) -> void:
	if unit != _li_chun and unit not in _stone_carriers:
		return
	for arch_key in _side_arch_cells.keys():
		if not _is_adjacent_or_same(unit.cell, _side_arch_cells[arch_key]):
			continue
		var cost := 30 if unit == _li_chun else 35
		if unit.combat_stats.ap_current < cost:
			return
		unit.combat_stats.ap_current -= cost
		unit.refresh_overhead_bars()
		_open_arch(arch_key, "%s 启肩泄洪" % unit.combat_stats.unit_name)
		return


func _try_repair_pier(unit: Unit) -> void:
	if unit not in _stone_carriers or unit.combat_stats.ap_current < 40:
		return
	if _is_adjacent_or_same(unit.cell, _left_pier) and _left_pier_stability < 6:
		unit.combat_stats.ap_current -= 40
		unit.refresh_overhead_bars()
		_left_pier_stability = min(_left_pier_stability + 1, 6)
		Notify.notify("左桥台抢修完成，稳定值 %d" % _left_pier_stability, Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 2.0)
	elif _is_adjacent_or_same(unit.cell, _right_pier) and _right_pier_stability < 6:
		unit.combat_stats.ap_current -= 40
		unit.refresh_overhead_bars()
		_right_pier_stability = min(_right_pier_stability + 1, 6)
		Notify.notify("右桥台抢修完成，稳定值 %d" % _right_pier_stability, Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 2.0)


func _open_arch(arch_key: String, reason: String) -> void:
	_side_arch_states[arch_key] = "open"
	Notify.notify("%s  已开启小拱 %d / 4" % [reason, _open_arch_count()], Notify.Position.TOP_RIGHT, Notify.Style.INFO, 2.0)


func _sync_boss_pressure() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	_boss.combat_stats.base_atk = roundi(_boss_base_atk * 0.85) if _open_arch_count() >= 4 else _boss_base_atk


func _resolve_enemy_pressure() -> void:
	for arch_key in _side_arch_cells.keys():
		if _side_arch_states[arch_key] == "blocked":
			_side_arch_states[arch_key] = "closed"
	for enemy in teams[ENEMY_TEAM].units:
		if not (enemy is Unit) or enemy.combat_stats == null or not enemy.combat_stats.is_alive():
			continue
		if enemy.combat_stats.unit_name == "漂木群·洪水版":
			for arch_key in _side_arch_cells.keys():
				if enemy.cell == _side_arch_cells[arch_key]:
					_side_arch_states[arch_key] = "blocked"

	var open_count := _open_arch_count()
	if open_count == 0:
		_overall_stability -= 2
		if _left_pier_stability <= _right_pier_stability:
			_left_pier_stability -= 1
		else:
			_right_pier_stability -= 1
	elif open_count == 1:
		_overall_stability -= 2
	elif open_count == 2:
		_overall_stability -= 1

	for enemy in teams[ENEMY_TEAM].units:
		if not (enemy is Unit) or enemy.combat_stats == null or not enemy.combat_stats.is_alive():
			continue
		if enemy.combat_stats.unit_name == "桥台噬者":
			if _is_adjacent_or_same(enemy.cell, _left_pier):
				_left_pier_stability -= 1
			if _is_adjacent_or_same(enemy.cell, _right_pier):
				_right_pier_stability -= 1
		if enemy.combat_stats.unit_name == "泥沙魇" and _is_adjacent_or_same(enemy.cell, _watch_point):
			_overall_stability -= 1

	Notify.notify("整桥:%d 左桥台:%d 右桥台:%d 小拱:%d/4" % [_overall_stability, _left_pier_stability, _right_pier_stability, open_count], Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 2.5)
	_check_win_lose()


func _get_ai_context() -> Dictionary:
	return {
		"drift_directions": {
			"漂木群·洪水版": Vector2i(0, 1),
		}
	}


func _is_adjacent_or_same(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) <= 1


func _open_arch_count() -> int:
	var count := 0
	for arch_key in _side_arch_states.keys():
		if _side_arch_states[arch_key] == "open":
			count += 1
	return count


func _boss_damage_cap() -> int:
	match _open_arch_count():
		0:
			return 1
		1:
			return 6
		2:
			return 12
		_:
			return 9999


func _spawn_ally(data: UnitData, cell: Vector2i, skills: Array[SkillData]) -> Unit:
	var unit := spawn_unit(data, cell, PLAYER_TEAM)
	set_unit_skills(unit, skills)
	setup_unit_stats(unit, data.unit_name, data.max_hp, data.base_atk, data.ap_max, data.move_cost_per_tile)
	return unit


func _spawn_enemy(data: UnitData, cell: Vector2i, skills: Array[SkillData], visual: PackedScene = null) -> Unit:
	var unit := spawn_unit(data, _nearest_walkable(cell), ENEMY_TEAM, visual)
	set_unit_skills(unit, skills)
	setup_unit_stats(unit, data.unit_name, data.max_hp, data.base_atk, data.ap_max, data.move_cost_per_tile, data.innate_element, data.innate_element_amount)
	return unit


func _make_unit_data(base: UnitData, unit_name: String, max_hp: int, base_atk: int, ap_max: int, move_cost: int, element: Enums.Element = Enums.Element.NONE, element_amount: int = 0) -> UnitData:
	var data := base.duplicate(true) as UnitData
	data.resource_local_to_scene = true
	data.unit_name = unit_name
	data.max_hp = max_hp
	data.base_atk = base_atk
	data.ap_max = ap_max
	data.move_cost_per_tile = move_cost
	data.innate_element = element
	data.innate_element_amount = element_amount
	return data


func _nearest_walkable(target: Vector2i) -> Vector2i:
	if movement_manager.get_movement_cost(target) != TileType.IMPASSABLE:
		return target
	for radius in range(1, 4):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var candidate := target + Vector2i(dx, dy)
				if movement_manager.get_movement_cost(candidate) != TileType.IMPASSABLE:
					return candidate
	return target
