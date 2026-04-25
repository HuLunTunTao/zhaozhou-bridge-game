class_name DialogueBox
extends CanvasLayer
## RPG 风格对话框。显示在屏幕底部，支持左/右头像、打字机效果。
## 用法：
##   var box = DialogueBoxScene.instantiate()
##   add_child(box)
##   box.start(lines)              # lines: Array[DialogueLine]
##   await box.dialogue_finished   # 全部对话结束后发出

## 全部对话结束后发出。
## 想知道是否被玩家手动跳过：emit 之前已把结果写到 `was_skipped` 属性，
## 调用方在 `await dialogue_finished` 之后读取（队列释放是 deferred，下一帧才生效）。
signal dialogue_finished

## 上一段（最后一行）对话的关闭原因：true=玩家按键/点击，false=auto_dismiss 计时器。
## 在 `dialogue_finished` 之前赋值，调用方 await 后可立即读。
var was_skipped: bool = false

const CHAR_DELAY := 0.03  # 每个字符的打字机间隔（秒）
const AUTO_DISMISS_DELAY_DEFAULT := 2.0  # auto_dismiss 模式下的"对话框最少展示秒数"（自开启起）
const VOICE_AFTERMATH_DELAY := 0.5  # auto_dismiss 模式下，语音结束后再停留多久才关闭

@onready var backdrop: ColorRect = %Backdrop
@onready var bottom_bar: HBoxContainer = %BottomBar
@onready var left_portrait: TextureRect = %LeftPortrait
@onready var left_portrait_bg: TextureRect = %LeftPortraitBg
@onready var left_frame: PanelContainer = %LeftPortraitFrame
@onready var right_portrait: TextureRect = %RightPortrait
@onready var right_portrait_bg: TextureRect = %RightPortraitBg
@onready var right_frame: PanelContainer = %RightPortraitFrame
@onready var speaker_label: Label = %SpeakerLabel
@onready var text_label: RichTextLabel = %TextLabel
@onready var continue_indicator: Label = %ContinueIndicator

var _lines: Array[DialogueLine] = []
var _current_index: int = -1
var _typing: bool = false
var _finished: bool = false
## auto_dismiss 模式：打字机结束后等 _dismiss_delay 秒自动推进 / 关闭，无需玩家点击。
## 用于单位闲聊（chatter）等不该打断游戏节奏的场景。
##
## auto_dismiss 关闭时机 = max(文字打完时刻, 语音结束 + 0.5s, 对话框开启 + _dismiss_delay)。
## 也就是说：
##   - 文字必须打完
##   - 如果 _voice_handle 还在 streaming，必须等它结束并再多 0.5s
##   - 整个对话框至少展示 _dismiss_delay 秒（默认 2s）
var _auto_dismiss: bool = false
var _dismiss_delay: float = AUTO_DISMISS_DELAY_DEFAULT
## 每次 _advance / _skip 会自增，用于取消上一轮的 auto-dismiss 计时协程。
var _dismiss_token: int = 0
## 当前行音频播放器（仅在有 line.audio_stream 时启用）。auto_dismiss 时长会被拉到不短于音频时长。
var _audio_player: AudioStreamPlayer = null
var _current_audio_length: float = 0.0
## 外部 TTS 语音句柄（鸭子接口：is_streaming() -> bool, signal streaming_done）。
## auto_dismiss 在它结束 + 0.5s 之前不会关闭。chatter 场景由 ChatterScheduler 注入。
var _voice_handle: Node = null
## start() 调用时刻，用作 "open + N 秒" 类下限的参考点。
var _open_time: float = 0.0


func _ready() -> void:
	layer = 80
	# 初始隐藏
	backdrop.modulate.a = 0.0
	bottom_bar.modulate.a = 0.0
	# 配音播放器（走 Voice 母线，音量沿用其控制）
	_audio_player = AudioStreamPlayer.new()
	_audio_player.bus = &"Voice"
	add_child(_audio_player)


func start(lines: Array[DialogueLine], auto_dismiss: bool = false, dismiss_delay: float = AUTO_DISMISS_DELAY_DEFAULT, voice_handle: Node = null) -> void:
	_lines = lines
	_current_index = -1
	_finished = false
	_auto_dismiss = auto_dismiss
	_dismiss_delay = dismiss_delay
	_voice_handle = voice_handle
	_open_time = Time.get_ticks_msec() / 1000.0
	# 先准备好第一行内容，再淡入，避免头像闪烁
	if _lines.size() > 0:
		_apply_line(_lines[0])
	# 淡入
	var tween := create_tween().set_parallel(true)
	tween.tween_property(backdrop, "modulate:a", 1.0, 0.15)
	tween.tween_property(bottom_bar, "modulate:a", 1.0, 0.15)
	await tween.finished
	_advance()


