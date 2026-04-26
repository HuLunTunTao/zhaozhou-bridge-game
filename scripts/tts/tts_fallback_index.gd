extends Node
## TTS Fallback 预合成音频索引（autoload，名 `TtsFallbackIndex`）。
##
## 启动时读 `data/tts_fallback_manifest.json`，对每条 (unit_id, text) 建立 → AudioStream 映射。
## 运行时由 chatter_voice_adapter / bridge_tour._play_npc_line 在 TTS 失败 / is_fallback=true
## 路径上调 get_fallback_audio(unit_id, text) 查 pre-baked MP3，注入 dialogue_line.audio_stream
## 或 AudioStreamPlayer 一次性播。
##
## Manifest schema：见 `data/tts_fallback_manifest.json` 头部
## 物理文件：`assets/audio/tts_fallback/<unit_id>/<slug>.mp3`
##
## 失败兜底链：火山 WS → pre-baked（本类查表）→ OS TTS → 静默
##
## 设计要点：
##   - 启动时 lazy-load AudioStream（load() 一次，缓存）；运行时 O(1) 查表
##   - manifest 缺项 / mp3 文件不存在 / Godot 还没生成 .import → 静默跳过该条，**不**报错
##   - text 字面比对（带 strip_edges）；与 npc_personas.fallback_lines 字面相等是契约

const MANIFEST_PATH := "res://data/tts_fallback_manifest.json"

## "unit_id::text" → AudioStream
var _by_key: Dictionary = {}
var _ready_done: bool = false


func _ready() -> void:
	_load_manifest()


func _load_manifest() -> void:
	var f: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		# 没 manifest 不算错——首次拉代码可能还没烤
		_ready_done = true
		return
	var raw: String = f.get_as_text()
	f.close()
	var doc: Variant = JSON.parse_string(raw)
	if not (doc is Dictionary):
		push_warning("[TtsFallbackIndex] manifest 解析失败：根节点不是 Object")
		_ready_done = true
		return
	var items: Variant = (doc as Dictionary).get("items", [])
	if not (items is Array):
		_ready_done = true
		return
	var loaded := 0
	var missing := 0
	for it_raw in items:
		if not (it_raw is Dictionary):
			continue
		var it: Dictionary = it_raw
		var unit_id: String = String(it.get("unit_id", "")).strip_edges()
		var text: String = String(it.get("text", "")).strip_edges()
		var output: String = String(it.get("output", "")).strip_edges()
		if unit_id.is_empty() or text.is_empty() or output.is_empty():
			continue
		var path: String = "res://" + output if not output.begins_with("res://") else output
		if not ResourceLoader.exists(path):
			missing += 1
			continue
		var stream: AudioStream = load(path) as AudioStream
		if stream == null:
			missing += 1
			continue
		_by_key[_make_key(unit_id, text)] = stream
		loaded += 1
	_ready_done = true
	if loaded > 0 or missing > 0:
		print("[TtsFallbackIndex] loaded=%d missing=%d" % [loaded, missing])


func _make_key(unit_id: String, text: String) -> String:
	return "%s::%s" % [unit_id, text.strip_edges()]


## 查 (unit_id, text) 对应的 pre-baked AudioStream。无则返回 null。
func get_fallback_audio(unit_id: String, text: String) -> AudioStream:
	if unit_id.is_empty() or text.is_empty():
		return null
	return _by_key.get(_make_key(unit_id, text), null)


## 调试用：返回已加载条目数。
func entry_count() -> int:
	return _by_key.size()
