class_name StreamChunker
extends RefCounted
## LLM token 流 → TTS feed chunk 的累积器。
##
## 三种切分策略，**默认 MIXED**（在测试场景对比后确定的最优）：
##   PUNCT   = 0  仅按中文标点切分；累积 ≥ PUNCT_SOFT_LIMIT 字仍无标点强制 flush（避免退化非流式）
##   FIXED   = 1  累积 ≥ FIXED_LEN 字才 flush（节奏稳定，可能在词中切）
##   MIXED   = 2  长度 ≥ FIXED_LEN 或遇到标点 whichever first（短句不卡，长句不堆）
##
## 用法：
##   var chunker := StreamChunker.new()           # 默认 MIXED
##   for c in chunker.push(llm_token_chunk):
##       voice_adapter.feed_stream(c)
##   var tail := chunker.flush_remaining()        # LLM 完成后必须调一次冲掉残余
##   if not tail.is_empty(): voice_adapter.feed_stream(tail)

enum Mode { PUNCT, FIXED, MIXED }

const PUNCT_CHARS := "，。？！；：、,.?!;:\n"
## 定长 / 混合模式的字数阈值。
const FIXED_LEN := 30
## 标点模式的兜底：累积超过此阈值仍未遇标点 → 强制 flush。
const PUNCT_SOFT_LIMIT := 50

var mode: int = Mode.MIXED
var _buf: String = ""


func _init(initial_mode: int = Mode.MIXED) -> void:
	mode = initial_mode


## 喂入一段文本（可能是 LLM 单次 SSE chunk 或几个 token）。
## 返回：本次该 flush 的 chunk 数组（可能为空）。调用方逐项 feed_stream 即可。
func push(s: String) -> Array[String]:
	var out: Array[String] = []
	for i in s.length():
		var c := s.substr(i, 1)
		_buf += c
		if _should_flush():
			out.append(_buf)
			_buf = ""
	return out


## LLM 流结束后调一次：拿出所有未 flush 的残余，清空 buf。
## 必须 feed 这段尾巴再调 finish_stream，否则丢字。
func flush_remaining() -> String:
	var r := _buf
	_buf = ""
	return r


## 当前 buffer 字数（debug 用）。
func pending_length() -> int:
	return _buf.length()


func _should_flush() -> bool:
	if _buf.is_empty():
		return false
	var last := _buf.substr(_buf.length() - 1, 1)
	match mode:
		Mode.PUNCT:
			if _is_punct(last):
				return true
			return _buf.length() >= PUNCT_SOFT_LIMIT
		Mode.FIXED:
			return _buf.length() >= FIXED_LEN
		Mode.MIXED:
			if _buf.length() >= FIXED_LEN:
				return true
			return _is_punct(last)
	return false


func _is_punct(c: String) -> bool:
	return PUNCT_CHARS.contains(c)
