extends BaseLevel
## Debug level: procedurally generates a flat 10x10 tilemap for testing.

@onready var debug_label: Label = $GUI/DebugLabel

const GRID_SIZE := 10


func get_player_start_cell() -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(GRID_SIZE / 2, GRID_SIZE / 2)


func _ready() -> void:
	_create_debug_tilemap()
	super._ready()


func _on_level_ready() -> void:
	_update_status_bar()
	_update_debug_label()


func _create_debug_tilemap() -> void:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(32, 16)

	var source := TileSetAtlasSource.new()
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.45, 0.55, 0.35))
	var tex := ImageTexture.create_from_image(img)
	source.texture = tex
	source.texture_region_size = Vector2i(32, 32)
	source.create_tile(Vector2i(0, 0))
	ts.add_source(source, 0)

	var tm := TileMapLayer.new()
	tm.tile_set = ts
	tm.name = "WalkableMap"
	tilemap_container.add_child(tm)

	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			tm.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_update_debug_label()


func _on_player_moved() -> void:
	_update_status_bar()


func _update_status_bar() -> void:
	status_bar.set_status("状态1", str(player.cell))
	status_bar.set_status("状态2", "待机")


func _update_debug_label() -> void:
	if tilemap == null:
		return
	var mouse_cell := tilemap.local_to_map(tilemap.get_local_mouse_position())
	var on_grid := mouse_cell.x >= 0 and mouse_cell.x < GRID_SIZE and mouse_cell.y >= 0 and mouse_cell.y < GRID_SIZE
	debug_label.text = "Player: %s | Mouse: %s %s | Selected: %s" % [
		player.cell if player else "null", mouse_cell,
		"(on grid)" if on_grid else "(off grid)", player_selected
	]
