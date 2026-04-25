class_name VolcengineTTSClient
extends Node
## 火山引擎双向流式 TTS（豆包语音合成 2.0）的 GDScript 客户端，
## 把 Python 参考实现的二进制协议翻译过来。
##
## 用法：
##   var client := VolcengineTTSClient.new()
##   client.api_key = "your-key"
##   add_child(client)
##   var mp3 := await client.synthesize("你好", "zh_male_dayi_uranus_bigtts")
##   if not mp3.is_empty():
##       var stream := AudioStreamMP3.new()
##       stream.data = mp3
##       audio_player.stream = stream
##       audio_player.play()
##
## 协议结构（每帧）：
##   [0x11, msg_type, serialization, 0x00] + int32 event + [u32 sid_len + sid] + u32 payload_len + payload
##   其中 audio-only 帧（msg_type=0xB4）的 payload 是裸 mp3 字节。
##
## 设计要点：
##   - 单次 synthesize 内自建 + 关闭一个 WS 连接，避免长连接管理
##   - 串行：synthesize 内部维护 _busy，重入直接返回空
##   - 失败一律返回空 PackedByteArray，调用方处理为"无音频"

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

const ApiConfig := preload("res://scripts/config/api_config.gd")

# ─── 默认配置（来自 ApiConfig，可在实例上覆盖）───────────────────
const CONNECT_TIMEOUT_MSEC := 8000
const SESSION_TIMEOUT_MSEC := 20000
const POLL_INTERVAL_FRAMES := 1   # 每多少帧 poll 一次（1 = 每帧）

## API Key（默认从 ApiConfig 读，调用方可覆盖）。
var api_key: String = ApiConfig.TTS_API_KEY
## 用户 ID，主要用于服务端日志。
var user_uid: String = ApiConfig.TTS_USER_UID
## WebSocket 端点。
var ws_url: String = ApiConfig.TTS_WS_URL
## Resource ID。
var resource_id: String = ApiConfig.TTS_RESOURCE_ID
## 默认 model（音色不传 model 时用）。
var default_model: String = ApiConfig.TTS_MODEL

var _busy: bool = false


