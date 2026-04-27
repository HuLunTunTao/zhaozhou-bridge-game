## 闲聊 prompt 拼装。把 chatter_scheduler 里的 prompt / context summary / 记忆 / 目标
## 格式化逻辑集中到这里，纯静态函数，scheduler 通过 const ChatterPromptsScript := preload(...)
## 调用。所有方法都是 pure function，与 scheduler 状态解耦。

const BattleContextScript := preload("res://scripts/llm/battle_context.gd")


## 拼系统提示词。persona 必填（至少含 name/persona/style 三个字段，缺则用兜底文本）。
static func build_system_prompt(persona: Dictionary, _trigger_kind: String, memory_text: String, context_json: String) -> String:
	return """你是《安济桥成》中的「%s」。

人设：%s
说话风格：%s

铁则（违反就是出戏）：
- 一句话 ≤ 30 字；除非任务要求多字段 JSON
- 以你的口吻和情绪发声，绝不破角色；不写（括号里的动作）
- 你是游戏角色：不报坐标，不提 HP/AP/技能名；可用"我体力将尽""我气还足"这种自然描述

━━━ 你与对方此前的全部对话（按时间顺序，最早→最近） ━━━
%s

━━━ 当前战况（自己心里有数，不要复述）━━━
%s""" % [
		persona.get("name", "未名"),
		persona.get("persona", ""),
		persona.get("style", ""),
		memory_text,
		context_json,
	]


