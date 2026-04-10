class_name CutscenePlayer
extends CanvasLayer
## Reusable comic cutscene player.
## Displays a sequence of full-page images with manual page-flipping.
## Two modes:
##   - Standalone: pass next_scene to setup(), transitions on finish.
##   - Overlay: omit next_scene, emits cutscene_finished and queue_free().

signal cutscene_finished

@onready var background: ColorRect = $Background
@onready var panel_image: TextureRect = $PanelImage
@onready var skip_button: Button = $SkipButton
@onready var page_indicator: Label = $PageIndicator

var _pages: Array[String] = []
var _current_index: int = -1
var _transitioning: bool = false
var _next_scene_path: String = ""


func _ready() -> void:
	layer = 100
	skip_button.pressed.connect(_on_skip_pressed)
	panel_image.modulate.a = 0.0


func setup(pages: Array[String], next_scene: String = "") -> void:
	_pages = pages
	_next_scene_path = next_scene
	_advance()


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning:
		get_viewport().set_input_as_handled()
		return

	var advance := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			advance = true

	if advance:
		get_viewport().set_input_as_handled()
		_advance()


func _advance() -> void:
	_current_index += 1
	if _current_index >= _pages.size():
		_finish()
		return

	_transitioning = true
	_update_page_indicator()

	if _current_index == 0:
		# First page: just fade in
		panel_image.texture = load(_pages[_current_index])
		var tween := create_tween()
		tween.tween_property(panel_image, "modulate:a", 1.0, 0.2)
		await tween.finished
	else:
		# Fade out, swap, fade in
		var tween := create_tween()
		tween.tween_property(panel_image, "modulate:a", 0.0, 0.15)
		await tween.finished
		panel_image.texture = load(_pages[_current_index])
		var tween_in := create_tween()
		tween_in.tween_property(panel_image, "modulate:a", 1.0, 0.15)
		await tween_in.finished

	_transitioning = false


func _finish() -> void:
	if _next_scene_path != "":
		GameState.transition_to_scene(_next_scene_path)
	else:
		cutscene_finished.emit()
		queue_free()


func _on_skip_pressed() -> void:
	_finish()


func _update_page_indicator() -> void:
	page_indicator.text = "%d / %d" % [_current_index + 1, _pages.size()]
