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
## AI 回合中每个敌人一轮内最多走几步（每步 = 向相邻格移动一次）。
## 子关卡可在 _on_level_ready 里覆盖，例如 `ai_max_move_steps = 4`。
@export var ai_max_move_steps: int = 1

# ─────────────────────────────────────────────
# 关卡事件信号（供关卡脚本 connect）
# ─────────────────────────────────────────────

## 某单位死亡（HP 降到 0）。每个单位只会触发一次。
signal unit_died(unit: Unit)

## 某单位 HP 变化（受伤/治疗/DoT/休息恢复）。可用于 HP 阈值监控。
signal unit_hp_changed(unit: Unit, old_hp: int, new_hp: int)

## 大回合开始（所有队伍各打完一次为一个大回合）。round_number 在 emit 前已递增。
signal round_started(round_number: int)

## 队伍小回合开始（team_index 从 0 起）。
signal team_turn_started(team_index: int)

## 某单位获得一个技能（通过 grant_skill 添加）。
signal unit_gained_skill(unit: Unit, skill: SkillData)

## 某单位失去一个技能（通过 revoke_skill 移除）。
signal unit_lost_skill(unit: Unit, skill: SkillData)


@onready var tilemap_container: Node2D = $TileMaps
@onready var units_container: Node2D = $Entities/Units
@onready var special_tiles_container: Node2D = $SpecialTiles
@onready var move_overlay: Node2D = $MoveOverlay
@onready var movement_manager: Node = $MovementManager
@onready var camera: Camera2D = $Camera2D
@onready var gui: CanvasLayer = $GUI
@onready var status_bar: HBoxContainer = $StatusBarScene/PanelContainer/MarginContainer/StatusBar

const SettingsPanelScene := preload("res://scenes/ui/settings_panel.tscn")

var tilemap: TileMapLayer
## 化势提示 UI（运行时创建，挂在 GUI 层）。
var _phase_notification: PhaseNotification = null
## 兼容旧版：指向第一个玩家控制队伍的第一个单位（李春）。
var hero: Node2D
var unit_selected := false
var _mid_cutscene_active := false
var _settings_open := false

## 输入状态机。
enum InputState { IDLE, UNIT_SELECTED, TARGETING_MOVE, TARGETING_SKILL, ANIMATING }
var _input_state: InputState = InputState.IDLE
## 当前选中的技能（TARGETING_SKILL 状态时有效）。
var _current_skill: SkillData = null
## 技能范围 Overlay（运行时动态创建）。
var _skill_targeting: Node2D = null
## 选中单位脚下的呼吸菱形指示器。
var _selection_indicator: Line2D
## 结束回合的待确认状态：第一次点击已登记，等待第二次确认。
var _end_turn_pending_confirm: bool = false
## 按钮默认 modulate，切换高亮状态时用来还原。
var _end_turn_button_default_modulate: Color = Color.WHITE

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
## 大回合计数（所有队伍各轮一次为一个大回合）。第一大回合 = 1。
var round_number: int = 1
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
	_init_turn_system()
	# 连接死亡处理
	unit_died.connect(_on_unit_died)
	# 连接状态栏技能按钮信号
	if status_bar and status_bar.has_signal("skill_button_pressed"):
		status_bar.skill_button_pressed.connect(_on_skill_button_pressed)
	if status_bar and status_bar.has_signal("move_button_pressed"):
		status_bar.move_button_pressed.connect(_on_move_button_pressed)
	# 初始显示主角信息
	if hero:
		_update_status_bar_for_unit(hero, false)


func _process(_delta: float) -> void:
	# 选中指示器跟随
	if _selection_indicator:
		if selected_unit != null and is_instance_valid(selected_unit):
			_selection_indicator.global_position = selected_unit.global_position
			_selection_indicator.visible = true
		else:
			_selection_indicator.visible = false


