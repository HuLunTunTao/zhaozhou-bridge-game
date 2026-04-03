extends Control

@onready var main_page: Control = $MainPage
@onready var level_select_page: Control = $LevelSelectPage
@onready var settings_page: Control = $SettingsPage


# TODO: 主菜单背景美术替换（赵州桥像素画）
# TODO: 标题字体和字号美化
func _ready() -> void:
	_show_page(main_page)


func _show_page(page: Control) -> void:
	main_page.visible = page == main_page
	level_select_page.visible = page == level_select_page
	settings_page.visible = page == settings_page


# Main page buttons
func _on_start_pressed() -> void:
	_show_page(level_select_page)


func _on_settings_pressed() -> void:
	_show_page(settings_page)


func _on_quit_pressed() -> void:
	get_tree().quit()


# Level select
func _on_level_selected(level: int) -> void:
	GameState.selected_level = level
	var path := GameState.get_level_scene_path(level)
	if path != "":
		get_tree().change_scene_to_file(path)
	# TODO: 关卡锁定机制——未通关的关卡按钮置灰
	# TODO: 已通关关卡显示评价（星级或其他标记）


func _on_level_back_pressed() -> void:
	_show_page(main_page)


# Settings
# TODO: 添加音量调节（主音量/音效/音乐）
# TODO: 添加全屏/窗口切换
# TODO: 存档管理（存档/读档/删档）
func _on_settings_back_pressed() -> void:
	_show_page(main_page)
