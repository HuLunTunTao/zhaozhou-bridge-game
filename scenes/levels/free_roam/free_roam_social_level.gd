class_name FreeRoamSocialLevel
extends Node2D

## 自由移动社交关卡基类（Social Stack）。**只继承 Node2D**，不继承 BaseLevel。
## 供验桥日这类「自由移动 + 实时社交交互」关卡使用。
## **AP 概念已删除**（点地即达）；回合 / AI / 技能结算 / 元素 / 成长 / prebattle 全部不存在。
## Shared Kernel 通过 setup(ctx) 注入 Callable 装配（风格与 LevelStateMachine.setup 一致）。
##
## 单位模型决策（Task 2.5）：**不引入 GridActor 新基类**，沿用 `Unit` + 最小 `CombatStats`。
## Unit 已有 move_along_path / set_cell / move_finished / refresh_overhead_bars，
## 换基类需全量重实现，得不偿失；空 CombatStats 足够满足 bridge_tour 等处的 is_alive() 读取。
##
## 子类职责：
##   - 场景提供 TileMaps / SpecialTiles / MoveOverlay / MovementManager / Camera2D / StatusBarScene
##   - _on_level_ready() 里布置主角（hero = ...）与 NPC
##   - 覆写 get_objectives_text / check_victory / check_defeat / _on_actor_* 等虚方法
##   - 目标计数驱动的通关走 SocialLevelEndFlow（get_end_flow().add_goal / increment）
##
## 对外委托 API 与 BaseLevel 同名同签名，便于 bridge_tour 迁移（Task 2.24）。

const _LI_CHUN_PORTRAIT := preload("res://assets/face/li_chun.png")
const ObjectivesPanelScene := preload("res://scenes/ui/objectives_panel.tscn")

## 关卡生命周期粗粒度时间线，单向转换 BRIEFING → PLAYING → ENDED。
const LevelPhase = LevelStateMachine.LevelPhase

## 当前独占前景的瞬态 UI。同时只能有一个非 NONE。
const ActiveOverlay = LevelStateMachine.ActiveOverlay

## 输入状态机（真源在 LevelStateMachine，与 Tactics Stack 共享）。
const InputState = LevelStateMachine.InputState

## Names to search for the walkable tilemap layer
const WALKABLE_LAYER_NAMES: Array[String] = [
	"surface z=0", "Main tile map z=0", "WalkableMap",
]

## 障碍层名字关键字（大小写不敏感，前缀匹配）。导出构建里 @export 引用可能丢失
## （AGENTS Pitfalls #2），_find_obstacle_tilemap 用它们做运行时回退查找。
const OBSTACLE_LAYER_KEYWORDS: Array[String] = ["obstacle", "障碍", "阻挡", "railing"]

# ─────────────────────────────────────────────
# 关卡状态机（双轴：LevelPhase × ActiveOverlay）
# ─────────────────────────────────────────────

## 关卡主阶段切换（BRIEFING → PLAYING → ENDED）。子关卡订阅启动开场演出等。
signal phase_changed(new_phase: int)
## overlay 打开/关闭。用于观察者，不负责互斥（互斥由 _open_overlay 守护）。
signal overlay_opened(kind: int)
signal overlay_closed(kind: int)

@export var obstacles_tilemap_layer: TileMapLayer  # 障碍 / Y-Sort 父层，必须在编辑器中指定

@onready var tilemap_container: Node2D = $TileMaps
@onready var special_tiles_container: Node2D = $SpecialTiles
@onready var move_overlay: Node2D = $MoveOverlay
@onready var movement_manager: MovementManager = $MovementManager
@onready var camera: LevelCamera = $Camera2D
@onready var status_bar: HBoxContainer = $StatusBarScene/PanelContainer/MarginContainer/StatusBar

