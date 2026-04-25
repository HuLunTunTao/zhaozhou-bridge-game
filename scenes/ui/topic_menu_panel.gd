class_name TopicMenuPanel
extends CanvasLayer
## 知识源 NPC（黄！）的求教选题面板。
## 玩家从 N 个推荐主题里选一个，或选"自由提问"走文本输入。
##
## 静态布局在 .tscn 里画好。本脚本只负责按 topics 数量克隆 TopicButtonTemplate。
## 想调整外观（按钮尺寸 / 配色 / 间距）→ 直接打开 topic_menu_panel.tscn 改 TopicButtonTemplate 即可。
##
## 用法：
##   var panel := preload(".../topic_menu_panel.tscn").instantiate()
##   level.add_child(panel)
##   panel.show_for("老监工", ["拱形是什么？","开肩怎么个用法？","为何不用半圆？"])
##   var pick: String = await panel.topic_picked   # "" = 取消；"__free__" = 选了自由提问

signal topic_picked(text: String)

@onready var _title: Label = %Title
@onready var _topic_list: VBoxContainer = %TopicList
@onready var _topic_template: Button = %TopicButtonTemplate
@onready var _free_btn: Button = %FreeButton
@onready var _cancel_btn: Button = %CancelButton


func _ready() -> void:
	_free_btn.pressed.connect(func(): _emit_and_close("__free__"))
	_cancel_btn.pressed.connect(func(): _emit_and_close(""))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_emit_and_close("")
		get_viewport().set_input_as_handled()


func show_for(speaker_name: String, topics: Array) -> void:
	_title.text = "向 %s 请教什么？" % speaker_name
	for t in topics:
		var topic_text: String = String(t)
		var btn: Button = _topic_template.duplicate() as Button
		btn.text = topic_text
		btn.visible = true
		btn.pressed.connect(func(): _emit_and_close(topic_text))
		_topic_list.add_child(btn)


func _emit_and_close(text: String) -> void:
	topic_picked.emit(text)
	queue_free()
