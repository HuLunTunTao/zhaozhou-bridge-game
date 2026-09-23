class_name LevelStateMachine
extends RefCounted

## 双轴关卡状态机：LevelPhase（生命周期）× ActiveOverlay（瞬态模态 UI）。
## 从 BaseLevel 抽出。通过 setup(context) 注入宿主 Callable，不反向依赖 BaseLevel。

signal phase_changed(new_phase: int)
signal overlay_opened(kind: int)
signal overlay_closed(kind: int)

## 关卡生命周期粗粒度时间线，单向转换 BRIEFING → PLAYING → ENDED。
enum LevelPhase { BRIEFING, PLAYING, ENDED }

## 当前独占前景的瞬态 UI。同时只能有一个非 NONE。统一替代原先 6 个独立 bool。
enum ActiveOverlay {
	NONE,
	BRIEFING_OBJECTIVES,
	DIALOGUE,
	CUTSCENE,
	OBJECTIVES_REVIEW,
	SETTINGS,
	PROGRESS,
	TUTORIAL_PANEL,
	GROWTH_CHOICE,
	DEFEAT_PANEL,
	KNOWLEDGE,
	SOCIAL_DIALOG,
	ARGUMENT_INPUT,
}

## LevelPhase 合法单向转换表：BRIEFING → PLAYING → ENDED，含 BRIEFING → ENDED 边缘情况。
const _PHASE_TRANSITIONS := {
	LevelPhase.BRIEFING: [LevelPhase.PLAYING, LevelPhase.ENDED],
	LevelPhase.PLAYING: [LevelPhase.ENDED],
	LevelPhase.ENDED: [],
}

var level_phase: LevelPhase = LevelPhase.BRIEFING
var active_overlay: ActiveOverlay = ActiveOverlay.NONE

## _begin_input_lock / _end_input_lock 嵌套计数。0 表示未锁。
var _input_lock_count: int = 0
## 进入锁前 camera.input_enabled 的快照，解锁时恢复（不假设原值为 true）。
var _saved_camera_input_enabled: bool = true

# ─── 宿主上下文 Callable（由 setup 注入） ───
var _get_tilemap: Callable = Callable()
var _is_waiting_for_player_input: Callable = Callable()
var _is_input_blocked: Callable = Callable()
var _lock_world_input: Callable = Callable()
var _unlock_world_input: Callable = Callable()
var _get_camera: Callable = Callable()
var _add_child: Callable = Callable()


## 注入宿主上下文。ctx 键：
##   get_tilemap / is_waiting_for_player_input / is_input_blocked /
##   lock_world_input / unlock_world_input / get_camera / add_child
func setup(ctx: Dictionary) -> void:
	_get_tilemap = ctx.get("get_tilemap", Callable())
	_is_waiting_for_player_input = ctx.get("is_waiting_for_player_input", Callable())
	_is_input_blocked = ctx.get("is_input_blocked", Callable())
	_lock_world_input = ctx.get("lock_world_input", Callable())
	_unlock_world_input = ctx.get("unlock_world_input", Callable())
	_get_camera = ctx.get("get_camera", Callable())
	_add_child = ctx.get("add_child", Callable())


func is_phase_playing() -> bool:
	return level_phase == LevelPhase.PLAYING


func is_phase_ended() -> bool:
	return level_phase == LevelPhase.ENDED


func has_overlay() -> bool:
	return active_overlay != ActiveOverlay.NONE


## from → to 是否为合法单向转换（不含相同值短路，由 _set_phase 自行处理）。
func _is_valid_phase_transition(from: LevelPhase, to: LevelPhase) -> bool:
	return to in _PHASE_TRANSITIONS[from]


func _set_phase(p: LevelPhase) -> void:
	if level_phase == p:
		return
	if not _is_valid_phase_transition(level_phase, p):
		push_warning("[LevelStateMachine] 非法阶段转换 %s → %s 已拒绝（单向 BRIEFING → PLAYING → ENDED）" % [
			LevelPhase.keys()[level_phase], LevelPhase.keys()[p],
		])
		return
	level_phase = p
	phase_changed.emit(p)


## 进入一个 overlay。若已有 overlay 则拒绝（互斥），node 由宿主 add_child 并挂关闭回调。
## closed_signal：关闭信号名（0 参或多参均可，实参会被忽略）。
## close_handler：可选自定义关闭 Callable，提供时替代默认关闭逻辑（需自行调用 _close_overlay）。
## 返回是否成功进入。
func _open_overlay(kind: ActiveOverlay, node: Node, closed_signal: StringName = &"closed", close_handler: Callable = Callable()) -> bool:
	if active_overlay != ActiveOverlay.NONE:
		return false
	active_overlay = kind
	if _add_child.is_valid():
		_add_child.call(node)
	if node.has_signal(closed_signal):
		var handler: Callable = close_handler if close_handler.is_valid() else _on_overlay_closed_signal.bind(kind)
		node.connect(closed_signal, handler, CONNECT_ONE_SHOT)
	overlay_opened.emit(kind)
	return true


## overlay 关闭信号的通用接收器：吞掉任意 arity 的信号实参，只做 _close_overlay。
## bind(kind) 预填 kind 后剩余形参全带默认值，兼容 0–4 参关闭信号。
func _on_overlay_closed_signal(kind: ActiveOverlay, _a = null, _b = null, _c = null, _d = null) -> void:
	_close_overlay(kind)


## 关闭当前 overlay。仅当 kind 匹配当前 active 时生效（防止竞态关错）。
func _close_overlay(kind: ActiveOverlay) -> void:
	if active_overlay != kind:
		return
	active_overlay = ActiveOverlay.NONE
	overlay_closed.emit(kind)


## 是否允许接收玩家命令。双轴状态机 + 既有子状态的联合闸门。
func _can_accept_command() -> bool:
	if level_phase != LevelPhase.PLAYING:
		return false
	if active_overlay != ActiveOverlay.NONE:
		return false
	if not _get_tilemap.is_valid() or _get_tilemap.call() == null:
		return false
	if not _is_waiting_for_player_input.is_valid() or not _is_waiting_for_player_input.call():
		return false
	if _is_input_blocked.is_valid() and _is_input_blocked.call():
		return false
	return true


## 进入"流程锁"。配对调用 _end_input_lock。支持嵌套（计数器）。
## 用于自由移动关卡的对话/输入面板等需要暂时屏蔽世界输入的场景。
func _begin_input_lock() -> void:
	if _input_lock_count == 0:
		if _get_camera.is_valid():
			var cam: Variant = _get_camera.call()
			if cam != null and "input_enabled" in cam:
				_saved_camera_input_enabled = cam.input_enabled
				cam.input_enabled = false
		if _lock_world_input.is_valid():
			_lock_world_input.call()
	_input_lock_count += 1


func _end_input_lock() -> void:
	_input_lock_count = maxi(0, _input_lock_count - 1)
	if _input_lock_count == 0:
		if _get_camera.is_valid():
			var cam: Variant = _get_camera.call()
			if cam != null and "input_enabled" in cam:
				cam.input_enabled = _saved_camera_input_enabled
		if _unlock_world_input.is_valid():
			_unlock_world_input.call()
