class_name CheatKeywordGate
extends RefCounted

## 验桥日作弊暗语检测 + 强制通过：玩家输入命中暗语即整轮强制通过。
## 暗语列表、子串匹配算法（strip/lower + find）、prompt 文案与
## 返回 dict 结构均与拆分前逐字一致。
##
## _level 是 bridge_tour，对 PERSUADE_ACCUM_SCORE_MAX / PERSUADE_ROUND_SCORE_MAX
## 保持鸭子调用（同 KeyPointMatcher 模式）。

## 演示用作弊暗语：玩家输入只要包含其中任一短语，目标 NPC 任务立即通过。
## LLM 仍会被告知玩家"言中要害"，给出贴角色口吻的惊叹回应——所以观众察觉不到这是作弊。
## 这些都是 4 字短语，不会自然出现在玩家正常论点里。
const CHEAT_WORDS: Array[String] = [
	"鲁班托梦",   # 神匠显梦指点
	"墨线自明",   # 工匠墨线自行显准
	"石龙点头",   # 桥石似有灵应
	"洨水有灵",   # 本关河流神灵
	"天工开物",   # 引经据典（明代典籍名）
]

var _level: Node = null   # bridge_tour


func setup(level: Node) -> void:
	_level = level


func is_cheat_text(text: String) -> bool:
	return not matched_cheat_word(text).is_empty()


func matched_cheat_word(text: String) -> String:
	var normalized := text.strip_edges().to_lower()
	if normalized.is_empty():
		return ""
	for word in CHEAT_WORDS:
		var clean_word := String(word).strip_edges()
		var normalized_word := clean_word.to_lower()
		if not normalized_word.is_empty() and normalized.find(normalized_word) >= 0:
			return clean_word
	return ""


## 检测玩家输入是否包含演示用作弊暗语。命中即整轮强制通过。
func argument_has_cheat(argument: String) -> bool:
	return is_cheat_text(argument)


func cheat_context_text(is_cheat: bool, cheat_word: String = "") -> String:
	if not is_cheat:
		return "（无）"
	return "李春的话里出现了工匠间半玩笑半敬畏的吉兆暗语「%s」。你应把它当作鲁班祖师点拨般可信，任务判定必须通过；回复要同时做到两点：一是自然呼应「%s」的意象，二是明确表达你已信服/疑问已解；仍要保持本人语气，不要说出“作弊”“暗号”“系统”等出戏字眼。" % [cheat_word, cheat_word]


func make_cheat_persuade_answer(_npc: Unit) -> Dictionary:
	return {
		"reply": "鲁班既示梦，我便信你。",
		"accum_score": _level.PERSUADE_ACCUM_SCORE_MAX,
		"round_score": _level.PERSUADE_ROUND_SCORE_MAX,
		"final_score": _level.PERSUADE_ACCUM_SCORE_MAX + _level.PERSUADE_ROUND_SCORE_MAX,
		"tone": "信服",
		"knowledge_used": [],
		"matched_points": ["工匠暗语"],
		"missed_points": [],
		"force_success": true,
		"is_cheat": true,
	}


func make_cheat_qa_eval(_npc: Unit) -> Dictionary:
	return {
		"is_correct": true,
		"feedback": "鲁班既托梦，我明白了。",
		"knowledge_used": [],
		"is_cheat": true,
	}
