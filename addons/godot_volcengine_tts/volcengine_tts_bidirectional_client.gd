class_name VolcengineTTSBidirectionalClient
extends Node
## 火山引擎豆包 TTS 双向流式 WebSocket 客户端（端点：/api/v3/tts/bidirection）。
##
## 适用场景：边喂文字边出音频，与 LLM token streaming 联动延迟最低。
## **不支持** SSML（火山协议限制）。
##
## 协议帧（client → server，二进制大端）：
##   [0x11, msg_type, serialization, 0x00] + i32 event + [u32 sid_len + sid] + u32 payload_len + payload
##
## 用法：
##   var client := VolcengineTTSBidirectionalClient.new()
##   client.api_key = "your-key"
##   add_child(client)
##   client.audio_chunk_received.connect(_on_chunk)
##   client.session_finished.connect(_on_done)
##   await client.start_session("zh_male_dayi_uranus_bigtts")
##   client.feed_text("你好，")
##   client.feed_text("世界。")
##   client.finish_session()

const TtsOptionsScript := preload("res://addons/godot_volcengine_tts/tts_options.gd")

# ─── 协议常量 ───────────────────────────────────────────────
const EVENT_START_CONNECTION := 1
const EVENT_FINISH_CONNECTION := 2
const EVENT_CONNECTION_STARTED := 50
const EVENT_CONNECTION_FAILED := 51

const EVENT_START_SESSION := 100
const EVENT_FINISH_SESSION := 102
const EVENT_SESSION_STARTED := 150
const EVENT_SESSION_FINISHED := 152
const EVENT_SESSION_FAILED := 153

const EVENT_TASK_REQUEST := 200
const EVENT_TTS_RESPONSE := 352

const MSG_FULL_CLIENT_REQUEST := 0x14
const MSG_FULL_SERVER_RESPONSE := 0x94
const MSG_AUDIO_ONLY_RESPONSE := 0xB4
const MSG_ERROR := 0xF0

const SERIAL_JSON := 0x10

# ─── 配置 ───────────────────────────────────────────────────
@export var api_key: String = ""
## host 部分，可改成镜像或兼容站点。
@export var base_url: String = "openspeech.bytedance.com"
## API path，通常不用改；火山改路径时可在此覆盖。
@export var path: String = "/api/v3/tts/bidirection"
@export var resource_id: String = "seed-tts-2.0"
@export var user_uid: String = "default"
@export var default_model: String = ""
@export var connect_timeout_msec: int = 8000
@export var session_timeout_msec: int = 20000

# ─── 信号 ───────────────────────────────────────────────────
## 收到一段音频字节。format（mp3/pcm/...）由 start_session 时的 opts 决定。
## session_id 必须由调用方比对：cancel 之后到达的 in-flight chunk 仍可能 emit，
## 必须靠 sid 区分新旧 session（详见 streaming_voice_player._on_bidi_audio_chunk）。
signal audio_chunk_received(session_id: String, chunk: PackedByteArray)
## session 正常结束。session_id 可被调用方保存做 section_id 链。
signal session_finished(session_id: String)
## session 任意失败原因（鉴权、超时、SessionFailed、WS 断）。
signal session_failed(session_id: String, reason: String)

# ─── 内部状态 ───────────────────────────────────────────────
var _ws: WebSocketPeer = null
var _session_id: String = ""
var _busy: bool = false
var _running: bool = false  # session 是否在 start...finish 之间
var _poll_token: int = 0    # 用来取消旧的 poll loop


# ─── 公共 API ──────────────────────────────────────────────