var tilemap: TileMapLayer
## 兼容 BaseLevel 契约的主角（李春）。ActorRegistry 未设 hero 时的回落字段（静态摆放路径）。
var hero: Node2D
## 当前是否等待玩家输入。自由移动关卡常开（无回合节拍）。
var _waiting_for_player_input: bool = true
## 输入状态机。LOCKED 表示被外部流程显式锁定（如对话流），与 ANIMATING（基类演出）正交。
var _input_state: InputState = InputState.IDLE

## 双轴状态机组件（RefCounted）。状态真源，本类通过方法委托。
var _state: LevelStateMachine = null
## 对话桥接组件。play_dialogue / _lc_line / play_chatter_* 的实际执行者。
var _dialogue: DialogueBridge = null
## 状态栏桥接组件。_update_status_bar_for_unit / _reset_status_bar 的实际执行者。
var _status_bar_bridge: StatusBarBridge = null
## 相机 input_enabled 快照句柄。由 LevelStateMachine 持有与嵌套计数，这里保留同一引用。
var _camera_handle: CameraHandle = null
## 特殊地块注册表。register / get_at / 脉动标记工厂 / enter-leave 派发。
var _special_tiles: SpecialTileRegistry = null
## 单位注册表。spawn_unit 自动注册；按 id / node_name / role / cell 查询，不依赖 TeamData。
var _actors: ActorRegistry = null
## 自由移动输入状态机（5 状态：IDLE / UNIT_SELECTED / TARGETING_MOVE / LOCKED / ANIMATING）。
## 已接 MovementManager + MoveOverlay 做可达范围预览与路径执行（2.3）。
var _input: FreeRoamInputController = null
## 目标计数驱动的通关流（Task 2.6）。子类 add_goal / increment 后自动 check_end_conditions。
var _end_flow: SocialLevelEndFlow = SocialLevelEndFlow.new()


func _init() -> void:
	_state = LevelStateMachine.new()
	var lock_input := func() -> void:
		if _input_state != InputState.ANIMATING:
			_input_state = InputState.LOCKED
	var unlock_input := func() -> void:
		if _input_state == InputState.LOCKED:
			_input_state = InputState.IDLE
	_state.setup({
		"get_tilemap": func() -> Variant: return tilemap,
		"is_waiting_for_player_input": func() -> bool: return _waiting_for_player_input,
		"is_input_blocked": func() -> bool: return _input_state == InputState.ANIMATING or _input_state == InputState.LOCKED,
		"lock_world_input": lock_input,
		"unlock_world_input": unlock_input,
		"get_camera": func() -> Variant: return camera,
		"add_child": func(node: Node) -> void: add_child(node),
	})
	_camera_handle = _state._camera_handle
	_state.phase_changed.connect(func(p: int) -> void: phase_changed.emit(p))
	_state.overlay_opened.connect(func(k: int) -> void: overlay_opened.emit(k))
	_state.overlay_closed.connect(func(k: int) -> void: overlay_closed.emit(k))
	_special_tiles = SpecialTileRegistry.new()
	_special_tiles.setup({
		"get_special_tiles_container": func() -> Node2D: return special_tiles_container,
		"get_obstacles_tilemap_layer": func() -> TileMapLayer: return obstacles_tilemap_layer,
		"get_tilemap": func() -> TileMapLayer: return tilemap,
		"get_parent_for_marker": func() -> Node: return self,
		"get_movement_manager": func() -> Node: return movement_manager,
		"get_teams": func() -> Array: return [],
	})
	_actors = ActorRegistry.new()
	_input = FreeRoamInputController.new()
	_input.setup({
		"can_accept_command": _can_accept_command,
		"get_hero": get_hero,
		"get_actors_at_cell": _get_actors_at_cell,
		"get_cell_at_screen": _get_cell_at_screen,
	})
	_input.actor_selected.connect(func(a): _on_actor_selected(a))
	_input.actor_deselected.connect(func(): _on_actor_deselected())
	_input.move_requested.connect(func(from_cell, to_cell): _on_move_requested(from_cell, to_cell))
	_input.interact_requested.connect(func(a, t): _on_actor_interact_requested(a, t))
	_end_flow.all_goals_met.connect(_on_all_goals_met)


