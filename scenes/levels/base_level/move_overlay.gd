extends Node2D
## Draws movement range overlay and path preview.
## Supports both legacy movement_points mode and AP-budget mode.

var cells: Array[Vector2i] = []
var tilemap: TileMapLayer
var movement_manager  # MovementManager
var half_tile := Vector2(16, 8)  # half of 32x16 isometric tile
var origin: Vector2i
var _parents: Dictionary = {}    # cell -> parent cell (for path reconstruction)
var _costs: Dictionary = {}      # cell -> total AP cost to reach this cell
var _current_path: Array[Vector2i] = []
var _ap_budget: int = -1         # -1 = legacy mode, >=0 = AP mode


## 旧版：按固定移动点数显示范围。
func show_range(
		p_tilemap: TileMapLayer,
		p_movement_manager,
		p_origin: Vector2i,
		max_points: int
) -> void:
	_ap_budget = -1
	_show_range_internal(p_tilemap, p_movement_manager, p_origin, max_points, 0)


## AP 制：按 AP 预算和每格消耗显示范围。
## move_cost_per_tile 为该单位基础每格消耗，地形额外消耗由 movement_manager 提供。
func show_range_ap(
		p_tilemap: TileMapLayer,
		p_movement_manager,
		p_origin: Vector2i,
		ap_budget: int,
		move_cost_per_tile: int,
		occupied_cells: Array[Vector2i] = []
) -> void:
	_ap_budget = ap_budget
	_show_range_internal(p_tilemap, p_movement_manager, p_origin, ap_budget, move_cost_per_tile, occupied_cells)


func _show_range_internal(
		p_tilemap: TileMapLayer,
		p_movement_manager,
		p_origin: Vector2i,
		budget: int,
		base_move_cost: int,
		occupied_cells: Array[Vector2i] = []
) -> void:
	tilemap = p_tilemap
	movement_manager = p_movement_manager
	origin = p_origin
	cells.clear()
	_parents.clear()
	_costs.clear()
	_current_path.clear()

	var occupied_set: Dictionary = {}
	for c in occupied_cells:
		occupied_set[c] = true

	# Dijkstra：best[cell] = 到达该格的最小消耗
	var best: Dictionary = { p_origin: 0 }
	_costs[p_origin] = 0
	var frontier: Array = [[0, p_origin]]
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]

	while frontier.size() > 0:
		# 取消耗最小的格
		var bi := 0
		for i in range(1, frontier.size()):
			if frontier[i][0] < frontier[bi][0]:
				bi = i
		var entry: Array = frontier[bi]
		frontier.remove_at(bi)
		var cost_so_far: int = entry[0]
		var current: Vector2i = entry[1]

		if cost_so_far > best.get(current, 999999):
			continue

		for dir in dirs:
			var nb: Vector2i = current + dir
			var tile_cost: int = movement_manager.get_movement_cost(nb)
			if tile_cost == -1:  # TileType.IMPASSABLE
				continue
			# AP 模式：消耗 = 单位每格基础消耗 + 地形额外消耗
			# 旧版模式：消耗 = 地形消耗（兼容）
			var step_cost: int
			if base_move_cost > 0:
				step_cost = base_move_cost + (tile_cost - 1)  # tile_cost includes base 1
			else:
				step_cost = tile_cost
			var new_cost: int = cost_so_far + step_cost
			if new_cost > budget:
				continue
			if best.has(nb) and best[nb] <= new_cost:
				continue
			# 被占据的格子可以路过但不能停留（仍加入寻路图）
			best[nb] = new_cost
			_parents[nb] = current
			_costs[nb] = new_cost
			frontier.append([new_cost, nb])

	for c: Vector2i in best:
		if c != origin and not occupied_set.has(c):
			cells.append(c)

	queue_redraw()


func clear_range() -> void:
	cells.clear()
	_parents.clear()
	_costs.clear()
	_current_path.clear()
	_ap_budget = -1
	queue_redraw()


func has_cell(cell: Vector2i) -> bool:
	return cell in cells


## 获取到达某格的 AP 消耗（AP 模式下有效）。
func get_cost_to_cell(cell: Vector2i) -> int:
	return _costs.get(cell, -1)


func update_path(target: Vector2i) -> void:
	var new_path: Array[Vector2i] = []
	if has_cell(target):
		var current := target
		while current != origin:
			new_path.append(current)
			current = _parents[current]
		new_path.append(origin)
		new_path.reverse()
	if new_path != _current_path:
		_current_path = new_path
		queue_redraw()


func get_path_to_cell(target: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not has_cell(target):
		return path
	var current := target
	while current != origin:
		path.append(current)
		current = _parents[current]
	path.append(origin)
	path.reverse()
	return path


func clear_path() -> void:
	if _current_path.size() > 0:
		_current_path.clear()
		queue_redraw()


func _draw() -> void:
	if tilemap == null:
		return

	# Draw range tiles
	var path_set: Dictionary = {}
	for cell in _current_path:
		path_set[cell] = true

	for cell in cells:
		var center := tilemap.map_to_local(cell)
		var points := _diamond_points(center)
		if path_set.has(cell):
			draw_colored_polygon(points, Color(1.0, 0.9, 0.0, 0.55))
		else:
			draw_colored_polygon(points, Color(1.0, 1.0, 0.0, 0.25))

	# Draw path line
	if _current_path.size() >= 2:
		var line_points := PackedVector2Array()
		for cell in _current_path:
			line_points.append(tilemap.map_to_local(cell))
		draw_polyline(line_points, Color(1.0, 1.0, 1.0, 0.8), 2.0)

	# AP 模式下在路径终点显示消耗/剩余
	if _ap_budget >= 0 and _current_path.size() >= 2:
		var target_cell := _current_path[_current_path.size() - 1]
		var cost := get_cost_to_cell(target_cell)
		if cost >= 0:
			var pos := tilemap.map_to_local(target_cell)
			var remaining := _ap_budget - cost
			var text := "-%d AP" % cost
			var text2 := "余 %d" % remaining
			# 背景框
			var bg_pos := pos + Vector2(-30, -32)
			draw_rect(Rect2(bg_pos, Vector2(60, 28)), Color(0, 0, 0, 0.7))
			# 消耗（红色，大字）
			draw_string(ThemeDB.fallback_font, pos + Vector2(-28, -20), text, HORIZONTAL_ALIGNMENT_CENTER, 56, 12, Color(1.0, 0.3, 0.3))
			# 剩余（白色）
			draw_string(ThemeDB.fallback_font, pos + Vector2(-28, -8), text2, HORIZONTAL_ALIGNMENT_CENTER, 56, 10, Color.WHITE)


func _diamond_points(center: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -half_tile.y),
		center + Vector2(half_tile.x, 0),
		center + Vector2(0, half_tile.y),
		center + Vector2(-half_tile.x, 0),
	])