func _setup_selection_indicator() -> void:
	_selection_indicator = Line2D.new()
	# 放大菱形尺寸（原 16→24），线条加粗，颜色更亮
	_selection_indicator.points = PackedVector2Array([-24, 0, 0, 12, 24, 0, 0, -12, -24, 0])
	_selection_indicator.width = 2.5
	_selection_indicator.default_color = Color(1.0, 0.95, 0.3, 1.0)
	_selection_indicator.z_index = -1
	_selection_indicator.visible = false
	add_child(_selection_indicator)
	var tween := create_tween().set_loops()
	tween.tween_property(_selection_indicator, "modulate:a", 0.45, 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_selection_indicator, "modulate:a", 1.0, 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


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
	CombatLog.msg("═══ %s 的回合开始 ═══" % team.team_name)
	team_turn_started.emit(index)
	for unit: Node2D in team.units:
		unit.has_acted = false
		if unit is Unit and unit.combat_stats != null:
			unit.combat_stats.reset_turn_counters()
			CombatLog.log_turn_start(team.team_name, unit.combat_stats.unit_name, unit.combat_stats.current_hp, unit.combat_stats.ap_current)
			unit.combat_stats.process_turn_start()
			(unit as Unit).refresh_overhead_bars()
			if not unit.combat_stats.is_alive():
				unit.has_acted = true
	# _go_idle 已在 _do_end_turn 中调用，此处只需确保状态干净
	move_overlay.clear_range()

	_animate_turn_label(team.team_name)

	if team.controller == "ai":
		if _end_turn_button:
			_end_turn_button.visible = false
		_waiting_for_player_input = false
		# 延迟一帧再执行 AI，确保 UI 更新后再开始移动
		_run_ai_turn.call_deferred(team)
	else:
		if _end_turn_button:
			_end_turn_button.visible = true
		_end_turn_pending_confirm = false
		_set_end_turn_button_highlight(false)
		_waiting_for_player_input = true
		# 玩家回合开始时把镜头平滑拉到主角，给本回合一个明确的起点。
		_focus_camera_on_team(team)
		# 玩家回合开始时刷新状态栏，确保显示 AP 恢复后的最新数据
		_reset_status_bar()


## 回合标签"弹入"动画：从 1.4 倍+透明缩放到正常+不透明。
func _animate_turn_label(team_name: String) -> void:
	if _turn_label == null:
		return
	_turn_label.text = "[ %s 的回合 ]" % team_name
	_turn_label.pivot_offset = _turn_label.size / 2
	_turn_label.scale = Vector2(1.4, 1.4)
	_turn_label.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(_turn_label, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_turn_label, "scale", Vector2.ONE, 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


## 把镜头平滑拉到队伍"代表单位"（优先 hero，否则队里第一个存活单位）。
## 仅修改 target_position，不锁定相机，玩家仍可随时手动平移/缩放。
func _focus_camera_on_team(team: TeamData) -> void:
	if camera == null:
		return
	var lv_camera := camera as LevelCamera
	if lv_camera == null:
		return
	var focus_unit: Node2D = null
	if hero != null and is_instance_valid(hero) and hero in team.units:
		var hu := hero as Unit
		if hu == null or hu.combat_stats == null or hu.combat_stats.is_alive():
			focus_unit = hero
	if focus_unit == null:
		for u: Node2D in team.units:
			if not is_instance_valid(u):
				continue
			if u is Unit:
				var us := (u as Unit).combat_stats
				if us != null and not us.is_alive():
					continue
			focus_unit = u
			break
	if focus_unit == null:
		return
	lv_camera.target_position = focus_unit.global_position


## 结束整个队伍的回合。UI"结束回合"按钮和 MCP 都调用此方法。
func end_team_turn() -> void:
	if current_team_index < 0 or current_team_index >= teams.size():
		return
	var team: TeamData = teams[current_team_index]
	if team.controller == "player" and not _waiting_for_player_input:
		return
	if _mid_cutscene_active:
		return
	_do_end_turn()


## 回合结束的实际逻辑。内部和 AI 也调用此方法。
func _do_end_turn() -> void:
	_clear_end_turn_pending()
	if current_team_index >= 0 and current_team_index < teams.size():
		var team: TeamData = teams[current_team_index]
		for unit: Node2D in team.units.duplicate():
			if unit is Unit and unit.combat_stats != null and unit.combat_stats.is_alive():
				var hp_before_dot: int = unit.combat_stats.current_hp
				var dot: int = unit.combat_stats.process_turn_end()
				var hp_after_dot: int = unit.combat_stats.current_hp
				if dot > 0:
					var popup := DamagePopup.new()
					add_child(popup)
					popup.show_at(unit.global_position, dot)
					unit_hp_changed.emit(unit, hp_before_dot, hp_after_dot)
					if hp_after_dot <= 0:
						unit_died.emit(unit)
				if team.controller == "player" and unit.combat_stats.is_alive():
					var hp_before_rest: int = unit.combat_stats.current_hp
					unit.combat_stats.rest_recovery()
					var hp_after_rest: int = unit.combat_stats.current_hp
					if hp_before_rest != hp_after_rest:
						unit_hp_changed.emit(unit, hp_before_rest, hp_after_rest)
				(unit as Unit).refresh_overhead_bars()
	_go_idle()
	_waiting_for_player_input = false
	if _end_turn_button:
		_end_turn_button.visible = false
	var next_index := (current_team_index + 1) % teams.size()
	if next_index == 0:
		round_number += 1
		round_started.emit(round_number)
	_start_team_turn(next_index)


func _on_end_turn_button_pressed() -> void:
	# 队伍已经没得做了 → 直接结束，跳过确认
	if not _player_team_has_remaining_actions():
		_end_turn_pending_confirm = false
		_set_end_turn_button_highlight(false)
		end_team_turn()
		return
	# 第一次点击 → 进入待确认并高亮
	if not _end_turn_pending_confirm:
		_end_turn_pending_confirm = true
		_set_end_turn_button_highlight(true)
		return
	# 第二次点击 → 真正结束
	_end_turn_pending_confirm = false
	_set_end_turn_button_highlight(false)
	end_team_turn()


## 结束回合按钮高亮配置（"待确认"态）。
const _END_TURN_HIGHLIGHT_MODULATE: Color = Color(1.8, 1.1, 0.4, 1.0)
## 边框颜色偏近白，被 modulate 乘完后正好变成更亮的暖橙，和按钮面形成层次。
const _END_TURN_HIGHLIGHT_BORDER_COLOR: Color = Color(1.0, 0.95, 0.85, 1.0)
const _END_TURN_HIGHLIGHT_BORDER_WIDTH: int = 3
const _END_TURN_HIGHLIGHT_STATES: Array[String] = ["normal", "hover", "pressed", "focus"]


func _set_end_turn_button_highlight(highlight: bool) -> void:
	if _end_turn_button == null:
		return
	if highlight:
		# 暖橙色 modulate + 各状态的 StyleBoxFlat 描边。两层叠加，底色再暗也看得见。
		_end_turn_button.modulate = _END_TURN_HIGHLIGHT_MODULATE
		for state in _END_TURN_HIGHLIGHT_STATES:
			var base := _end_turn_button.get_theme_stylebox(state)
			var style: StyleBoxFlat
			if base is StyleBoxFlat:
				style = (base as StyleBoxFlat).duplicate() as StyleBoxFlat
			else:
				style = StyleBoxFlat.new()
				style.bg_color = Color(0.15, 0.15, 0.18, 0.95)
				style.set_corner_radius_all(3)
			style.border_color = _END_TURN_HIGHLIGHT_BORDER_COLOR
			style.set_border_width_all(_END_TURN_HIGHLIGHT_BORDER_WIDTH)
			_end_turn_button.add_theme_stylebox_override(state, style)
	else:
		_end_turn_button.modulate = _end_turn_button_default_modulate
		for state in _END_TURN_HIGHLIGHT_STATES:
			_end_turn_button.remove_theme_stylebox_override(state)


## 取消"待确认结束回合"状态。被任何玩家的其他操作入口调用。
func _clear_end_turn_pending() -> void:
	if _end_turn_pending_confirm:
		_end_turn_pending_confirm = false
		_set_end_turn_button_highlight(false)




# ─────────────────────────────────────────────
# AI 回合
# ─────────────────────────────────────────────

## AI 回合中每个单位行动前，镜头锁定并放大的倍率。
const _AI_TURN_CAMERA_LOCK_ZOOM: float = 1.4
## 镜头切到新单位后、该单位开始移动前的等待时间（秒），给玩家视线跟上的间隔。
const _AI_TURN_CAMERA_FOCUS_DELAY: float = 0.3


func _run_ai_turn(team: TeamData) -> void:
	# TODO: 完善 AI —— 目前为随机向相邻格移动一步
	var lv_camera := camera as LevelCamera
	for unit: Node2D in team.units:
		if lv_camera and is_instance_valid(unit):
			lv_camera.lock_on(unit, _AI_TURN_CAMERA_LOCK_ZOOM)
			await get_tree().create_timer(_AI_TURN_CAMERA_FOCUS_DELAY).timeout
		if not unit.is_moving:
			CombatLog.msg("  AI行动: %s 在%s 尝试移动..." % [
				unit.combat_stats.unit_name if unit is Unit and unit.combat_stats else unit.name,
				unit.cell])
			await _ai_move_unit(unit)
		unit.has_acted = true
	if lv_camera:
		lv_camera.unlock()
	_do_end_turn()


func _ai_move_unit(unit: Node2D) -> void:
	var steps: int = max(1, ai_max_move_steps)
	for _i in range(steps):
		var dirs: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0),
			Vector2i(0, 1), Vector2i(0, -1),
		]
		dirs.shuffle()
		var moved := false
		for dir: Vector2i in dirs:
			var target_cell: Vector2i = unit.cell + dir
			var cost: int = movement_manager.get_movement_cost(target_cell)
			var occupied := _is_cell_occupied(target_cell)
			if cost != TileType.IMPASSABLE and not occupied:
				var path: Array[Vector2i] = [unit.cell, target_cell]
				unit.move_along_path(path, tilemap)
				await unit.move_finished
				CombatLog.msg("  AI移动: %s → %s" % [unit.cell - dir, unit.cell])
				moved = true
				break
		if not moved:
			CombatLog.msg("  AI无法移动: 所有相邻格不可通行或被占据")
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
		GameState.transition_to_scene("res://scenes/cutscene/cutscene_scene.tscn")
	else:
		GameState.transition_to_scene("res://scenes/menu/main_menu.tscn")


