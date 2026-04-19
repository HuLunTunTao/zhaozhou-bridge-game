extends Node
## 全局设置单例。负责读取、保存和应用游戏设置。
## 数据持久化到 Godot 用户数据目录（user://settings.json）。

const SETTINGS_PATH := "user://settings.json"

signal settings_changed

var music_volume := 0.8    ## 音乐音量，范围 0.0 ~ 1.0
var sfx_volume := 0.8      ## 音效音量，范围 0.0 ~ 1.0
var ui_volume := 0.8       ## UI 音量，范围 0.0 ~ 1.0
var voice_volume := 0.8    ## 语音音量，范围 0.0 ~ 1.0
var ambience_volume := 0.8 ## 环境音量，范围 0.0 ~ 1.0
var debug_mode := false    ## 隐藏调试模式开关。
var muted := false         ## 全局静音开关（不覆盖各通道记忆值）。


func _ready() -> void:
	load_settings()
	apply_settings()


## 将当前设置保存到本地文件
func save_settings() -> void:
	var data := {
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"ui_volume": ui_volume,
		"voice_volume": voice_volume,
		"ambience_volume": ambience_volume,
		"debug_mode": debug_mode,
		"muted": muted,
	}
	var json := JSON.stringify(data)
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
	else:
		push_error("Settings: 无法保存设置到 %s" % SETTINGS_PATH)


## 从本地文件读取设置；若文件不存在则使用默认值
func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return

	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		push_error("Settings: 无法读取设置文件 %s" % SETTINGS_PATH)
		return

	var json := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(json)
	if parsed is Dictionary:
		music_volume = parsed.get("music_volume", music_volume) as float
		sfx_volume = parsed.get("sfx_volume", sfx_volume) as float
		ui_volume = parsed.get("ui_volume", ui_volume) as float
		voice_volume = parsed.get("voice_volume", voice_volume) as float
		ambience_volume = parsed.get("ambience_volume", ambience_volume) as float
		debug_mode = parsed.get("debug_mode", debug_mode) as bool
		muted = parsed.get("muted", muted) as bool
	else:
		push_error("Settings: 设置文件格式错误")


# Kimi Code，2026-04-19

## 应用当前设置到游戏引擎（音量、窗口等）
func apply_settings() -> void:
	if muted:
		for bus in ["Master", "Music", "SFX", "UI", "Voice", "Ambience", "Cutscene"]:
			_set_bus_volume(bus, 0.0)
	else:
		_set_bus_volume("Master", 1.0)
		_set_bus_volume("Music", music_volume)
		_set_bus_volume("SFX", sfx_volume)
		_set_bus_volume("UI", ui_volume)
		_set_bus_volume("Voice", voice_volume)
		_set_bus_volume("Ambience", ambience_volume)
		# Cutscene 总线跟随 Music + Voice 的加权平均，或直接用 Voice
		var cutscene_vol := (music_volume + voice_volume) / 2.0
		_set_bus_volume("Cutscene", cutscene_vol)
	settings_changed.emit()


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))


## 全局静音/取消静音（保留各通道记忆值）
func set_mute(enabled: bool) -> void:
	if muted == enabled:
		return
	muted = enabled
	apply_settings()
	save_settings()
	settings_changed.emit()


## 切换静音状态
func toggle_mute() -> void:
	set_mute(not muted)


func set_debug_mode(enabled: bool) -> void:
	if debug_mode == enabled:
		return
	debug_mode = enabled
	save_settings()
	settings_changed.emit()


## 重置为默认值（仅更新内存状态，不落盘）
func reset_to_defaults() -> void:
	music_volume = 0.8
	sfx_volume = 0.8
	ui_volume = 0.8
	voice_volume = 0.8
	ambience_volume = 0.8
	debug_mode = false
	muted = false
	apply_settings()
