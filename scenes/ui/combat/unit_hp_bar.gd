extends Node2D
## 单位头顶 HP+AP 双条 + 属性标签。场景结构在 unit_hp_bar.tscn 中定义。
## z_index = 100（absolute），确保始终在所有 sprite 之上。

class_name UnitHpBar

const BAR_WIDTH: float = 30.0
const HP_COLOR_ALLY := Color(0.15, 0.95, 0.15)
const HP_COLOR_ENEMY := Color(1.0, 0.15, 0.15)
const _LABEL_DEFAULT_RECT := Rect2(-53.0, 0.0, 35.0, 24.0)
const _LABEL_NAME_RECT := Rect2(-48.0, -2.0, 96.0, 20.0)

@onready var _hp_bg: ColorRect = $HpBg
@onready var _hp_fill: ColorRect = $HpBg/HpFill
@onready var _ap_bg: ColorRect = $ApBg
@onready var _ap_fill: ColorRect = $ApBg/ApFill
@onready var _elem_label: Label = $ElemLabel


## 更新属性标签。
func update_element(element: Enums.Element, amount: int) -> void:
	_apply_label_rect(_LABEL_DEFAULT_RECT, HORIZONTAL_ALIGNMENT_RIGHT)
	var tag := ElementDefs.element_tag(element, amount)
	_elem_label.text = tag
	if tag != "":
		_elem_label.add_theme_color_override("font_color", ElementDefs.get_color(element))


## 把头顶 ElemLabel 当通用文字位用：直接覆盖 text + 颜色。
## 主要给非战斗场景（如验桥日的状态图标）。
## 传 "" 清空标签。
func set_custom_label(text: String, color: Color) -> void:
	_apply_label_rect(_LABEL_DEFAULT_RECT, HORIZONTAL_ALIGNMENT_RIGHT)
	_elem_label.text = text
	if text != "":
		_elem_label.add_theme_color_override("font_color", color)


## 非战斗场景的姓名牌模式：隐藏 HP/AP 条，用居中的名字取代。
func set_name_label(text: String, color: Color) -> void:
	set_bars_visible(false)
	_apply_label_rect(_LABEL_NAME_RECT, HORIZONTAL_ALIGNMENT_CENTER)
	_elem_label.text = text
	if text != "":
		_elem_label.add_theme_color_override("font_color", color)


func set_bars_visible(visible_flag: bool) -> void:
	_hp_bg.visible = visible_flag
	_ap_bg.visible = visible_flag


func _apply_label_rect(rect: Rect2, align: HorizontalAlignment) -> void:
	_elem_label.offset_left = rect.position.x
	_elem_label.offset_top = rect.position.y
	_elem_label.offset_right = rect.position.x + rect.size.x
	_elem_label.offset_bottom = rect.position.y + rect.size.y
	_elem_label.horizontal_alignment = align


## 更新血条。ratio = current_hp / max_hp (0.0 ~ 1.0)，颜色只表示敌我阵营。
func update_hp(ratio: float, camp: int = Enums.Camp.ALLY) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	_hp_fill.size.x = BAR_WIDTH * ratio
	_hp_fill.color = HP_COLOR_ENEMY if camp == Enums.Camp.ENEMY else HP_COLOR_ALLY


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
