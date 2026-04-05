extends Node2D

signal move_finished

@export var move_range: int = 4
@export var move_speed: float = 100.0  # pixels per second

var cell: Vector2i
var is_moving := false


func set_cell(new_cell: Vector2i, tilemap: TileMapLayer) -> void:
	cell = new_cell
	position = tilemap.map_to_local(cell)


func move_along_path(path: Array[Vector2i], tilemap: TileMapLayer) -> void:
	if path.size() < 2 or is_moving:
		return
	is_moving = true
	modulate = Color.PURPLE
	# Walk each step sequentially
	for i in range(1, path.size()):
		var target_pos := tilemap.map_to_local(path[i])
		var dist := position.distance_to(target_pos)
		var duration := dist / move_speed
		var tween := create_tween()
		tween.tween_property(self, "position", target_pos, duration)
		await tween.finished
	modulate = Color.WHITE
	cell = path[path.size() - 1]
	is_moving = false
	move_finished.emit()
