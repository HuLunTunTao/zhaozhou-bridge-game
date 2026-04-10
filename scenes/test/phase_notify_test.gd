extends Control
## 化势通知测试场景。模拟实战中的化势播报，验证导出版中通知是否可见。


func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_CENTER)
	vbox.offset_left = -150.0
	vbox.offset_top = -140.0
	vbox.offset_right = 150.0
	vbox.offset_bottom = 140.0
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	var title := Label.new()
	title.text = "化势通知测试"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer)

	# ── 模拟化势播报（与 base_level._format_phase_details 格式一致）──
	_add_button(vbox, "制势·遏流（土→水）", func():
		var text := "【制势·遏流】\n"
		text += "[color=#c89650]土×2[/color] → [color=#5ab4ff]水×2[/color]\n"
		text += "附加伤害 11\n"
		text += "施加【壅水】3回合"
		Notify.notify(text, Notify.Position.TOP_RIGHT, Notify.Style.INFO, 4.0)
	)

	_add_button(vbox, "承势·炼金（火→金）", func():
		var text := "【承势·炼金】\n"
		text += "[color=#e6463c]火×3[/color] → [color=#ffd746]金×1[/color]\n"
		text += "伤害倍率 ×1.15\n"
		text += "附加伤害 8"
		Notify.notify(text, Notify.Position.TOP_RIGHT, Notify.Style.INFO, 4.0)
	)

	_add_button(vbox, "制势·蔓缚（木→土）", func():
		var text := "【制势·蔓缚】\n"
		text += "[color=#6edc6e]木×2[/color] → [color=#c89650]土×2[/color]\n"
		text += "施加【蔓缚】2回合"
		Notify.notify(text, Notify.Position.TOP_RIGHT, Notify.Style.INFO, 4.0)
	)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# ── 普通通知（对照组）──
	_add_button(vbox, "普通文本通知", func():
		Notify.notify("这是一条普通通知", Notify.Position.TOP_RIGHT, Notify.Style.INFO)
	)

	_add_button(vbox, "成功通知", func():
		Notify.notify("操作成功！", Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS)
	)

	_add_button(vbox, "连续3条化势", func():
		Notify.notify("【制势·遏流】\n[color=#c89650]土×2[/color] → [color=#5ab4ff]水×2[/color]\n附加伤害 11", Notify.Position.TOP_RIGHT, Notify.Style.INFO, 4.0)
		Notify.notify("【承势·炼金】\n[color=#e6463c]火×3[/color] → [color=#ffd746]金×1[/color]\n伤害倍率 ×1.15", Notify.Position.TOP_RIGHT, Notify.Style.INFO, 4.0)
		Notify.notify("【制势·蔓缚】\n[color=#6edc6e]木×2[/color] → [color=#c89650]土×2[/color]", Notify.Position.TOP_RIGHT, Notify.Style.INFO, 4.0)
	)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	_add_button(vbox, "返回主菜单", func():
		get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
	)


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	parent.add_child(btn)