## 关卡失败。由关卡脚本在检测到失败条件时调用（例如主角死亡）。
func defeat_level() -> void:
	GameState.transition_to_scene("res://scenes/menu/main_menu.tscn")


## 运行时生成一个单位。加入指定队伍，放置在指定 cell 的脚下。
## 返回生成的 Unit 节点供进一步操作。
func spawn_unit(unit_data: UnitData, cell: Vector2i, team_index: int) -> Unit:
	var UnitScene := preload("res://scenes/unit/unit.tscn")
	var unit: Unit = UnitScene.instantiate()
	unit.unit_data = unit_data
	obstacles_tilemap_layer.add_child(unit)
	unit.movement_manager = movement_manager
	unit.set_cell(cell, tilemap)
	if team_index >= 0 and team_index < teams.size():
		var team: TeamData = teams[team_index]
		unit.team_index = team_index
		unit.faction = team.faction
		team.units.append(unit)
	return unit


## 单位死亡处理：从队伍名单中移除，取消选中，播放退场动画。
func _on_unit_died(unit: Unit) -> void:
	# 从队伍名单中移除
	for team: TeamData in teams:
		team.units.erase(unit)
	# 若正选中该单位，取消选中
	if selected_unit == unit:
		_go_idle()
	# 播放退场动画并移除节点
	unit.die()


