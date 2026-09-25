class_name BaseLevel
extends Node2D

const LEVEL_BGM_BY_LEVEL := {
	"关卡1-1": "res://assets/audio/music/1：踏勘洨河(Charting_the_Hidden_Shore).mp3",
	"关卡1-2": "res://assets/audio/music/2：弧拱定式(Geometry_of_the_Arch).mp3",
	"关卡1-3": "res://assets/audio/music/3：二十八券(The_Twenty_Eighth_Arch).mp3",
	"关卡1-4": "res://assets/audio/music/4：敞肩试汛(Against_the_Angry_Tide).mp3",
}
const DEBUG_INFINITE_AP_BUDGET := 9999
## Base class for all battle levels.
const _LI_CHUN_PORTRAIT := preload("res://assets/face/li_chun.png")
## Inherited scenes should add TileMapLayers under the TileMaps node,
## and place unit nodes under the Entities node.
##
## 队伍与回合机制：
##   - 子关卡覆盖 get_teams_config() 返回队伍配置。
##   - 角色节点挂载在场景中，颜色与初始格子通过 @export 在编辑器中设置。
##   - 若不覆盖 get_teams_config()，则沿用旧的单玩家行为。

## 敌方名称 → Visual 场景映射表。spawn_unit 会根据 unit_data.unit_name 自动应用外观。
## （真源在 UnitFactory，此处保留别名。）
const MONSTER_VISUALS: Dictionary = UnitFactory.MONSTER_VISUALS

## 友方名称 → Visual 场景映射表。spawn_unit 在 MONSTER_VISUALS 未命中时回落到这里。
## （真源在 UnitFactory，此处保留别名。）
const HUMAN_VISUALS: Dictionary = UnitFactory.HUMAN_VISUALS

@export var obstacles_tilemap_layer: TileMapLayer  # 障碍物所在的层，必须在编辑器中指定
## AI 回合中每个敌人一轮内最多走几步（每步 = 向相邻格移动一次）。
## 子关卡可在 _on_level_ready 里覆盖，例如 `ai_max_move_steps = 4`。
@export var ai_max_move_steps: int = 1

# ─────────────────────────────────────────────
# 关卡事件信号（供关卡脚本 connect）
# ─────────────────────────────────────────────

## 某单位倒下（HP 降到 0）。每个单位只会触发一次。
signal unit_died(unit: Unit)

## 某单位 HP 变化（受伤/治疗/DoT/休息恢复）。可用于 HP 阈值监控。
signal unit_hp_changed(unit: Unit, old_hp: int, new_hp: int)

## 大回合开始（所有队伍各打完一次为一个大回合）。round_number 在 emit 前已递增。
signal round_started(round_number: int)

## 大回合结束：所有队伍都走完一轮，round_number 即将递增前 emit。
## 参数是"刚刚结束的这个大回合号"。
signal round_ended(round_number: int)

## 队伍小回合开始（team_index 从 0 起）。
signal team_turn_started(team_index: int)

## 队伍小回合结束。切到下一队伍之前 emit，参数是"刚结束的这个队伍号"。
signal team_turn_ended(team_index: int)

## 某单位获得一个技能（通过 grant_skill 添加）。
signal unit_gained_skill(unit: Unit, skill: SkillData)

## 某单位失去一个技能（通过 revoke_skill 移除）。
signal unit_lost_skill(unit: Unit, skill: SkillData)

## 技能成功执行后发射。用于关卡响应技能副作用（如勘测点完成）。
signal skill_executed(caster: Unit, skill: SkillData, cast_cell: Vector2i)


@onready var tilemap_container: Node2D = $TileMaps
@onready var units_container: Node2D = $Entities/Units
@onready var special_tiles_container: Node2D = $SpecialTiles
@onready var move_overlay: Node2D = $MoveOverlay
@onready var hover_overlay: Node2D = $HoverOverlay
@onready var movement_manager: Node = $MovementManager
@onready var camera: Camera2D = $Camera2D
@onready var gui: CanvasLayer = $GUI
@onready var status_bar: HBoxContainer = $StatusBarScene/PanelContainer/MarginContainer/StatusBar
@onready var win_button: Button = $GUI/WinButton
@onready var infinite_ap_button_label: Label = $GUI/InfiniteApButtonLabel
@onready var infinite_ap_button_button: CheckButton = $GUI/InfiniteApButtonLabel/InfiniteApButtonButton

const SettingsPanelScene := preload("res://scenes/ui/settings_panel.tscn")
const ObjectivesPanelScene := preload("res://scenes/ui/objectives_panel.tscn")
const ProgressPanelScene := preload("res://scenes/ui/progress_panel.tscn")
const GrowthChoicePanelScript := preload("res://scenes/ui/growth_choice_panel.gd")
const ChatterSchedulerScript := preload("res://scripts/llm/chatter_scheduler.gd")
const TutorialPanelScene := preload("res://scenes/ui/tutorial_panel.tscn")

var tilemap: TileMapLayer
## 化势提示 UI（运行时创建，挂在 GUI 层）。
var _phase_notification: PhaseNotification = null
## 兼容旧版：指向第一个玩家控制队伍的第一个单位（李春）。
var hero: Node2D
var unit_selected := false
## debug AI 闲聊忙锁。代理属性：真源在 LLMChatterBridge，保持旧字段名可读写。
var _ai_busy: bool:
	get:
		return _get_chatter_bridge().ai_busy
	set(value):
		_get_chatter_bridge().ai_busy = value
## 单位闲聊调度器（LLM 驱动）。BRIEFING 之后的战斗中监听 team_turn_ended / round_ended 触发对话。
var _chatter_scheduler: Node = null
## 对话桥接组件（Shared Kernel）。BaseLevel 通过同名委托方法转发调用。
var _dialogue: DialogueBridge = null
## 状态栏桥接组件（Shared Kernel）。BaseLevel 通过同名委托方法转发调用。
var _status_bar_bridge: StatusBarBridge = null
var _infinite_ally_actions_enabled := false

## 输入状态机。LOCKED 表示被外部流程显式锁定（例如自由移动关卡的对话流），与 ANIMATING（基类演出）正交。
## 枚举真源在 InputController，此处保留旧名供全文件注解使用。
const InputState = InputController.InputState

## 输入状态机组件（Tactics Stack）。输入状态机 / hover 反馈 / 移动与技能瞄准的执行者。
var _input_controller: InputController = null

## 代理属性：真源在 InputController，保持旧字段名可读写。
var _input_state: InputState:
	get:
		return _get_input_controller()._input_state
	set(value):
		_get_input_controller()._input_state = value

# ─────────────────────────────────────────────
# 关卡状态机（双轴：LevelPhase × ActiveOverlay）
# ─────────────────────────────────────────────

## 关卡生命周期粗粒度时间线，单向转换 BRIEFING → PLAYING → ENDED。
const LevelPhase = LevelStateMachine.LevelPhase

## 当前独占前景的瞬态 UI。同时只能有一个非 NONE。统一替代原先 6 个独立 bool。
const ActiveOverlay = LevelStateMachine.ActiveOverlay

## 双轴状态机组件（RefCounted）。状态真源，BaseLevel 通过属性/方法委托。
var _state: LevelStateMachine = null

## 代理属性：保持旧字段名可读。写入已全部走 _open_overlay / _close_overlay，setter 不再需要。
var _level_phase: int:
	get:
		return _state.level_phase
	set(value):
		_state.level_phase = value

var _active_overlay: int:
	get:
		return _state.active_overlay

