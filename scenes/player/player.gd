extends Node2D

signal move_finished

@export var movement_points: int = 10
@export var move_speed: float = 100.0  # pixels per second

var cell: Vector2i
var is_moving := false
## 由 BaseLevel 在场景就绪后赋值，用于触发地块进入/退出钩子。
var movement_manager = null


func set_cell(new_cell: Vector2i, tilemap: TileMapLayer) -> void:
	cell = new_cell
	position = tilemap.map_to_local(cell)


func move_along_path(path: Array[Vector2i], tilemap: TileMapLayer) -> void:
	if path.size() < 2 or is_moving:
		return
	is_moving = true
	# Walk each step sequentially
	for i in range(1, path.size()):
		if movement_manager:
			movement_manager.on_tile_exit(path[i - 1], self)
		var target_pos := tilemap.map_to_local(path[i])
		var dist := position.distance_to(target_pos)
		var duration := dist / move_speed
		var tween := create_tween()
		tween.tween_property(self, "position", target_pos, duration)
		await tween.finished
		if movement_manager:
			movement_manager.on_tile_enter(path[i], self)
	cell = path[path.size() - 1]
	is_moving = false
	move_finished.emit()
