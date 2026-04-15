extends BaseLevel
## 第三关《二十八券》

const PLAYER_TEAM := 0
const ENEMY_TEAM := 1

var _li_chun: Unit
var _craftsmen: Array[Unit] = []
var _stone_carriers: Array[Unit] = []
var _boss: Unit

var _left_arch_value := 2
var _right_arch_value := 2
var _bridge_stability := 6
var _arch_closed := false
var _pending_enemy_resolution := false
var _carrying_stone: Dictionary = {}
var _carrier_base_move_cost: Dictionary = {}
var _close_arch_ap_cost := 35

var _left_platform: Vector2i
var _right_platform: Vector2i
var _crown_point: Vector2i
var _stone_yard_cells: Array[Vector2i] = []
var _joint_cells: Array[Vector2i] = []

var _hero_data: UnitData = preload("res://data/units/hero_li_chun.tres")
var _hero_visual: PackedScene = preload("res://scenes/unit/visual/human/li_chun/li_chun_visual.tscn")
var _survey_data: UnitData = preload("res://data/units/survey_worker.tres")
var _craftsman_data: UnitData = preload("res://data/units/craftsman_guard.tres")
var _mud_data: UnitData = preload("res://data/units/bank_mud_wraith.tres")
var _dark_data: UnitData = preload("res://data/units/dark_current.tres")

var _staff: SkillData = preload("res://data/skills/sw_staff_end_strike.tres")
var _mallet: SkillData = preload("res://data/skills/cg_mallet_strike.tres")
var _guard: SkillData = preload("res://data/skills/cg_guard_the_works.tres")
var _divider: SkillData = preload("res://data/skills/lc_divider_mark_arc.tres")
var _inkline: SkillData = preload("res://data/skills/lc_inkline_balance_arch.tres")
var _crush: SkillData = preload("res://data/skills/bmw_crumbling_bank_crush.tres")
var _lunge: SkillData = preload("res://data/skills/dc_hidden_current_lunge.tres")


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/Player" as Unit
	return [
		{
			"name": "施工队",
			"faction": "好人",
			"controller": "player",
			"units": [_li_chun],
		},
		{
			"name": "偏载方",
			"faction": "坏人",
			"controller": "ai",
			"units": [],
		},
	]


func get_wave_config() -> Dictionary:
	return {
		3: [
			{"unit_data": _make_unit_data(_mud_data, "裂石兽", 145, 22, 90, 10, Enums.Element.EARTH, 1), "cell": _nearest_walkable(_left_platform + Vector2i(-2, 0)), "team_index": ENEMY_TEAM, "skills": [_crush]},
		],
		5: [
			{"unit_data": _make_unit_data(_dark_data, "脱缝潮", 95, 18, 95, 8, Enums.Element.WATER, 1), "cell": _joint_cells[0], "team_index": ENEMY_TEAM, "skills": [_lunge]},
		],
		7: [
			{"unit_data": _make_unit_data(_dark_data, "脱缝潮", 95, 18, 95, 8, Enums.Element.WATER, 1), "cell": _joint_cells[1], "team_index": ENEMY_TEAM, "skills": [_lunge]},
			{"unit_data": _make_unit_data(_mud_data, "裂石兽", 145, 22, 90, 10, Enums.Element.EARTH, 1), "cell": _nearest_walkable(_right_platform + Vector2i(2, 0)), "team_index": ENEMY_TEAM, "skills": [_crush]},
		],
	}


func get_objectives_text() -> Dictionary:
	return {
		"victory": [
			"- 左右券值均达到 8",
			"- 李春在拱冠点完成收缝合龙",
			"- 击退偏载傀",
		],
		"defeat": [
			"- 李春倒下",
			"- 桥体稳定值归零",
			"- 超过第 14 回合",
		],
	}


func check_victory() -> bool:
	return _arch_closed and _boss != null and _boss.combat_stats != null and not _boss.combat_stats.is_alive()


func check_defeat() -> String:
	if _li_chun == null or _li_chun.combat_stats == null or not _li_chun.combat_stats.is_alive():
		return "李春倒下"
	if _bridge_stability <= 0:
		return "桥体稳定值耗尽"
	if round_number > 14:
		return "超过第 14 回合"
	return ""


func _on_level_ready() -> void:
	_setup_anchor_cells()
	_setup_li_chun()
	_spawn_allies()
	_spawn_enemies()
	team_turn_started.connect(_on_stage_team_turn_started)
	unit_hp_changed.connect(_on_stage_hp_changed)
	Notify.notify("运石工取石入券，保持左右差值不超过 1", Notify.Position.TOP_CENTER, Notify.Style.INFO, 3.0)


