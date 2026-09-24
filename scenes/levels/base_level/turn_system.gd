class_name TurnSystem
extends RefCounted

## 回合系统组件（Tactics Stack）。
## 从 BaseLevel 抽出：TeamData / 回合流转（init → start → end）/ 结束回合双击 / 回合成长问询。
## 通过 setup(level) 持有宿主关卡，对 _level 保持鸭子调用，不反向依赖 BaseLevel。
## 不含 AI 回合执行（_run_ai_turn 留在 BaseLevel，由 start_team_turn 触发）、输入处理、技能施放。

const GrowthChoicePanelScript := preload("res://scenes/ui/growth_choice_panel.gd")

## 结束回合按钮高亮配置（"待确认"态）。
const _END_TURN_HIGHLIGHT_MODULATE: Color = Color(1.8, 1.1, 0.4, 1.0)
## 边框颜色偏近白，被 modulate 乘完后正好变成更亮的暖橙，和按钮面形成层次。
const _END_TURN_HIGHLIGHT_BORDER_COLOR: Color = Color(1.0, 0.95, 0.85, 1.0)
const _END_TURN_HIGHLIGHT_BORDER_WIDTH: int = 3
const _END_TURN_HIGHLIGHT_STATES: Array[String] = ["normal", "hover", "pressed", "focus"]

## 波次刷新敌人时的镜头演出：锁定到刷新单位的中心，拉近，停留后解锁。
const _WAVE_CAMERA_ZOOM: float = 1.4
const _WAVE_CAMERA_SETTLE_TIME: float = 0.4
const _WAVE_CAMERA_LINGER_TIME: float = 0.8


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


var _level: Node = null   # BaseLevel 宿主

## 结束回合的待确认状态：第一次点击已登记，等待第二次确认。
var _end_turn_pending_confirm: bool = false
## 已选过回合成长的大回合号（每大回合只问一次）。
var _round_growth_selected_rounds: Array[int] = []


func setup(level: Node) -> void:
	_level = level


# ─────────────────────────────────────────────
# 回合系统初始化
# ─────────────────────────────────────────────

func init_turn_system() -> void:
	if _level.is_free_roam_level():
		return
	# 若未通过 get_teams_config() 创建队伍，则将旧版 player 包装为单队伍
	if _level.teams.is_empty() and _level.hero:
		var team := TeamData.new("玩家", "", "player")
		team.units.append(_level.hero)
		_level.teams.append(team)

	if _level.teams.is_empty():
		return

	start_team_turn(0)


# ─────────────────────────────────────────────
# 回合流转
# ─────────────────────────────────────────────

func start_team_turn(index: int) -> void:
	if _level.is_phase_ended():
		return
	_level.current_team_index = index
	var team: TeamData = _level.teams[index]
	CombatLog.msg("═══ %s 的回合开始 ═══" % team.team_name)
	_level.team_turn_started.emit(index)
	# 波次生成：在每大回合第一个队伍开始时处理
	if index == 0:
		var spawned: Array[Unit] = _level._process_wave(_level.round_number)
		# 第一回合不播镜头演出（初始敌人已在场）；后续波次刷新时聚焦新敌人
		if not spawned.is_empty() and _level.round_number > 1:
			await _camera_focus_spawned(spawned)
			if _level == null or not is_instance_valid(_level) or _level.is_phase_ended():
				return
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
	_level.move_overlay.clear_range()

	_animate_turn_label(team.team_name)

	if team.controller == "ai":
		if _level._end_turn_button:
			_level._end_turn_button.visible = false
		_level._waiting_for_player_input = false
		# 延迟一帧再执行 AI，确保 UI 更新后再开始移动
		_level._run_ai_turn.call_deferred(team)
	else:
		if _level._end_turn_button:
			_level._end_turn_button.visible = true
		_end_turn_pending_confirm = false
		set_end_turn_button_highlight(false)
		_level._waiting_for_player_input = true
		UiSounds.play_turn_start()
		# 玩家回合开始时把镜头平滑拉到主角，给本回合一个明确的起点。
		_focus_camera_on_team(team)
		# 玩家回合开始时刷新状态栏，确保显示 AP 恢复后的最新数据
		_level._reset_status_bar()


