class_name RoamingAI
extends Node
## NPC 漫游状态机。挂在 Unit 节点下，用 Timer 驱动每 N 秒动一次。
##
## 三种模式：
##   STATIONARY  : 不动
##   PATROL      : 沿 waypoints 循环
##   RANDOM_WALK : 每次随机选一个 4 邻接可走格
##
## 暂停条件：
##   - level._interaction_target == _unit（玩家正和我对话）
##   - hero 紧贴（曼哈顿 ≤ 1）—— 避免擦身错位

enum Mode { STATIONARY, PATROL, RANDOM_WALK }

@export var mode: Mode = Mode.STATIONARY
@export var waypoints: Array[Vector2i] = []
@export var move_interval_min: float = 2.0
@export var move_interval_max: float = 4.0

var _unit: Unit
var _level: Node = null
var _waypoint_index: int = 0
var _timer: Timer = null


## 设置依赖与模式。waypoints_value 接受任意 Array（PATROL 用），内部按 Vector2i 复制。
## 这样调用方可以从 Dictionary 字面量直接传未带类型的 Array 不报错。
func setup(unit: Unit, level: Node, mode_value: int = Mode.STATIONARY, waypoints_value: Array = []) -> void:
	_unit = unit
	_level = level
	mode = mode_value as Mode
	waypoints.clear()
	for v in waypoints_value:
		if v is Vector2i:
			waypoints.append(v)
		elif v is Vector2:
			waypoints.append(Vector2i(int(v.x), int(v.y)))


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_step)
	add_child(_timer)
	# 起手延迟随机一点，避免所有 NPC 同帧动
	_timer.start(randf_range(move_interval_min, move_interval_max))


func _step() -> void:
	if not _is_unit_alive() or _level == null:
		return
	if _should_pause():
		_schedule_next()
		return
	match mode:
		Mode.STATIONARY:
			pass
		Mode.PATROL:
			await _do_patrol_step()
		Mode.RANDOM_WALK:
			await _do_random_step()
	if _is_unit_alive():
		_schedule_next()


func _schedule_next() -> void:
	if _timer == null or not is_inside_tree():
		return
	_timer.start(randf_range(move_interval_min, move_interval_max))


func _should_pause() -> bool:
	if _unit == null or _unit.is_moving:
		return true
	# 任何 NPC 正在和玩家对话 → 全员停（包括"现在没在被对话的"也别抢戏）
	if _level.has_method("get_interaction_target") and _level.get_interaction_target() != null:
		return true
	# 关卡有 overlay（设置面板 / dialogue_box / 输入面板等）→ 暂停一拍
	if _level.has_method("has_overlay") and _level.has_overlay():
		return true
	# Hero 紧贴 → 避免擦身错位；Hero 在 tween 中 → 全员停（避免 NPC 步入 hero 终点格的竞态）
	if _level.hero != null and is_instance_valid(_level.hero) and _level.hero is Unit:
		var hero_unit := _level.hero as Unit
		if hero_unit.is_moving:
			return true
		var hero_cell: Vector2i = hero_unit.cell
		var d: Vector2i = hero_cell - _unit.cell
		if absi(d.x) + absi(d.y) <= 1:
			return true
	return false


func _do_patrol_step() -> void:
	if waypoints.is_empty():
		return
	var target: Vector2i = waypoints[_waypoint_index]
	# 走完当前目标后切下一个 waypoint
	if _unit.cell == target:
		_waypoint_index = (_waypoint_index + 1) % waypoints.size()
		target = waypoints[_waypoint_index]
	var step := _step_toward(_unit.cell, target)
	if step == Vector2i.ZERO:
		return
	await _try_step(step)


func _do_random_step() -> void:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	dirs.shuffle()
	for d in dirs:
		if await _try_step(d):
			return


func _try_step(step: Vector2i) -> bool:
	var next: Vector2i = _unit.cell + step
	if _level == null or _level.movement_manager == null:
		return false
	if _level.movement_manager.get_movement_cost(next) < 0:
		return false
	if _is_cell_occupied(next):
		return false
	if _level.tilemap == null:
		return false
	_unit.move_along_path([_unit.cell, next], _level.tilemap)
	await _unit.move_finished
	return true


func _step_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	# 朴素 4 邻接逼近：先纠正 x，再纠正 y。被障碍卡住时本拍跳过。
	if from.x != to.x:
		return Vector2i(signi(to.x - from.x), 0)
	if from.y != to.y:
		return Vector2i(0, signi(to.y - from.y))
	return Vector2i.ZERO


func _is_cell_occupied(cell: Vector2i) -> bool:
	if _level == null or not "teams" in _level:
		return false
	for team in _level.teams:
		for u in team.units:
			if u == _unit:
				continue
			if is_instance_valid(u) and u is Unit and (u as Unit).cell == cell:
				return true
	return false


func _is_unit_alive() -> bool:
	return _unit != null and is_instance_valid(_unit) and _unit.is_inside_tree()
