extends Node
## 闲聊语音播放器：把"火山流式 TTS + AudioStreamGenerator + 系统 TTS 兜底"
## 这一摞细节从 ChatterScheduler 里拎出来。
##
## 用法：
##   var voice := preload("res://scripts/tts/chatter_voice.gd").new()
##   add_child(voice)              # 内部会建 AudioStreamPlayer 子节点
##   await voice.speak(unit, text) # 走完整流程：火山失败时回落系统 TTS
##
## 设计：
##   - 单实例 _voice_player（bus=Voice），与 dialogue_box 的 _audio_player 解耦
##   - 第一个 await 后让出控制权，调用方可与 dialogue_box 并行
##   - 出错时回落系统 TTS（如果 use_system_tts_fallback=true）

const VoiceMappingScript := preload("res://scripts/tts/voice_mapping.gd")
const VolcengineTTSClientScript := preload("res://scripts/tts/volcengine_tts_client.gd")

## 流式 TTS 不可用时的兜底：true → DisplayServer.tts_speak（系统 TTS）；false → 静默
var use_system_tts_fallback: bool = true

const _AUDIO_SAMPLE_RATE := 24000
const _AUDIO_BUFFER_LENGTH := 0.5

var _voice_player: AudioStreamPlayer = null
var _tts: Node = null
var _streaming: bool = false

## speak() 内部走完一次（不论成功还是回落）后 emit。
## 调用方 fire-and-forget speak() 后，可在外部 await 此信号收尾。
signal streaming_done


func _ready() -> void:
	_tts = VolcengineTTSClientScript.new()
	add_child(_tts)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = &"Voice"
	add_child(_voice_player)


## 串行播放 unit 说出 text 这一句。返回时音频已经全部接收完毕（或失败回落完成）。
## 调用方可以在调用此方法之前不 await，先去开对话框，让两者并行；之后 await 等收尾即可。
## 不论成功 / 回落系统 TTS / 静默，最后都会 emit streaming_done。
func speak(unit: Node, text: String) -> void:
	if _tts == null or _voice_player == null:
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

	# 切到 AudioStreamGenerator 流并 play 拿 playback
	_voice_player.stop()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = float(_AUDIO_SAMPLE_RATE)
	generator.buffer_length = _AUDIO_BUFFER_LENGTH
	_voice_player.stream = generator
	_voice_player.play()
	var pb := _voice_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		_voice_player.stop()
		_maybe_speak_via_system_tts(text)
		streaming_done.emit()
		return

	_streaming = true
	var ok: bool = await _tts.synthesize_streaming(text, voice, pb)
	if not ok:
		_voice_player.stop()
		_maybe_speak_via_system_tts(text)
	_streaming = false
	streaming_done.emit()


## 当前是否还在收 TTS chunk / 推 buffer 中。
func is_streaming() -> bool:
	return _streaming


## 系统 TTS 兜底：火山合成失败时由 OS 把文本读出来。
## 不返回 AudioStream（系统 TTS 走另一条声道）。
func _maybe_speak_via_system_tts(text: String) -> void:
	if not use_system_tts_fallback or text.is_empty():
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	var voices: Array = DisplayServer.tts_get_voices_for_language("zh")
	if voices.is_empty():
		# 没有中文系统语音，索性不发声（避免英文音念中文出洋相）
		return
	var voice_id: String = voices[0]
	# interrupt=true 防止上一次系统朗读把这句压住
	DisplayServer.tts_speak(text, voice_id, 50, 1.0, 1.0, 0, true)
