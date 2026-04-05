class_name TileType
extends RefCounted
## 所有地块类型的基类。
## 子类覆盖 get_movement_cost、on_enter、on_exit 来实现地块特有逻辑。
## 在不同 level 里可以进一步子类化来覆盖效果。

const IMPASSABLE := -1

## 返回进入此地块所需移动点。返回 IMPASSABLE(-1) 表示不可通行。
func get_movement_cost() -> int:
	return 1

## entity 进入此地块时调用（每步移动到达后触发）。
func on_enter(_entity: Node2D) -> void:
	pass

## entity 离开此地块时调用（每步移动出发前触发）。
func on_exit(_entity: Node2D) -> void:
	pass