func _ready() -> void:
	_dialogue = DialogueBridge.new()
	add_child(_dialogue)
	_dialogue.setup({
		"open_overlay": _open_overlay,
		"has_overlay": has_overlay,
		"get_level_node": func() -> Node: return self,
		"get_li_chun_portrait": func() -> Texture2D: return _LI_CHUN_PORTRAIT,
	})
	_status_bar_bridge = StatusBarBridge.new()
	add_child(_status_bar_bridge)
	_status_bar_bridge.setup({
		"get_status_bar": func() -> Node: return status_bar,
		"get_hero": func() -> Node2D: return get_hero(),
	})
	tilemap = _find_walkable_tilemap()
	if tilemap == null:
		push_error("No walkable tilemap found in level")
	elif movement_manager != null and movement_manager.movement_tilemaps.is_empty():
		movement_manager.movement_tilemaps.append(tilemap)
	# @export 引用在导出构建里可能为 null（AGENTS Pitfalls #2），运行时按名字回退查找
	if obstacles_tilemap_layer == null:
		obstacles_tilemap_layer = _find_obstacle_tilemap()
	_setup_special_tiles()
	if camera != null and camera is LevelCamera:
		camera.set_level_bounds(get_tilemap_bounds())
	_apply_tilemap_texture_filter()
	if hero != null:
		_update_status_bar_for_unit(hero, false)
	_on_level_ready()
	_begin_initial_briefing.call_deferred()


## 子类覆写：基类 _ready() 完成装配后调用，子类在此布置主角 / NPC / HUD。
func _on_level_ready() -> void:
	pass


# ─────────────────────────────────────────────
# 状态机委托
# ─────────────────────────────────────────────

func is_phase_ended() -> bool:
	return _state.is_phase_ended()


func has_overlay() -> bool:
	return _state.has_overlay()


func _set_phase(p: LevelPhase) -> void:
	_state._set_phase(p)


## 进入一个 overlay。若已有 overlay 则拒绝（互斥），node 由本方法 add_child 并挂关闭回调。
## closed_signal：关闭信号名（0 参或多参均可，实参会被忽略）。
## close_handler：可选自定义关闭 Callable，提供时替代默认关闭逻辑（需自行调用 _close_overlay）。
## 返回是否成功进入。
func _open_overlay(kind: ActiveOverlay, node: Node, closed_signal: StringName = &"closed", close_handler: Callable = Callable()) -> bool:
	return _state._open_overlay(kind, node, closed_signal, close_handler)


## 关闭当前 overlay。仅当 kind 匹配当前 active 时生效（防止竞态关错）。
func _close_overlay(kind: ActiveOverlay) -> void:
	_state._close_overlay(kind)


## 是否允许接收玩家命令。双轴状态机 + 既有子状态的联合闸门。
func _can_accept_command() -> bool:
	return _state._can_accept_command()


## 进入"流程锁"。配对调用 _end_input_lock。支持嵌套（计数器）。
## 用于对话 / 输入面板等需要暂时屏蔽世界输入的场景。
func _begin_input_lock() -> void:
	_state._begin_input_lock()
	if _input != null:
		_input.set_state(FreeRoamInputController.S.LOCKED)


func _end_input_lock() -> void:
	_state._end_input_lock()
	if _input != null and _input.get_state() == FreeRoamInputController.S.LOCKED:
		_input.set_state(FreeRoamInputController.S.IDLE)


# ─────────────────────────────────────────────
# 对话 / TTS（委托 DialogueBridge）
# ─────────────────────────────────────────────

## 播放一段对话。阻塞直到对话结束。用法：await play_dialogue([line1, line2])
## auto_dismiss=true 时走"打字机结束后自动飘过"，用于单位闲聊（chatter）。
func play_dialogue(lines: Array[DialogueLine], auto_dismiss: bool = false, dismiss_delay: float = 2.5) -> void:
	await _dialogue.play_dialogue(lines, auto_dismiss, dismiss_delay)


