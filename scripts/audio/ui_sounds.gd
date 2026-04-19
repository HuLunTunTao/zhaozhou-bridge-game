extends Node
## 全局 UI 音效管理器。提供常用 UI 音效的便捷接口。
## 若项目中还没有正式 UI 音效资源，则使用程序化生成的轻量提示音兜底。

const CLICK_PATH := ""
const HOVER_PATH := ""
const POPUP_PATH := ""
const TURN_START_PATH := ""
const VICTORY_PATH := ""
const DEFEAT_PATH := ""

var _click: AudioStream = null
var _hover: AudioStream = null
var _popup: AudioStream = null
var _turn_start: AudioStream = null
var _victory: AudioStream = null
var _defeat: AudioStream = null


func _ready() -> void:
	_click = _load_or_generate(CLICK_PATH, 880.0, 0.045, 0.45)
	_hover = _load_or_generate(HOVER_PATH, 1220.0, 0.025, 0.2)
	_popup = _load_or_generate(POPUP_PATH, 660.0, 0.08, 0.3)
	_turn_start = _load_or_generate(TURN_START_PATH, 523.25, 0.18, 0.3, 783.99)
	_victory = _load_or_generate(VICTORY_PATH, 659.25, 0.28, 0.35, 987.77)
	_defeat = _load_or_generate(DEFEAT_PATH, 392.0, 0.24, 0.32, 261.63)


func _load_or_generate(path: String, freq_a: float, duration: float, amplitude: float, freq_b: float = 0.0) -> AudioStream:
	var stream := _try_load(path)
	if stream != null:
		return stream
	return AudioUtils.make_tone(freq_a, duration, amplitude, freq_b)


func _try_load(path: String) -> AudioStream:
	if path.is_empty():
		return null
	var res := load(path)
	if res is AudioStream:
		return res
	return null


func bind_button(button: BaseButton, bind_hover_sound: bool = true) -> void:
	if button == null:
		return
	if not button.pressed.is_connected(play_click):
		button.pressed.connect(play_click)
	if bind_hover_sound and not button.mouse_entered.is_connected(play_hover):
		button.mouse_entered.connect(play_hover)

# Kimi Code，2026-04-19

func unbind_button(button: BaseButton, unbind_hover_sound: bool = true) -> void:
	if button == null:
		return
	if button.pressed.is_connected(play_click):
		button.pressed.disconnect(play_click)
	if unbind_hover_sound and button.mouse_entered.is_connected(play_hover):
		button.mouse_entered.disconnect(play_hover)


func play_click() -> void:
	if _click:
		SfxManager.play_ui(_click)

func play_hover() -> void:
	if _hover:
		SfxManager.play_ui(_hover)

func play_popup() -> void:
	if _popup:
		SfxManager.play_ui(_popup)

func play_turn_start() -> void:
	if _turn_start:
		SfxManager.play_ui(_turn_start)

func play_victory() -> void:
	if _victory:
		SfxManager.play_ui(_victory)

func play_defeat() -> void:
	if _defeat:
		SfxManager.play_ui(_defeat)
