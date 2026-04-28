class_name DefeatPanel
extends CanvasLayer
## 关卡失败弹窗。显示失败原因，提供重试/读档/返回主菜单。

signal retry_pressed
signal main_menu_pressed

var defeat_reason: String = ""

@onready var _reason_label: RichTextLabel = %ReasonLabel
@onready var _retry_button: Button = %RetryButton
@onready var _load_button: Button = %LoadButton


func _ready() -> void:
	layer = 90
	_reason_label.text = defeat_reason
	_retry_button.grab_focus()
	if _load_button != null:
		_load_button.disabled = true
		_load_button.visible = false


func _unhandled_input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		_on_menu_pressed()


func _on_retry_pressed() -> void:
	retry_pressed.emit()
	queue_free()


func _on_load_pressed() -> void:
	pass


func _on_menu_pressed() -> void:
	main_menu_pressed.emit()
	queue_free()
