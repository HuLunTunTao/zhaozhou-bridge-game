extends Control
## TTS 测试场景脚本（v2，使用 addons/godot_volcengine_tts SDK）。
##
## 提供 4 类操作（演示三个端点 + 系统兜底）：
##   1. 🎙 HTTP 整段：调 SDK http_client，等待完整 mp3 后用 AudioStreamMP3 一次性播
##   2. 🌊 单向流式：调 SDK uni_client，PCM 流式推到 AudioStreamGenerator，首音 ~1s
##   3. 🔀 双向流式：调 SDK bidi_client，模拟 LLM 分段喂入（每 400ms feed 一段）
##   4. 📢 系统 TTS：DisplayServer.tts_speak，无网无 key 也能听
##
## 关键节点（unique_name_in_owner）：
##   %ApiKeyEdit, %VoiceOption, %CustomVoiceEdit, %TextEdit,
##   %SynthBtn, %StreamSynthBtn, %SystemBtn, %StopBtn, %StatusLabel, %Player
## 第三个 "BidirectionalBtn" 在 _ready 里动态插入 ButtonRow。

const VoiceMappingScript := preload("res://scripts/tts/voice_mapping.gd")
const BidiClientScript := preload("res://addons/godot_volcengine_tts/volcengine_tts_bidirectional_client.gd")
const UniClientScript := preload("res://addons/godot_volcengine_tts/volcengine_tts_unidirectional_client.gd")
const HttpClientScript := preload("res://addons/godot_volcengine_tts/volcengine_tts_http_client.gd")

const SAMPLE_TEXT := """赵郡有河，名曰洨水，春秋涨溢，每逢雨季便阻断南北交通。诸位匠人，我决意在此修建一座石桥，使百姓不再受困于洪水。

此河宽逾三十丈，若用多孔桥恐怕根基不稳。所以我要造一座单孔大弧拱桥，以巨石为券，跨河而过。诸位放心，我已经反复推算。从底券起算，每石分三层叠压，按尺绳所测，三尺七寸为一节，依算筹推之，此桥若得二十年风霜不倒，便是我李春此生之愿。"""

var _bidi: VolcengineTTSBidirectionalClient = null
var _uni: VolcengineTTSUnidirectionalClient = null
var _http: VolcengineTTSHttpClient = null
var _voice_keys: Array[String] = []

@onready var api_key_edit: LineEdit = %ApiKeyEdit
@onready var voice_option: OptionButton = %VoiceOption
@onready var custom_voice_edit: LineEdit = %CustomVoiceEdit
@onready var text_edit: TextEdit = %TextEdit
@onready var synth_btn: Button = %SynthBtn
@onready var stream_synth_btn: Button = %StreamSynthBtn
@onready var system_btn: Button = %SystemBtn
@onready var stop_btn: Button = %StopBtn
@onready var status_label: Label = %StatusLabel
@onready var player: AudioStreamPlayer = %Player
@onready var back_btn: Button = %BackBtn

var bidi_btn: Button = null


