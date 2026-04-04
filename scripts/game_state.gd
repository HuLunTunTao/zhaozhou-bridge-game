extends Node

var selected_level: int = 1

## Transient data for passing cutscene info across scene changes.
var pending_cutscene_pages: Array[String] = []
var pending_next_scene: String = ""

const LEVEL_SCENES: Dictionary = {
	1: "res://scenes/levels/level1-1/level1-1.tscn",
	2: "res://scenes/levels/level1-2/level1-2.tscn",
	3: "res://scenes/levels/level1-3/level1-3.tscn",
	4: "res://scenes/levels/level1-3-2/level1-3-2.tscn",
	5: "res://scenes/levels/level1-4/level1-4.tscn",
	6: "res://scenes/levels/test/test.tscn",
}

## Cutscene image paths per level and timing ("pre" / "post").
## Mid-battle cutscenes are defined in individual level scripts.
const CUTSCENE_DATA: Dictionary = {
	1: {
		"pre": [
			"res://assets/cutscenes/level1-1/pre_01.png",
			"res://assets/cutscenes/level1-1/pre_02.png",
		],
		"post": [
			"res://assets/cutscenes/level1-1/post_01.png",
		],
	},
}


func get_level_scene_path(level_num: int) -> String:
	return LEVEL_SCENES.get(level_num, "")


func get_cutscene_pages(level_num: int, timing: String) -> Array[String]:
	var level_data: Dictionary = CUTSCENE_DATA.get(level_num, {})
	var pages: Array[String] = []
	pages.assign(level_data.get(timing, []))
	return pages


func has_cutscene(level_num: int, timing: String) -> bool:
	return get_cutscene_pages(level_num, timing).size() > 0