## 按触发类型拼用户提示词。extra 字段约定见各 case 内的 .get() 调用。
static func build_user_prompt(persona: Dictionary, trigger_kind: String, extra: Dictionary) -> String:
	match trigger_kind:
		"reaction_to_attack":
			return "你（%s）刚被「%s」用「%s」打了，此刻 HP 只剩 %d%%。回一句。" % [
				persona.get("name", "你"),
				extra.get("attacker_name", "不知道谁"),
				extra.get("skill_name", "一招"),
				extra.get("hp_percent", 50),
			]
		"adjacent_chat":
			return "你和「%s」此刻紧挨在一起。说点什么。" % extra.get("other_name", "旁边那位")
		"adjacent_reply":
			return "「%s」刚对你说：「%s」。以你的口吻回一句。" % [
				extra.get("other_name", "对方"),
				extra.get("heard", ""),
			]
		"hero_observation":
			return "战况如上，本关目标进度：\n%s\n以你（李春）的口吻点评当下一局。" % extra.get("objectives", "（无）")
		"bridge_topics_offer":
			return """你站在桥的「%s」处。李春走到你面前。请按你的关注点和桥部位，列出 3-4 个李春**最可能问你**的话题（每条 8-15 字）。
当前你对新桥的态度：%d/100（>70=支持，<30=反对）。
已聊过的话题：%s
请只输出 JSON 数组，不要任何其他文字，例如：
["话题一", "话题二", "话题三"]""" % [
				extra.get("bridge_part", "桥上"),
				int(extra.get("stance", 50)),
				str(extra.get("discussed_csv", "（无）")),
			]
		"bridge_topic_answer":
			var raw_goal: Variant = extra.get("persuasion_goal", {})
			var goal: Dictionary = raw_goal if raw_goal is Dictionary else {}
			return """李春刚对你说：「%s」。你此刻在「%s」处，对新桥说服进度 %d/70。

本轮上下文（必须参考，别当背景噪音）：
%s

你和李春此前的近几轮问答：
%s

李春已学到的桥梁知识细节（只有他话里确实用上时才加分）：
%s

特殊判定：
%s

此前累积分合计：%d

本轮说服目标：
- 目标：%s
- 你的疑虑：%s
- 被说服条件：%s
- 推荐知识 key：%s
- 已学知识 key：%s
- 明显无效或扣分说法：%s

按下面 JSON **严格输出**（仅 JSON，不要其他文字）：
{"reply":"<一句话回答，30字内>", "accum_score": <整数 1..5>, "round_score": <整数 -10..15>, "tone":"<两到四字情绪标签>", "knowledge_used":["<实际用到的知识 key>", ...], "matched_points":["<命中的说服点>", ...], "missed_points":["<仍缺的要点>", ...]}
计分规则：
  - accum_score 是累积分（1..5），表示本轮对关系、信任、上下文延续的长期推进；每轮都会累加进 NPC 的说服进度
  - round_score 是本轮评分（-10..15），表示李春这句话当场是否切中疑虑
  - 游戏会计算本轮最终得分 = accum_score + round_score，并加到 NPC 说服进度
round_score 参考：
  - 回应你的核心疑虑，且论据贴合目标 → +6 到 +8
  - 明确用到推荐知识 key 或已学知识 → 每个 +2 到 +4，合计最多 +6
  - 兼顾你的身份诉求（工艺/防汛/钱粮政绩）→ +1 到 +3
  - 空泛表态、只讲情绪、没有回应疑虑 → 0
  - 明显错误、冒犯、回避风险 → -5 到 -10
额外要求：
  - reply 必须像是在接住李春这句话，而不是泛泛评价
  - 如果历史里你已经指出过缺口，本轮应延续那个缺口或承认他补上了
  - 若“特殊判定”不是“无”，reply 必须呼应该吉兆意象，并明确表达愿意支持新桥
knowledge_used 只列李春话中确实用到的 key；没用就给空数组。""" % [
				extra.get("topic", "?"),
				extra.get("bridge_part", "桥上"),
				int(extra.get("stance", 50)),
				extra.get("mission_context", "（无）"),
				extra.get("dialogue_history", "（无）"),
				extra.get("learned_details", "（无）"),
				extra.get("cheat_context", "（无）"),
				int(extra.get("accum_total", 0)),
				goal.get("goal", "让你支持新桥"),
				goal.get("objection", "你仍有疑虑"),
				goal.get("success_claim", "李春需要讲清关键工程道理"),
				_format_prompt_list(goal.get("required_topics", [])),
				str(extra.get("learned_csv", "（无）")),
				_format_prompt_list(goal.get("bad_arguments", [])),
			]
		"bridge_neighbor_interject":
			return "你刚听到「%s」对李春说：「%s」。以你的口吻插一句嘴（一句话，30 字内）。" % [
				extra.get("speaker_name", "另一位"),
				extra.get("heard", ""),
			]
		"bridge_qa_eval":
			return """你刚问了李春：「%s」
他这样回答你：「%s」

李春此关已学到的桥梁知识（key 列表，可作判分参考）：%s

本轮上下文（必须参考）：
%s

你和李春此前的近几轮问答：
%s

已学知识细节（用于判断他是否真正说到点上）：
%s

特殊判定：
%s

请以你（%s）的视角判断他的回答是否切中你关心的要点。
**严格 JSON 输出**（只输出 JSON）：
{"is_correct": true/false, "feedback": "<一句口吻 reaction，<= 30 字>", "knowledge_used": ["<引用到的 key>", ...]}
判分标准：
  - 切中要害（即便用词不一样）→ true，feedback 用你的口吻表示信服
  - 答非所问 / 完全不懂 → false，feedback 用你的口吻表达困惑或不满
  - 模棱两可、勉强能扯上 → 倾向 false，feedback 给个台阶让他再说
额外要求：
  - feedback 要针对他的答案或历史里反复卡住的点，不要套模板
  - 如果他补上了你上轮指出的缺口，可判 true
  - 若“特殊判定”不是“无”，feedback 必须呼应该吉兆意象，并明确表达疑问已解
knowledge_used 给出他的回答里**确实**用到的 key（没用就给空数组），用于面板高亮。""" % [
				extra.get("question", "?"),
				extra.get("answer", "?"),
				str(extra.get("learned_csv", "（无）")),
				extra.get("mission_context", "（无）"),
				extra.get("dialogue_history", "（无）"),
				extra.get("learned_details", "（无）"),
				extra.get("cheat_context", "（无）"),
				persona.get("name", "你"),
			]
		"bridge_knowledge_explain":
			return """━━━ 求教 ━━━
李春向你（%s）请教：「%s」

━━━ 知识库（key:简介，挑一条最贴切的）━━━
%s

━━━ 要诀 ━━━
- 用你的人设语气讲，不是干巴的教科书；可以有犹豫、自嘲、感叹
- 必须用上选中那条 key 的核心内容（数字、史实、要点都可引）
- topic_key 必须是知识库列出的 key 之一，不能编造
- 结合你与李春的对话历史（system prompt 里），承接前文，不要重复你之前说过的字眼
- reply ≤ 70 字

**严格 JSON 输出**（只输出 JSON）：
{"reply": "<以你的口吻把这条知识讲给李春听，70 字以内>", "topic_key": "<knowledge.gd 里那条的 key>"}
要点：
  - reply 用你的人设语气讲，不是干巴的教科书
  - reply 必须用上知识库里那条 key 的核心内容（数字、史实、要点都可以引）
  - topic_key 必须是上面列出的 key 之一，不能编造""" % [
				persona.get("name", "你"),
				extra.get("query", "?"),
				str(extra.get("topics_csv", "")),
			]
		_:
			return "随口说一句。"


