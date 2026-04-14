extends BaseLevel
## 第二关《弧拱定式》

const PLAYER_TEAM := 0
const ENEMY_TEAM := 1
const ENEMY_FIELD_CAP := 5
const REQUIRED_DEFEATS := 8

const PARAMETER_NAMES := {
	"width": "河宽",
	"slope": "坡度",
	"weight": "石重",
}

var _li_chun: Unit
var _survey_worker: Unit
var _craftsmen: Array[Unit] = []
var _boss: Unit

var _parameter_cells: Dictionary = {}
var _drafting_cells: Array[Vector2i] = []
var _parameters_done := {
	"width": false,
	"slope": false,
	"weight": false,
}
var _finalized := false
var _driven_enemy_defeats := 0
var _summon_cycle := ["守法匠首", "高拱幻影", "守法匠首", "守法匠首", "重墩石像"]
var _summon_index := 0

var _hero_data: UnitData = preload("res://data/units/hero_li_chun.tres")
var _hero_visual: PackedScene = preload("res://scenes/unit/visual/human/li_chun/li_chun_visual.tscn")
var _survey_data: UnitData = preload("res://data/units/survey_worker.tres")
var _craftsman_data: UnitData = preload("res://data/units/craftsman_guard.tres")
var _mud_data: UnitData = preload("res://data/units/bank_mud_wraith.tres")
var _whirl_data: UnitData = preload("res://data/units/whirl_pool.tres")

var _staff: SkillData = preload("res://data/skills/sw_staff_end_strike.tres")
var _survey_skill: SkillData = preload("res://data/skills/sw_field_measure_site.tres")
var _mallet: SkillData = preload("res://data/skills/cg_mallet_strike.tres")
var _guard: SkillData = preload("res://data/skills/cg_guard_the_works.tres")
var _pull: SkillData = preload("res://data/skills/wp_spiral_pull.tres")
var _crush: SkillData = preload("res://data/skills/bmw_crumbling_bank_crush.tres")


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/Player" as Unit
	return [
		{
			"name": "营造队",
			"faction": "好人",
			"controller": "player",
			"units": [_li_chun],
		},
		{
			"name": "旧制势力",
			"faction": "坏人",
			"controller": "ai",
			"units": [],
		},
	]


func get_objectives_text() -> Dictionary:
	return {
		"victory": [
			"- 完成 3 个参数点",
			"- 李春在绘样台完成执墨定拱",
			"- 累计击破 8 名受驱役敌人",
		],
		"defeat": [
			"- 李春死亡",
			"- 超过第 12 回合",
		],
	}


func check_victory() -> bool:
	return _finalized and _driven_enemy_defeats >= REQUIRED_DEFEATS


func check_defeat() -> String:
	if _li_chun == null or _li_chun.combat_stats == null or not _li_chun.combat_stats.is_alive():
		return "李春阵亡"
	if round_number > 12:
		return "超过第 12 回合"
	return ""


func _on_level_ready() -> void:
	_setup_anchor_cells()
	_setup_li_chun()
	_spawn_allies()
	_spawn_initial_enemies()
	unit_died.connect(_on_stage_unit_died)
	unit_hp_changed.connect(_on_stage_hp_changed)
	team_turn_started.connect(_on_stage_team_turn_started)
	Notify.notify("完成 3 个参数点后，将李春送上绘样台", Notify.Position.TOP_CENTER, Notify.Style.INFO, 3.0)


func _on_unit_moved() -> void:
	if selected_unit == null or not (selected_unit is Unit):
		return
	var unit := selected_unit as Unit
	_try_collect_parameter(unit)
	_try_finalize_design(unit)


func _on_stage_team_turn_started(team_index: int) -> void:
	if team_index != ENEMY_TEAM or _boss == null or not _boss.combat_stats.is_alive():
		return
	var summon_count := 2 if _enemy_controls_drafting_platform() else 1
	for i in range(summon_count):
		if _count_driven_enemies() >= ENEMY_FIELD_CAP:
			break
		_spawn_next_summon()


func _on_stage_unit_died(unit: Unit) -> void:
	if unit == _boss:
		return
	if unit.team_index == ENEMY_TEAM:
		_driven_enemy_defeats += 1
		Notify.notify("受驱役敌人击破数 %d / %d" % [_driven_enemy_defeats, REQUIRED_DEFEATS], Notify.Position.TOP_RIGHT, Notify.Style.INFO, 2.0)
		_check_win_lose()


func _on_stage_hp_changed(unit: Unit, old_hp: int, new_hp: int) -> void:
	if unit != _boss or old_hp <= new_hp:
		return
	unit.combat_stats.current_hp = old_hp
	unit.refresh_overhead_bars()


func _setup_anchor_cells() -> void:
	var anchor := _li_chun.cell
	_parameter_cells = {
		"width": _nearest_walkable(anchor + Vector2i(-3, 1)),
		"slope": _nearest_walkable(anchor + Vector2i(2, -3)),
		"weight": _nearest_walkable(anchor + Vector2i(4, 1)),
	}
	_drafting_cells = [
		_nearest_walkable(anchor + Vector2i(2, -1)),
		_nearest_walkable(anchor + Vector2i(3, -1)),
		_nearest_walkable(anchor + Vector2i(2, -2)),
		_nearest_walkable(anchor + Vector2i(3, -2)),
	]


func _setup_li_chun() -> void:
	_li_chun.apply_runtime_setup(_hero_data, _hero_visual, Color(1, 0.85, 0, 1))
	set_unit_skills(_li_chun, Progress.get_equipped_skill_resources())
	setup_unit_stats(_li_chun, "李春", 130, 24, 100, 8, Enums.Element.NONE, 0, true)


