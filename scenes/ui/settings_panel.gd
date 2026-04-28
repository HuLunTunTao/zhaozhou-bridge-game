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
@onready var resolution_option: OptionButton = %ResolutionOption
@onready var apply_display_button: Button = %ApplyDisplayButton
@onready var difficulty_option: OptionButton = %DifficultyOption
@onready var settings_title: Label = %SettingsTitle
@onready var save_manager_button: Button = get_node_or_null("Backdrop/Panel/ScrollContainer/Content/SaveManagerButton") as Button
@onready var quick_save_button: Button = get_node_or_null("Backdrop/Panel/ScrollContainer/Content/QuickSaveButton") as Button
@onready var restart_button: Button = get_node_or_null("Backdrop/Panel/ScrollContainer/Content/RestartButton") as Button
@onready var back_to_menu_button: Button = get_node_or_null("Backdrop/Panel/ScrollContainer/Content/BackToMenuButton") as Button

const FULLSCREEN_INDEX := -1  ## OptionButton 中代表「全屏」的 metadata 值

var _title_tap_count := 0
var _title_tap_reset_timer: SceneTreeTimer


func _ready() -> void:
	layer = 90
	if save_manager_button != null:
		save_manager_button.visible = not show_back_to_menu
	if quick_save_button != null:
		quick_save_button.visible = false
	if restart_button != null:
		restart_button.visible = show_back_to_menu
	if back_to_menu_button != null:
		back_to_menu_button.visible = show_back_to_menu

	_populate_resolution_options()
	_populate_difficulty_options()
	_refresh_controls_from_settings()
	for button in find_children("*", "BaseButton", true, false):
		UiSounds.bind_button(button as BaseButton)
	UiSounds.play_popup()

# AI辅助编程，Kimi Code，2026-04-20


## 填充分辨率下拉框，并将当前选项指向 Settings 中的窗口大小 / 全屏状态。
func _populate_resolution_options() -> void:
	resolution_option.clear()
	for i in Settings.RESOLUTION_PRESETS.size():
		var res: Vector2i = Settings.RESOLUTION_PRESETS[i]
		resolution_option.add_item("%d×%d" % [res.x, res.y], i)
		resolution_option.set_item_metadata(i, res)
	# 全屏单独一档
	var fs_idx := resolution_option.item_count
	resolution_option.add_item("全屏", FULLSCREEN_INDEX)
	resolution_option.set_item_metadata(fs_idx, FULLSCREEN_INDEX)
	# 同步当前选中项
	var current_idx := fs_idx if Settings.fullscreen else _find_resolution_index(Settings.window_width, Settings.window_height)
	resolution_option.select(current_idx)
	apply_display_button.disabled = true


func _find_resolution_index(width: int, height: int) -> int:
	for i in Settings.RESOLUTION_PRESETS.size():
		var res: Vector2i = Settings.RESOLUTION_PRESETS[i]
		if res.x == width and res.y == height:
			return i
	return 1  # 默认 1920×1080


## 填充难度下拉框，按 GameState.DIFFICULTY_ORDER 顺序加项，并选中当前 Settings.difficulty。
func _populate_difficulty_options() -> void:
	difficulty_option.clear()
	for i in GameState.DIFFICULTY_ORDER.size():
		var id: String = GameState.DIFFICULTY_ORDER[i]
		var label: String = GameState.DIFFICULTY_LABELS.get(id, id)
		difficulty_option.add_item(label, i)
		difficulty_option.set_item_metadata(i, id)
	var idx: int = GameState.DIFFICULTY_ORDER.find(Settings.difficulty)
	if idx < 0:
		idx = GameState.DIFFICULTY_ORDER.find("normal")
	difficulty_option.select(idx)


func _on_difficulty_option_item_selected(index: int) -> void:
	var meta: Variant = difficulty_option.get_item_metadata(index)
	if meta is String:
		Settings.set_difficulty(meta)


func _unhandled_input(event: InputEvent) -> void:
	# Consume all input so nothing leaks to the scene behind
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		_close()

##AI辅助生成， Kimi Code，2026-04-19

# Audio
func _on_music_slider_value_changed(value: float) -> void:
	Settings.music_volume = value / 100.0
	Settings.apply_settings()


func _on_sfx_slider_value_changed(value: float) -> void:
	Settings.sfx_volume = value / 100.0
	Settings.apply_settings()


func _on_ui_slider_value_changed(value: float) -> void:
	Settings.ui_volume = value / 100.0
	Settings.apply_settings()