## 关卡主阶段切换（BRIEFING → PLAYING → ENDED）。子关卡订阅启动教程、开场演出等。
signal phase_changed(new_phase: int)
## overlay 打开/关闭。用于观察者，不负责互斥（互斥由 _open_overlay 守护）。
signal overlay_opened(kind: int)
signal overlay_closed(kind: int)

## selected_unit 赋值或清空（含 _go_idle / _confirm_idle / _confirm_move）。unit 为 null 表示取消选中。
signal selection_changed(unit: Node2D)
## 玩家控制的单位完成一次移动（AP 扣除后、_on_unit_moved 钩子之后发射）。
signal unit_move_completed(unit: Unit)


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
	_state.phase_changed.connect(func(p: int) -> void: phase_changed.emit(p))
	_state.overlay_opened.connect(func(k: int) -> void: overlay_opened.emit(k))
	_state.overlay_closed.connect(func(k: int) -> void: overlay_closed.emit(k))
	_special_tile_registry = SpecialTileRegistry.new()
	_special_tile_registry.setup({
		"get_special_tiles_container": func() -> Node2D: return special_tiles_container,
		"get_obstacles_tilemap_layer": func() -> TileMapLayer: return obstacles_tilemap_layer,
		"get_tilemap": func() -> TileMapLayer: return tilemap,
		"get_parent_for_marker": func() -> Node: return self,
		"get_movement_manager": func() -> Node: return movement_manager,
		"get_teams": func() -> Array: return teams,
	})


func is_phase_playing() -> bool:
	return _state.is_phase_playing()


func is_phase_ended() -> bool:
	return _state.is_phase_ended()


func has_overlay() -> bool:
	return _state.has_overlay()


## 薄壳转发至 TutorialRunner.set_tutorial_onboarding_active（保留旧调用点零改动）。
func set_tutorial_onboarding_active(active: bool) -> void:
	_get_tutorial_runner().set_tutorial_onboarding_active(active)


## 薄壳转发至 TutorialRunner.is_tutorial_onboarding_active（保留旧调用点零改动）。
func is_tutorial_onboarding_active() -> bool:
	return _get_tutorial_runner().is_tutorial_onboarding_active()


## 进入一个 overlay。若已有 overlay 则拒绝（互斥），node 由本方法 add_child 并挂关闭回调。
## closed_signal：关闭信号名（0 参或多参均可，实参会被忽略）。
## close_handler：可选自定义关闭 Callable，提供时替代默认关闭逻辑（需自行调用 _close_overlay）。
## 返回是否成功进入。
func _open_overlay(kind: ActiveOverlay, node: Node, closed_signal: StringName = &"closed", close_handler: Callable = Callable()) -> bool:
	return _state._open_overlay(kind, node, closed_signal, close_handler)


## overlay 关闭信号的通用接收器：吞掉任意 arity 的信号实参，只做 _close_overlay。
## bind(kind) 预填 kind 后剩余形参全带默认值，兼容 0–4 参关闭信号。
func _on_overlay_closed_signal(kind: ActiveOverlay, _a = null, _b = null, _c = null, _d = null) -> void:
	_state._close_overlay(kind)


## 关闭当前 overlay。仅当 kind 匹配当前 active 时生效（防止竞态关错）。
func _close_overlay(kind: ActiveOverlay) -> void:
	_state._close_overlay(kind)


## 薄壳转发至 TutorialRunner.ask_tutorial_replay（保留旧调用点零改动）。
func _ask_tutorial_replay() -> bool:
	return await _get_tutorial_runner().ask_tutorial_replay()


func _set_phase(p: LevelPhase) -> void:
	_state._set_phase(p)
## 当前选中的技能（TARGETING_SKILL 状态时有效）。代理属性：真源在 InputController。
var _current_skill: SkillData:
	get:
		return _get_input_controller()._current_skill
	set(value):
		_get_input_controller()._current_skill = value
## 技能范围 Overlay（运行时动态创建）。代理属性：真源在 InputController。
var _skill_targeting: Node2D:
	get:
		return _get_input_controller()._skill_targeting
	set(value):
		_get_input_controller()._skill_targeting = value
## 选中单位脚下的呼吸菱形指示器。
var _selection_indicator: Line2D
## 按钮默认 modulate，切换高亮状态时用来还原（TurnSystem 高亮时读取）。
var _end_turn_button_default_modulate: Color = Color.WHITE

## Names to search for the walkable tilemap layer
## （真源在 SceneBootstrap，此处保留别名。）
const WALKABLE_LAYER_NAMES: Array[String] = SceneBootstrap.WALKABLE_LAYER_NAMES

## 障碍层名字关键字（大小写不敏感，前缀匹配）。导出构建里 @export 引用可能丢失
## （AGENTS Pitfalls #2），_find_obstacle_tilemap 用它们做运行时回退查找。
## "railing" 对应 level1-4 / 验桥日的 "railing z=7"（那两关用栏杆层当 Y-Sort 父层）。
## （真源在 SceneBootstrap，此处保留别名。）
const OBSTACLE_LAYER_KEYWORDS: Array[String] = SceneBootstrap.OBSTACLE_LAYER_KEYWORDS

# ─────────────────────────────────────────────
# 队伍 / 回合系统
# ─────────────────────────────────────────────

## 单个队伍的运行时数据（真源在 TurnSystem，此处保留旧类型名供全文件注解使用）。
const TeamData = TurnSystem.TeamData

## 回合系统组件（Tactics Stack）。回合流转 / 结束回合双击 / 回合成长问询的执行者。
var _turn_system: TurnSystem = null

## AI 回合执行组件（Tactics Stack）。AI 决策循环 / AI 技能执行 / 行动预算查询的执行者。
var _ai_runner: AITurnRunner = null

## 技能施放与战斗反馈组件（Tactics Stack）。技能目标确认执行 / 战斗反馈 UI / 直接伤害上报的执行者。
var _skill_cast_controller: SkillCastController = null

## UI 桥接组件（Tactics Stack）。状态栏联动 / 按钮回调 / debug UI / BGM / 技能 targeting 管理的执行者。
var _ui_bridge: LevelUIBridge = null

## 目标跟踪组件（Tactics Stack）。胜负条件检查分发（先 defeat 后 victory）的执行者。
var _objectives_tracker: ObjectivesTracker = null

## 关卡胜负流程组件（Tactics Stack）。中场剧情 / 通关结算 / 失败面板的执行者。
var _level_flow: LevelFlow = null

## 单位工厂 + 队伍编成组件（Tactics Stack）。单位生成 / 技能授予收回 / 战斗数值覆写 / 队伍编成的执行者。
var _unit_factory: UnitFactory = null

## 场景引导组件（Tactics Stack）。TileMapLayer 查找 / 实体重挂 / 地图边界 / 单位枚举的执行者。
var _scene_bootstrap: SceneBootstrap = null

## 查询接口组件（Tactics Stack）。网格占用 / 占位格子 / 行动预算 / MCP 查询与操作 / 单位查询的执行者。
var _query_api: LevelQueryAPI = null

## debug AI 闲聊桥接组件（Tactics Stack）。debug 闲聊请求 / LLM 客户端与忙锁状态的执行者。
var _chatter_bridge: LLMChatterBridge = null

var teams: Array = []  # Array[TeamData]
var current_team_index: int = -1
## 大回合计数（所有队伍各轮一次为一个大回合）。第一大回合 = 1。
var round_number: int = 1
## 当前选中的单位（玩家回合时有效）。
var selected_unit: Node2D = null
## 当前鼠标 hover 上的 unit（含 boss extra_target_cells 命中），用于驱动单位高亮叠加。
## 代理属性：真源在 InputController。
var _hovered_unit: Unit:
	get:
		return _get_input_controller()._hovered_unit
	set(value):
		_get_input_controller()._hovered_unit = value
