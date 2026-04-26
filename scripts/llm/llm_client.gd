class_name LLMClient
extends Node
## OpenAI Chat Completions API 兼容的 HTTP 请求发送器。
##
## 提供两条独立通道：
##   1. chat_completion(messages, opts)     —— 非流式，await 拿完整 JSON（BridgeTour 等结构化场景）
##   2. stream_chat_completion(messages, opts) + 信号 —— SSE 流式，逐 token emit（与 TTS bidi 联动）
##
## 用法示例（非流式）：
##   var client := LLMClient.new()
##   add_child(client)
##   var resp := await client.chat_completion([{"role": "user", "content": "你好"}])
##   if resp.ok: print(resp.text)
##
## 用法示例（流式）：
##   client.stream_chunk_received.connect(func(t): print(t))
##   client.stream_finished.connect(func(full, ok, err): print("done"))
##   client.stream_chat_completion([{"role": "user", "content": "你好"}])
##   # ...想中断时：client.abort_stream()

## 允许透传给 OpenAI 的可选参数白名单。其它字段需通过 options.extra_body 传递。
const _ALLOWED_OPTIONS := [
	"temperature",
	"top_p",
	"max_tokens",
	"presence_penalty",
	"frequency_penalty",
	"stop",
	"seed",
	"response_format",
	"n",
	"user",
]

const ApiConfigScript := preload("res://scripts/config/api_config.gd")

## API 根地址，不带尾部斜杠。chat completions 端点拼为 base_url + "/chat/completions"。
var base_url: String = ApiConfigScript.LLM_BASE_URL

## 形如 "sk-..."。从 settings 或环境变量读入；本模块不负责持久化。
var api_key: String = ApiConfigScript.LLM_API_KEY

## 模型名，按 base_url 服务方约定填写。
var model: String = ApiConfigScript.LLM_MODEL

## 单次请求超时秒数。0 表示不超时。
var timeout_sec: float = ApiConfigScript.LLM_TIMEOUT_SEC

var _http: HTTPRequest
var _busy: bool = false

# ── 流式通道（与上面的 _http / _busy 互不影响）──

## 收到一段 token（OpenAI delta.content）。多次 emit 直到 stream_finished。
signal stream_chunk_received(text: String)
## 流式结束（成功/失败均触发）。full_text 是累积的完整文本；失败时仍带已收到的部分。
signal stream_finished(full_text: String, ok: bool, error: String)

var _stream_http: HTTPClient = null
var _stream_busy: bool = false
## 旧协程身份比对：abort_stream() 自增，让仍在跑的 _run_stream_loop 自我退出。
var _stream_token: int = 0
var _stream_buffer: String = ""
## SSE 行解析缓冲，用 PackedByteArray 防止多字节 UTF-8 在 chunk 边界被截断。
var _stream_sse_residual: PackedByteArray = PackedByteArray()


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)


## 发送一次 chat completion 请求并 await 响应。
##
## messages: OpenAI 标准格式，例如
##   [{"role": "system", "content": "..."}, {"role": "user", "content": "..."}]
## options: 可选透传字段（仅白名单内生效），并支持 "extra_body" 子字典强制透传任意键值。
##
## 返回 Dictionary：
##   成功: {"ok": true, "text": String, "raw": Dictionary}
##   失败: {"ok": false, "code": int, "error": String}
func chat_completion(messages: Array, options: Dictionary = {}) -> Dictionary:
	if _busy:
		return _err(-5, "上一次请求尚未完成")
	if api_key.is_empty():
		return _err(-1, "api_key 未设置")
	if messages.is_empty():
		return _err(-1, "messages 不能为空")

	_http.timeout = timeout_sec

	var url := base_url + "/chat/completions"
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
	])

	var body_dict := {
		"model": model,
		"messages": messages,
		"stream": false,
	}
	for key in _ALLOWED_OPTIONS:
		if options.has(key):
			body_dict[key] = options[key]
	if options.has("extra_body") and options["extra_body"] is Dictionary:
		var extra: Dictionary = options["extra_body"]
		for key in extra:
			body_dict[key] = extra[key]

	var body := JSON.stringify(body_dict)

	_busy = true
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		return _err(-1, "请求发起失败: %s" % error_string(err))

	var signal_args: Array = await _http.request_completed
	_busy = false

	var result: int = signal_args[0]
	var response_code: int = signal_args[1]
	var body_bytes: PackedByteArray = signal_args[3]

	if result != HTTPRequest.RESULT_SUCCESS:
		return _err(-2, "网络错误: result=%d" % result)

	var body_text := body_bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body_text)

	if response_code < 200 or response_code >= 300:
		return _err(response_code, "HTTP %d: %s" % [response_code, _extract_error_message(parsed, body_text)])

	if not (parsed is Dictionary):
		return _err(-3, "响应不是合法 JSON")

	var data: Dictionary = parsed
	if not data.has("choices") or not (data["choices"] is Array) or (data["choices"] as Array).is_empty():
		return _err(-4, "响应缺少 choices")
	var first: Variant = (data["choices"] as Array)[0]
	if not (first is Dictionary) or not (first as Dictionary).has("message"):
		return _err(-4, "响应缺少 choices[0].message")
	var message: Variant = (first as Dictionary)["message"]
	if not (message is Dictionary) or not (message as Dictionary).has("content"):
		return _err(-4, "响应缺少 choices[0].message.content")

	return {
		"ok": true,
		"text": str((message as Dictionary)["content"]),
		"raw": data,
	}


