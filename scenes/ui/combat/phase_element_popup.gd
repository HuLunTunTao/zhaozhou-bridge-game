extends Node2D
class_name PhaseElementPopup
## 化势触发时在目标头顶显示「攻击元素×量 → 目标元素×量」。
## 用法：var p = PhaseElementPopup.new(); add_child(p); p.show_at(pos, atk_e, atk_a, tgt_e, tgt_a)


func show_at(world_pos: Vector2, atk_e: Enums.Element, atk_a: int, tgt_e: Enums.Element, tgt_a: int) -> void:
	z_index = 106  # 在伤害弹字(105)之上，AP消耗标签(110)之下
	z_as_relative = false
	position = world_pos + Vector2(0, -38)

	var hbox := HBoxContainer.new()
	hbox.position = Vector2(-32, 0)
	hbox.add_theme_constant_override("separation", 2)
	add_child(hbox)

	_add_label(hbox, "%s×%d" % [ElementDefs.element_name(atk_e), atk_a], ElementDefs.get_color(atk_e))
	_add_label(hbox, "→", Color(1, 1, 1))
	_add_label(hbox, "%s×%d" % [ElementDefs.element_name(tgt_e), tgt_a], ElementDefs.get_color(tgt_e))

	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 18, 1.0).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.8).set_delay(0.6)
	tween.chain().tween_callback(queue_free)


func _add_label(parent: HBoxContainer, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", Fonts.PIXEL_8)
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 3)
	parent.add_child(lbl)
