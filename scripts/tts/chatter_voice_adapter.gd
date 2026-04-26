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
## fallback 路径专用的 AudioStreamPlayer（pre-baked MP3 或 OS TTS 之前的占位）。
## 复用同一节点避免反复 add_child / queue_free。
var _fallback_player: AudioStreamPlayer = null

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
	# 解析 unit_id（用于 fallback 查表）
	var unit_id: String = ""
	if unit is Unit and (unit as Unit).unit_data != null:
		unit_id = String((unit as Unit).unit_data.unit_id)
	if _player == null:
		await _fallback_voice(unit_id, clean_text)
		streaming_done.emit()
		return
	if unit_id.is_empty():
		await _fallback_voice(unit_id, clean_text)
		streaming_done.emit()
		return
	var u := unit as Unit
	var voice_cfg: Dictionary = VoiceMappingScript.get_voice(u.unit_data.unit_id, u.unit_data.camp)
	var voice: String = voice_cfg.get("voice", "")
	if voice.is_empty():
		await _fallback_voice(unit_id, clean_text)
		streaming_done.emit()
		return
	if ApiConfig.TTS_API_KEY.is_empty():
		await _fallback_voice(unit_id, clean_text)
		streaming_done.emit()
		return

	var opts := _trigger_to_opts(unit, trigger_kind)
	var ok: bool = await _player.speak(clean_text, voice, opts)
	# 旧协程被 cancel() / 重入打断时，不能再走系统 TTS 兜底——否则旧台词会被当成"失败"再读一遍。
	if my_token != _speak_token:
		return
	if not ok:
		await _fallback_voice(unit_id, clean_text)
	# _player 的 speak_finished 已经把 streaming_done emit 了


## 主动中断当前正在播放的语音。
## ChatterScheduler 在"用户跳过 + 还有下一条"时调用：声音立即停，等待 streaming_done 的协程被唤醒。
func cancel() -> void:
	_speak_token += 1
	_stream_token += 1
	_stream_active = false
	if _player != null:
		_player.stop()
	# 同步停 fallback player（如果正在播 pre-baked mp3）
	if _fallback_player != null and _fallback_player.playing:
		_fallback_player.stop()
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


# ─────────────────────────────────────────────
# 高层封装：LLM 流式 → 混合切分 → TTS 流式 一体化
# ─────────────────────────────────────────────

const StreamChunkerScript := preload("res://scripts/llm/stream_chunker.gd")

## 一次完成 LLM 流式 → 切分 → TTS 流式播放，并把每个 LLM token chunk 通过 on_token 回调转发给 caller（用于同步刷字幕）。
##
## - llm_client: LLMClient 实例（由 caller 持有/管理生命周期，本函数只调它的 stream_chat_completion）
## - messages: OpenAI Chat Completions 风格 messages
## - llm_opts: temperature / max_tokens 等（透传到 stream_chat_completion）
## - chunk_mode: StreamChunker.Mode.MIXED（默认）/ PUNCT / FIXED
## - on_token: 可选回调 func(text: String)，每次收到 LLM chunk 时调一次（用于刷 dialogue_box 字幕）
##
## 返回：{"ok": bool, "full_text": String, "error": String}
##
## 行为：
##   - LLM 启动失败 → ok=false，TTS 不开（如果已开会被 cancel）
##   - TTS 启动失败 → ok=true（继续吐文字），stream_failed 信号已 emit；尾段不再 feed
##   - LLM 中途失败 → ok=false 但 full_text 含部分内容；TTS 已 feed 的部分会自然播完
##
## 不调 cancel()——caller 想中途停就自己调 voice_adapter.cancel() + llm_client.abort_stream()。
func speak_streaming(
		unit: Node,
		llm_client: LLMClient,
		messages: Array,
		llm_opts: Dictionary = {},
		chunk_mode: int = StreamChunkerScript.Mode.MIXED,
		trigger_kind: String = "",
		on_token: Callable = Callable(),
	) -> Dictionary:
	if llm_client == null:
		return {"ok": false, "full_text": "", "error": "llm_client 为空"}
	if messages.is_empty():
		return {"ok": false, "full_text": "", "error": "messages 为空"}

	var chunker = StreamChunkerScript.new(chunk_mode)
	var has_tts: bool = await start_stream(unit, trigger_kind)

	var done := [false]
	var ok_state := [true]
	var err_state := [""]
	var full_text := [""]

	var on_chunk := func(text: String) -> void:
		full_text[0] += text
		if on_token.is_valid():
			on_token.call(text)
		if has_tts and _stream_active:
			for c in chunker.push(text):
				feed_stream(c)

	var on_finished := func(_full_unused: String, ok: bool, err: String) -> void:
		ok_state[0] = ok
		err_state[0] = err
		# 残余冲掉
		var tail: String = chunker.flush_remaining()
		if not tail.is_empty() and has_tts and _stream_active:
			feed_stream(tail)
		if has_tts and _stream_active:
			finish_stream()
		done[0] = true

	llm_client.stream_chunk_received.connect(on_chunk)
	llm_client.stream_finished.connect(on_finished, CONNECT_ONE_SHOT)
	var started: bool = llm_client.stream_chat_completion(messages, llm_opts)
	if not started:
		if llm_client.stream_chunk_received.is_connected(on_chunk):
			llm_client.stream_chunk_received.disconnect(on_chunk)
		if llm_client.stream_finished.is_connected(on_finished):
			llm_client.stream_finished.disconnect(on_finished)
		if has_tts:
			cancel()
		return {"ok": false, "full_text": "", "error": "stream_chat_completion 启动失败"}

	# 等 stream_finished 回调把 done 翻成 true。get_tree() 拿不到时退化成单帧 await。
	while not done[0]:
		var tree := get_tree()
		if tree == null:
			break
		await tree.process_frame
	if llm_client.stream_chunk_received.is_connected(on_chunk):
		llm_client.stream_chunk_received.disconnect(on_chunk)

	return {"ok": ok_state[0], "full_text": full_text[0], "error": err_state[0]}


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


## 失败兜底链入口：火山失败 / api_key 空 / voice 空 / unit 无 unit_data 等情况都进这里。
## 优先级：pre-baked MP3 (TtsFallbackIndex) → OS TTS (DisplayServer.tts_speak) → 静默
## 文本 text 应已经过 _sanitize_for_tts；unit_id 为空时跳过查表直接走 OS TTS。
func _fallback_voice(unit_id: String, text: String) -> void:
	if unit_id != "":
		var pre: AudioStream = TtsFallbackIndex.get_fallback_audio(unit_id, text)
		if pre != null:
			if _fallback_player == null:
				_fallback_player = AudioStreamPlayer.new()
				_fallback_player.bus = &"Voice"
				add_child(_fallback_player)
			_fallback_player.stream = pre
			_fallback_player.play()
			await _fallback_player.finished
			return
	_maybe_speak_via_system_tts(text)


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
