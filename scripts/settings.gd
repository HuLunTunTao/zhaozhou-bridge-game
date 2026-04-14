extends Node
## 全局设置单例。负责读取、保存和应用游戏设置。
## 数据持久化到 Godot 用户数据目录（user://settings.json）。

const SETTINGS_PATH := "user://settings.json"

var music_volume := 0.8 ## 音乐音量，范围 0.0 ~ 1.0
var sfx_volume := 0.8   ## 音效音量，范围 0.0 ~ 1.0


func _ready() -> void:
	load_settings()
	_apply_settings()


## 将当前设置保存到本地文件
func save_settings() -> void:
	var data := {
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
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
	else:
		push_error("Settings: 设置文件格式错误")


## 应用当前设置到游戏引擎（音量、窗口等）
func _apply_settings() -> void:
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))
