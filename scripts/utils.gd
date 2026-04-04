class_name Utils

static func get_tilemap_layer_bounds(layer: TileMapLayer) -> Rect2:
	var used: Rect2i = layer.get_used_rect()
	if used.size == Vector2i.ZERO:
		return Rect2()

	var tile_size := Vector2(layer.tile_set.tile_size)
	var half := tile_size * 0.5

	var corners := [
		used.position,
		used.position + Vector2i(used.size.x - 1, 0),
		used.position + Vector2i(0, used.size.y - 1),
		used.position + used.size - Vector2i.ONE
	]

	var has_any := false
	var result := Rect2()

	for c in corners:
		var p := layer.to_global(layer.map_to_local(c))
		var r := Rect2(p - half, tile_size)

		if not has_any:
			result = r
			has_any = true
		else:
			result = result.expand(r.position)
			result = result.expand(r.position + r.size)

	return result