class_name BaseLevel
extends Node2D
## Base class for all battle levels.
## Inherited scenes should add TileMapLayers under the TileMaps node,
## and place unit nodes under the Entities node.
##
## 队伍与回合机制：
##   - 子关卡覆盖 get_teams_config() 返回队伍配置。
##   - 角色节点挂载在场景中，颜色与初始格子通过 @export 在编辑器中设置。
##   - 若不覆盖 get_teams_config()，则沿用旧的单玩家行为。

@export var obstacles_tilemap_layer: TileMapLayer  # 障碍物所在的层，必须在编辑器中指定

@onready var tilemap_container: Node2D = $TileMaps
@onready var players_container: Node2D = $Entities/Players
@onready var enemies_container: Node2D = $Entities/Enemies
@onready var special_tiles_container: Node2D = $SpecialTiles
@onready var move_overlay: Node2D = $MoveOverlay
@onready var movement_manager: Node = $MovementManager
@onready var camera: Camera2D = $Camera2D
@onready var gui: CanvasLayer = $GUI
@onready var status_bar: HBoxContainer = $GUI/StatusPanel/MarginContainer/StatusBar

const SettingsPanelScene := preload("res://scenes/ui/settings_panel.tscn")

var tilemap: TileMapLayer
## 兼容旧版：指向第一个玩家控制队伍的第一个单位。
var player: Node2D
var player_selected := false
var _mid_cutscene_active := false
var _settings_open := false

## Names to search for the walkable tilemap layer
const WALKABLE_LAYER_NAMES: Array[String] = [
	"surface z=0", "Main tile map z=0", "WalkableMap",
]

# ─────────────────────────────────────────────
# 队伍 / 回合系统
# ─────────────────────────────────────────────

## 单个队伍的运行时数据。
class TeamData:
	var team_name: String
	var faction: String
	## "player" = 玩家操控；"ai" = 电脑操控。
	var controller: String
	var units: Array = []  # Array[Node2D]

	func _init(n: String, f: String, c: String) -> void:
		team_name = n
		faction = f
		controller = c
		units = []

var teams: Array = []  # Array[TeamData]
var current_team_index: int = -1
## 当前选中的单位（玩家回合时有效）。
var selected_unit: Node2D = null
## 当前是否等待玩家输入。
var _waiting_for_player_input: bool = false

## 特殊地块：cell → SpecialTile
var _special_tile_map: Dictionary = {}
## 缓冲：entity → 最近进入的特殊地块 cell（用于区分抵达与经过）
var _pending_special_enter: Dictionary = {}

@onready var _turn_label: Label = $GUI/TurnLabel
@onready var _end_turn_button: Button = $GUI/EndTurnButton


func _ready() -> void:
	tilemap = _find_walkable_tilemap()
	if tilemap == null:
		push_error("No walkable tilemap found in level")
		return
	# 若 MovementManager 的 movement_tilemaps 未在编辑器中配置，自动填入 walkable tilemap 作为回退
	if movement_manager and movement_manager.movement_tilemaps.is_empty():
		movement_manager.movement_tilemaps.append(tilemap)

	var team_configs := get_teams_config()
	if team_configs.is_empty():
		# ── 旧版单玩家模式 ──────────────────────────────
		player = _find_player()
		if player:
			player.set_cell(get_player_start_cell(), tilemap)
			player.movement_manager = movement_manager
	else:
		# ── 多队伍模式：读取场景中已有的节点 ───────────
		_setup_teams_from_config(team_configs)

	_reparent_entities_to_obstacles()
	_setup_special_tiles()
	if camera and camera is LevelCamera:
		(camera as LevelCamera).set_level_bounds(get_tilemap_bounds())
	_on_level_ready()
	_init_turn_system()


# ─────────────────────────────────────────────
# 可覆盖的虚方法
# ─────────────────────────────────────────────

## 返回队伍配置列表，元素为 Dictionary：
##   name       : String      — 队伍显示名
##   faction    : String      — 阵营名（同阵营不可互攻，不同阵营可互攻）
##   controller : String      — "player" | "ai"
##   units      : Array[Node] — 场景中已挂载的角色节点（颜色和初始格子在节点上设置）
## 返回空数组则使用旧版单玩家行为。
func get_teams_config() -> Array:
	return []


## 覆盖以设置旧版单玩家的起始位置（仅在 get_teams_config() 为空时使用）。
func get_player_start_cell() -> Vector2i:
	return Vector2i(0, 0)


## 在基类 _ready 完成后调用，子关卡在此做额外初始化。
func _on_level_ready() -> void:
	pass


## 任意单位移动完毕后调用（兼容旧版钩子）。
func _on_player_moved() -> void:
	pass


# ─────────────────────────────────────────────
# 队伍初始化（读取场景已有节点）
# ─────────────────────────────────────────────

