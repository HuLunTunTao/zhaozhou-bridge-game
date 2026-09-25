class_name LevelFlow
extends RefCounted

## 关卡胜负流程组件（Tactics Stack）。
## 从 BaseLevel 抽出：中场剧情 / 通关结算（成长选择面板 + Progress 落盘 + 切场景）/ 失败面板。
## 通过 setup(level) 持有宿主关卡，对 _level 保持鸭子调用，不反向依赖 BaseLevel。
## 不含胜负条件检查（check_win_lose 在 ObjectivesTracker）、
## 胜负按钮薄壳（_on_win_button_pressed / _on_defeat_retry / _on_defeat_main_menu 在 LevelUIBridge）。

## 关卡生命周期粗粒度时间线（真源在 LevelStateMachine，此处保留旧名供注解使用）。
const LevelPhase = LevelStateMachine.LevelPhase

## 当前独占前景的瞬态 UI（真源在 LevelStateMachine，此处保留旧名供注解使用）。
const ActiveOverlay = LevelStateMachine.ActiveOverlay

const GrowthChoicePanelScript := preload("res://scenes/ui/growth_choice_panel.gd")

var _level: Node = null   # BaseLevel 宿主


func setup(level: Node) -> void:
	_level = level


## Play a mid-battle cutscene as an overlay. Blocks until finished.
func play_mid_cutscene(pages: Array) -> void:
	var cutscene: CutscenePlayer = preload("res://scenes/cutscene/cutscene_player.tscn").instantiate()
	cutscene.setup(pages)
	if not _level._open_overlay(ActiveOverlay.CUTSCENE, cutscene, &"cutscene_finished"):
		cutscene.queue_free()
		return
	await cutscene.cutscene_finished


## Call when the level is won. Handles post-cutscene or returns to menu.
## 幂等：phase 已 ENDED 时直接返回，防止重复副作用（Progress.complete_level / 切场景等）。
func complete_level() -> void:
	if _level.is_phase_ended():
		return
	_level._set_phase(LevelPhase.ENDED)
	UiSounds.play_victory()
	var level := GameState.selected_level
	var growth_options: Array[Dictionary] = _level.get_post_level_growth_options()
	if not growth_options.is_empty() and not Progress.has_level_growth_choices(level):
		var panel := GrowthChoicePanelScript.new()
		panel.panel_title = "结算成长"
		panel.options = growth_options
		panel.required_selection_count = 3
		panel.options_confirmed.connect(func(option_ids: Array[String]):
			Progress.complete_level(level, option_ids)
			var chosen_names: Array[String] = []
			for option_id in option_ids:
				chosen_names.append(Progress.get_growth_option_name(option_id))
			if not chosen_names.is_empty():
				Notify.success("已选择结算成长：%s" % "、".join(chosen_names), 3.0)
			_level._continue_after_level_completion(level)
		, CONNECT_ONE_SHOT)
		if not _level._open_overlay(ActiveOverlay.GROWTH_CHOICE, panel, &"options_confirmed"):
			panel.queue_free()
			Progress.complete_level(level)
			_level._continue_after_level_completion(level)
		return
	Progress.complete_level(level)
	_level._continue_after_level_completion(level)


func continue_after_level_completion(level: String) -> void:
	if GameState.has_cutscene(level, "post"):
		GameState.pending_cutscene_pages = GameState.get_cutscene_pages(level, "post")
		GameState.pending_next_scene = "res://scenes/menu/main_menu.tscn"
		GameState.transition_to_scene("res://scenes/cutscene/cutscene_scene.tscn")
	else:
		GameState.transition_to_scene("res://scenes/menu/main_menu.tscn")


## 关卡失败。显示失败面板，玩家选择重试或返回主菜单。
## reason: 失败原因文本（显示在面板中）。
## 幂等：phase 已 ENDED 时直接返回，防止重复弹失败面板。
func defeat_level(reason: String = "任务失败") -> void:
	if _level.is_phase_ended():
		return
	_level._set_phase(LevelPhase.ENDED)
	UiSounds.play_defeat()
	var panel: Node = preload("res://scenes/ui/defeat_panel.tscn").instantiate()
	panel.defeat_reason = reason
	panel.retry_pressed.connect(_level._on_defeat_retry)
	panel.main_menu_pressed.connect(_level._on_defeat_main_menu)
	if not _level._open_overlay(ActiveOverlay.DEFEAT_PANEL, panel):
		panel.queue_free()
		return
