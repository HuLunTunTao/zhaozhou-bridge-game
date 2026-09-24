class_name LLMInteractionRunner
extends RefCounted

## 验桥日 LLM 交互胶水：persona 查表 → prompt 装配 → chat_completion → JSON 解析。
## persuade / qa / mentor / neighbor 四个调用点共用同一段装配；领域解析与 cheat /
## rule 兜底留在 bridge_tour 各 _generate_xxx 薄壳里。
##
## _level 是 bridge_tour，对 _build_npc_memory_memo / _build_bridge_context_json /
## _get_llm / _parse_object_json 保持鸭子调用（同 SocialInteractionFlow 模式）。

const _ChatterPromptsScript := preload("res://scripts/llm/chatter_prompts.gd")

var _level: Node = null   # bridge_tour


func setup(level: Node) -> void:
	_level = level


## 返回 {ok, text, parsed, persona, code, error}。
## ok = chat 成功，且 required_key 非空时解析出的 JSON 含该 key。
## required_key 为空（neighbor 纯文本场景）不做 JSON 解析校验，调用方直接用 text。
func run(npc: Unit, trigger_kind: String, role: String, extra: Dictionary, opts: Dictionary, required_key: String = "") -> Dictionary:
	var persona: Dictionary = NpcPersonas.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var sys: String = _ChatterPromptsScript.build_system_prompt(
		persona,
		trigger_kind,
		_level._build_npc_memory_memo(npc),
		_level._build_bridge_context_json(npc, role)
	)
	var user: String = _ChatterPromptsScript.build_user_prompt(persona, trigger_kind, extra)
	var resp: Dictionary = await _level._get_llm().chat_completion([
		{"role": "system", "content": sys},
		{"role": "user", "content": user},
	], opts)
	var text := String(resp.get("text", ""))
	var parsed: Dictionary = _level._parse_object_json(text)
	var ok := bool(resp.get("ok", false))
	if ok and not required_key.is_empty():
		ok = not parsed.is_empty() and parsed.has(required_key)
	return {
		"ok": ok,
		"text": text,
		"parsed": parsed,
		"persona": persona,
		"code": resp.get("code", "?"),
		"error": resp.get("error", "?"),
	}