## 结束整个队伍的回合。UI"结束回合"按钮和 MCP 都调用此方法。
func end_team_turn() -> void:
	if _level.current_team_index < 0 or _level.current_team_index >= _level.teams.size():
		return
	var team: TeamData = _level.teams[_level.current_team_index]
	if team.controller == "player" and not _level._waiting_for_player_input:
		return
	if _level._active_overlay == LevelStateMachine.ActiveOverlay.CUTSCENE:
		return
	do_end_turn()


## 回合结束的实际逻辑。内部和 AI 也调用此方法。
func do_end_turn() -> void:
	clear_end_turn_pending()
	if _level.current_team_index >= 0 and _level.current_team_index < _level.teams.size():
		var team: TeamData = _level.teams[_level.current_team_index]
		for unit: Node2D in team.units.duplicate():
			if unit is Unit and unit.combat_stats != null and unit.combat_stats.is_alive():
				var hp_before_dot: int = unit.combat_stats.current_hp
				var dot: int = unit.combat_stats.process_turn_end()
				var hp_after_dot: int = unit.combat_stats.current_hp
				if dot > 0:
					var popup := DamagePopup.new()
					_level.add_child(popup)
					popup.show_at(unit.global_position, dot)
					_level.unit_hp_changed.emit(unit, hp_before_dot, hp_after_dot)
					if hp_after_dot <= 0:
						_level.unit_died.emit(unit)
				if team.controller == "player" and unit.combat_stats.is_alive():
					var hp_before_rest: int = unit.combat_stats.current_hp
					unit.combat_stats.rest_recovery()
					var hp_after_rest: int = unit.combat_stats.current_hp
					if hp_before_rest != hp_after_rest:
						_level.unit_hp_changed.emit(unit, hp_before_rest, hp_after_rest)
				(unit as Unit).refresh_overhead_bars()
		# 回合结束后恢复外观，避免进入对方回合时仍显示灰色
		for unit: Node2D in team.units:
			unit.has_acted = false
	_level._go_idle()
	_level._waiting_for_player_input = false
	if _level._end_turn_button:
		_level._end_turn_button.visible = false
	var next_index: int = (_level.current_team_index + 1) % _level.teams.size()
	# 先广播当前小回合结束，给 ChatterScheduler / 教程脚本等挂钩
	_level.team_turn_ended.emit(_level.current_team_index)
	if next_index == 0:
		# 大回合也到头了：先 emit round_ended（旧回合号），再推进 round_number
		_level.round_ended.emit(_level.round_number)
		_level.round_number += 1
		_level.round_started.emit(_level.round_number)
	start_team_turn(next_index)


# ─────────────────────────────────────────────
# 结束回合双击
# ─────────────────────────────────────────────

func on_end_turn_button_pressed() -> void:
	# 队伍已经没得做了 → 直接结束，跳过确认
	if not _level._player_team_has_remaining_actions():
		_end_turn_pending_confirm = false
		set_end_turn_button_highlight(false)
		end_team_turn()
		return
	# 第一次点击 → 进入待确认并高亮
	if not _end_turn_pending_confirm:
		_end_turn_pending_confirm = true
		set_end_turn_button_highlight(true)
		return
	# 第二次点击 → 真正结束
	_end_turn_pending_confirm = false
	set_end_turn_button_highlight(false)
	end_team_turn()


## 结束回合按钮高亮切换（"待确认"态）。
func set_end_turn_button_highlight(highlight: bool) -> void:
	if _level._end_turn_button == null:
		return
	if highlight:
		# 暖橙色 modulate + 各状态的 StyleBoxFlat 描边。两层叠加，底色再暗也看得见。
		_level._end_turn_button.modulate = _END_TURN_HIGHLIGHT_MODULATE
		for state in _END_TURN_HIGHLIGHT_STATES:
			var base: StyleBox = _level._end_turn_button.get_theme_stylebox(state)
			var style: StyleBoxFlat
			if base is StyleBoxFlat:
				style = (base as StyleBoxFlat).duplicate() as StyleBoxFlat
			else:
				style = StyleBoxFlat.new()
				style.bg_color = Color(0.15, 0.15, 0.18, 0.95)
				style.set_corner_radius_all(3)
			style.border_color = _END_TURN_HIGHLIGHT_BORDER_COLOR
			style.set_border_width_all(_END_TURN_HIGHLIGHT_BORDER_WIDTH)
			_level._end_turn_button.add_theme_stylebox_override(state, style)
	else:
		_level._end_turn_button.modulate = _level._end_turn_button_default_modulate
		for state in _END_TURN_HIGHLIGHT_STATES:
			_level._end_turn_button.remove_theme_stylebox_override(state)


