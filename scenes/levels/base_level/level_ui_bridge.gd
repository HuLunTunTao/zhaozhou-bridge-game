class_name LevelUIBridge
extends RefCounted

## UI 桥接组件（Tactics Stack）。
## 从 BaseLevel 抽出：状态栏联动 / 回合标签 / 选中指示器 / 阶段通知 / debug UI /
## 无限 AP 调试 / 面板按钮回调 / 胜负按钮 / 难度 UI / BGM / 技能 targeting 管理。
## 通过 setup(level) 持有宿主关卡，对 _level 保持鸭子调用，不反向依赖 BaseLevel。
## 不含 overlay 闸门（_open_overlay / _close_overlay / has_overlay 留在 BaseLevel）、
## 对话桥接（play_dialogue 等）、战斗反馈（_show_combat_feedback 在 SkillCastController）。

## 输入状态机（真源在 InputController，此处保留旧名供注解使用）。
const InputState = InputController.InputState

## overlay 枚举（真源在 LevelStateMachine，此处保留旧名供注解使用）。
const ActiveOverlay = LevelStateMachine.ActiveOverlay

var _level: Node = null   # BaseLevel 宿主


func setup(level: Node) -> void:
	_level = level


# ─────────────────────────────────────────────
# BGM / debug UI
# ─────────────────────────────────────────────

func play_level_bgm() -> void:
	var path: String = _level.LEVEL_BGM_BY_LEVEL.get(GameState.selected_level, "")
	if path.is_empty() or not ResourceLoader.exists(path, "AudioStream"):
		return
	var stream: AudioStream = load(path)
	if stream != null:
		BgmManager.play(stream)


func refresh_debug_ui() -> void:
	if _level.win_button:
		_level.win_button.visible = Settings.debug_mode
	if _level.infinite_ap_button_label:
		_level.infinite_ap_button_label.visible = Settings.debug_mode
	if _level.infinite_ap_button_button:
		_level.infinite_ap_button_button.disabled = not Settings.debug_mode
		if not Settings.debug_mode and _level._infinite_ally_actions_enabled:
			_level.infinite_ap_button_button.set_pressed_no_signal(false)
			set_infinite_ally_actions_enabled(false)


func on_infinite_ap_button_toggled(enabled: bool) -> void:
	if not Settings.debug_mode:
		if _level.infinite_ap_button_button:
			_level.infinite_ap_button_button.set_pressed_no_signal(false)
		return
	set_infinite_ally_actions_enabled(enabled)


func set_infinite_ally_actions_enabled(enabled: bool) -> void:
	if _level._infinite_ally_actions_enabled == enabled:
		return
	_level._infinite_ally_actions_enabled = enabled
	for unit in _level._get_all_units():
		if unit is Unit:
			apply_infinite_ally_actions_to_unit(unit)
	refresh_difficulty_dependent_ui()
	Notify.notify(
		"友方无限AP已%s" % ("开启" if enabled else "关闭"),
		Notify.Position.TOP_CENTER,
		Notify.Style.SUCCESS if enabled else Notify.Style.INFO,
		2.0,
	)


func apply_infinite_ally_actions_to_unit(unit: Unit) -> void:
	if unit == null or unit.combat_stats == null:
		return
	var stats: CombatStats = unit.combat_stats
	stats.debug_infinite_actions = _level._infinite_ally_actions_enabled and stats.camp == Enums.Camp.ALLY
	if stats.has_infinite_actions():
		stats.ap_current = stats.ap_max
	if unit.has_method("refresh_overhead_bars"):
		unit.refresh_overhead_bars()


# ─────────────────────────────────────────────
# 选中指示器 / 阶段通知 / 回合标签 / 状态栏
# ─────────────────────────────────────────────

