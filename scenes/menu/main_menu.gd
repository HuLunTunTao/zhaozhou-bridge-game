extends Control

@onready var main_page: Control = $MainPage
@onready var level_select_page: Control = $LevelSelectPage
@onready var level_grid: GridContainer = $LevelSelectPage/LevelGrid
@onready var test_select_page: Control = $TestSelectPage
@onready var test_grid: GridContainer = $TestSelectPage/TestGrid

const SettingsPanelScene := preload("res://scenes/ui/settings_panel.tscn")
var _settings_open := false


# TODO: 主菜单背景美术替换（赵州桥像素画）
# TODO: 标题字体和字号美化
func _ready() -> void:
	_build_level_buttons()
	_show_page(main_page)


func _build_level_buttons() -> void:
	for child in level_grid.get_children():
		child.queue_free()
	for level_name: String in GameState.LEVEL_SCENES.keys():
		var btn := Button.new()
		btn.text = level_name
		btn.custom_minimum_size = Vector2(56, 32)
		btn.pressed.connect(_on_level_selected.bind(level_name))
		level_grid.add_child(btn)


func _show_page(page: Control) -> void:
	main_page.visible = page == main_page
	level_select_page.visible = page == level_select_page
	test_select_page.visible = page == test_select_page


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


func _on_quit_pressed() -> void:
	get_tree().quit()


# Level select
func _on_level_selected(level: String) -> void:
	GameState.selected_level = level
	var battle_path := GameState.get_level_scene_path(level)
	if battle_path == "":
		return
	if GameState.has_cutscene(level, "pre"):
		GameState.pending_cutscene_pages = GameState.get_cutscene_pages(level, "pre")
		GameState.pending_next_scene = battle_path
		get_tree().change_scene_to_file("res://scenes/cutscene/cutscene_scene.tscn")
	else:
		get_tree().change_scene_to_file(battle_path)
	# TODO: 关卡锁定机制——未通关的关卡按钮置灰
	# TODO: 已通关关卡显示评价（星级或其他标记）


func _on_level_back_pressed() -> void:
	_show_page(main_page)


# Test scenes
const TEST_SCENES: Dictionary = {
	"对话系统": "res://scenes/test/dialogue_test.tscn",
}


func _ready_test_buttons() -> void:
	for child in test_grid.get_children():
		child.queue_free()
	for test_name: String in TEST_SCENES.keys():
		var btn := Button.new()
		btn.text = test_name
		btn.custom_minimum_size = Vector2(56, 32)
		btn.pressed.connect(func(): get_tree().change_scene_to_file(TEST_SCENES[test_name]))
		test_grid.add_child(btn)


func _on_test_pressed() -> void:
	_ready_test_buttons()
	_show_page(test_select_page)


func _on_test_back_pressed() -> void:
	_show_page(main_page)
