extends Control
## TTS 测试场景脚本。
## 在编辑器里 F6 运行 res://scenes/test/tts_test.tscn 即可独立调试 TTS。
##
## 提供 3 类操作：
##   1. 用火山 TTS 合成并播放（按 voice_mapping 选音色 / 也支持自定义 voice_type）
##   2. 用系统 TTS 试听（DisplayServer.tts_speak，无网无 key 也能听）
##   3. 停止当前播放（火山的 AudioStreamPlayer 和系统 TTS 都停）
##
## 关键节点（unique_name_in_owner）：
##   %ApiKeyEdit, %VoiceOption, %CustomVoiceEdit,
##   %TextEdit, %SynthBtn, %SystemBtn, %StopBtn, %StatusLabel, %Player

const VoiceMappingScript := preload("res://scripts/tts/voice_mapping.gd")
const VolcengineTTSClientScript := preload("res://scripts/tts/volcengine_tts_client.gd")
const ApiConfig := preload("res://scripts/config/api_config.gd")

const SAMPLE_TEXT := "桥要成，须得脚下踩稳。"

var _tts: Node = null
var _voice_keys: Array[String] = []  # OptionButton index → unit_id
var _current_audio: AudioStream = null

@onready var api_key_edit: LineEdit = %ApiKeyEdit
@onready var voice_option: OptionButton = %VoiceOption
@onready var custom_voice_edit: LineEdit = %CustomVoiceEdit
@onready var text_edit: TextEdit = %TextEdit
@onready var synth_btn: Button = %SynthBtn
@onready var system_btn: Button = %SystemBtn
@onready var stop_btn: Button = %StopBtn
@onready var status_label: Label = %StatusLabel
@onready var player: AudioStreamPlayer = %Player
@onready var back_btn: Button = %BackBtn


func _ready() -> void:
	_tts = VolcengineTTSClientScript.new()
	add_child(_tts)
	_populate_voice_option()
	text_edit.text = SAMPLE_TEXT
	# 默认从 ApiConfig 拉 key（如果 ApiConfig 里填了，省去手动粘贴）
	if api_key_edit.text.is_empty() and not ApiConfig.TTS_API_KEY.is_empty():
		api_key_edit.text = ApiConfig.TTS_API_KEY
	synth_btn.pressed.connect(_on_synth_pressed)
	system_btn.pressed.connect(_on_system_pressed)
	stop_btn.pressed.connect(_on_stop_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	voice_option.item_selected.connect(_on_voice_selected)
	_on_voice_selected(voice_option.selected)
	var hint := "就绪。已从 ApiConfig 自动填入 TTS Key。" if not ApiConfig.TTS_API_KEY.is_empty() else "就绪。请填 API Key（或改 scripts/config/api_config.gd 后重启），选音色，按按钮。"
	_set_status(hint, Color(0.7, 0.85, 0.7))


func _populate_voice_option() -> void:
	voice_option.clear()
	_voice_keys.clear()
	# 从 VoiceMapping 拉出 16 个角色
	var keys := (VoiceMappingScript.VOICES as Dictionary).keys()
	keys.sort()  # 字母序，便于查找
	for key: String in keys:
		var cfg: Dictionary = VoiceMappingScript.VOICES[key]
		voice_option.add_item("%s（%s）" % [key, cfg.get("label", "?")])
		_voice_keys.append(key)
	# 末尾加一个"自定义"
	voice_option.add_item("自定义 voice_type…")
	_voice_keys.append("__custom__")


func _on_voice_selected(index: int) -> void:
	if index < 0 or index >= _voice_keys.size():
		return
	var key: String = _voice_keys[index]
	if key == "__custom__":
		custom_voice_edit.editable = true
		custom_voice_edit.placeholder_text = "粘贴 voice_type 字符串，例如 zh_male_dayi_uranus_bigtts"
		if custom_voice_edit.text.is_empty():
			custom_voice_edit.text = ""
	else:
		var cfg: Dictionary = VoiceMappingScript.VOICES[key]
		custom_voice_edit.text = cfg.get("voice", "")
		custom_voice_edit.editable = false


func _resolved_voice() -> String:
	return custom_voice_edit.text.strip_edges()


func _on_synth_pressed() -> void:
	var text := text_edit.text.strip_edges()
	var voice := _resolved_voice()
	var key := api_key_edit.text.strip_edges()
	if text.is_empty():
		_set_status("文本为空", Color(1, 0.6, 0.6))
		return
	if voice.is_empty():
		_set_status("voice_type 为空", Color(1, 0.6, 0.6))
		return
	if key.is_empty():
		_set_status("API Key 为空：火山 TTS 无法调用，可改用「系统 TTS 试听」。", Color(1, 0.85, 0.4))
		return

	_set_busy(true)
	_set_status("[1/3] 连接并合成中…", Color(0.7, 0.85, 1))
	_tts.api_key = key
	var t0 := Time.get_ticks_msec()
	var mp3: PackedByteArray = await _tts.synthesize(text, voice)
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	if mp3.is_empty():
		_set_status("[失败] 火山 TTS 没返回音频（耗时 %.1fs）。请看 Output 面板的 [TTS] 警告。" % elapsed, Color(1, 0.5, 0.5))
		_set_busy(false)
		return
	var stream := AudioStreamMP3.new()
	stream.data = mp3
	_current_audio = stream
	player.stream = stream
	player.play()
	_set_status("[成功] 收到 %d 字节，时长 %.2fs，合成耗时 %.1fs。播放中…" % [mp3.size(), stream.get_length(), elapsed], Color(0.7, 1, 0.7))
	_set_busy(false)


func _on_system_pressed() -> void:
	var text := text_edit.text.strip_edges()
	if text.is_empty():
		_set_status("文本为空", Color(1, 0.6, 0.6))
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		_set_status("[失败] 当前平台不支持系统 TTS。", Color(1, 0.5, 0.5))
		return
	var voices: Array = DisplayServer.tts_get_voices_for_language("zh")
	if voices.is_empty():
		_set_status("[失败] 系统没装中文 TTS 语音包。macOS：系统设置 > 辅助功能 > 朗读内容 > 系统朗读 > 增加新声音。", Color(1, 0.6, 0.4))
		return
	var voice_id: String = voices[0]
	DisplayServer.tts_speak(text, voice_id, 50, 1.0, 1.0, 0, true)
	_set_status("[系统 TTS] 用 voice=%s 朗读中（无录音文件，离线生效）" % voice_id, Color(0.85, 0.85, 1))


func _on_stop_pressed() -> void:
	if player.playing:
		player.stop()
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_stop()
	_set_status("已停止", Color(0.8, 0.8, 0.8))


func _on_back_pressed() -> void:
	if player.playing:
		player.stop()
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_stop()
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


func _set_busy(busy: bool) -> void:
	synth_btn.disabled = busy
	system_btn.disabled = busy
	api_key_edit.editable = not busy


func _set_status(msg: String, color: Color = Color.WHITE) -> void:
	status_label.text = msg
	status_label.add_theme_color_override("font_color", color)
