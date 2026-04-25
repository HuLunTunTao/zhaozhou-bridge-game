class_name WaveBuffHud
extends CanvasLayer
## 无尽生存模式左上角累计 buff 显示。
## set_wave(n) 更新顶部波次；add_buff(text) 累加同名 buff；clear() 重置。

@onready var _wave_label: Label = %WaveLabel
@onready var _buff_list: VBoxContainer = %BuffList

var _buff_counts: Dictionary = {}  # text -> int
var _buff_labels: Dictionary = {}  # text -> Label


func _ready() -> void:
	layer = 70


func set_wave(n: int) -> void:
	if _wave_label:
		_wave_label.text = "第 %d 波" % n


func add_buff(text: String) -> void:
	var n: int = int(_buff_counts.get(text, 0)) + 1
	_buff_counts[text] = n
	if _buff_labels.has(text):
		var lbl: Label = _buff_labels[text]
		lbl.text = "%s × %d" % [text, n]
	else:
		var lbl := Label.new()
		lbl.text = "%s × 1" % text
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
		lbl.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.08))
		lbl.add_theme_constant_override("outline_size", 3)
		_buff_list.add_child(lbl)
		_buff_labels[text] = lbl


func clear() -> void:
	_buff_counts.clear()
	for c in _buff_list.get_children():
		c.queue_free()
	_buff_labels.clear()
