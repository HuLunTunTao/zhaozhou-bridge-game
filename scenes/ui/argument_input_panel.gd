class_name ArgumentInputPanel
extends CanvasLayer
## 玩家输入"想对 NPC 说什么"的模态文本面板。
##
## 用法：
##   var panel := preload("...argument_input_panel.tscn").instantiate()
##   level.add_child(panel)
##   panel.show_for("老匠首", "主拱")
##   var text: String = await panel.argument_submitted   # 取消时返回 ""
##
## 静态布局：所有 UI 在 .tscn 里画好。本脚本只负责绑节点 + 处理事件。

signal argument_submitted(text: String)

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _input: LineEdit = %Input
@onready var _submit_btn: Button = %SubmitButton
@onready var _cancel_btn: Button = %CancelButton


func _ready() -> void:
	_input.text_submitted.connect(func(t: String): _emit_and_close(t.strip_edges()))
	_submit_btn.pressed.connect(func(): _emit_and_close(_input.text.strip_edges()))
	_cancel_btn.pressed.connect(func(): _emit_and_close(""))
	_input.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_emit_and_close("")
		get_viewport().set_input_as_handled()


func show_for(npc_name: String, subtitle_text: String) -> void:
	_title.text = "对 %s 说点什么" % npc_name
	if subtitle_text.is_empty():
		_subtitle.visible = false
	else:
		_subtitle.text = subtitle_text
		_subtitle.visible = true


func _emit_and_close(text: String) -> void:
	argument_submitted.emit(text)
	queue_free()
