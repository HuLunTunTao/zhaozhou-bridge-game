class_name LevelQueryAPI
extends RefCounted

## 网格 / 占位 / 行动预算 / MCP 查询接口组件（Tactics Stack）。
## 从 BaseLevel 抽出：网格占用查询 / 占位格子收集 / 行动预算查询 / MCP 查询与操作接口 / 单位查询。
## UI 和 MCP 共用同一套接口。通过 setup(level) 持有宿主关卡，对 _level 保持鸭子调用，不反向依赖 BaseLevel。

## 单个队伍的运行时数据（真源在 TurnSystem，此处保留旧类型名供注解使用）。
const TeamData = TurnSystem.TeamData

## 输入状态机枚举（真源在 InputController，此处保留旧类型名供注解使用）。
const InputState = InputController.InputState

var _level: Node = null   # BaseLevel 宿主


func setup(level: Node) -> void:
	_level = level


# ─────────────────────────────────────────────
# 网格占用查询
# ─────────────────────────────────────────────

func is_cell_occupied(cell: Vector2i) -> bool:
	for team: TeamData in _level.teams:
		for unit: Node2D in team.units:
			if unit.cell == cell:
				return true
	return false


func is_any_unit_moving() -> bool:
	for team: TeamData in _level.teams:
		for unit: Node2D in team.units:
			if unit.is_moving:
				return true
	return false


func get_unit_at_cell(cell: Vector2i, team: TeamData) -> Node2D:
	for unit: Node2D in team.units:
		if unit.cell == cell:
			return unit
		if unit is Unit:
			var u := unit as Unit
			# 巨型单位可用 extra_target_cells 扩展受击区；点击这些格也应查看该单位。
			for offset in u.extra_target_cells:
				if u.cell + offset == cell:
					return unit
	return null


## 在点击位置附近查找任意队伍的单位（用于状态栏显示）。
func find_nearest_any_unit(local_mouse_pos: Vector2, max_dist: float = 24.0) -> Node2D:
	var clicked_cell: Vector2i = _level.tilemap.local_to_map(local_mouse_pos)
	# 先精确匹配
	for team: TeamData in _level.teams:
		var exact := get_unit_at_cell(clicked_cell, team)
		if exact != null:
			return exact
	# 回退到像素距离
	var best: Node2D = null
	var best_dist := max_dist
	for team: TeamData in _level.teams:
		for unit: Node2D in team.units:
			var unit_pos: Vector2 = _level.tilemap.map_to_local(unit.cell)
			var dist := local_mouse_pos.distance_to(unit_pos)
			if dist < best_dist:
				best_dist = dist
				best = unit
	return best


# ─────────────────────────────────────────────
# 占位格子收集
# ─────────────────────────────────────────────

## 获取除指定单位外所有被占据的格子。
func get_occupied_cells_except(exclude: Node2D) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for team: TeamData in _level.teams:
		for unit: Node2D in team.units:
			if unit != exclude:
				result.append(unit.cell)
	return result


## 获取敌方占据的格子（faction 不同），排除指定单位。用于寻路阻挡。
func get_enemy_cells_except(exclude: Node2D) -> Array[Vector2i]:
	var exclude_faction: String = exclude.faction if exclude is Unit else ""
	var result: Array[Vector2i] = []
	for team: TeamData in _level.teams:
		if team.faction == exclude_faction:
			continue
		for unit: Node2D in team.units:
			if unit != exclude and unit is Unit and unit.combat_stats and unit.combat_stats.is_alive():
				result.append(unit.cell)
	return result


## 获取友方占据的格子（faction 相同），排除指定单位。友方可穿越但不可停留。
func get_friendly_cells_except(exclude: Node2D) -> Array[Vector2i]:
	var exclude_faction: String = exclude.faction if exclude is Unit else ""
	var result: Array[Vector2i] = []
	for team: TeamData in _level.teams:
		if team.faction != exclude_faction:
			continue
		for unit: Node2D in team.units:
			if unit != exclude and unit is Unit and unit.combat_stats and unit.combat_stats.is_alive():
				result.append(unit.cell)
	return result


## 收集指定阵营的所有存活敌方单位格子。
func get_enemy_cell_set(faction: String) -> Dictionary:
	var result: Dictionary = {}
	for t: TeamData in _level.teams:
		if t.faction != faction:
			for eu: Node2D in t.units:
				if eu is Unit and eu.combat_stats and eu.combat_stats.is_alive():
					result[eu.cell] = true
	return result


# ─────────────────────────────────────────────
# 行动预算查询（真源在 AITurnRunner，本组件经 _level 鸭子调用）
# ─────────────────────────────────────────────

## 当前玩家队伍是否还有可行动单位（未 has_acted、未在移动中、还能移动或有技能能打到敌人）。
func player_team_has_remaining_actions() -> bool:
	return _level._get_ai_runner().player_team_has_remaining_actions()


