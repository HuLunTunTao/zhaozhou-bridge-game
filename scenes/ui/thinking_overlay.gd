extends CanvasLayer
## 等 LLM 期间盖在世界上的全屏阻塞层。吃掉所有点击和键盘事件。
##
## 用法：
##   var ov := preload(".../thinking_overlay.tscn").instantiate()
##   level.add_child(ov)
##   var ans: Dictionary = await _generate_answer(...)
##   ov.queue_free()
##
## 静态布局：所有视觉在 .tscn 里。需要换文案就改 Label 的 text 字段。


func _unhandled_input(_event: InputEvent) -> void:
	# 全部输入吃掉，避免方向键 / 点击穿透到关卡
	get_viewport().set_input_as_handled()