## 播放一段对话。阻塞直到对话结束。用法：await play_dialogue([line1, line2])
func play_dialogue(lines: Array[DialogueLine]) -> void:
	var DialogueBoxScene := preload("res://scenes/ui/dialogue_box.tscn")
	var box = DialogueBoxScene.instantiate()
	add_child(box)
	box.start(lines)
	await box.dialogue_finished
	box.queue_free()


## 授予单位一个新技能。幂等：若单位已有该技能则不做任何操作，不 emit 信号。
func grant_skill(unit: Unit, skill: SkillData) -> void:
	if unit == null or unit.unit_data == null or skill == null:
		return
	# 确保 unit_data 已 duplicate，避免污染磁盘资源
	if not unit.unit_data.resource_local_to_scene:
		unit.unit_data = unit.unit_data.duplicate()
		unit.unit_data.resource_local_to_scene = true
	if skill in unit.unit_data.skills:
		return
	unit.unit_data.skills.append(skill)
	unit_gained_skill.emit(unit, skill)
	# 若正是当前选中单位，刷新状态栏
	if selected_unit == unit:
		_update_status_bar_for_unit(unit, true)


## 收回单位的一个技能。若单位没有该技能则不做任何操作，不 emit 信号。
func revoke_skill(unit: Unit, skill: SkillData) -> void:
	if unit == null or unit.unit_data == null or skill == null:
		return
	if not skill in unit.unit_data.skills:
		return
	unit.unit_data.skills.erase(skill)
	unit_lost_skill.emit(unit, skill)
	if selected_unit == unit:
		_update_status_bar_for_unit(unit, true)


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
	if not _can_accept_command():
		return
	if event.is_action_pressed("ui_cancel"):
		_on_settings_button_pressed()
		return
	if _mid_cutscene_active:
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


