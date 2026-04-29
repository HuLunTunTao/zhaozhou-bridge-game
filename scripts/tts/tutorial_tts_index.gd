extends Node
## Tutorial dialogue pre-baked TTS index.
##
## Loads data/tutorial_tts_manifest.json and maps
## (level_id, unit_id, displayed text) to an AudioStream.

const MANIFEST_PATH := "res://data/tutorial_tts_manifest.json"

var _by_key: Dictionary = {}
var _ready_done := false


func _ready() -> void:
	_load_manifest()


func _load_manifest() -> void:
	var f: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		print("[TutorialTTS][MANIFEST_MISSING] path=%s" % MANIFEST_PATH)
		_ready_done = true
		return
	var raw := f.get_as_text()
	f.close()

	var doc: Variant = JSON.parse_string(raw)
	if not (doc is Dictionary):
		push_warning("[TutorialTTS][MANIFEST_ERROR] path=%s reason=root_not_object" % MANIFEST_PATH)
		_ready_done = true
		return

	var items: Variant = (doc as Dictionary).get("items", [])
	if not (items is Array):
		push_warning("[TutorialTTS][MANIFEST_ERROR] path=%s reason=items_not_array" % MANIFEST_PATH)
		_ready_done = true
		return

	var loaded := 0
	var missing := 0
	for raw_item in items:
		if not (raw_item is Dictionary):
			continue
		var item: Dictionary = raw_item
		var level_id := str(item.get("level_id", "")).strip_edges()
		var unit_id := str(item.get("unit_id", "")).strip_edges()
		var text := str(item.get("text", "")).strip_edges()
		var output := str(item.get("output", "")).strip_edges()
		if level_id.is_empty() or unit_id.is_empty() or text.is_empty() or output.is_empty():
			continue

		var path := "res://" + output if not output.begins_with("res://") else output
		var stream := _load_audio(path)
		if stream == null:
			missing += 1
			print("[TutorialTTS][LOAD_FAIL] level=%s unit=%s output=%s text=%s" % [level_id, unit_id, output, text.left(60)])
			continue

		_by_key[_make_key(level_id, unit_id, text)] = stream
		loaded += 1

	_ready_done = true
	if loaded > 0 or missing > 0:
		print("[TutorialTTS][LOAD] loaded=%d missing=%d" % [loaded, missing])


func _make_key(level_id: String, unit_id: String, text: String) -> String:
	return "%s::%s::%s" % [level_id, unit_id, text.strip_edges()]


func _load_audio(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var imported := load(path) as AudioStream
		if imported != null:
			return imported

	# Freshly baked MP3 files may not have Godot .import files yet. Load the
	# bytes directly so local builds can use them immediately.
	if not FileAccess.file_exists(path):
		print("[TutorialTTS][AUDIO_MISSING] output=%s" % path)
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var stream := AudioStreamMP3.new()
	stream.data = bytes
	return stream


func get_audio(level_id: String, unit_id: String, text: String) -> AudioStream:
	if not _ready_done:
		_load_manifest()
	var stream: AudioStream = _by_key.get(_make_key(level_id, unit_id, text), null)
	if stream == null:
		print("[TutorialTTS][MISS] level=%s unit=%s text=%s" % [level_id, unit_id, text.strip_edges().left(80)])
	return stream


func entry_count() -> int:
	return _by_key.size()
