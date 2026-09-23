class_name SpecialTileRegistry
extends RefCounted

## 特殊地块注册表 + 脉动标记工厂（Shared Kernel）。
## 从 BaseLevel 抽出，通过 setup(ctx) 注入宿主 Callable，不反向依赖 BaseLevel。
## 契约标杆：SpecialTile 基类及子类（silt_tile / rapid_edge_tile / small_arch_tile 等）不动。

const MARKER_SCENE: PackedScene = preload("res://scenes/levels/base_level/tile_pulsing_marker.tscn")

# ─── 宿主上下文 Callable（由 setup 注入） ───
var _get_special_tiles_container: Callable = Callable()
var _get_obstacles_tilemap_layer: Callable = Callable()
var _get_tilemap: Callable = Callable()
var _get_parent_for_marker: Callable = Callable()
var _get_movement_manager: Callable = Callable()
var _get_teams: Callable = Callable()

# ─── 内部状态 ───
## cell → SpecialTile
var _tile_map: Dictionary = {}
## entity → 最近进入的特殊地块 cell（用于区分抵达与经过）
var _pending_enter: Dictionary = {}


func setup(ctx: Dictionary) -> void:
	_get_special_tiles_container = ctx.get("get_special_tiles_container", Callable())
	_get_obstacles_tilemap_layer = ctx.get("get_obstacles_tilemap_layer", Callable())
	_get_tilemap = ctx.get("get_tilemap", Callable())
	_get_parent_for_marker = ctx.get("get_parent_for_marker", Callable())
	_get_movement_manager = ctx.get("get_movement_manager", Callable())
	_get_teams = ctx.get("get_teams", Callable())


## 返回内部字典引用（cell → SpecialTile）。宿主可用 .get() 查询。
func get_map() -> Dictionary:
	return _tile_map


## 扫描 special_tiles_container 里的 SpecialTile 子项，自动吸附到格；
## 并连接 movement_manager / unit 信号以派发 enter/leave 钩子。
func scan_from_container() -> void:
	var container: Node2D = _get_special_tiles_container.call() as Node2D \
			if _get_special_tiles_container.is_valid() else null
	if container == null:
		return
	var tilemap: TileMapLayer = _get_tilemap.call() as TileMapLayer \
			if _get_tilemap.is_valid() else null
	if tilemap == null:
		return
	var obstacles = _get_obstacles_tilemap_layer.call() \
			if _get_obstacles_tilemap_layer.is_valid() else null
	for child in container.get_children():
		if child is SpecialTile:
			var snapped_cell := tilemap.local_to_map(tilemap.to_local(child.global_position))
			child.cell = snapped_cell
			if obstacles != null:
				child.reparent(obstacles)
			child.position = tilemap.map_to_local(snapped_cell)
			_tile_map[snapped_cell] = child
	var mm = _get_movement_manager.call() if _get_movement_manager.is_valid() else null
	if mm != null:
		mm.tile_entered.connect(on_tile_entered)
		mm.tile_exited.connect(on_tile_exited)
	var teams: Array = _get_teams.call() if _get_teams.is_valid() else []
	for team in teams:
		for unit in team.units:
			unit.move_finished.connect(on_unit_move_finished.bind(unit))


## 查询指定格的 SpecialTile，失效条目自动清理。
func get_at(cell: Vector2i) -> SpecialTile:
	var tile = _tile_map.get(cell)
	if tile == null:
		return null
	if not is_instance_valid(tile) or not (tile is SpecialTile):
		_tile_map.erase(cell)
		return null
	return tile as SpecialTile


## 程序化注册一个 SpecialTile（跳过 scan_from_container 自动扫描）。
func register(tile: SpecialTile, cell: Vector2i) -> void:
	tile.cell = cell
	if not tile.is_inside_tree():
		var container = _get_special_tiles_container.call() \
				if _get_special_tiles_container.is_valid() else null
		if container != null:
			container.add_child(tile)
	var obstacles = _get_obstacles_tilemap_layer.call() \
			if _get_obstacles_tilemap_layer.is_valid() else null
	if obstacles != null:
		tile.reparent(obstacles)
	var tilemap = _get_tilemap.call() if _get_tilemap.is_valid() else null
	if tilemap != null:
		tile.position = tilemap.map_to_local(cell)
	_tile_map[cell] = tile


## 从派发表解除一个运行时特殊地格，避免 queue_free 后字典保留失效实例。幂等。
func unregister(tile: SpecialTile, cell: Vector2i) -> void:
	if _tile_map.get(cell) == tile:
		_tile_map.erase(cell)


## 在指定地块上方挂一个统一的脉动强调标记（菱形光晕 + 下指箭头 + 可选文字）。
## - cell：地块坐标。对 2×2 区域可传 NW 角并配合 local_offset = Vector2(0, 8) 居中。
## - halo_color：光晕颜色（核心色会自动按 alpha 推导）。
## - label_text：菱形上方的文字标签，留空则隐藏。
## - local_offset：相对 tilemap.map_to_local(cell) 的额外位移，用于 2×2 居中或微调。
## - node_name：可选节点名，便于调试 / 后续 queue_free。
## - tile_z_index：halo / core / label 的绝对 z（Floater 始终 120）。默认 1：覆盖
##   surface(0) 与 decoration(1)，被 obstacle z>=2 的角色覆盖。关卡若有更高 z 的
##   建筑/桥面层（如 level1-3 的 building bridge z=2 + obstacle z=3），传 2 让 halo
##   盖住桥面但仍处于角色之下。
func spawn_pulsing_marker(
		cell: Vector2i,
		halo_color: Color,
		label_text: String = "",
		local_offset: Vector2 = Vector2.ZERO,
		node_name: String = "",
		tile_z_index: int = 1) -> Marker2D:
	var marker: Marker2D = MARKER_SCENE.instantiate()
	if node_name != "":
		marker.name = node_name
	marker.z_index = tile_z_index
	marker.set("halo_color", halo_color)
	marker.set("label_text", label_text)
	var parent: Node = _get_parent_for_marker.call() \
			if _get_parent_for_marker.is_valid() else null
	if parent != null:
		parent.add_child(marker)
	var tilemap = _get_tilemap.call() if _get_tilemap.is_valid() else null
	if tilemap != null:
		marker.position = tilemap.map_to_local(cell) + local_offset
	return marker


# ─── enter / leave 钩子派发 ───

func on_tile_entered(cell: Vector2i, entity: Node2D) -> void:
	if get_at(cell) != null:
		_pending_enter[entity] = cell


func on_tile_exited(cell: Vector2i, entity: Node2D) -> void:
	var tile := get_at(cell)
	if tile == null:
		return
	if _pending_enter.get(entity) == cell:
		tile._on_unit_pass(entity)
		_pending_enter.erase(entity)
	else:
		tile._on_unit_depart(entity)


func on_unit_move_finished(entity: Node2D) -> void:
	if entity in _pending_enter:
		var cell: Vector2i = _pending_enter[entity]
		var tile := get_at(cell)
		if tile != null:
			tile._on_unit_arrive(entity)
		_pending_enter.erase(entity)
