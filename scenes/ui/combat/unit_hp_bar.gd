extends Node2D
## 单位头顶 HP+AP 双条 + 属性标签。场景结构在 unit_hp_bar.tscn 中定义。
## z_index = 100（absolute），确保始终在所有 sprite 之上。

class_name UnitHpBar

const BAR_WIDTH: float = 30.0

@onready var _hp_fill: ColorRect = $HpBg/HpFill
@onready var _ap_fill: ColorRect = $ApBg/ApFill
@onready var _elem_label: Label = $ElemLabel


## 更新属性标签。
func update_element(element: Enums.Element, amount: int) -> void:
	var tag := ElementDefs.element_tag(element, amount)
	_elem_label.text = tag
	if tag != "":
		_elem_label.add_theme_color_override("font_color", ElementDefs.get_color(element))


## 把头顶 ElemLabel 当通用文字位用：直接覆盖 text + 颜色。
## 主要给非战斗场景（如验桥日的状态图标 🔵?/🟢?/🟡!）。
## 传 "" 清空标签。
func set_custom_label(text: String, color: Color) -> void:
	_elem_label.text = text
	if text != "":
		_elem_label.add_theme_color_override("font_color", color)


## 更新血条。ratio = current_hp / max_hp (0.0 ~ 1.0)。
func update_hp(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	_hp_fill.size.x = BAR_WIDTH * ratio

	# 颜色渐变: 亮绿(>60%) → 亮黄(30%~60%) → 亮红(<30%)
	if ratio > 0.6:
		_hp_fill.color = Color(0.15, 0.95, 0.15)
	elif ratio > 0.3:
		_hp_fill.color = Color(1.0, 0.9, 0.1)
	else:
		_hp_fill.color = Color(1.0, 0.15, 0.15)


## 更新 AP 条。ratio = ap_current / ap_max (0.0 ~ 1.0)。
func update_ap(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	_ap_fill.size.x = BAR_WIDTH * ratio

	# 颜色渐变: 亮蓝(>60%) → 淡蓝(30%~60%) → 暗灰(<30%)
	if ratio > 0.6:
		_ap_fill.color = Color(0.25, 0.55, 1.0)
	elif ratio > 0.3:
		_ap_fill.color = Color(0.5, 0.55, 0.8)
	else:
		_ap_fill.color = Color(0.35, 0.3, 0.35)
