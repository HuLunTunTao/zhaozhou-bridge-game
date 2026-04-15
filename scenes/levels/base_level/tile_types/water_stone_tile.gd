class_name WaterStoneTile
extends TileType

func get_movement_cost() -> int:
	return 3

func is_water() -> bool:
	return true
