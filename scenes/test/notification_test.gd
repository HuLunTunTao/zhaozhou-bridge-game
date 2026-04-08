extends Control
## 通知系统测试场景。点击按钮测试各种位置和样式。


func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_CENTER)
	vbox.offset_left = -120.0
	vbox.offset_top = -100.0
	vbox.offset_right = 120.0
	vbox.offset_bottom = 100.0
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	var title := Label.new()
	title.text = "通知系统测试"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer)

	# 位置测试按钮
	_add_button(vbox, "左上角", func(): Notify.notify("左上角通知", Notify.Position.TOP_LEFT))
	_add_button(vbox, "右上角", func(): Notify.notify("右上角通知", Notify.Position.TOP_RIGHT))
	_add_button(vbox, "左下角", func(): Notify.notify("左下角通知", Notify.Position.BOTTOM_LEFT))
	_add_button(vbox, "右下角", func(): Notify.notify("右下角通知", Notify.Position.BOTTOM_RIGHT))
	_add_button(vbox, "顶部居中", func(): Notify.notify("顶部居中通知", Notify.Position.TOP_CENTER))
	_add_button(vbox, "底部居中", func(): Notify.notify("底部居中通知", Notify.Position.BOTTOM_CENTER))
	_add_button(vbox, "正中间", func(): Notify.notify("正中间通知", Notify.Position.CENTER))

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 样式测试按钮
	_add_button(vbox, "信息 (INFO)", func(): Notify.notify("这是一条信息", Notify.Position.TOP_RIGHT, Notify.Style.INFO))
	_add_button(vbox, "成功 (SUCCESS)", func(): Notify.notify("操作成功！", Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS))
	_add_button(vbox, "警告 (WARNING)", func(): Notify.notify("注意：资源不足", Notify.Position.TOP_RIGHT, Notify.Style.WARNING))
	_add_button(vbox, "错误 (ERROR)", func(): Notify.notify("错误：连接失败", Notify.Position.TOP_RIGHT, Notify.Style.ERROR))

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# 堆叠测试
	_add_button(vbox, "连续3条（测试堆叠）", func():
		Notify.notify("第一条通知", Notify.Position.TOP_RIGHT, Notify.Style.INFO)
		Notify.notify("第二条通知", Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS)
		Notify.notify("第三条通知", Notify.Position.TOP_RIGHT, Notify.Style.WARNING)
	)


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	parent.add_child(btn)