## 李春教程对话单行构造：自动带头像、左侧显示，并按当前关卡匹配预生成 TTS。
func _lc_line(text: String, can_skip: bool = true) -> DialogueLine:
	return _dialogue._lc_line(text, can_skip)


## 单行 chatter 对话的便捷入口。返回 true 表示已播完；false 表示被拒绝（已有 overlay）。
func play_chatter_dialogue(unit: Node, text: String, dismiss_delay: float = 2.5) -> bool:
	return await _dialogue.play_chatter_dialogue(unit, text, dismiss_delay)


## 多行 chatter 对话（邻接对话的双人场景用）。
## voice_handle: 可选 TTS 句柄（鸭子接口：is_streaming() / streaming_done 信号）。
## 返回 `{"ok": bool, "was_skipped": bool}`。
func play_chatter_lines(lines: Array[DialogueLine], dismiss_delay: float = 2.0, voice_handle: Node = null) -> Dictionary:
	return await _dialogue.play_chatter_lines(lines, dismiss_delay, voice_handle)


# ─────────────────────────────────────────────
# 状态栏（委托 StatusBarBridge）
# ─────────────────────────────────────────────

## 更新状态栏显示指定单位的信息。
func _update_status_bar_for_unit(unit: Node2D, is_active: bool = false) -> void:
	_status_bar_bridge.show_unit_for(unit, is_active)


## 状态栏回退显示主角。
func _reset_status_bar() -> void:
	_status_bar_bridge.reset_to_hero()


# ─────────────────────────────────────────────
# 特殊地块（委托 SpecialTileRegistry）
# ─────────────────────────────────────────────

func _get_special_tile_at(cell: Vector2i) -> SpecialTile:
	return _special_tiles.get_at(cell)


## 在 _on_level_ready() 中程序化注册一个 SpecialTile（跳过 _setup_special_tiles 自动扫描）。
func register_special_tile(tile: SpecialTile, cell: Vector2i) -> void:
	_special_tiles.register(tile, cell)


## 从统一派发表解除一个运行时特殊地格，避免 queue_free 后字典保留失效实例。
func unregister_special_tile(tile: SpecialTile, cell: Vector2i) -> void:
	_special_tiles.unregister(tile, cell)


## 在指定地块上方挂一个统一的脉动强调标记。详见 SpecialTileRegistry.spawn_pulsing_marker。
func spawn_tile_pulsing_marker(
		cell: Vector2i,
		halo_color: Color,
		label_text: String = "",
		local_offset: Vector2 = Vector2.ZERO,
		node_name: String = "",
		tile_z_index: int = 1) -> Marker2D:
	return _special_tiles.spawn_pulsing_marker(
			cell, halo_color, label_text, local_offset, node_name, tile_z_index)


func _setup_special_tiles() -> void:
	_special_tiles.scan_from_container()


# ─────────────────────────────────────────────
# 单位生成
# ─────────────────────────────────────────────

## 运行时生成一个单位（简化版）：只加到场景 + set_cell，不走 TeamData / faction / 无限行动力。
## 自动注册进 ActorRegistry（unit_data.unit_id / unit.name 双 key）。
## 注意：不自动配 CombatStats（保守方案）——子类显式调 setup_free_roam_unit 或自行覆写，
## 避免自动默认值覆盖子类定制数值（如 bridge_tour 的 setup_unit_stats）。
func spawn_unit(unit_data: UnitData, cell: Vector2i, team_index: int, visual: PackedScene = null) -> Unit:
	var UnitScene := preload("res://scenes/unit/unit.tscn")
	var unit: Unit = UnitScene.instantiate()
	unit.unit_data = unit_data
	if visual != null:
		unit.visual_scene = visual
	unit.team_index = team_index
	var unit_parent: Node = obstacles_tilemap_layer
	if unit_parent == null:
		unit_parent = _find_obstacle_tilemap()
	if unit_parent == null:
		push_warning("obstacles_tilemap_layer is not set; spawning unit under level node")
		unit_parent = self
	unit_parent.add_child(unit)
	unit.movement_manager = movement_manager
	unit.set_cell(cell, tilemap)
	# 特殊地格 _on_unit_arrive 依赖 move_finished；本栈无 teams 名单，出生时直连
	unit.move_finished.connect(_special_tiles.on_unit_move_finished.bind(unit))
	_actors.register(unit, unit_data.unit_id if unit_data != null else "", String(unit.name))
	return unit


