class_name TaskChain
extends RefCounted

## 任务链组件（Step 4.2 四关数据化）。
## 管理线性任务列表 + 当前索引，吸收关卡里的 TaskState 枚举 / _current_task / _advance_to_taskN。
## 任务条目 schema：
##   "id": StringName              任务标识（查询 / 调试）。
##   "objective_text": String | Callable(mode: int) -> String
##                                 目标行文案。Callable 时按 DisplayMode 返回三种展示形态。
##   "hint_text": String | Callable() -> String
##                                 顶部提示条文案（允许带进度插值的动态文案）。
##   "on_enter": Callable          进入该任务时的进场副作用（可异步；按旧 `_advance_to_taskN()` 裸调语义
##                                 不被 await，协程由其 await 的信号 / 计时器自行续命）。
##   "marker_cell": Vector2i       任务指引标记所在格（多点任务取代表格）。
## 通过 setup(level) 持有宿主关卡，对 _level 保持鸭子调用，不反向依赖 BaseLevel。

## objective_text 的展示形态：未解锁 / 当前 / 已完成（目标面板按此渲染全链）。
enum DisplayMode { PENDING, ACTIVE, DONE }

var _level: Node = null   # BaseLevel 宿主

var current_index: int = 0
var tasks: Array[Dictionary] = []


## 任务条目快捷构造（返回标准 schema 字典）。
static func task(id: StringName, objective_text: Variant, hint_text: Variant,
		on_enter: Callable = Callable(), marker_cell: Vector2i = Vector2i.ZERO) -> Dictionary:
	return {
		"id": id,
		"objective_text": objective_text,
		"hint_text": hint_text,
		"on_enter": on_enter,
		"marker_cell": marker_cell,
	}


func setup(level: Node) -> void:
	_level = level


## 装载任务链。不触发 on_enter（开局任务的进场动作由关卡自行安排）。
func configure(p_tasks: Array[Dictionary], start_index: int = 0) -> void:
	tasks = []
	for t in p_tasks:
		tasks.append(t.duplicate())
	current_index = clampi(start_index, 0, maxi(tasks.size() - 1, 0))


func size() -> int:
	return tasks.size()


## 当前是否停在指定任务上。
func is_at(index: int) -> bool:
	return current_index == index


func current_id() -> StringName:
	return get_id_at(current_index)


func is_at_id(id: StringName) -> bool:
	return current_id() == id


func get_id_at(index: int) -> StringName:
	if index < 0 or index >= tasks.size():
		return &""
	return StringName(str(_entry(index).get("id", "")))


## 跳到指定任务并触发其 on_enter。越界索引自动夹回合法区间（末任务会重进一次）。
func advance_to(index: int) -> void:
	if tasks.is_empty():
		return
	current_index = clampi(index, 0, tasks.size() - 1)
	_fire_on_enter()


## 前进一格；已在末任务时不动作（避免重复触发 on_enter）。
func advance_next() -> void:
	if current_index >= tasks.size() - 1:
		return
	advance_to(current_index + 1)


## 当前任务的目标行文案（ACTIVE 形态）。
func get_current_objective() -> String:
	return get_objective_at(current_index, DisplayMode.ACTIVE)


## 指定任务在给定展示形态下的目标行文案。
func get_objective_at(index: int, mode: int = DisplayMode.ACTIVE) -> String:
	if index < 0 or index >= tasks.size():
		return ""
	var v: Variant = _entry(index).get("objective_text", "")
	if v is Callable:
		var c := v as Callable
		return str(c.call(mode)) if c.is_valid() else ""
	return str(v)


## 全链目标行（目标面板用）：未解锁 PENDING / 当前 ACTIVE / 已完成 DONE。
func get_objective_lines() -> Array[String]:
	var lines: Array[String] = []
	for i in tasks.size():
		var mode: int = DisplayMode.PENDING
		if i < current_index:
			mode = DisplayMode.DONE
		elif i == current_index:
			mode = DisplayMode.ACTIVE
		lines.append(get_objective_at(i, mode))
	return lines


## 当前任务的顶部提示条文案。
func get_current_hint() -> String:
	return _hint_at(current_index)


## 当前任务的指引标记格。
func get_current_marker_cell() -> Vector2i:
	return get_marker_cell_at(current_index)


func get_marker_cell_at(index: int) -> Vector2i:
	if index < 0 or index >= tasks.size():
		return Vector2i.ZERO
	var v: Variant = _entry(index).get("marker_cell", Vector2i.ZERO)
	return v if v is Vector2i else Vector2i.ZERO


func _entry(index: int) -> Dictionary:
	return tasks[index]


func _hint_at(index: int) -> String:
	if index < 0 or index >= tasks.size():
		return ""
	var v: Variant = _entry(index).get("hint_text", "")
	if v is Callable:
		var c := v as Callable
		return str(c.call()) if c.is_valid() else ""
	return str(v)


func _fire_on_enter() -> void:
	var v: Variant = _entry(current_index).get("on_enter", Callable())
	if v is Callable:
		var c := v as Callable
		if c.is_valid():
			c.call()
