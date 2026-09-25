class_name SceneBootstrap
extends RefCounted

## 场景引导组件（Tactics Stack）。
## 从 BaseLevel 抽出：walkable / obstacle TileMapLayer 查找（@export → 运行时查找 → 兜底回退）/
## 实体重挂到 Y-Sort 障碍层 / 地图边界 / 单位枚举与空格搜索 / TileMap 纹理过滤。
## 通过 setup(level) 持有宿主关卡，对 _level 保持鸭子调用，不反向依赖 BaseLevel。

## 单个队伍的运行时数据（真源在 TurnSystem，此处保留旧类型名供注解使用）。
const TeamData = TurnSystem.TeamData

## Names to search for the walkable tilemap layer
const WALKABLE_LAYER_NAMES: Array[String] = [
	"surface z=0", "Main tile map z=0", "WalkableMap",
]

## 障碍层名字关键字（大小写不敏感，前缀匹配）。导出构建里 @export 引用可能丢失
## （AGENTS Pitfalls #2），_find_obstacle_tilemap 用它们做运行时回退查找。
## "railing" 对应 level1-4 / 验桥日的 "railing z=7"（那两关用栏杆层当 Y-Sort 父层）。
const OBSTACLE_LAYER_KEYWORDS: Array[String] = ["obstacle", "障碍", "阻挡", "railing"]

var _level: Node = null   # BaseLevel 宿主


func setup(level: Node) -> void:
	_level = level


# ─────────────────────────────────────────────
# TileMapLayer 查找
# ─────────────────────────────────────────────

func find_walkable_tilemap() -> TileMapLayer:
	for layer_name in WALKABLE_LAYER_NAMES:
		var node: Node = _level.tilemap_container.find_child(layer_name, true, false)
		if node is TileMapLayer:
			return node
	for child in _level.tilemap_container.get_children():
		if child is TileMapLayer:
			return child
	return null


## 导出构建里 @export obstacles_tilemap_layer 可能为 null（AGENTS Pitfalls #2），
## 按节点名关键字模糊回退查找障碍层。用前缀匹配而非包含匹配，避免误命中
## "unvisiable obstacle"（modulate.a == 0 的隐形碰撞层，挂上去单位会被隐掉）。
func find_obstacle_tilemap() -> TileMapLayer:
	if _level.tilemap_container == null:
		return null
	for node: Node in _level.tilemap_container.find_children("*", "TileMapLayer", true, false):
		var lname := String(node.name).to_lower()
		for keyword in OBSTACLE_LAYER_KEYWORDS:
			if lname.begins_with(keyword.to_lower()):
				return node as TileMapLayer
	return null


func find_hero() -> Node2D:
	for child in _level.units_container.get_children():
		return child
	return null


func apply_tilemap_texture_filter() -> void:
	if _level.tilemap_container == null:
		return
	_level.tilemap_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for node: Node in _level.tilemap_container.find_children("*", "TileMapLayer", true):
		if node is TileMapLayer:
			node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func get_tilemap_bounds() -> Rect2:
	var has_bounds := false
	var res_bounds := Rect2()

	for child in _level.tilemap_container.get_children():
		if child is TileMapLayer:
			var bounds := Utils.get_tilemap_layer_bounds(child)
			if bounds.size == Vector2.ZERO:
				continue
			if not has_bounds:
				res_bounds = bounds
				has_bounds = true
				continue
			res_bounds = res_bounds.expand(bounds.position)
			res_bounds = res_bounds.expand(bounds.end)

	return res_bounds


# ─────────────────────────────────────────────
# 场景辅助
# ─────────────────────────────────────────────

func reparent_entities_to_obstacles() -> void:
	if _level.obstacles_tilemap_layer == null:
		push_error("obstacles_tilemap_layer is not set; cannot reparent entities")
		return
	var entities: Node2D = _level.get_node("Entities")
	for container in entities.get_children():
		for entity in container.get_children():
			# keep_global_transform=true (default) preserves world position
			entity.reparent(_level.obstacles_tilemap_layer)
			# Snap to nearest tile cell so cell property matches visual position
			if _level.tilemap != null:
				var nearest_cell: Vector2i = _level.tilemap.local_to_map(
						_level.tilemap.to_local(entity.global_position))
				if entity.has_method("set_cell"):
					entity.set_cell(nearest_cell, _level.tilemap)
				else:
					entity.global_position = _level.tilemap.to_global(
							_level.tilemap.map_to_local(nearest_cell))
					if "cell" in entity:
						entity.cell = nearest_cell
	_level.obstacles_tilemap_layer.y_sort_enabled = true
	for child in _level.obstacles_tilemap_layer.get_children():
		if child is Node2D:
			child.y_sort_enabled = true


# ─────────────────────────────────────────────
# 单位枚举与空格搜索
# ─────────────────────────────────────────────

func get_all_units() -> Array:
	var result: Array = []
	for team: TeamData in _level.teams:
		for unit: Node2D in team.units:
			result.append(unit)
	return result


## 找一个"空且可走"的格。同心方环外扩搜索，max_radius 控制最大半径。
## 找不到时返回 target 本身（不静默崩；调用方可以看到 spawn_unit 的 push_warning）。
## 复用 movement_manager.get_movement_cost 判地形 + _get_all_units 判占位。
func find_empty_walkable_cell(target: Vector2i, max_radius: int = 4) -> Vector2i:
	if is_cell_walkable_and_empty(target):
		return target
	for radius in range(1, max_radius + 1):
		# 只扫方环边界（内部已在前一轮试过）
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var candidate := target + Vector2i(dx, dy)
				if is_cell_walkable_and_empty(candidate):
					return candidate
	return target


func is_cell_walkable_and_empty(cell: Vector2i) -> bool:
	if _level.movement_manager == null:
		return false
	if _level.movement_manager.get_movement_cost(cell) < 0:
		return false
	for unit in get_all_units():
		if not is_instance_valid(unit):
			continue
		if unit is Unit and (unit as Unit).cell == cell:
			return false
	return true
