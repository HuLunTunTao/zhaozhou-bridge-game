class_name LLMClient
extends Node
## OpenAI Chat Completions API 兼容的 HTTP 请求发送器（非流式）。
##
## 用法示例：
##   var client := LLMClient.new()
##   client.api_key = "sk-..."
##   client.base_url = "https://api.deepseek.com/v1"   # 可选，缺省走 OpenAI 官方
##   client.model = "deepseek-chat"
##   add_child(client)
##   var resp := await client.chat_completion([
##       {"role": "user", "content": "你好"}
##   ])
##   if resp.ok:
##       print(resp.text)
##   else:
##       push_warning("LLM 调用失败: %s" % resp.error)

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
