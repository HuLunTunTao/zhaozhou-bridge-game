extends Node
## 全局背景音乐管理器。支持交叉淡入淡出，场景切换不中断。

const FADE_TIME := 0.8

@onready var _player_a: AudioStreamPlayer = AudioStreamPlayer.new()
@onready var _player_b: AudioStreamPlayer = AudioStreamPlayer.new()

var _current: AudioStreamPlayer
var _next: AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	_player_a.bus = "Music"
	_player_b.bus = "Music"
	add_child(_player_a)
	add_child(_player_b)
	_current = _player_a
	_next = _player_b


## 播放新的 BGM，可选交叉淡入淡出
func play(stream: AudioStream, with_crossfade: bool = true) -> void:
	if stream == null:
		return

	#AI辅助生成， Kimi Code，2026-04-19

	var same_stream := _current.stream == stream
	if not same_stream and _current.stream != null and stream != null:
		same_stream = _current.stream.resource_path == stream.resource_path
	if same_stream and _current.playing:
		return

	if with_crossfade:
		_crossfade_to(stream)
	else:
		_current.stream = stream
		_set_stream_loop(stream) # AI辅助编程，Kimi Code，2026-04-21
		_current.play()


## 停止当前 BGM，可选淡出
func stop(fade_out: bool = true) -> void:
	if not _current.playing:
		return
	if fade_out:
		var tween := create_tween()
		tween.tween_property(_current, "volume_db", -80.0, FADE_TIME)
		tween.finished.connect(func():
			if is_instance_valid(self) and is_inside_tree():
				_current.stop()
		, CONNECT_ONE_SHOT)
	else:
		_current.stop()


## 返回当前是否正在播放 BGM
func is_playing() -> bool:
	return _current.playing


## 返回当前播放的 AudioStream（可能为 null）
func get_current_stream() -> AudioStream:
	return _current.stream


func _crossfade_to(stream: AudioStream) -> void:
	# 准备 next 播放器
	_next.stream = stream
	_set_stream_loop(stream)
	_next.volume_db = -80.0
	_next.play()

	# 同时淡出 current、淡入 next
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel()
	_tween.tween_property(_current, "volume_db", -80.0, FADE_TIME)
	_tween.tween_property(_next, "volume_db", 0.0, FADE_TIME)
	_tween.finished.connect(_swap_players, CONNECT_ONE_SHOT)


func _set_stream_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


func _swap_players() -> void:
	if not is_instance_valid(self):
		return
	_current.stop()
	var temp := _current
	_current = _next
	_next = temp
