class_name VolcengineTTSUnidirectionalClient
extends Node
## 火山引擎豆包 TTS 单向流式 WebSocket 客户端
## （端点：/api/v3/tts/unidirectional/stream）。
##
## 适用场景：一次塞文本，PCM/MP3 流式吐回。**支持 SSML**。
##
## 协议与双向流式**不同**：单向只发一帧 SendText（不带 event 号），
## 然后接收服务端流式音频，最后发 FinishConnection 关闭。无需 StartConnection/
## StartSession/TaskRequest/FinishSession 这些事件。
##
## 流程：
##   1. WS 握手（HTTP Upgrade）
##   2. client → server: SendText 帧（byte1=0x10，无 event 号，payload=full request JSON）
##   3. server → client: TTSSentenceStart(350) / TTSResponse(352) × N / TTSSentenceEnd(351) / SessionFinished(152)
##   4. client → server: FinishConnection 帧（byte1=0x14，event=2，payload=空 JSON）
##   5. WS close
##
## 用法：
##   var client := VolcengineTTSUnidirectionalClient.new()
##   client.api_key = "..."
##   add_child(client)
##   var out := {}
##   var ok := await client.synthesize_streaming(
##       "你好世界", "zh_male_dayi_uranus_bigtts",
##       func(chunk): print("got %d bytes" % chunk.size()),
##       {"format": "pcm", "sample_rate": 24000},
##       out,
##   )

const TtsOptionsScript := preload("res://addons/godot_volcengine_tts/tts_options.gd")

# ─── 协议常量 ───────────────────────────────────────────────
## 收到的事件类型（response）
const EVENT_CONNECTION_FINISHED := 52
const EVENT_SESSION_FINISHED := 152
const EVENT_SESSION_FAILED := 153
const EVENT_TTS_SENTENCE_START := 350
const EVENT_TTS_SENTENCE_END := 351
const EVENT_TTS_RESPONSE := 352
## 发出的事件（client → server，仅在 FinishConnection 时使用）
const EVENT_FINISH_CONNECTION := 2

## 帧 byte1：
##   高 4 bit = message type (0001=Full-client, 1001=Full-server, 1011=Audio-only, 1111=Error)
##   低 4 bit = flags (0000=no event num, 0100=with event num)
const FRAME_FULL_CLIENT_NO_EVENT := 0x10  # SendText
const FRAME_FULL_CLIENT_WITH_EVENT := 0x14  # FinishConnection

const MSG_FULL_SERVER_RESPONSE := 0x94
const MSG_AUDIO_ONLY_RESPONSE := 0xB4
const MSG_ERROR := 0xF0

const SERIAL_JSON := 0x10

# ─── 配置 ───────────────────────────────────────────────────
@export var api_key: String = ""
@export var base_url: String = "openspeech.bytedance.com"
@export var path: String = "/api/v3/tts/unidirectional/stream"
@export var resource_id: String = "seed-tts-2.0"
@export var user_uid: String = "default"
@export var default_model: String = ""
@export var connect_timeout_msec: int = 8000
@export var session_timeout_msec: int = 20000

var _busy: bool = false
var _cancel_requested: bool = false
## 保留对当前活动 WS 的引用，使 cancel() 能立即关连接打断主循环。
var _active_ws: WebSocketPeer = null


