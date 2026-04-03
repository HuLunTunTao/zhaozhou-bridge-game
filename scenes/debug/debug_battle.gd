extends Node2D
## Debug scene for testing battle logic on a procedurally generated flat tilemap.

@onready var player: Node2D = $Player
@onready var move_overlay: Node2D = $MoveOverlay
@onready var debug_label: Label = $CanvasLayer/DebugLabel

var tilemap: TileMapLayer
var player_selected := false

const GRID_SIZE := 10


func _ready() -> void:
	_create_tilemap()
	@warning_ignore("integer_division")
	player.set_cell(Vector2i(GRID_SIZE / 2, GRID_SIZE / 2), tilemap)
	_update_debug_label()


func _create_tilemap() -> void:
	# Create a TileSet in code with isometric settings
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(32, 16)

	# Add a dummy source so get_cell_source_id returns 0 instead of -1
	var source := TileSetAtlasSource.new()
	# Create a 1x1 white image as texture
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.45, 0.55, 0.35))
	var tex := ImageTexture.create_from_image(img)
	source.texture = tex
	source.texture_region_size = Vector2i(32, 32)
	source.create_tile(Vector2i(0, 0))
	ts.add_source(source, 0)

	tilemap = TileMapLayer.new()
	tilemap.tile_set = ts
	tilemap.name = "DebugTileMap"
	add_child(tilemap)
	move_child(tilemap, 0)

	# Fill a GRID_SIZE x GRID_SIZE grid
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			tilemap.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var clicked_cell := tilemap.local_to_map(tilemap.get_local_mouse_position())

		if player_selected:
			if event.button_index == MOUSE_BUTTON_RIGHT and move_overlay.has_cell(clicked_cell):
				player.set_cell(clicked_cell, tilemap)
			player_selected = false
			move_overlay.clear_range()
		elif event.button_index == MOUSE_BUTTON_RIGHT and clicked_cell == player.cell:
			player_selected = true
			move_overlay.show_range(tilemap, player.cell, player.move_range)

		_update_debug_label()

	if event is InputEventMouseMotion:
		_update_debug_label()


func _update_debug_label() -> void:
	var mouse_cell := tilemap.local_to_map(tilemap.get_local_mouse_position())
	var on_grid := mouse_cell.x >= 0 and mouse_cell.x < GRID_SIZE and mouse_cell.y >= 0 and mouse_cell.y < GRID_SIZE
	debug_label.text = "Player: %s | Mouse: %s %s | Selected: %s" % [
		player.cell, mouse_cell, "(on grid)" if on_grid else "(off grid)", player_selected
	]
