extends Node2D

@export var move_range: int = 4
@export var actions: Array[ActionData] = []

var cell: Vector2i


func _ready() -> void:
	if actions.is_empty():
		_add_default_actions()


func set_cell(new_cell: Vector2i, tilemap: TileMapLayer) -> void:
	cell = new_cell
	position = tilemap.map_to_local(cell)


func _add_default_actions() -> void:
	for entry in [["action1", "动作1"], ["action2", "动作2"], ["action3", "动作3"]]:
		var a := ActionData.new()
		a.id = entry[0]
		a.label = entry[1]
		actions.append(a)
