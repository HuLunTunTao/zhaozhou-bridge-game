@tool
class_name SpecialTile
extends Node2D
## 特殊地块基类。
## 开发者在场景的 SpecialTiles 节点下放置实例，运行时自动吸附到最近格子。
## 子类覆盖以下三个方法实现不同交互逻辑：
##   _on_unit_arrive — 角色移动结束，最终停留在此地块
##   _on_unit_pass   — 角色经过此地块但未停留
##   _on_unit_depart — 角色从此地块出发去往别处

@export var tile_color: Color = Color(0.5, 0, 1, 0.6):
	set(value):
		tile_color = value
		_apply_color()

var cell: Vector2i


func _ready() -> void:
	z_as_relative = false
	z_index = 40
	y_sort_enabled = false
	_apply_color()


func _apply_color() -> void:
	var visual := get_node_or_null("Visual")
	if visual is Polygon2D:
		(visual as Polygon2D).color = tile_color


## 角色最终停留在此地块时调用。
func _on_unit_arrive(entity: Node2D) -> void:
	pass


## 角色经过此地块但未停留时调用。
func _on_unit_pass(entity: Node2D) -> void:
	pass


## 角色从此地块出发去往别处时调用。
func _on_unit_depart(entity: Node2D) -> void:
	pass
