## 火山引擎 TTS 参数分层工具：把扁平 `opts` 字典转成火山协议要求的嵌套 req_params 结构。
##
## 设计目标：让调用方传一层平铺的 dict（{"emotion": "happy", "speech_rate": 10}），
## SDK 内部根据"哪个键属于 audio_params / additions / req_params"自动 demux。
##
## 三个 Tier：
##   Tier 1：什么都不传，只传 voice，全部走默认（mp3 / 24kHz / 中性）
##   Tier 2：扁平键名（emotion/speech_rate/speech 等），SDK 自动归位到正确嵌套
##   Tier 3：逃生口键名
##     - audio_params_extra : Dictionary，merge 进 audio_params
##     - additions_extra    : Dictionary，merge 进 additions（在 stringify 前）
##     - raw_req_params     : Dictionary，完全覆盖最终 req_params（绕过所有合并）
##
## 不在白名单里的键 → push_warning 提示，但不阻止请求。
##
## 用法（client 内部）：
##   var req_params := TtsOptions.build_req_params(voice, opts)
##   var payload := { "event": ..., "req_params": req_params, ... }
##   _send_packet(...)

# === 白名单：键名 → 应该被塞到哪个嵌套层 ===

## audio_params 子结构（火山 protobuf 决定 schema）
const _AUDIO_PARAMS_KEYS := [
	"format",                      # "mp3" / "pcm" / "wav" / "ogg_opus"
	"sample_rate",                 # 8000/16000/22050/24000/32000/44100/48000
	"bit_rate",                    # 仅 mp3 生效
	"emotion",                     # "happy"/"sad"/"angry"/...，仅情感音色
	"emotion_scale",               # 1-5
	"speech_rate",                 # -50 to 100
	"loudness_rate",               # -50 to 100（mix 音色不支持）
	"enable_timestamp",            # 仅 TTS 1.0
	"enable_subtitle",             # 仅 TTS 2.0 / ICL 2.0
]

## additions 是 jsonstring（火山要求，不是嵌套对象）
const _ADDITIONS_KEYS := [
	"silence_duration",
	"enable_language_detector",
	"disable_markdown_filter",
	"disable_emoji_filter",
	"explicit_language",
	"explicit_dialect",
	"context_language",
	"context_texts",               # ★ TTS 2.0 上下文 hint，list[String]
	"section_id",                  # ★ TTS 2.0 跨 session 链
	"use_tag_parser",              # ICL 2.0 cot
	"post_process",                # {"pitch": -12..12}
	"cache_config",                # {"text_type":1,"use_cache":true}
	"aigc_metadata",
	"max_length_to_filter_parenthesis",
	"unsupported_char_ratio_thresh",
	"mute_cut_threshold",
	"mute_cut_remain_ms",
	"enable_latex_tn",
	"latex_parser",
	"disable_default_bit_rate",
]

## req_params 顶层（除 audio_params/additions/speaker 外）
const _REQ_PARAMS_TOP_KEYS := [
	"model",                       # "seed-tts-1.1"/"seed-tts-2.0-expressive"/...
	"ssml",                        # 当走 SSML 时，此处放 SSML 字符串，text 留空
]


## 把扁平 opts 转成火山协议的 req_params 结构。
##
## - voice 必填（除非 raw_req_params 完全覆盖）
## - opts 形如 {"emotion": "happy", "speech_rate": 10, "model": "seed-tts-2.0"}
## - 返回 { "speaker": ..., "audio_params": {...}, "additions": "...json...", "model": "..." }
##
## raw_req_params 优先级最高：如有此键，直接返回它（拿来当最终 req_params），调用方负责自己拼对。
static func build_req_params(voice: String, opts: Dictionary) -> Dictionary:
	if opts.has("raw_req_params"):
		return opts["raw_req_params"] as Dictionary

	var audio_params: Dictionary = {}
	var additions: Dictionary = {}
	var top: Dictionary = {}
	var unknown: Array[String] = []

	for key: String in opts.keys():
		if key in _AUDIO_PARAMS_KEYS:
			audio_params[key] = opts[key]
		elif key in _ADDITIONS_KEYS:
			additions[key] = opts[key]
		elif key in _REQ_PARAMS_TOP_KEYS:
			top[key] = opts[key]
		elif key == "audio_params_extra":
			pass  # 稍后合并
		elif key == "additions_extra":
			pass
		elif key == "raw_req_params":
			pass  # 已在前面处理
		else:
			unknown.append(key)

	# 合并 Tier 3 逃生口
	if opts.has("audio_params_extra") and opts["audio_params_extra"] is Dictionary:
		audio_params.merge(opts["audio_params_extra"] as Dictionary, true)
	if opts.has("additions_extra") and opts["additions_extra"] is Dictionary:
		additions.merge(opts["additions_extra"] as Dictionary, true)

	if not unknown.is_empty():
		push_warning("[TTS] 未识别的 opts 键（已忽略）: %s。如需透传，请用 audio_params_extra/additions_extra/raw_req_params" % str(unknown))

	# 组装最终 req_params
	var req: Dictionary = {
		"speaker": voice,
		"audio_params": audio_params,
	}
	if not additions.is_empty():
		req["additions"] = JSON.stringify(additions)
	for key: String in top.keys():
		req[key] = top[key]

	# 当传了 ssml 时，按文档 text 字段也得有（实测留空字符串即可，火山以 ssml 为准）
	if req.has("ssml") and not req.has("text"):
		req["text"] = ""

	return req


## 校验 voice 是否能用 SSML：双向流式整体不支持；saturn_ 前缀音色不支持；icl 2.0 不支持。
## 仅做警告，不阻止请求（用户可能就是想测试服务端会怎么报错）。
static func warn_if_ssml_unsupported(voice: String, endpoint_kind: String) -> void:
	if endpoint_kind == "bidirectional":
		push_warning("[TTS] 双向流式端点不支持 SSML（火山协议限制），SSML 内容会被服务端忽略或拒绝")
		return
	# saturn_ 前缀的 ICL 2.0 复刻音色 / 直接以 saturn_ 结尾的 TTS 2.0 音色
	if voice.begins_with("saturn_") or voice.ends_with("_saturn_bigtts"):
		push_warning("[TTS] 音色 %s 不支持 SSML 标签（豆包 2.0 / ICL 2.0 限制）" % voice)


## 把 audio_params.format 字段读出来；若没设置返回默认 "mp3"（与火山服务端默认一致）。
## 客户端用它决定收到的音频字节怎么处理（PCM 转帧 vs MP3 直存）。
static func get_audio_format(opts: Dictionary) -> String:
	if opts.has("format"):
		return str(opts["format"])
	if opts.has("audio_params_extra") and opts["audio_params_extra"] is Dictionary:
		var extra: Dictionary = opts["audio_params_extra"]
		if extra.has("format"):
			return str(extra["format"])
	return "mp3"


## 把 audio_params.sample_rate 字段读出来；默认 24000。
static func get_sample_rate(opts: Dictionary) -> int:
	if opts.has("sample_rate"):
		return int(opts["sample_rate"])
	if opts.has("audio_params_extra") and opts["audio_params_extra"] is Dictionary:
		var extra: Dictionary = opts["audio_params_extra"]
		if extra.has("sample_rate"):
			return int(extra["sample_rate"])
	return 24000
