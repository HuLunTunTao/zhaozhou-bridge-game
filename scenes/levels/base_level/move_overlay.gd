extends Node2D
## Draws movement range overlay and path preview.

var cells: Array[Vector2i] = []
var tilemap: TileMapLayer
var movement_manager  # MovementManager
var half_tile := Vector2(16, 8)  # half of 32x16 isometric tile
var origin: Vector2i
var _parents: Dictionary = {}  # cell -> parent cell (for path reconstruction)
var _current_path: Array[Vector2i] = []


func show_range(
		p_tilemap: TileMapLayer,
		p_movement_manager,  # MovementManager
		p_origin: Vector2i,
		max_points: int
) -> void:
	tilemap = p_tilemap
	movement_manager = p_movement_manager
	origin = p_origin
	cells.clear()
	_parents.clear()
	_current_path.clear()

	# Dijkstra：best[cell] = 到达该格后的最大剩余移动点数
	var best: Dictionary = { p_origin: max_points }
	var frontier: Array = [[max_points, p_origin]]
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]

	while frontier.size() > 0:
		# 线性扫描取剩余点最多的格（地图规模小，性能足够）
		var bi := 0
		for i in range(1, frontier.size()):
			if frontier[i][0] > frontier[bi][0]:
				bi = i
		var entry: Array = frontier[bi]
		frontier.remove_at(bi)
		var remaining: int = entry[0]
		var current: Vector2i = entry[1]

		for dir in dirs:
			var nb: Vector2i = current + dir
			var cost: int = movement_manager.get_movement_cost(nb)
			if cost == -1:  # TileType.IMPASSABLE
				continue
			var new_rem: int = remaining - cost
			if new_rem < 0:
				continue
			if best.has(nb) and best[nb] >= new_rem:
				continue
			best[nb] = new_rem
			_parents[nb] = current
			frontier.append([new_rem, nb])

	for c: Vector2i in best:
		if c != origin:
			cells.append(c)

	queue_redraw()


func clear_range() -> void:
	cells.clear()
	_parents.clear()
	_current_path.clear()
	queue_redraw()


func has_cell(cell: Vector2i) -> bool:
	return cell in cells


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
			# Path tiles: brighter
			draw_colored_polygon(points, Color(1.0, 0.9, 0.0, 0.55))
		else:
			draw_colored_polygon(points, Color(1.0, 1.0, 0.0, 0.25))

	# Draw path line
	if _current_path.size() >= 2:
		var line_points := PackedVector2Array()
		for cell in _current_path:
			line_points.append(tilemap.map_to_local(cell))
		draw_polyline(line_points, Color(1.0, 1.0, 1.0, 0.8), 2.0)


func _diamond_points(center: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -half_tile.y),
		center + Vector2(half_tile.x, 0),
		center + Vector2(0, half_tile.y),
		center + Vector2(-half_tile.x, 0),
	])