## 同步合成一段文本为 mp3 字节流。失败返回空 PackedByteArray。
## voice / model / emotion 走音色清单约定：
##   - voice: 形如 "zh_male_dayi_uranus_bigtts"
##   - model: 留空使用 DEFAULT_MODEL
##   - emotion: "happy"/"sad"/"angry"/...，仅情感音色有效；不需要传空字符串
func synthesize(text: String, voice: String, model: String = "", emotion: String = "") -> PackedByteArray:
	if _busy:
		push_warning("[TTS] 上次合成尚未完成，丢弃本次")
		return PackedByteArray()
	if api_key.is_empty():
		push_warning("[TTS] api_key 未设置（ApiConfig.TTS_API_KEY 为空），跳过合成")
		return PackedByteArray()
	if text.is_empty() or voice.is_empty():
		return PackedByteArray()

	_busy = true
	var ws := WebSocketPeer.new()
	var connect_id := _gen_uuid()
	ws.handshake_headers = PackedStringArray([
		"X-Api-Key: " + api_key,
		"X-Api-Resource-Id: " + resource_id,
		"X-Api-Connect-Id: " + connect_id,
		"X-Control-Require-Usage-Tokens-Return: *",
	])

	var err := ws.connect_to_url(ws_url)
	if err != OK:
		push_warning("[TTS] connect_to_url 失败: %s" % error_string(err))
		_busy = false
		return PackedByteArray()

	# 等连接建立
	if not await _wait_for_open(ws):
		_busy = false
		_safe_close(ws)
		return PackedByteArray()

	# 1. StartConnection → ConnectionStarted
	_send_packet(ws, EVENT_START_CONNECTION, {}, "")
	if not await _wait_event(ws, [EVENT_CONNECTION_STARTED]):
		_busy = false
		_safe_close(ws)
		return PackedByteArray()

	# 2. StartSession → SessionStarted
	var session_id := _gen_uuid()
	var req_params := {
		"speaker": voice,
		"audio_params": {
			"format": ApiConfig.TTS_AUDIO_FORMAT,
			"sample_rate": ApiConfig.TTS_SAMPLE_RATE,
			"bit_rate": ApiConfig.TTS_BIT_RATE,
			"speech_rate": 0,
			"loudness_rate": 0,
		},
		"additions": JSON.stringify({
			"disable_markdown_filter": false,
			"enable_language_detector": true,
		}),
	}
	var actual_model: String = model if not model.is_empty() else default_model
	if not actual_model.is_empty():
		req_params["model"] = actual_model
	if not emotion.is_empty():
		(req_params["audio_params"] as Dictionary)["emotion"] = emotion
		(req_params["audio_params"] as Dictionary)["emotion_scale"] = 4

	var start_payload := {
		"event": EVENT_START_SESSION,
		"namespace": "BidirectionalTTS",
		"user": {"uid": user_uid},
		"req_params": req_params,
	}
	_send_packet(ws, EVENT_START_SESSION, start_payload, session_id)
	if not await _wait_event(ws, [EVENT_SESSION_STARTED]):
		_busy = false
		_safe_close(ws)
		return PackedByteArray()

	# 3. TaskRequest + FinishSession（一次性把全文丢进去，等所有音频回来）
	_send_packet(ws, EVENT_TASK_REQUEST, {
		"event": EVENT_TASK_REQUEST,
		"namespace": "BidirectionalTTS",
		"req_params": {"text": text},
	}, session_id)
	_send_packet(ws, EVENT_FINISH_SESSION, {}, session_id)

	# 4. 收音频直到 SessionFinished
	var audio := PackedByteArray()
	var deadline := Time.get_ticks_msec() + SESSION_TIMEOUT_MSEC
	var got_finish := false
	while not got_finish:
		if Time.get_ticks_msec() > deadline:
			push_warning("[TTS] 等待 SessionFinished 超时，已收 %d 字节" % audio.size())
			break
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var raw: PackedByteArray = ws.get_packet()
			var msg := _parse_server_packet(raw)
			if msg.msg_type == MSG_ERROR:
				push_warning("[TTS] 服务端错误 code=%s payload=%s" % [msg.error_code, msg.payload])
				audio = PackedByteArray()
				got_finish = true
				break
			if msg.event == EVENT_SESSION_FAILED:
				push_warning("[TTS] SessionFailed: %s" % msg.payload)
				audio = PackedByteArray()
				got_finish = true
				break
			var chunk: PackedByteArray = msg.audio
			if chunk.size() > 0:
				audio.append_array(chunk)
			if msg.event == EVENT_SESSION_FINISHED:
				got_finish = true
				break
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			break
		await get_tree().process_frame

	# 5. FinishConnection（best-effort）
	_send_packet(ws, EVENT_FINISH_CONNECTION, {}, "")
	_safe_close(ws)
	_busy = false
	return audio


# ─── 内部：连接管理 ─────────────────────────────────────────

func _wait_for_open(ws: WebSocketPeer) -> bool:
	var deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MSEC
	while true:
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			return true
		if st == WebSocketPeer.STATE_CLOSED or st == WebSocketPeer.STATE_CLOSING:
			push_warning("[TTS] 连接被关闭，状态=%d" % st)
			return false
		if Time.get_ticks_msec() > deadline:
			push_warning("[TTS] 连接超时")
			return false
		await get_tree().process_frame
	return false


func _wait_event(ws: WebSocketPeer, expected: Array, timeout_msec: int = SESSION_TIMEOUT_MSEC) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while true:
		if Time.get_ticks_msec() > deadline:
			push_warning("[TTS] 等待事件 %s 超时" % str(expected))
			return false
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var raw: PackedByteArray = ws.get_packet()
			var msg := _parse_server_packet(raw)
			if msg.msg_type == MSG_ERROR:
				push_warning("[TTS] 服务端错误 code=%s payload=%s" % [msg.error_code, msg.payload])
				return false
			if msg.event == EVENT_CONNECTION_FAILED or msg.event == EVENT_SESSION_FAILED:
				push_warning("[TTS] 失败事件 %s payload=%s" % [msg.event, msg.payload])
				return false
			if msg.event in expected:
				return true
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			push_warning("[TTS] 连接被远端关闭")
			return false
		await get_tree().process_frame
	return false