## 是否允许接收命令（非过场、非动画、玩家回合中）。
func _can_accept_command() -> bool:
	if _mid_cutscene_active or tilemap == null:
		return false
	if not _waiting_for_player_input:
		return false
	if _input_state == InputState.ANIMATING:
		return false
	return true


func preview_cell(cell: Vector2i) -> void:
	if not _can_accept_command():
		return
	match _input_state:
		InputState.TARGETING_MOVE:
			move_overlay.update_path(cell)
		InputState.TARGETING_SKILL:
			if _skill_targeting:
				_skill_targeting.update_hover(cell)

## MCP 兼容：接受两个 int 参数。
func preview_cell_xy(x: int, y: int) -> void:
	preview_cell(Vector2i(x, y))


## 确认：点击某格执行对应操作。
func confirm_cell(cell: Vector2i) -> void:
	if not _can_accept_command():
		return
	var local_mouse := tilemap.map_to_local(cell) if tilemap else Vector2.ZERO
	var current_team: TeamData = teams[current_team_index] if current_team_index >= 0 else null
	if current_team == null:
		return

	match _input_state:
		InputState.IDLE, InputState.UNIT_SELECTED:
			_confirm_idle(cell, local_mouse, current_team)
		InputState.TARGETING_MOVE:
			_confirm_targeting_move(cell, local_mouse, current_team)
		InputState.TARGETING_SKILL:
			_confirm_targeting_skill(cell)


## MCP 兼容：接受两个 int 参数。
func confirm_cell_xy(x: int, y: int) -> void:
	confirm_cell(Vector2i(x, y))


## 取消：回到 IDLE，完全取消选中。
func cancel_action() -> void:
	if not _can_accept_command():
		return
	_clear_end_turn_pending()
	if _input_state == InputState.TARGETING_SKILL:
		_clear_skill_targeting()
	if _input_state != InputState.IDLE:
		_go_idle()


## 选择技能，进入 TARGETING_SKILL 状态。
func select_skill(skill: SkillData) -> void:
	if not _can_accept_command():
		return
	if selected_unit == null or not selected_unit is Unit:
		return
	var unit := selected_unit as Unit
	if unit.combat_stats == null or not unit.combat_stats.can_use_skill(skill):
		return
	_clear_end_turn_pending()
	_current_skill = skill
	move_overlay.clear_range()
	if _skill_targeting:
		_skill_targeting.show_skill_range(tilemap, skill, unit.cell)
	_input_state = InputState.TARGETING_SKILL


func _go_idle() -> void:
	selected_unit = null
	unit_selected = false
	_current_skill = null
	move_overlay.clear_range()
	_clear_skill_targeting()
	_input_state = InputState.IDLE
	_reset_status_bar()


