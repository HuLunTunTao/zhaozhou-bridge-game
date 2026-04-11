class_name ObjectivesPanel
extends CanvasLayer
## 关卡目标弹窗。显示胜利/失败条件，点击确认或按 ESC 关闭。

signal closed

var victory_lines: Array = []
var defeat_lines: Array = []

@onready var _victory_label: RichTextLabel = %VictoryContent
@onready var _defeat_label: RichTextLabel = %DefeatContent
@onready var _confirm_button: Button = %ConfirmButton


func _ready() -> void:
	layer = 85
	_victory_label.text = ""
	for line in victory_lines:
		_victory_label.text += line + "\n"
	_defeat_label.text = ""
	for line in defeat_lines:
		_defeat_label.text += line + "\n"
	_confirm_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		_close()


func _on_confirm_pressed() -> void:
	_close()


func _close() -> void:
	closed.emit()
	queue_free()
