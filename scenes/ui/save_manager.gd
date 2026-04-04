class_name SaveManager
extends CanvasLayer
## Save management overlay with 9 save slots.
## Each slot supports save, load, and delete operations.

signal closed

const SLOT_COUNT := 9

@onready var slot_container: VBoxContainer = %SlotContainer


func _ready() -> void:
	layer = 95
	_build_slots()


func _unhandled_input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		_close()


func _build_slots() -> void:
	for i in range(SLOT_COUNT):
		var slot := _create_slot_row(i + 1)
		slot_container.add_child(slot)


func _create_slot_row(slot_num: int) -> HBoxContainer:
	var row := HBoxContainer.new()

	# Slot label
	var label := Label.new()
	label.text = "栏位 %d" % slot_num
	label.custom_minimum_size = Vector2(56, 0)
	row.add_child(label)

	# Status label (empty or save info)
	var status := Label.new()
	status.text = _get_slot_status(slot_num)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(status)

	# Save button
	var save_btn := Button.new()
	save_btn.text = "存"
	save_btn.custom_minimum_size = Vector2(28, 0)
	save_btn.pressed.connect(_on_save_slot.bind(slot_num))
	row.add_child(save_btn)

	# Load button
	var load_btn := Button.new()
	load_btn.text = "读"
	load_btn.custom_minimum_size = Vector2(28, 0)
	load_btn.pressed.connect(_on_load_slot.bind(slot_num))
	row.add_child(load_btn)

	# Delete button
	var delete_btn := Button.new()
	delete_btn.text = "删"
	delete_btn.custom_minimum_size = Vector2(28, 0)
	delete_btn.pressed.connect(_on_delete_slot.bind(slot_num))
	row.add_child(delete_btn)

	return row


func _get_slot_status(_slot_num: int) -> String:
	# TODO: 检查 user://save_{slot_num}.dat 是否存在，返回存档时间等信息
	return "—— 空 ——"


func _on_save_slot(slot_num: int) -> void:
	# TODO: 将 GameState 序列化写入 user://save_{slot_num}.dat
	print("TODO: save to slot %d" % slot_num)
	_refresh_slots()


func _on_load_slot(slot_num: int) -> void:
	# TODO: 从 user://save_{slot_num}.dat 读取并恢复 GameState
	print("TODO: load from slot %d" % slot_num)


func _on_delete_slot(slot_num: int) -> void:
	# TODO: 删除 user://save_{slot_num}.dat，可加确认对话框
	print("TODO: delete slot %d" % slot_num)
	_refresh_slots()


func _refresh_slots() -> void:
	for child in slot_container.get_children():
		child.queue_free()
	_build_slots()


func _on_close_pressed() -> void:
	_close()


func _close() -> void:
	closed.emit()
	queue_free()