## 流式合成。返回 true=正常完成；false=失败 / 被取消。
## - on_chunk: Callable(chunk: PackedByteArray)，每收到一段音频就回调一次（可同步可 await）
## - opts: 见 tts_options.gd（emotion/speech_rate/format/ssml/section_id/...）
## - out_session_id: 调用方传一个空 dict，SDK 会写入 ["session_id"]，方便做 section_id 链
func synthesize_streaming(
	text: String,
	voice: String,
	on_chunk: Callable,
	opts: Dictionary = {},
	out_session_id: Dictionary = {},
) -> bool:
	if _busy:
		push_warning("[TTS-Uni] 上次合成尚未完成，丢弃本次")
		return false
	if api_key.is_empty():
		push_warning("[TTS-Uni] api_key 未设置")
		return false
	if voice.is_empty():
		push_warning("[TTS-Uni] voice 不能为空")
		return false
	var has_ssml: bool = opts.has("ssml") and not String(opts["ssml"]).is_empty()
	if text.is_empty() and not has_ssml:
		push_warning("[TTS-Uni] text 与 ssml 都为空")
		return false
	if has_ssml:
		TtsOptionsScript.warn_if_ssml_unsupported(voice, "unidirectional")

	_busy = true
	_cancel_requested = false
	var ws := WebSocketPeer.new()
	_active_ws = ws
	var connect_id := _gen_uuid()
	ws.handshake_headers = PackedStringArray([
		"X-Api-Key: " + api_key,
		"X-Api-Resource-Id: " + resource_id,
		"X-Api-Connect-Id: " + connect_id,
		"X-Control-Require-Usage-Tokens-Return: *",
	])

	var url := "wss://" + base_url + path
	var err := ws.connect_to_url(url)
	if err != OK:
		push_warning("[TTS-Uni] connect_to_url 失败: %s" % error_string(err))
		_release()
		return false

	if not await _wait_for_open(ws):
		_safe_close(ws)
		_release()
		return false

	# 1. 构造并发送 SendText（一次性把全文 + 配置打包发出）
	var req_params := TtsOptionsScript.build_req_params(voice, opts)
	# model 仅对 saturn_ 前缀的 ICL 2.0 复刻音色生效
	if not req_params.has("model") and not default_model.is_empty() and voice.begins_with("saturn_"):
		req_params["model"] = default_model
	if not has_ssml:
		req_params["text"] = text
	# has_ssml 时 build_req_params 已经把 ssml 放进 req_params

	var payload := {
		"user": {"uid": user_uid},
		"req_params": req_params,
	}
	_send_text_packet(ws, payload)

	# 2. 收音频循环
	# 超时是"无活动"超时：每收到一个包重置 deadline
	var deadline := Time.get_ticks_msec() + session_timeout_msec
	var got_finish := false
	var ok := false
	while not got_finish and not _cancel_requested:
		if Time.get_ticks_msec() > deadline:
			@warning_ignore("integer_division")
			var sec := session_timeout_msec / 1000
			push_warning("[TTS-Uni] 等待 SessionFinished 超时（无活动 %ds）" % sec)
			break
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var raw: PackedByteArray = ws.get_packet()
			deadline = Time.get_ticks_msec() + session_timeout_msec
			var msg := _parse_server_packet(raw)
			if msg.msg_type == MSG_ERROR:
				push_warning("[TTS-Uni] 服务端错误 code=%s payload=%s" % [msg.error_code, msg.payload])
				got_finish = true
				break
			# 第一次见到 session_id 就保存
			if not msg.session_id.is_empty() and not out_session_id.has("session_id"):
				out_session_id["session_id"] = msg.session_id
			if msg.event == EVENT_SESSION_FAILED:
				push_warning("[TTS-Uni] SessionFailed: %s" % msg.payload)
				got_finish = true
				break
			# 音频帧（事件 352）
			var chunk: PackedByteArray = msg.audio
			if chunk.size() > 0 and on_chunk.is_valid():
				await on_chunk.call(chunk)
			if msg.event == EVENT_SESSION_FINISHED:
				got_finish = true
				ok = true
				break
			# 350 / 351 句首/句尾事件忽略（如需字幕，调用方可 hook on_chunk 之外的扩展）
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			break
		if not is_inside_tree():
			break
		await get_tree().process_frame

	# 3. FinishConnection（带 event 号），best-effort
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send_finish_connection(ws)
	_safe_close(ws)
	# cancel() 可能已经把 _busy 释放并把 _active_ws 清掉。
	# 只有在它还没动手（即正常退出）时，本协程才负责复位状态。
	if _active_ws == ws:
		_release()
	return ok and not _cancel_requested


func is_busy() -> bool:
	return _busy


