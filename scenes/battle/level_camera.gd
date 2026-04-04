# 这个节点务必只能挂载在BaseLevel下

extends Camera2D
class_name LevelCamera

@export var pan_speed := 560.0
@export var smooth_speed := 8.0


@export var level_bounds: Rect2 = Rect2()
var target_position := Vector2.ZERO
var input_enabled := true


func _ready() -> void:
	make_current()
	target_position = global_position


func _process(delta: float) -> void:
	var input_vector := Vector2.ZERO
	if input_enabled:
		input_vector = Input.get_vector("left", "right", "up", "down")
	if input_vector != Vector2.ZERO:
		target_position += input_vector.normalized() * pan_speed * delta

	target_position = _clamp_to_bounds(target_position)
	global_position = global_position.lerp(target_position, 1.0 - exp(-smooth_speed * delta))


func set_level_bounds(new_bounds: Rect2) -> void:
	level_bounds = new_bounds
	target_position = _clamp_to_bounds(level_bounds.get_center())
	global_position = target_position


func center_on_bounds() -> void:
	target_position = _clamp_to_bounds(level_bounds.get_center())
	global_position = target_position


func _clamp_to_bounds(candidate: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size * zoom
	var half_view := viewport_size * 0.5
	var min_x := level_bounds.position.x + half_view.x
	var max_x := level_bounds.end.x - half_view.x
	var min_y := level_bounds.position.y + half_view.y
	var max_y := level_bounds.end.y - half_view.y

	if min_x > max_x:
		candidate.x = level_bounds.get_center().x
	else:
		candidate.x = clampf(candidate.x, min_x, max_x)

	if min_y > max_y:
		candidate.y = level_bounds.get_center().y
	else:
		candidate.y = clampf(candidate.y, min_y, max_y)

	return candidate

func get_level_bounds() -> Rect2:
	var level_node := get_parent() as BaseLevel
	if not level_node:
		push_error("LevelCamera must be a child of BaseLevel")
		return Rect2()
	return level_node.get_tilemap_bounds()