func has_action_budget(stats: CombatStats) -> bool:
	return _level._get_ai_runner().has_action_budget(stats)


## 检查单位是否有攻击技能能够打到敌人（AP/次数够 + 范围内有敌人）。
func has_usable_attack(unit: Unit, enemy_cells: Dictionary) -> bool:
	return _level._get_ai_runner().has_usable_attack(unit, enemy_cells)


# ─────────────────────────────────────────────
# 统一接口（UI 和 MCP 共用）
# ─────────────────────────────────────────────

## 通过技能索引选择技能（0~4）。UI 按钮和 MCP 都调用此方法。
## 真源在 InputController，本组件经 _level 鸭子调用。
func select_skill_by_index(index: int) -> bool:
	return _level._get_input_controller().select_skill_by_index(index)


## 进入移动模式。UI 移动按钮和 MCP 都调用此方法。
## 真源在 InputController，本组件经 _level 鸭子调用。
func start_move() -> bool:
	return _level._get_input_controller().start_move()


## 查询当前游戏状态。返回字典，所有值为原始类型。
func query_state() -> Dictionary:
	var state_names := ["IDLE", "UNIT_SELECTED", "TARGETING_MOVE", "TARGETING_SKILL", "ANIMATING"]
	var team_name := ""
	if _level.current_team_index >= 0 and _level.current_team_index < _level.teams.size():
		team_name = _level.teams[_level.current_team_index].team_name
	var sel_name := ""
	if _level.selected_unit is Unit and _level.selected_unit.combat_stats:
		sel_name = _level.selected_unit.combat_stats.unit_name
	return {
		"input_state": state_names[_level._input_state] if _level._input_state < state_names.size() else "UNKNOWN",
		"team_name": team_name,
		"team_index": _level.current_team_index,
		"selected_unit": sel_name,
		"waiting_for_input": _level._waiting_for_player_input,
	}


## 查询所有单位信息。返回字典数组，所有值为原始类型。
func query_units() -> Array:
	var result: Array = []
	for ti in range(_level.teams.size()):
		var team: TeamData = _level.teams[ti]
		for ui in range(team.units.size()):
			var unit: Node2D = team.units[ui]
			var info: Dictionary = {
				"name": unit.name,
				"cell": [unit.cell.x, unit.cell.y],
				"team_index": ti,
				"team_name": team.team_name,
				"faction": team.faction,
				"has_acted": unit.has_acted,
			}
			if unit is Unit and unit.combat_stats:
				var s: CombatStats = unit.combat_stats
				info["hp"] = s.current_hp
				info["max_hp"] = s.max_hp
				info["ap"] = s.ap_current
				info["ap_max"] = s.ap_max
				info["base_atk"] = s.base_atk
				info["element"] = s.current_element
				info["element_amount"] = s.current_element_amount
				info["is_hero"] = s.is_hero
				info["statuses"] = []
				for st in s.statuses:
					info["statuses"].append({"id": st.status_id, "turns": st.remaining_turns})
				# 技能列表
				var skills_info: Array = []
				if unit.unit_data:
					for si in range(unit.unit_data.skills.size()):
						var sk: SkillData = unit.unit_data.skills[si]
						skills_info.append({
							"index": si,
							"id": sk.skill_id,
							"name": sk.skill_name,
							"ap_cost": sk.ap_cost,
							"can_use": s.can_use_skill(sk),
						})
				info["skills"] = skills_info
			result.append(info)
	return result


## 查询当前可移动范围（TARGETING_MOVE 时有效）。
func query_move_range() -> Array:
	if _level._input_state != InputState.TARGETING_MOVE:
		return []
	var result: Array = []
	for c in _level.move_overlay.cells:
		result.append([c.x, c.y])
	return result


## 查询技能释放/影响范围（TARGETING_SKILL 时有效）。
func query_skill_range() -> Dictionary:
	if _level._input_state != InputState.TARGETING_SKILL or _level._skill_targeting == null:
		return {"cast_cells": [], "effect_cells": []}
	var cast: Array = []
	for c in _level._skill_targeting._cast_cells:
		cast.append([c.x, c.y])
	var effect: Array = []
	for c in _level._skill_targeting._effect_cells:
		effect.append([c.x, c.y])
	return {"cast_cells": cast, "effect_cells": effect}


# ─────────────────────────────────────────────
# 单位查询
# ─────────────────────────────────────────────

func get_friendly_units() -> Array[Unit]:
	var result: Array[Unit] = []
	for team in _level.teams:
		if team.controller != "player":
			continue
		for unit in team.units:
			if unit is Unit and unit.combat_stats != null and unit.combat_stats.is_alive():
				result.append(unit)
	return result


func get_hero_unit() -> Unit:
	return _level.hero as Unit if _level.hero is Unit else null
