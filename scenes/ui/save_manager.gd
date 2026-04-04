class_name SaveManager
extends CanvasLayer
## Minecraft-style save management overlay.
## Top: selectable slot list. Bottom: action buttons for selected slot.

signal closed

const SLOT_COUNT := 9

@onready var slot_container: VBoxContainer = %SlotContainer
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var delete_button: Button = %DeleteButton

var _selected_slot := -1
var _slot_buttons: Array[Button] = []


func _ready() -> void:
	layer = 95
	_build_slots()
	_update_action_buttons()


func _unhandled_input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		_close()


func _build_slots() -> void:
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
	save_button.disabled = not has_selection
	load_button.disabled = not has_save
	delete_button.disabled = not has_save


func _slot_has_save(_slot_num: int) -> bool:
	# TODO: 检查 user://save_{slot_num}.dat 是否存在
	return false


func _get_slot_status(_slot_num: int) -> String:
	# TODO: 检查存档文件，返回存档时间等信息
	return "—— 空 ——"


func _on_save_pressed() -> void:
	if _selected_slot < 1:
		return
	# TODO: 将 GameState 序列化写入 user://save_{_selected_slot}.dat
	print("TODO: save to slot %d" % _selected_slot)
	_build_slots()
	_select_slot(_selected_slot)


func _on_load_pressed() -> void:
	if _selected_slot < 1:
		return
	# TODO: 从 user://save_{_selected_slot}.dat 读取并恢复 GameState
	print("TODO: load from slot %d" % _selected_slot)


func _on_delete_pressed() -> void:
	if _selected_slot < 1:
		return
	# TODO: 删除 user://save_{_selected_slot}.dat
	print("TODO: delete slot %d" % _selected_slot)
	_build_slots()
	_select_slot(_selected_slot)


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
