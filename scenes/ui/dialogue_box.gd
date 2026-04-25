class_name DialogueBox
extends CanvasLayer
## RPG 风格对话框。显示在屏幕底部，支持左/右头像、打字机效果。
## 用法：
##   var box = DialogueBoxScene.instantiate()
##   add_child(box)
##   box.start(lines)              # lines: Array[DialogueLine]
##   await box.dialogue_finished   # 全部对话结束后发出

signal dialogue_finished

const CHAR_DELAY := 0.03  # 每个字符的打字机间隔（秒）
const AUTO_DISMISS_DELAY_DEFAULT := 2.5  # auto_dismiss 模式下的默认停留秒数

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
var _auto_dismiss: bool = false
var _dismiss_delay: float = AUTO_DISMISS_DELAY_DEFAULT
## 每次 _advance / _skip 会自增，用于取消上一轮的 auto-dismiss 计时协程。
var _dismiss_token: int = 0
## 当前行音频播放器（仅在有 line.audio_stream 时启用）。auto_dismiss 时长会被拉到不短于音频时长。
var _audio_player: AudioStreamPlayer = null
var _current_audio_length: float = 0.0


func _ready() -> void:
	layer = 80
	# 初始隐藏
	backdrop.modulate.a = 0.0
	bottom_bar.modulate.a = 0.0
	# 配音播放器（走 Voice 母线，音量沿用其控制）
	_audio_player = AudioStreamPlayer.new()
	_audio_player.bus = &"Voice"
	add_child(_audio_player)


func start(lines: Array[DialogueLine], auto_dismiss: bool = false, dismiss_delay: float = AUTO_DISMISS_DELAY_DEFAULT) -> void:
	_lines = lines
	_current_index = -1
	_finished = false
	_auto_dismiss = auto_dismiss
	_dismiss_delay = dismiss_delay
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
			_advance()


func _advance() -> void:
	_dismiss_token += 1  # 使任何仍在等 auto_dismiss 延迟的协程失效
	_current_index += 1
	if _current_index >= _lines.size():
		_finish()
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


## 若开启 auto_dismiss，延迟后自动 _advance；
## 实际延迟取 max(_dismiss_delay, 当前行音频时长 + 0.3 秒)，避免话还没说完就关。
## 玩家在此期间手动推进则 token 自增使本协程静默退出。
func _schedule_auto_dismiss() -> void:
	if not _auto_dismiss:
		return
	var delay := _dismiss_delay
	if _current_audio_length > 0.0:
		delay = maxf(delay, _current_audio_length + 0.3)
	var token := _dismiss_token
	await get_tree().create_timer(delay).timeout
	if _finished or token != _dismiss_token:
		return
	_advance()


func _finish() -> void:
	_finished = true
	if _audio_player:
		_audio_player.stop()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(backdrop, "modulate:a", 0.0, 0.15)
	tween.tween_property(bottom_bar, "modulate:a", 0.0, 0.15)
	await tween.finished
	dialogue_finished.emit()
	queue_free()
