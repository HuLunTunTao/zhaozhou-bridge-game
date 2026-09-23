class_name StatusBarBridge
extends Node

## 状态栏桥接组件：从 BaseLevel 抽出的状态栏联动。
## 通过 setup(ctx) 注入宿主 Callable（风格与 LevelStateMachine.setup 一致），不反向依赖 BaseLevel。

# ─── 宿主上下文 Callable（由 setup 注入） ───
var _get_status_bar: Callable = Callable()
var _get_hero: Callable = Callable()


## 注入宿主上下文。ctx 键：get_status_bar / get_hero
func setup(ctx: Dictionary) -> void:
	_get_status_bar = ctx.get("get_status_bar", Callable())
	_get_hero = ctx.get("get_hero", Callable())


## 更新状态栏显示指定单位的信息。
func show_unit_for(unit: Node2D, is_active: bool = false) -> void:
	var status_bar: Node = _get_status_bar.call() if _get_status_bar.is_valid() else null
	if status_bar and status_bar.has_method("show_unit"):
		status_bar.show_unit(unit, is_active)


## 状态栏回退显示主角（无主角时清空）。
func reset_to_hero() -> void:
	var status_bar: Node = _get_status_bar.call() if _get_status_bar.is_valid() else null
	if status_bar == null:
		return
	var hero: Node2D = _get_hero.call() if _get_hero.is_valid() else null
	if hero and status_bar.has_method("show_unit"):
		status_bar.show_unit(hero, false)
	elif status_bar.has_method("clear_unit"):
		status_bar.clear_unit()
