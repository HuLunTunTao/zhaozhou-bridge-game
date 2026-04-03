extends Node

var selected_level: int = 1

const LEVEL_SCENES: Dictionary = {
	1: "res://scenes/levels/level1-1.tscn",
	2: "res://scenes/levels/level1-2.tscn",
	3: "res://scenes/levels/level1-3.tscn",
	4: "res://scenes/levels/level1-3-2.tscn",
	5: "res://scenes/levels/level1-4.tscn",
	6: "res://scenes/levels/test.tscn",
}


func get_level_scene_path(level_num: int) -> String:
	return LEVEL_SCENES.get(level_num, "")