## 开始一个 session。建立 WS 连接 → StartConnection → StartSession。
## opts: 见 tts_options.gd 注释（emotion/speech_rate/loudness_rate/format/sample_rate/...）
## 返回 true 表示 session 准备好接受 feed_text；false 表示已失败（同时 emit session_failed）
func start_session(voice: String, opts: Dictionary = {}) -> bool:
	if _busy:
		_emit_failed("上次 session 尚未完成（重入）")
		return false
	if api_key.is_empty():
		_emit_failed("api_key 未设置")
		return false
	if voice.is_empty():
		_emit_failed("voice 不能为空")
		return false
	# 双向流式不支持 SSML，做个提醒
	if opts.has("ssml") or opts.has("raw_req_params"):
		TtsOptionsScript.warn_if_ssml_unsupported(voice, "bidirectional")

	_busy = true
	_session_id = _gen_uuid()
	_ws = WebSocketPeer.new()
	var connect_id := _gen_uuid()
	_ws.handshake_headers = PackedStringArray([
		"X-Api-Key: " + api_key,
		"X-Api-Resource-Id: " + resource_id,
		"X-Api-Connect-Id: " + connect_id,
		"X-Control-Require-Usage-Tokens-Return: *",
	])

	var url := "wss://" + base_url + path
	var err := _ws.connect_to_url(url)
	if err != OK:
		_busy = false
		_emit_failed("connect_to_url 失败: %s" % error_string(err))
		return false

	if not await _wait_for_open():
		_close_ws()
		_busy = false
		return false

	_send_packet(EVENT_START_CONNECTION, {}, "")
	if not await _wait_event([EVENT_CONNECTION_STARTED]):
		_close_ws()
		_busy = false
		return false

	# 构造 StartSession payload
	var req_params := TtsOptionsScript.build_req_params(voice, opts)
	# default_model 仅对 saturn_ 前缀的 ICL 2.0 复刻音色生效（火山文档明确）。
	# 对非 saturn_ 音色传 model 在双向端点会被宽容，但单向端点会报
	# "resource ID is mismatched with speaker"。统一规则避免坑。
	if not req_params.has("model") and not default_model.is_empty() and voice.begins_with("saturn_"):
		req_params["model"] = default_model
	var start_payload := {
		"event": EVENT_START_SESSION,
		"namespace": "BidirectionalTTS",
		"user": {"uid": user_uid},
		"req_params": req_params,
	}
	_send_packet(EVENT_START_SESSION, start_payload, _session_id)
	if not await _wait_event([EVENT_SESSION_STARTED]):
		_close_ws()
		_busy = false
		return false

	# 启动后台 poll 接收音频帧（与 feed_text 并发）
	_running = true
	_poll_token += 1
	_run_audio_recv_loop(_poll_token)
	return true


## 喂入一段文本。可多次调用，文本会被火山 TTS 接续合成（共享同一 session 的 prosody）。
## 返回 true 表示包已发送；false 表示 session 未启动 / 已断 / WS 错。
func feed_text(chunk: String) -> bool:
	if not _running or _ws == null:
		push_warning("[TTS-Bidi] feed_text 在 session 未启动时调用，已忽略")
		return false
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		push_warning("[TTS-Bidi] WS 已关闭，feed_text 失败")
		return false
	if chunk.is_empty():
		return true  # 空文本无需发包，不当错
	_send_packet(EVENT_TASK_REQUEST, {
		"event": EVENT_TASK_REQUEST,
		"namespace": "BidirectionalTTS",
		"req_params": {"text": chunk},
	}, _session_id)
	return true


## 结束 session：发送 FinishSession，等服务端把剩余音频流完后 emit session_finished。
## 不阻塞返回，调用方可以接着监听信号。
func finish_session() -> void:
	if not _running or _ws == null:
		return
	_send_packet(EVENT_FINISH_SESSION, {}, _session_id)
	# 后续音频在 _run_audio_recv_loop 里继续收，直到 EVENT_SESSION_FINISHED


## 强行中断当前 session（不发 FinishSession，直接关 WS）。
## 用于"切角色不要再说了"的紧急停止场景。
func cancel() -> void:
	_running = false
	_close_ws()
	_busy = false


func is_busy() -> bool:
	return _busy


func current_session_id() -> String:
	return _session_id


# ─── 内部：异步收音频循环 ─────────────────────────────────

func _run_audio_recv_loop(token: int) -> void:
	var deadline := Time.get_ticks_msec() + session_timeout_msec
	while _running and token == _poll_token:
		if Time.get_ticks_msec() > deadline:
			@warning_ignore("integer_division")
			var sec := session_timeout_msec / 1000
			_emit_failed("等待 SessionFinished 超时（无活动 %ds）" % sec)
			break
		if _ws == null:
			break
		_ws.poll()
		while _ws.get_available_packet_count() > 0:
			var raw: PackedByteArray = _ws.get_packet()
			deadline = Time.get_ticks_msec() + session_timeout_msec  # 收到包→续命
			var msg := _parse_server_packet(raw)
			if msg.msg_type == MSG_ERROR:
				_emit_failed("服务端错误 code=%s payload=%s" % [msg.error_code, msg.payload])
				_close_ws()
				return
			if msg.event == EVENT_SESSION_FAILED:
				_emit_failed("SessionFailed: %s" % msg.payload)
				_close_ws()
				return
			var chunk: PackedByteArray = msg.audio
			if chunk.size() > 0:
				audio_chunk_received.emit(_session_id, chunk)
			if msg.event == EVENT_SESSION_FINISHED:
				_send_packet(EVENT_FINISH_CONNECTION, {}, "")
				var sid := _session_id
				_close_ws()
				_busy = false
				_running = false
				session_finished.emit(sid)
				return
		if _ws == null or _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_emit_failed("WS 被远端关闭")
			break
		if not is_inside_tree():
			break  # 节点 detach，安全退出
		await get_tree().process_frame
	# while 退出（异常或被取消）
	if _running:
		_running = false
	_busy = false


func _emit_failed(reason: String) -> void:
	push_warning("[TTS-Bidi] " + reason)
	session_failed.emit(_session_id, reason)


# ─── 内部：连接管理 ─────────────────────────────────────────

