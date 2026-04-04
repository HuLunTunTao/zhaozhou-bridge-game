extends Control

@onready var main_page: Control = $MainPage
@onready var level_select_page: Control = $LevelSelectPage

const SettingsPanelScene := preload("res://scenes/ui/settings_panel.tscn")
var _settings_open := false


# TODO: 主菜单背景美术替换（赵州桥像素画）
# TODO: 标题字体和字号美化
func _ready() -> void:
	_show_page(main_page)


func _show_page(page: Control) -> void:
	main_page.visible = page == main_page
	level_select_page.visible = page == level_select_page


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
func _on_level_selected(level: int) -> void:
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
