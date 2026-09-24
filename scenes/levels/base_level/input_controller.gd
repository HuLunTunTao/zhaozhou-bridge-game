class_name InputController
extends RefCounted

## 玩家输入状态机组件（Tactics Stack）。
## 从 BaseLevel 抽出：InputState 状态机 / 命令闸门 / hover 反馈 / 移动与技能瞄准流程。
## 通过 setup(level) 持有宿主关卡，对 _level 保持鸭子调用，不反向依赖 BaseLevel。
## 不含技能施放执行（_confirm_targeting_skill 留在 BaseLevel，confirm_cell 鸭子转发）、
## 战斗反馈 UI（3.4/3.5）、网格查询（3.11 LevelQueryAPI，本文件走 _level._xxx 鸭子调用）。

## 输入状态机。LOCKED 表示被外部流程显式锁定（例如自由移动关卡的对话流），与 ANIMATING（基类演出）正交。
enum InputState { IDLE, UNIT_SELECTED, TARGETING_MOVE, TARGETING_SKILL, ANIMATING, LOCKED }

## 单个队伍的运行时数据（真源在 TurnSystem，此处保留旧类型名供注解使用）。
const TeamData = TurnSystem.TeamData

## 关卡生命周期 / 瞬态 overlay 枚举（真源在 LevelStateMachine）。
const LevelPhase = LevelStateMachine.LevelPhase
const ActiveOverlay = LevelStateMachine.ActiveOverlay

var _level: Node = null   # BaseLevel 宿主

var _input_state: InputState = InputState.IDLE
## 当前选中的技能（TARGETING_SKILL 状态时有效）。
var _current_skill: SkillData = null
## 技能范围 Overlay（运行时动态创建）。
var _skill_targeting: Node2D = null
## 当前鼠标 hover 上的 unit（含 boss extra_target_cells 命中），用于驱动单位高亮叠加。
var _hovered_unit: Unit = null
## 当前是否等待玩家输入。
var _waiting_for_player_input: bool = false


func setup(level: Node) -> void:
	_level = level


# ─────────────────────────────────────────────
# 输入事件分发
# ─────────────────────────────────────────────

func handle_unhandled_input(event: InputEvent) -> void:
	if not can_accept_command():
		return
	if event.is_action_pressed("ui_cancel"):
		# ESC：如果当前有选中/瞄准状态，先取消；否则打开设置
		if _input_state != InputState.IDLE:
			cancel_action()
		else:
			_level._on_settings_button_pressed()
		return

	if event is InputEventMouseMotion:
		var hover_cell: Vector2i = _level.tilemap.local_to_map(_level.tilemap.get_local_mouse_position())
		preview_cell(hover_cell)
		return

	if not (event is InputEventMouseButton and event.pressed):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		# 左键确认：选择单位 / 移动 / 释放技能
		var clicked_cell: Vector2i = _level.tilemap.local_to_map(_level.tilemap.get_local_mouse_position())
		confirm_cell(clicked_cell)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		# 右键取消：移动或技能瞄准状态下回到选中状态
		if _input_state == InputState.TARGETING_MOVE or _input_state == InputState.TARGETING_SKILL:
			cancel_action()


## 是否允许接收玩家命令。双轴状态机 + 既有子状态的联合闸门（真源在 LevelStateMachine）。
func can_accept_command() -> bool:
	return _level._state._can_accept_command()


## 输入相关通知处理（鼠标离屏清 hover 等）。
func handle_notification(what: int) -> void:
	if what == Node.NOTIFICATION_WM_MOUSE_EXIT and _level.hover_overlay != null:
		_level.hover_overlay.set_visible_state(false)
		_update_hovered_unit(Vector2i(-9999, -9999))


# ─────────────────────────────────────────────
# 命令函数
# ─────────────────────────────────────────────

## MCP 兼容：接受两个 int 参数。
func preview_cell_xy(x: int, y: int) -> void:
	preview_cell(Vector2i(x, y))