func _wait_for_open() -> bool:
	var deadline := Time.get_ticks_msec() + connect_timeout_msec
	while true:
		if _ws == null:
			return false
		_ws.poll()
		var st := _ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			return true
		if st == WebSocketPeer.STATE_CLOSED or st == WebSocketPeer.STATE_CLOSING:
			_emit_failed("连接被关闭，状态=%d" % st)
			return false
		if Time.get_ticks_msec() > deadline:
			_emit_failed("连接超时")
			return false
		if not is_inside_tree():
			return false
		await get_tree().process_frame
	return false


func _wait_event(expected: Array) -> bool:
	var deadline := Time.get_ticks_msec() + session_timeout_msec
	while true:
		if Time.get_ticks_msec() > deadline:
			_emit_failed("等待事件 %s 超时" % str(expected))
			return false
		if _ws == null:
			return false
		_ws.poll()
		while _ws.get_available_packet_count() > 0:
			var raw: PackedByteArray = _ws.get_packet()
			var msg := _parse_server_packet(raw)
			if msg.msg_type == MSG_ERROR:
				_emit_failed("服务端错误 code=%s payload=%s" % [msg.error_code, msg.payload])
				return false
			if msg.event == EVENT_CONNECTION_FAILED or msg.event == EVENT_SESSION_FAILED:
				_emit_failed("失败事件 %s payload=%s" % [msg.event, msg.payload])
				return false
			if msg.event in expected:
				return true
		if _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_emit_failed("连接被远端关闭")
			return false
		if not is_inside_tree():
			return false
		await get_tree().process_frame
	return false


func _close_ws() -> void:
	if _ws == null:
		return
	if _ws.get_ready_state() not in [WebSocketPeer.STATE_CLOSED, WebSocketPeer.STATE_CLOSING]:
		_ws.close()
	_ws = null


# ─── 内部：包构造 / 解析 ───────────────────────────────────

func _send_packet(event: int, payload: Dictionary, session_id: String) -> void:
	if _ws == null:
		return
	var bytes := _make_client_packet(event, payload, session_id)
	var err := _ws.send(bytes)  # BINARY
	if err != OK:
		push_warning("[TTS-Bidi] send 失败 event=%d err=%s" % [event, error_string(err)])


func _make_client_packet(event: int, payload: Dictionary, session_id: String) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_u8(0x11)
	buf.put_u8(MSG_FULL_CLIENT_REQUEST)
	buf.put_u8(SERIAL_JSON)
	buf.put_u8(0x00)
	buf.put_32(event)
	if not session_id.is_empty():
		var sid := session_id.to_utf8_buffer()
		buf.put_u32(sid.size())
		buf.put_data(sid)
	var payload_bytes := JSON.stringify(payload).to_utf8_buffer()
	buf.put_u32(payload_bytes.size())
	buf.put_data(payload_bytes)
	return buf.data_array


func _parse_server_packet(data: PackedByteArray) -> Dictionary:
	var result := {
		"msg_type": 0, "event": 0, "session_id": "", "connection_id": "",
		"payload": null, "audio": PackedByteArray(), "error_code": 0,
	}
	if data.size() < 4:
		return result
	var msg_type := data[1]
	result.msg_type = msg_type
	var buf := StreamPeerBuffer.new()
	buf.big_endian = true
	buf.data_array = data
	buf.seek(4)
	var n := data.size()

	if msg_type == MSG_ERROR:
		result.error_code = buf.get_32()
		result.event = result.error_code
		result.payload = _decode_payload(_read_lp_bytes(buf, n))
		return result

	result.event = buf.get_32()

	if result.event == EVENT_CONNECTION_STARTED or result.event == EVENT_CONNECTION_FAILED:
		result.connection_id = _read_lp_bytes(buf, n).get_string_from_utf8()
		result.payload = _decode_payload(_read_lp_bytes(buf, n))
		return result

	result.session_id = _read_lp_bytes(buf, n).get_string_from_utf8()

	if msg_type == MSG_AUDIO_ONLY_RESPONSE:
		result.audio = _read_lp_bytes(buf, n)
		return result

	if msg_type == MSG_FULL_SERVER_RESPONSE:
		result.payload = _decode_payload(_read_lp_bytes(buf, n))
	return result


func _read_lp_bytes(buf: StreamPeerBuffer, data_size: int) -> PackedByteArray:
	if buf.get_position() + 4 > data_size:
		return PackedByteArray()
	var sz := buf.get_u32()
	if buf.get_position() + sz > data_size:
		return PackedByteArray()
	return buf.get_data(int(sz))[1] as PackedByteArray


func _decode_payload(bytes: PackedByteArray) -> Variant:
	if bytes.is_empty():
		return null
	var text := bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed != null else text


func _gen_uuid() -> String:
	var hex := ""
	for i in 4:
		hex += "%08x" % randi()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12),
	]
