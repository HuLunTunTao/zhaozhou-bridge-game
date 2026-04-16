extends UnitVisual
## 单一动画敌方，通过水平翻转实现左右转向。

func _resolve_anim_name(_facing: Facing, _state: StringName) -> StringName:
	return &"default"