## 为自由移动单位配最小 CombatStats（无攻、满血）。
## **AP 概念已删除**（点地即达）；回合 / AI / 技能结算 / 元素 / 成长 / prebattle 全部不存在。
## 自由移动关卡无战斗，但 Unit 内部与外部约定仍读 combat_stats（如 is_alive / unit_name）。
## 决策（Task 2.5）：不引入 GridActor 新基类，沿用 Unit + 最小 CombatStats——
## Unit 已有 move_along_path / set_cell / move_finished / refresh_overhead_bars，
## 换基类需全量重实现，得不偿失；空 CombatStats 足够满足 bridge_tour 等处的 is_alive() 读取。
## 参数：
##   unit: Unit
##   display_name: String   — 显示名（CombatStats.unit_name）
##   max_hp: int = 100
##   move_cost: int = 6    — 保留参数签名，AP 已删除，此值不影响移动
func setup_free_roam_unit(unit: Unit, display_name: String, max_hp: int = 100, move_cost: int = 6) -> void:
	if unit == null or unit.combat_stats == null:
		return
	var cs := unit.combat_stats
	cs.unit_name = display_name
	cs.max_hp = max_hp
	cs.current_hp = max_hp
	cs.move_cost_per_tile = move_cost


# ─────────────────────────────────────────────
# 自由移动虚方法契约
# ─────────────────────────────────────────────

## 子类覆写：返回 true 表示这是"自由移动 / 实时"关卡（本基类恒为 true，与 BaseLevel hook 对齐）。
func is_free_roam_level() -> bool:
	return true


## 返回主角。优先 ActorRegistry.get_hero()，未设置时回落 hero 字段（静态摆放的兼容路径）。
func get_hero() -> Node2D:
	var registered := _actors.get_hero()
	return registered if registered != null else hero


## 按 unit_id 查 actor（委托 ActorRegistry）。
func get_actor_by_id(id: String) -> Node2D:
	return _actors.get_by_id(id)


## 按节点名查 actor（委托 ActorRegistry）。
func get_actor_by_node_name(node_name: String) -> Node2D:
	return _actors.get_by_node_name(node_name)


## 所有 NPC（排除 hero）。委托 ActorRegistry。
func get_npcs() -> Array:
	return _actors.get_npcs()


## actor 被选中时：显示可达范围预览。子类覆写时调用 super 保留此行为。
func _on_actor_selected(actor) -> void:
	var u := actor as Unit
	if u == null or move_overlay == null or tilemap == null:
		return
	move_overlay.show_range(tilemap, movement_manager, u.cell, u.movement_points)


## actor 取消选中时：清可达范围预览。子类覆写时调用 super 保留此行为。
func _on_actor_deselected() -> void:
	if move_overlay != null:
		move_overlay.clear_range()


## 子类覆写：actor 完成一次移动时。
func _on_actor_move_completed(_actor) -> void:
	pass


## 子类覆写：actor 请求与 target 交互时。
func _on_actor_interact_requested(_actor, _target) -> void:
	pass


