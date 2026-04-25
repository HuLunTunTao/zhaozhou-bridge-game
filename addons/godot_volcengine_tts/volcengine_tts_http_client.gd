class_name VolcengineTTSHttpClient
extends Node
## 火山引擎豆包 TTS HTTP Chunked 客户端
## （端点：/api/v3/tts/unidirectional）。
##
## 适用场景：一次塞文本，等服务端把所有 chunk 流完，**累积返回完整音频字节**。
## 适合预合成 / 缓存 / 短文本 UI 提示音。**支持 SSML**。
##
## 响应体格式（HTTP Chunked，每行一个 JSON）：
##   {"code":0,"message":"","data":"<base64音频>"}    ← 多次，每次一段音频
##   {"code":0,"message":"","data":null,"sentence":...} ← 时间戳/字幕（可选）
##   {"code":20000000,"message":"ok","data":null}      ← 结束
##
## 用法：
##   var client := VolcengineTTSHttpClient.new()
##   client.api_key = "..."
##   add_child(client)
##   var out := {}
##   var mp3 := await client.synthesize("你好", "zh_male_dayi_uranus_bigtts", {}, out)
##   # mp3 是完整音频字节，可塞 AudioStreamMP3 直接播

const TtsOptionsScript := preload("res://addons/godot_volcengine_tts/tts_options.gd")

const SUCCESS_FINAL_CODE := 20000000

# ─── 配置 ───────────────────────────────────────────────────
@export var api_key: String = ""
@export var base_url: String = "openspeech.bytedance.com"
@export var path: String = "/api/v3/tts/unidirectional"
@export var resource_id: String = "seed-tts-2.0"
@export var user_uid: String = "default"
@export var default_model: String = ""
@export var connect_timeout_msec: int = 8000
@export var read_timeout_msec: int = 30000   ## HTTP 总活动超时（每收到一段 chunk 续命）

var _busy: bool = false


## 同步合成：返回完整音频字节流（按 opts.format 决定 mp3/pcm/wav 等）。
## 失败返回空 PackedByteArray。out_session_id 暂时不写（HTTP 端点的 session_id 在响应里没单独字段）。
func synthesize(
	text: String,
	voice: String,
	opts: Dictionary = {},
	out_session_id: Dictionary = {},
) -> PackedByteArray:
	if _busy:
		push_warning("[TTS-HTTP] 上次合成尚未完成，丢弃本次")
		return PackedByteArray()
	if api_key.is_empty():
		push_warning("[TTS-HTTP] api_key 未设置")
		return PackedByteArray()
	if voice.is_empty():
		push_warning("[TTS-HTTP] voice 不能为空")
		return PackedByteArray()
	var has_ssml: bool = opts.has("ssml") and not String(opts["ssml"]).is_empty()
	if text.is_empty() and not has_ssml:
		push_warning("[TTS-HTTP] text 与 ssml 都为空")
		return PackedByteArray()

	if has_ssml:
		TtsOptionsScript.warn_if_ssml_unsupported(voice, "http")

	# 火山 HTTP 端点目前不在响应里单独返回 session_id；保留 out 参数为了 API 一致性
	out_session_id["session_id"] = ""

	_busy = true
	var audio := await _do_request(text, voice, opts, has_ssml)
	_busy = false
	return audio


func is_busy() -> bool:
	return _busy


# ─── 内部 ────────────────────────────────────────────────────

