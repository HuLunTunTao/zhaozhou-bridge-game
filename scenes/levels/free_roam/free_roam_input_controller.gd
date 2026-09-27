class_name FreeRoamInputController
extends RefCounted

## 自由移动社交关卡的输入状态机（Social Stack）。
##
## 与 BaseLevel 的 450 行战棋输入状态机相比，自由移动只需要：
##   点英雄 → 选中；点 NPC → 交互；点可达地 → 移动请求；ESC/右键 → 取消。
##
## 状态机（5 状态）：
##   IDLE            — 未选中
##   UNIT_SELECTED   — 已选中英雄
##   TARGETING_MOVE  — 移动请求已发出，等待 2.3 接执行
##   LOCKED          — 对话/思考中（_begin_input_lock）
##   ANIMATING       — 移动动画中
##
## 事件分发走 LevelStateMachine._can_accept_command 闸门。
## 2.3 会接 MovementManager + MoveOverlay 做可达范围预览与路径执行。

signal actor_selected(actor: Node2D)
signal actor_deselected()
signal move_requested(from_cell: Vector2i, to_cell: Vector2i)
signal interact_requested(actor: Node2D, target: Node2D)

enum S { IDLE, UNIT_SELECTED, TARGETING_MOVE, LOCKED, ANIMATING }

var _state: S = S.IDLE
var _selected_actor: Node2D = null

var _can_accept_command: Callable = Callable()
var _get_hero: Callable = Callable()
var _get_actors_at_cell: Callable = Callable()
var _get_cell_at_screen: Callable = Callable()


func setup(ctx: Dictionary) -> void:
	_can_accept_command = ctx.get("can_accept_command", Callable())
	_get_hero = ctx.get("get_hero", Callable())
	_get_actors_at_cell = ctx.get("get_actors_at_cell", Callable())
	_get_cell_at_screen = ctx.get("get_cell_at_screen", Callable())


func get_state() -> S:
	return _state


func set_state(s: S) -> void:
	_state = s


func is_blocked() -> bool:
	return _state == S.ANIMATING or _state == S.LOCKED


func get_selected_actor() -> Node2D:
	return _selected_actor


func select_actor(a: Node2D) -> void:
	_selected_actor = a
	_state = S.UNIT_SELECTED
	actor_selected.emit(a)


func deselect() -> void:
	if _selected_actor == null and _state == S.IDLE:
		return
	_selected_actor = null
	_state = S.IDLE
	actor_deselected.emit()


func handle_input(event: InputEvent) -> void:
	if is_blocked():
		return
	if _can_accept_command.is_valid() and not _can_accept_command.call():
		return
	# ESC / 右键 → 取消选中
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _state != S.IDLE:
			deselect()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _state != S.IDLE:
			deselect()
		return
	# 左键 / 触屏 tap → 选中 / 交互 / 移动请求
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_handle_click(event.position)


func _handle_click(screen_pos: Vector2) -> void:
	if not _get_cell_at_screen.is_valid():
		return
	var cell: Vector2i = _get_cell_at_screen.call(screen_pos)
	var actors: Array = _get_actors_at_cell.call(cell) if _get_actors_at_cell.is_valid() else []
	var hero: Node2D = _get_hero.call() if _get_hero.is_valid() else null
	for a in actors:
		if a == hero:
			if _state != S.UNIT_SELECTED:
				select_actor(hero)
			return
		else:
			if hero != null:
				interact_requested.emit(hero, a)
			return
	if _state == S.UNIT_SELECTED and hero != null and "cell" in hero:
		_state = S.TARGETING_MOVE
		move_requested.emit(hero.cell, cell)
	elif _state == S.TARGETING_MOVE and hero != null and "cell" in hero:
		_state = S.ANIMATING
		move_requested.emit(hero.cell, cell)
