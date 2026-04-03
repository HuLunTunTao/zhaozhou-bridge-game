extends Node2D

@export var move_range: int = 4

var cell: Vector2i


func _ready() -> void:
	pass


func set_cell(new_cell: Vector2i, tilemap: TileMapLayer) -> void:
	cell = new_cell
	position = tilemap.map_to_local(cell)