func _spawn_allies() -> void:
	_survey_worker = _spawn_ally(_make_unit_data(_survey_data, "测量工", 80, 12, 85, 10), _nearest_walkable(_li_chun.cell + Vector2i(-2, 2)), [_staff, _survey_skill])
	_craftsmen = [
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 110, 18, 90, 9), _nearest_walkable(_li_chun.cell + Vector2i(-1, 1)), [_mallet, _guard]),
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 110, 18, 90, 9), _nearest_walkable(_li_chun.cell + Vector2i(1, 1)), [_mallet, _guard]),
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 110, 18, 90, 9), _nearest_walkable(_li_chun.cell + Vector2i(2, 0)), [_mallet, _guard]),
	]


func _spawn_initial_enemies() -> void:
	_boss = _spawn_enemy(_make_unit_data(_craftsman_data, "旧制监工", 260, 0, 1, 99), _drafting_cells[1] + Vector2i(0, -1), [])
	_spawn_enemy(_make_unit_data(_craftsman_data, "守法匠首", 120, 20, 90, 9), _drafting_cells[0] + Vector2i(-1, 0), [_mallet, _guard])
	_spawn_enemy(_make_unit_data(_craftsman_data, "守法匠首", 120, 20, 90, 9), _drafting_cells[1] + Vector2i(1, 0), [_mallet, _guard])
	_spawn_enemy(_make_unit_data(_whirl_data, "高拱幻影", 95, 18, 90, 8), _drafting_cells[3] + Vector2i(1, -1), [_pull])
	_spawn_enemy(_make_unit_data(_mud_data, "重墩石像", 165, 22, 85, 14), _nearest_walkable(_li_chun.cell + Vector2i(1, -1)), [_crush])


func _spawn_next_summon() -> void:
	var summon_name: String = _summon_cycle[_summon_index % _summon_cycle.size()]
	_summon_index += 1
	match summon_name:
		"守法匠首":
			_spawn_enemy(_make_unit_data(_craftsman_data, "守法匠首", 120, 20, 90, 9), _random_enemy_spawn_cell(), [_mallet, _guard])
		"高拱幻影":
			_spawn_enemy(_make_unit_data(_whirl_data, "高拱幻影", 95, 18, 90, 8), _random_enemy_spawn_cell(), [_pull])
		"重墩石像":
			_spawn_enemy(_make_unit_data(_mud_data, "重墩石像", 165, 22, 85, 14), _random_enemy_spawn_cell(), [_crush])


func _try_collect_parameter(unit: Unit) -> void:
	var key := ""
	for parameter_key in _parameter_cells.keys():
		if _parameters_done[parameter_key]:
			continue
		if unit.cell == _parameter_cells[parameter_key]:
			key = parameter_key
			break
	if key.is_empty():
		return
	var ap_cost := 40 if unit == _survey_worker else 45
	if unit != _survey_worker and unit != _li_chun:
		return
	if unit.combat_stats.ap_current < ap_cost:
		return
	unit.combat_stats.ap_current -= ap_cost
	_parameters_done[key] = true
	unit.refresh_overhead_bars()
	Notify.notify("%s 完成参数点：%s" % [unit.combat_stats.unit_name, PARAMETER_NAMES[key]], Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.5)


func _try_finalize_design(unit: Unit) -> void:
	if unit != _li_chun or _finalized or not _all_parameters_done():
		return
	if unit.cell not in _drafting_cells:
		return
	if unit.combat_stats.ap_current < 35:
		return
	unit.combat_stats.ap_current -= 35
	unit.refresh_overhead_bars()
	_finalized = true
	Notify.notify("执墨定拱完成，继续击退旧制驱役之敌", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 3.0)


func _all_parameters_done() -> bool:
	for done in _parameters_done.values():
		if not done:
			return false
	return true


func _enemy_controls_drafting_platform() -> bool:
	for enemy in teams[ENEMY_TEAM].units:
		if enemy is Unit and enemy.combat_stats and enemy.combat_stats.is_alive() and enemy.cell in _drafting_cells:
			return true
	return false


func _count_driven_enemies() -> int:
	var count := 0
	for enemy in teams[ENEMY_TEAM].units:
		if enemy != _boss and enemy is Unit and enemy.combat_stats and enemy.combat_stats.is_alive():
			count += 1
	return count


func _random_enemy_spawn_cell() -> Vector2i:
	var candidates := [
		_nearest_walkable(_drafting_cells[0] + Vector2i(-2, 0)),
		_nearest_walkable(_drafting_cells[1] + Vector2i(2, 0)),
		_nearest_walkable(_drafting_cells[2] + Vector2i(-1, -2)),
		_nearest_walkable(_drafting_cells[3] + Vector2i(1, -2)),
	]
	for cell in candidates:
		if not _cell_occupied(cell):
			return cell
	return candidates[0]


func _spawn_ally(data: UnitData, cell: Vector2i, skills: Array[SkillData]) -> Unit:
	var unit := spawn_unit(data, cell, PLAYER_TEAM)
	set_unit_skills(unit, skills)
	setup_unit_stats(unit, data.unit_name, data.max_hp, data.base_atk, data.ap_max, data.move_cost_per_tile)
	return unit


func _spawn_enemy(data: UnitData, cell: Vector2i, skills: Array[SkillData]) -> Unit:
	var unit := spawn_unit(data, _nearest_walkable(cell), ENEMY_TEAM)
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


func _cell_occupied(cell: Vector2i) -> bool:
	for unit in _get_all_units():
		if unit is Unit and unit.combat_stats and unit.combat_stats.is_alive() and unit.cell == cell:
			return true
	return false
