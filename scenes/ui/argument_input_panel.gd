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
## 不预生成话题——所有玩家论点都自由输入；LLM 拿原文当 topic 评分。

signal argument_submitted(text: String)

const PANEL_BG := Color(0.09, 0.10, 0.13, 0.95)
const PANEL_BORDER := Color(0.30, 0.35, 0.40)
const SUBMIT_BG := Color(0.20, 0.32, 0.20, 0.95)
const CANCEL_BG := Color(0.25, 0.18, 0.18, 0.95)

var _input: LineEdit = null


func _ready() -> void:
	layer = 90


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_emit_and_close("")
		get_viewport().set_input_as_handled()


func show_for(npc_name: String, bridge_part: String) -> void:
	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0.55)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(blocker)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -280
	panel.offset_top = -120
	panel.offset_right = 280
	panel.offset_bottom = 120
	var bg := StyleBoxFlat.new()
	bg.bg_color = PANEL_BG
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.border_color = PANEL_BORDER
	bg.set_corner_radius_all(8)
	bg.content_margin_left = 24
	bg.content_margin_right = 24
	bg.content_margin_top = 18
	bg.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "对 %s 说点什么" % npc_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
	vbox.add_child(title)

	if not bridge_part.is_empty():
		var subtitle := Label.new()
		subtitle.text = "TA 在桥的「%s」处" % bridge_part
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		subtitle.add_theme_font_size_override("font_size", 12)
		subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
		vbox.add_child(subtitle)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_input = LineEdit.new()
	_input.placeholder_text = "用论据 / 反问 / 共情……试着打动 TA"
	_input.custom_minimum_size = Vector2(0, 36)
	_input.add_theme_font_size_override("font_size", 14)
	_input.text_submitted.connect(func(text: String): _emit_and_close(text.strip_edges()))
	vbox.add_child(_input)
	_input.grab_focus.call_deferred()

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消（ESC）"
	cancel_btn.add_theme_font_size_override("font_size", 13)
	cancel_btn.custom_minimum_size = Vector2(120, 32)
	var cancel_style := StyleBoxFlat.new()
	cancel_style.bg_color = CANCEL_BG
	cancel_style.set_corner_radius_all(4)
	cancel_btn.add_theme_stylebox_override("normal", cancel_style)
	cancel_btn.pressed.connect(func(): _emit_and_close(""))
	btn_row.add_child(cancel_btn)

	var submit_btn := Button.new()
	submit_btn.text = "说出口（Enter）"
	submit_btn.add_theme_font_size_override("font_size", 13)
	submit_btn.custom_minimum_size = Vector2(140, 32)
	var submit_style := StyleBoxFlat.new()
	submit_style.bg_color = SUBMIT_BG
	submit_style.set_corner_radius_all(4)
	submit_btn.add_theme_stylebox_override("normal", submit_style)
	submit_btn.pressed.connect(func(): _emit_and_close(_input.text.strip_edges()))
	btn_row.add_child(submit_btn)


func _emit_and_close(text: String) -> void:
	argument_submitted.emit(text)
	queue_free()