func _confirm_idle(_cell: Vector2i, local_mouse: Vector2, current_team: TeamData) -> void:
	_clear_end_turn_pending()
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
	var unit := selected_unit
	if unit is Unit and unit.combat_stats != null:
		var stats: CombatStats = unit.combat_stats
		if not stats.can_move():
			return
		var occupied: Array[Vector2i] = _get_occupied_cells_except(unit)
		# 每格消耗 = 基础消耗 + 状态修正
		var effective_cost := stats.move_cost_per_tile + stats.get_move_ap_modifier()
		move_overlay.show_range_ap(tilemap, movement_manager, unit.cell, stats.ap_current, effective_cost, occupied)
	else:
		move_overlay.show_range(tilemap, movement_manager, unit.cell, unit.movement_points)


func _confirm_targeting_move(cell: Vector2i, local_mouse: Vector2, current_team: TeamData) -> void:
	_clear_end_turn_pending()
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
			var from_cell := path[0]
			moving_unit.combat_stats.ap_current -= ap_cost
			moving_unit.combat_stats.moves_used += 1
			CombatLog.log_unit_move(moving_unit.combat_stats.unit_name, from_cell, cell, ap_cost, moving_unit.combat_stats.ap_current)
			moving_unit.refresh_overhead_bars()
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
## 当前玩家队伍是否还有可行动单位（未 has_acted、未在移动中、还能移动或放技能）。
func _player_team_has_remaining_actions() -> bool:
	if current_team_index < 0 or current_team_index >= teams.size():
		return false
	var team: TeamData = teams[current_team_index]
	if team.controller != "player":
		return false
	for unit: Node2D in team.units:
		if not unit is Unit:
			continue
		var u := unit as Unit
		if u.has_acted or u.is_moving:
			continue
		if u.combat_stats == null or not u.combat_stats.is_alive():
			continue
		var stats: CombatStats = u.combat_stats
		if stats.ap_current > 0 and (stats.can_move() or _has_usable_skill(u)):
			return true
	return false


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
# 技能释放
# ─────────────────────────────────────────────

func _setup_skill_targeting() -> void:
	var SkillTargetingScript := preload("res://scripts/combat/skill_targeting.gd")
	var st := Node2D.new()
	st.set_script(SkillTargetingScript)
	st.name = "SkillTargeting"
	add_child(st)
	_skill_targeting = st


func _setup_phase_notification() -> void:
	_phase_notification = PhaseNotification.new()
	gui.add_child(_phase_notification)


func _clear_skill_targeting() -> void:
	if _skill_targeting and _skill_targeting.has_method("clear"):
		_skill_targeting.clear()
	_current_skill = null


func _confirm_targeting_skill(cell: Vector2i) -> void:
	_clear_end_turn_pending()
	if selected_unit == null or _current_skill == null or _skill_targeting == null:
		_go_idle()
		return

	if not _skill_targeting.has_cast_cell(cell):
		_go_idle()
		return

	var all_units: Array = _get_all_units()
	var caster_faction: String = selected_unit.faction if "faction" in selected_unit else ""

	var exec_result := SkillExecutor.execute(selected_unit, _current_skill, cell, all_units, caster_faction)
	_clear_skill_targeting()

	if not exec_result.success:
		push_warning("技能执行失败: %s" % exec_result.error)
		_go_idle()
		return

	# ── UI 反馈 ──
	_show_combat_feedback(exec_result)

	# 更新状态栏
	_update_status_bar_for_unit(selected_unit, true)
	# 刷新攻击者头顶状态条（AP 消耗后）
	if selected_unit is Unit:
		(selected_unit as Unit).refresh_overhead_bars()

	# AP 剩余且还能行动？
	var unit := selected_unit as Unit
	if unit and unit.combat_stats:
		var stats := unit.combat_stats
		if stats.ap_current > 0 and (stats.can_move() or _has_usable_skill(unit)):
			_input_state = InputState.UNIT_SELECTED
			if stats.can_move():
				_enter_targeting_move()
			return

	if selected_unit:
		selected_unit.has_acted = true
	_go_idle()