func _input(event: InputEvent) -> void:
	if _finished:
		return

	var accept := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			accept = true

	if accept:
		get_viewport().set_input_as_handled()
		if _typing:
			# 跳过打字机，直接显示全文
			_skip_typewriter()
		else:
			_advance(true)


func _advance(from_user: bool = false) -> void:
	_dismiss_token += 1  # 使任何仍在等 auto_dismiss 延迟的协程失效
	_current_index += 1
	if _current_index >= _lines.size():
		_finish(from_user)
		return

	var line := _lines[_current_index]
	_apply_line(line)
	_start_typewriter(line.text)


func _apply_line(line: DialogueLine) -> void:
	# 说话者
	if line.speaker == "":
		speaker_label.visible = false
	else:
		speaker_label.visible = true
		speaker_label.text = line.speaker

	# 头像：frame 始终占位，通过 self_modulate.a 控制显隐
	left_portrait.texture = null
	right_portrait.texture = null
	left_portrait_bg.texture = null
	right_portrait_bg.texture = null
	left_frame.self_modulate.a = 0.0
	right_frame.self_modulate.a = 0.0
	if line.portrait != null:
		if line.portrait_side == "right":
			right_portrait.texture = line.portrait
			right_portrait_bg.texture = line.portrait_bg
			right_frame.self_modulate.a = 1.0
		else:
			left_portrait.texture = line.portrait
			left_portrait_bg.texture = line.portrait_bg
			left_frame.self_modulate.a = 1.0

	# 配音：先停旧的，再播新的；记录时长供 auto_dismiss 用
	_current_audio_length = 0.0
	if _audio_player:
		_audio_player.stop()
		_audio_player.stream = null
		if line.audio_stream != null:
			_audio_player.stream = line.audio_stream
			if line.audio_stream.has_method("get_length"):
				_current_audio_length = line.audio_stream.get_length()
			_audio_player.play()

	# 隐藏继续提示
	continue_indicator.visible = false


func _start_typewriter(full_text: String) -> void:
	_typing = true
	text_label.text = full_text
	text_label.visible_ratio = 0.0

	var total_chars := full_text.length()
	if total_chars == 0:
		_typing = false
		continue_indicator.visible = not _auto_dismiss
		_schedule_auto_dismiss()
		return

	var tween := create_tween()
	tween.tween_property(text_label, "visible_ratio", 1.0, total_chars * CHAR_DELAY)
	await tween.finished

	if _typing:  # 没有被跳过
		_typing = false
		continue_indicator.visible = not _auto_dismiss
		_schedule_auto_dismiss()


func _skip_typewriter() -> void:
	_typing = false
	text_label.visible_ratio = 1.0
	continue_indicator.visible = not _auto_dismiss
	# 跳过后同样触发 auto_dismiss 倒计时
	_schedule_auto_dismiss()


## auto_dismiss 模式下，等满三个条件再关：
##   1. 文字打完（本函数已是文字打完后才被调用，天然满足）
##   2. 语音结束 + VOICE_AFTERMATH_DELAY（仅当 _voice_handle 在 streaming 时生效）
##   3. 对话框开启时间 + _dismiss_delay
## 玩家在此期间手动推进则 _dismiss_token 自增，本协程静默退出。
func _schedule_auto_dismiss() -> void:
	if not _auto_dismiss:
		return
	var token := _dismiss_token

	# Phase 1: 等外部 TTS 语音播完（轮询避免 signal-race；is_streaming 同步可靠）
	var voice_was_streaming := false
	while _voice_handle != null and is_instance_valid(_voice_handle) \
			and _voice_handle.has_method("is_streaming") and _voice_handle.is_streaming():
		voice_was_streaming = true
		if not is_inside_tree():
			return
		await get_tree().process_frame
		if _finished or token != _dismiss_token:
			return

	# Phase 2: 计算 close 时刻
	var now := Time.get_ticks_msec() / 1000.0
	var close_at := _open_time + _dismiss_delay
	if voice_was_streaming:
		close_at = maxf(close_at, now + VOICE_AFTERMATH_DELAY)
	# 兼容内置 audio_stream（非 chatter 路径）：若 line 自带音频且尚未播完，再额外补 0.3s
	if _current_audio_length > 0.0:
		close_at = maxf(close_at, _open_time + _current_audio_length + 0.3)

	if close_at > now:
		await get_tree().create_timer(close_at - now).timeout
	if _finished or token != _dismiss_token:
		return
	_advance()


func _finish(from_user: bool = false) -> void:
	was_skipped = from_user
	_finished = true
	if _audio_player:
		_audio_player.stop()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(backdrop, "modulate:a", 0.0, 0.15)
	tween.tween_property(bottom_bar, "modulate:a", 0.0, 0.15)
	await tween.finished
	dialogue_finished.emit()
	queue_free()
