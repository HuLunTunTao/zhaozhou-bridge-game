class_name BaseLevel
extends Node2D
## Base class for all battle levels.
## Inherited scenes should add TileMapLayers under the TileMaps node,
## and place Player instances under the Players node.

@export var map_scene: PackedScene

@onready var tilemap_container: Node2D = $TileMaps
@onready var players_container: Node2D = $Entities/Players
@onready var enemies_container: Node2D = $Entities/Enemies
@onready var move_overlay: Node2D = $MoveOverlay
@onready var camera: Camera2D = $Camera2D
@onready var gui: CanvasLayer = $GUI
@onready var status_bar: HBoxContainer = $GUI/StatusPanel/MarginContainer/StatusBar

var tilemap: TileMapLayer
var player: Node2D
var player_selected := false

## Names to search for the walkable tilemap layer
const WALKABLE_LAYER_NAMES: Array[String] = [
	"surface z=0", "Main tile map z=0", "WalkableMap",
]


func _ready() -> void:
	# 加载地图
	if map_scene:
		var map_instance: Node = map_scene.instantiate()
		map_instance.name = "MapData"
		tilemap_container.add_child(map_instance)

	tilemap = _find_walkable_tilemap()
	if tilemap == null:
		push_error("No walkable tilemap found in level")
		return
	player = _find_player()
	if player:
		player.set_cell(get_player_start_cell(), tilemap)
	_on_level_ready()


## Override in inherited levels to set player start position.
func get_player_start_cell() -> Vector2i:
	return Vector2i(0, 0)


## Override in inherited levels for custom setup after base _ready.
func _on_level_ready() -> void:
	pass


## Override for custom logic after player moves.
func _on_player_moved() -> void:
	pass


func _find_walkable_tilemap() -> TileMapLayer:
	for layer_name in WALKABLE_LAYER_NAMES:
		var node: Node = tilemap_container.find_child(layer_name, true, false)
		if node is TileMapLayer:
			return node
	for child in tilemap_container.get_children():
		if child is TileMapLayer:
			return child
	return null


func _find_player() -> Node2D:
	for child in players_container.get_children():
		return child
	return null


func _unhandled_input(event: InputEvent) -> void:
	if tilemap == null or player == null or player.is_moving:
		return

	if event is InputEventMouseMotion:
		if player_selected:
			var hover_cell := tilemap.local_to_map(tilemap.get_local_mouse_position())
			move_overlay.update_path(hover_cell)
		return

	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_RIGHT:
		return

	var clicked_cell := tilemap.local_to_map(tilemap.get_local_mouse_position())

	if player_selected:
		if move_overlay.has_cell(clicked_cell):
			var path: Array[Vector2i] = move_overlay.get_path_to_cell(clicked_cell)
			move_overlay.clear_range()
			player_selected = false
			player.move_along_path(path, tilemap)
			await player.move_finished
			_on_player_moved()
		else:
			player_selected = false
			move_overlay.clear_range()
	elif clicked_cell == player.cell:
		player_selected = true
		move_overlay.show_range(tilemap, player.cell, player.move_range)
