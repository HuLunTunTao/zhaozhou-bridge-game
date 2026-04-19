class_name CutscenePlayer
extends CanvasLayer
## Reusable comic cutscene player.
## Displays a sequence of full-page images with manual page-flipping.
## Two modes:
##   - Standalone: pass next_scene to setup(), transitions on finish.
##   - Overlay: omit next_scene, emits cutscene_finished and queue_free().
##
## Supported content types:
## 1. String: image path (compatible with old format)
## 2. Dictionary: video content, format:
##    {
##      "type": "video",
##      "path": "res://path/to/video.mp4",
##      "pause_points": [3.5, 7.2, 10.0]  # optional, time points to pause (seconds)
##    }

# Kimi Code，2026-04-19

signal cutscene_finished

@onready var background: ColorRect = $Background
@onready var panel_image: TextureRect = $PanelImage
@onready var video_player: VideoStreamPlayer = $VideoPlayer
@onready var skip_button: Button = $SkipButton
@onready var page_indicator: Label = $PageIndicator
@onready var continue_hint: Container = $DownPanel

var _pages: Array = []  # Can hold String (image) or Dictionary (video)
var _current_index: int = -1
var _transitioning: bool = false
var _next_scene_path: String = ""

# Video playback state
var _is_playing_video: bool = false
var _video_pause_points: Array = []
var _current_pause_point_index: int = 0
var _waiting_for_click: bool = false


func _ready() -> void:
	layer = 100
	skip_button.pressed.connect(_on_skip_pressed)
	panel_image.modulate.a = 0.0
	video_player.bus = "Cutscene"
	video_player.finished.connect(_on_video_finished)


func setup(pages: Array, next_scene: String = "") -> void:
	_pages = pages
	_next_scene_path = next_scene
	_advance()


func _input(event: InputEvent) -> void:
	if _transitioning:
		get_viewport().set_input_as_handled()
		return

	var advance := false

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			advance = true

	if advance:
		get_viewport().set_input_as_handled()
		_advance()


func _advance() -> void:
	if _is_playing_video:
		if _waiting_for_click:
			# Video is paused: resume playback
			_waiting_for_click = false
			video_player.paused = false
			continue_hint.visible = false
		else:
			# Video is playing: fast forward to next pause point
			if _current_pause_point_index < _video_pause_points.size():
				var next_pause_point = _video_pause_points[_current_pause_point_index]
				video_player.stream_position = next_pause_point
			else:
				# No more pause points: finish video immediately
				_on_video_finished()
		return

	# Normal page advance
	_current_index += 1
	if _current_index >= _pages.size():
		_finish()
		return

	_transitioning = true
	_update_page_indicator()

	# Stop any playing video
	if _is_playing_video:
		video_player.stop()
		_is_playing_video = false
		video_player.visible = false

	var current_content = _pages[_current_index]

	if typeof(current_content) == TYPE_STRING:
		# Image content
		panel_image.visible = true
		panel_image.texture = load(current_content)

		if _current_index == 0:
			# First page: just fade in
			var tween := create_tween()
			tween.tween_property(panel_image, "modulate:a", 1.0, 0.2)
			await tween.finished
		else:
			# Fade out, swap, fade in
			var tween := create_tween()
			tween.tween_property(panel_image, "modulate:a", 0.0, 0.15)
			await tween.finished
			panel_image.texture = load(current_content)
			var tween_in := create_tween()
			tween_in.tween_property(panel_image, "modulate:a", 1.0, 0.15)
			await tween_in.finished

		_transitioning = false
	elif typeof(current_content) == TYPE_DICTIONARY and current_content.get("type") == "video":
		# Video content
		panel_image.visible = false
		video_player.visible = true
		video_player.modulate.a = 0.0

		# Load video
		var video_path = current_content.get("path", "")
		var video_stream = load(video_path)
		if not video_stream:
			push_error("Failed to load video: " + video_path)
			# If video load failed, skip to next page
			_advance()
			return

		video_player.stream = video_stream

		# Get pause points
		_video_pause_points = current_content.get("pause_points", []).duplicate()
		_video_pause_points.sort()  # Ensure pause points are in order
		_current_pause_point_index = 0
		_waiting_for_click = false
		_is_playing_video = true

		if _current_index == 0:
			# First page: fade in video
			var tween := create_tween()
			tween.tween_property(video_player, "modulate:a", 1.0, 0.2)
			await tween.finished
		else:
			# Fade out previous content
			var tween := create_tween()
			tween.tween_property(panel_image, "modulate:a", 0.0, 0.15)
			await tween.finished
			# Fade in video
			var tween_in := create_tween()
			tween_in.tween_property(video_player, "modulate:a", 1.0, 0.15)
			await tween_in.finished

		# Play video
		video_player.play()
		_transitioning = false


func _finish() -> void:
	# Stop any playing video
	if _is_playing_video:
		video_player.stop()
		_is_playing_video = false
	continue_hint.visible = false

	if _next_scene_path != "":
		GameState.transition_to_scene(_next_scene_path)
	else:
		cutscene_finished.emit()
		queue_free()


func _fade_cutscene_volume(duration: float, target_db: float) -> void:
	var idx := AudioServer.get_bus_index("Cutscene")
	if idx < 0:
		return
	var tween := create_tween()
	tween.tween_method(func(v): AudioServer.set_bus_volume_db(idx, v), AudioServer.get_bus_volume_db(idx), target_db, duration)


func _on_skip_pressed() -> void:
	_fade_cutscene_volume(0.3, -80.0)
	await get_tree().create_timer(0.3).timeout
	_finish()
	# 恢复 Cutscene 总线音量（由 Settings 负责实际值）
	Settings.apply_settings()


func _process(_delta: float) -> void:
	if _is_playing_video and not _waiting_for_click and not _transitioning:
		# Check if we have reached the next pause point
		if _current_pause_point_index < _video_pause_points.size():
			var next_pause_point = _video_pause_points[_current_pause_point_index]
			if video_player.stream_position >= next_pause_point:
				video_player.paused = true
				_current_pause_point_index += 1
				_waiting_for_click = true
				continue_hint.visible = true


func _on_video_finished() -> void:
	# Video playback completed, advance to next page
	_is_playing_video = false
	_advance()


func _update_page_indicator() -> void:
	page_indicator.text = "%d / %d" % [_current_index + 1, _pages.size()]


func _on_skip_button_pressed() -> void:
	_finish()


func _on_skip_one_step_button_pressed() -> void:
	_advance()
