extends Node
## Standalone wrapper for CutscenePlayer.
## Reads pending cutscene data from GameState and starts playback.

@onready var cutscene_player: CutscenePlayer = $CutscenePlayer


func _ready() -> void:
	cutscene_player.setup(GameState.pending_cutscene_pages, GameState.pending_next_scene)
