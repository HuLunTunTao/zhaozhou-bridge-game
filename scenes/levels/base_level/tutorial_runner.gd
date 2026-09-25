class_name TutorialRunner
extends RefCounted

## 教程运行器组件（Shared Kernel）。
## 从 BaseLevel 抽出：新手引导开关状态 / 重玩问询弹窗 / 李春教程对话单行构造。
## 通过 setup(level) 持有宿主关卡，对 _level 保持鸭子调用，不反向依赖 BaseLevel。
## 不含教程步进逻辑（在各关卡子类，Step 4 收编）、教程面板按钮（_on_tutorial_button_pressed 在 LevelUIBridge）。

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
