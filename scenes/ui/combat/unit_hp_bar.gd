extends Node2D
## 单位头顶 HP 条。作为 Unit 的子节点使用。

class_name UnitHpBar

var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _bar_width: float = 24.0
var _bar_height: float = 3.0
var _offset_y: float = -22.0  # 在精灵上方


func _ready() -> void:
	# 背景（深灰）
	_bar_bg = ColorRect.new()
	_bar_bg.size = Vector2(_bar_width, _bar_height)
	_bar_bg.position = Vector2(-_bar_width * 0.5, _offset_y)
	_bar_bg.color = Color(0.15, 0.15, 0.15, 0.8)
	add_child(_bar_bg)

	# 填充（绿→黄→红）
	_bar_fill = ColorRect.new()
	_bar_fill.size = Vector2(_bar_width, _bar_height)
	_bar_fill.position = _bar_bg.position
	_bar_fill.color = Color.GREEN
	add_child(_bar_fill)


## 更新血条。ratio = current_hp / max_hp (0.0 ~ 1.0)。
func update_hp(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	_bar_fill.size.x = _bar_width * ratio

	# 颜色渐变: 绿(>60%) → 黄(30%~60%) → 红(<30%)
	if ratio > 0.6:
		_bar_fill.color = Color(0.2, 0.85, 0.2)
	elif ratio > 0.3:
		_bar_fill.color = Color(0.9, 0.8, 0.2)
	else:
		_bar_fill.color = Color(0.9, 0.2, 0.2)

	# 满血时隐藏
	visible = ratio < 1.0
