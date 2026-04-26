extends Node
## 游戏侧 chatter 语音通道适配器（取代旧 chatter_voice.gd）。
##
## 职责：
##   1. 把 ApiConfig 的 TTS 配置灌到 SDK 的三个 client
##   2. 把 (Unit, trigger_kind) 翻成 (voice_type, opts)
##   3. 系统 TTS 兜底（火山失败时）
##   4. 暴露与旧 chatter_voice.gd 兼容的接口给 ChatterScheduler 调
##
## 与 SDK 的边界：本文件**所有**对 Unit / unit_data / Enums / VoiceMapping 的依赖都在这里。
## SDK 本身（addons/godot_volcengine_tts/）零项目依赖。

const VolcengineStreamingVoicePlayerScript := preload("res://addons/godot_volcengine_tts/streaming_voice_player.gd")
const VoiceMappingScript := preload("res://scripts/tts/voice_mapping.gd")

## 火山失败时是否走 DisplayServer.tts_speak。
var use_system_tts_fallback: bool = true

var _player: VolcengineStreamingVoicePlayer = null
## 每次 speak() 自增；用于在重入 / cancel 时让旧协程认出"我已经被取代了"，
## 不要再触发系统 TTS 兜底。
var _speak_token: int = 0

## ChatterScheduler 监听这个信号判断本次 chatter 是否说完。
signal streaming_done

## 流式通道相关信号（仅 start_stream / feed_stream / finish_stream 路径用）。
signal stream_started
signal stream_failed(reason: String)

## 去括号正则：匹配成对（含不严格成对）的全角 `（）` 与半角 `()`。内层不允许再含括号，靠 _sanitize_for_tts 多轮替换处理嵌套。
var _bracket_re: RegEx = null

## 流式会话状态。start_stream 成功置 true，finish_stream / cancel 清回 false。
var _stream_active: bool = false
## 流式 token：start_stream / cancel 自增，让被打断的协程认出"我已被取代"。
var _stream_token: int = 0


func _build_bracket_re() -> RegEx:
	if _bracket_re == null:
		_bracket_re = RegEx.new()
		_bracket_re.compile("[（(][^（）()]*[)）]")
	return _bracket_re


## 把 LLM / 兜底文本里的 `（动作描写）` `(stage direction)` 这类括号块剥掉，留下"该读出来"的正文。
## 全 LLM 文本经 chatter_voice_adapter.speak 时都会先过这层；显示路径走 dialogue_box，不受影响。
func _sanitize_for_tts(text: String) -> String:
	var re := _build_bracket_re()
	var cleaned := text
	var prev := ""
	# 嵌套括号需要多轮替换（典型 LLM 输出深度 ≤ 2，循环极少超过 2 次）
	while cleaned != prev:
		prev = cleaned
		cleaned = re.sub(cleaned, "", true)
	# 收拾连续空格 / 全角空格 / 边缘空白
	while cleaned.find("  ") >= 0:
		cleaned = cleaned.replace("  ", " ")
	return cleaned.strip_edges()


func _ready() -> void:
	_player = VolcengineStreamingVoicePlayerScript.new()
	_player.audio_bus = &"Voice"
	_player.sample_rate = ApiConfig.TTS_SAMPLE_RATE
	# 必须先 add_child：三个 client 是在 player 的 _ready() 里 new 的，
	# add_child 触发 _ready 后才存在，否则下面 _configure_client 会拿到 null。
	add_child(_player)
	_configure_client(_player.bidi_client)
	_configure_client(_player.uni_client)
	_configure_client(_player.http_client)
	_player.speak_finished.connect(streaming_done.emit)


func _configure_client(client: Node) -> void:
	client.api_key = ApiConfig.TTS_API_KEY
	client.resource_id = ApiConfig.TTS_RESOURCE_ID
	client.user_uid = ApiConfig.TTS_USER_UID
	if "default_model" in client:
		client.default_model = ApiConfig.TTS_MODEL
	# base_url / path 用 SDK 默认值即可（与火山官方一致）。
	# 如果未来 ApiConfig 想覆盖 base_url，在此读对应字段并写入。


## 串行播一句。trigger_kind 决定 emotion / speech_rate 等"上下文适配"。
## 调用方先不 await，开对话框时再 await streaming_done 等收尾。
func speak(unit: Node, text: String, trigger_kind: String = "") -> void:
	_speak_token += 1
	var my_token := _speak_token
	# 先剥离动作描写括号；如果全是括号动作（剥完为空）→ 跳过 TTS，让显示路径自己计时收尾。
	var clean_text := _sanitize_for_tts(text)
	if clean_text.is_empty():
		streaming_done.emit()
		return
	if _player == null:
		_maybe_speak_via_system_tts(clean_text)
		streaming_done.emit()
		return
	if not (unit is Unit) or (unit as Unit).unit_data == null:
		_maybe_speak_via_system_tts(clean_text)
		streaming_done.emit()
		return
	var u := unit as Unit
	var voice_cfg: Dictionary = VoiceMappingScript.get_voice(u.unit_data.unit_id, u.unit_data.camp)
	var voice: String = voice_cfg.get("voice", "")
	if voice.is_empty():
		_maybe_speak_via_system_tts(clean_text)
		streaming_done.emit()
		return
	if ApiConfig.TTS_API_KEY.is_empty():
		_maybe_speak_via_system_tts(clean_text)
		streaming_done.emit()
		return

	var opts := _trigger_to_opts(unit, trigger_kind)
	var ok: bool = await _player.speak(clean_text, voice, opts)
	# 旧协程被 cancel() / 重入打断时，不能再走系统 TTS 兜底——否则旧台词会被当成"失败"再读一遍。
	if my_token != _speak_token:
		return
	if not ok:
		_maybe_speak_via_system_tts(clean_text)
	# _player 的 speak_finished 已经把 streaming_done emit 了


