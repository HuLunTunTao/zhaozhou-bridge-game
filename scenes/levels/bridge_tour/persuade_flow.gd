class_name PersuadeFlow
extends SocialInteractionFlow

## 说服流（persuade）：ArgumentInputPanel 输入论点 → LLM 评 stance_delta → ≥70 视为说服。
## 2.24 收编 bridge_tour 的开场白轮换 / LLM 生成（含 cheat 注入）/ 计分规范化 / 结果落地 / 反馈轮换。
## prompt 装配字段、max_tokens / temperature、scoring 公式与返回 dict 结构与拆分前逐字一致。

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
	_opening = pick_opening(npc)
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
	panel.set_history(history_with_npc_prompt(npc, _opening))
	return panel


func _await_submission(panel: Node) -> String:
	if not _opening.is_empty():
		await play_npc_line(_npc, _opening, true, "bridge_persuade_opening")
	_level.add_child(panel)
	panel.show_for(_npc.unit_data.unit_name, _subtitle)
	return await panel.argument_submitted


func _generate(npc: Unit, submission: String) -> Dictionary:
	return await generate_answer(npc, submission)


func _apply(npc: Unit, result: Dictionary) -> void:
	apply_result(npc, result)


func _log(npc: Unit, submission: String, result: Dictionary) -> void:
	var tone := String(result.get("tone", ""))
	if _is_fallback(result):
		tone = "fallback"
	append_dialogue_log(npc, submission, _reply_text(result), tone, _opening)


func _reply_text(result: Dictionary) -> String:
	return String(result.get("reply", ""))


func _is_fallback(result: Dictionary) -> bool:
	return bool(result.get("is_fallback", false))


# ─────────────────────────────────────────────
# 领域逻辑（2.24 自 bridge_tour 移入）
# ─────────────────────────────────────────────


## 轮换取一句开场白；persona 无 persuade_opening 时 fallback 到 persuasion_goal.objection。
func pick_opening(npc: Unit) -> String:
	var persona: Dictionary = NpcPersonas.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var fallback_lines: Variant = persona.get("fallback_lines", {})
	var openings: Array = []
	if fallback_lines is Dictionary:
		var raw: Variant = (fallback_lines as Dictionary).get("persuade_opening", [])
		if raw is Array:
			openings = raw
	if openings.is_empty():
		var goal: Dictionary = _level._npc_state(npc).persuasion_goal
		return String(goal.get("objection", "")).strip_edges()
	var st: NpcSocialState = _level._npc_state(npc)
	var attempt: int = st.persuade_opening_attempt
	st.persuade_opening_attempt = attempt + 1
	return String(openings[attempt % openings.size()]).strip_edges()


## LLM 评累积分 + 本轮评分；命中作弊暗语整轮强制通过；LLM 失败走 cheat / rule 兜底。
func generate_answer(npc: Unit, topic: String) -> Dictionary:
	var cheat_word: String = _level._get_cheat_gate().matched_cheat_word(topic)
	var is_cheat := not cheat_word.is_empty()
	var st: NpcSocialState = _level._npc_state(npc)
	var persuasion_goal: Dictionary = st.persuasion_goal
	var result: Dictionary = await _level._get_llm_runner().run(npc, "bridge_topic_answer", "persuade", {
		"topic": topic,
		"bridge_part": st.bridge_part,
		"stance": st.stance,
		"persuasion_goal": persuasion_goal,
		"learned_csv": _level._get_llm_context_builder().learned_csv(),
		"learned_details": _level._get_llm_context_builder().learned_details_text(),
		"dialogue_history": _level._get_llm_context_builder().dialogue_history_text(npc),
		"mission_context": _level._get_llm_context_builder().mission_context_text(npc),
		"cheat_context": _level._get_cheat_gate().cheat_context_text(is_cheat, cheat_word),
		"accum_total": st.accum_score_total,
		"persuade_key_points": _level._get_key_point_matcher().persuade_key_points_text(persuasion_goal),
	}, {"max_tokens": 260, "temperature": 0.85}, "reply")
	var persona: Dictionary = result.get("persona", {})
	if result.get("ok", false):
		var parsed: Dictionary = result.get("parsed", {})
		if is_cheat:
			parsed["accum_score"] = _level.PERSUADE_ACCUM_SCORE_MAX
			parsed["round_score"] = _level.PERSUADE_ROUND_SCORE_MAX
			parsed["final_score"] = _level.PERSUADE_ACCUM_SCORE_MAX + _level.PERSUADE_ROUND_SCORE_MAX
			parsed["force_success"] = true
			parsed["is_cheat"] = true
		else:
			normalize_scores(parsed)
		if not parsed.has("tone"): parsed["tone"] = ""
		if not parsed.has("knowledge_used"): parsed["knowledge_used"] = []
		if not parsed.has("matched_points"): parsed["matched_points"] = []
		if not parsed.has("missed_points"): parsed["missed_points"] = []
		return parsed
	if is_cheat:
		return _level._get_cheat_gate().make_cheat_persuade_answer(npc)
	return _level._get_key_point_matcher().make_rule_persuade_answer(npc, topic, persona, persuasion_goal)


