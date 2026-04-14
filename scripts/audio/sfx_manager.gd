extends Node
## 全局音效管理器。使用对象池避免频繁实例化 AudioStreamPlayer。

const POOL_SIZE := 8

var _pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0


func _ready() -> void:
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_pool.append(player)


## 播放音效。支持指定总线、随机音高变化。
func play_sfx(stream: AudioStream, bus: String = "SFX", pitch_random: float = 0.0) -> void:
	if stream == null:
		return

	var player := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE

	player.bus = bus
	player.stream = stream
	if pitch_random > 0.0:
		player.pitch_scale = 1.0 + randf_range(-pitch_random, pitch_random)
	else:
		player.pitch_scale = 1.0
	player.play()


## 便捷方法：播放指定总线的音效
func play_ui(stream: AudioStream) -> void:
	play_sfx(stream, "UI")

func play_voice(stream: AudioStream) -> void:
	play_sfx(stream, "Voice")

func play_ambience(stream: AudioStream) -> void:
	play_sfx(stream, "Ambience")
