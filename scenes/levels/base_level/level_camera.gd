# 这个节点务必只能挂载在BaseLevel下

extends Camera2D
class_name LevelCamera

@export var pan_speed := 560.0
@export var smooth_speed := 8.0
@export var zoom_step := 0.1 ## 每次滚轮缩放的幅度
@export var min_zoom := 0.5 ## 最小缩放（看到更多）
@export var max_zoom := 2.0 ## 最大缩放（看到更少）
@export var zoom_smooth_speed := 8.0


@export var drag_threshold := 4.0 ## 右键拖拽的像素阈值，低于此值视为点击


@export var level_bounds: Rect2 = Rect2()
var target_position := Vector2.ZERO
var target_zoom := Vector2.ONE
var input_enabled := true
var _right_pressed := false
var _is_dragging := false
var _drag_start := Vector2.ZERO
var _drag_accumulated := Vector2.ZERO

## 多点触控状态（移动端/触摸屏）。键=触点 index，值=最近一次屏幕坐标。
## 单指触摸交给 base_level 做点选/移动，相机只在出现 2 个及以上触点时介入。
var _touches: Dictionary = {}
## 双指捏合的初始两指距离，作为缩放比例的基准。
var _pinch_initial_distance: float = 0.0
## 双指捏合开始时的 target_zoom 快照，用于按比例计算新缩放。
var _pinch_initial_zoom: Vector2 = Vector2.ONE
## 上一帧两指中点（屏幕坐标），用于计算两指拖动相机位移。
var _pinch_last_midpoint: Vector2 = Vector2.ZERO

## 锁定跟随的目标。非 null 时 _process 会每帧把相机拉到其位置，并禁用玩家手动操作。
var _lock_target: Node2D = null
## 进入 lock_on 之前的 target_zoom，unlock 时按需恢复。
var _zoom_before_lock: Vector2 = Vector2.ONE
## 进入 lock_on 之前的 input_enabled，unlock 时恢复（防止锁定前就是禁用态的边缘情况）。
var _input_enabled_before_lock: bool = true


func _ready() -> void:
	make_current()
	target_position = global_position
	target_zoom = zoom


func _process(delta: float) -> void:
	# 镜头锁定：优先跟随目标，跳过玩家输入/边缘滚动。
	if _lock_target != null:
		if not is_instance_valid(_lock_target):
			unlock()
		else:
			target_position = _clamp_to_bounds(_lock_target.global_position)
			global_position = global_position.lerp(target_position, 1.0 - exp(-smooth_speed * delta))
			zoom = zoom.lerp(target_zoom, 1.0 - exp(-zoom_smooth_speed * delta))
			return

	var input_vector := Vector2.ZERO
	if input_enabled:
		input_vector = Input.get_vector("left", "right", "up", "down")
		if input_vector != Vector2.ZERO:
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


## 锁定镜头到一个节点。锁定期间：
##   - 每帧把 target_position 拉到该节点的 global_position；
##   - 玩家键盘/边缘滚动/右键拖拽/滚轮缩放输入全部失效；
##   - 按 lock_zoom 设定缩放（<= 0 时不改动缩放）。
## 典型用法：`(camera as LevelCamera).lock_on(hero, 1.4)`。
##   - target    : 要跟随的节点（必须仍在场景树里）
##   - lock_zoom : 锁定期间的缩放系数；默认 1.3（轻微放大），会被 min/max_zoom 夹取
##   - instant   : 是否立即贴到目标（跳过平滑），默认 false 走平滑过渡
func lock_on(target: Node2D, lock_zoom: float = 1.3, instant: bool = false) -> void:
	if target == null or not is_instance_valid(target):
		return
	if _lock_target == null:
		_zoom_before_lock = target_zoom
		_input_enabled_before_lock = input_enabled
	_lock_target = target
	input_enabled = false
	if lock_zoom > 0.0:
		target_zoom = Vector2(lock_zoom, lock_zoom).clampf(min_zoom, max_zoom)
	target_position = _clamp_to_bounds(target.global_position)
	if instant:
		global_position = target_position
		zoom = target_zoom


## 解除锁定，恢复玩家手动控制。restore_zoom=true 时回到锁定前的缩放。
func unlock(restore_zoom: bool = true) -> void:
	if _lock_target == null:
		return
	_lock_target = null
	input_enabled = _input_enabled_before_lock
	if restore_zoom:
		target_zoom = _zoom_before_lock