func preview_cell(cell: Vector2i) -> void:
	# Hover 框 / 单位高亮独立于命令闸门——观察反馈在 PLAYING 期间始终给出。
	_update_hover_visual(cell)
	if not can_accept_command():
		return
	match _input_state:
		InputState.TARGETING_MOVE:
			_level.move_overlay.update_path(cell)
		InputState.TARGETING_SKILL:
			if _skill_targeting:
				_skill_targeting.update_hover(cell)


## MCP 兼容：接受两个 int 参数。
func confirm_cell_xy(x: int, y: int) -> void:
	confirm_cell(Vector2i(x, y))


## 确认：点击某格执行对应操作。
func confirm_cell(cell: Vector2i) -> void:
	if not can_accept_command():
		return
	var local_mouse: Vector2 = _level.tilemap.map_to_local(cell) if _level.tilemap else Vector2.ZERO
	var current_team: TeamData = _level.teams[_level.current_team_index] if _level.current_team_index >= 0 else null
	if current_team == null:
		return

	match _input_state:
		InputState.IDLE, InputState.UNIT_SELECTED:
			confirm_idle(cell, local_mouse, current_team)
		InputState.TARGETING_MOVE:
			confirm_targeting_move(cell, local_mouse, current_team)
		InputState.TARGETING_SKILL:
			# 技能施放执行暂留 BaseLevel（3.4 SkillCastController 收编），此处鸭子转发
			_level._confirm_targeting_skill(cell)


## 取消：回到 IDLE，完全取消选中。
func cancel_action() -> void:
	if not can_accept_command():
		return
	_level._clear_end_turn_pending()
	if _input_state == InputState.TARGETING_SKILL:
		clear_skill_targeting()
	if _input_state != InputState.IDLE:
		go_idle()


## 选择技能，进入 TARGETING_SKILL 状态。
func select_skill(skill: SkillData) -> void:
	if not can_accept_command():
		return
	if _level.selected_unit == null or not _level.selected_unit is Unit:
		return
	var unit := _level.selected_unit as Unit
	if unit.combat_stats == null or not unit.combat_stats.can_use_skill(skill):
		return
	_level._clear_end_turn_pending()
	_show_skill_targeting_for(unit, skill)


func _show_skill_targeting_for(unit: Unit, skill: SkillData) -> void:
	_current_skill = skill
	_level.move_overlay.clear_range()
	if _skill_targeting:
		var enemy_cells: Array[Vector2i] = []
		var caster_faction: String = unit.faction if "faction" in unit else ""
		for t: TeamData in _level.teams:
			if t.faction != caster_faction:
				for eu: Node2D in t.units:
					enemy_cells.append(eu.cell)
					if eu is Unit:
						for offset in (eu as Unit).extra_target_cells:
							enemy_cells.append(eu.cell + offset)
		_skill_targeting.show_skill_range(_level.tilemap, skill, unit.cell, enemy_cells)
	_input_state = InputState.TARGETING_SKILL


func go_idle() -> void:
	_level.selected_unit = null
	_level.unit_selected = false
	_current_skill = null
	_level.move_overlay.clear_range()
	clear_skill_targeting()
	_input_state = InputState.IDLE
	_level._reset_status_bar()
	_level.selection_changed.emit(null)


func confirm_idle(cell: Vector2i, _local_mouse: Vector2, current_team: TeamData) -> void:
	_level._clear_end_turn_pending()
	# 检查点击格子上是否有当前队伍的可行动单位
	var clicked_unit: Node2D = _level._get_unit_at_cell(cell, current_team)
	if clicked_unit != null and clicked_unit is Unit:
		var u := clicked_unit as Unit
		if not u.has_acted and not u.is_moving:
			_level.selected_unit = u
			_level.unit_selected = true
			_input_state = InputState.UNIT_SELECTED
			_level._update_status_bar_for_unit(u, true)
			_level.selection_changed.emit(u)
			enter_targeting_move()
			return
	# 检查是否点击了其他队伍的单位（仅显示信息）
	for team: TeamData in _level.teams:
		var unit_on_cell: Node2D = _level._get_unit_at_cell(cell, team)
		if unit_on_cell != null:
			_level._update_status_bar_for_unit(unit_on_cell, false)
			return
	_level._reset_status_bar()


