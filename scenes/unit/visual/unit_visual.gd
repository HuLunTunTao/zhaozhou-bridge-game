class_name UnitVisual
extends AnimatedSprite2D
## 单位动画视觉组件。
## 提供统一的动画播放、朝向、颜色、描边 API。
## 子类可覆写 _resolve_anim_name() 实现不同动画行为。
##
## 约定：Visual 下有一个 Marker2D "FootMarker" 标记脚底位置（在 Visual 本地坐标系）。
## unit.gd 根据 FootMarker 自动定位 Visual 和 HpBar。

enum Facing { RIGHT_FRONT, RIGHT_BACK, LEFT_FRONT, LEFT_BACK }

## move 和 idle 使用相同动画（只有一组帧时设为 true）。
@export var move_is_idle: bool = false
## 使用水平翻转实现左右转向（只有一侧方向的精灵时启用）。
@export var flip_h_for_turning: bool = false
## 精灵图的原始朝向是否朝左。启用后翻转逻辑会取反。
@export var default_facing_left: bool = false
## HP 条距脚底的高度（像素）。不同体型的单位可调整此值。
@export var hp_bar_height: float = 40.0

var _current_facing: Facing = Facing.RIGHT_FRONT


func _ready() -> void:
	_make_unique()
	frame_changed.connect(_update_frame_uv_rect)
	animation_changed.connect(_update_frame_uv_rect)
	_update_frame_uv_rect()


# ─────────────────────────────────────────────
# 公开 API（由 unit.gd 调用）
# ─────────────────────────────────────────────

## 返回脚底标记在 Unit 坐标系中的偏移（已乘以 Visual 的 scale）。
## unit.gd 用此值定位 Visual：visual.position = -get_foot_offset()
func get_foot_offset() -> Vector2:
	var marker := get_node_or_null("FootMarker") as Marker2D
	if marker:
		return marker.position * scale
	return Vector2.ZERO


## 播放指定状态的动画（&"idle" 或 &"move"）。
func play_state(state: StringName) -> void:
	var resolved_state := state
	if move_is_idle and state == &"move":
		resolved_state = &"idle"
	var anim_name := _resolve_anim_name(_current_facing, resolved_state)
	if sprite_frames and sprite_frames.has_animation(anim_name):
		play(anim_name)


## 设置朝向。若 flip_h_for_turning 为 true，根据 default_facing_left 决定翻转方向。
func set_facing(facing: Facing) -> void:
	_current_facing = facing
	if flip_h_for_turning:
		var want_left := (facing == Facing.LEFT_FRONT or facing == Facing.LEFT_BACK)
		flip_h = want_left if not default_facing_left else not want_left


## 设置单位叠加颜色。
func set_unit_color(color: Color) -> void:
	self_modulate = color


## 设置已行动变暗/恢复。
func set_acted(acted: bool) -> void:
	modulate = Color(0.5, 0.5, 0.55, 0.75) if acted else Color.WHITE


## 设置描边颜色（shader uniform）。
func set_outline_color(color: Color) -> void:
	var mat := material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("outline_color", color)


## 替换整个精灵帧资源（用于占位精灵等）。
func replace_sprite_frames(new_frames: SpriteFrames) -> void:
	sprite_frames = new_frames


# ─────────────────────────────────────────────
# 内部方法（可覆写）
# ─────────────────────────────────────────────

## 根据朝向和状态解析动画名。子类可覆写以支持不同命名规范。
func _resolve_anim_name(facing: Facing, state: StringName) -> StringName:
	var dir := _facing_to_string(facing)
	return StringName(dir + "_" + String(state))


func _facing_to_string(facing: Facing) -> String:
	if flip_h_for_turning:
		if default_facing_left:
			match facing:
				Facing.LEFT_FRONT, Facing.RIGHT_FRONT:
					return "left_front"
				Facing.LEFT_BACK, Facing.RIGHT_BACK:
					return "left_back"
		else:
			match facing:
				Facing.RIGHT_FRONT, Facing.LEFT_FRONT:
					return "right_front"
				Facing.RIGHT_BACK, Facing.LEFT_BACK:
					return "right_back"
	match facing:
		Facing.RIGHT_FRONT:
			return "right_front"
		Facing.RIGHT_BACK:
			return "right_back"
		Facing.LEFT_FRONT:
			return "left_front"
		Facing.LEFT_BACK:
			return "left_back"
	return "right_front"


## 资源唯一化：避免实例间共享导致互相影响。
func _make_unique() -> void:
	if sprite_frames:
		sprite_frames = sprite_frames.duplicate()
	if material is ShaderMaterial:
		material = material.duplicate()


## 更新 shader 的 frame_uv_rect，使描边采样限制在当前帧区域内。
func _update_frame_uv_rect() -> void:
	var mat := material as ShaderMaterial
	if mat == null or sprite_frames == null:
		return
	var anim := animation
	var idx := frame
	if idx < 0 or idx >= sprite_frames.get_frame_count(anim):
		return
	var tex := sprite_frames.get_frame_texture(anim, idx)
	if tex is AtlasTexture:
		var atlas_tex := tex as AtlasTexture
		if atlas_tex.atlas == null:
			return
		var atlas_size := atlas_tex.atlas.get_size()
		var r := atlas_tex.region
		mat.set_shader_parameter("frame_uv_rect", Vector4(
			r.position.x / atlas_size.x,
			r.position.y / atlas_size.y,
			(r.position.x + r.size.x) / atlas_size.x,
			(r.position.y + r.size.y) / atlas_size.y
		))
	else:
		# 非 AtlasTexture（独立纹理），整张都是当前帧
		mat.set_shader_parameter("frame_uv_rect", Vector4(0.0, 0.0, 1.0, 1.0))
