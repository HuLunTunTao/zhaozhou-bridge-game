extends Node
## 全局音效管理器。使用对象池避免频繁实例化 AudioStreamPlayer。

const POOL_SIZE := 8
const SAMPLE_RATE := 22050
const SKILL_MELEE_PATHS: Array[String] = [
	"res://assets/audio/sfx/攻击1.mp3",
	"res://assets/audio/sfx/攻击2.mp3",
	"res://assets/audio/sfx/攻击3.mp3",
]
const SKILL_RANGED_PATHS: Array[String] = [
	"res://assets/audio/sfx/拉弓.mp3",
	"res://assets/audio/sfx/放弓.mp3",
]
const SKILL_SUPPORT_PATHS: Array[String] = [
	"res://assets/audio/sfx/metal 01.mp3",
	"res://assets/audio/sfx/metal 02.mp3",
]

var _pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0
var _skill_melee_streams: Array[AudioStream] = []
var _skill_ranged_streams: Array[AudioStream] = []
var _skill_support_streams: Array[AudioStream] = []
var _fallback_skill_attack: AudioStream = null
var _fallback_skill_support: AudioStream = null


func _ready() -> void:
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_pool.append(player)
	_skill_melee_streams = _load_streams(SKILL_MELEE_PATHS)
	_skill_ranged_streams = _load_streams(SKILL_RANGED_PATHS)
	_skill_support_streams = _load_streams(SKILL_SUPPORT_PATHS)
	_fallback_skill_attack = _make_tone(520.0, 0.11, 0.32, 780.0)
	_fallback_skill_support = _make_tone(420.0, 0.18, 0.24, 560.0)


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


func play_skill_cast(skill: SkillData) -> void:
	if skill == null:
		return
	var stream := _pick_skill_stream(skill)
	var pitch_random := 0.03 if skill.skill_type == Enums.SkillType.ATTACK else 0.02
	play_sfx(stream, "SFX", pitch_random)


func _pick_skill_stream(skill: SkillData) -> AudioStream:
	if skill.skill_type == Enums.SkillType.ATTACK:
		if skill.cast_offsets.size() > 4 and not _skill_ranged_streams.is_empty():
			return _skill_ranged_streams[randi() % _skill_ranged_streams.size()]
		if not _skill_melee_streams.is_empty():
			return _skill_melee_streams[randi() % _skill_melee_streams.size()]
		return _fallback_skill_attack
	if not _skill_support_streams.is_empty():
		return _skill_support_streams[randi() % _skill_support_streams.size()]
	return _fallback_skill_support


func _load_streams(paths: Array[String]) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for path in paths:
		if not FileAccess.file_exists(path + ".import"):
			continue
		var stream := load(path) as AudioStream
		if stream != null:
			streams.append(stream)
	return streams


func _make_tone(freq_a: float, duration: float, amplitude: float, freq_b: float = 0.0) -> AudioStreamWAV:
	var sample_count := maxi(1, int(SAMPLE_RATE * duration))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / float(SAMPLE_RATE)
		var envelope := 1.0 - (float(i) / float(sample_count))
		var sample := sin(TAU * freq_a * t)
		if freq_b > 0.0:
			sample = (sample + sin(TAU * freq_b * t)) * 0.5
		var value := int(clampf(sample * amplitude * envelope, -1.0, 1.0) * 32767.0)
		data[i * 2] = value & 0xff
		data[i * 2 + 1] = (value >> 8) & 0xff

	var wav := AudioStreamWAV.new()
	wav.data = data
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	return wav