func _setup_teams_from_config(configs: Array) -> void:
	for i in range(configs.size()):
		var cfg: Dictionary = configs[i]
		var team := TeamData.new(
			cfg.get("name", "队伍%d" % i),
			cfg.get("faction", ""),
			cfg.get("controller", "ai")
		)
		for unit: Node2D in cfg.get("units", []):
			unit.team_index = i
			unit.faction = team.faction
			unit.movement_manager = movement_manager
			# 从节点在编辑器中的位置推算所在格子并对齐到格子中心
			var snapped_cell := tilemap.local_to_map(tilemap.to_local(unit.global_position))
			unit.set_cell(snapped_cell, tilemap)
			team.units.append(unit)
		teams.append(team)

	# 向后兼容：player 指向第一个玩家控制队伍的第一个单位
	for team: TeamData in teams:
		if team.controller == "player" and not team.units.is_empty():
			player = team.units[0]
			break


# ─────────────────────────────────────────────
# 回合系统初始化
# ─────────────────────────────────────────────

func _init_turn_system() -> void:
	# 若未通过 get_teams_config() 创建队伍，则将旧版 player 包装为单队伍
	if teams.is_empty() and player:
		var team := TeamData.new("玩家", "", "player")
		team.units.append(player)
		teams.append(team)

	if teams.is_empty():
		return

	_start_team_turn(0)


# ─────────────────────────────────────────────
# 回合流转
# ─────────────────────────────────────────────

func _start_team_turn(index: int) -> void:
	current_team_index = index
	var team: TeamData = teams[index]
	for unit: Node2D in team.units:
		unit.has_acted = false
	selected_unit = null
	player_selected = false
	move_overlay.clear_range()

	if _turn_label:
		_turn_label.text = "[ %s 的回合 ]" % team.team_name

	if team.controller == "ai":
		if _end_turn_button:
			_end_turn_button.visible = false
		_waiting_for_player_input = false
		# 延迟一帧再执行 AI，确保 UI 更新后再开始移动
		_run_ai_turn.call_deferred(team)
	else:
		if _end_turn_button:
			_end_turn_button.visible = true
		_waiting_for_player_input = true


func _end_current_turn() -> void:
	_waiting_for_player_input = false
	selected_unit = null
	player_selected = false
	move_overlay.clear_range()
	if _end_turn_button:
		_end_turn_button.visible = false
	var next_index := (current_team_index + 1) % teams.size()
	_start_team_turn(next_index)


func _on_end_turn_button_pressed() -> void:
	if _waiting_for_player_input:
		_end_current_turn()


func _check_all_units_acted() -> void:
	if current_team_index < 0 or current_team_index >= teams.size():
		return
	var team: TeamData = teams[current_team_index]
	if team.controller != "player":
		return
	for unit: Node2D in team.units:
		if not unit.has_acted:
			return
	# 全员行动完毕，自动结束回合
	_end_current_turn()


# ─────────────────────────────────────────────
# AI 回合
# ─────────────────────────────────────────────

func _run_ai_turn(team: TeamData) -> void:
	# TODO: 完善 AI —— 目前为随机向相邻格移动一步
	for unit: Node2D in team.units:
		if not unit.is_moving:
			await _ai_move_unit(unit)
		unit.has_acted = true
	_end_current_turn()


func _ai_move_unit(unit: Node2D) -> void:
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
	]
	dirs.shuffle()
	for dir: Vector2i in dirs:
		var target_cell: Vector2i = unit.cell + dir
		if movement_manager.get_movement_cost(target_cell) != TileType.IMPASSABLE \
				and not _is_cell_occupied(target_cell):
			var path: Array[Vector2i] = [unit.cell, target_cell]
			unit.move_along_path(path, tilemap)
			await unit.move_finished
			return


func _is_cell_occupied(cell: Vector2i) -> bool:
	for team: TeamData in teams:
		for unit: Node2D in team.units:
			if unit.cell == cell:
				return true
	return false


func _is_any_unit_moving() -> bool:
	for team: TeamData in teams:
		for unit: Node2D in team.units:
			if unit.is_moving:
				return true
	return false


func _get_unit_at_cell(cell: Vector2i, team: TeamData) -> Node2D:
	for unit: Node2D in team.units:
		if unit.cell == cell:
			return unit
	return null


# ─────────────────────────────────────────────
# 关卡完成 / 剧情
# ─────────────────────────────────────────────

## Play a mid-battle cutscene as an overlay. Blocks until finished.
func play_mid_cutscene(pages: Array[String]) -> void:
	_mid_cutscene_active = true
	var cutscene: CutscenePlayer = preload("res://scenes/cutscene/cutscene_player.tscn").instantiate()
	add_child(cutscene)
	cutscene.setup(pages)
	await cutscene.cutscene_finished
	_mid_cutscene_active = false