## 主动中断当前正在播放的语音。
## ChatterScheduler 在"用户跳过 + 还有下一条"时调用：声音立即停，等待 streaming_done 的协程被唤醒。
func cancel() -> void:
	_speak_token += 1
	_stream_token += 1
	_stream_active = false
	if _player != null:
		_player.stop()
	streaming_done.emit()


func is_streaming() -> bool:
	return _player != null and _player.is_speaking()


# ─────────────────────────────────────────────
# 流式通道（LLM token → TTS bidi 直连）
# ─────────────────────────────────────────────

## 启动一段双向流式会话。voice 由 unit 经 VoiceMapping 解析。
## 成功后调用方反复调 feed_stream(chunk) 喂 LLM token，结束时调 finish_stream()。
## 流式失败**不**走系统 TTS 兜底（OS TTS 不支持流式喂入）；改 emit stream_failed。
func start_stream(unit: Node, trigger_kind: String = "") -> bool:
	if not (unit is Unit) or (unit as Unit).unit_data == null:
		return false
	var u := unit as Unit
	var voice_cfg: Dictionary = VoiceMappingScript.get_voice(u.unit_data.unit_id, u.unit_data.camp)
	var voice: String = voice_cfg.get("voice", "")
	if voice.is_empty():
		return false
	var opts := _trigger_to_opts(unit, trigger_kind)
	return await start_stream_with_voice(voice, opts)


## 直接用 voice id 启动流式（绕过 Unit 查询）。测试场景用这个。
func start_stream_with_voice(voice: String, opts: Dictionary = {}) -> bool:
	# 互斥：旧流式或一次性 speak 还在跑就先停
	if _stream_active or is_streaming():
		if _player != null:
			_player.stop()  # 同步 emit speak_finished → streaming_done
		_stream_active = false
	_stream_token += 1
	_speak_token += 1            # 同时让 speak() 协程退出
	var my_token := _stream_token
	if _player == null or voice.is_empty():
		return false
	if ApiConfig.TTS_API_KEY.is_empty():
		return false
	var ok: bool = await _player.start_streaming(voice, opts)
	# 启动期间被 cancel / 重入：丢弃本次启动结果
	if my_token != _stream_token:
		return false
	if not ok:
		stream_failed.emit("start_streaming 失败")
		return false
	_stream_active = true
	stream_started.emit()
	return true


## 喂一段文本到当前流式会话。返回是否成功（false 时多半是会话已 cancel / WS 断了）。
func feed_stream(text_chunk: String) -> bool:
	if not _stream_active or _player == null:
		return false
	var clean := _sanitize_for_tts(text_chunk)
	if clean.is_empty():
		return true                # 空字符串当作 noop，不视作失败
	return _player.feed_text(clean)


## 通知服务端文本喂完。剩余音频由 SDK 的 session_finished 信号自然收尾，
## 最终触发 _player.speak_finished → streaming_done。
func finish_stream() -> void:
	if not _stream_active or _player == null:
		return
	_stream_active = false
	_player.finish_streaming()


func is_stream_active() -> bool:
	return _stream_active


## 把 (unit, trigger_kind) 映射到火山的 emotion / speech_rate / loudness_rate。
## 这层逻辑是**游戏特化**的，不属于 SDK。
func _trigger_to_opts(unit: Node, trigger_kind: String) -> Dictionary:
	var opts: Dictionary = {}
	match trigger_kind:
		"reaction_to_attack":
			# 受击：急促 + 情绪重。HP 越低越紧张
			var hp_pct: int = _hp_percent(unit)
			opts["speech_rate"] = 20
			opts["emotion"] = "scared" if hp_pct < 30 else "angry"
			opts["emotion_scale"] = 4
		"hero_observation":
			# 主角观察战况：沉稳
			opts["speech_rate"] = -5
			opts["emotion"] = "calm"
		"adjacent_chat", "adjacent_reply":
			# 闲聊：默认（无修饰）
			pass
		_:
			pass
	return opts


func _hp_percent(unit: Node) -> int:
	if not (unit is Unit):
		return 100
	var stats: CombatStats = (unit as Unit).combat_stats
	if stats == null or stats.max_hp <= 0:
		return 100
	return int(round(100.0 * float(stats.current_hp) / float(stats.max_hp)))


## 系统 TTS 兜底：火山合成失败时由 OS 把文本读出来。
func _maybe_speak_via_system_tts(text: String) -> void:
	if not use_system_tts_fallback or text.is_empty():
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	var voices: Array = DisplayServer.tts_get_voices_for_language("zh")
	if voices.is_empty():
		return
	var voice_id: String = voices[0]
	DisplayServer.tts_speak(text, voice_id, 50, 1.0, 1.0, 0, true)
