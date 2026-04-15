extends PanelContainer
## Action panel that appears next to a character showing available actions.
## Dynamically generates buttons from an array of ActionData.

signal action_selected(action_id: String)
signal panel_closed

var _actions: Array[ActionData] = []
@onready var _button_container: VBoxContainer = $MarginContainer/VBoxContainer


func open(actions: Array[ActionData], screen_pos: Vector2) -> void:
	_actions = actions
	_build_buttons()
	# Position to the right of the character
	position = screen_pos + Vector2(20, -size.y * 0.5)
	# Clamp to viewport
	var vp_size := get_viewport_rect().size
	if position.x + size.x > vp_size.x:
		position.x = screen_pos.x - size.x - 20
	if position.y + size.y > vp_size.y:
		position.y = vp_size.y - size.y
	if position.y < 0:
		position.y = 0
	visible = true


func close() -> void:
	visible = false
	panel_closed.emit()


func _build_buttons() -> void:
	for child in _button_container.get_children():
		child.queue_free()
	for action in _actions:
		var btn := Button.new()
		btn.text = action.label
		btn.pressed.connect(_on_action_pressed.bind(action.id))
		_button_container.add_child(btn)


func _on_action_pressed(action_id: String) -> void:
	action_selected.emit(action_id)
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# 左键点击面板外部：关闭面板
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local := get_local_mouse_position()
		if not Rect2(Vector2.ZERO, size).has_point(local):
			close()
			get_viewport().set_input_as_handled()
