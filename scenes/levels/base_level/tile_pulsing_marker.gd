class_name TilePulsingMarker
extends Marker2D
## 通用「地块强调」浮动标记。
## 自身是一个 Marker2D：把它的 position 放到对应地块的 local 坐标，
## 子节点 Halo / Core / Floater(Pole+Arrow) / Label 自动呈现脉动光晕 + 指向地块的下指箭头。
##
## 三个独立显示开关：
##   show_tile  — 地块上的菱形光晕 + 核心（低不透明度的覆盖）
##   show_pole  — Floater 里的竖线 + 下指箭头（脉动指针）
##   show_label — 菱形上方的文字标签（需同时 label_text 非空才真正显示）
##
## 推荐通过 BaseLevel.spawn_tile_pulsing_marker(cell, halo_color, label_text, local_offset) 创建。

const SCENE: PackedScene = preload("res://scenes/levels/base_level/tile_pulsing_marker.tscn")

@export var halo_color: Color = Color(0.18, 0.72, 1.0, 0.25):
	set(value):
		halo_color = value
		_apply_colors()

@export var pole_color: Color = Color(1.0, 0.95, 0.55, 0.95):
	set(value):
		pole_color = value
		_apply_pole_color()

@export var label_text: String = "":
	set(value):
		label_text = value
		_apply_label()

@export var show_tile: bool = true:
	set(value):
		show_tile = value
		if _halo:
			_halo.visible = value
		if _core:
			_core.visible = value

@export var show_pole: bool = true:
	set(value):
		show_pole = value
		if _floater:
			_floater.visible = value

@export var show_label: bool = true:
	set(value):
		show_label = value
		_apply_label()

@export var pulse_amplitude: float = 6.0
@export var pulse_duration: float = 0.7

@onready var _halo: Polygon2D = $Halo
@onready var _core: Polygon2D = $Core
@onready var _label: Label = $Label
@onready var _floater: Node2D = $Floater
@onready var _pole: Polygon2D = $Floater/Pole
@onready var _arrow: Polygon2D = $Floater/Arrow


func _ready() -> void:
	_apply_colors()
	_apply_pole_color()
	_apply_label()
	_halo.visible = show_tile
	_core.visible = show_tile
	_floater.visible = show_pole
	_start_pulse()


func _apply_colors() -> void:
	if _halo:
		_halo.color = halo_color
	if _core:
		# 核心色跟随 halo：取 halo 色相 + 稍亮，并把 alpha 控制在 halo + 小幅增量内
		var core_color := Color(1.0, 0.92, 0.80, 0.95)
		core_color.a = clampf(halo_color.a + 0.15, 0.0, 0.6)
		_core.color = core_color


func _apply_pole_color() -> void:
	if _pole:
		_pole.color = pole_color
	if _arrow:
		_arrow.color = pole_color


func _apply_label() -> void:
	if _label:
		_label.text = label_text
		_label.visible = show_label and label_text != ""


func _start_pulse() -> void:
	if _floater == null:
		return
	var base_y := _floater.position.y
	var tween := create_tween().set_loops()
	tween.tween_property(_floater, "position:y", base_y - pulse_amplitude, pulse_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_floater, "position:y", base_y, pulse_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
