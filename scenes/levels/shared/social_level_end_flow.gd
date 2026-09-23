class_name SocialLevelEndFlow
extends RefCounted

## 目标计数驱动的通关流（Shared Kernel / Social Stack）。
## 自由移动社交关卡用：`add_goal("persuade", 3, "说服")` + `increment("persuade")` → 全达标 emit `all_goals_met`。
## 与 `BaseLevel._check_win_lose` 的战棋胜负判据解耦——本类只管"目标计数 → complete_level"，
## 失败条件由宿主覆写 `check_defeat() -> String`，在 `check_end_conditions()` 里统一派发。
##
## 幂等约定：`all_goals_met` 只 emit 一次直到 `reset()`；`complete_level` / `defeat_level` 自身幂等，
## 两条路径（`all_goals_met` 自动 + 子类手动调 `check_end_conditions`）同时触发安全。

signal goal_updated(goal_id: String, current: int, target: int)
signal all_goals_met

## goal_id -> {current: int, target: int, label: String}
var _goals: Dictionary = {}
## 是否已 emit 过 all_goals_met（幂等，reset() 才清）
var _all_goals_emitted: bool = false


## 注册一个目标。target <= 0 视为 1（防御：0 目标会让 is_all_met() 恒 true）。
func add_goal(goal_id: String, target: int, label: String = "") -> void:
	_goals[goal_id] = {
		"current": 0,
		"target": maxi(1, target),
		"label": label,
	}


## 目标进度推进 delta（默认 +1）。未知 goal_id 静默忽略。
## 每次调用 emit `goal_updated`；若全部达标且此前未 emit，再 emit `all_goals_met`（幂等）。
func increment(goal_id: String, delta: int = 1) -> void:
	set_progress(goal_id, get_progress(goal_id) + delta)


## 直接设定目标进度。未知 goal_id 静默忽略。语义同 increment。
func set_progress(goal_id: String, current: int) -> void:
	if not _goals.has(goal_id):
		return
	var goal: Dictionary = _goals[goal_id]
	var target: int = goal["target"]
	goal["current"] = clampi(current, 0, target)
	goal_updated.emit(goal_id, goal["current"], target)
	_maybe_emit_all_met()


func get_progress(goal_id: String) -> int:
	return int(_goals.get(goal_id, {}).get("current", 0))


func get_target(goal_id: String) -> int:
	return int(_goals.get(goal_id, {}).get("target", 0))


func is_met(goal_id: String) -> bool:
	if not _goals.has(goal_id):
		return false
	return get_progress(goal_id) >= get_target(goal_id)


func is_all_met() -> bool:
	if _goals.is_empty():
		return false
	for goal_id in _goals:
		if not is_met(goal_id):
			return false
	return true


## 汇总进度文本，如 "3/3 说服，2/4 解答"。无 label 的目标只输出 "2/4"。
func get_progress_text() -> String:
	var parts: PackedStringArray = []
	for goal_id in _goals:
		var goal: Dictionary = _goals[goal_id]
		var piece := "%d/%d" % [goal["current"], goal["target"]]
		var label := String(goal.get("label", ""))
		if not label.is_empty():
			piece += " " + label
		parts.append(piece)
	return "，".join(parts)


## 全部目标的进度快照（返回副本，外部改动不影响内部）。
func get_goals_summary() -> Dictionary:
	var out: Dictionary = {}
	for goal_id in _goals:
		var goal: Dictionary = _goals[goal_id]
		out[goal_id] = {
			"current": int(goal["current"]),
			"target": int(goal["target"]),
			"label": String(goal.get("label", "")),
		}
	return out


## 清空全部目标进度并允许再次 emit `all_goals_met`。
func reset() -> void:
	for goal_id in _goals:
		_goals[goal_id]["current"] = 0
	_all_goals_emitted = false


## 达标且未 emit 过时发一次 `all_goals_met`。
func _maybe_emit_all_met() -> void:
	if _all_goals_emitted or not is_all_met():
		return
	_all_goals_emitted = true
	all_goals_met.emit()