func _ready() -> void:
	_bidi = BidiClientScript.new()
	_uni = UniClientScript.new()
	_http = HttpClientScript.new()
	add_child(_bidi)
	add_child(_uni)
	add_child(_http)
	# 把 ApiConfig 灌进三个 client（用户也可在 UI 上覆盖）
	for c in [_bidi, _uni, _http]:
		c.api_key = ApiConfig.TTS_API_KEY
		c.resource_id = ApiConfig.TTS_RESOURCE_ID
		c.user_uid = ApiConfig.TTS_USER_UID
		c.default_model = ApiConfig.TTS_MODEL
	_populate_voice_option()
	text_edit.text = SAMPLE_TEXT
	if api_key_edit.text.is_empty() and not ApiConfig.TTS_API_KEY.is_empty():
		api_key_edit.text = ApiConfig.TTS_API_KEY
	synth_btn.text = "🎙 HTTP 整段"
	stream_synth_btn.text = "🌊 单向流式"
	system_btn.text = "📢 系统 TTS"
	# 在 ButtonRow 里插入第三个端点按钮
	bidi_btn = Button.new()
	bidi_btn.text = "🔀 双向（模拟 LLM 分段）"
	bidi_btn.custom_minimum_size = Vector2(160, 40)
	system_btn.get_parent().add_child(bidi_btn)
	system_btn.get_parent().move_child(bidi_btn, system_btn.get_index())

	synth_btn.pressed.connect(_on_synth_pressed)
	stream_synth_btn.pressed.connect(_on_stream_synth_pressed)
	bidi_btn.pressed.connect(_on_bidi_pressed)
	system_btn.pressed.connect(_on_system_pressed)
	stop_btn.pressed.connect(_on_stop_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	voice_option.item_selected.connect(_on_voice_selected)
	_on_voice_selected(voice_option.selected)
	_bidi.audio_chunk_received.connect(_on_bidi_chunk)
	_bidi.session_finished.connect(_on_bidi_finished)
	_bidi.session_failed.connect(_on_bidi_failed)
	var hint := "就绪。已从 ApiConfig 自动填入 TTS Key。" if not ApiConfig.TTS_API_KEY.is_empty() else "就绪。请填 API Key（或改 scripts/config/api_config.gd 后重启），选音色，按按钮。"
	_set_status(hint, Color(0.7, 0.85, 0.7))


func _populate_voice_option() -> void:
	voice_option.clear()
	_voice_keys.clear()
	var keys := (VoiceMappingScript.VOICES as Dictionary).keys()
	keys.sort()
	for key: String in keys:
		var cfg: Dictionary = VoiceMappingScript.VOICES[key]
		voice_option.add_item("%s（%s）" % [key, cfg.get("label", "?")])
		_voice_keys.append(key)
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


func _refresh_keys() -> void:
	var key := api_key_edit.text.strip_edges()
	for c in [_bidi, _uni, _http]:
		c.api_key = key


# ───── HTTP 整段（端点 3）─────

func _on_synth_pressed() -> void:
	var text := text_edit.text.strip_edges()
	var voice := _resolved_voice()
	if not _validate(text, voice):
		return
	_set_busy(true)
	_set_status("[HTTP] 连接并合成中（等待全部音频）…", Color(0.7, 0.85, 1))
	_refresh_keys()
	var t0 := Time.get_ticks_msec()
	var out: Dictionary = {}
	var mp3: PackedByteArray = await _http.synthesize(text, voice, {"format": "mp3"}, out)
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	if mp3.is_empty():
		_set_status("[HTTP 失败] 没返回音频（耗时 %.1fs）。看 [TTS-HTTP] 警告。" % elapsed, Color(1, 0.5, 0.5))
		_set_busy(false)
		return
	var stream := AudioStreamMP3.new()
	stream.data = mp3
	player.stream = stream
	player.play()
	_set_status("[HTTP 成功] 收到 %d 字节，时长 %.2fs，合成耗时 %.1fs。播放中…" % [mp3.size(), stream.get_length(), elapsed], Color(0.7, 1, 0.7))
	_set_busy(false)


# ───── 单向流式（端点 2）─────

func _on_stream_synth_pressed() -> void:
	var text := text_edit.text.strip_edges()
	var voice := _resolved_voice()
	if not _validate(text, voice):
		return
	_set_busy(true)
	_set_status("[单向流式] 建 WS，等首音…", Color(0.7, 0.85, 1))
	_refresh_keys()

	var generator := AudioStreamGenerator.new()
	generator.mix_rate = float(ApiConfig.TTS_SAMPLE_RATE)
	generator.buffer_length = 0.5
	player.stop()
	player.stream = generator
	player.play()
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		_set_status("[失败] 拿不到 AudioStreamGeneratorPlayback。", Color(1, 0.5, 0.5))
		_set_busy(false)
		return

	var t0 := Time.get_ticks_msec()
	var out: Dictionary = {}
	var ok: bool = await _uni.synthesize_streaming(
		text, voice,
		func(chunk: PackedByteArray) -> void:
			await _push_pcm(playback, chunk),
		{"format": "pcm", "sample_rate": ApiConfig.TTS_SAMPLE_RATE},
		out,
	)
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	if ok:
		_set_status("[单向流式 成功] WS 总耗时 %.1fs（首音应在第一秒）。session_id=%s" % [elapsed, out.get("session_id", "?")], Color(0.7, 1, 0.7))
	else:
		_set_status("[单向流式 失败] 见 [TTS-Uni] 警告。耗时 %.1fs。" % elapsed, Color(1, 0.5, 0.5))
	_set_busy(false)


# ───── 双向流式（端点 1，模拟 LLM 分段）─────

var _bidi_playback: AudioStreamGeneratorPlayback = null
var _bidi_t0_msec: int = 0
## 双向 chunk 串行化：FIFO 队列 + 单 drain 协程，避免多个异步 push 协程
## 同时争抢 _bidi_playback 导致 frame 顺序错乱（卡顿/破音）。
var _bidi_chunk_queue: Array[PackedByteArray] = []
var _bidi_drain_running: bool = false

## drain 收尾唤醒信号（_drain_bidi_chunks 结束 / 手动清理时 emit）。
signal _bidi_drain_finished
## _yield_frame 用的自信号。节点销毁时连接自动断开，协程静默死亡。
signal _frame_woke


func _on_bidi_pressed() -> void:
	var text := text_edit.text.strip_edges()
	var voice := _resolved_voice()
	if not _validate(text, voice):
		return
	_set_busy(true)
	_set_status("[双向] 建 WS，准备分段喂入…", Color(0.7, 0.85, 1))
	_refresh_keys()

	var generator := AudioStreamGenerator.new()
	generator.mix_rate = float(ApiConfig.TTS_SAMPLE_RATE)
	generator.buffer_length = 0.5
	player.stop()
	player.stream = generator
	player.play()
	_bidi_playback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _bidi_playback == null:
		_set_status("[失败] 拿不到 AudioStreamGeneratorPlayback。", Color(1, 0.5, 0.5))
		_set_busy(false)
		return

	_bidi_t0_msec = Time.get_ticks_msec()
	var ok: bool = await _bidi.start_session(voice, {"format": "pcm", "sample_rate": ApiConfig.TTS_SAMPLE_RATE})
	if not ok:
		_set_status("[双向] start_session 失败，看 [TTS-Bidi] 警告", Color(1, 0.5, 0.5))
		_set_busy(false)
		return

	# 把全文按 ~每段 30 字（模拟 LLM token chunk）切，每 400ms feed 一段
	var chunks: Array[String] = _split_into_chunks(text, 30)
	for i in chunks.size():
		_set_status("[双向] feed_text %d/%d…" % [i + 1, chunks.size()], Color(0.7, 0.85, 1))
		_bidi.feed_text(chunks[i])
		await get_tree().create_timer(0.4).timeout
	_bidi.finish_session()
	_set_status("[双向] FinishSession 已发，等剩余音频…", Color(0.7, 0.85, 1))
	# 后续 audio_chunk_received / session_finished 由信号驱动


func _on_bidi_chunk(_sid: String, chunk: PackedByteArray) -> void:
	if _bidi_playback == null:
		return
	# 入队，由单 drain 协程串行 push，避免多协程争抢 playback 引起破音
	_bidi_chunk_queue.append(chunk)
	if not _bidi_drain_running:
		_bidi_drain_running = true
		_drain_bidi_chunks()


func _drain_bidi_chunks() -> void:
	while not _bidi_chunk_queue.is_empty():
		if not is_inside_tree() or _bidi_playback == null:
			_bidi_chunk_queue.clear()
			break
		var chunk: PackedByteArray = _bidi_chunk_queue.pop_front()
		await _push_pcm(_bidi_playback, chunk)
	_bidi_drain_running = false
	_bidi_drain_finished.emit()


func _on_bidi_finished(_sid: String) -> void:
	var elapsed := (Time.get_ticks_msec() - _bidi_t0_msec) / 1000.0
	_set_status("[双向 成功] 总耗时 %.1fs。session_id=%s" % [elapsed, _sid], Color(0.7, 1, 0.7))
	# 等队列里剩余的 chunk 全部 push 完再清 playback
	if _bidi_drain_running:
		await _bidi_drain_finished
	if not is_inside_tree():
		return
	_bidi_playback = null
	_set_busy(false)


func _on_bidi_failed(_session_id: String, reason: String) -> void:
	_set_status("[双向 失败] %s" % reason, Color(1, 0.5, 0.5))
	_bidi_chunk_queue.clear()
	_bidi_playback = null
	_set_busy(false)


func _split_into_chunks(s: String, chunk_size: int) -> Array[String]:
	var out: Array[String] = []
	var i := 0
	while i < s.length():
		var end: int = mini(i + chunk_size, s.length())
		out.append(s.substr(i, end - i))
		i = end
	return out


# ───── 系统 TTS（兜底）─────

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
		_set_status("[失败] 系统没装中文 TTS 语音包。", Color(1, 0.6, 0.4))
		return
	DisplayServer.tts_speak(text, voices[0], 50, 1.0, 1.0, 0, true)
	_set_status("[系统 TTS] 朗读中…", Color(0.85, 0.85, 1))


func _on_stop_pressed() -> void:
	if player.playing:
		player.stop()
	if _bidi.is_busy():
		_bidi.cancel()
	if _uni.is_busy():
		_uni.cancel()
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_stop()
	# 清理 bidi 流式状态——bidi 走信号驱动收尾，用户中途停止时
	# _on_bidi_finished 永不触发，需要手动复位 _set_busy 与队列。
	_bidi_chunk_queue.clear()
	_bidi_drain_running = false
	_bidi_drain_finished.emit()
	_bidi_playback = null
	_set_busy(false)
	_set_status("已停止", Color(0.8, 0.8, 0.8))


func _on_back_pressed() -> void:
	if player.playing:
		player.stop()
	if _bidi.is_busy():
		_bidi.cancel()
	if _uni.is_busy():
		_uni.cancel()
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_stop()
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


# ───── 工具 ─────

## 安全的单帧让出。把 process_frame 转发到自信号 _frame_woke：
## 节点销毁时连接自动断开、协程静默死亡，避免在 freed 实例上恢复。
func _yield_frame() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.process_frame.connect(_frame_woke.emit, CONNECT_ONE_SHOT)
	await _frame_woke

func _validate(text: String, voice: String) -> bool:
	if text.is_empty():
		_set_status("文本为空", Color(1, 0.6, 0.6))
		return false
	if voice.is_empty():
		_set_status("voice_type 为空", Color(1, 0.6, 0.6))
		return false
	if api_key_edit.text.strip_edges().is_empty():
		_set_status("API Key 为空：火山 TTS 无法调用。", Color(1, 0.85, 0.4))
		return false
	return true


func _push_pcm(pb: AudioStreamGeneratorPlayback, bytes: PackedByteArray) -> void:
	# PCM int16 LE → Vector2 frames，背压让出帧
	@warning_ignore("integer_division")
	var sample_count := bytes.size() / 2
	if sample_count <= 0:
		return
	var frames := PackedVector2Array()
	frames.resize(sample_count)
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = bytes
	for i in sample_count:
		var s := float(buf.get_16()) / 32768.0
		frames[i] = Vector2(s, s)
	var idx := 0
	while idx < frames.size():
		if not is_inside_tree() or pb == null:
			return
		var avail := pb.get_frames_available()
		if avail <= 0:
			await _yield_frame()
			continue
		var end := mini(idx + avail, frames.size())
		var slice := frames.slice(idx, end)
		pb.push_buffer(slice)
		idx = end


func _set_busy(busy: bool) -> void:
	synth_btn.disabled = busy
	stream_synth_btn.disabled = busy
	if bidi_btn != null:
		bidi_btn.disabled = busy
	system_btn.disabled = busy
	api_key_edit.editable = not busy


func _set_status(msg: String, color: Color = Color.WHITE) -> void:
	status_label.text = msg
	status_label.add_theme_color_override("font_color", color)
