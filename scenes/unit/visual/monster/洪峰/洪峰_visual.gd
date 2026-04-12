extends UnitVisual
## 单一动画怪物，不区分方向。

func _resolve_anim_name(_facing: Facing, _state: StringName) -> StringName:
	return &"default"