## 当前是否等待玩家输入。代理属性：真源在 InputController（TurnSystem 会直写本字段）。
var _waiting_for_player_input: bool:
	get:
		return _get_input_controller()._waiting_for_player_input
	set(value):
		_get_input_controller()._waiting_for_player_input = value
## 教程运行器组件（Shared Kernel）。新手引导开关 / 重玩问询 / 李春教程对话构造的执行者。
var _tutorial_runner: TutorialRunner = null
## 关卡脚本可在新手引导等流程中置为 true，暂停所有战场闲聊触发。代理属性：真源在 TutorialRunner。
var tutorial_onboarding_active: bool:
	get:
		return _get_tutorial_runner().tutorial_onboarding_active
	set(value):
		_get_tutorial_runner().tutorial_onboarding_active = value

## 特殊地块注册表组件（RefCounted）。注册/查询/标记工厂/enter-leave 派发。
var _special_tile_registry: SpecialTileRegistry = null

## 代理属性：保持旧字段名可读（level1-1.gd 直接 .get() 查询）。
var _special_tile_map: Dictionary:
	get:
		return _special_tile_registry.get_map() if _special_tile_registry else {}

@onready var _turn_label: Label = $GUI/TurnLabel
@onready var _round_label: Label = $GUI/RoundLabel
@onready var _end_turn_button: Button = $GUI/EndTurnButton


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
		"get_hero": func() -> Node2D: return hero,
	})
	Settings.settings_changed.connect(_refresh_debug_ui, CONNECT_REFERENCE_COUNTED)
	Settings.difficulty_changed.connect(_on_difficulty_changed)
	if infinite_ap_button_button and not infinite_ap_button_button.toggled.is_connected(_on_infinite_ap_button_toggled):
		infinite_ap_button_button.toggled.connect(_on_infinite_ap_button_toggled)
	_refresh_debug_ui()
	_play_level_bgm()
	tilemap = _find_walkable_tilemap()
	if tilemap == null:
		push_error("No walkable tilemap found in level")
		return
	if _end_turn_button:
		_end_turn_button_default_modulate = _end_turn_button.modulate
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
	_setup_skill_targeting()
	_setup_phase_notification()
	_setup_selection_indicator()
	if camera and camera is LevelCamera:
		(camera as LevelCamera).set_level_bounds(get_tilemap_bounds())
	_on_level_ready()
	_apply_tilemap_texture_filter()
	# 连接倒下处理
	unit_died.connect(_on_unit_died)
	# 胜负条件检查
	unit_died.connect(_check_win_lose)
	round_started.connect(func(_r): _check_win_lose())
	# 回合计数器
	round_started.connect(_update_round_label)
	_update_round_label(round_number)
	# 每个大回合开始（玩家→友方→敌人 跑完一圈后）自动触发一次 AI
	round_started.connect(_on_round_started_ai_call)
	# LLM 单位闲聊：ChatterScheduler 内部订阅 skill_executed / team_turn_ended / round_ended
	_chatter_scheduler = ChatterSchedulerScript.new()
	add_child(_chatter_scheduler)
	_chatter_scheduler.setup(self)
	# 连接状态栏技能按钮信号
	if status_bar and status_bar.has_signal("skill_button_pressed"):
		status_bar.skill_button_pressed.connect(_on_skill_button_pressed)
	if status_bar and status_bar.has_signal("move_button_pressed"):
		status_bar.move_button_pressed.connect(_on_move_button_pressed)
	# 初始显示主角信息
	if hero:
		_update_status_bar_for_unit(hero, false)
	# 进入关卡：弹出初始目标面板（BRIEFING 阶段），关闭后才启动回合系统进入 PLAYING
	_begin_initial_briefing.call_deferred()


## BRIEFING 入口：弹出初始目标面板；若无目标文本则直接进入 PLAYING。
func _begin_initial_briefing() -> void:
	var obj := get_objectives_text()
	var has_objectives: bool = not obj["victory"].is_empty() or not obj["defeat"].is_empty() or not obj.get("details", []).is_empty()
	if not has_objectives:
		_on_initial_briefing_done()
		return
	var panel: ObjectivesPanel = ObjectivesPanelScene.instantiate()
	panel.victory_lines = obj["victory"]
	panel.defeat_lines = obj["defeat"]
	panel.detail_lines = obj.get("details", [])
	if _open_overlay(ActiveOverlay.BRIEFING_OBJECTIVES, panel):
		panel.closed.connect(_on_initial_briefing_done, CONNECT_ONE_SHOT)
	else:
		panel.queue_free()
		_on_initial_briefing_done()


## 初始目标面板关闭：BRIEFING → PLAYING，启动回合系统。
func _on_initial_briefing_done() -> void:
	if _level_phase != LevelPhase.BRIEFING:
		return
	_set_phase(LevelPhase.PLAYING)
	_init_turn_system()


## 薄壳转发至 LevelUIBridge.play_level_bgm。
func _play_level_bgm() -> void:
	_get_ui_bridge().play_level_bgm()


## 薄壳转发至 LevelUIBridge.refresh_debug_ui（Settings.settings_changed 信号目标）。
func _refresh_debug_ui() -> void:
	_get_ui_bridge().refresh_debug_ui()


## 薄壳转发至 LevelUIBridge.on_infinite_ap_button_toggled（按钮 toggled 信号目标）。
func _on_infinite_ap_button_toggled(enabled: bool) -> void:
	_get_ui_bridge().on_infinite_ap_button_toggled(enabled)


## 薄壳转发至 LevelUIBridge.set_infinite_ally_actions_enabled。
func _set_infinite_ally_actions_enabled(enabled: bool) -> void:
	_get_ui_bridge().set_infinite_ally_actions_enabled(enabled)


## 薄壳转发至 LevelUIBridge.apply_infinite_ally_actions_to_unit。
func _apply_infinite_ally_actions_to_unit(unit: Unit) -> void:
	_get_ui_bridge().apply_infinite_ally_actions_to_unit(unit)


func _process(_delta: float) -> void:
	# 选中指示器跟随
	if _selection_indicator:
		if selected_unit != null and is_instance_valid(selected_unit):
			_selection_indicator.global_position = selected_unit.global_position
			_selection_indicator.visible = true
		else:
			_selection_indicator.visible = false


## 薄壳转发至 LevelUIBridge.setup_selection_indicator。
func _setup_selection_indicator() -> void:
	_get_ui_bridge().setup_selection_indicator()


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


## 返回本关可用的回合成长选项。默认无。
func get_round_growth_options() -> Array[Dictionary]:
	return []


## 应用一个回合成长选项。子关卡按 option_id 自行实现。
func apply_round_growth_option(_option_id: String) -> void:
	pass


## 返回本关胜利后的结算成长选项。默认无。
func get_post_level_growth_options() -> Array[Dictionary]:
	return []


## 在基类 _ready 完成后调用，子关卡在此做额外初始化。
func _on_level_ready() -> void:
	pass


## 任意单位移动完毕后调用（兼容旧版钩子）。
func _on_unit_moved() -> void:
	pass


## 子类覆写：返回波次配置。格式：{ round_number: [WaveEntry, ...] }
## WaveEntry = { "unit_data": UnitData, "cell": Vector2i, "team_index": int,
##               "skills": Array[SkillData]（可选）}
func get_wave_config() -> Dictionary:
	return {}


## 子类覆写：检查是否满足胜利条件。每次关键事件后自动调用。
func check_victory() -> bool:
	return false


