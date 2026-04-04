class_name SettingsPanel
extends CanvasLayer
## Reusable settings overlay. Semi-transparent backdrop + centered panel.
## Can be used from main menu or in-game (gear icon).
## Set show_back_to_menu = true before adding to tree to show "返回主菜单".

signal closed

@export var show_back_to_menu := false

@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var back_to_menu_button: Button = %BackToMenuButton


func _ready() -> void:
	layer = 90
	back_to_menu_button.visible = show_back_to_menu


func _unhandled_input(event: InputEvent) -> void:
	# Consume all input so nothing leaks to the scene behind
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		_close()


# Audio
func _on_music_slider_value_changed(_value: float) -> void:
	# TODO: AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(value / 100.0))
	pass


func _on_sfx_slider_value_changed(_value: float) -> void:
	# TODO: AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(value / 100.0))
	pass


# Save Management
func _on_save_pressed() -> void:
	# TODO: 将 GameState 序列化写入 user://save.dat
	pass


func _on_load_pressed() -> void:
	# TODO: 从 user://save.dat 读取并恢复 GameState
	pass


func _on_delete_pressed() -> void:
	# TODO: 删除 user://save.dat，弹出确认对话框
	pass


func _on_back_to_menu_pressed() -> void:
	_close()
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


func _on_close_pressed() -> void:
	_close()


func _close() -> void:
	closed.emit()
	queue_free()
