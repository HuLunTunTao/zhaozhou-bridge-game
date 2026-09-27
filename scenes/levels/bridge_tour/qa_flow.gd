class_name QaFlow
extends SocialInteractionFlow

## 解答流（qa）：NPC 抛预设问题 → 玩家作答 → LLM 判 is_correct → 记入已解。
## 2.24 收编 bridge_tour 的 LLM 判分（含 cheat 注入）与成功反馈轮换。
## prompt 装配字段、max_tokens / temperature、返回 dict 结构与拆分前逐字一致。

const _ArgumentInputPanelScene := preload("res://scenes/ui/argument_input_panel.tscn")
const _NpcPersonasScript := preload("res://scripts/llm/npc_personas.gd")

var _npc: Unit = null
var _question: String = ""
var _subtitle: String = ""


func _is_done(npc: Unit) -> bool:
	return _level._npc_state(npc).is_done()


func _done_message(npc: Unit) -> String:
	return "%s 的疑问已解" % npc.unit_data.unit_name


func _open_panel(npc: Unit) -> Node:
	_npc = npc
	var st: NpcSocialState = _level._npc_state(npc)
	_question = _pick_qa_question(npc)
	_subtitle = "%s · 「%s」" % [st.bridge_part, _question]
	# 面板先配置、暂不入树：问题要走 dialogue_box + TTS 播完才弹输入框（原 _flow_qa
	# 顺序）。播放挂在 _await_submission 开头，同 PersuadeFlow 的 pre-panel 模式。
	return _ArgumentInputPanelScene.instantiate()


func _await_submission(panel: Node) -> String:
	# 先让 NPC 把问题抛给玩家——dialogue_box 显示 + TTS（跳过即 cancel 语音，在 play_npc_line 内）
	await play_npc_line(_npc, _question, true)
	if _level == null or _level.is_phase_ended():
		return ""
	# 玩家输入答案；副标题用 NPC 名 + 桥部位
	_level.add_child(panel)
	panel.show_for(_npc.unit_data.unit_name, _subtitle)
	panel.set_learned_topics(_level._player_learned_topics, _level._player_used_topics)
	panel.set_history(history_with_npc_prompt(_npc, _question))
	var answer: String = await panel.argument_submitted
	if _level == null or _level.is_phase_ended():
		return ""
	return answer


func _thinking_message(npc: Unit) -> String:
	return "%s 正在判断……" % npc.unit_data.unit_name


func _generate(npc: Unit, submission: String) -> Dictionary:
	var eval: Dictionary = await generate_eval(npc, _question, submission)
	if _level == null or _level.is_phase_ended():
		return {}
	return eval


func _apply(npc: Unit, result: Dictionary) -> void:
	if result.is_empty():
		return
	for k in result.get("knowledge_used", []):
		var key := String(k)
		if not key.is_empty() and not _level._player_used_topics.has(key):
			_level._player_used_topics.append(key)
	var is_correct: bool = bool(result.get("is_correct", false))
	var st: NpcSocialState = _level._npc_state(npc)
	if is_correct and not st.qa_solved:
		st.qa_solved = true
		Notify.notify("已解答 %s 的疑问" % npc.unit_data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 3.0)
		_level._refresh_npc_name_label(npc)
		_level.get_end_flow().increment("qa")
	elif not is_correct:
		Notify.warn("%s 摇头：尚有疑虑" % npc.unit_data.unit_name)
	if _level._mission_hud:
		_level._mission_hud.update_npc("qa", npc.unit_data.unit_name, is_correct)
		_level._mission_hud.set_counts(_level.get_end_flow().get_progress("persuade"), _level.get_end_flow().get_progress("qa"))


func _log(npc: Unit, submission: String, result: Dictionary) -> void:
	if result.is_empty():
		return
	# 记入对话历史。问题用本轮抛出的 question + 玩家答案 + NPC feedback 三段拼接：
	# 历史每条同时保存 question，避免下次打开面板时丢掉 NPC 上轮问句。
	append_dialogue_log(npc, submission, _reply_text(result), "fallback" if _is_fallback(result) else "qa", _question)


