class_name PersuadeFlow
extends SocialInteractionFlow

## 说服流（persuade）：ArgumentInputPanel 输入论点 → LLM 评 stance_delta → ≥70 视为说服。
## 从 bridge_tour._flow_persuade 抽出（流程骨架部分）。
## LLM 生成与 apply 暂留 bridge_tour（2.16 LLMInteractionRunner 再抽）。

const _ArgumentInputPanelScene := preload("res://scenes/ui/argument_input_panel.tscn")

var _npc: Unit = null
## 本轮开场白。_open_panel 取出后存下，_log 复用（原 _flow_persuade 里是局部变量直传）。
var _opening: String = ""
var _subtitle: String = ""


func _is_done(npc: Unit) -> bool:
	return _level._npc_state(npc).persuaded


func _done_message(npc: Unit) -> String:
	return "已说服 %s" % npc.unit_data.unit_name


func _open_panel(npc: Unit) -> Node:
	_npc = npc
	var st: NpcSocialState = _level._npc_state(npc)
	_opening = _level._pick_persuade_opening(npc)
	_subtitle = st.bridge_part
	if not _opening.is_empty():
		_subtitle = "%s · 「%s」" % [st.bridge_part, _opening]
	# 面板先配置、暂不入树：开场白要走 dialogue_box + TTS 播完才弹输入框（原
	# _flow_persuade 顺序）。模板没有 pre-panel 钩子，播放挂在 _await_submission 开头；
	# setter 走 ModalPanel 的 pending 缓存，ready 前调用安全。
	var panel: Node = _ArgumentInputPanelScene.instantiate()
	panel.set_persuasion_goal(st.persuasion_goal)
	panel.set_persuade_base_total(st.accum_score_total)
	panel.set_learned_topics(_level._player_learned_topics, _level._player_used_topics)
	panel.set_history(_level._history_with_npc_prompt(npc, _opening))
	return panel


func _await_submission(panel: Node) -> String:
	if not _opening.is_empty():
		await _level._play_npc_line(_npc, _opening, true, "bridge_persuade_opening")
	_level.add_child(panel)
	panel.show_for(_npc.unit_data.unit_name, _subtitle)
	return await panel.argument_submitted


func _generate(npc: Unit, submission: String) -> Dictionary:
	return await _level._generate_persuade_answer(npc, submission)


func _apply(npc: Unit, result: Dictionary) -> void:
	_level._apply_persuade_result(npc, result)


func _log(npc: Unit, submission: String, result: Dictionary) -> void:
	var tone := String(result.get("tone", ""))
	if _is_fallback(result):
		tone = "fallback"
	_level._append_dialogue_log(npc, submission, _reply_text(result), tone, _opening)


func _reply_text(result: Dictionary) -> String:
	return String(result.get("reply", ""))


func _is_fallback(result: Dictionary) -> bool:
	return bool(result.get("is_fallback", false))
