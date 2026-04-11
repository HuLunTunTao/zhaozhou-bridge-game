class_name MovementManager
extends Node
## 集中管理地块信息查询。
## tile_type_map 将地形名称映射到 TileType 实例。
## 子关卡可通过覆盖 _setup_tile_types() 来注册自定义类型。

signal tile_entered(cell: Vector2i, entity: Node2D)
signal tile_exited(cell: Vector2i, entity: Node2D)

## 用于查询移动消耗的 TileMapLayer 列表，顺序为从上到下（第一个匹配的层优先）。
@export var movement_tilemaps: Array[TileMapLayer] = []
## 障碍物层，这些层中存在地块的格子视为不可通行。
@export var obstacle_tilemaps: Array[TileMapLayer] = []

## 地形名 → TileType 实例。子类可在 _setup_tile_types() 中修改。
var tile_type_map: Dictionary = {}


func _ready() -> void:
	_setup_tile_types()


## 注册默认地块类型。子类 override 此函数来替换或追加自定义类型。
func _setup_tile_types() -> void:
	tile_type_map = {
		"earth":       EarthTile.new(),
		"grass":       GrassTile.new(),
		"stone_road":  StoneRoadTile.new(),
		"water":       WaterTile.new(),
		"dark_water":  DarkWaterTile.new(),
		"water_stone": WaterStoneTile.new(),
		"decora":      DecoraTile.new(),
	}


## 返回进入该格的移动点消耗。TileType.IMPASSABLE(-1) 表示不可通行。
func get_movement_cost(cell: Vector2i) -> int:
	if is_blocked(cell):
		return TileType.IMPASSABLE
	var tile := _get_tile_type(cell)
	if tile == null:
		return TileType.IMPASSABLE
	return tile.get_movement_cost()


## 障碍物检测：obstacle_tilemaps 中有地块即视为不可通行。
func is_blocked(cell: Vector2i) -> bool:
	for layer: TileMapLayer in obstacle_tilemaps:
		if layer == null:
			continue
		if layer.get_cell_source_id(cell) != -1:
			return true
	return false


## 是否存在可移动地块（不考虑障碍物）。
func has_tile(cell: Vector2i) -> bool:
	return _get_tile_type(cell) != null


## 发出 tile_exited 信号并调用对应 TileType.on_exit。
func on_tile_exit(cell: Vector2i, entity: Node2D) -> void:
	tile_exited.emit(cell, entity)
	var tile := _get_tile_type(cell)
	if tile:
		tile.on_exit(entity)


## 发出 tile_entered 信号并调用对应 TileType.on_enter。
func on_tile_enter(cell: Vector2i, entity: Node2D) -> void:
	tile_entered.emit(cell, entity)
	var tile := _get_tile_type(cell)
	if tile:
		tile.on_enter(entity)


## 从 movement_tilemaps 中查找最上层地块对应的 TileType。
## 若地块存在但无 terrain 数据，回退为 earth（消耗1）。
func _get_tile_type(cell: Vector2i) -> TileType:
	for layer: TileMapLayer in movement_tilemaps:
		if layer == null:
			continue
		if layer.get_cell_source_id(cell) == -1:
			continue
		var tile_data: TileData = layer.get_cell_tile_data(cell)
		if tile_data == null:
			return tile_type_map.get("earth", EarthTile.new())
		var ts: int = tile_data.terrain_set
		var tid: int = tile_data.terrain
		if ts < 0 or tid < 0:
			# 有地块但无 terrain — 回退默认
			return tile_type_map.get("earth", EarthTile.new())
		var terrain_name: String = layer.tile_set.get_terrain_name(ts, tid)
		return tile_type_map.get(terrain_name, tile_type_map.get("earth", EarthTile.new()))
	return null
