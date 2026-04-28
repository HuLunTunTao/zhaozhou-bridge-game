class_name SaveManager
extends CanvasLayer
## Save slot management overlay. Slots store only settings.json and progress.json.

signal closed
signal slot_data_changed

const SLOT_COUNT := 9

@onready var active_slot_label: Label = %ActiveSlotLabel
@onready var slot_container: VBoxContainer = %SlotContainer
@onready var new_button: Button = %NewButton
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var delete_button: Button = %DeleteButton

var _selected_slot := -1
var _slot_buttons: Array[Button] = []


func _ready() -> void:
	layer = 95
	for button in find_children("*", "BaseButton", true, false):
		UiSounds.bind_button(button as BaseButton)
	_build_slots()
	_update_action_buttons()


func _unhandled_input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		_close()


func _build_slots() -> void:
	active_slot_label.text = "当前存档位：%d" % SaveSlots.active_slot
	_slot_buttons.clear()
	for child in slot_container.get_children():
		child.queue_free()

	for i in range(SLOT_COUNT):
		var slot_num := i + 1
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 22)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.toggle_mode = true
		btn.button_group = _get_or_create_button_group()
		btn.text = "  栏位 %d    %s" % [slot_num, _get_slot_status(slot_num)]
		btn.pressed.connect(_on_slot_selected.bind(slot_num))
		slot_container.add_child(btn)
		_slot_buttons.append(btn)
		if slot_num == SaveSlots.active_slot:
			btn.button_pressed = true
			_selected_slot = slot_num


var _button_group: ButtonGroup

func _get_or_create_button_group() -> ButtonGroup:
	if _button_group == null:
		_button_group = ButtonGroup.new()
	return _button_group


func _on_slot_selected(slot_num: int) -> void:
	_selected_slot = slot_num
	_update_action_buttons()


func _update_action_buttons() -> void:
	var has_selection := _selected_slot > 0
	var has_save := has_selection and _slot_has_save(_selected_slot)
	new_button.disabled = not has_selection
	save_button.disabled = not has_selection
	load_button.disabled = not has_save
	delete_button.disabled = not has_save


func _slot_has_save(slot_num: int) -> bool:
	return SaveSlots.slot_exists(slot_num)


func _get_slot_status(slot_num: int) -> String:
	var parts: Array[String] = []
	if slot_num == SaveSlots.active_slot:
		parts.append("当前")
	parts.append("已存在" if SaveSlots.slot_exists(slot_num) else "空")
	return " / ".join(parts)


func _on_new_pressed() -> void:
	if _selected_slot < 1:
		return
	var selected_slot := _selected_slot
	if SaveSlots.slot_exists(selected_slot):
		_confirm_overwrite_with_new_progress(selected_slot)
		return
	_create_new_progress(selected_slot)


func _confirm_overwrite_with_new_progress(slot_num: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "栏位 %d 已有存档。\n新建进度会清空该栏位原有进度与设置。\n\n确定继续？" % slot_num
	dialog.ok_button_text = "新建"
	dialog.cancel_button_text = "取消"
	dialog.confirmed.connect(func(): _create_new_progress(slot_num), CONNECT_ONE_SHOT)
	add_child(dialog)
	dialog.popup_centered()


func _create_new_progress(slot_num: int) -> void:
	if not SaveSlots.new_progress_in_slot(slot_num):
		Notify.notify("新建进度失败", Notify.Position.TOP_CENTER, Notify.Style.ERROR, 2.0)
		return
	Notify.notify("已在栏位 %d 新建进度" % slot_num, Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.0)
	_build_slots()
	_select_slot(slot_num)
	slot_data_changed.emit()


func _on_save_pressed() -> void:
	if _selected_slot < 1:
		return
	if not SaveSlots.save_current_to_slot(_selected_slot):
		Notify.notify("存档失败", Notify.Position.TOP_CENTER, Notify.Style.ERROR, 2.0)
		return
	Notify.notify("已保存到栏位 %d" % _selected_slot, Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.0)
	_build_slots()
	_select_slot(_selected_slot)
	slot_data_changed.emit()


func _on_load_pressed() -> void:
	if _selected_slot < 1:
		return
	if not SaveSlots.load_slot(_selected_slot):
		Notify.notify("读档失败或栏位为空", Notify.Position.TOP_CENTER, Notify.Style.ERROR, 2.0)
		return
	Notify.notify("已切换到栏位 %d" % _selected_slot, Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.0)
	_build_slots()
	_select_slot(_selected_slot)
	slot_data_changed.emit()


func _on_delete_pressed() -> void:
	if _selected_slot < 1:
		return
	var deleted_slot := _selected_slot
	if not SaveSlots.delete_slot(deleted_slot):
		Notify.notify("删档失败", Notify.Position.TOP_CENTER, Notify.Style.ERROR, 2.0)
		return
	Notify.notify("已删除栏位 %d" % deleted_slot, Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.0)
	_build_slots()
	_select_slot(SaveSlots.active_slot)
	slot_data_changed.emit()


func _select_slot(slot_num: int) -> void:
	var idx := slot_num - 1
	if idx >= 0 and idx < _slot_buttons.size():
		_slot_buttons[idx].button_pressed = true
		_selected_slot = slot_num
	_update_action_buttons()


func _on_close_pressed() -> void:
	_close()


func _close() -> void:
	closed.emit()
	queue_free()
