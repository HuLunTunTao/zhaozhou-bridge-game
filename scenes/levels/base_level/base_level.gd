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
@onready var units_container: Node2D = $Entities/Units
@onready var special_tiles_container: Node2D = $SpecialTiles
@onready var move_overlay: Node2D = $MoveOverlay
@onready var movement_manager: Node = $MovementManager
@onready var camera: Camera2D = $Camera2D
@onready var gui: CanvasLayer = $GUI
@onready var status_bar: HBoxContainer = $GUI/StatusPanel/MarginContainer/StatusBar

const SettingsPanelScene := preload("res://scenes/ui/settings_panel.tscn")

var tilemap: TileMapLayer
## 兼容旧版：指向第一个玩家控制队伍的第一个单位（李春）。
var hero: Node2D
var unit_selected := false
var _mid_cutscene_active := false
var _settings_open := false

## 输入状态机。
enum InputState { IDLE, UNIT_SELECTED, TARGETING_MOVE, ANIMATING }
var _input_state: InputState = InputState.IDLE

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
		hero = _find_hero()
		if hero:
			hero.set_cell(get_hero_start_cell(), tilemap)
			hero.movement_manager = movement_manager
	else:
		# ── 多队伍模式：读取场景中已有的节点 ───────────
		_setup_teams_from_config(team_configs)

	_reparent_entities_to_obstacles()
	_setup_special_tiles()
	if camera and camera is LevelCamera:
		(camera as LevelCamera).set_level_bounds(get_tilemap_bounds())
	_on_level_ready()
	_init_turn_system()
	# 初始显示主角信息
	if hero:
		_update_status_bar_for_unit(hero, false)


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
func get_hero_start_cell() -> Vector2i:
	return Vector2i(0, 0)


## 在基类 _ready 完成后调用，子关卡在此做额外初始化。
func _on_level_ready() -> void:
	pass


## 任意单位移动完毕后调用（兼容旧版钩子）。
func _on_unit_moved() -> void:
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

	# 向后兼容：hero 指向第一个玩家控制队伍的第一个单位
	for team: TeamData in teams:
		if team.controller == "player" and not team.units.is_empty():
			hero = team.units[0]
			break


# ─────────────────────────────────────────────
# 回合系统初始化
# ─────────────────────────────────────────────

func _init_turn_system() -> void:
	# 若未通过 get_teams_config() 创建队伍，则将旧版 player 包装为单队伍
	if teams.is_empty() and hero:
		var team := TeamData.new("玩家", "", "player")
		team.units.append(hero)
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
		# 回合开始重置计数器
		if unit is Unit and unit.combat_stats != null:
			unit.combat_stats.reset_turn_counters()
	selected_unit = null
	unit_selected = false
	_input_state = InputState.IDLE
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
	unit_selected = false
	_input_state = InputState.IDLE
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


## 在点击位置附近查找队伍中的单位。先精确匹配格子，不命中时回退到像素距离。
## max_dist 为像素距离阈值（等距半格约 16px，设 24px 兼顾易用与精度）。
func _find_nearest_team_unit(local_mouse_pos: Vector2, team: TeamData, max_dist: float = 24.0) -> Node2D:
	var clicked_cell := tilemap.local_to_map(local_mouse_pos)
	var exact := _get_unit_at_cell(clicked_cell, team)
	if exact != null:
		return exact
	var best: Node2D = null
	var best_dist := max_dist
	for unit: Node2D in team.units:
		var unit_pos := tilemap.map_to_local(unit.cell)
		var dist := local_mouse_pos.distance_to(unit_pos)
		if dist < best_dist:
			best_dist = dist
			best = unit
	return best


## 在点击位置附近查找任意队伍的单位（用于状态栏显示）。
func _find_nearest_any_unit(local_mouse_pos: Vector2, max_dist: float = 24.0) -> Node2D:
	var clicked_cell := tilemap.local_to_map(local_mouse_pos)
	# 先精确匹配
	for team: TeamData in teams:
		var exact := _get_unit_at_cell(clicked_cell, team)
		if exact != null:
			return exact
	# 回退到像素距离
	var best: Node2D = null
	var best_dist := max_dist
	for team: TeamData in teams:
		for unit: Node2D in team.units:
			var unit_pos := tilemap.map_to_local(unit.cell)
			var dist := local_mouse_pos.distance_to(unit_pos)
			if dist < best_dist:
				best_dist = dist
				best = unit
	return best


## 更新状态栏显示指定单位的信息。
func _update_status_bar_for_unit(unit: Node2D, is_active: bool = false) -> void:
	if status_bar and status_bar.has_method("show_unit"):
		status_bar.show_unit(unit, is_active)


## 状态栏回退显示主角。
func _reset_status_bar() -> void:
	if hero and status_bar and status_bar.has_method("show_unit"):
		status_bar.show_unit(hero, false)
	elif status_bar and status_bar.has_method("clear_unit"):
		status_bar.clear_unit()


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
# 输入处理（状态机 + 命令函数）
# ─────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _mid_cutscene_active or tilemap == null:
		return
	if not _waiting_for_player_input:
		return
	if _input_state == InputState.ANIMATING:
		return

	if event is InputEventMouseMotion:
		var hover_cell := tilemap.local_to_map(tilemap.get_local_mouse_position())
		preview_cell(hover_cell)
		return

	if not (event is InputEventMouseButton and event.pressed):
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		var clicked_cell := tilemap.local_to_map(tilemap.get_local_mouse_position())
		confirm_cell(clicked_cell)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		# 左键取消（ESC 也可以）
		cancel_action()

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_action()