func _on_unit_moved() -> void:
	if selected_unit == null or not (selected_unit is Unit):
		return
	var unit := selected_unit as Unit
	_try_pick_or_deliver_stone(unit)
	_try_close_arch(unit)


func _on_skill_executed(caster: Unit, skill: SkillData, cast_cell: Vector2i, _exec_result: SkillExecutor.ExecuteResult) -> void:
	if caster != _li_chun:
		return
	if skill.skill_id == "lc_inkline_balance_arch":
		if cast_cell == _left_platform:
			_adjust_arch_value(true, 1, "墨绳校券")
		elif cast_cell == _right_platform:
			_adjust_arch_value(false, 1, "墨绳校券")


func _on_stage_team_turn_started(team_index: int) -> void:
	if team_index == ENEMY_TEAM:
		_pending_enemy_resolution = true
		_shift_load()
	elif team_index == PLAYER_TEAM and _pending_enemy_resolution:
		_pending_enemy_resolution = false
		_resolve_enemy_pressure()


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
	_left_platform = _nearest_walkable(anchor + Vector2i(-3, 0))
	_right_platform = _nearest_walkable(anchor + Vector2i(4, 0))
	_crown_point = _nearest_walkable(anchor + Vector2i(1, -2))
	_stone_yard_cells = [
		_nearest_walkable(anchor + Vector2i(-1, 3)),
		_nearest_walkable(anchor + Vector2i(2, 3)),
	]
	_joint_cells = [
		_nearest_walkable(anchor + Vector2i(-1, -1)),
		_nearest_walkable(anchor + Vector2i(2, -1)),
	]


func _setup_li_chun() -> void:
	_li_chun.apply_runtime_setup(_hero_data, _hero_visual, Color(1, 0.85, 0, 1))
	set_unit_skills(_li_chun, Progress.get_battle_skill_resources(GameState.selected_level))
	setup_unit_stats(_li_chun, "李春", 130, 24, 100, 8, Enums.Element.NONE, 0, true)


func _spawn_allies() -> void:
	_craftsmen = [
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 118, 20, 92, 9), _nearest_walkable(_left_platform + Vector2i(-2, 0)), [_mallet, _guard]),
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 118, 20, 92, 9), _nearest_walkable(_crown_point + Vector2i(0, 2)), [_mallet, _guard]),
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 118, 20, 92, 9), _nearest_walkable(_right_platform + Vector2i(2, 0)), [_mallet, _guard]),
	]
	_stone_carriers = [
		_spawn_ally(_make_unit_data(_survey_data, "运石工", 88, 13, 90, 9), _nearest_walkable(_stone_yard_cells[0] + Vector2i(-1, 0)), [_staff]),
		_spawn_ally(_make_unit_data(_survey_data, "运石工", 88, 13, 90, 9), _nearest_walkable(_stone_yard_cells[1] + Vector2i(1, 0)), [_staff]),
	]
	for carrier in _stone_carriers:
		_carrier_base_move_cost[carrier.get_instance_id()] = carrier.combat_stats.move_cost_per_tile
	_apply_persistent_growth_effects()


func _spawn_enemies() -> void:
	_boss = _spawn_enemy(_make_unit_data(_mud_data, "偏载傀", 320, 22, 1, 99, Enums.Element.EARTH, 2), _nearest_walkable(_crown_point + Vector2i(1, -1)), [_divider], preload("res://scenes/unit/visual/monster/错券兵/错券兵_visual.tscn"))
	_spawn_enemy(_make_unit_data(_craftsman_data, "错券兵", 120, 20, 90, 9), _nearest_walkable(_left_platform + Vector2i(-1, 0)), [_mallet], preload("res://scenes/unit/visual/monster/错券兵/错券兵_visual.tscn"))
	_spawn_enemy(_make_unit_data(_craftsman_data, "错券兵", 120, 20, 90, 9), _nearest_walkable(_right_platform + Vector2i(1, 0)), [_mallet], preload("res://scenes/unit/visual/monster/错券兵/错券兵_visual.tscn"))
	_spawn_enemy(_make_unit_data(_mud_data, "裂石兽", 145, 22, 90, 10, Enums.Element.EARTH, 1), _nearest_walkable(_crown_point + Vector2i(0, 1)), [_crush])


