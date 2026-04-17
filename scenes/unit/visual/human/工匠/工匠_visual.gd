extends UnitVisual
## 工匠：单方向精灵，idle 和 move 两种状态，依靠 flip_h 转向。

func _resolve_anim_name(_facing: Facing, state: StringName) -> StringName:
	return state