func setup_selection_indicator() -> void:
	_level._selection_indicator = Line2D.new()
	# 放大菱形尺寸（原 16→24），线条加粗，颜色更亮
	_level._selection_indicator.points = PackedVector2Array([-24, 0, 0, 12, 24, 0, 0, -12, -24, 0])
	_level._selection_indicator.width = 2.5
	_level._selection_indicator.default_color = Color(1.0, 0.95, 0.3, 1.0)
	_level._selection_indicator.z_index = -1
	_level._selection_indicator.visible = false
	_level.add_child(_level._selection_indicator)
	var tween := _level.create_tween().set_loops()
	tween.tween_property(_level._selection_indicator, "modulate:a", 0.45, 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_level._selection_indicator, "modulate:a", 1.0, 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func setup_phase_notification() -> void:
	_level._phase_notification = PhaseNotification.new()
	_level.gui.add_child(_level._phase_notification)


func update_round_label(round_num: int) -> void:
	if _level._round_label == null:
		return
	_level._round_label.text = "第 %d 回合" % round_num


## 更新状态栏显示指定单位的信息。
func update_status_bar_for_unit(unit: Node2D, is_active: bool = false) -> void:
	_level._status_bar_bridge.show_unit_for(unit, is_active)


## 状态栏回退显示主角。
func reset_status_bar() -> void:
	_level._status_bar_bridge.reset_to_hero()


# ─────────────────────────────────────────────
# 面板按钮回调 / 胜负按钮
# ─────────────────────────────────────────────

func on_settings_button_pressed() -> void:
	if _level.has_overlay():
		return
	var panel: SettingsPanel = _level.SettingsPanelScene.instantiate()
	panel.show_back_to_menu = true
	_level._open_overlay(ActiveOverlay.SETTINGS, panel)


func on_tutorial_button_pressed() -> void:
	if _level.has_overlay():
		return
	var panel: Node = _level.TutorialPanelScene.instantiate()
	_level._open_overlay(ActiveOverlay.TUTORIAL_PANEL, panel)


func on_objectives_button_pressed() -> void:
	show_objectives()


func on_progress_button_pressed() -> void:
	if _level.has_overlay():
		return
	var panel: Node = _level.ProgressPanelScene.instantiate()
	panel.set("show_debug_controls", Settings.debug_mode)
	_level._open_overlay(ActiveOverlay.PROGRESS, panel)
	UiSounds.play_popup()


## 弹出本关目标面板（战斗中按 🎯 按钮查看）。初始 BRIEFING 的面板由 _begin_initial_briefing 负责。
func show_objectives() -> void:
	if _level.has_overlay():
		return
	var obj: Dictionary = _level.get_objectives_text()
	if obj["victory"].is_empty() and obj["defeat"].is_empty() and obj.get("details", []).is_empty():
		return
	var panel: ObjectivesPanel = _level.ObjectivesPanelScene.instantiate()
	panel.victory_lines = obj["victory"]
	panel.defeat_lines = obj["defeat"]
	panel.detail_lines = obj.get("details", [])
	_level._open_overlay(ActiveOverlay.OBJECTIVES_REVIEW, panel)


# 用于测试的一键胜利按钮
func on_win_button_pressed() -> void:
	_level.complete_level()


func on_defeat_retry() -> void:
	_level.get_tree().reload_current_scene()


func on_defeat_main_menu() -> void:
	GameState.transition_to_scene("res://scenes/menu/main_menu.tscn")


# ─────────────────────────────────────────────
# 难度 UI / 技能 targeting 管理
# ─────────────────────────────────────────────

## 难度变化时，按比例重算所有存活单位的 max_hp / ap_max / base_atk。
## 自由移动关卡（验桥日）跳过——hero 的 HERO_INFINITE_AP 不能被系数缩水。
func on_difficulty_changed(_id: String) -> void:
	if _level.is_free_roam_level():
		return
	for unit in _level._get_all_units():
		if unit == null or not is_instance_valid(unit):
			continue
		var stats: CombatStats = unit.combat_stats
		if stats == null:
			continue
		stats.apply_difficulty_multipliers()
		if unit.has_method("refresh_overhead_bars"):
			unit.refresh_overhead_bars()
	refresh_difficulty_dependent_ui()


func refresh_difficulty_dependent_ui() -> void:
	var display_unit: Node2D = null
	if _level.selected_unit != null and is_instance_valid(_level.selected_unit):
		display_unit = _level.selected_unit
	elif _level.status_bar and _level.status_bar.has_method("get_current_unit"):
		display_unit = _level.status_bar.get_current_unit()

	var selected_is_active := false
	if _level.selected_unit != null and is_instance_valid(_level.selected_unit) and _level.selected_unit is Unit:
		var selected_stats: CombatStats = (_level.selected_unit as Unit).combat_stats
		selected_is_active = selected_stats != null and selected_stats.is_alive() and _level._input_state != InputState.IDLE

	if display_unit != null and is_instance_valid(display_unit):
		update_status_bar_for_unit(display_unit, display_unit == _level.selected_unit and selected_is_active)
	else:
		reset_status_bar()

	if _level.selected_unit == null or not is_instance_valid(_level.selected_unit) or not (_level.selected_unit is Unit):
		_level.move_overlay.clear_range()
		clear_skill_targeting()
		return

	var unit := _level.selected_unit as Unit
	var stats: CombatStats = unit.combat_stats
	if stats == null or not stats.is_alive():
		_level.move_overlay.clear_range()
		clear_skill_targeting()
		return

	match _level._input_state:
		InputState.TARGETING_MOVE:
			if stats.can_move():
				_level._enter_targeting_move()
			else:
				_level.move_overlay.clear_range()
				_level._input_state = InputState.UNIT_SELECTED
		InputState.TARGETING_SKILL:
			var skill: SkillData = _level._current_skill
			clear_skill_targeting()
			if skill != null and stats.can_use_skill(skill):
				_level._show_skill_targeting_for(unit, skill)
			else:
				_level._input_state = InputState.UNIT_SELECTED


func setup_skill_targeting() -> void:
	_level._get_input_controller().setup_skill_targeting()


func clear_skill_targeting() -> void:
	_level._get_input_controller().clear_skill_targeting()
