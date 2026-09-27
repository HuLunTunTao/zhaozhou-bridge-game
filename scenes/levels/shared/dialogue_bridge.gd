class_name DialogueBridge
extends Node

## 对话桥接组件：从 BaseLevel 抽出的对话 / TTS 逻辑。
## 通过 setup(ctx) 注入宿主 Callable（风格与 LevelStateMachine.setup 一致），不反向依赖 BaseLevel。

const NpcPersonasScript := preload("res://scripts/llm/npc_personas.gd")
const PortraitResolverScript := preload("res://scripts/llm/portrait_resolver.gd")
const DialogueBoxScene := preload("res://scenes/ui/dialogue_box.tscn")

# ─── 宿主上下文 Callable（由 setup 注入） ───
var _open_overlay: Callable = Callable()
var _has_overlay: Callable = Callable()
var _get_level_node: Callable = Callable()
var _get_li_chun_portrait: Callable = Callable()


## 注入宿主上下文。ctx 键：
##   open_overlay / has_overlay / get_level_node / get_li_chun_portrait
func setup(ctx: Dictionary) -> void:
	_open_overlay = ctx.get("open_overlay", Callable())
	_has_overlay = ctx.get("has_overlay", Callable())
	_get_level_node = ctx.get("get_level_node", Callable())
	_get_li_chun_portrait = ctx.get("get_li_chun_portrait", Callable())


## 播放一段对话。阻塞直到对话结束。用法：await play_dialogue([line1, line2])
## auto_dismiss=true 时走"打字机结束后自动飘过"，用于单位闲聊（chatter）；
## 默认 false 保持原有"点击/空格推进"行为，关卡剧情调用无需改动。
func play_dialogue(lines: Array[DialogueLine], auto_dismiss: bool = false, dismiss_delay: float = 2.5) -> void:
	var box = DialogueBoxScene.instantiate()
	if not _open_overlay.is_valid() \
			or not _open_overlay.call(LevelStateMachine.ActiveOverlay.DIALOGUE, box, &"dialogue_finished"):
		box.queue_free()
		return
	box.start(lines, auto_dismiss, dismiss_delay)
	await box.dialogue_finished


## 李春教程对话单行构造：自动带头像、左侧显示，并按当前关卡匹配预生成 TTS。
func _lc_line(text: String, can_skip: bool = true) -> DialogueLine:
	var portrait: Texture2D = _get_li_chun_portrait.call() if _get_li_chun_portrait.is_valid() else null
	return DialogueLine.create(
		"李春",
		text,
		portrait,
		"left",
		null,
		TutorialTtsIndex.get_audio(_tutorial_tts_level_id(), "hero_li_chun", text),
		can_skip
	)


func _tutorial_tts_level_id() -> String:
	if not _get_level_node.is_valid():
		return ""
	var level: Node = _get_level_node.call()
	if level == null:
		return ""
	var path := level.scene_file_path
	if path.is_empty():
		var script := level.get_script() as Script
		if script != null:
			path = script.resource_path
	var basename := path.get_file().get_basename()
	return basename if not basename.is_empty() else String(level.name)


## 单行 chatter 对话的便捷入口。单位阵营决定头像左右，头像来自 PortraitResolver，自动飘过。
## 返回值：true 表示对话已播放完毕；false 表示被拒绝（已有 overlay 占用）。
func play_chatter_dialogue(unit: Node, text: String, dismiss_delay: float = 2.5) -> bool:
	if unit == null or not (unit is Unit) or text.is_empty():
		return false
	var u := unit as Unit
	if u.unit_data == null:
		return false
	NpcPersonasScript.get_persona(
		u.unit_data.unit_id,
		u.unit_data.camp
	)
	var line := DialogueLine.create(
		u.combat_stats.unit_name if u.combat_stats != null else u.unit_data.unit_name,
		text,
		PortraitResolverScript.get_portrait(u),
		PortraitResolverScript.side_for_unit(u),
		PortraitResolverScript.get_portrait_bg(u)
	)
	# 如果已有 overlay（别的对话/面板在跑），chatter 直接放弃本次
	if _has_overlay.is_valid() and _has_overlay.call():
		return false
	await play_dialogue([line], true, dismiss_delay)
	return true


## 多行 chatter 对话（邻接对话的双人场景用）。每条 line 已由调用方准备好 portrait/side。
## voice_handle: 可选 TTS 句柄（鸭子接口：is_streaming() / streaming_done 信号），
##   传入后 auto_dismiss 会等语音播完 +0.5s 才关；不传则只看 dismiss_delay 与文字打完。
## 返回 `{"ok": bool, "was_skipped": bool}`：
##   - ok=false 表示被拒绝（已有 overlay）；was_skipped 此时无意义
##   - was_skipped=true 表示玩家手动按键/点击关闭，false 表示 auto_dismiss 自然结束
func play_chatter_lines(lines: Array[DialogueLine], dismiss_delay: float = 2.0, voice_handle: Node = null) -> Dictionary:
	if lines.is_empty() or (_has_overlay.is_valid() and _has_overlay.call()):
		return {"ok": false, "was_skipped": false}
	var box = DialogueBoxScene.instantiate()
	if not _open_overlay.is_valid() \
			or not _open_overlay.call(LevelStateMachine.ActiveOverlay.DIALOGUE, box, &"dialogue_finished"):
		box.queue_free()
		return {"ok": false, "was_skipped": false}
	box.start(lines, true, dismiss_delay, voice_handle)
	await box.dialogue_finished
	# emit 在 queue_free 前，节点本帧仍在树上；was_skipped 已被 _finish 写入。
	var skipped: bool = box.was_skipped if is_instance_valid(box) else false
	return {"ok": true, "was_skipped": skipped}