## 请求中断当前合成。立即关 WS 让主循环马上断开 + 同步释放 _busy，
## 调用方下一行就能再次发起新请求。
func cancel() -> void:
	if not _busy:
		return
	_cancel_requested = true
	if _active_ws != null:
		var ws := _active_ws
		_active_ws = null
		_safe_close(ws)
	_busy = false


## 集中释放：关掉 _active_ws、清 _busy。
## synthesize_streaming 各种失败/正常退出路径共用，避免漏改。
func _release() -> void:
	_active_ws = null
	_busy = false


# ─── 内部：连接 ────────────────────────────────────────────

func _wait_for_open(ws: WebSocketPeer) -> bool:
	var deadline := Time.get_ticks_msec() + connect_timeout_msec
	while true:
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			return true
		if st == WebSocketPeer.STATE_CLOSED or st == WebSocketPeer.STATE_CLOSING:
			push_warning("[TTS-Uni] 连接被关闭，状态=%d" % st)
			return false
		if Time.get_ticks_msec() > deadline:
			push_warning("[TTS-Uni] 连接超时")
			return false
		if not is_inside_tree():
			return false
		await get_tree().process_frame
	return false


func _safe_close(ws: WebSocketPeer) -> void:
	if ws == null:
		return
	if ws.get_ready_state() not in [WebSocketPeer.STATE_CLOSED, WebSocketPeer.STATE_CLOSING]:
		ws.close()


# ─── 内部：包构造 ────────────────────────────────────────────

## SendText 帧：byte1=0x10（Full-client request, **无 event 号**）+ payload。
## 这是单向流式专属帧格式，与双向流式的 0x14（含 event 号）不同。
func _send_text_packet(ws: WebSocketPeer, payload: Dictionary) -> void:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_u8(0x11)                       # v1, 4-byte header
	buf.put_u8(FRAME_FULL_CLIENT_NO_EVENT)  # 0x10：full-client + 无 event 号
	buf.put_u8(SERIAL_JSON)
	buf.put_u8(0x00)
	var payload_bytes := JSON.stringify(payload).to_utf8_buffer()
	buf.put_u32(payload_bytes.size())
	buf.put_data(payload_bytes)
	var err := ws.send(buf.data_array)
	if err != OK:
		push_warning("[TTS-Uni] SendText 发送失败: %s" % error_string(err))


## FinishConnection 帧：byte1=0x14（含 event 号）+ event(2) + 空 payload。
func _send_finish_connection(ws: WebSocketPeer) -> void:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_u8(0x11)
	buf.put_u8(FRAME_FULL_CLIENT_WITH_EVENT)  # 0x14
	buf.put_u8(SERIAL_JSON)
	buf.put_u8(0x00)
	buf.put_32(EVENT_FINISH_CONNECTION)
	var payload_bytes := "{}".to_utf8_buffer()
	buf.put_u32(payload_bytes.size())
	buf.put_data(payload_bytes)
	var err := ws.send(buf.data_array)
	if err != OK:
		push_warning("[TTS-Uni] FinishConnection 发送失败: %s" % error_string(err))


# ─── 内部：响应解析 ──────────────────────────────────────────

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

	# 错误帧
	if msg_type == MSG_ERROR:
		result.error_code = buf.get_32()
		result.event = result.error_code
		result.payload = _decode_payload(_read_lp_bytes(buf, n))
		return result

	# 正常帧（msg_type 高 4 bit 含义：1001=Full-server, 1011=Audio-only）
	# 单向流式所有响应都带 event 号
	result.event = buf.get_32()

	# ConnectionFinished：connection_id + payload
	if result.event == EVENT_CONNECTION_FINISHED:
		result.connection_id = _read_lp_bytes(buf, n).get_string_from_utf8()
		result.payload = _decode_payload(_read_lp_bytes(buf, n))
		return result

	# 其余 session 类事件：session_id 在前
	result.session_id = _read_lp_bytes(buf, n).get_string_from_utf8()

	# 音频帧
	if msg_type == MSG_AUDIO_ONLY_RESPONSE:
		result.audio = _read_lp_bytes(buf, n)
		return result

	# 其他响应：JSON payload
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