## 显示战斗 UI 反馈：伤害弹字 + 血条刷新 + 化势提示。
func _show_combat_feedback(exec_result: SkillExecutor.ExecuteResult) -> void:
	var showed_phase := false
	for entry in exec_result.hit_results:
		var target_unit: Node2D = entry["unit"]
		var hit: CombatResolver.HitResult = entry["hit"]

		# 伤害弹字
		if hit.damage > 0:
			var phase_name := ""
			if hit.phase_result and hit.phase_result.phase_data:
				phase_name = hit.phase_result.phase_data.phase_name
			var popup := DamagePopup.new()
			add_child(popup)
			popup.show_at(target_unit.global_position, hit.damage, phase_name)

		# 刷新头顶状态条
		if target_unit is Unit:
			(target_unit as Unit).refresh_overhead_bars()

		# 关卡事件信号：HP 变化 + 死亡
		if target_unit is Unit and hit.damage > 0:
			var stats := (target_unit as Unit).combat_stats
			var new_hp: int = stats.current_hp
			var old_hp: int = new_hp + hit.damage
			unit_hp_changed.emit(target_unit, old_hp, new_hp)
			if hit.is_kill:
				unit_died.emit(target_unit)

		# 化势触发时的元素对比 popup（每个命中都显示）
		if hit.phase_result and hit.phase_result.phase_data:
			var elem_popup := PhaseElementPopup.new()
			add_child(elem_popup)
			elem_popup.show_at(
				target_unit.global_position,
				hit.skill_attach_element, hit.skill_attach_amount,
				hit.pre_target_element, hit.pre_target_amount
			)

		# 化势提示（整次施法只一次）
		if not showed_phase and hit.phase_result and hit.phase_result.phase_data:
			showed_phase = true
			var pd: PhaseData = hit.phase_result.phase_data
			var cat_name := "制势" if pd.category == Enums.PhaseCategory.DOMINANT else "承势"
			if _phase_notification:
				_phase_notification.show_phase(pd.phase_name, cat_name)
			Notify.notify(_format_phase_details(pd, hit, cat_name), Notify.Position.TOP_RIGHT, Notify.Style.INFO, 4.0)


const _STATUS_NAMES: Dictionary = {
	"rend": "裂伤",
	"fracture_step": "陷裂",
	"silt_lock": "壅水",
	"weakened": "攻衰",
	"brittle": "脆裂",
	"scorch_mark": "灼痕",
	"overgrow_bind": "蔓缚",
	"cold_damp": "湿寒",
	"smothered": "闷熄",
	"open_fissure": "开隙",
	"steady_step": "稳步",
	"slowed_step": "迟步",
	"hindered_step": "迟滞",
	"guarded_cover": "护持",
}


## 拼接化势详情 BBCode 富文本，供 Notify 右上角显示。
func _format_phase_details(pd: PhaseData, hit: CombatResolver.HitResult, cat_name: String) -> String:
	var lines: Array[String] = []
	lines.append("【%s·%s】" % [cat_name, pd.phase_name])

	var atk_str := "%s×%d" % [ElementColors.element_name(hit.skill_attach_element), hit.skill_attach_amount]
	var tgt_str := "%s×%d" % [ElementColors.element_name(hit.pre_target_element), hit.pre_target_amount]
	lines.append("%s → %s" % [
		ElementColors.bbcode(hit.skill_attach_element, atk_str),
		ElementColors.bbcode(hit.pre_target_element, tgt_str),
	])

	if not is_equal_approx(pd.damage_multiplier, 1.0):
		lines.append("伤害倍率 ×%.2f" % pd.damage_multiplier)
	if hit.phase_bonus_damage > 0:
		lines.append("附加伤害 %d" % hit.phase_bonus_damage)
	if pd.apply_status_id != "":
		var sname: String = _STATUS_NAMES.get(pd.apply_status_id, pd.apply_status_id)
		lines.append("施加【%s】%d回合" % [sname, pd.status_duration])

	return "\n".join(lines)


func _on_skill_button_pressed(index: int) -> void:
	_clear_end_turn_pending()
	select_skill_by_index(index)


func _on_move_button_pressed() -> void:
	_clear_end_turn_pending()
	start_move()


func _get_all_units() -> Array:
	var result: Array = []
	for team: TeamData in teams:
		for unit: Node2D in team.units:
			result.append(unit)
	return result


