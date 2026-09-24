class_name MentorFlow
extends SocialInteractionFlow

## 求教流（mentor）：TopicMenuPanel 选题 → LLM 讲解 → 记入已学 → 播台词。
## 2.24 收编 bridge_tour 的 LLM 讲解生成与已学知识落地。
## prompt 装配字段、max_tokens / temperature、返回 dict 结构与拆分前逐字一致。

const FREE_PICK := "__free__"

const _TopicMenuPanelScene := preload("res://scenes/ui/topic_menu_panel.tscn")
const _ArgumentInputPanelScene := preload("res://scenes/ui/argument_input_panel.tscn")
const _PersonaFallbackScript := preload("res://scripts/llm/persona_fallback.gd")
const _BridgeKnowledgeScript := preload("res://scripts/data/bridge_knowledge.gd")

var _npc: Unit = null


func _is_done(_npc: Unit) -> bool:
	return false


func _done_message(_npc: Unit) -> String:
	return ""


func _open_panel(npc: Unit) -> Node:
	_npc = npc
	var st: NpcSocialState = _level._npc_state(npc)
	var menu: Node = _TopicMenuPanelScene.instantiate()
	_level.add_child(menu)
	menu.show_for(npc.unit_data.unit_name, st.mentor_topics)
	return menu


func _await_submission(panel: Node) -> String:
	var pick: String = await panel.topic_picked
	if pick.is_empty():
		return ""
	if pick != FREE_PICK:
		return pick
	var inp: Node = _ArgumentInputPanelScene.instantiate()
	_level.add_child(inp)
	inp.show_for(_npc.unit_data.unit_name, "向 %s 自由请教" % _npc.unit_data.unit_name)
	inp.set_learned_topics(_level._player_learned_topics, _level._player_used_topics)
	return await inp.argument_submitted


func _thinking_message(npc: Unit) -> String:
	return "%s 正在斟酌讲法……" % npc.unit_data.unit_name


func _generate(npc: Unit, submission: String) -> Dictionary:
	return await generate_lesson(npc, submission)


func _apply(npc: Unit, result: Dictionary) -> void:
	apply_lesson(npc, result)


func _log(npc: Unit, submission: String, result: Dictionary) -> void:
	append_dialogue_log(npc, submission, _reply_text(result), "fallback" if _is_fallback(result) else "mentor")


func _reply_text(result: Dictionary) -> String:
	return String(result.get("reply", ""))


func _is_fallback(result: Dictionary) -> bool:
	return bool(result.get("is_fallback", false))


# ─────────────────────────────────────────────
# 领域逻辑（2.24 自 bridge_tour 移入）
# ─────────────────────────────────────────────


## LLM 按提问挑一个 BridgeKnowledge.TOPICS 讲解；失败时给 persona 兜底且标记 is_fallback。
func generate_lesson(npc: Unit, query: String) -> Dictionary:
	var result: Dictionary = await _level._get_llm_runner().run(npc, "bridge_knowledge_explain", "mentor", {
		"query": query,
		"topics_csv": _BridgeKnowledgeScript.key_to_title_csv(),
	}, {"max_tokens": 320, "temperature": 0.7}, "reply")
	var persona: Dictionary = result.get("persona", {})
	if result.get("ok", false):
		var parsed: Dictionary = result.get("parsed", {})
		if not parsed.has("topic_key"):
			parsed["topic_key"] = ""
		return parsed
	return {
		"reply": _PersonaFallbackScript.pick(persona, "mentor"),
		"topic_key": "",
		"is_fallback": true,
	}


## topic_key 记入"已学"（需在 BridgeKnowledge 里能查到）。
func apply_lesson(npc: Unit, lesson: Dictionary) -> void:
	var key: String = String(lesson.get("topic_key", "")).strip_edges()
	if key.is_empty():
		return
	# 要在 BridgeKnowledge 里能找到这个 key 才算"学到"
	var topic: Dictionary = _BridgeKnowledgeScript.get_topic(key)
	if topic.is_empty():
		return
	if _level._get_learned_view().add_learned(key):
		Notify.notify(
			"向 %s 学到了「%s」" % [npc.unit_data.unit_name, topic.get("title", key)],
			Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 3.5
		)
