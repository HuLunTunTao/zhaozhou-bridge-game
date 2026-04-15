class_name DarkWaterTile
extends TileType

func get_movement_cost() -> int:
	return IMPASSABLE

func is_water() -> bool:
	return true
