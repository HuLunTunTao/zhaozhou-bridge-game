class_name VolcengineStreamingVoicePlayer
extends Node
## 火山 TTS 高层"会发声的节点"。
##
## 内部持有三个 client（双向 / 单向 WS / HTTP）+ 一个 AudioStreamPlayer，
## 对调用方暴露**用法导向**的三个 API：
##
##   speak(text, voice, opts)              ← 走单向流式 WS（最常用，低延迟）
##   start_streaming/feed_text/finish      ← 走双向 WS（LLM token streaming）
##   fetch_audio(text, voice, opts)        ← 走 HTTP，返回完整字节（缓存/外部播放）
##
## 上下文链：开 auto_context_chain 后，连续 speak/finish_streaming 会自动用
## 前一次的 session_id 做 section_id，让 TTS 2.0 的语调延续。
## 切角色/场景时调 reset_context_chain() 显式断开。
##
## 用法：
##   var voice := VolcengineStreamingVoicePlayer.new()
##   voice.audio_bus = &"Voice"
##   add_child(voice)
##   voice.bidi_client.api_key = "..."
##   voice.uni_client.api_key = "..."
##   voice.http_client.api_key = "..."
##   await voice.speak("你好", "zh_male_dayi_uranus_bigtts")

const BidiClientScript := preload("res://addons/godot_volcengine_tts/volcengine_tts_bidirectional_client.gd")
const UniClientScript := preload("res://addons/godot_volcengine_tts/volcengine_tts_unidirectional_client.gd")
const HttpClientScript := preload("res://addons/godot_volcengine_tts/volcengine_tts_http_client.gd")
const TtsOptionsScript := preload("res://addons/godot_volcengine_tts/tts_options.gd")

# ─── 配置 ───────────────────────────────────────────────────
@export var audio_bus: StringName = &"Master"
@export var sample_rate: int = 24000
@export var buffer_length: float = 0.5
## true 时连续两次 speak 自动接续 section_id（仅 TTS 2.0 音色生效）。
@export var auto_context_chain: bool = false

# ─── 公开 client 实例（调用方设 api_key 等）───────────────────
var bidi_client: VolcengineTTSBidirectionalClient
var uni_client: VolcengineTTSUnidirectionalClient
var http_client: VolcengineTTSHttpClient

# ─── 信号 ───────────────────────────────────────────────────
## speak() 与 finish_streaming() 完成（成功或失败）后 emit。
signal speak_finished

# ─── 内部 ───────────────────────────────────────────────────
var _player: AudioStreamPlayer = null
var _generator: AudioStreamGenerator = null
var _playback: AudioStreamGeneratorPlayback = null
var _last_session_id: String = ""
var _speaking: bool = false


func _ready() -> void:
	bidi_client = BidiClientScript.new()
	uni_client = UniClientScript.new()
	http_client = HttpClientScript.new()
	add_child(bidi_client)
	add_child(uni_client)
	add_child(http_client)
	_player = AudioStreamPlayer.new()
	_player.bus = audio_bus
	add_child(_player)
	# 双向 client 信号挂一遍（只有走 start_streaming 路径才会真正派发）
	bidi_client.audio_chunk_received.connect(_on_bidi_audio_chunk)
	bidi_client.session_finished.connect(_on_bidi_session_finished)
	bidi_client.session_failed.connect(_on_bidi_session_failed)


# ─── 用法 A：单句流式（走双向 WS，单 session 喂全文）───────
# 选用 bidi 而非 uni 端点的原因：
# 1. bidi 协议层成熟、对 model/resource_id 容忍度高
# 2. uni 端点对 model 字段较严，部分音色组合会报 "resource ID is mismatched with speaker"
# 3. bidi 走 start_session→feed_text(全文)→finish_session 与一次性输入语义等价，延迟相当

## 一次性给文本，流式播放。返回 true=正常播完；false=失败（会 emit speak_finished）。
func speak(text: String, voice: String, opts: Dictionary = {}) -> bool:
	if _speaking:
		push_warning("[VoicePlayer] 上次 speak 未结束（重入）")
		return false

	# 自动 section_id 续接
	var effective_opts := opts.duplicate()
	if auto_context_chain and not _last_session_id.is_empty() and not effective_opts.has("section_id"):
		effective_opts["section_id"] = _last_session_id

	# 决定输出格式（默认 PCM 流式）
	if not effective_opts.has("format"):
		effective_opts["format"] = "pcm"
	if not effective_opts.has("sample_rate"):
		effective_opts["sample_rate"] = sample_rate

	var fmt: String = TtsOptionsScript.get_audio_format(effective_opts)
	if fmt != "pcm":
		push_warning("[VoicePlayer] speak() 当前只支持 PCM 流式播放；如需 mp3 请用 fetch_audio()。已强制 pcm")
		effective_opts["format"] = "pcm"
		fmt = "pcm"

	_speaking = true
	_setup_streaming_player(int(effective_opts["sample_rate"]))

	# 走双向：start → feed(全文) → finish。剩余的音频接收 + 播放结束由信号驱动
	var ok: bool = await bidi_client.start_session(voice, effective_opts)
	if not ok:
		_speaking = false
		_player.stop()
		speak_finished.emit()
		return false
	bidi_client.feed_text(text)
	bidi_client.finish_session()
	# 等 _on_bidi_session_finished / _on_bidi_session_failed 触发 speak_finished
	await speak_finished
	return true