func enter_targeting_move() -> void:
	if _level.selected_unit == null:
		return
	_input_state = InputState.TARGETING_MOVE
	var unit: Node2D = _level.selected_unit
	if unit is Unit and unit.combat_stats != null:
		var stats: CombatStats = unit.combat_stats
		if not stats.can_move():
			return
		var friendly: Array[Vector2i] = _level._get_friendly_cells_except(unit)
		var enemy: Array[Vector2i] = _level._get_enemy_cells_except(unit)
		# 每格消耗 = 基础消耗 + 状态修正
		var effective_cost := stats.move_cost_per_tile + stats.get_move_ap_modifier()
		var ap_budget: int = _level.DEBUG_INFINITE_AP_BUDGET if stats.has_infinite_actions() else stats.ap_current
		_level.move_overlay.show_range_ap(_level.tilemap, _level.movement_manager, unit.cell, ap_budget, effective_cost, friendly, enemy)
	else:
		_level.move_overlay.show_range(_level.tilemap, _level.movement_manager, unit.cell, unit.movement_points)


func confirm_targeting_move(cell: Vector2i, local_mouse: Vector2, current_team: TeamData) -> void:
	_level._clear_end_turn_pending()
	if _level.selected_unit == null:
		go_idle()
		return

	if _level.move_overlay.has_cell(cell):
		# 移动到目标格
		var path: Array[Vector2i] = _level.move_overlay.get_path_to_cell(cell)
		var ap_cost: int = _level.move_overlay.get_cost_to_cell(cell)
		_level.move_overlay.clear_range()
		var moving_unit: Node2D = _level.selected_unit
		_input_state = InputState.ANIMATING
		moving_unit.move_along_path(path, _level.tilemap)
		await moving_unit.move_finished
		if _level == null or not is_instance_valid(_level):
			return
		# TODO: 替换为实际脚步声资源
		# SfxManager.play_sfx(preload("res://assets/audio/sfx/footstep.wav"), "SFX")
		# 扣除 AP
		if moving_unit is Unit and moving_unit.combat_stats != null:
			var from_cell := path[0]
			if not moving_unit.combat_stats.has_infinite_actions():
				moving_unit.combat_stats.ap_current -= ap_cost
			moving_unit.combat_stats.moves_used += 1
			CombatLog.log_unit_move(moving_unit.combat_stats.unit_name, from_cell, cell, ap_cost, moving_unit.combat_stats.ap_current)
			moving_unit.refresh_overhead_bars()
		_level._on_unit_moved()
		_level.unit_move_completed.emit(moving_unit as Unit)
		# AP 剩余且还能行动？回到 UNIT_SELECTED
		if moving_unit is Unit and moving_unit.combat_stats != null:
			var stats: CombatStats = moving_unit.combat_stats
			var ec: Dictionary = _level._get_enemy_cell_set(moving_unit.faction)
			if _level._has_action_budget(stats) and (stats.can_move() or _level._has_usable_attack(moving_unit, ec)):
				_level.selected_unit = moving_unit
				_level.unit_selected = true
				_input_state = InputState.UNIT_SELECTED
				_level._update_status_bar_for_unit(moving_unit, true)
				_level.selection_changed.emit(moving_unit)
				# 自动重新进入移动模式
				if stats.can_move():
					enter_targeting_move()
				return
		# 否则该单位行动结束
		moving_unit.has_acted = true
		go_idle()
	else:
		# 点击范围外：检查是否点击了其他友方单位，切换选中
		go_idle()
		if current_team:
			confirm_idle(cell, local_mouse, current_team)


# ─────────────────────────────────────────────
# 技能瞄准（施放执行在 BaseLevel._confirm_targeting_skill）
# ─────────────────────────────────────────────

func setup_skill_targeting() -> void:
	var SkillTargetingScript := preload("res://scripts/combat/skill_targeting.gd")
	var st := Node2D.new()
	st.set_script(SkillTargetingScript)
	st.name = "SkillTargeting"
	_level.add_child(st)
	_skill_targeting = st


