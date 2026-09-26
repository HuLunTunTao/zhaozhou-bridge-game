class_name TutorialRunner
extends RefCounted

## 教程运行器组件（Shared Kernel）。
## 从 BaseLevel 抽出：新手引导开关状态 / 重玩问询弹窗 / 李春教程对话单行构造。
## 通过 setup(level) 持有宿主关卡，对 _level 保持鸭子调用，不反向依赖 BaseLevel。
## 另含 TutorialStep 步进引擎（run_steps，Step 4.1）；教程面板按钮（_on_tutorial_button_pressed）在 LevelUIBridge。

## overlay 枚举（真源在 LevelStateMachine，此处保留旧名供注解使用）。
const ActiveOverlay = LevelStateMachine.ActiveOverlay

var _level: Node = null   # BaseLevel 宿主

## 关卡脚本可在新手引导等流程中置为 true，暂停所有战场闲聊触发。
var tutorial_onboarding_active: bool = false


func setup(level: Node) -> void:
	_level = level


func set_tutorial_onboarding_active(active: bool) -> void:
	tutorial_onboarding_active = active
	_level.set_meta("tutorial/onboarding_active", active)


func is_tutorial_onboarding_active() -> bool:
	return tutorial_onboarding_active


## 复玩问询：已看过教程的玩家进关时弹 yes/no 菜单，问要不要再听李春讲解一遍。
## TopicMenuPanel 是 ModalPanel，自带 closed 信号，走 _open_overlay 统一闸门。
func ask_tutorial_replay() -> bool:
	var menu_scene: PackedScene = preload("res://scenes/ui/topic_menu_panel.tscn")
	var menu := menu_scene.instantiate() as TopicMenuPanel
	if not _level._open_overlay(ActiveOverlay.TUTORIAL_PANEL, menu):
		menu.queue_free()
		return false
	menu.show_yes_no(
		"上次已经听过李春讲解，是否再听一遍？",
		"再听一遍",
		"跳过，直接开打",
	)
	var pick: String = await menu.topic_picked
	return pick == "再听一遍"


## 李春教程对话单行构造：自动带头像、左侧显示，并按当前关卡匹配预生成 TTS。
func lc_line(text: String, can_skip: bool = true) -> DialogueLine:
	return _level._dialogue._lc_line(text, can_skip)


func tutorial_tts_level_id() -> String:
	return _level._dialogue._tutorial_tts_level_id()


# ─────────────────────────────────────────────
# 步进引擎（TutorialStep 数组）
# ─────────────────────────────────────────────

## 逐步执行 TutorialStep 数组。每步：播放 dialogue → 显示 hint（若有）→ 按 wait_mode 等待 → 下一步。
## 玩家跳过对话不中断步进（跳过即完成本段对话，照常进入提示 / 等待）。
## 每个 await 后守卫：关卡已销毁或已 ENDED 则立即终止，剩余步骤不再执行。
## 全程 await 关卡信号，不做逐帧轮询。
func run_steps(steps: Array[TutorialStep]) -> void:
	for step: TutorialStep in steps:
		if _is_level_gone() or _level.is_phase_ended():
			return
		if step == null:
			continue
		if not step.dialogue.is_empty():
			await _level.play_dialogue(build_lines(step.dialogue))
			if _is_level_gone() or _level.is_phase_ended():
				return
		if not step.hint.is_empty():
			Notify.hint(step.hint, step.hint_duration)
		await _wait_for_step(step)
		if _is_level_gone() or _level.is_phase_ended():
			return


## 按 wait_mode 等待一步完成：DIALOGUE_DONE 直接完成；SIGNAL 等一次触发；
## PREDICATE 等价 `while not wait_predicate.call(args): await wait_signal`（入口先以空 args 预检）。
func _wait_for_step(step: TutorialStep) -> void:
	match step.wait_mode:
		TutorialStep.WaitMode.DIALOGUE_DONE:
			pass
		TutorialStep.WaitMode.SIGNAL:
			if step.wait_signal.is_empty():
				return
			await Signal(_level, step.wait_signal)
		TutorialStep.WaitMode.PREDICATE:
			if step.wait_signal.is_empty() or not step.wait_predicate.is_valid():
				return
			var arg_count := _signal_arg_count(step.wait_signal)
			var args: Array = []
			while not step.wait_predicate.call(args):
				var fired = await Signal(_level, step.wait_signal)
				if _is_level_gone() or _level.is_phase_ended():
					return
				args = _signal_args(fired, arg_count)


## dialogue 行 dict → DialogueLine。speaker 缺省 / 空 /「李春」走 lc_line（保留预生成 TTS）。
func build_lines(rows: Array[Dictionary]) -> Array[DialogueLine]:
	var lines: Array[DialogueLine] = []
	for row: Dictionary in rows:
		var speaker := String(row.get("speaker", "李春"))
		var text := String(row.get("text", ""))
		var can_skip := bool(row.get("can_skip", true))
		if speaker.is_empty() or speaker == "李春":
			lines.append(lc_line(text, can_skip))
		else:
			lines.append(DialogueLine.create(speaker, text, null, "left", null, null, can_skip))
	return lines


## await 信号的返回值归一成实参列表：多参信号返回 Array，单参返回该值本身，无参返回 null。
## arg_count 为信号声明的形参个数，用来区分「单参 null 实参」和「无参信号」。
func _signal_args(fired, arg_count: int) -> Array:
	if arg_count <= 0:
		return []
	if arg_count == 1:
		return [fired]
	return fired if fired is Array else []


## wait_signal 在宿主关卡上声明的形参个数（找不到信号时按 1 处理）。
func _signal_arg_count(sig: StringName) -> int:
	if _is_level_gone():
		return 1
	for info: Dictionary in _level.get_signal_list():
		if StringName(info.get("name", "")) == sig:
			return (info.get("args", []) as Array).size()
	return 1


## 宿主关卡是否已销毁（queue_free 后引用仍在，必须用 is_instance_valid）。
func _is_level_gone() -> bool:
	return _level == null or not is_instance_valid(_level)
