extends UnitVisual
## 测量工：左右两方向，idle 和 move 两种状态。
## 动画命名：idle_left, idle_right, move_left, move_right。

func _resolve_anim_name(facing: Facing, state: StringName) -> StringName:
	var dir: String
	match facing:
		Facing.LEFT_FRONT, Facing.LEFT_BACK:
			dir = "left"
		_:
			dir = "right"
	return StringName(String(state) + "_" + dir)
