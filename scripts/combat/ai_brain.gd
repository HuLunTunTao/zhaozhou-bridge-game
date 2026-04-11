class_name AIBrain
## 敌方 AI 决策器。纯静态函数，无状态。
##
## 用法：var action = _AIBrain.decide_action(unit, enemies, tilemap, mm, friendly, enemy, ctx)
## 返回 {"move_path": Array[Vector2i], "move_cost": int,
##        "skill": SkillData or null, "cast_cell": Vector2i}


const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

## 无效格子哨兵值。
const _INVALID_CELL := Vector2i(-99999, -99999)


## 为一个 AI 单位决定本回合行动。
static func decide_action(
		unit: Unit,
		enemies: Array,
		tilemap: TileMapLayer,
		movement_manager,
		occupied: Array[Vector2i],
		blocked: Array[Vector2i] = [],
		level_context: Dictionary = {}
) -> Dictionary:
	var empty_action: Dictionary = _make_empty_action()

	if unit.combat_stats == null or not unit.combat_stats.is_alive():
		return empty_action
	if unit.unit_data == null:
		return empty_action

	var ai_type: String = unit.combat_stats.ai_type

	# hazard_charge 完全不同的逻辑
	if ai_type == "hazard_charge":
		return _decide_hazard_charge(unit, enemies, tilemap, movement_manager, occupied, blocked, level_context)

	# ── 标准流程 ──
	var alive_enemies: Array = []
	for e in enemies:
		if e is Unit and e.combat_stats != null and e.combat_stats.is_alive():
			alive_enemies.append(e)
	if alive_enemies.is_empty():
		return empty_action

	var target: Unit = _pick_target(unit, alive_enemies, ai_type, level_context)
	if target == null:
		return empty_action

	var stats: CombatStats = unit.combat_stats
	var occupied_set: Dictionary = {}
	for c in occupied:
		occupied_set[c] = true
	var blocked_set: Dictionary = {}
	for c in blocked:
		blocked_set[c] = true

	# 1. 检查原地是否能攻击
	var standing_hit: Dictionary = _find_best_skill_hit(unit, unit.cell, target.cell)
	if not standing_hit.is_empty():
		return {
			"move_path": [] as Array[Vector2i],
			"move_cost": 0,
			"skill": standing_hit["skill"],
			"cast_cell": standing_hit["cast_cell"],
		}

	# 2. 尝试移动后攻击
	var effective_move_cost: int = stats.move_cost_per_tile + stats.get_move_ap_modifier()
	var best_action: Dictionary = empty_action
	var best_dist: int = 999999

	for skill: SkillData in unit.unit_data.skills:
		if skill.skill_type != Enums.SkillType.ATTACK:
			continue
		if not stats.can_use_skill(skill):
			continue
		var move_budget: int = stats.ap_current - skill.ap_cost
		if move_budget < 0:
			continue
		var reach: Dictionary = _compute_reachable(unit.cell, move_budget, effective_move_cost,
				movement_manager, occupied_set, blocked_set)
		var attack_cell: Vector2i = _find_attack_cell(unit.cell, target.cell, skill, reach)
		if attack_cell != _INVALID_CELL:
			var dist: int = _manhattan(attack_cell, target.cell)
			if dist < best_dist:
				best_dist = dist
				var path: Array[Vector2i] = _reconstruct_path(reach["parents"], unit.cell, attack_cell)
				var cost: int = reach["costs"].get(attack_cell, 0)
				var hit: Dictionary = _find_best_skill_hit(unit, attack_cell, target.cell)
				best_action = {
					"move_path": path,
					"move_cost": cost,
					"skill": hit["skill"] if not hit.is_empty() else skill,
					"cast_cell": hit["cast_cell"] if not hit.is_empty() else Vector2i.ZERO,
				}

	if best_action["skill"] != null:
		return best_action

	# 3. 无法攻击：尽可能接近目标
	var full_reach: Dictionary = _compute_reachable(unit.cell, stats.ap_current, effective_move_cost,
			movement_manager, occupied_set, blocked_set)
	var closest: Vector2i = _find_closest_to_target(target.cell, full_reach)
	if closest != _INVALID_CELL and closest != unit.cell:
		var path: Array[Vector2i] = _reconstruct_path(full_reach["parents"], unit.cell, closest)
		var cost: int = full_reach["costs"].get(closest, 0)
		return {
			"move_path": path,
			"move_cost": cost,
			"skill": null,
			"cast_cell": Vector2i.ZERO,
		}

	return empty_action


# ─────────────────────────────────────────────
# 目标选择
# ─────────────────────────────────────────────

