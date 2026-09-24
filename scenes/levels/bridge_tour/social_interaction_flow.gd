class_name SocialInteractionFlow
extends RefCounted

## 验桥日社交交互流程骨架（模板方法）。
## 子类覆写 _is_done / _done_message / _open_panel / _await_submission /
## _thinking_message / _generate / _apply / _log / _reply_text / _is_fallback。
## 共同骨架 run() 走：done 检查 → 面板 → await 提交 → thinking → LLM → apply → log → 邻居插话 → 播台词。
##
## 对话呈现工具（append_dialogue_log / history_with_npc_prompt / play_npc_line /
## show_thinking / hide_thinking）2.24 自 bridge_tour 移入，三个 flow 与
## NeighborInterjecter 共用。
##
## _level 是 bridge_tour（FreeRoamSocialLevel 子类），对 _npc_state / _get_voice /
## _get_neighbor_interjecter / play_chatter_lines / add_child 保持鸭子调用。

const _ThinkingOverlayScene := preload("res://scenes/ui/thinking_overlay.tscn")
const _PortraitResolverScript := preload("res://scripts/llm/portrait_resolver.gd")

var _level: Node = null   # bridge_tour（FreeRoamSocialLevel 子类）


func setup(level: Node) -> void:
	_level = level


func run(npc: Unit) -> void:
	if _is_done(npc):
		Notify.info(_done_message(npc), 1.5)
		return
	var panel := _open_panel(npc)
	if panel == null:
		return
	var submission := await _await_submission(panel)
	if submission.is_empty():
		return
	var thinking: CanvasLayer = show_thinking(_thinking_message(npc))
	var result := await _generate(npc, submission)
	hide_thinking(thinking)
	_apply(npc, result)
	_log(npc, submission, result)
	var reply := _reply_text(result)
	var is_fallback := _is_fallback(result)
	var neighbor_spec: Dictionary = _level._get_neighbor_interjecter().start_interject(npc, reply)
	await play_npc_line(npc, reply, not is_fallback)
	await _level._get_neighbor_interjecter().play_pending(neighbor_spec, self)


# ─────────────────────────────────────────────
# 对话呈现工具
# ─────────────────────────────────────────────


## 把一轮交互写入 NPC 的 dialogue_log meta。供 set_history 显示给玩家看。
## question 只在 QA 流程传入，用于在玩家答案前恢复 NPC 的提问。
## tone 字段可记 "fallback" / "qa" / LLM 给的 tone 标签，便于将来分类（当前未做特殊渲染）。
func append_dialogue_log(npc: Unit, player: String, npc_text: String, tone: String, question: String = "") -> void:
	var st: NpcSocialState = _level._npc_state(npc)
	var history: Array = st.dialogue_log
	var entry := {
		"player": player,
		"npc": npc_text,
		"npc_name": npc.unit_data.unit_name,
		"tone": tone,
	}
	if not question.strip_edges().is_empty():
		entry["question"] = question.strip_edges()
	history.append(entry)
	st.dialogue_log = history


## 给输入面板显示"当前 NPC 刚问的话"，但不立即写入持久历史；
## 玩家取消时不会留下半截对话，提交后由 append_dialogue_log 保存完整问答。
func history_with_npc_prompt(npc: Unit, prompt_text: String) -> Array:
	var history: Array = _level._npc_state(npc).dialogue_log.duplicate()
	var clean_prompt := prompt_text.strip_edges()
	if clean_prompt.is_empty():
		return history
	history.append({
		"npc": clean_prompt,
		"npc_name": npc.unit_data.unit_name,
		"tone": "question_preview",
	})
	return history


## 播一句 NPC 台词。LLM 已在调用前完整返回；这里才启动 TTS 流式播放。
func play_npc_line(
	npc: Unit,
	text: String,
	with_voice: bool = true,
	trigger_kind: String = "bridge_topic_answer"
) -> bool:
	if text.is_empty():
		return false
	# is_fallback=true 时（with_voice=false）跳过火山 TTS，但优先注入 pre-baked。
	# AudioStreamMP3 让 dialogue_box 自己播——这样 fallback 文本仍能听到 NPC 自己音色。
	var pre_baked: AudioStream = null
	if not with_voice:
		pre_baked = TtsFallbackIndex.get_fallback_audio(npc.unit_data.unit_id, text)
	var line := DialogueLine.create(
		npc.unit_data.unit_name,
		text,
		_PortraitResolverScript.get_portrait(npc),
		_PortraitResolverScript.side_for_unit(npc),
		_PortraitResolverScript.get_portrait_bg(npc),
		pre_baked,
	)
	var result: Dictionary
	if with_voice:
		_level._get_voice().speak(npc, text, trigger_kind)
		result = await _level.play_chatter_lines([line], 2.0, _level._get_voice())
	else:
		result = await _level.play_chatter_lines([line], 2.0)
	var was_skipped: bool = bool(result.get("was_skipped", false))
	if was_skipped and with_voice and _level._get_voice().is_streaming():
		_level._get_voice().cancel()
	return was_skipped


func show_thinking(message: String = "……（思忖中）……") -> CanvasLayer:
	var ov := _ThinkingOverlayScene.instantiate()
	if ov.has_method("set_message"):
		ov.set_message(message)
	_level.add_child(ov)
	return ov


func hide_thinking(ov: CanvasLayer) -> void:
	if ov != null and is_instance_valid(ov):
		ov.queue_free()


# ─────────────────────────────────────────────
# 子类覆写
# ─────────────────────────────────────────────


func _is_done(_npc: Unit) -> bool:
	return false


func _done_message(_npc: Unit) -> String:
	return ""


func _open_panel(_npc: Unit) -> Node:
	return null


func _await_submission(_panel: Node) -> String:
	return ""


func _thinking_message(npc: Unit) -> String:
	return "%s 正在思量……" % npc.unit_data.unit_name


func _generate(_npc: Unit, _submission: String) -> Dictionary:
	return {}


func _apply(_npc: Unit, _result: Dictionary) -> void:
	pass


func _log(_npc: Unit, _submission: String, _result: Dictionary) -> void:
	pass


func _reply_text(result: Dictionary) -> String:
	return String(result.get("reply", ""))


func _is_fallback(result: Dictionary) -> bool:
	return bool(result.get("is_fallback", false))