## 子类覆写：检查是否满足失败条件。返回失败原因字符串，空串表示未失败。
func check_defeat() -> String:
	return ""


## 子类覆写：返回本关目标文本。
## 格式：{ "victory": Array[String], "defeat": Array[String], "details": Array[String] 可选 }
func get_objectives_text() -> Dictionary:
	return { "victory": [], "defeat": [] }


## 子类覆写：为 AI 提供关卡特有的上下文信息。
## 可包含 "escort_units"（护送目标）、"drift_directions"（浮木方向）等。
## 默认实现体在 AITurnRunner.get_ai_context，此处薄壳转发（保留子类覆写钩子）。
func _get_ai_context() -> Dictionary:
	return _get_ai_runner().get_ai_context()


## 子类覆写：技能成功执行后的关卡机制钩子。
## 默认实现体在 SkillCastController.on_skill_executed（空实现），此处薄壳转发（保留子类覆写钩子）。
func _on_skill_executed(_caster: Unit, _skill: SkillData, _cast_cell: Vector2i, _exec_result: SkillExecutor.ExecuteResult) -> void:
	_get_skill_cast_controller().on_skill_executed(_caster, _skill, _cast_cell, _exec_result)


## 子类覆写：在战斗反馈显示前修正单次命中的最终 HP / 实际伤害。
## 默认实现体在 SkillCastController.finalize_skill_hit_damage（空实现），此处薄壳转发（保留子类覆写钩子）。
func _finalize_skill_hit_damage(_caster: Unit, _skill: SkillData, _target: Unit, _hit: CombatResolver.HitResult) -> void:
	_get_skill_cast_controller().finalize_skill_hit_damage(_caster, _skill, _target, _hit)


## 处理波次生成。在每大回合开始时调用。
func _process_wave(round_num: int) -> Array[Unit]:
	var waves := get_wave_config()
	if not waves.has(round_num):
		return [] as Array[Unit]
	var spawned: Array[Unit] = []
	for entry: Dictionary in waves[round_num]:
		var vis: PackedScene = entry.get("visual", null)
		var unit := spawn_unit(entry["unit_data"], entry["cell"], entry["team_index"], vis)
		if entry.has("skills"):
			set_unit_skills(unit, entry["skills"])
		if entry.has("color"):
			unit.unit_color = entry["color"]
		spawned.append(unit)
	return spawned


## 薄壳转发至 SkillCastController.report_unit_damaged（保留旧调用点零改动）。
## 直接伤害/回复统一出口（不经 SkillExecutor 的 HP 变化必须走这里）。
## 前置条件：伤害/回复已应用到 combat_stats。负责 emit unit_hp_changed / unit_died，
## 并无条件调用 _check_win_lose（幂等：phase ENDED 后重复调用为 no-op）。
func report_unit_damaged(unit: Unit, old_hp: int, new_hp: int) -> void:
	_get_skill_cast_controller().report_unit_damaged(unit, old_hp, new_hp)


## 薄壳转发至 SkillCastController.apply_direct_damage（保留旧调用点零改动）。
## 直接伤害便捷入口：先扣减 combat_stats.current_hp，再走 report_unit_damaged 上报结算。
## source 可选，非空时写入 CombatLog。仅用于关卡机制类固定伤害，不走 SkillExecutor。
func apply_direct_damage(unit: Unit, damage: int, source: String = "") -> void:
	_get_skill_cast_controller().apply_direct_damage(unit, damage, source)


## 执行胜负条件检查。在关键事件（倒下、回合开始）后自动调用。
## 薄壳转发至 ObjectivesTracker.check_win_lose（保留旧调用点与信号连接零改动）。
func _check_win_lose(_arg = null) -> void:
	await _get_objectives_tracker().check_win_lose(_arg)

# 用于测试的一键胜利按钮。薄壳转发至 LevelUIBridge.on_win_button_pressed。
func _on_win_button_pressed() -> void:
	_get_ui_bridge().on_win_button_pressed()

# ─────────────────────────────────────────────
# 队伍初始化（读取场景已有节点）
# ─────────────────────────────────────────────

## 薄壳转发至 UnitFactory.setup_teams_from_config（保留旧调用点零改动）。
func _setup_teams_from_config(configs: Array) -> void:
	_get_unit_factory().setup_teams_from_config(configs)


# ─────────────────────────────────────────────
# 回合系统初始化
# ─────────────────────────────────────────────

## 薄壳转发至 SceneBootstrap.apply_tilemap_texture_filter（保留旧调用点零改动）。
func _apply_tilemap_texture_filter() -> void:
	_get_scene_bootstrap().apply_tilemap_texture_filter()


## 子类覆写：返回 true 表示这是"自由移动 / 实时"关卡，跳过回合系统。
## 此模式下 _init_turn_system 直接 return，玩家用键盘自由控李春，AP / round / team_turn 等概念全部失效。
## 关卡仍要在 _on_level_ready 里手动设 _waiting_for_player_input = true 让 _can_accept_command 通过。
func is_free_roam_level() -> bool:
	return false


## 输入状态机组件懒加载（首调时 setup(self)）。
func _get_input_controller() -> InputController:
	if _input_controller == null:
		_input_controller = InputController.new()
		_input_controller.setup(self)
	return _input_controller


## 回合系统组件懒加载（首调时 setup(self)）。
func _get_turn_system() -> TurnSystem:
	if _turn_system == null:
		_turn_system = TurnSystem.new()
		_turn_system.setup(self)
	return _turn_system


## AI 回合执行组件懒加载（首调时 setup(self)）。
func _get_ai_runner() -> AITurnRunner:
	if _ai_runner == null:
		_ai_runner = AITurnRunner.new()
		_ai_runner.setup(self)
	return _ai_runner


## 技能施放与战斗反馈组件懒加载（首调时 setup(self)）。
func _get_skill_cast_controller() -> SkillCastController:
	if _skill_cast_controller == null:
		_skill_cast_controller = SkillCastController.new()
		_skill_cast_controller.setup(self)
	return _skill_cast_controller


## UI 桥接组件懒加载（首调时 setup(self)）。
func _get_ui_bridge() -> LevelUIBridge:
	if _ui_bridge == null:
		_ui_bridge = LevelUIBridge.new()
		_ui_bridge.setup(self)
	return _ui_bridge


## 教程运行器组件懒加载（首调时 setup(self)）。
func _get_tutorial_runner() -> TutorialRunner:
	if _tutorial_runner == null:
		_tutorial_runner = TutorialRunner.new()
		_tutorial_runner.setup(self)
	return _tutorial_runner


## 目标跟踪组件懒加载（首调时 setup(self)）。
func _get_objectives_tracker() -> ObjectivesTracker:
	if _objectives_tracker == null:
		_objectives_tracker = ObjectivesTracker.new()
		_objectives_tracker.setup(self)
	return _objectives_tracker


## 关卡胜负流程组件懒加载（首调时 setup(self)）。
func _get_level_flow() -> LevelFlow:
	if _level_flow == null:
		_level_flow = LevelFlow.new()
		_level_flow.setup(self)
	return _level_flow


## 单位工厂组件懒加载（首调时 setup(self)）。
func _get_unit_factory() -> UnitFactory:
	if _unit_factory == null:
		_unit_factory = UnitFactory.new()
		_unit_factory.setup(self)
	return _unit_factory


## 场景引导组件懒加载（首调时 setup(self)）。
func _get_scene_bootstrap() -> SceneBootstrap:
	if _scene_bootstrap == null:
		_scene_bootstrap = SceneBootstrap.new()
		_scene_bootstrap.setup(self)
	return _scene_bootstrap


