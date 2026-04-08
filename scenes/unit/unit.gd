@tool
class_name Unit
extends Node2D

signal move_finished

@export var movement_points: int = 10
@export var move_speed: float = 100.0  # pixels per second
## 单位颜色，修改后在编辑器中实时预览。
@export var unit_color: Color = Color(1, 0.85, 0, 1):
	set(value):
		unit_color = value
		_apply_color()

var cell: Vector2i
var is_moving := false
## 由 BaseLevel 在场景就绪后赋值，用于触发地块进入/退出钩子。
var movement_manager = null

## 所属队伍编号（由 BaseLevel 赋值）。
var team_index: int = -1
## 所属阵营名称（由 BaseLevel 赋值）。
var faction: String = ""
## 本回合是否已行动。
var has_acted: bool = false


func _ready() -> void:
	_apply_color()


func _apply_color() -> void:
	var visual := get_node_or_null("Visual")
	if visual is Polygon2D:
		(visual as Polygon2D).color = unit_color


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
	modulate = Color.WHITE
	cell = path[path.size() - 1]
	is_moving = false
	move_finished.emit()