func _do_request(text: String, voice: String, opts: Dictionary, has_ssml: bool) -> PackedByteArray:
	var http := HTTPClient.new()
	var conn_err := http.connect_to_host(base_url, 443, TLSOptions.client())
	if conn_err != OK:
		push_warning("[TTS-HTTP] connect_to_host 失败: %s" % error_string(conn_err))
		return PackedByteArray()

	# 等握手完成
	var deadline := Time.get_ticks_msec() + connect_timeout_msec
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		if Time.get_ticks_msec() > deadline:
			push_warning("[TTS-HTTP] 连接超时")
			return PackedByteArray()
		if not is_inside_tree():
			return PackedByteArray()
		await get_tree().process_frame
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		push_warning("[TTS-HTTP] 握手失败，status=%d" % http.get_status())
		return PackedByteArray()

	# 构造 body
	var req_params := TtsOptionsScript.build_req_params(voice, opts)
	# model 仅对 saturn_ 前缀的 ICL 2.0 复刻音色生效；其他音色不传以免报错。
	if not req_params.has("model") and not default_model.is_empty() and voice.begins_with("saturn_"):
		req_params["model"] = default_model
	if has_ssml:
		# build_req_params 已经把 ssml 放对位置；text 字段火山要求空字符串
		pass
	else:
		req_params["text"] = text
	var body_dict := {
		"user": {"uid": user_uid},
		"req_params": req_params,
	}
	var body := JSON.stringify(body_dict)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-Api-Key: " + api_key,
		"X-Api-Resource-Id: " + resource_id,
		"X-Api-Request-Id: " + _gen_uuid(),
		"X-Control-Require-Usage-Tokens-Return: *",
	])

	var req_err := http.request(HTTPClient.METHOD_POST, path, headers, body)
	if req_err != OK:
		push_warning("[TTS-HTTP] request 发起失败: %s" % error_string(req_err))
		return PackedByteArray()

	# 等响应 head
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		if not is_inside_tree():
			return PackedByteArray()
		await get_tree().process_frame

	if http.get_status() != HTTPClient.STATUS_BODY:
		var hdrs := http.get_response_headers()
		var status_code := http.get_response_code()
		push_warning("[TTS-HTTP] 状态异常 code=%d status=%d headers=%s" % [status_code, http.get_status(), str(hdrs)])
		return PackedByteArray()

	if http.get_response_code() < 200 or http.get_response_code() >= 300:
		push_warning("[TTS-HTTP] HTTP %d" % http.get_response_code())
		return PackedByteArray()

	# 流式读 body：每行一个 JSON。
	# Godot HTTPClient.read_response_body_chunk 是字节级，可能不按 JSON 边界切——
	# 自己缓冲、按换行分隔
	var audio := PackedByteArray()
	var leftover := ""
	var read_deadline := Time.get_ticks_msec() + read_timeout_msec
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk: PackedByteArray = http.read_response_body_chunk()
		if chunk.is_empty():
			if Time.get_ticks_msec() > read_deadline:
				push_warning("[TTS-HTTP] 读取超时")
				break
			if not is_inside_tree():
				break
			await get_tree().process_frame
			continue
		read_deadline = Time.get_ticks_msec() + read_timeout_msec
		leftover += chunk.get_string_from_utf8()
		# 按 \n 切行（含 \r\n 的兼容）
		while true:
			var nl := leftover.find("\n")
			if nl < 0:
				break
			var line := leftover.substr(0, nl).strip_edges()
			leftover = leftover.substr(nl + 1)
			if line.is_empty():
				continue
			var done := _process_line(line, audio)
			if done:
				return audio
	# 处理最后剩余（可能没有尾换行）
	if not leftover.strip_edges().is_empty():
		var _done := _process_line(leftover.strip_edges(), audio)
	return audio


## 解析一行 JSON。返回 true 表示已收到结束标志，调用方应停止读。
func _process_line(line: String, audio: PackedByteArray) -> bool:
	var parsed: Variant = JSON.parse_string(line)
	if not (parsed is Dictionary):
		push_warning("[TTS-HTTP] 非法响应行（已忽略）: %s" % line.left(80))
		return false
	var d: Dictionary = parsed
	var code: int = int(d.get("code", -1))
	if code == SUCCESS_FINAL_CODE:
		return true   # 正常结束
	if code != 0:
		push_warning("[TTS-HTTP] 服务端错误 code=%d msg=%s" % [code, d.get("message", "")])
		return true
	var data: Variant = d.get("data", null)
	if data is String and not (data as String).is_empty():
		var b64: String = data
		var bytes := Marshalls.base64_to_raw(b64)
		audio.append_array(bytes)
	# data == null 时是 sentence/timestamp 帧，不带音频，跳过
	return false


func _gen_uuid() -> String:
	var hex := ""
	for i in 4:
		hex += "%08x" % randi()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12),
	]
