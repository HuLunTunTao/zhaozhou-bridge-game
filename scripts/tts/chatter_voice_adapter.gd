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
	if _player == null:
		_maybe_speak_via_system_tts(text)
		streaming_done.emit()
		return
	if not (unit is Unit) or (unit as Unit).unit_data == null:
		_maybe_speak_via_system_tts(text)
		streaming_done.emit()
		return
	var u := unit as Unit
	var voice_cfg: Dictionary = VoiceMappingScript.get_voice(u.unit_data.unit_id, u.unit_data.camp)
	var voice: String = voice_cfg.get("voice", "")
	if voice.is_empty():
		_maybe_speak_via_system_tts(text)
		streaming_done.emit()
		return
	if ApiConfig.TTS_API_KEY.is_empty():
		_maybe_speak_via_system_tts(text)
		streaming_done.emit()
		return

	var opts := _trigger_to_opts(unit, trigger_kind)
	var ok: bool = await _player.speak(text, voice, opts)
	# 旧协程被 cancel() / 重入打断时，不能再走系统 TTS 兜底——否则旧台词会被当成"失败"再读一遍。
	if my_token != _speak_token:
		return
	if not ok:
		_maybe_speak_via_system_tts(text)
	# _player 的 speak_finished 已经把 streaming_done emit 了


## 主动中断当前正在播放的语音。
## ChatterScheduler 在"用户跳过 + 还有下一条"时调用：声音立即停，等待 streaming_done 的协程被唤醒。
func cancel() -> void:
	_speak_token += 1
	if _player != null:
		_player.stop()
	streaming_done.emit()


func is_streaming() -> bool:
	return _player != null and _player.is_speaking()


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