# ─── 用法 B：真双向（走双向 WS）─────────────────────────────

func start_streaming(voice: String, opts: Dictionary = {}) -> bool:
	if _speaking:
		push_warning("[VoicePlayer] 上次合成未结束")
		return false
	var effective_opts := opts.duplicate()
	if auto_context_chain and not _last_session_id.is_empty() and not effective_opts.has("section_id"):
		effective_opts["section_id"] = _last_session_id
	if not effective_opts.has("format"):
		effective_opts["format"] = "pcm"
	if not effective_opts.has("sample_rate"):
		effective_opts["sample_rate"] = sample_rate

	_speaking = true
	_setup_streaming_player(int(effective_opts["sample_rate"]))
	var ok: bool = await bidi_client.start_session(voice, effective_opts)
	if not ok:
		_speaking = false
		speak_finished.emit()
	return ok


func feed_text(chunk: String) -> bool:
	return bidi_client.feed_text(chunk)


func finish_streaming() -> void:
	bidi_client.finish_session()
	# 后续 audio_chunk_received / session_finished 由信号回调驱动，这里直接返回
	# speak_finished 在 _on_bidi_session_finished 里 emit


# ─── 用法 C：拿原始字节（走 HTTP）───────────────────────────

## 阻塞直到拿到完整音频字节。注意：HTTP 路径不影响 _speaking / _last_session_id 状态。
func fetch_audio(text: String, voice: String, opts: Dictionary = {}) -> PackedByteArray:
	var out_session: Dictionary = {}
	return await http_client.synthesize(text, voice, opts, out_session)


# ─── 上下文链管理 ───────────────────────────────────────────

func reset_context_chain() -> void:
	_last_session_id = ""


func is_speaking() -> bool:
	return _speaking


func current_session_id() -> String:
	return _last_session_id


# ─── 内部：playback 准备 ──────────────────────────────────────

func _setup_streaming_player(rate: int) -> void:
	_player.stop()
	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = float(rate)
	_generator.buffer_length = buffer_length
	_player.stream = _generator
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback == null:
		push_warning("[VoicePlayer] 拿不到 AudioStreamGeneratorPlayback")


## 等当前 buffer 里的帧全部播完，再让 speak 返回。
## 不做无限等：超过 buffer_length × 2 就当播完。
func _drain_player() -> void:
	if _playback == null or _player == null:
		return
	var max_wait := int(buffer_length * 2.0 * 1000.0)
	var deadline := Time.get_ticks_msec() + max_wait
	while _player.playing and _playback.get_frames_available() < int(_generator.buffer_length * _generator.mix_rate * 0.95):
		if Time.get_ticks_msec() > deadline:
			break
		if not is_inside_tree():
			break
		await get_tree().process_frame
	_player.stop()


# ─── 内部：PCM 字节 → frames → push_buffer（背压）──────────
# 用单 drain 协程 + FIFO 队列串行化所有 push，避免多个异步回调
# 同时争抢 _playback 导致 frame 顺序错乱（卡顿/破音）。

var _chunk_queue: Array[PackedByteArray] = []
var _drain_running: bool = false


func _on_pcm_chunk(chunk: PackedByteArray) -> void:
	_enqueue_chunk(chunk)


func _on_bidi_audio_chunk(chunk: PackedByteArray) -> void:
	_enqueue_chunk(chunk)


func _enqueue_chunk(chunk: PackedByteArray) -> void:
	if _playback == null:
		return
	_chunk_queue.append(chunk)
	if not _drain_running:
		_drain_running = true
		_drain_chunk_queue()


func _drain_chunk_queue() -> void:
	while not _chunk_queue.is_empty():
		if not is_inside_tree() or _playback == null:
			_chunk_queue.clear()
			break
		var chunk: PackedByteArray = _chunk_queue.pop_front()
		var frames := _pcm_to_frames(chunk)
		await _push_with_backpressure(frames)
	_drain_running = false


func _on_bidi_session_finished(sid: String) -> void:
	_last_session_id = sid
	# 等队列里剩余的 chunk 全部 push 完，再做最终 drain
	while _drain_running:
		if not is_inside_tree():
			break
		await get_tree().process_frame
	await _drain_player()
	_speaking = false
	speak_finished.emit()


func _on_bidi_session_failed(_reason: String) -> void:
	_chunk_queue.clear()
	_speaking = false
	if _player != null and _player.playing:
		_player.stop()
	speak_finished.emit()


func _pcm_to_frames(bytes: PackedByteArray) -> PackedVector2Array:
	@warning_ignore("integer_division")
	var sample_count := bytes.size() / 2
	if sample_count <= 0:
		return PackedVector2Array()
	var out := PackedVector2Array()
	out.resize(sample_count)
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = bytes
	for i in sample_count:
		var s := float(buf.get_16()) / 32768.0
		out[i] = Vector2(s, s)
	return out


func _push_with_backpressure(frames: PackedVector2Array) -> void:
	var idx := 0
	while idx < frames.size():
		if not is_inside_tree() or _playback == null:
			return
		var avail := _playback.get_frames_available()
		if avail <= 0:
			await get_tree().process_frame
			continue
		var end := mini(idx + avail, frames.size())
		var slice := frames.slice(idx, end)
		_playback.push_buffer(slice)
		idx = end
