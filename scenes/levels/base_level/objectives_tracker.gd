class_name ObjectivesTracker
extends RefCounted

## 目标跟踪组件（Tactics Stack）。
## 从 BaseLevel 抽出：胜负条件检查分发（先 defeat 后 victory）。
## 通过 setup(level) 持有宿主关卡，对 _level 保持鸭子调用，不反向依赖 BaseLevel。
## 不含虚方法契约（check_victory / check_defeat / get_objectives_text 留在 BaseLevel 供子类覆写）、
## 目标面板展示（show_objectives 在 LevelUIBridge）、胜负流程收尾（complete_level / defeat_level 在 LevelFlow）。

var _level: Node = null   # BaseLevel 宿主


func setup(level: Node) -> void:
	_level = level


## 执行胜负条件检查。在关键事件（倒下、回合开始）后自动调用。
## 单帧延迟等状态刷新后再判定，非轮询。
func check_win_lose(_arg = null) -> void:
	if _level.is_phase_ended():
		return
	await _level.get_tree().process_frame
	if _level.is_phase_ended():
		return
	var defeat_reason: String = _level.check_defeat()
	if defeat_reason != "":
		_level.defeat_level(defeat_reason)
		return
	if _level.check_victory():
		_level.complete_level()