func _reply_text(result: Dictionary) -> String:
	var text := String(result.get("feedback", ""))
	if bool(result.get("is_correct", false)):
		return text
	var missed: Array = result.get("missed_points", [])
	if missed.is_empty():
		return text
	var labels: Array[String] = []
	for m in missed:
		var s := String(m).strip_edges()
		if not s.is_empty():
			labels.append(s)
	if labels.is_empty():
		return text
	var hint := "提点：%s。" % "；".join(labels)
	if text.is_empty():
		return hint
	return "%s\n%s" % [text, hint]


func _is_fallback(result: Dictionary) -> bool:
	return bool(result.get("is_fallback", false))


# ─────────────────────────────────────────────
# 领域逻辑（2.24 自 bridge_tour 移入）
# ─────────────────────────────────────────────


## LLM 判 is_correct；命中作弊暗语强制通过；LLM 失败走 cheat / rule 兜底。
func generate_eval(npc: Unit, question: String, answer: String) -> Dictionary:
	var cheat_word: String = _level._get_cheat_gate().matched_cheat_word(answer)
	var is_cheat := not cheat_word.is_empty()
	var result: Dictionary = await _level._get_llm_runner().run(npc, "bridge_qa_eval", "qa", {
		"question": question,
		"answer": answer,
		"learned_csv": _level._get_llm_context_builder().learned_csv(),
		"learned_details": _level._get_llm_context_builder().learned_details_text(),
		"dialogue_history": _level._get_llm_context_builder().dialogue_history_text(npc),
		"mission_context": _level._get_llm_context_builder().mission_context_text(npc),
		"cheat_context": _level._get_cheat_gate().cheat_context_text(is_cheat, cheat_word),
		"qa_key_points": _level._get_key_point_matcher().qa_key_points_text(npc),
	}, {"max_tokens": 240, "temperature": 0.7}, "feedback")
	var persona: Dictionary = result.get("persona", {})
	if result.get("ok", false):
		var parsed: Dictionary = result.get("parsed", {})
		if is_cheat:
			parsed["is_correct"] = true
			parsed["is_cheat"] = true
		elif not parsed.has("is_correct"):
			parsed["is_correct"] = false
		if not parsed.has("knowledge_used"): parsed["knowledge_used"] = []
		return parsed
	if is_cheat:
		return _level._get_cheat_gate().make_cheat_qa_eval(npc)
	return _level._get_key_point_matcher().make_rule_qa_eval(npc, answer, persona)


## 解答成功反馈轮换；persona 无 qa_success 台词时给固定句。
func pick_success_feedback(npc: Unit, persona: Dictionary) -> String:
	var lines: Array = DictUtil.fallback_lines_for(persona, "qa_success")
	if lines.is_empty():
		return "这回说到点上了。"
	var st: NpcSocialState = _level._npc_state(npc)
	var attempt: int = st.qa_success_attempt
	st.qa_success_attempt = attempt + 1
	return String(lines[attempt % lines.size()]).strip_edges()


## 取一句 QA 问题。优先用 persona.qa_questions 数组按尝试次数轮换；空时 fallback 到旧
## qa_question 单字段；再空 fallback 到 spawn 时存的 state.qa_question；最终兜底固定句。
## 选完后 state.qa_attempt += 1 写回，供下次轮换。
func _pick_qa_question(npc: Unit) -> String:
	var persona: Dictionary = _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var st: NpcSocialState = _level._npc_state(npc)
	var attempt: int = st.qa_attempt
	var qs_raw: Variant = persona.get("qa_questions", [])
	var qs: Array = qs_raw if qs_raw is Array else []
	var picked: String = ""
	if not qs.is_empty():
		picked = String(qs[attempt % qs.size()])
	else:
		picked = String(persona.get("qa_question", ""))
	if picked.is_empty():
		picked = st.qa_question if not st.qa_question.is_empty() else "我有一事相问，可解么？"
	st.qa_attempt = attempt + 1
	return picked
