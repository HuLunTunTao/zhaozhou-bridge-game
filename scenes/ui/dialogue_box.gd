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

@onready var backdrop: ColorRect = %Backdrop
@onready var bottom_bar: HBoxContainer = %BottomBar
@onready var left_portrait: TextureRect = %LeftPortrait
@onready var left_frame: PanelContainer = %LeftPortrait.get_parent()
@onready var right_portrait: TextureRect = %RightPortrait
@onready var right_frame: PanelContainer = %RightPortrait.get_parent()
@onready var speaker_label: Label = %SpeakerLabel
@onready var text_label: RichTextLabel = %TextLabel
@onready var continue_indicator: Label = %ContinueIndicator

var _lines: Array[DialogueLine] = []
var _current_index: int = -1
var _typing: bool = false
var _finished: bool = false


func _ready() -> void:
	layer = 80
	# 初始隐藏
	backdrop.modulate.a = 0.0
	bottom_bar.modulate.a = 0.0


func start(lines: Array[DialogueLine]) -> void:
	_lines = lines
	_current_index = -1
	_finished = false
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
	left_frame.self_modulate.a = 0.0
	right_frame.self_modulate.a = 0.0
	if line.portrait != null:
		if line.portrait_side == "right":
			right_portrait.texture = line.portrait
			right_frame.self_modulate.a = 1.0
		else:
			left_portrait.texture = line.portrait
			left_frame.self_modulate.a = 1.0

	# 隐藏继续提示
	continue_indicator.visible = false


func _start_typewriter(full_text: String) -> void:
	_typing = true
	text_label.text = full_text
	text_label.visible_ratio = 0.0

	var total_chars := full_text.length()
	if total_chars == 0:
		_typing = false
		continue_indicator.visible = true
		return

	var tween := create_tween()
	tween.tween_property(text_label, "visible_ratio", 1.0, total_chars * CHAR_DELAY)
	await tween.finished

	if _typing:  # 没有被跳过
		_typing = false
		continue_indicator.visible = true


func _skip_typewriter() -> void:
	_typing = false
	text_label.visible_ratio = 1.0
	continue_indicator.visible = true
	# 停止正在播放的 tween
	for child in get_children():
		pass  # Tween 是内部对象，直接设置 visible_ratio=1 即可覆盖


func _finish() -> void:
	_finished = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(backdrop, "modulate:a", 0.0, 0.15)
	tween.tween_property(bottom_bar, "modulate:a", 0.0, 0.15)
	await tween.finished
	dialogue_finished.emit()
	queue_free()
