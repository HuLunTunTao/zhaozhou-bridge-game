extends Node2D
## 伤害弹字：在单位上方弹出伤害数字，向上漂浮后消失。
## 用法：var popup = DamagePopup.new(); add_child(popup); popup.show_damage(pos, 24, "斫枝")

class_name DamagePopup


## 在指定世界坐标显示伤害数字。
## phase_name 非空时在伤害下方显示化势名。
func show_at(world_pos: Vector2, damage: int, phase_name: String = "", is_heal: bool = false) -> void:
	z_index = 105
	z_as_relative = false
	position = world_pos + Vector2(0, -20)

	# 伤害数字（12px 字体）
	var dmg_label := Label.new()
	dmg_label.text = str(damage) if not is_heal else "+%d" % damage
	dmg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dmg_label.add_theme_font_override("font", Fonts.PIXEL_12)
	dmg_label.add_theme_font_size_override("font_size", 12)
	dmg_label.add_theme_color_override("font_color", Color.RED if not is_heal else Color.GREEN)
	dmg_label.add_theme_color_override("font_outline_color", Color.BLACK)
	dmg_label.add_theme_constant_override("outline_size", 3)
	dmg_label.position = Vector2(-20, 0)
	add_child(dmg_label)

	# 化势名称（10px 字体）
	if phase_name != "":
		var phase_label := Label.new()
		phase_label.text = phase_name
		phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		phase_label.add_theme_font_override("font", Fonts.PIXEL_10)
		phase_label.add_theme_font_size_override("font_size", 10)
		phase_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		phase_label.add_theme_color_override("font_outline_color", Color.BLACK)
		phase_label.add_theme_constant_override("outline_size", 2)
		phase_label.position = Vector2(-20, 14)
		add_child(phase_label)

	# 上浮 + 淡出动画
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 24, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(queue_free)
