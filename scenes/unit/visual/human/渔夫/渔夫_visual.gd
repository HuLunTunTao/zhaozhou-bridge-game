extends UnitVisual
## 渔夫：单方向单帧动画，所有 facing/state 都映射到唯一的 default 动画。
## sprite_frames 仅有 "default"；走路/朝向通过 flip_h 实现。

func _resolve_anim_name(_facing: Facing, _state: StringName) -> StringName:
	return &"default"
