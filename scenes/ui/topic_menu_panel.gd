class_name TopicMenuPanel
extends ModalPanel
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
##
## 基类同时提供 0 参 `closed` 信号与 `result: Variant` 字段，可直接
## `_open_overlay(ActiveOverlay.X, panel)` 不传 `closed_signal`。

signal topic_picked(text: String)

@onready var _title: Label = %Title
@onready var _topic_list: VBoxContainer = %TopicList
@onready var _topic_template: Button = %TopicButtonTemplate
@onready var _free_btn: Button = %FreeButton
@onready var _cancel_btn: Button = %CancelButton


func _ready() -> void:
	_free_btn.pressed.connect(func(): _request_close("__free__"))
	_cancel_btn.pressed.connect(func(): _request_close(""))


func _default_cancel_result() -> Variant:
	return ""


func _emit_result_signal(close_result: Variant) -> void:
	topic_picked.emit(String(close_result))


func show_for(speaker_name: String, topics: Array) -> void:
	_title.text = "向 %s 请教什么？" % speaker_name
	for t in topics:
		var topic_text: String = String(t)
		var btn: Button = _topic_template.duplicate() as Button
		btn.text = topic_text
		btn.visible = true
		btn.pressed.connect(func(): _request_close(topic_text))
		_topic_list.add_child(btn)


# 通用 yes/no 选择面板（教程复玩询问等场景）。
# title 整段写死、不再走"向 X 请教什么？"前缀；隐藏自由提问按钮；
# 取消按钮与 ESC 沿用既有的 emit "" 语义——caller 用 == yes_label 即可把"取消"自然归为 no。
func show_yes_no(title: String, yes_label: String, no_label: String) -> void:
	_title.text = title
	_free_btn.visible = false
	for label in [yes_label, no_label]:
		var btn: Button = _topic_template.duplicate() as Button
		btn.text = label
		btn.visible = true
		btn.pressed.connect(func(): _request_close(label))
		_topic_list.add_child(btn)
