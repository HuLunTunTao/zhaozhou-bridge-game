class_name PersonaFallback
## 从 npc_personas.fallback_lines 按 trigger_kind 抽一句变体；空时降级到全局兜底。
##
## 用法：
##   var persona := NpcPersonas.get_persona(unit_id, camp)
##   var line: String = PersonaFallback.pick(persona, "reaction_to_attack")
##
## 设计：
##   - 优先 persona["fallback_lines"][trigger_kind] 数组，random pick
##   - 缺字段 / 数组空 → 降级到 _GLOBAL[trigger_kind]（保留旧"沉吟不语"等行为）
##   - _GLOBAL 也没有 → 返回 ""，调用方按"该轮跳过"处理
##
## 文本约束（写到 npc_personas 时遵守）：
##   - 单条 ≤30 字
##   - **不带外角括号**（预合成 TTS 会把括号读出来；内嵌动作描写括号也不要，除非确认不进 manifest）
##   - 严格贴 persona.style 字段口吻

## 全局兜底，给"未配 fallback_lines 字段的 NPC"用。保留原有写死风味。
const _GLOBAL := {
	"reaction_to_attack": ["（吭一声）", "（咬牙）"],
	"adjacent_chat":      ["（嘟囔了一句）"],
	"adjacent_reply":     ["（点了点头）"],
	"hero_observation":   ["（眯眼远眺）"],
	"persuade":           ["（沉吟不语）"],
	"qa":                 ["（摇头不语）"],
	"mentor":             ["（摸了摸下巴）"],
	"neighbor":           [""],   # 空字符串=本轮跳过
}


## 抽一条 fallback 文本。trigger_kind 见 _GLOBAL keys。
static func pick(persona: Dictionary, trigger_kind: String) -> String:
	var bag: Variant = persona.get("fallback_lines", {})
	if bag is Dictionary:
		var arr: Variant = (bag as Dictionary).get(trigger_kind, [])
		if arr is Array and not (arr as Array).is_empty():
			return str((arr as Array)[randi() % (arr as Array).size()])
	var fallback: Array = _GLOBAL.get(trigger_kind, [""])
	if fallback.is_empty():
		return ""
	return str(fallback[randi() % fallback.size()])


## 给定 unit_id 的便利重载，自动取 persona。
static func pick_for(unit_id: String, camp: int, trigger_kind: String) -> String:
	var persona: Dictionary = NpcPersonas.get_persona(unit_id, camp)
	return pick(persona, trigger_kind)
