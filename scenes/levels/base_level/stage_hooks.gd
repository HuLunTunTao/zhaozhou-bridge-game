class_name StageHooks
extends RefCounted

## 阶段接线器（Step 4.6）：把关卡的 `_on_stage_*` 处理器按声明表一次性接到领域信号上。
## 吸收 1-2 / 1-3 / 1-4 `_on_level_ready` 里的手写 connect 接线块；处理器本体留在关卡
## （各关机制不同），接线本身声明化，并记账支持一键断开。
##
## 用法：
##   _stage_hooks.setup(self)
##   _stage_hooks.connect_all({
##       "team_turn_started": _on_stage_team_turn_started,
##       "unit_hp_changed": _on_stage_hp_changed,
##       ...
##   })
## 键为 BaseLevel 领域信号名（StringName），值为处理器 Callable；
## 无对应信号 / 无效 Callable 的条目跳过并告警，不阻断其余接线。

var _source: Object = null
## 已接线记账：[[source, signal_name, handler], ...]
var _links: Array = []


func setup(source: Object) -> void:
	_source = source


## 声明式接线（幂等：同一 (signal, handler) 不会重复 connect）。
func connect_all(bindings: Dictionary) -> void:
	if _source == null:
		push_warning("StageHooks: setup() 未装配宿主，忽略接线")
		return
	for signal_name in bindings:
		var handler: Callable = bindings[signal_name]
		if not _source.has_signal(signal_name):
			push_warning("StageHooks: 宿主没有信号 %s，跳过" % signal_name)
			continue
		if not handler.is_valid():
			push_warning("StageHooks: 信号 %s 的处理器无效，跳过" % signal_name)
			continue
		if _source.is_connected(signal_name, handler):
			continue
		_source.connect(signal_name, handler)
		_links.append([_source, signal_name, handler])


## 断开本对象接过的全部信号（幂等）。
func disconnect_all() -> void:
	for link in _links:
		var source: Object = link[0]
		var signal_name: StringName = link[1]
		var handler: Callable = link[2]
		if source != null and is_instance_valid(source) and source.is_connected(signal_name, handler):
			source.disconnect(signal_name, handler)
	_links.clear()