## 取消"待确认结束回合"状态。被任何玩家的其他操作入口调用。
func clear_end_turn_pending() -> void:
	if _end_turn_pending_confirm:
		_end_turn_pending_confirm = false
		set_end_turn_button_highlight(false)


# ─────────────────────────────────────────────
# 回合成长问询
# ─────────────────────────────────────────────

func try_prompt_round_growth() -> bool:
	if _level._active_overlay == LevelStateMachine.ActiveOverlay.GROWTH_CHOICE:
		return true
	if _level.current_team_index < 0 or _level.current_team_index >= _level.teams.size():
		return false
	var team: TeamData = _level.teams[_level.current_team_index]
	if team.controller != "player":
		return false
	if not _is_player_side_ending_turn():
		return false
	if _level.round_number in _round_growth_selected_rounds:
		return false
	var options: Array[Dictionary] = _level.get_round_growth_options()
	if options.is_empty():
		return false
	var panel := GrowthChoicePanelScript.new()
	panel.panel_title = "回合成长"
	panel.options = options
	panel.required_selection_count = 3
	panel.options_confirmed.connect(_on_round_growth_options_confirmed)
	if not _level._open_overlay(LevelStateMachine.ActiveOverlay.GROWTH_CHOICE, panel, &"options_confirmed"):
		panel.queue_free()
		return false
	return true


func _on_round_growth_options_confirmed(option_ids: Array[String]) -> void:
	if _level.round_number not in _round_growth_selected_rounds:
		_round_growth_selected_rounds.append(_level.round_number)
	for option_id in option_ids:
		_level.apply_round_growth_option(option_id)
	do_end_turn()


func _is_player_side_ending_turn() -> bool:
	if _level.current_team_index < 0 or _level.current_team_index >= _level.teams.size():
		return false
	var next_index: int = (_level.current_team_index + 1) % _level.teams.size()
	if next_index < _level.teams.size() and _level.teams[next_index].controller == "player":
		return false
	return true


# ─────────────────────────────────────────────
# 回合 UI / 镜头演出
# ─────────────────────────────────────────────

## 回合标签"弹入"动画：从 1.4 倍+透明缩放到正常+不透明。
func _animate_turn_label(team_name: String) -> void:
	if _level._turn_label == null:
		return
	_level._turn_label.text = "[ %s 的回合 ]" % team_name
	_level._turn_label.pivot_offset = _level._turn_label.size / 2
	_level._turn_label.scale = Vector2(1.4, 1.4)
	_level._turn_label.modulate = Color(1, 1, 1, 0)
	var tween := _level.create_tween()
	tween.tween_property(_level._turn_label, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_level._turn_label, "scale", Vector2.ONE, 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


## 波次刷新敌人时的镜头演出：锁定到刷新单位的中心，拉近，停留后解锁。
func _camera_focus_spawned(spawned: Array[Unit]) -> void:
	var lv_camera := _level.camera as LevelCamera
	if lv_camera == null:
		return
	# 计算所有刷新单位的中心点
	var center := Vector2.ZERO
	var count := 0
	for u in spawned:
		if is_instance_valid(u):
			center += u.global_position
			count += 1
	if count == 0:
		return
	center /= count
	# 用临时节点作为锁定目标
	var marker := Node2D.new()
	_level.add_child(marker)
	marker.global_position = center
	lv_camera.lock_on(marker, _WAVE_CAMERA_ZOOM)
	await _level.get_tree().create_timer(_WAVE_CAMERA_SETTLE_TIME).timeout
	if _level == null or not is_instance_valid(_level):
		return
	await _level.get_tree().create_timer(_WAVE_CAMERA_LINGER_TIME).timeout
	if _level == null or not is_instance_valid(_level):
		return
	lv_camera.unlock()
	marker.queue_free()


## 把镜头平滑拉到队伍"代表单位"（优先 hero，否则队里第一个存活单位）。
## 仅修改 target_position，不锁定相机，玩家仍可随时手动平移/缩放。
func _focus_camera_on_team(team: TeamData) -> void:
	if _level.camera == null:
		return
	var lv_camera := _level.camera as LevelCamera
	if lv_camera == null:
		return
	var focus_unit: Node2D = null
	if _level.hero != null and is_instance_valid(_level.hero) and _level.hero in team.units:
		var hu := _level.hero as Unit
		if hu == null or hu.combat_stats == null or hu.combat_stats.is_alive():
			focus_unit = _level.hero
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
