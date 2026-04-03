extends Node2D
## Draws movement range overlay and path preview.

var cells: Array[Vector2i] = []
var tilemap: TileMapLayer
var half_tile := Vector2(16, 8)  # half of 32x16 isometric tile
var origin: Vector2i
var _parents: Dictionary = {}  # cell -> parent cell (for path reconstruction)
var _current_path: Array[Vector2i] = []


func show_range(p_tilemap: TileMapLayer, p_origin: Vector2i, max_dist: int) -> void:
	tilemap = p_tilemap
	origin = p_origin
	cells.clear()
	_parents.clear()
	_current_path.clear()

	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [origin]
	var dists: Dictionary = {origin: 0}
	visited[origin] = true
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		var dist: int = dists[current]
		if dist > 0:
			cells.append(current)
		if dist < max_dist:
			for dir in directions:
				var neighbor: Vector2i = current + dir
				if visited.has(neighbor):
					continue
				if tilemap.get_cell_source_id(neighbor) == -1:
					continue
				visited[neighbor] = true
				dists[neighbor] = dist + 1
				_parents[neighbor] = current
				queue.append(neighbor)
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
