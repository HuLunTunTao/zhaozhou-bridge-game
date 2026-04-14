class_name SettingsPanel
extends CanvasLayer
## Reusable settings overlay. Semi-transparent backdrop + centered panel.
## Can be used from main menu or in-game (gear icon).
## Set show_back_to_menu = true before adding to tree to show "返回主菜单".

signal closed

@export var show_back_to_menu := false

@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var ui_slider: HSlider = %UiSlider
@onready var voice_slider: HSlider = %VoiceSlider
@onready var ambience_slider: HSlider = %AmbienceSlider
@onready var quick_save_button: Button = %QuickSaveButton
@onready var restart_button: Button = %RestartButton
@onready var back_to_menu_button: Button = %BackToMenuButton


func _ready() -> void:
	layer = 90
	quick_save_button.visible = show_back_to_menu
	restart_button.visible = show_back_to_menu
	back_to_menu_button.visible = show_back_to_menu

	music_slider.value = Settings.music_volume * 100.0
	sfx_slider.value = Settings.sfx_volume * 100.0
	ui_slider.value = Settings.ui_volume * 100.0
	voice_slider.value = Settings.voice_volume * 100.0
	ambience_slider.value = Settings.ambience_volume * 100.0
	for button in find_children("*", "BaseButton", true, false):
		UiSounds.bind_button(button as BaseButton)
	UiSounds.play_popup()


func _unhandled_input(event: InputEvent) -> void:
	# Consume all input so nothing leaks to the scene behind
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		_close()


# Audio
func _on_music_slider_value_changed(value: float) -> void:
	Settings.music_volume = value / 100.0
	Settings._apply_settings()


func _on_sfx_slider_value_changed(value: float) -> void:
	Settings.sfx_volume = value / 100.0
	Settings._apply_settings()


func _on_ui_slider_value_changed(value: float) -> void:
	Settings.ui_volume = value / 100.0
	Settings._apply_settings()


func _on_voice_slider_value_changed(value: float) -> void:
	Settings.voice_volume = value / 100.0
	Settings._apply_settings()


func _on_ambience_slider_value_changed(value: float) -> void:
	Settings.ambience_volume = value / 100.0
	Settings._apply_settings()


# 保存设置
func _on_save_settings_button_pressed() -> void:
	Settings.save_settings()
	Notify.notify("设置已保存", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.0)


# Save Management
const SaveManagerScene := preload("res://scenes/ui/save_manager.tscn")

func _on_save_manager_pressed() -> void:
	var manager: SaveManager = SaveManagerScene.instantiate()
	add_child(manager)
	UiSounds.play_popup()


func _on_quick_save_pressed() -> void:
	# TODO: 快速存档到固定栏位（如 slot 0），保存当前关卡状态
	print("TODO: quick save")


func _on_restart_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "确定要重新开始本关吗？\n所有未存档的进度将会丢失"
	dialog.ok_button_text = "确定"
	dialog.cancel_button_text = "取消"
	dialog.confirmed.connect(func():
		_close()
		get_tree().reload_current_scene()
	)
	add_child(dialog)
	dialog.popup_centered()


func _on_back_to_menu_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "确定要返回主菜单吗？\n所有未存档的进度将会丢失"
	dialog.ok_button_text = "确定"
	dialog.cancel_button_text = "取消"
	dialog.confirmed.connect(func():
		_close()
		GameState.transition_to_scene("res://scenes/menu/main_menu.tscn")
	)
	add_child(dialog)
	dialog.popup_centered()


func _on_close_pressed() -> void:
	_close()


func _close() -> void:
	closed.emit()
	queue_free()


