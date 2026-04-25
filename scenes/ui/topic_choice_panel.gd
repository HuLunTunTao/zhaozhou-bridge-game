class_name TopicChoicePanel
extends CanvasLayer
## 多选话题面板。在与 NPC 交互时弹出，玩家点话题 → emit topic_chosen。
##
## 用法：
##   var panel = preload(".../topic_choice_panel.tscn").instantiate()
##   level.add_child(panel)
##   panel.show_topics("老匠首", ["话题1", "话题2", "话题3"])
##   var idx: int = await panel.topic_chosen
##   panel.queue_free()

signal topic_chosen(text: String)

const PANEL_BG := Color(0.09, 0.10, 0.13, 0.95)
const PANEL_BORDER := Color(0.30, 0.35, 0.40)
const BUTTON_HOVER := Color(0.20, 0.22, 0.27, 0.95)
const BUTTON_NORMAL := Color(0.13, 0.15, 0.19, 0.95)


func _ready() -> void:
	layer = 90


func _unhandled_input(_event: InputEvent) -> void:
	# 拦截一切输入（模态）
	get_viewport().set_input_as_handled()


func show_topics(speaker_name: String, topics: Array) -> void:
	# 全屏拦截
	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0.55)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(blocker)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_top = -160
	panel.offset_right = 260
	panel.offset_bottom = 160
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
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
	title.text = "你想问 %s 什么？" % speaker_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	for i in topics.size():
		var topic_text: String = String(topics[i])
		var btn := Button.new()
		btn.text = topic_text
		btn.custom_minimum_size = Vector2(0, 38)
		btn.add_theme_font_size_override("font_size", 14)
		var normal := StyleBoxFlat.new()
		normal.bg_color = BUTTON_NORMAL
		normal.set_corner_radius_all(4)
		normal.content_margin_left = 12
		normal.content_margin_right = 12
		normal.content_margin_top = 6
		normal.content_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", normal)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = BUTTON_HOVER
		btn.add_theme_stylebox_override("hover", hover)
		btn.pressed.connect(func(): _on_pick(topic_text))
		vbox.add_child(btn)


func _on_pick(text: String) -> void:
	topic_chosen.emit(text)
	queue_free()
