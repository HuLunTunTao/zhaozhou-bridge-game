class_name MentorFlow
extends SocialInteractionFlow

## 求教流（mentor）：TopicMenuPanel 选题 → LLM 讲解 → 记入已学 → 播台词。
## 从 bridge_tour._flow_mentor 抽出。_generate_mentor_lesson / _apply_mentor_lesson
## 仍留在 bridge_tour（2.16 LLMInteractionRunner 再抽 LLM 胶水）。

const FREE_PICK := "__free__"

const _TopicMenuPanelScene := preload("res://scenes/ui/topic_menu_panel.tscn")
const _ArgumentInputPanelScene := preload("res://scenes/ui/argument_input_panel.tscn")

var _npc: Unit = null


func _is_done(_npc: Unit) -> bool:
	return false


func _done_message(_npc: Unit) -> String:
	return ""


func _open_panel(npc: Unit) -> Node:
	_npc = npc
	var st: NpcSocialState = _level._state(npc)
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
	var lesson: Dictionary = await _level._generate_mentor_lesson(npc, submission)
	return lesson


func _apply(npc: Unit, result: Dictionary) -> void:
	_level._apply_mentor_lesson(npc, result)


func _log(npc: Unit, submission: String, result: Dictionary) -> void:
	_level._append_dialogue_log(npc, submission, _reply_text(result), "fallback" if _is_fallback(result) else "mentor")


func _reply_text(result: Dictionary) -> String:
	return String(result.get("reply", ""))


func _is_fallback(result: Dictionary) -> bool:
	return bool(result.get("is_fallback", false))
