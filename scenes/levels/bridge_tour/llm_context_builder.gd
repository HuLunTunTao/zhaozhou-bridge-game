class_name LLMContextBuilder
extends RefCounted

## 验桥日 LLM prompt 上下文拼装：memory memo / context JSON / dialogue history /
## mission context / 距离标签 / 已学知识各视图。
## 字符串格式与 JSON 字段名与拆分前逐字一致；_clip_text 等纯字符串工具留在 bridge_tour。
##
## _level 是 bridge_tour，对 _npc_state / _persuaded_count / _qa_solved_count /
## _player_learned_topics / _player_used_topics / _clip_text / hero 及常量
## PERSUADE_TARGET / QA_TARGET / STANCE_PERSUADED 保持鸭子调用（同 LLMInteractionRunner 模式）。

const _BridgeKnowledgeScript := preload("res://scripts/data/bridge_knowledge.gd")

var _level: Node = null   # bridge_tour


func setup(level: Node) -> void:
	_level = level


func build_npc_memory_memo(npc: Unit) -> String:
	var parts: Array[String] = [learned_memo()]
	var dialogue := dialogue_history_text(npc)
	if dialogue.is_empty():
		parts.append("与该 NPC 尚无历史问答。")
	else:
		parts.append("与该 NPC 的近几轮问答：\n%s" % dialogue)
	return "\n\n".join(parts)


func build_bridge_context_json(npc: Unit, trigger_kind: String) -> String:
	var st: NpcSocialState = _level._npc_state(npc)
	var role := st.role
	var context := {
		"关卡": "验桥日",
		"触发": trigger_kind,
		"当前NPC": npc.unit_data.unit_name,
		"NPC类型": role,
		"所在桥段": st.bridge_part,
		"李春与NPC距离": hero_distance_label(npc),
		"任务进度": "%d/%d 说服，%d/%d 解答" % [_level._persuaded_count(), _level.PERSUADE_TARGET, _level._qa_solved_count(), _level.QA_TARGET],
		"已学知识": learned_title_list(),
		"已用知识": _level._player_used_topics.duplicate(),
	}
	if role == "persuade":
		context["当前说服进度"] = "%d/%d" % [st.stance, _level.STANCE_PERSUADED]
		context["累积分合计"] = st.accum_score_total
		var goal: Dictionary = st.persuasion_goal
		context["说服目标"] = goal.get("goal", "")
		context["核心疑虑"] = goal.get("objection", "")
		context["成功条件"] = goal.get("success_claim", "")
	elif role == "qa":
		context["已解答"] = st.qa_solved
	return JSON.stringify(context)


func dialogue_history_text(npc: Unit, max_entries: int = 4) -> String:
	var history: Array = _level._npc_state(npc).dialogue_log
	if history.is_empty():
		return ""
	var lines: Array[String] = []
	var start: int = maxi(0, history.size() - max_entries)
	for i in range(start, history.size()):
		var entry: Dictionary = history[i] if history[i] is Dictionary else {}
		var speaker := String(entry.get("npc_name", npc.unit_data.unit_name))
		var question := _level._clip_text(String(entry.get("question", "")).strip_edges(), 80)
		var player_text := _level._clip_text(String(entry.get("player", "")).strip_edges(), 90)
		var npc_text := _level._clip_text(String(entry.get("npc", "")).strip_edges(), 90)
		if not question.is_empty():
			lines.append("%s问：%s" % [speaker, question])
		if not player_text.is_empty():
			lines.append("李春答：%s" % player_text)
		if not npc_text.is_empty():
			lines.append("%s回：%s" % [speaker, npc_text])
	return "\n".join(lines)


func mission_context_text(npc: Unit) -> String:
	var st: NpcSocialState = _level._npc_state(npc)
	var role := st.role
	var parts: Array[String] = [
		"关卡目标：说服 %d/%d，解答 %d/%d。" % [_level._persuaded_count(), _level.PERSUADE_TARGET, _level._qa_solved_count(), _level.QA_TARGET],
		"当前 NPC：%s，桥段：%s，距离：%s。" % [
			npc.unit_data.unit_name,
			st.bridge_part,
			hero_distance_label(npc),
		],
	]
	if role == "persuade":
		parts.append("当前说服进度：%d/%d。" % [st.stance, _level.STANCE_PERSUADED])
		parts.append("此前累积分合计：%d。" % st.accum_score_total)
		var goal: Dictionary = st.persuasion_goal
		parts.append("疑虑：%s" % String(goal.get("objection", "")))
		parts.append("真正想听到：%s" % String(goal.get("success_claim", "")))
	elif role == "qa":
		parts.append("这是答疑目标，需判断李春是否切中问题。")
	return "\n".join(parts)


func hero_distance_label(npc: Unit) -> String:
	if _level.hero == null:
		return "未知"
	var d: Vector2i = npc.cell - _level.hero.cell
	var dist := absi(d.x) + absi(d.y)
	if dist <= 1:
		return "近在身旁"
	if dist <= 3:
		return "隔数步"
	return "隔得较远"


func learned_title_list() -> Array[String]:
	var titles: Array[String] = []
	for k in _level._player_learned_topics:
		var topic := _BridgeKnowledgeScript.get_topic(k)
		if not topic.is_empty():
			titles.append("%s:%s" % [k, String(topic.get("title", k))])
	return titles


func learned_details_text() -> String:
	if _level._player_learned_topics.is_empty():
		return "（无。若李春没有引用具体工程知识，NPC 应保持疑虑。）"
	var lines: Array[String] = []
	for k in _level._player_learned_topics:
		var topic := _BridgeKnowledgeScript.get_topic(k)
		if topic.is_empty():
			continue
		lines.append("%s（%s）：%s" % [
			k,
			String(topic.get("title", k)),
			_level._clip_text(String(topic.get("body", topic.get("summary", ""))), 220),
		])
	return "\n".join(lines) if not lines.is_empty() else "（无有效知识）"


## 拼"已学知识"渲染给 LLM。空时给"（无）"。
func learned_memo() -> String:
	if _level._player_learned_topics.is_empty():
		return "（玩家尚未学过任何桥梁知识）"
	var titles: Array[String] = []
	for k in _level._player_learned_topics:
		var topic := _BridgeKnowledgeScript.get_topic(k)
		if not topic.is_empty():
			titles.append(String(topic.get("title", k)))
	return "玩家已学知识：" + "、".join(titles)


func learned_csv() -> String:
	if _level._player_learned_topics.is_empty():
		return "（无）"
	return ", ".join(_level._player_learned_topics)