# ─────────────────────────────────────────────
# 统一接口（UI 和 MCP 共用）
# ─────────────────────────────────────────────

## 通过技能索引选择技能（0~4）。UI 按钮和 MCP 都调用此方法。
func select_skill_by_index(index: int) -> bool:
	if not _can_accept_command():
		return false
	if selected_unit == null or not selected_unit is Unit:
		return false
	var u := selected_unit as Unit
	if u.unit_data == null or index < 0 or index >= u.unit_data.skills.size():
		return false
	select_skill(u.unit_data.skills[index])
	return true


## 进入移动模式。UI 移动按钮和 MCP 都调用此方法。
func start_move() -> bool:
	if not _can_accept_command():
		return false
	if selected_unit == null:
		return false
	if _input_state == InputState.TARGETING_MOVE:
		return true
	if _input_state == InputState.TARGETING_SKILL:
		_clear_skill_targeting()
	_enter_targeting_move()
	return true


## 查询当前游戏状态。返回字典，所有值为原始类型。
func query_state() -> Dictionary:
	var state_names := ["IDLE", "UNIT_SELECTED", "TARGETING_MOVE", "TARGETING_SKILL", "ANIMATING"]
	var team_name := ""
	if current_team_index >= 0 and current_team_index < teams.size():
		team_name = teams[current_team_index].team_name
	var sel_name := ""
	if selected_unit is Unit and selected_unit.combat_stats:
		sel_name = selected_unit.combat_stats.unit_name
	return {
		"input_state": state_names[_input_state] if _input_state < state_names.size() else "UNKNOWN",
		"team_name": team_name,
		"team_index": current_team_index,
		"selected_unit": sel_name,
		"waiting_for_input": _waiting_for_player_input,
	}


## 查询所有单位信息。返回字典数组，所有值为原始类型。
func query_units() -> Array:
	var result: Array = []
	for ti in range(teams.size()):
		var team: TeamData = teams[ti]
		for ui in range(team.units.size()):
			var unit: Node2D = team.units[ui]
			var info: Dictionary = {
				"name": unit.name,
				"cell": [unit.cell.x, unit.cell.y],
				"team_index": ti,
				"team_name": team.team_name,
				"faction": team.faction,
				"has_acted": unit.has_acted,
			}
			if unit is Unit and unit.combat_stats:
				var s: CombatStats = unit.combat_stats
				info["hp"] = s.current_hp
				info["max_hp"] = s.max_hp
				info["ap"] = s.ap_current
				info["ap_max"] = s.ap_max
				info["base_atk"] = s.base_atk
				info["element"] = s.current_element
				info["element_amount"] = s.current_element_amount
				info["is_hero"] = s.is_hero
				info["statuses"] = []
				for st in s.statuses:
					info["statuses"].append({"id": st.status_id, "turns": st.remaining_turns})
				# 技能列表
				var skills_info: Array = []
				if unit.unit_data:
					for si in range(unit.unit_data.skills.size()):
						var sk: SkillData = unit.unit_data.skills[si]
						skills_info.append({
							"index": si,
							"id": sk.skill_id,
							"name": sk.skill_name,
							"ap_cost": sk.ap_cost,
							"can_use": s.can_use_skill(sk),
						})
				info["skills"] = skills_info
			result.append(info)
	return result


## 查询当前可移动范围（TARGETING_MOVE 时有效）。
func query_move_range() -> Array:
	if _input_state != InputState.TARGETING_MOVE:
		return []
	var result: Array = []
	for c in move_overlay.cells:
		result.append([c.x, c.y])
	return result


## 查询技能释放/影响范围（TARGETING_SKILL 时有效）。
func query_skill_range() -> Dictionary:
	if _input_state != InputState.TARGETING_SKILL or _skill_targeting == null:
		return {"cast_cells": [], "effect_cells": []}
	var cast: Array = []
	for c in _skill_targeting._cast_cells:
		cast.append([c.x, c.y])
	var effect: Array = []
	for c in _skill_targeting._effect_cells:
		effect.append([c.x, c.y])
	return {"cast_cells": cast, "effect_cells": effect}


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
