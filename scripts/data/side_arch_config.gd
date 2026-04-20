class_name SideArchConfig
extends Resource
## 四小拱锚点相对 anchor（通常是李春起始 cell）的偏移。
## 关卡脚本在 `_setup_anchor_cells` 里读取后 + anchor 得到绝对格。

@export var left_front_offset: Vector2i = Vector2i(-3, -1)
@export var left_back_offset: Vector2i = Vector2i(-2, 2)
@export var right_front_offset: Vector2i = Vector2i(3, -1)
@export var right_back_offset: Vector2i = Vector2i(2, 2)