## 查询接口组件懒加载（首调时 setup(self)）。
func _get_query_api() -> LevelQueryAPI:
	if _query_api == null:
		_query_api = LevelQueryAPI.new()
		_query_api.setup(self)
	return _query_api


## debug AI 闲聊桥接组件懒加载（首调时 setup(self)）。
func _get_chatter_bridge() -> LLMChatterBridge:
	if _chatter_bridge == null:
		_chatter_bridge = LLMChatterBridge.new()
		_chatter_bridge.setup(self)
	return _chatter_bridge


## 薄壳转发至 TurnSystem.init_turn_system（保留旧调用点零改动）。
func _init_turn_system() -> void:
	_get_turn_system().init_turn_system()


# ─────────────────────────────────────────────
# 回合流转
# ─────────────────────────────────────────────

## 薄壳转发至 TurnSystem.start_team_turn（保留旧调用点零改动）。
func _start_team_turn(index: int) -> void:
	_get_turn_system().start_team_turn(index)


## 薄壳转发至 LevelUIBridge.update_round_label（round_started 信号目标）。
func _update_round_label(round_num: int) -> void:
	_get_ui_bridge().update_round_label(round_num)


## 薄壳转发至 TurnSystem.end_team_turn。UI"结束回合"按钮和 MCP 都调用此方法。
func end_team_turn() -> void:
	_get_turn_system().end_team_turn()


## 薄壳转发至 TurnSystem.do_end_turn。回合结束的实际逻辑，内部和 AI 也调用此方法。
func _do_end_turn() -> void:
	_get_turn_system().do_end_turn()


## 薄壳转发至 TurnSystem.on_end_turn_button_pressed（base_level.tscn 信号目标）。
func _on_end_turn_button_pressed() -> void:
	_get_turn_system().on_end_turn_button_pressed()


## 薄壳转发至 TurnSystem.try_prompt_round_growth（保留旧调用点零改动）。
func _try_prompt_round_growth() -> bool:
	return _get_turn_system().try_prompt_round_growth()


## 薄壳转发至 TurnSystem.clear_end_turn_pending。取消"待确认结束回合"状态。
func _clear_end_turn_pending() -> void:
	_get_turn_system().clear_end_turn_pending()


## 薄壳转发至 TurnSystem._camera_focus_spawned（level1-3 的倾压之号召唤演出调用）。
func _camera_focus_spawned(spawned: Array[Unit]) -> void:
	await _get_turn_system()._camera_focus_spawned(spawned)




# ─────────────────────────────────────────────
# AI 回合
# ─────────────────────────────────────────────

## 薄壳转发至 AITurnRunner.run_ai_turn（由 TurnSystem.start_team_turn call_deferred 触发）。
func _run_ai_turn(team: TeamData) -> void:
	await _get_ai_runner().run_ai_turn(team)


## 薄壳转发至 AITurnRunner.execute_ai_skill（保留旧调用点零改动）。
func _execute_ai_skill(unit: Unit, skill: SkillData, cast_cell: Vector2i) -> void:
	await _get_ai_runner().execute_ai_skill(unit, skill, cast_cell)


## 薄壳转发至 AITurnRunner.get_alive_enemies_of。
func _get_alive_enemies_of(faction: String) -> Array:
	return _get_ai_runner().get_alive_enemies_of(faction)


## 薄壳转发至 LevelQueryAPI.is_cell_occupied。
func _is_cell_occupied(cell: Vector2i) -> bool:
	return _get_query_api().is_cell_occupied(cell)


## 薄壳转发至 LevelQueryAPI.is_any_unit_moving。
func _is_any_unit_moving() -> bool:
	return _get_query_api().is_any_unit_moving()


## 薄壳转发至 LevelQueryAPI.get_unit_at_cell。
func _get_unit_at_cell(cell: Vector2i, team: TeamData) -> Node2D:
	return _get_query_api().get_unit_at_cell(cell, team)



## 在点击位置附近查找任意队伍的单位（用于状态栏显示）。
## 薄壳转发至 LevelQueryAPI.find_nearest_any_unit（保留旧调用点零改动）。
func _find_nearest_any_unit(local_mouse_pos: Vector2, max_dist: float = 24.0) -> Node2D:
	return _get_query_api().find_nearest_any_unit(local_mouse_pos, max_dist)


## 更新状态栏显示指定单位的信息。薄壳转发至 LevelUIBridge.update_status_bar_for_unit。
func _update_status_bar_for_unit(unit: Node2D, is_active: bool = false) -> void:
	_get_ui_bridge().update_status_bar_for_unit(unit, is_active)


## 状态栏回退显示主角。薄壳转发至 LevelUIBridge.reset_status_bar。
func _reset_status_bar() -> void:
	_get_ui_bridge().reset_status_bar()


# ─────────────────────────────────────────────
# 关卡完成 / 剧情
# ─────────────────────────────────────────────

## Play a mid-battle cutscene as an overlay. Blocks until finished.
## 薄壳转发至 LevelFlow.play_mid_cutscene（保留旧调用点零改动）。
func play_mid_cutscene(pages: Array) -> void:
	await _get_level_flow().play_mid_cutscene(pages)


## Call when the level is won. Handles post-cutscene or returns to menu.
## 幂等：phase 已 ENDED 时直接返回，防止重复副作用（Progress.complete_level / 切场景等）。
## 薄壳转发至 LevelFlow.complete_level（保留旧调用点与子类 super() 覆写零改动）。
func complete_level() -> void:
	_get_level_flow().complete_level()


## 薄壳转发至 LevelFlow.continue_after_level_completion（保留旧调用点零改动）。
func _continue_after_level_completion(level: String) -> void:
	_get_level_flow().continue_after_level_completion(level)


## 关卡失败。显示失败面板，玩家选择重试或返回主菜单。
## reason: 失败原因文本（显示在面板中）。
## 幂等：phase 已 ENDED 时直接返回，防止重复弹失败面板。
## 薄壳转发至 LevelFlow.defeat_level（保留旧调用点零改动）。
func defeat_level(reason: String = "任务失败") -> void:
	_get_level_flow().defeat_level(reason)


## 薄壳转发至 LevelUIBridge.on_defeat_retry（defeat_panel.retry_pressed 信号目标）。
func _on_defeat_retry() -> void:
	_get_ui_bridge().on_defeat_retry()


## 薄壳转发至 LevelUIBridge.on_defeat_main_menu（defeat_panel.main_menu_pressed 信号目标）。
func _on_defeat_main_menu() -> void:
	_get_ui_bridge().on_defeat_main_menu()


## 运行时生成一个单位。加入指定队伍，放置在指定 cell 的脚下。
## visual 可选：传入 PackedScene 直接指定外观，否则根据 unit_data.unit_name 自动查表。
## 薄壳转发至 UnitFactory.spawn_unit（保留旧调用点零改动）。
func spawn_unit(unit_data: UnitData, cell: Vector2i, team_index: int, visual: PackedScene = null) -> Unit:
	return _get_unit_factory().spawn_unit(unit_data, cell, team_index, visual)


## 单位倒下处理：从队伍名单中移除，取消选中，播放退场动画。
func _on_unit_died(unit: Unit) -> void:
	# 从队伍名单中移除
	for team: TeamData in teams:
		team.units.erase(unit)
	# 若正选中该单位，取消选中
	if selected_unit == unit:
		_go_idle()
	# 若正 hover 在该单位上，清掉 hover 引用避免 freed 指针
	if _hovered_unit == unit:
		_hovered_unit = null
	# TODO: 替换为实际倒下音效
	# SfxManager.play_sfx(preload("res://assets/audio/sfx/death.wav"), "SFX")
	# 播放退场动画并移除节点
	unit.die()