func _safe_close(ws: WebSocketPeer) -> void:
	if ws == null:
		return
	if ws.get_ready_state() not in [WebSocketPeer.STATE_CLOSED, WebSocketPeer.STATE_CLOSING]:
		ws.close()


# ─── 内部：包构造 ───────────────────────────────────────────

func _send_packet(ws: WebSocketPeer, event: int, payload: Dictionary, session_id: String) -> void:
	var bytes := _make_client_packet(event, payload, session_id)
	var err := ws.send(bytes)  # 默认 BINARY
	if err != OK:
		push_warning("[TTS] send 失败 event=%d err=%s" % [event, error_string(err)])


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


# ─── 内部：包解析 ───────────────────────────────────────────

func _parse_server_packet(data: PackedByteArray) -> Dictionary:
	var result := {
		"msg_type": 0,
		"event": 0,
		"session_id": "",
		"connection_id": "",
		"payload": null,
		"audio": PackedByteArray(),
		"error_code": 0,
	}
	if data.size() < 4:
		return result

	var msg_type := data[1]
	result.msg_type = msg_type

	var buf := StreamPeerBuffer.new()
	buf.big_endian = true
	buf.data_array = data
	buf.seek(4)

	# 错误包
	if msg_type == MSG_ERROR:
		result.error_code = buf.get_32()
		result.event = result.error_code
		if buf.get_position() + 4 <= data.size():
			var sz := buf.get_u32()
			if buf.get_position() + sz <= data.size():
				var bytes := buf.get_data(int(sz))[1] as PackedByteArray
				result.payload = _decode_payload(bytes)
		return result

	# 正常包：event
	result.event = buf.get_32()

	# Connection 系列：connection_id 在前
	if result.event == EVENT_CONNECTION_STARTED or result.event == EVENT_CONNECTION_FAILED:
		if buf.get_position() + 4 <= data.size():
			var sz := buf.get_u32()
			if buf.get_position() + sz <= data.size():
				var bytes := buf.get_data(int(sz))[1] as PackedByteArray
				result.connection_id = bytes.get_string_from_utf8()
		if buf.get_position() + 4 <= data.size():
			var sz := buf.get_u32()
			if buf.get_position() + sz <= data.size():
				var bytes := buf.get_data(int(sz))[1] as PackedByteArray
				result.payload = _decode_payload(bytes)
		return result

	# Session 系列：session_id 在前
	if buf.get_position() + 4 <= data.size():
		var sz := buf.get_u32()
		if buf.get_position() + sz <= data.size():
			var bytes := buf.get_data(int(sz))[1] as PackedByteArray
			result.session_id = bytes.get_string_from_utf8()

	# 音频帧
	if msg_type == MSG_AUDIO_ONLY_RESPONSE:
		if buf.get_position() + 4 <= data.size():
			var sz := buf.get_u32()
			if buf.get_position() + sz <= data.size():
				var bytes := buf.get_data(int(sz))[1] as PackedByteArray
				result.audio = bytes
		return result

	# 普通响应
	if msg_type == MSG_FULL_SERVER_RESPONSE:
		if buf.get_position() + 4 <= data.size():
			var sz := buf.get_u32()
			if buf.get_position() + sz <= data.size():
				var bytes := buf.get_data(int(sz))[1] as PackedByteArray
				result.payload = _decode_payload(bytes)

	return result


func _decode_payload(bytes: PackedByteArray) -> Variant:
	if bytes.is_empty():
		return null
	var text := bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed != null else text


# ─── 内部：UUID（v4-ish，不严格遵守 RFC 但够用） ─────────────────

func _gen_uuid() -> String:
	var hex := ""
	for i in 4:
		hex += "%08x" % randi()
	# hex 长度 32，按 8-4-4-4-12 切
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]
