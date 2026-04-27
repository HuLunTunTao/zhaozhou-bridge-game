extends Node
## 全局设置单例。负责读取、保存和应用游戏设置。
## 数据持久化到 Godot 用户数据目录（user://settings.json）。

const SETTINGS_PATH := "user://settings.json"
const DEFAULT_DIFFICULTY := "normal"

signal settings_changed
signal difficulty_changed(new_id: String)

var music_volume := 0.8    ## 音乐音量，范围 0.0 ~ 1.0
var sfx_volume := 0.8      ## 音效音量，范围 0.0 ~ 1.0
var ui_volume := 0.8       ## UI 音量，范围 0.0 ~ 1.0
var voice_volume := 0.8    ## 语音音量，范围 0.0 ~ 1.0
var ambience_volume := 0.8 ## 环境音量，范围 0.0 ~ 1.0
var debug_mode := false    ## 隐藏调试模式开关。
var muted := false         ## 全局静音开关（不覆盖各通道记忆值）。
var window_width := 1920   ## 窗口宽度（像素）。仅在非全屏模式下使用。
var window_height := 1080  ## 窗口高度（像素）。仅在非全屏模式下使用。
var fullscreen := false    ## 是否使用独占全屏（fullscreen 模式）。
var difficulty := DEFAULT_DIFFICULTY ## 难度档位 ID，配置见 GameState.DIFFICULTY_CONFIG。

# AI辅助编程，Kimi Code，2026-04-20

const RESOLUTION_PRESETS: Array = [
	Vector2i(960, 540),
	Vector2i(1920, 1080),
	Vector2i(2880, 1620),
	Vector2i(3840, 2160),
]


func _ready() -> void:
	load_settings()
	call_deferred("apply_settings")


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
		"window_width": window_width,
		"window_height": window_height,
		"fullscreen": fullscreen,
		"difficulty": difficulty,
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
		window_width = int(parsed.get("window_width", window_width))
		window_height = int(parsed.get("window_height", window_height))
		fullscreen = parsed.get("fullscreen", fullscreen) as bool
		difficulty = parsed.get("difficulty", difficulty) as String
		if not GameState.DIFFICULTY_CONFIG.has(difficulty):
			difficulty = DEFAULT_DIFFICULTY
	else:
		push_error("Settings: 设置文件格式错误")


#AI辅助生成， Kimi Code，2026-04-19

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
	_apply_window_settings()
	settings_changed.emit()

# AI辅助编程，Kimi Code，2026-04-20

func _apply_window_settings() -> void:
	var window := get_window()
	window.content_scale_factor = 1.0
	window.content_scale_size = Vector2i(960, 540)
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
		_print_display_info(window)
		return
	window.mode = Window.MODE_WINDOWED
	window.size = Vector2i(window_width, window_height)
	window.call_deferred("move_to_center")
	_print_display_info(window)


func _print_display_info(window: Window) -> void:
	var size := window.size
	var scale := float(size.x) / 960.0
	print("[Settings] 分辨率: %dx%d | 缩放: %.2fx" % [size.x, size.y, scale])


## 设置窗口分辨率（窗口模式）。立即应用并落盘。
func set_window_resolution(width: int, height: int) -> void:
	window_width = width
	window_height = height
	fullscreen = false
	apply_settings()
	save_settings()


## 切换全屏开关。立即应用并落盘。
func set_fullscreen(enabled: bool) -> void:
	if fullscreen == enabled:
		return
	fullscreen = enabled
	apply_settings()
	save_settings()


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


## 切换难度档位。立即落盘并广播 difficulty_changed，关卡监听后会重算所有单位。
func set_difficulty(id: String) -> void:
	if difficulty == id:
		return
	if not GameState.DIFFICULTY_CONFIG.has(id):
		push_warning("Settings: 未知难度 ID '%s'，已忽略" % id)
		return
	difficulty = id
	save_settings()
	difficulty_changed.emit(id)


## 重置为默认值（仅更新内存状态，不落盘）
func reset_to_defaults() -> void:
	music_volume = 0.8
	sfx_volume = 0.8
	ui_volume = 0.8
	voice_volume = 0.8
	ambience_volume = 0.8
	debug_mode = false
	muted = false
	window_width = 1920
	window_height = 1080
	fullscreen = false
	difficulty = DEFAULT_DIFFICULTY
	apply_settings()