## 播放一段对话。阻塞直到对话结束。用法：await play_dialogue([line1, line2])
## auto_dismiss=true 时走"打字机结束后自动飘过"，用于单位闲聊（chatter）；
## 默认 false 保持原有"点击/空格推进"行为，关卡剧情调用无需改动。
func play_dialogue(lines: Array[DialogueLine], auto_dismiss: bool = false, dismiss_delay: float = 2.5) -> void:
	await _dialogue.play_dialogue(lines, auto_dismiss, dismiss_delay)


## 李春教程对话单行构造：自动带头像、左侧显示，并按当前关卡匹配预生成 TTS。
## 薄壳转发至 TutorialRunner.lc_line（保留旧调用点零改动）。
func _lc_line(text: String, can_skip: bool = true) -> DialogueLine:
	return _get_tutorial_runner().lc_line(text, can_skip)


## 薄壳转发至 TutorialRunner.tutorial_tts_level_id（保留旧调用点零改动）。
func _tutorial_tts_level_id() -> String:
	return _get_tutorial_runner().tutorial_tts_level_id()


## 单行 chatter 对话的便捷入口。单位阵营决定头像左右，头像来自 PortraitResolver，自动飘过。
## 返回值：true 表示对话已播放完毕；false 表示被拒绝（已有 overlay 占用）。
func play_chatter_dialogue(unit: Node, text: String, dismiss_delay: float = 2.5) -> bool:
	return await _dialogue.play_chatter_dialogue(unit, text, dismiss_delay)


## 多行 chatter 对话（邻接对话的双人场景用）。每条 line 已由调用方准备好 portrait/side。
## voice_handle: 可选 TTS 句柄（鸭子接口：is_streaming() / streaming_done 信号），
##   传入后 auto_dismiss 会等语音播完 +0.5s 才关；不传则只看 dismiss_delay 与文字打完。
## 返回 `{"ok": bool, "was_skipped": bool}`：
##   - ok=false 表示被拒绝（已有 overlay）；was_skipped 此时无意义
##   - was_skipped=true 表示玩家手动按键/点击关闭，false 表示 auto_dismiss 自然结束
func play_chatter_lines(lines: Array[DialogueLine], dismiss_delay: float = 2.0, voice_handle: Node = null) -> Dictionary:
	return await _dialogue.play_chatter_lines(lines, dismiss_delay, voice_handle)


## 授予单位一个新技能。幂等：若单位已有该技能则不做任何操作，不 emit 信号。
## 薄壳转发至 UnitFactory.grant_skill（保留旧调用点零改动）。
func grant_skill(unit: Unit, skill: SkillData) -> void:
	_get_unit_factory().grant_skill(unit, skill)


## 收回单位的一个技能。若单位没有该技能则不做任何操作，不 emit 信号。
## 薄壳转发至 UnitFactory.revoke_skill（保留旧调用点零改动）。
func revoke_skill(unit: Unit, skill: SkillData) -> void:
	_get_unit_factory().revoke_skill(unit, skill)


## 替换单位的全部技能列表。会 duplicate unit_data 避免修改共享资源。
## 薄壳转发至 UnitFactory.set_unit_skills（保留旧调用点零改动）。
func set_unit_skills(unit: Unit, skills: Array) -> void:
	_get_unit_factory().set_unit_skills(unit, skills)


## 在运行时覆写单位的战斗数值。修改后自动刷新头顶 UI。
## 注：hp / atk / ap 是"设计师视角的基线值"，会在 CombatStats.set_base_stats() 里
## 按当前难度系数烤进实际属性。这样难度切换对脚本生成的单位也生效。
## 薄壳转发至 UnitFactory.setup_unit_stats（保留旧调用点零改动）。
func setup_unit_stats(unit: Unit, uname: String, hp: int, atk: int,
		ap: int, move_cost: int, elem: Enums.Element = Enums.Element.NONE,
		elem_amt: int = 0, is_hero_flag: bool = false) -> void:
	_get_unit_factory().setup_unit_stats(unit, uname, hp, atk, ap, move_cost, elem, elem_amt, is_hero_flag)


## 薄壳转发至 LevelUIBridge.on_settings_button_pressed（base_level.tscn 信号目标）。
func _on_settings_button_pressed() -> void:
	_get_ui_bridge().on_settings_button_pressed()


## AI 支持按钮：临时调用 LLM 做一次测试请求。后续会替换为具体业务（旁白/调侃等）。
## 薄壳转发至 LLMChatterBridge.on_ai_button_pressed。
func _on_ai_button_pressed() -> void:
	await _get_chatter_bridge().on_ai_button_pressed()


## 大回合开始信号回调：自动触发一次 AI（占位，后续替换为剧情/战况点评）。
## 薄壳转发至 LLMChatterBridge.on_round_started_ai_call。
func _on_round_started_ai_call(rn: int) -> void:
	await _get_chatter_bridge().on_round_started_ai_call(rn)


## 内部：拼请求 + 显示 toast。被按钮和回合开始两处复用。
## 薄壳转发至 LLMChatterBridge.call_ai_with_prompt。
func _call_ai_with_prompt(prompt: String) -> void:
	await _get_chatter_bridge().call_ai_with_prompt(prompt)


## 薄壳转发至 LevelUIBridge.on_tutorial_button_pressed（base_level.tscn 信号目标）。
func _on_tutorial_button_pressed() -> void:
	_get_ui_bridge().on_tutorial_button_pressed()


## 薄壳转发至 LevelUIBridge.on_objectives_button_pressed（base_level.tscn 信号目标）。
func _on_objectives_button_pressed() -> void:
	_get_ui_bridge().on_objectives_button_pressed()


## 薄壳转发至 LevelUIBridge.on_progress_button_pressed（base_level.tscn 信号目标）。
func _on_progress_button_pressed() -> void:
	_get_ui_bridge().on_progress_button_pressed()


## 弹出本关目标面板（战斗中按 🎯 按钮查看）。薄壳转发至 LevelUIBridge.show_objectives。
func show_objectives() -> void:
	_get_ui_bridge().show_objectives()


# ─────────────────────────────────────────────
# 输入处理（状态机 + 命令函数，实现体在 InputController）
# ─────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	_get_input_controller().handle_unhandled_input(event)


## 是否允许接收玩家命令。双轴状态机 + 既有子状态的联合闸门。
func _can_accept_command() -> bool:
	return _get_input_controller().can_accept_command()


## 进入"流程锁"。配对调用 _end_input_lock。支持嵌套（计数器）。
## 用于自由移动关卡的对话/输入面板等需要暂时屏蔽世界输入的场景。
func _begin_input_lock() -> void:
	_state._begin_input_lock()


func _end_input_lock() -> void:
	_state._end_input_lock()


func preview_cell(cell: Vector2i) -> void:
	_get_input_controller().preview_cell(cell)


func _notification(what: int) -> void:
	# 不走懒加载：_notification 在构造/析构期也会触发
	if _input_controller != null:
		_input_controller.handle_notification(what)


## MCP 兼容：接受两个 int 参数。
func preview_cell_xy(x: int, y: int) -> void:
	preview_cell(Vector2i(x, y))


## 确认：点击某格执行对应操作。
func confirm_cell(cell: Vector2i) -> void:
	_get_input_controller().confirm_cell(cell)


## MCP 兼容：接受两个 int 参数。
func confirm_cell_xy(x: int, y: int) -> void:
	confirm_cell(Vector2i(x, y))