func _try_pick_or_deliver_stone(unit: Unit) -> void:
	if unit not in _stone_carriers:
		return
	var key := unit.get_instance_id()
	if _is_adjacent_to_any(unit.cell, _stone_yard_cells) and not _carrying_stone.get(key, false):
		if unit.combat_stats.ap_current < 40:
			return
		unit.combat_stats.ap_current -= 40
		_carrying_stone[key] = true
		_set_carrier_loaded(unit, true)
		unit.refresh_overhead_bars()
		Notify.notify("%s 已取石" % unit.combat_stats.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.INFO, 1.5)
		return
	if not _carrying_stone.get(key, false):
		return
	if _is_adjacent_or_same(unit.cell, _left_platform):
		if unit.combat_stats.ap_current < 40:
			return
		unit.combat_stats.ap_current -= 40
		_adjust_arch_value(true, 1, "%s 运石入左券" % unit.combat_stats.unit_name)
		_carrying_stone[key] = false
		_set_carrier_loaded(unit, false)
		unit.refresh_overhead_bars()
	elif _is_adjacent_or_same(unit.cell, _right_platform):
		if unit.combat_stats.ap_current < 40:
			return
		unit.combat_stats.ap_current -= 40
		_adjust_arch_value(false, 1, "%s 运石入右券" % unit.combat_stats.unit_name)
		_carrying_stone[key] = false
		_set_carrier_loaded(unit, false)
		unit.refresh_overhead_bars()


func _try_close_arch(unit: Unit) -> void:
	if unit != _li_chun or _arch_closed:
		return
	if unit.cell != _crown_point:
		return
	if _left_arch_value < 8 or _right_arch_value < 8 or _arch_gap() > 1:
		return
	if unit.combat_stats.ap_current < _close_arch_ap_cost:
		return
	unit.combat_stats.ap_current -= _close_arch_ap_cost
	unit.refresh_overhead_bars()
	_arch_closed = true
	Notify.notify("收缝合龙完成，偏载傀的核心开始暴露", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 3.0)


func _shift_load() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	if _left_arch_value == _right_arch_value:
		_adjust_arch_value(randi() % 2 == 0, -1, "偏载傀扰动平衡")
	elif _left_arch_value > _right_arch_value:
		_adjust_arch_value(false, -1, "偏载傀压右券")
	else:
		_adjust_arch_value(true, -1, "偏载傀压左券")


func _resolve_enemy_pressure() -> void:
	if _arch_gap() >= 4:
		_bridge_stability -= 1
		Notify.notify("左右失衡过大，桥体稳定值 -1", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
	for enemy in teams[ENEMY_TEAM].units:
		if enemy is Unit and enemy.combat_stats and enemy.combat_stats.is_alive() and enemy.cell in _joint_cells and enemy.combat_stats.unit_name == "脱缝潮":
			_bridge_stability -= 1
			Notify.notify("脱缝潮侵蚀缝口，桥体稳定值 -1", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
	_check_win_lose()


func _boss_damage_cap() -> int:
	if not _arch_closed:
		return 1
	if _arch_gap() >= 4:
		return 1
	if _arch_gap() >= 2:
		return 8
	return 9999


func _arch_gap() -> int:
	return absi(_left_arch_value - _right_arch_value)


func _adjust_arch_value(is_left: bool, delta: int, reason: String) -> void:
	if is_left:
		_left_arch_value = clampi(_left_arch_value + delta, 0, 8)
	else:
		_right_arch_value = clampi(_right_arch_value + delta, 0, 8)
	Notify.notify("%s  左券:%d 右券:%d 稳定:%d" % [reason, _left_arch_value, _right_arch_value, _bridge_stability], Notify.Position.TOP_RIGHT, Notify.Style.INFO, 2.5)


func _set_carrier_loaded(unit: Unit, loaded: bool) -> void:
	var key := unit.get_instance_id()
	var base_cost := int(_carrier_base_move_cost.get(key, unit.combat_stats.move_cost_per_tile))
	unit.combat_stats.move_cost_per_tile = base_cost + 1 if loaded else base_cost


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


func _is_adjacent_or_same(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) <= 1


func _is_adjacent_to_any(cell: Vector2i, targets: Array[Vector2i]) -> bool:
	for target in targets:
		if _is_adjacent_or_same(cell, target):
			return true
	return false


func get_post_level_growth_options() -> Array[Dictionary]:
	return [
		{"id": "growth_balance_method", "name": "校券有法", "description": "墨绳校券冷却 -1，李春行动力上限 +5"},
		{"id": "growth_joint_finish", "name": "收缝习熟", "description": "收缝合龙消耗 -10，李春基础攻击力 +4"},
		{"id": "growth_link_arch", "name": "连楔并拱", "description": "李春获得连楔并拱，可替换规尺击或木楔勘岸"},
		{"id": "growth_team_hold", "name": "立券同力", "description": "全体工匠最大生命值 +10，全体运石工行动力上限 +5"},
	]


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
		_close_arch_ap_cost = 25
		apply_unit_growth_bonus(get_hero_unit(), 0, 4, 0)
	if Progress.has_growth_option("growth_team_hold"):
		for craftsman in _craftsmen:
			apply_unit_growth_bonus(craftsman, 10, 0, 0)
		for carrier in _stone_carriers:
			apply_unit_growth_bonus(carrier, 0, 0, 5)