func clear_skill_targeting() -> void:
	if _skill_targeting and _skill_targeting.has_method("clear"):
		_skill_targeting.clear()
	_current_skill = null


# ─────────────────────────────────────────────
# 统一接口（UI 和 MCP 共用）
# ─────────────────────────────────────────────

func on_skill_button_pressed(index: int) -> void:
	_level._clear_end_turn_pending()
	select_skill_by_index(index)


func on_move_button_pressed() -> void:
	_level._clear_end_turn_pending()
	start_move()


## 通过技能索引选择技能（0~4）。UI 按钮和 MCP 都调用此方法。
func select_skill_by_index(index: int) -> bool:
	if not can_accept_command():
		return false
	if _level.selected_unit == null or not _level.selected_unit is Unit:
		return false
	var u := _level.selected_unit as Unit
	if u.unit_data == null or index < 0 or index >= u.unit_data.skills.size():
		return false
	select_skill(u.unit_data.skills[index])
	return true


## 进入移动模式。UI 移动按钮和 MCP 都调用此方法。
func start_move() -> bool:
	if not can_accept_command():
		return false
	if _level.selected_unit == null:
		return false
	if _input_state == InputState.TARGETING_MOVE:
		return true
	if _input_state == InputState.TARGETING_SKILL:
		clear_skill_targeting()
	enter_targeting_move()
	return true


# ─────────────────────────────────────────────
# Hover 反馈
# ─────────────────────────────────────────────

## 鼠标 hover 反馈：白色脉冲框 + 命中 unit 的 modulate 脉动。
## 在 preview_cell / 模态面板开关 / 鼠标离屏处统一调度。
func _update_hover_visual(cell: Vector2i) -> void:
	if _level.hover_overlay == null:
		return
	var should_show := _should_show_hover(cell)
	_level.hover_overlay.set_hover(cell, _level.tilemap)
	_level.hover_overlay.set_visible_state(should_show)
	# 单位本体高亮复用 extra_target_cells 命中逻辑；不要被"当前格是否可画 hover 框"限制，
	# 否则 1-4 Boss 这类受击范围落在非行走层时不会触发本体白色闪烁。
	_update_hovered_unit(cell if _should_update_hovered_unit() else Vector2i(-9999, -9999))


func _should_show_hover(cell: Vector2i) -> bool:
	if _level._level_phase != LevelPhase.PLAYING:
		return false
	if _level._active_overlay != ActiveOverlay.NONE:
		return false
	if _level.tilemap == null:
		return false
	if _input_state == InputState.ANIMATING or _input_state == InputState.LOCKED:
		return false
	if _level.tilemap.get_cell_source_id(cell) == -1:
		return false
	return true


func _should_update_hovered_unit() -> bool:
	if _level._level_phase != LevelPhase.PLAYING:
		return false
	if _level._active_overlay != ActiveOverlay.NONE:
		return false
	if _level.tilemap == null:
		return false
	if _input_state == InputState.ANIMATING or _input_state == InputState.LOCKED:
		return false
	return true


## 维护"鼠标当前 hover 的单位"。切换时调旧的关高亮、新的开高亮。
## 支持 boss 多格：cell 命中 extra_target_cells 任一格视为命中本体。
func _update_hovered_unit(cell: Vector2i) -> void:
	var unit: Unit = _find_unit_under_cell(cell)
	if unit == _hovered_unit:
		return
	if _hovered_unit != null and is_instance_valid(_hovered_unit):
		_hovered_unit.set_hover_highlight(false)
	_hovered_unit = unit
	if unit != null:
		unit.set_hover_highlight(true)


func _find_unit_under_cell(cell: Vector2i) -> Unit:
	for u in _level._get_all_units():
		if not is_instance_valid(u) or not (u is Unit):
			continue
		var unit := u as Unit
		if unit.cell == cell:
			return unit
		for offset in unit.extra_target_cells:
			if unit.cell + offset == cell:
				return unit
	return null