func is_locked() -> bool:
	return _lock_target != null and is_instance_valid(_lock_target)


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
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_right_pressed = true
				_is_dragging = false
				_drag_start = event.position
				_drag_accumulated = Vector2.ZERO
			else:
				_right_pressed = false
				if _is_dragging:
					_is_dragging = false
					get_viewport().set_input_as_handled()
		elif event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_zoom += Vector2.ONE * zoom_step
				target_zoom = target_zoom.clampf(min_zoom, max_zoom)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				target_zoom -= Vector2.ONE * zoom_step
				target_zoom = target_zoom.clampf(min_zoom, max_zoom)
	elif event is InputEventMouseMotion and _right_pressed:
		_drag_accumulated += event.relative
		if not _is_dragging and _drag_accumulated.length() >= drag_threshold:
			_is_dragging = true
		if _is_dragging:
			target_position -= event.relative / zoom
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)
	elif event is InputEventMagnifyGesture:
		# 触控板捏合（macOS / 部分 Linux）。factor>1 放大，<1 缩小。
		target_zoom *= (event as InputEventMagnifyGesture).factor
		target_zoom = target_zoom.clampf(min_zoom, max_zoom)
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		# 触控板双指拖动（系统派发，与多点触摸独立）。
		var pan := (event as InputEventPanGesture).delta
		target_position += pan / zoom
		get_viewport().set_input_as_handled()


## 触点按下/抬起：维护 _touches，并在双指出现/消失时初始化或清空捏合基准。
## 单指触摸不消费事件，留给 base_level 走点选 / 移动。
## 第二指落下的瞬间会触发 _emit_cancel_action()，行为镜像鼠标右键按下。
func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 2:
			_begin_pinch()
			# 双指按下 = 鼠标右键：base_level 的 cancel_action() 自带状态闸门，
			# 仅在 TARGETING_MOVE / TARGETING_SKILL 时真正取消，其它状态下是无害空操作。
			_emit_cancel_action()
			get_viewport().set_input_as_handled()
		elif _touches.size() > 2:
			# 三指及以上不做手势识别，但仍然消费事件防止穿透到 base_level 误触。
			get_viewport().set_input_as_handled()
	else:
		var was_two_or_more := _touches.size() >= 2
		_touches.erase(event.index)
		if was_two_or_more:
			get_viewport().set_input_as_handled()
		if _touches.size() == 2:
			# 从 3+ 指降到 2 指，重新建立捏合基准。
			_begin_pinch()
		elif _touches.size() < 2:
			_pinch_initial_distance = 0.0


## 触点拖动：更新 _touches 中对应 index 的最新位置，再按当前两指状态做缩放 + 平移。
func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if _touches.size() < 2:
		return
	var positions: Array = _touches.values()
	if positions.size() > 2:
		positions = positions.slice(0, 2)
	var p0: Vector2 = positions[0]
	var p1: Vector2 = positions[1]
	var distance: float = p0.distance_to(p1)
	var midpoint: Vector2 = (p0 + p1) * 0.5

	# 双指缩放：相对初始距离比，按 _pinch_initial_zoom 等比扩缩。
	if _pinch_initial_distance > 0.0 and distance > 0.0:
		var ratio: float = distance / _pinch_initial_distance
		target_zoom = (_pinch_initial_zoom * ratio).clampf(min_zoom, max_zoom)

	# 双指拖动：用中点位移驱动相机位移（屏幕坐标 → 世界坐标除以 zoom）。
	var midpoint_delta: Vector2 = midpoint - _pinch_last_midpoint
	_pinch_last_midpoint = midpoint
	target_position -= midpoint_delta / zoom
	get_viewport().set_input_as_handled()


## 进入双指手势时记下基准距离 / 中点 / 缩放，后续 drag 都基于这组初始值算 delta。
func _begin_pinch() -> void:
	var positions: Array = _touches.values()
	if positions.size() < 2:
		return
	var p0: Vector2 = positions[0]
	var p1: Vector2 = positions[1]
	_pinch_initial_distance = max(p0.distance_to(p1), 1.0)
	_pinch_initial_zoom = target_zoom
	_pinch_last_midpoint = (p0 + p1) * 0.5


## 触发 BaseLevel.cancel_action()，等价鼠标右键按下；非 targeting 状态下是无害空操作。
func _emit_cancel_action() -> void:
	var parent := get_parent()
	if parent != null and parent.has_method("cancel_action"):
		parent.call("cancel_action")



func get_level_bounds() -> Rect2:
	var level_node := get_parent() as BaseLevel
	if not level_node:
		push_error("LevelCamera must be a child of BaseLevel")
		return Rect2()
	return level_node.get_tilemap_bounds()
