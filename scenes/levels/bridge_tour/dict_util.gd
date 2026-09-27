class_name DictUtil
extends RefCounted

## 验桥日纯字符串 / 字典工具。所有函数 static，无状态，不依赖 level。
## 从 bridge_tour.gd 收编；逻辑逐字不变。


static func fallback_lines_for(persona: Dictionary, kind: String) -> Array:
	var fallback_lines: Variant = persona.get("fallback_lines", {})
	if fallback_lines is Dictionary:
		var raw: Variant = (fallback_lines as Dictionary).get(kind, [])
		if raw is Array:
			return raw
	return []


static func get_dict_array(dict: Dictionary, key: String) -> Array:
	var raw: Variant = dict.get(key, [])
	return raw if raw is Array else []


static func string_array(items: Array) -> Array[String]:
	var result: Array[String] = []
	for item in items:
		var text := String(item).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


static func strip_quotes(s: String) -> String:
	var out := s.strip_edges()
	while out.length() > 1:
		var first := out[0]
		var last := out[out.length() - 1]
		if (first == "\"" and last == "\"") or (first == "「" and last == "」") or (first == "“" and last == "”"):
			out = out.substr(1, out.length() - 2).strip_edges()
		else:
			break
	return out


static func parse_object_json(text: String) -> Dictionary:
	var s := text.strip_edges()
	var l := s.find("{")
	var r := s.rfind("}")
	if l < 0 or r <= l:
		return {}
	var json_text := s.substr(l, r - l + 1)
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return {}
	return parsed


static func clip_text(text: String, max_len: int) -> String:
	if text.length() <= max_len:
		return text
	return text.substr(0, max_len - 1) + "…"
