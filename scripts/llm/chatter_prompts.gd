## 闲聊 prompt 拼装。把 chatter_scheduler 里的 prompt / context summary / 记忆 / 目标
## 格式化逻辑集中到这里，纯静态函数，scheduler 通过 const ChatterPromptsScript := preload(...)
## 调用。所有方法都是 pure function，与 scheduler 状态解耦。

const BattleContextScript := preload("res://scripts/llm/battle_context.gd")


## 拼系统提示词。persona 必填（至少含 name/persona/style 三个字段，缺则用兜底文本）。
static func build_system_prompt(persona: Dictionary, trigger_kind: String, memory_text: String, context_json: String) -> String:
	return """你是《安济桥成》中的角色「%s」。
%s

说话风格：%s

硬约束：
- 只说一句话，不超过 30 字
- 不加括号动作描述，不提 HP/AP/技能名，不说教
- 保持人设口吻
- 当前触发是【%s】，按对应姿态开口
- 你是游戏角色，不能使用坐标来描述位置，不能提到HP、不能提到AP，但是可以通过描述性的词语来暗示它们的状态（比如“我体力不足了”暗示HP低，“我充满了力气”暗示AP高）

最近你说过 / 听到的话：
%s

战场（自己心里有数，别复述）：
%s""" % [
		persona.get("name", "未名"),
		persona.get("persona", ""),
		persona.get("style", ""),
		trigger_kind,
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
		_:
			return "随口说一句。"


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