func _on_voice_slider_value_changed(value: float) -> void:
	Settings.voice_volume = value / 100.0
	Settings.apply_settings()


func _on_ambience_slider_value_changed(value: float) -> void:
	Settings.ambience_volume = value / 100.0
	Settings.apply_settings()


# Display
func _on_resolution_option_item_selected(_index: int) -> void:
	# 仅当选项与当前 Settings 不一致时才允许「应用」
	apply_display_button.disabled = not _has_pending_display_change()


func _has_pending_display_change() -> bool:
	var idx := resolution_option.selected
	if idx < 0:
		return false
	var meta: Variant = resolution_option.get_item_metadata(idx)
	if typeof(meta) == TYPE_INT and int(meta) == FULLSCREEN_INDEX:
		return not Settings.fullscreen
	if meta is Vector2i:
		var res: Vector2i = meta
		return Settings.fullscreen or Settings.window_width != res.x or Settings.window_height != res.y
	return false


func _on_apply_display_pressed() -> void:
	var idx := resolution_option.selected
	if idx < 0:
		return
	var meta: Variant = resolution_option.get_item_metadata(idx)
	if typeof(meta) == TYPE_INT and int(meta) == FULLSCREEN_INDEX:
		Settings.set_fullscreen(true)
	elif meta is Vector2i:
		var res: Vector2i = meta
		Settings.set_window_resolution(res.x, res.y)
	apply_display_button.disabled = true
	Notify.notify("显示设置已应用", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.0)


# 保存设置
func _on_save_settings_button_pressed() -> void:
	Settings.save_settings()
	Notify.notify("设置已保存", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.0)


# Save Management
const SaveManagerScene := preload("res://scenes/ui/save_manager.tscn")

func _on_save_manager_pressed() -> void:
	var manager: SaveManager = SaveManagerScene.instantiate()
	add_child(manager)
	manager.slot_data_changed.connect(_refresh_controls_from_settings, CONNECT_REFERENCE_COUNTED)
	UiSounds.play_popup()


func _on_settings_title_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	_title_tap_count += 1
	_title_tap_reset_timer = get_tree().create_timer(1.2)
	_title_tap_reset_timer.timeout.connect(func(): _title_tap_count = 0, CONNECT_ONE_SHOT)
	if _title_tap_count < 7:
		return
	_title_tap_count = 0
	Settings.set_debug_mode(not Settings.debug_mode)
	Notify.notify("调试模式已%s" % ("开启" if Settings.debug_mode else "关闭"), Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.0)


func _on_quick_save_pressed() -> void:
	pass


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


func _on_clear_data_pressed() -> void:
	_show_clear_data_confirm(1)


func _show_clear_data_confirm(step: int) -> void:
	var dialog := ConfirmationDialog.new()
	match step:
		1:
			dialog.dialog_text = "您即将删除所有本地数据。\n包括：全部 1～9 号存档、当前存档位记录、设置。\n\n该操作不可撤销，确定继续？"
			dialog.ok_button_text = "继续"
		2:
			dialog.dialog_text = "再次确认：\n所有存档位中的章节进度、技能解锁、成长选择和设置\n都将被永久删除！\n\n您真的要继续吗？"
			dialog.ok_button_text = "我已知晓，继续"
		_:
			dialog.dialog_text = "最终确认：\n这会清空全部存档，无法恢复。\n\n点击「立即删除」将删除所有本地数据。"
			dialog.ok_button_text = "立即删除"
	dialog.cancel_button_text = "取消"
	dialog.confirmed.connect(func():
		if step >= 3:
			_clear_all_local_data()
		else:
			_show_clear_data_confirm(step + 1)
	)
	add_child(dialog)
	dialog.popup_centered()


func _clear_all_local_data() -> void:
	SaveSlots.clear_all_slot_data()
	Settings.reset_to_defaults()
	Progress.clear_all_in_memory()

	_populate_resolution_options()
	_populate_difficulty_options()
	_refresh_controls_from_settings()

	Notify.notify("本地数据已清除", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.5)


func _refresh_controls_from_settings() -> void:
	music_slider.value = Settings.music_volume * 100.0
	sfx_slider.value = Settings.sfx_volume * 100.0
	ui_slider.value = Settings.ui_volume * 100.0
	voice_slider.value = Settings.voice_volume * 100.0
	ambience_slider.value = Settings.ambience_volume * 100.0
	_populate_resolution_options()
	_populate_difficulty_options()


func _close() -> void:
	closed.emit()
	queue_free()
