extends Control

@onready var main_page: Control = $MainPage
@onready var level_select_page: Control = $LevelSelectPage
@onready var level_grid: GridContainer = $LevelSelectPage/LevelGrid
@onready var test_select_page: Control = $TestSelectPage
@onready var test_grid: GridContainer = $TestSelectPage/TestGrid
@onready var test_button: Button = $MainPage/TestButton

const SettingsPanelScene := preload("res://scenes/ui/settings_panel.tscn")
const ProgressPanelScene := preload("res://scenes/ui/progress_panel.tscn")
const TutorialPanelScene := preload("res://scenes/ui/tutorial_panel.tscn")
const MAIN_MENU_BGM_PATH := "res://assets/audio/music/主：桥起千秋(Before_the_First_Stone).mp3"
var _settings_open := false
var _progress_open := false
var _tutorial_open := false


# TODO: 主菜单背景美术替换（赵州桥像素画）
# TODO: 标题字体和字号美化
func _ready() -> void:
	_play_menu_bgm()
	Progress.progress_changed.connect(_build_level_buttons, CONNECT_REFERENCE_COUNTED)
	Settings.settings_changed.connect(_refresh_debug_visibility, CONNECT_REFERENCE_COUNTED)
	_build_level_buttons()
	_bind_static_button_sounds()
	_refresh_debug_visibility()
	_show_page(main_page)


func _build_level_buttons() -> void:
	for child in level_grid.get_children():
		child.queue_free()
	for level_name: String in GameState.LEVEL_SCENES.keys():
		var btn := Button.new()
		var label := level_name
		if Progress.is_level_completed(level_name):
			label += "  已完成"
		elif not Progress.is_level_unlocked(level_name):
			label += "  未解锁"
		btn.text = label
		btn.custom_minimum_size = Vector2(56, 32)
		btn.pressed.connect(_on_level_selected.bind(level_name))
		btn.disabled = not Progress.is_level_unlocked(level_name)
		UiSounds.bind_button(btn)
		level_grid.add_child(btn)
	# 额外关卡：不走主线解锁，常驻可玩
	for level_name: String in GameState.EXTRA_LEVEL_SCENES.keys():
		var btn := Button.new()
		btn.text = level_name
		btn.custom_minimum_size = Vector2(56, 32)
		btn.pressed.connect(_on_level_selected.bind(level_name))
		UiSounds.bind_button(btn)
		level_grid.add_child(btn)
	if Settings.debug_mode:
		for level_name: String in GameState.TEST_LEVEL_SCENES.keys():
			var btn := Button.new()
			btn.text = level_name
			btn.custom_minimum_size = Vector2(56, 32)
			btn.pressed.connect(_on_level_selected.bind(level_name))
			UiSounds.bind_button(btn)
			level_grid.add_child(btn)


func _bind_static_button_sounds() -> void:
	for button in find_children("*", "BaseButton", true, false):
		UiSounds.bind_button(button as BaseButton)


func _play_menu_bgm() -> void:
	if not ResourceLoader.exists(MAIN_MENU_BGM_PATH, "AudioStream"):
		return
	BgmManager.play(load(MAIN_MENU_BGM_PATH), false)


func _show_page(page: Control) -> void:
	main_page.visible = page == main_page
	level_select_page.visible = page == level_select_page
	test_select_page.visible = page == test_select_page


func _refresh_debug_visibility() -> void:
	test_button.visible = Settings.debug_mode
	if not Settings.debug_mode and test_select_page.visible:
		_show_page(main_page)
	_build_level_buttons()


# Main page buttons
func _on_start_pressed() -> void:
	_show_page(level_select_page)


func _on_settings_pressed() -> void:
	if _settings_open:
		return
	_settings_open = true
	var panel: SettingsPanel = SettingsPanelScene.instantiate()
	add_child(panel)
	panel.closed.connect(func(): _settings_open = false)


func _on_tutorial_pressed() -> void:
	if _tutorial_open:
		return
	_tutorial_open = true
	var panel: Node = TutorialPanelScene.instantiate()
	add_child(panel)
	panel.closed.connect(func(): _tutorial_open = false)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_progress_pressed() -> void:
	if _progress_open:
		return
	_progress_open = true
	var panel: Node = ProgressPanelScene.instantiate()
	add_child(panel)
	panel.closed.connect(func(): _progress_open = false)


# Level select
func _on_level_selected(level: String) -> void:
	# 主线关卡需查解锁；额外关卡 / 测试关卡免查
	var bypass_unlock: bool = level in GameState.EXTRA_LEVEL_SCENES or level in GameState.TEST_LEVEL_SCENES
	if not bypass_unlock and not Progress.is_level_unlocked(level):
		return
	GameState.selected_level = level
	var battle_path := GameState.get_level_scene_path(level)
	if battle_path == "":
		return
	GameState.pending_battle_scene = battle_path
	# 验桥日等关卡跳过 prebattle_setup（无意义的 skill loadout）
	var skip_prebattle: bool = level in GameState.LEVELS_SKIP_PREBATTLE
	var post_cutscene_scene: String = battle_path if skip_prebattle else "res://scenes/ui/prebattle_setup.tscn"
	if GameState.has_cutscene(level, "pre"):
		GameState.pending_cutscene_pages = GameState.get_cutscene_pages(level, "pre")
		GameState.pending_next_scene = post_cutscene_scene
		GameState.transition_to_scene("res://scenes/cutscene/cutscene_scene.tscn")
	else:
		GameState.transition_to_scene(post_cutscene_scene)
	# TODO: 关卡锁定机制——未通关的关卡按钮置灰
	# TODO: 已通关关卡显示评价（星级或其他标记）


func _on_level_back_pressed() -> void:
	_show_page(main_page)


# Test scenes
const TEST_SCENES: Dictionary = {
	"对话系统": "res://scenes/test/dialogue_test.tscn",
	"通知系统": "res://scenes/test/notification_test.tscn",
	"化势通知": "res://scenes/test/phase_notify_test.tscn",
	"TTS": "res://scenes/test/tts_test.tscn",
	"高级对话": "res://scenes/test/advanced_dialogue_test.tscn",
}


func _ready_test_buttons() -> void:
	for child in test_grid.get_children():
		child.queue_free()
	for test_name: String in TEST_SCENES.keys():
		var btn := Button.new()
		btn.text = test_name
		btn.custom_minimum_size = Vector2(56, 32)
		btn.pressed.connect(func(): GameState.transition_to_scene(TEST_SCENES[test_name]))
		UiSounds.bind_button(btn)
		test_grid.add_child(btn)


func _on_test_pressed() -> void:
	if not Settings.debug_mode:
		return
	_ready_test_buttons()
	_show_page(test_select_page)


func _on_test_back_pressed() -> void:
	_show_page(main_page)
