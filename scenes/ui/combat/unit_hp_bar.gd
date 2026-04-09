extends Node2D
## 单位头顶 HP+AP 条。作为 Unit 的子节点使用。
## z_as_relative = false + z_index = 100，确保始终在所有 sprite 之上。

class_name UnitHpBar

var _hp_bg: ColorRect
var _hp_fill: ColorRect
var _ap_bg: ColorRect
var _ap_fill: ColorRect

var _bar_width: float = 30.0
var _hp_height: float = 4.0
var _ap_height: float = 3.0
var _gap: float = 1.0           # HP 与 AP 之间间距
var _border: float = 1.0        # 每条各自的描边粗细
var _offset_y: float = -40.0    # HP 条顶端，在精灵上方


func _ready() -> void:
	z_index = 100
	z_as_relative = false

	# ── HP 条（背景比填充大 1px 形成独立描边）──
	_hp_bg = ColorRect.new()
	_hp_bg.size = Vector2(_bar_width + _border * 2, _hp_height + _border * 2)
	_hp_bg.position = Vector2(-_bar_width * 0.5 - _border, _offset_y - _border)
	_hp_bg.color = Color(0.0, 0.0, 0.0, 0.7)
	add_child(_hp_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.size = Vector2(_bar_width, _hp_height)
	_hp_fill.position = Vector2(-_bar_width * 0.5, _offset_y)
	_hp_fill.color = Color(0.15, 0.95, 0.15)
	add_child(_hp_fill)

	# ── AP 条（同样独立描边）──
	var ap_y := _offset_y + _hp_height + _border + _gap
	_ap_bg = ColorRect.new()
	_ap_bg.size = Vector2(_bar_width + _border * 2, _ap_height + _border * 2)
	_ap_bg.position = Vector2(-_bar_width * 0.5 - _border, ap_y - _border)
	_ap_bg.color = Color(0.0, 0.0, 0.0, 0.7)
	add_child(_ap_bg)

	_ap_fill = ColorRect.new()
	_ap_fill.size = Vector2(_bar_width, _ap_height)
	_ap_fill.position = Vector2(-_bar_width * 0.5, ap_y)
	_ap_fill.color = Color(0.25, 0.55, 1.0)
	add_child(_ap_fill)


## 更新血条。ratio = current_hp / max_hp (0.0 ~ 1.0)。
func update_hp(ratio: float) -> void:
	_hp_fill.size.x = _bar_width * clampf(ratio, 0.0, 1.0)

	# 颜色渐变: 亮绿(>60%) → 亮黄(30%~60%) → 亮红(<30%)
	if ratio > 0.6:
		_hp_fill.color = Color(0.15, 0.95, 0.15)
	elif ratio > 0.3:
		_hp_fill.color = Color(1.0, 0.9, 0.1)
	else:
		_hp_fill.color = Color(1.0, 0.15, 0.15)


## 更新 AP 条。ratio = ap_current / ap_max (0.0 ~ 1.0)。
func update_ap(ratio: float) -> void:
	_ap_fill.size.x = _bar_width * clampf(ratio, 0.0, 1.0)

	# 颜色渐变: 亮蓝(>60%) → 淡蓝(30%~60%) → 暗灰(<30%)
	if ratio > 0.6:
		_ap_fill.color = Color(0.25, 0.55, 1.0)
	elif ratio > 0.3:
		_ap_fill.color = Color(0.5, 0.55, 0.8)
	else:
		_ap_fill.color = Color(0.35, 0.3, 0.35)