static func _pick_target(unit: Unit, enemies: Array, ai_type: String,
		level_context: Dictionary) -> Unit:
	var best_target: Unit = null
	var best_score: float = -999999.0

	var escort_units: Array = level_context.get("escort_units", [])

	# 第一遍：找出最大距离用于归一化
	var max_dist: int = 1
	for enemy in enemies:
		var e: Unit = enemy as Unit
		if e == null or e.combat_stats == null or not e.combat_stats.is_alive():
			continue
		var dist: int = _manhattan(unit.cell, e.cell)
		if dist > max_dist:
			max_dist = dist

	# 第二遍：加权评分
	for enemy in enemies:
		var e: Unit = enemy as Unit
		if e == null or e.combat_stats == null or not e.combat_stats.is_alive():
			continue
		var dist: int = _manhattan(unit.cell, e.cell)
		# 距离分：越近越高（归一化到 0~1）
		var proximity_score: float = 1.0 - float(dist) / float(max_dist)
		# 护送目标分：是护送目标则为 1，否则为 0
		var is_escort: bool = e.combat_stats.is_escort_target or e in escort_units
		var escort_score: float = 1.0 if is_escort else 0.0
		# 加权：距离 0.8 + 护送目标 0.2
		var score: float = 0.8 * proximity_score + 0.2 * escort_score

		match ai_type:
			"flank_melee":
				if e.combat_stats.current_hp < e.combat_stats.max_hp * 0.5:
					score += 0.1
			_:
				pass

		if score > best_score:
			best_score = score
			best_target = e

	return best_target


# ─────────────────────────────────────────────
# 寻路（Dijkstra，从 move_overlay.gd 提取）
# ─────────────────────────────────────────────

## 返回 {"costs": {cell: int}, "parents": {cell: Vector2i}, "cells": Array[Vector2i]}
static func _compute_reachable(
		origin: Vector2i,
		ap_budget: int,
		base_move_cost: int,
		movement_manager,
		occupied_set: Dictionary,
		blocked_set: Dictionary = {}
) -> Dictionary:
	var costs: Dictionary = { origin: 0 }
	var parents: Dictionary = {}
	var frontier: Array = [[0, origin]]

	while frontier.size() > 0:
		var bi: int = 0
		for i in range(1, frontier.size()):
			if frontier[i][0] < frontier[bi][0]:
				bi = i
		var entry: Array = frontier[bi]
		frontier.remove_at(bi)
		var cost_so_far: int = entry[0]
		var current: Vector2i = entry[1]

		if cost_so_far > costs.get(current, 999999):
			continue

		for dir: Vector2i in DIRS:
			var nb: Vector2i = current + dir
			var tile_cost: int = movement_manager.get_movement_cost(nb)
			if tile_cost == -1:
				continue
			if blocked_set.has(nb):
				continue
			var step_cost: int
			if base_move_cost > 0:
				step_cost = base_move_cost + (tile_cost - 1)
			else:
				step_cost = tile_cost
			var new_cost: int = cost_so_far + step_cost
			if new_cost > ap_budget:
				continue
			if costs.has(nb) and costs[nb] <= new_cost:
				continue
			costs[nb] = new_cost
			parents[nb] = current
			frontier.append([new_cost, nb])

	# 可停留的格子（排除起点和被占据的格子）
	var reachable_cells: Array[Vector2i] = []
	for c: Vector2i in costs:
		if c != origin and not occupied_set.has(c):
			reachable_cells.append(c)

	return {"costs": costs, "parents": parents, "cells": reachable_cells}