## Call when the level is won. Handles post-cutscene or returns to menu.
func complete_level() -> void:
	var level := GameState.selected_level
	if GameState.has_cutscene(level, "post"):
		GameState.pending_cutscene_pages = GameState.get_cutscene_pages(level, "post")
		GameState.pending_next_scene = "res://scenes/menu/main_menu.tscn"
		get_tree().change_scene_to_file("res://scenes/cutscene/cutscene_scene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


func _on_settings_button_pressed() -> void:
	if _settings_open:
		return
	_settings_open = true
	var panel: SettingsPanel = SettingsPanelScene.instantiate()
	panel.show_back_to_menu = true
	add_child(panel)
	panel.closed.connect(func(): _settings_open = false)


# ─────────────────────────────────────────────
# 输入处理
# ─────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_settings_button_pressed()
		return
	if _mid_cutscene_active:
		return
	if tilemap == null:
		return
	if not _waiting_for_player_input:
		return
	if _is_any_unit_moving():
		return

	var current_team: TeamData = teams[current_team_index]

	if event is InputEventMouseMotion:
		if selected_unit != null:
			var hover_cell := tilemap.local_to_map(tilemap.get_local_mouse_position())
			move_overlay.update_path(hover_cell)
		return

	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_RIGHT:
		return

	var clicked_cell := tilemap.local_to_map(tilemap.get_local_mouse_position())

	if selected_unit != null:
		if move_overlay.has_cell(clicked_cell):
			# 移动选中单位到目标格
			var path: Array[Vector2i] = move_overlay.get_path_to_cell(clicked_cell)
			move_overlay.clear_range()
			var moving_unit := selected_unit
			selected_unit = null
			player_selected = false
			moving_unit.move_along_path(path, tilemap)
			await moving_unit.move_finished
			moving_unit.has_acted = true
			_on_player_moved()
		else:
			# 尝试切换选中到同队伍其他单位
			var target_unit := _get_unit_at_cell(clicked_cell, current_team)
			if target_unit != null and not target_unit.has_acted and not target_unit.is_moving:
				selected_unit = target_unit
				player_selected = true
				move_overlay.show_range(tilemap, movement_manager, target_unit.cell, target_unit.movement_points)
			else:
				selected_unit = null
				player_selected = false
				move_overlay.clear_range()
	else:
		# 尝试选中当前队伍的一个单位
		var target_unit := _get_unit_at_cell(clicked_cell, current_team)
		if target_unit != null and not target_unit.has_acted and not target_unit.is_moving:
			selected_unit = target_unit
			player_selected = true
			move_overlay.show_range(tilemap, movement_manager, target_unit.cell, target_unit.movement_points)


# ─────────────────────────────────────────────
# 特殊地块
# ─────────────────────────────────────────────

func _setup_special_tiles() -> void:

	if special_tiles_container == null:
		return
	for child in special_tiles_container.get_children():
		if child is SpecialTile:
			var snapped_cell := tilemap.local_to_map(tilemap.to_local(child.global_position))
			child.cell = snapped_cell
			child.reparent(obstacles_tilemap_layer)
			child.position = tilemap.map_to_local(snapped_cell)
			_special_tile_map[snapped_cell] = child
	movement_manager.tile_entered.connect(_on_special_tile_entered)
	movement_manager.tile_exited.connect(_on_special_tile_exited)
	# 连接所有单位的 move_finished 信号，用于判定"抵达"
	for team: TeamData in teams:
		for unit: Node2D in team.units:
			unit.move_finished.connect(_on_unit_move_finished_special.bind(unit))


func _on_special_tile_entered(cell: Vector2i, entity: Node2D) -> void:
	if cell in _special_tile_map:
		_pending_special_enter[entity] = cell


func _on_special_tile_exited(cell: Vector2i, entity: Node2D) -> void:
	if cell not in _special_tile_map:
		return
	if _pending_special_enter.get(entity) == cell:
		# 进入后又离开 → 经过
		_special_tile_map[cell]._on_unit_pass(entity)
		_pending_special_enter.erase(entity)
	else:
		# 没有对应的 pending enter → 从此格出发
		_special_tile_map[cell]._on_unit_depart(entity)


func _on_unit_move_finished_special(entity: Node2D) -> void:
	if entity in _pending_special_enter:
		var cell: Vector2i = _pending_special_enter[entity]
		if cell in _special_tile_map:
			_special_tile_map[cell]._on_unit_arrive(entity)
		_pending_special_enter.erase(entity)


# ─────────────────────────────────────────────
# 场景辅助
# ─────────────────────────────────────────────

func _reparent_entities_to_obstacles() -> void:
	if obstacles_tilemap_layer == null:
		push_error("obstacles_tilemap_layer is not set; cannot reparent entities")
		return
	var entities: Node2D = $Entities
	for container in entities.get_children():
		for entity in container.get_children():
			# keep_global_transform=true (default) preserves world position
			entity.reparent(obstacles_tilemap_layer)
			# Snap to nearest tile cell so cell property matches visual position
			if tilemap != null:
				var nearest_cell := tilemap.local_to_map(
						tilemap.to_local(entity.global_position))
				if entity.has_method("set_cell"):
					entity.set_cell(nearest_cell, tilemap)
				else:
					entity.global_position = tilemap.to_global(
							tilemap.map_to_local(nearest_cell))
					if "cell" in entity:
						entity.cell = nearest_cell
	obstacles_tilemap_layer.y_sort_enabled = true
	for child in obstacles_tilemap_layer.get_children():
		if child is Node2D:
			child.y_sort_enabled = true


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


func get_tilemap_bounds() -> Rect2:
	var has_bounds := false
	var res_bounds := Rect2()

	for child in tilemap_container.get_children():
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