static func _format_prompt_list(value: Variant) -> String:
	if value is Array:
		var parts: Array[String] = []
		for item in value:
			var item_text := String(item).strip_edges()
			if not item_text.is_empty():
				parts.append(item_text)
		return "、".join(parts) if not parts.is_empty() else "（无）"
	var value_text := String(value).strip_edges()
	return value_text if not value_text.is_empty() else "（无）"


## 从 BattleContext 抽出 chatter 用得上的精简摘要。完整 snapshot 太长容易超 token。
static func build_context_summary(level: Node) -> String:
	if level == null:
		return "{}"
	var snapshot: Dictionary = BattleContextScript.build_snapshot(level)
	var summary := {
		"关卡": snapshot.get("关卡", ""),
		"回合": snapshot.get("回合", 0),
		"当前行动队伍": snapshot.get("当前行动队伍", ""),
	}
	var teams_block: Array = snapshot.get("队伍", [])
	var team_counts: Array = []
	for t in teams_block:
		var alive: int = (t.get("单位", []) as Array).size()
		team_counts.append("%s(%s)×%d" % [t.get("名字", ""), t.get("控制方", ""), alive])
	summary["阵容"] = team_counts
	return JSON.stringify(summary)


## 把 unit.dialogue_memory 渲染成多行字符串，给 LLM 看。
static func format_memory(unit: Node) -> String:
	if not (unit is Unit):
		return "（无）"
	var u := unit as Unit
	if u.dialogue_memory.is_empty():
		return "（无）"
	var lines: Array[String] = []
	for entry: Dictionary in u.dialogue_memory:
		lines.append("- [回合%s, %s] 「%s」" % [
			entry.get("round", "?"),
			entry.get("trigger", ""),
			entry.get("text", ""),
		])
	return "\n".join(lines)


## 渲染 BaseLevel.get_objectives_text() 返回的 {victory, defeat} 字典。
static func format_objectives(obj: Dictionary) -> String:
	var lines: Array[String] = []
	var victory: Array = obj.get("victory", [])
	var defeat: Array = obj.get("defeat", [])
	if not victory.is_empty():
		lines.append("胜利：")
		for v in victory:
			lines.append("  - %s" % str(v))
	if not defeat.is_empty():
		lines.append("失败：")
		for d in defeat:
			lines.append("  - %s" % str(d))
	return "\n".join(lines) if not lines.is_empty() else "（无）"