## 输入状态机请求移动（from_cell → to_cell）。用 MoveOverlay 计算路径并执行 Unit.move_along_path；
## 移动完成后通知 _on_actor_move_completed、状态回 IDLE、清预览。AP 概念已删除，点地即达。
func _on_move_requested(_from_cell: Vector2i, to_cell: Vector2i) -> void:
	var h := get_hero() as Unit
	if h == null or move_overlay == null or tilemap == null:
		if _input != null:
			_input.set_state(FreeRoamInputController.S.IDLE)
		if move_overlay != null:
			move_overlay.clear_range()
		return
	var path: Array[Vector2i] = move_overlay.get_path_to_cell(to_cell)
	if path.is_empty():
		_input.set_state(FreeRoamInputController.S.IDLE)
		move_overlay.clear_range()
		return
	_input.set_state(FreeRoamInputController.S.ANIMATING)
	h.move_along_path(path, tilemap)
	await h.move_finished
	if is_phase_ended():
		return
	_on_actor_move_completed(h)
	_input.set_state(FreeRoamInputController.S.IDLE)
	move_overlay.clear_range()


# ─────────────────────────────────────────────
# 输入辅助（FreeRoamInputController 注入用）
# ─────────────────────────────────────────────

## 世界坐标 → 格子坐标（考虑相机与 tilemap 的变换）。
func _get_cell_at_screen(screen_pos: Vector2) -> Vector2i:
	if tilemap == null:
		return Vector2i.ZERO
	var world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	return tilemap.local_to_map(tilemap.to_local(world))


## 指定格子上的所有 actor（ActorRegistry 查询）。
## 未走 spawn_unit / register 的静态主角（hero 字段回落路径）同样参与点选，保持行为等价。
func _get_actors_at_cell(cell: Vector2i) -> Array:
	var out: Array = _actors.get_at_cell(cell)
	if is_instance_valid(hero) and not _actors.has_actor(hero) and "cell" in hero and hero.cell == cell:
		out.append(hero)
	return out


## 转发到 FreeRoamInputController。
func _unhandled_input(event: InputEvent) -> void:
	if _input != null:
		_input.handle_input(event)


## 子类覆写：返回本关目标文本。
## 格式：{ "victory": Array[String], "defeat": Array[String], "details": Array[String] 可选 }
func get_objectives_text() -> Dictionary:
	return { "victory": [], "defeat": [] }


## 子类覆写：检查是否满足胜利条件。
## 约定（与 bridge_tour 一致）：可用 get_end_flow() 的目标计数，也可自行判据。
func check_victory() -> bool:
	return _end_flow.is_all_met()


## 子类覆写：检查是否满足失败条件。返回失败原因（"" 表示未失败）。
## 签名统一为 -> String（与 bridge_tour 的 check_defeat 一致），调用点用非空判定。
func check_defeat() -> String:
	return ""


## 目标 / 失败判据统一出口。子类每次进度推进后调（或走 get_end_flow().increment 自动触发）。
## 幂等：complete_level / defeat_level 自身有 is_phase_ended 守卫。
func check_end_conditions() -> void:
	if is_phase_ended():
		return
	var defeat_reason := check_defeat()
	if not defeat_reason.is_empty():
		defeat_level(defeat_reason)
		return
	if check_victory():
		complete_level()


## 目标计数驱动的通关流。子类 add_goal / increment 用（Task 2.6）。
func get_end_flow() -> SocialLevelEndFlow:
	return _end_flow


## all_goals_met 回调：目标全达标 → 通关。子类可覆写以插入横幅 / 延时等收尾。
func _on_all_goals_met() -> void:
	complete_level()


## 关卡胜利收尾。幂等。
func complete_level() -> void:
	if is_phase_ended():
		return
	_set_phase(LevelPhase.ENDED)
	UiSounds.play_victory()
	var level := GameState.selected_level
	Progress.complete_level(level)
	_continue_after_level_completion(level)


