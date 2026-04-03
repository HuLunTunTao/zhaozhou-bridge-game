extends Node2D
## Draws yellow transparent diamond overlays on tiles to show movement range.

var cells: Array[Vector2i] = []
var tilemap: TileMapLayer
var half_tile := Vector2(16, 8)  # half of 32x16 isometric tile


func show_range(p_tilemap: TileMapLayer, origin: Vector2i, max_dist: int) -> void:
	tilemap = p_tilemap
	cells.clear()
	# BFS flood fill within Manhattan distance
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
				# Only allow movement on tiles that exist in the main tilemap
				if tilemap.get_cell_source_id(neighbor) == -1:
					continue
				visited[neighbor] = true
				dists[neighbor] = dist + 1
				queue.append(neighbor)
	queue_redraw()


func clear_range() -> void:
	cells.clear()
	queue_redraw()


func has_cell(cell: Vector2i) -> bool:
	return cell in cells


func _draw() -> void:
	for cell in cells:
		var center := tilemap.map_to_local(cell)
		var points := PackedVector2Array([
			center + Vector2(0, -half_tile.y),
			center + Vector2(half_tile.x, 0),
			center + Vector2(0, half_tile.y),
			center + Vector2(-half_tile.x, 0),
		])
		draw_colored_polygon(points, Color(1.0, 1.0, 0.0, 0.35))