## 预选：悬停到某格时更新预览。
func preview_cell(cell: Vector2i) -> void:
	match _input_state:
		InputState.TARGETING_MOVE:
			move_overlay.update_path(cell)
		# TARGETING_SKILL 将在 Phase 4 添加


## 确认：点击某格执行对应操作。
func confirm_cell(cell: Vector2i) -> void:
	var local_mouse := tilemap.get_local_mouse_position() if tilemap else Vector2.ZERO
	var current_team: TeamData = teams[current_team_index] if current_team_index >= 0 else null
	if current_team == null:
		return

	match _input_state:
		InputState.IDLE, InputState.UNIT_SELECTED:
			_confirm_idle(cell, local_mouse, current_team)
		InputState.TARGETING_MOVE:
			_confirm_targeting_move(cell, local_mouse, current_team)


## 取消：回到 IDLE，完全取消选中。
func cancel_action() -> void:
	if _input_state != InputState.IDLE:
		_go_idle()


## 选择技能（Phase 4 实现，目前预留）。
func select_skill(_skill: SkillData) -> void:
	pass


## 结束当前单位回合。
func end_unit_turn() -> void:
	if selected_unit:
		selected_unit.has_acted = true
	_go_idle()
	_check_all_units_acted()


func _go_idle() -> void:
	selected_unit = null
	unit_selected = false
	move_overlay.clear_range()
	_input_state = InputState.IDLE
	_reset_status_bar()


func _confirm_idle(cell: Vector2i, local_mouse: Vector2, current_team: TeamData) -> void:
	# 尝试选中当前队伍的单位
	var target := _find_nearest_team_unit(local_mouse, current_team)
	if target != null and not target.has_acted and not target.is_moving:
		selected_unit = target
		unit_selected = true
		_input_state = InputState.UNIT_SELECTED
		_update_status_bar_for_unit(target, true)
		# 自动进入移动模式
		_enter_targeting_move()
	else:
		# 点击了其他队伍的单位？显示其信息
		var any_unit := _find_nearest_any_unit(local_mouse)
		if any_unit != null:
			_update_status_bar_for_unit(any_unit, false)
		else:
			_reset_status_bar()


func _enter_targeting_move() -> void:
	if selected_unit == null:
		return
	_input_state = InputState.TARGETING_MOVE
	# 使用 AP 制或旧版
	var unit := selected_unit
	if unit is Unit and unit.combat_stats != null:
		var stats: CombatStats = unit.combat_stats
		if not stats.can_move():
			return
		var occupied: Array[Vector2i] = _get_occupied_cells_except(unit)
		move_overlay.show_range_ap(tilemap, movement_manager, unit.cell, stats.ap_current, stats.move_cost_per_tile, occupied)
	else:
		move_overlay.show_range(tilemap, movement_manager, unit.cell, unit.movement_points)


func _confirm_targeting_move(cell: Vector2i, local_mouse: Vector2, current_team: TeamData) -> void:
	if selected_unit == null:
		_go_idle()
		return

	if move_overlay.has_cell(cell):
		# 移动到目标格
		var path: Array[Vector2i] = move_overlay.get_path_to_cell(cell)
		var ap_cost: int = move_overlay.get_cost_to_cell(cell)
		move_overlay.clear_range()
		var moving_unit := selected_unit
		_input_state = InputState.ANIMATING
		moving_unit.move_along_path(path, tilemap)
		await moving_unit.move_finished
		# 扣除 AP
		if moving_unit is Unit and moving_unit.combat_stats != null:
			moving_unit.combat_stats.ap_current -= ap_cost
			moving_unit.combat_stats.moves_used += 1
		_on_unit_moved()
		# AP 剩余且还能行动？回到 UNIT_SELECTED
		if moving_unit is Unit and moving_unit.combat_stats != null:
			var stats: CombatStats = moving_unit.combat_stats
			if stats.ap_current > 0 and (stats.can_move() or _has_usable_skill(moving_unit)):
				selected_unit = moving_unit
				unit_selected = true
				_input_state = InputState.UNIT_SELECTED
				_update_status_bar_for_unit(moving_unit, true)
				# 自动重新进入移动模式
				if stats.can_move():
					_enter_targeting_move()
				return
		# 否则该单位行动结束
		moving_unit.has_acted = true
		_go_idle()
		_check_all_units_acted()
	else:
		# 点击范围外：尝试切换到其他单位
		var target := _find_nearest_team_unit(local_mouse, current_team)
		if target != null and target != selected_unit and not target.has_acted and not target.is_moving:
			selected_unit = target
			unit_selected = true
			_input_state = InputState.UNIT_SELECTED
			_update_status_bar_for_unit(target, true)
			_enter_targeting_move()
		else:
			var any_unit := _find_nearest_any_unit(local_mouse)
			if any_unit != null:
				_update_status_bar_for_unit(any_unit, false)
			_go_idle()


## 获取除指定单位外所有被占据的格子。
func _get_occupied_cells_except(exclude: Node2D) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for team: TeamData in teams:
		for unit: Node2D in team.units:
			if unit != exclude:
				result.append(unit.cell)
	return result


## 检查单位是否有可用技能（AP 够 + 次数未尽）。
func _has_usable_skill(unit: Node2D) -> bool:
	if not unit is Unit:
		return false
	var u := unit as Unit
	if u.combat_stats == null or u.unit_data == null:
		return false
	for skill: SkillData in u.unit_data.skills:
		if u.combat_stats.can_use_skill(skill):
			return true
	return false


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


func _find_hero() -> Node2D:
	for child in units_container.get_children():
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