## 取消：回到 IDLE，完全取消选中。
func cancel_action() -> void:
	_get_input_controller().cancel_action()


## 选择技能，进入 TARGETING_SKILL 状态。
func select_skill(skill: SkillData) -> void:
	_get_input_controller().select_skill(skill)


func _show_skill_targeting_for(unit: Unit, skill: SkillData) -> void:
	_get_input_controller()._show_skill_targeting_for(unit, skill)


func _go_idle() -> void:
	_get_input_controller().go_idle()


func _confirm_idle(cell: Vector2i, _local_mouse: Vector2, current_team: TeamData) -> void:
	_get_input_controller().confirm_idle(cell, _local_mouse, current_team)


func _enter_targeting_move() -> void:
	_get_input_controller().enter_targeting_move()


func _confirm_targeting_move(cell: Vector2i, local_mouse: Vector2, current_team: TeamData) -> void:
	await _get_input_controller().confirm_targeting_move(cell, local_mouse, current_team)


## 获取除指定单位外所有被占据的格子。
## 薄壳转发至 LevelQueryAPI.get_occupied_cells_except。
func _get_occupied_cells_except(exclude: Node2D) -> Array[Vector2i]:
	return _get_query_api().get_occupied_cells_except(exclude)


## 获取敌方占据的格子（faction 不同），排除指定单位。用于寻路阻挡。
## 薄壳转发至 LevelQueryAPI.get_enemy_cells_except。
func _get_enemy_cells_except(exclude: Node2D) -> Array[Vector2i]:
	return _get_query_api().get_enemy_cells_except(exclude)


## 获取友方占据的格子（faction 相同），排除指定单位。友方可穿越但不可停留。
## 薄壳转发至 LevelQueryAPI.get_friendly_cells_except。
func _get_friendly_cells_except(exclude: Node2D) -> Array[Vector2i]:
	return _get_query_api().get_friendly_cells_except(exclude)


## 薄壳转发至 LevelQueryAPI.player_team_has_remaining_actions（真源在 AITurnRunner）。
## 当前玩家队伍是否还有可行动单位（未 has_acted、未在移动中、还能移动或有技能能打到敌人）。
func _player_team_has_remaining_actions() -> bool:
	return _get_query_api().player_team_has_remaining_actions()


## 薄壳转发至 LevelQueryAPI.has_action_budget（真源在 AITurnRunner）。
func _has_action_budget(stats: CombatStats) -> bool:
	return _get_query_api().has_action_budget(stats)


## 薄壳转发至 LevelQueryAPI.has_usable_attack（真源在 AITurnRunner）。
## 检查单位是否有攻击技能能够打到敌人（AP/次数够 + 范围内有敌人）。
func _has_usable_attack(unit: Unit, enemy_cells: Dictionary) -> bool:
	return _get_query_api().has_usable_attack(unit, enemy_cells)


## 收集指定阵营的所有存活敌方单位格子。
## 薄壳转发至 LevelQueryAPI.get_enemy_cell_set。
func _get_enemy_cell_set(faction: String) -> Dictionary:
	return _get_query_api().get_enemy_cell_set(faction)


# ─────────────────────────────────────────────
# 技能释放
# ─────────────────────────────────────────────

## 薄壳转发至 LevelUIBridge.setup_skill_targeting。
func _setup_skill_targeting() -> void:
	_get_ui_bridge().setup_skill_targeting()


## 薄壳转发至 LevelUIBridge.setup_phase_notification。
func _setup_phase_notification() -> void:
	_get_ui_bridge().setup_phase_notification()


## 薄壳转发至 LevelUIBridge.clear_skill_targeting。
func _clear_skill_targeting() -> void:
	_get_ui_bridge().clear_skill_targeting()


## 技能攻击镜头参数（真源在 SkillCastController，AITurnRunner 经 _level._xxx 引用此处常量名）。
const _SKILL_CAMERA_ZOOM: float = SkillCastController._SKILL_CAMERA_ZOOM
const _SKILL_CAMERA_SETTLE_TIME: float = SkillCastController._SKILL_CAMERA_SETTLE_TIME
const _SKILL_CAMERA_PAUSE_TIME: float = SkillCastController._SKILL_CAMERA_PAUSE_TIME
const _SKILL_CAMERA_LINGER_TIME: float = SkillCastController._SKILL_CAMERA_LINGER_TIME


## 薄壳转发至 SkillCastController.confirm_targeting_skill（input_controller.confirm_cell 调用）。
func _confirm_targeting_skill(cell: Vector2i) -> void:
	await _get_skill_cast_controller().confirm_targeting_skill(cell)


## 薄壳转发至 SkillCastController.show_combat_feedback（AITurnRunner 与本文件调用）。
## 显示战斗 UI 反馈：伤害弹字 + 血条刷新 + 化势提示。
func _show_combat_feedback(exec_result: SkillExecutor.ExecuteResult, _caster_name: String = "", skill: SkillData = null) -> void:
	_get_skill_cast_controller().show_combat_feedback(exec_result, _caster_name, skill)


## 状态 / 额外效果中文名表（真源在 SkillCastController，AITurnRunner 经 _level._xxx 引用此处常量名）。
const _STATUS_NAMES: Dictionary = SkillCastController._STATUS_NAMES

const _EXTRA_EFFECT_NAMES: Dictionary = SkillCastController._EXTRA_EFFECT_NAMES


## 薄壳转发至 SkillCastController.format_phase_details。
## 拼接化势详情 BBCode 富文本，供 Notify 右上角显示。
func _format_phase_details(pd: PhaseData, hit: CombatResolver.HitResult, cat_name: String) -> String:
	return _get_skill_cast_controller().format_phase_details(pd, hit, cat_name)


func _on_skill_button_pressed(index: int) -> void:
	_get_input_controller().on_skill_button_pressed(index)


func _on_move_button_pressed() -> void:
	_get_input_controller().on_move_button_pressed()


## 薄壳转发至 SceneBootstrap.get_all_units（保留旧调用点零改动）。
func _get_all_units() -> Array:
	return _get_scene_bootstrap().get_all_units()


## 找一个"空且可走"的格。同心方环外扩搜索，max_radius 控制最大半径。
## 找不到时返回 target 本身（不静默崩；调用方可以看到 spawn_unit 的 push_warning）。
## 复用 movement_manager.get_movement_cost 判地形 + _get_all_units 判占位。
## 薄壳转发至 SceneBootstrap.find_empty_walkable_cell（保留旧调用点零改动）。
func _find_empty_walkable_cell(target: Vector2i, max_radius: int = 4) -> Vector2i:
	return _get_scene_bootstrap().find_empty_walkable_cell(target, max_radius)


## 薄壳转发至 SceneBootstrap.is_cell_walkable_and_empty（保留旧调用点零改动）。
func _is_cell_walkable_and_empty(cell: Vector2i) -> bool:
	return _get_scene_bootstrap().is_cell_walkable_and_empty(cell)


## 难度变化时，按比例重算所有存活单位的 max_hp / ap_max / base_atk。
## 薄壳转发至 LevelUIBridge.on_difficulty_changed（Settings.difficulty_changed 信号目标）。
func _on_difficulty_changed(_id: String) -> void:
	_get_ui_bridge().on_difficulty_changed(_id)


## 薄壳转发至 LevelUIBridge.refresh_difficulty_dependent_ui。
func _refresh_difficulty_dependent_ui() -> void:
	_get_ui_bridge().refresh_difficulty_dependent_ui()


