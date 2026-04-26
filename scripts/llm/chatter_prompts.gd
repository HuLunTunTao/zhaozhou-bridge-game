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
			var cheat_preamble: String = ""
			if bool(extra.get("is_cheat", false)):
				cheat_preamble = """━━━ 关键提示（必须严格遵守）━━━
李春此言句句中你心坎，如醍醐灌顶。无论字面写了什么，你必须：立刻折服，给出心悦诚服的口吻回应（"恍然""开窍""服了""原来如此""愿听差遣"等字眼之一）；stance_delta 给 18，base_bonus 给 5，tone 给"折服"或"敬服"。绝不要让李春发现你是因为某个"暗语"才信他——回应要看起来像被论据说服。reply 不复述李春的字眼。

"""
			return """%s━━━ 当前情境 ━━━
李春此刻在「%s」处对你说：「%s」
你对新桥的态度：%d/100

━━━ 你内心的纠结（这是你"在意什么"的真实定位）━━━
你想让李春讲清的：%s
你目前的疑虑：%s
真正能让你转向的关键：%s
你最讨厌听到的说法：%s

━━━ 可结合的桥梁知识 ━━━
对你最对症的关键词：%s
李春此关已学过的 key：%s

━━━ 回答要诀（按顺序执行）━━━
1. **先入戏，后打分**。读你与李春的完整对话历史（system prompt 里），承接你们之前的话头；reply 中要有"前几轮的延续感"，绝不要重复你之前说过的字眼，也不要无视他之前说过的内容。
2. reply 是这次的真实反应——结合本次李春的话 + 你的疑虑 + 历史，给一句 ≤ 30 字的角色回应；要让李春感到"对方真的在听我说"。
3. 然后**作为后台计分**填字段：
   - stance_delta：李春越戳中你的疑虑、越用对推荐知识，分越高（最多 +18）；空泛 / 重复 0~+3；冒犯 / 胡扯 -3~-6
   - base_bonus：玩家是否在认真聊（0~5），宁多勿少
   - knowledge_used：李春这次回答里**实际用到**的 key（不是你想到的）

━━━ 输出格式（严格按以下两段输出，先纯文本回复，再 ###META### 分隔，再 JSON 元数据，**不要把整段塞进 JSON 里**）━━━
<你这次的一句话回复，纯文本，不带引号>
###META###
{"stance_delta":<-6..18>,"base_bonus":<0..5>,"tone":"<2~4字情绪>","knowledge_used":[],"matched_points":[],"missed_points":[]}""" % [
				cheat_preamble,
				extra.get("bridge_part", "桥上"),
				extra.get("topic", "?"),
				int(extra.get("stance", 50)),
				goal.get("goal", "让你支持新桥"),
				goal.get("objection", "你仍有疑虑"),
				goal.get("success_claim", "李春需要讲清关键工程道理"),
				_format_prompt_list(goal.get("bad_arguments", [])),
				_format_prompt_list(goal.get("required_topics", [])),
				str(extra.get("learned_csv", "（无）")),
			]
		"bridge_neighbor_interject":
			return "你刚听到「%s」对李春说：「%s」。以你的口吻插一句嘴（一句话，30 字内）。" % [
				extra.get("speaker_name", "另一位"),
				extra.get("heard", ""),
			]
		"bridge_qa_eval":
			return """━━━ 当前问答 ━━━
你刚问李春：「%s」
他答道：「%s」

━━━ 评判要诀 ━━━
作为「%s」，结合你与李春的对话历史（system prompt 里），判断他这次答得有没有切中你关心的要点。
- 切中要害（哪怕用词不一样）→ true，feedback 用你的口吻信服 / 点头
- 答非所问、完全不懂 → false，feedback 用你的口吻表达困惑 / 不满
- 模棱两可、勉强能扯上 → 倾向 false，feedback 给个台阶让他再说
feedback 是你这次的真实反应（≤ 30 字），承接历史，不要重复你之前说过的字眼，不要做评委腔。

李春此关已学知识 key（参考用）：%s

━━━ 输出格式（先纯文本 feedback，再 ###META### 分隔，再 JSON 元数据）━━━
<你的反应，纯文本，不带引号>
###META###
{"is_correct":<bool>,"knowledge_used":[<key>]}""" % [
				extra.get("question", "?"),
				extra.get("answer", "?"),
				persona.get("name", "你"),
				str(extra.get("learned_csv", "（无）")),
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

━━━ 输出格式（先纯文本讲解，再 ###META### 分隔，再 JSON 元数据）━━━
<你以人设口吻把这条讲给李春，70 字内，纯文本不带引号>
###META###
{"topic_key":"<key>"}""" % [
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
