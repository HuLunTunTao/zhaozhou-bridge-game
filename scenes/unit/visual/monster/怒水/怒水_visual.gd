extends UnitVisual

func _resolve_anim_name(_facing: Facing, _state: StringName) -> StringName:
	match _facing:
		Facing.RIGHT_FRONT, Facing.RIGHT_BACK:
		
			return &"left"
		Facing.LEFT_FRONT, Facing.LEFT_BACK:
			return &"right"
	return &"left"
