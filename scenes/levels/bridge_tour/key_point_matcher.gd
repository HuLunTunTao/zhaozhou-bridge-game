class_name KeyPointMatcher
extends RefCounted

## 验桥日关键点匹配 + 规则兜底：把玩家自由输入与 persuasion_goal / qa_key_points
## 的关键词组做规范化子串匹配，LLM 失败时据此生成 rule_match 兜底结果。
## 匹配算法（groups / alternatives / hit_count 阈值）、标点替换表、scoring 公式、
## 返回 dict 结构与 key-point 列表文案均与拆分前逐字一致。
##
## _level 是 bridge_tour，对 _npc_state / _persuade_flow / _qa_flow 及常量
## PERSUADE_ACCUM_SCORE_MIN/MAX / PERSUADE_ROUND_SCORE_MIN/MAX 保持鸭子调用；
## 纯字符串 / 字典工具直接走 DictUtil。

const _PersonaFallbackScript := preload("res://scripts/llm/persona_fallback.gd")

var _level: Node = null   # bridge_tour


func setup(level: Node) -> void:
	_level = level


func key_point_matches(answer: String, point: Dictionary) -> bool:
	var normalized := normalize_match_text(answer)
	if normalized.is_empty():
		return false
	var groups: Array = DictUtil.get_dict_array(point, "groups")
	if groups.is_empty():
		return false
	var hit_count := 0
	for group_v in groups:
		var alternatives: Array = group_v if group_v is Array else [group_v]
		var hit := false
		for keyword_v in alternatives:
			var keyword := normalize_match_text(String(keyword_v))
			if not keyword.is_empty() and normalized.find(keyword) >= 0:
				hit = true
				break
		if hit:
			hit_count += 1
	var required_hits: int = mini(groups.size(), maxi(2, groups.size() - 1))
	return hit_count >= required_hits


func normalize_match_text(text: String) -> String:
	var out := text.strip_edges().to_lower()
	for ch in [" ", "\n", "\t", "，", "。", "、", "？", "！", "：", "；", "“", "”", "「", "」", "（", "）", "(", ")", ",", ".", "?", "!", ":", ";"]:
		out = out.replace(ch, "")
	return out


func qa_key_points_text(npc: Unit) -> String:
	var key_points: Array = _level._npc_state(npc).qa_key_points
	if key_points.is_empty():
		return "（未配置；按问题语义宽松判断）"
	var lines: Array[String] = []
	for point_v in key_points:
		if not (point_v is Dictionary):
			continue
		var point: Dictionary = point_v
		var label := String(point.get("label", "")).strip_edges()
		if label.is_empty():
			continue
		var keys: Array = DictUtil.get_dict_array(point, "knowledge_keys")
		var suffix := ""
		if not keys.is_empty():
			suffix = "；关联知识 key：" + "、".join(DictUtil.string_array(keys))
		lines.append("- %s%s" % [label, suffix])
	return "\n".join(lines) if not lines.is_empty() else "（未配置；按问题语义宽松判断）"


func persuade_key_points_text(persuasion_goal: Dictionary) -> String:
	var key_points: Array = DictUtil.get_dict_array(persuasion_goal, "key_points")
	if key_points.is_empty():
		return "（未配置；按说服目标语义宽松判断）"
	var lines: Array[String] = []
	for point_v in key_points:
		if not (point_v is Dictionary):
			continue
		var point: Dictionary = point_v
		var label := String(point.get("label", "")).strip_edges()
		if label.is_empty():
			continue
		var keys: Array = DictUtil.get_dict_array(point, "knowledge_keys")
		var suffix := ""
		if not keys.is_empty():
			suffix = "；关联知识 key：" + "、".join(DictUtil.string_array(keys))
		lines.append("- %s%s" % [label, suffix])
	return "\n".join(lines) if not lines.is_empty() else "（未配置；按说服目标语义宽松判断）"


func make_rule_persuade_answer(npc: Unit, argument: String, persona: Dictionary, persuasion_goal: Dictionary) -> Dictionary:
	var key_points: Array = DictUtil.get_dict_array(persuasion_goal, "key_points")
	var matched: Array[String] = []
	var missed: Array[String] = []
	var knowledge_used: Array[String] = []
	for point_v in key_points:
		if not (point_v is Dictionary):
			continue
		var point: Dictionary = point_v
		var label := String(point.get("label", "")).strip_edges()
		if label.is_empty():
			continue
		if key_point_matches(argument, point):
			matched.append(label)
			var keys: Array = DictUtil.get_dict_array(point, "knowledge_keys")
			for key_v in keys:
				var key := String(key_v).strip_edges()
				if not key.is_empty() and not knowledge_used.has(key):
					knowledge_used.append(key)
		else:
			missed.append(label)
	var matched_count := matched.size()
	var has_progress := matched_count > 0
	var accum_score := 0
	var round_score := 0
	if has_progress:
		accum_score = clampi(10 + matched_count * 2, _level.PERSUADE_ACCUM_SCORE_MIN, _level.PERSUADE_ACCUM_SCORE_MAX)
		round_score = clampi(5 + matched_count * 4, _level.PERSUADE_ROUND_SCORE_MIN, _level.PERSUADE_ROUND_SCORE_MAX)
	var reply: String = _level._persuade_flow.pick_success_feedback(npc, persona) if has_progress else _PersonaFallbackScript.pick(persona, "persuade")
	return {
		"reply": reply,
		"accum_score": accum_score,
		"round_score": round_score,
		"final_score": accum_score + round_score,
		"tone": "松动" if has_progress else "沉默",
		"knowledge_used": knowledge_used,
		"matched_points": matched,
		"missed_points": missed,
		"is_fallback": true,
		"allow_fallback_score": has_progress,
		"fallback_reason": "rule_match",
	}


func make_rule_qa_eval(npc: Unit, answer: String, persona: Dictionary) -> Dictionary:
	var key_points: Array = _level._npc_state(npc).qa_key_points
	var matched: Array[String] = []
	var missed: Array[String] = []
	var knowledge_used: Array[String] = []
	for point_v in key_points:
		if not (point_v is Dictionary):
			continue
		var point: Dictionary = point_v
		var label := String(point.get("label", "")).strip_edges()
		if label.is_empty():
			continue
		if key_point_matches(answer, point):
			matched.append(label)
			var keys: Array = DictUtil.get_dict_array(point, "knowledge_keys")
			for key_v in keys:
				var key := String(key_v).strip_edges()
				if not key.is_empty() and not knowledge_used.has(key):
					knowledge_used.append(key)
		else:
			missed.append(label)
	var is_correct := not matched.is_empty()
	var feedback: String = _level._qa_flow.pick_success_feedback(npc, persona) if is_correct else _PersonaFallbackScript.pick(persona, "qa")
	return {
		"is_correct": is_correct,
		"feedback": feedback,
		"knowledge_used": knowledge_used,
		"matched_points": matched,
		"missed_points": missed,
		"is_fallback": true,
		"fallback_reason": "rule_match",
	}