## 落地判分结果：stance 推进、知识入 used 集合、达标通知、MissionHud 同步、目标计数推进。
func apply_result(npc: Unit, ans: Dictionary) -> void:
	var force_success: bool = bool(ans.get("force_success", false))
	if not ans.has("final_score"):
		normalize_scores(ans)
	var accum_score: int = clampi(int(ans.get("accum_score", _level.PERSUADE_ACCUM_SCORE_MIN)), _level.PERSUADE_ACCUM_SCORE_MIN, _level.PERSUADE_ACCUM_SCORE_MAX)
	var round_score: int = clampi(int(ans.get("round_score", 0)), _level.PERSUADE_ROUND_SCORE_MIN, _level.PERSUADE_ROUND_SCORE_MAX)
	var final_score: int = int(ans.get("final_score", accum_score + round_score))
	if bool(ans.get("is_fallback", false)) and not force_success and not bool(ans.get("allow_fallback_score", false)):
		accum_score = 0
		round_score = 0
		final_score = 0
	var st: NpcSocialState = _level._npc_state(npc)
	var old_stance: int = st.stance
	var new_stance: int = _level.STANCE_PERSUADED if force_success else clampi(old_stance + final_score, 0, 100)
	st.stance = new_stance
	var accum_total: int = st.accum_score_total + accum_score
	st.accum_score_total = accum_total
	st.last_accum_score = accum_score
	st.last_round_score = round_score
	st.last_final_score = final_score
	# LLM 引用过的知识 → 加入 used 集合，知识面板高亮
	for k in ans.get("knowledge_used", []):
		var key := String(k)
		if not key.is_empty():
			_level._get_learned_view().add_used(key)
	var was_persuaded: bool = st.persuaded
	var now_persuaded: bool = new_stance >= _level.STANCE_PERSUADED
	if not was_persuaded and now_persuaded:
		st.persuaded = true
		Notify.notify("已说服 %s" % npc.unit_data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 3.0)
		_level._refresh_npc_name_label(npc)
		_level.get_end_flow().increment("persuade")
	elif final_score < 0:
		Notify.warn("%s 摇头：「此说不通」" % npc.unit_data.unit_name)
	if _level._mission_hud:
		_level._mission_hud.update_npc("persuade", npc.unit_data.unit_name, now_persuaded)
		_level._mission_hud.update_npc_stance(npc.unit_data.unit_name, new_stance, _level.STANCE_PERSUADED, accum_total, accum_score, round_score, final_score)
		_level._mission_hud.set_counts(_level.get_end_flow().get_progress("persuade"), _level.get_end_flow().get_progress("qa"))


## 归一化 LLM 给的分数字段（兼容 cumulative_score / stance_delta 别名）。
func normalize_scores(ans: Dictionary) -> void:
	var accum_score: int
	if ans.has("accum_score"):
		accum_score = int(ans.get("accum_score", _level.PERSUADE_ACCUM_SCORE_MIN))
	elif ans.has("cumulative_score"):
		accum_score = int(ans.get("cumulative_score", _level.PERSUADE_ACCUM_SCORE_MIN))
	else:
		accum_score = _level.PERSUADE_ACCUM_SCORE_MIN
	accum_score = clampi(accum_score, _level.PERSUADE_ACCUM_SCORE_MIN, _level.PERSUADE_ACCUM_SCORE_MAX)
	var round_score: int
	if ans.has("round_score"):
		round_score = int(ans.get("round_score", 0))
	elif ans.has("stance_delta"):
		round_score = int(ans.get("stance_delta", 0))
	else:
		round_score = 0
	round_score = clampi(round_score, _level.PERSUADE_ROUND_SCORE_MIN, _level.PERSUADE_ROUND_SCORE_MAX)
	ans["accum_score"] = accum_score
	ans["round_score"] = round_score
	ans["final_score"] = accum_score + round_score


## 说服成功反馈轮换；persona 无 persuade_success 台词时给固定句。
func pick_success_feedback(npc: Unit, persona: Dictionary) -> String:
	var lines: Array = DictUtil.fallback_lines_for(persona, "persuade_success")
	if lines.is_empty():
		return "这话说到点上了。"
	var st: NpcSocialState = _level._npc_state(npc)
	var attempt: int = st.persuade_success_attempt
	st.persuade_success_attempt = attempt + 1
	return String(lines[attempt % lines.size()]).strip_edges()