func _err(code: int, error: String) -> Dictionary:
	return {"ok": false, "code": code, "error": error}


## 从 OpenAI 风格的错误响应中提取 message；提取不到则截断 body 返回。
func _extract_error_message(parsed: Variant, fallback_body: String) -> String:
	if parsed is Dictionary and (parsed as Dictionary).has("error"):
		var e: Variant = (parsed as Dictionary)["error"]
		if e is Dictionary and (e as Dictionary).has("message"):
			return str((e as Dictionary)["message"])
		if e is String:
			return e
	if fallback_body.length() > 200:
		return fallback_body.substr(0, 200) + "..."
	return fallback_body


# ─────────────────────────────────────────────
# 流式通道（SSE / HTTPClient）
# ─────────────────────────────────────────────

## 启动一次流式聊天补全。立即返回 bool（true=已发起；false=参数错或上次未结束）。
##
## 调用方监听两个信号取数据：
##   stream_chunk_received(text)              —— 每收到一段 token 触发
##   stream_finished(full_text, ok, error)    —— 整个流结束（成功或失败）触发
##
## 中途想停就调 abort_stream()——会让仍在跑的协程自我退出，不再 emit chunk。
##
## 与非流式 chat_completion() 互不干扰：用独立的 HTTPClient + busy 标志位。
func stream_chat_completion(messages: Array, options: Dictionary = {}) -> bool:
	if _stream_busy:
		push_warning("[LLM-Stream] 上次未完成，先 abort_stream() 再重试")
		return false
	if api_key.is_empty():
		push_warning("[LLM-Stream] api_key 未设置")
		return false
	if messages.is_empty():
		return false
	_stream_token += 1
	_stream_busy = true
	_stream_buffer = ""
	_stream_sse_residual = PackedByteArray()
	_stream_http = HTTPClient.new()
	var hp: Dictionary = _parse_host_port(base_url)
	var tls: TLSOptions = TLSOptions.client() if hp["scheme"] == "https" else null
	var err := _stream_http.connect_to_host(hp["host"], hp["port"], tls)
	if err != OK:
		_emit_stream_finished(false, "connect_to_host 失败: %s" % error_string(err))
		return false
	_run_stream_loop(_stream_token, hp, messages, options)
	return true


## 主动中断当前流。idempotent：空闲时调也安全。
## 调完后旧协程会在下一个 await 点检查 token 不匹配并自行退出，
## 之后不再有 stream_chunk_received。stream_finished 会以 ok=false 触发一次。
func abort_stream() -> void:
	if not _stream_busy:
		return
	_stream_token += 1
	if _stream_http != null:
		_stream_http.close()
	_stream_http = null
	var partial := _stream_buffer
	_stream_buffer = ""
	_stream_sse_residual = PackedByteArray()
	_stream_busy = false
	stream_finished.emit(partial, false, "用户中断")


func is_streaming() -> bool:
	return _stream_busy


