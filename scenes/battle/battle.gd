extends Node2D

@onready var player: Node2D = $Player
@onready var move_overlay: Node2D = $MoveOverlay

var tilemap: TileMapLayer
var player_selected := false

## Map of level number to scene path
const LEVEL_SCENES: Dictionary = {
	1: "res://scenes/levels/level1-1.tscn",
	2: "res://scenes/levels/level1-2.tscn",
	3: "res://scenes/levels/level1-3.tscn",
	4: "res://scenes/levels/level1-3-2.tscn",
	5: "res://scenes/levels/level1-4.tscn",
	6: "res://scenes/levels/test.tscn",
}

## Name of the walkable tilemap layer to look for in level scenes
const WALKABLE_LAYER_NAMES: Array[String] = ["surface z=0", "Main tile map z=0"]


func _ready() -> void:
	load_level(GameState.selected_level)


func load_level(level_num: int) -> void:
	# Remove previous level if any
	var old_level: Node = get_node_or_null("Level")
	if old_level:
		old_level.queue_free()
		await old_level.tree_exited

	# Load new level
	var path: String = LEVEL_SCENES.get(level_num, "")
	if path == "":
		push_error("No scene for level %d" % level_num)
		return
	var scene: PackedScene = load(path)
	var level_instance: Node = scene.instantiate()
	level_instance.name = "Level"
	add_child(level_instance)
	move_child(level_instance, 0)  # put behind player and overlay

	# Find walkable tilemap
	tilemap = _find_walkable_tilemap(level_instance)
	if tilemap == null:
		push_error("No walkable tilemap found in level %d" % level_num)
		return

	# Reset player state
	player_selected = false
	move_overlay.clear_range()
	player.set_cell(Vector2i(0, 0), tilemap)


func _find_walkable_tilemap(root: Node) -> TileMapLayer:
	for layer_name in WALKABLE_LAYER_NAMES:
		var node: Node = root.find_child(layer_name, true, false)
		if node is TileMapLayer:
			return node
	# Fallback: return first TileMapLayer found
	for child in root.get_children():
		if child is TileMapLayer:
			return child
	return null


func _unhandled_input(event: InputEvent) -> void:
	if tilemap == null or player.is_moving:
		return
	if event is InputEventMouseMotion and player_selected:
		var hover_cell := tilemap.local_to_map(tilemap.get_local_mouse_position())
		move_overlay.update_path(hover_cell)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var clicked_cell := tilemap.local_to_map(tilemap.get_local_mouse_position())

		if player_selected:
			if move_overlay.has_cell(clicked_cell):
				var path: Array[Vector2i] = move_overlay.get_path_to_cell(clicked_cell)
				move_overlay.clear_range()
				player_selected = false
				player.move_along_path(path, tilemap)
			else:
				player_selected = false
				move_overlay.clear_range()
		elif clicked_cell == player.cell:
			player_selected = true
			move_overlay.show_range(tilemap, player.cell, player.move_range)