## 路径重建：从 origin 到 target。
static func _reconstruct_path(parents: Dictionary, origin: Vector2i,
		target: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current: Vector2i = target
	while current != origin:
		path.append(current)
		if not parents.has(current):
			return [] as Array[Vector2i]
		current = parents[current]
	path.append(origin)
	path.reverse()
	return path


# ─────────────────────────────────────────────
# 技能范围
# ─────────────────────────────────────────────

## 检查从 from_cell 用 skill 能否打到 target_cell，返回 cast_cell 或 _INVALID_CELL。
static func _get_cast_cell_for_hit(from_cell: Vector2i, skill: SkillData,
		target_cell: Vector2i) -> Vector2i:
	for cast_offset: Vector2i in skill.cast_offsets:
		var cast_cell: Vector2i = from_cell + cast_offset
		for effect_offset: Vector2i in skill.effect_offsets:
			if cast_cell + effect_offset == target_cell:
				return cast_cell
	return _INVALID_CELL


## 在单位的技能中找到能从 from_cell 打到 target_cell 的最佳技能。
## 返回 {"skill": SkillData, "cast_cell": Vector2i} 或空字典。
static func _find_best_skill_hit(unit: Unit, from_cell: Vector2i,
		target_cell: Vector2i) -> Dictionary:
	if unit.unit_data == null or unit.combat_stats == null:
		return {}
	for skill: SkillData in unit.unit_data.skills:
		if skill.skill_type != Enums.SkillType.ATTACK:
			continue
		if not unit.combat_stats.can_use_skill(skill):
			continue
		var cast_cell: Vector2i = _get_cast_cell_for_hit(from_cell, skill, target_cell)
		if cast_cell != _INVALID_CELL:
			return {"skill": skill, "cast_cell": cast_cell}
	return {}


## 在可达范围内找到能用 skill 打到 target 的最佳格子。
static func _find_attack_cell(origin: Vector2i, target_cell: Vector2i,
		skill: SkillData, reachable: Dictionary) -> Vector2i:
	var best_cell: Vector2i = _INVALID_CELL
	var best_dist: int = 999999
	for cell: Vector2i in reachable["cells"]:
		var cast_cell: Vector2i = _get_cast_cell_for_hit(cell, skill, target_cell)
		if cast_cell != _INVALID_CELL:
			var dist: int = _manhattan(cell, target_cell)
			if dist < best_dist:
				best_dist = dist
				best_cell = cell
	# 也检查原地（如果在 costs 中）
	if reachable["costs"].has(origin):
		var cast_cell: Vector2i = _get_cast_cell_for_hit(origin, skill, target_cell)
		if cast_cell != _INVALID_CELL:
			var dist: int = _manhattan(origin, target_cell)
			if dist < best_dist:
				best_cell = origin
	return best_cell


## 在可达范围内找到距离 target 最近的格子。
static func _find_closest_to_target(target_cell: Vector2i,
		reachable: Dictionary) -> Vector2i:
	var best_cell: Vector2i = _INVALID_CELL
	var best_dist: int = 999999
	for cell: Vector2i in reachable["cells"]:
		var dist: int = _manhattan(cell, target_cell)
		if dist < best_dist:
			best_dist = dist
			best_cell = cell
	return best_cell


# ─────────────────────────────────────────────
# hazard_charge 特殊逻辑
# ─────────────────────────────────────────────

static func _decide_hazard_charge(
		unit: Unit,
		enemies: Array,
		_tilemap: TileMapLayer,
		movement_manager,
		occupied: Array[Vector2i],
		blocked: Array[Vector2i],
		level_context: Dictionary
) -> Dictionary:
	var stats: CombatStats = unit.combat_stats

	# 从 level_context 获取移动方向，默认向左（水流方向）
	var drift_dirs: Dictionary = level_context.get("drift_directions", {})
	var direction: Vector2i = drift_dirs.get(unit, Vector2i(-1, 0))

	# 冲锋在任何单位面前都会停下，合并友方和敌方占据格
	var occupied_set: Dictionary = {}
	for c in occupied:
		occupied_set[c] = true
	for c in blocked:
		occupied_set[c] = true

	# 构建敌人位置集合
	var enemy_cells: Dictionary = {}
	for e in enemies:
		if e is Unit and e.combat_stats != null and e.combat_stats.is_alive():
			enemy_cells[e.cell] = e

	var effective_cost: int = stats.move_cost_per_tile + stats.get_move_ap_modifier()
	var path: Array[Vector2i] = [unit.cell]
	var total_cost: int = 0
	var current: Vector2i = unit.cell
	var attack_skill: SkillData = null
	var attack_cast_cell: Vector2i = Vector2i.ZERO

	# 找到攻击技能
	for skill: SkillData in unit.unit_data.skills:
		if skill.skill_type == Enums.SkillType.ATTACK:
			attack_skill = skill
			break

	# 沿方向直线前进
	for _step in range(10):
		var next_cell: Vector2i = current + direction
		var tile_cost: int = movement_manager.get_movement_cost(next_cell)
		if tile_cost == -1:
			break
		var step_cost: int = effective_cost + (tile_cost - 1) if effective_cost > 0 else tile_cost
		if total_cost + step_cost > stats.ap_current:
			break

		# 检查前方是否有敌人
		if enemy_cells.has(next_cell) and attack_skill != null:
			var cast_cell: Vector2i = _get_cast_cell_for_hit(current, attack_skill, next_cell)
			if cast_cell != _INVALID_CELL:
				attack_cast_cell = cast_cell
				break

		if occupied_set.has(next_cell):
			break

		total_cost += step_cost
		current = next_cell
		path.append(current)

	var result_path: Array[Vector2i] = path if path.size() >= 2 else [] as Array[Vector2i]
	return {
		"move_path": result_path,
		"move_cost": total_cost,
		"skill": attack_skill if attack_cast_cell != Vector2i.ZERO else null,
		"cast_cell": attack_cast_cell,
	}


# ─────────────────────────────────────────────
# 工具函数
# ─────────────────────────────────────────────

static func _make_empty_action() -> Dictionary:
	return {
		"move_path": [] as Array[Vector2i],
		"move_cost": 0,
		"skill": null,
		"cast_cell": Vector2i.ZERO,
	}


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