## SSE 主循环。token 比对随时让旧协程退出，避免 abort 后还残留 emit。
func _run_stream_loop(my_token: int, hp: Dictionary, messages: Array, options: Dictionary) -> void:
	# 1) 等连接
	while _stream_http != null and _stream_http.get_status() in [
		HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING
	]:
		if my_token != _stream_token:
			return
		_stream_http.poll()
		await get_tree().process_frame
	if my_token != _stream_token:
		return
	if _stream_http == null or _stream_http.get_status() != HTTPClient.STATUS_CONNECTED:
		var s: int = -1
		if _stream_http != null:
			s = _stream_http.get_status()
		_emit_stream_finished(false, "连接失败 status=%d" % s)
		return

	# 2) 组装 + 发请求
	var body_dict: Dictionary = {
		"model": model,
		"messages": messages,
		"stream": true,
	}
	for key in _ALLOWED_OPTIONS:
		if options.has(key):
			body_dict[key] = options[key]
	if options.has("extra_body") and options["extra_body"] is Dictionary:
		var extra: Dictionary = options["extra_body"]
		for key in extra:
			body_dict[key] = extra[key]
	var body := JSON.stringify(body_dict)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
		"Accept: text/event-stream",
	])
	var path: String = hp["path_prefix"] + "/chat/completions"
	var rerr := _stream_http.request(HTTPClient.METHOD_POST, path, headers, body)
	if rerr != OK:
		_emit_stream_finished(false, "request 失败: %s" % error_string(rerr))
		return

	# 3) 等响应头
	while _stream_http != null and _stream_http.get_status() == HTTPClient.STATUS_REQUESTING:
		if my_token != _stream_token:
			return
		_stream_http.poll()
		await get_tree().process_frame
	if my_token != _stream_token:
		return
	if _stream_http == null:
		return
	if not _stream_http.has_response():
		_emit_stream_finished(false, "无 response")
		return

	# 4) 非 2xx：把 body 当错误信息读完
	var rcode := _stream_http.get_response_code()
	if rcode < 200 or rcode >= 300:
		var err_bytes := PackedByteArray()
		while _stream_http != null and _stream_http.get_status() == HTTPClient.STATUS_BODY:
			if my_token != _stream_token:
				return
			_stream_http.poll()
			err_bytes.append_array(_stream_http.read_response_body_chunk())
			await get_tree().process_frame
		var err_text := err_bytes.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(err_text) if not err_text.is_empty() else null
		_emit_stream_finished(false, "HTTP %d: %s" % [rcode, _extract_error_message(parsed, err_text)])
		return

	# 5) 流式读 body chunk
	while _stream_http != null and _stream_http.get_status() == HTTPClient.STATUS_BODY:
		if my_token != _stream_token:
			return
		_stream_http.poll()
		var raw: PackedByteArray = _stream_http.read_response_body_chunk()
		if raw.size() > 0:
			_consume_sse(raw, my_token)
			# _consume_sse 可能在收到 [DONE] 时已 emit_stream_finished，及时退出避免重复
			if not _stream_busy or my_token != _stream_token:
				return
		else:
			await get_tree().process_frame

	# 6) 服务端没发 [DONE] 就把连接关了——也算自然结束
	if my_token == _stream_token and _stream_busy:
		_emit_stream_finished(true, "")


## 解析 SSE：按 \n 切行，取以 "data:" 开头的有效负载，处理 [DONE] 终止。
## 用 PackedByteArray 累积，避免多字节 UTF-8 字符在 chunk 边界被截断。
func _consume_sse(raw: PackedByteArray, my_token: int) -> void:
	_stream_sse_residual.append_array(raw)
	var lf_byte: int = 10  # '\n'
	while true:
		var nl := _stream_sse_residual.find(lf_byte)
		if nl < 0:
			break
		var line_bytes: PackedByteArray = _stream_sse_residual.slice(0, nl)
		_stream_sse_residual = _stream_sse_residual.slice(nl + 1)
		var line := line_bytes.get_string_from_utf8().strip_edges()
		if line.is_empty() or not line.begins_with("data:"):
			continue
		var payload := line.substr(5).strip_edges()
		if payload == "[DONE]":
			_emit_stream_finished(true, "")
			return
		var parsed: Variant = JSON.parse_string(payload)
		if not (parsed is Dictionary):
			continue
		var choices_v: Variant = (parsed as Dictionary).get("choices", [])
		if not (choices_v is Array) or (choices_v as Array).is_empty():
			continue
		var first_v: Variant = (choices_v as Array)[0]
		if not (first_v is Dictionary):
			continue
		var delta_v: Variant = (first_v as Dictionary).get("delta", {})
		if not (delta_v is Dictionary):
			continue
		var content := str((delta_v as Dictionary).get("content", ""))
		if content.is_empty():
			continue
		_stream_buffer += content
		if my_token == _stream_token:
			stream_chunk_received.emit(content)


func _emit_stream_finished(ok: bool, error: String) -> void:
	if not _stream_busy:
		return  # idempotent：abort 后或自然结束后再次调用都无副作用
	_stream_busy = false
	var full := _stream_buffer
	_stream_buffer = ""
	_stream_sse_residual = PackedByteArray()
	if _stream_http != null:
		_stream_http.close()
		_stream_http = null
	stream_finished.emit(full, ok, error)


## 极简 URL 拆解：scheme/host/port/path_prefix。Godot 4.6 没内置 URL 类。
func _parse_host_port(url: String) -> Dictionary:
	var scheme := "https"
	var rest := url
	var sep := url.find("://")
	if sep >= 0:
		scheme = url.substr(0, sep).to_lower()
		rest = url.substr(sep + 3)
	var slash := rest.find("/")
	var host_port := rest if slash < 0 else rest.substr(0, slash)
	var path_prefix := "" if slash < 0 else rest.substr(slash)
	# path_prefix 末尾如果是 "/" 后续会拼成 "//chat/completions"，剥掉尾斜杠保安全
	if path_prefix.ends_with("/"):
		path_prefix = path_prefix.substr(0, path_prefix.length() - 1)
	var host := host_port
	var port: int = 443 if scheme == "https" else 80
	var colon := host_port.rfind(":")
	if colon > 0:
		host = host_port.substr(0, colon)
		port = int(host_port.substr(colon + 1))
	return {"host": host, "port": port, "scheme": scheme, "path_prefix": path_prefix}