# ─────────────────────────────────────────────
# 统一接口（UI 和 MCP 共用）
# ─────────────────────────────────────────────

## 通过技能索引选择技能（0~4）。UI 按钮和 MCP 都调用此方法。
## 薄壳转发至 LevelQueryAPI.select_skill_by_index（真源在 InputController）。
func select_skill_by_index(index: int) -> bool:
	return _get_query_api().select_skill_by_index(index)


## 进入移动模式。UI 移动按钮和 MCP 都调用此方法。
## 薄壳转发至 LevelQueryAPI.start_move（真源在 InputController）。
func start_move() -> bool:
	return _get_query_api().start_move()


## 查询当前游戏状态。返回字典，所有值为原始类型。
## 薄壳转发至 LevelQueryAPI.query_state。
func query_state() -> Dictionary:
	return _get_query_api().query_state()


## 查询所有单位信息。返回字典数组，所有值为原始类型。
## 薄壳转发至 LevelQueryAPI.query_units。
func query_units() -> Array:
	return _get_query_api().query_units()


## 薄壳转发至 LevelQueryAPI.get_friendly_units。
func get_friendly_units() -> Array[Unit]:
	return _get_query_api().get_friendly_units()


## 薄壳转发至 LevelQueryAPI.get_hero_unit。
func get_hero_unit() -> Unit:
	return _get_query_api().get_hero_unit()


func apply_unit_growth_bonus(unit: Unit, hp_delta: int = 0, atk_delta: int = 0, ap_delta: int = 0) -> void:
	if unit == null or unit.combat_stats == null:
		return
	unit.combat_stats.grow_base_stats(hp_delta, atk_delta, ap_delta)
	unit.refresh_overhead_bars()
	if selected_unit == unit:
		_update_status_bar_for_unit(unit, true)


## 应用 Progress 中已选的成长选项加成。子关卡若有特殊单位类型可 override。
##
## 选项语义（与 progress.gd::LEVEL_GROWTH_OPTIONS 对应）：
##   g1_X_atk: 李春基础攻击力 +4
##   g1_X_ap:  全体我方行动力上限 +5
##   g1_2_craft: 全体工匠 HP +10 / ATK +2
##   g1_3_team:  全体我方 HP +10 / 运石工 AP 上限 +5
## 解锁类成长在 Progress.LEVEL_GROWTH_OPTIONS 中配置 skill_id，
## 由 Progress._normalize_progress 自动写入 unlocked_skill_ids，这里不重复处理。
func _apply_persistent_growth_effects() -> void:
	# 攻击力 +4（每关都有，可叠加 +12）
	for atk_id in ["g1_1_atk", "g1_2_atk", "g1_3_atk"]:
		if Progress.has_growth_option(atk_id):
			apply_unit_growth_bonus(get_hero_unit(), 0, 4, 0)
	# AP 上限 +5（每关都有，全体我方）
	for ap_id in ["g1_1_ap", "g1_2_ap", "g1_3_ap"]:
		if Progress.has_growth_option(ap_id):
			for unit in get_friendly_units():
				apply_unit_growth_bonus(unit, 0, 0, 5)
	# 1-2 工匠强化
	if Progress.has_growth_option("g1_2_craft"):
		for unit in get_friendly_units():
			if unit is Unit and unit.combat_stats and unit.combat_stats.unit_name == "工匠":
				apply_unit_growth_bonus(unit, 10, 2, 0)
	# 1-3 全体 HP + 运石工 AP
	if Progress.has_growth_option("g1_3_team"):
		for unit in get_friendly_units():
			apply_unit_growth_bonus(unit, 10, 0, 0)
			if unit is Unit and unit.combat_stats and unit.combat_stats.unit_name == "运石工":
				apply_unit_growth_bonus(unit, 0, 0, 5)


## 薄壳转发至 UnitFactory.modify_unit_skill（保留旧调用点零改动）。
func modify_unit_skill(unit: Unit, skill_id: String, changes: Dictionary) -> bool:
	return _get_unit_factory().modify_unit_skill(unit, skill_id, changes)


## 薄壳转发至 UnitFactory.add_skill_to_unit（保留旧调用点零改动）。
func add_skill_to_unit(unit: Unit, skill: SkillData, replace_candidates: Array[String] = []) -> void:
	_get_unit_factory().add_skill_to_unit(unit, skill, replace_candidates)


## 查询当前可移动范围（TARGETING_MOVE 时有效）。
## 薄壳转发至 LevelQueryAPI.query_move_range。
func query_move_range() -> Array:
	return _get_query_api().query_move_range()


## 查询技能释放/影响范围（TARGETING_SKILL 时有效）。
## 薄壳转发至 LevelQueryAPI.query_skill_range。
func query_skill_range() -> Dictionary:
	return _get_query_api().query_skill_range()


# ─────────────────────────────────────────────
# 特殊地块（委托 SpecialTileRegistry）
# ─────────────────────────────────────────────

func _setup_special_tiles() -> void:
	_special_tile_registry.scan_from_container()


func _get_special_tile_at(cell: Vector2i) -> SpecialTile:
	return _special_tile_registry.get_at(cell)


## 在 _on_level_ready() 中程序化注册一个 SpecialTile（跳过 _setup_special_tiles 自动扫描）。
func register_special_tile(tile: SpecialTile, cell: Vector2i) -> void:
	_special_tile_registry.register(tile, cell)


## 从统一派发表解除一个运行时特殊地格，避免 queue_free 后字典保留失效实例。
func unregister_special_tile(tile: SpecialTile, cell: Vector2i) -> void:
	_special_tile_registry.unregister(tile, cell)


## 在指定地块上方挂一个统一的脉动强调标记。详见 SpecialTileRegistry.spawn_pulsing_marker。
func spawn_tile_pulsing_marker(
		cell: Vector2i,
		halo_color: Color,
		label_text: String = "",
		local_offset: Vector2 = Vector2.ZERO,
		node_name: String = "",
		tile_z_index: int = 1) -> Marker2D:
	return _special_tile_registry.spawn_pulsing_marker(
			cell, halo_color, label_text, local_offset, node_name, tile_z_index)


# ─────────────────────────────────────────────
# 场景辅助
# ─────────────────────────────────────────────

## 薄壳转发至 SceneBootstrap.reparent_entities_to_obstacles（保留旧调用点零改动）。
func _reparent_entities_to_obstacles() -> void:
	_get_scene_bootstrap().reparent_entities_to_obstacles()


## 薄壳转发至 SceneBootstrap.find_walkable_tilemap（保留旧调用点零改动）。
func _find_walkable_tilemap() -> TileMapLayer:
	return _get_scene_bootstrap().find_walkable_tilemap()


## 导出构建里 @export obstacles_tilemap_layer 可能为 null（AGENTS Pitfalls #2），
## 按节点名关键字模糊回退查找障碍层。用前缀匹配而非包含匹配，避免误命中
## "unvisiable obstacle"（modulate.a == 0 的隐形碰撞层，挂上去单位会被隐掉）。
## 薄壳转发至 SceneBootstrap.find_obstacle_tilemap（保留旧调用点零改动）。
func _find_obstacle_tilemap() -> TileMapLayer:
	return _get_scene_bootstrap().find_obstacle_tilemap()


## 薄壳转发至 SceneBootstrap.find_hero（保留旧调用点零改动）。
func _find_hero() -> Node2D:
	return _get_scene_bootstrap().find_hero()


## 薄壳转发至 SceneBootstrap.get_tilemap_bounds（保留旧调用点零改动）。
func get_tilemap_bounds() -> Rect2:
	return _get_scene_bootstrap().get_tilemap_bounds()
