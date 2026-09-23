extends ModalPanel
## 等 LLM 期间盖在世界上的全屏阻塞层。吃掉所有点击和键盘事件。
##
## 用法：
##   var ov := preload(".../thinking_overlay.tscn").instantiate()
##   ov.set_message("……")   # 可在 add_child 之前调
##   level.add_child(ov)
##   var ans: Dictionary = await _generate_answer(...)
##   ov.queue_free()
##
## 静态布局：所有视觉在 .tscn 里。需要换文案就改 Label 的 text 字段。
##
## 继承 ModalPanel 只为复用 pending 缓存（set_message 可在 add_child 前调）。
## 这是加载指示器、不是结果面板——无结果信号，caller 直接 queue_free() 即可。

@onready var _label: Label = %Label


func set_message(message: String) -> void:
	_cache_or_render("message", message, func(v: Variant) -> void:
		if _label:
			_label.text = String(v)
	)


func _unhandled_input(_event: InputEvent) -> void:
	# 全部输入吃掉（含 ESC），避免方向键 / 点击穿透到关卡。
	# 不调 super——基类会把 ESC 转成 _request_close。
	get_viewport().set_input_as_handled()