func _continue_after_level_completion(level: String) -> void:
	if GameState.has_cutscene(level, "post"):
		GameState.pending_cutscene_pages = GameState.get_cutscene_pages(level, "post")
		GameState.pending_next_scene = "res://scenes/menu/main_menu.tscn"
		GameState.transition_to_scene("res://scenes/cutscene/cutscene_scene.tscn")
	else:
		GameState.transition_to_scene("res://scenes/menu/main_menu.tscn")


## 关卡失败收尾。幂等。
func defeat_level(reason: String = "任务失败") -> void:
	if is_phase_ended():
		return
	_set_phase(LevelPhase.ENDED)
	UiSounds.play_defeat()
	var panel: Node = preload("res://scenes/ui/defeat_panel.tscn").instantiate()
	panel.defeat_reason = reason
	panel.retry_pressed.connect(_on_defeat_retry)
	panel.main_menu_pressed.connect(_on_defeat_main_menu)
	if not _open_overlay(ActiveOverlay.DEFEAT_PANEL, panel):
		panel.queue_free()


func _on_defeat_retry() -> void:
	get_tree().reload_current_scene()


func _on_defeat_main_menu() -> void:
	GameState.transition_to_scene("res://scenes/menu/main_menu.tscn")


# ─────────────────────────────────────────────
# BRIEFING → PLAYING 生命周期
# ─────────────────────────────────────────────

## BRIEFING 入口：弹出初始目标面板；若无目标文本则直接进入 PLAYING。
## 闸门（_can_accept_command）要求 phase == PLAYING，由这里统一开闸，
## 子类不必再手动设 _waiting_for_player_input（消除自由移动隐式契约）。
func _begin_initial_briefing() -> void:
	var obj := get_objectives_text()
	var victory: Array = obj.get("victory", [])
	var defeat: Array = obj.get("defeat", [])
	var details: Array = obj.get("details", [])
	if victory.is_empty() and defeat.is_empty() and details.is_empty():
		_set_phase(LevelPhase.PLAYING)
		return
	var panel: ObjectivesPanel = ObjectivesPanelScene.instantiate()
	panel.victory_lines = victory
	panel.defeat_lines = defeat
	panel.detail_lines = details
	if _open_overlay(ActiveOverlay.BRIEFING_OBJECTIVES, panel):
		panel.closed.connect(_on_initial_briefing_done, CONNECT_ONE_SHOT)
	else:
		panel.queue_free()
		_on_initial_briefing_done()


func _on_initial_briefing_done() -> void:
	_set_phase(LevelPhase.PLAYING)


# ─────────────────────────────────────────────
# 场景辅助
# ─────────────────────────────────────────────

func _apply_tilemap_texture_filter() -> void:
	if tilemap_container == null:
		return
	tilemap_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for node: Node in tilemap_container.find_children("*", "TileMapLayer", true):
		if node is TileMapLayer:
			node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _find_walkable_tilemap() -> TileMapLayer:
	if tilemap_container == null:
		return null
	for layer_name in WALKABLE_LAYER_NAMES:
		var node: Node = tilemap_container.find_child(layer_name, true, false)
		if node is TileMapLayer:
			return node
	for child in tilemap_container.get_children():
		if child is TileMapLayer:
			return child
	return null


## 导出构建里 @export obstacles_tilemap_layer 可能为 null（AGENTS Pitfalls #2），
## 按节点名关键字模糊回退查找障碍层。用前缀匹配而非包含匹配，避免误命中
## "unvisiable obstacle"（modulate.a == 0 的隐形碰撞层，挂上去单位会被隐掉）。
func _find_obstacle_tilemap() -> TileMapLayer:
	if tilemap_container == null:
		return null
	for node: Node in tilemap_container.find_children("*", "TileMapLayer", true, false):
		var lname := String(node.name).to_lower()
		for keyword in OBSTACLE_LAYER_KEYWORDS:
			if lname.begins_with(keyword.to_lower()):
				return node as TileMapLayer
	return null


func get_tilemap_bounds() -> Rect2:
	var has_bounds := false
	var res_bounds := Rect2()
	if tilemap_container == null:
		return res_bounds
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
