# 这个节点务必只能挂载在BaseLevel下

extends Camera2D
class_name LevelCamera

@export var pan_speed := 560.0
@export var smooth_speed := 8.0
@export var edge_margin := 16.0 ## 鼠标距屏幕边缘多少像素时触发滚动
@export var zoom_step := 0.1 ## 每次滚轮缩放的幅度
@export var min_zoom := 0.5 ## 最小缩放（看到更多）
@export var max_zoom := 2.0 ## 最大缩放（看到更少）
@export var zoom_smooth_speed := 8.0


@export var level_bounds: Rect2 = Rect2()
var target_position := Vector2.ZERO
var target_zoom := Vector2.ONE
var input_enabled := true


func _ready() -> void:
	make_current()
	target_position = global_position
	target_zoom = zoom


func _process(delta: float) -> void:
	var input_vector := Vector2.ZERO
	if input_enabled:
		input_vector = Input.get_vector("left", "right", "up", "down")
		if input_vector != Vector2.ZERO:
			input_vector = input_vector.normalized()
		else:
			input_vector = _get_edge_scroll_vector()
			if input_vector.length() > 1.0:
				input_vector = input_vector.normalized()
	if input_vector != Vector2.ZERO:
		target_position += input_vector * pan_speed * delta

	target_position = _clamp_to_bounds(target_position)
	global_position = global_position.lerp(target_position, 1.0 - exp(-smooth_speed * delta))
	zoom = zoom.lerp(target_zoom, 1.0 - exp(-zoom_smooth_speed * delta))


func set_level_bounds(new_bounds: Rect2) -> void:
	level_bounds = new_bounds
	target_position = _clamp_to_bounds(level_bounds.get_center())
	global_position = target_position


func center_on_bounds() -> void:
	target_position = _clamp_to_bounds(level_bounds.get_center())
	global_position = target_position


func _clamp_to_bounds(candidate: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size / zoom
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

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom += Vector2.ONE * zoom_step
			target_zoom = target_zoom.clampf(min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom -= Vector2.ONE * zoom_step
			target_zoom = target_zoom.clampf(min_zoom, max_zoom)


func _get_edge_scroll_vector() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var mouse_pos := viewport.get_mouse_position()
	var vp_size := viewport.get_visible_rect().size
	var result := Vector2.ZERO
	if mouse_pos.x < edge_margin:
		result.x = -(1.0 - mouse_pos.x / edge_margin)
	elif mouse_pos.x > vp_size.x - edge_margin:
		result.x = 1.0 - (vp_size.x - mouse_pos.x) / edge_margin
	if mouse_pos.y < edge_margin:
		result.y = -(1.0 - mouse_pos.y / edge_margin)
	elif mouse_pos.y > vp_size.y - edge_margin:
		result.y = 1.0 - (vp_size.y - mouse_pos.y) / edge_margin
	return result


func get_level_bounds() -> Rect2:
	var level_node := get_parent() as BaseLevel
	if not level_node:
		push_error("LevelCamera must be a child of BaseLevel")
		return Rect2()
	return level_node.get_tilemap_bounds()
