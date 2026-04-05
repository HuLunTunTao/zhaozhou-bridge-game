extends Node

var selected_level: String = ""

## Transient data for passing cutscene info across scene changes.
var pending_cutscene_pages: Array[String] = []
var pending_next_scene: String = ""

## 关卡名 → 场景路径。字典的插入顺序即关卡按钮的显示顺序。
## 开发者只需在此处添加条目，选关界面会自动生成对应按钮。
const LEVEL_SCENES: Dictionary = {
	"关卡1-1": "res://scenes/levels/level1-1/level1-1.tscn",
	"关卡1-2": "res://scenes/levels/level1-2/level1-2.tscn",
	"关卡1-3": "res://scenes/levels/level1-3/level1-3.tscn",
	"关卡1-3-2": "res://scenes/levels/level1-3-2/level1-3-2.tscn",
	"关卡1-4": "res://scenes/levels/level1-4/level1-4.tscn",
	"关卡测试": "res://scenes/levels/test/test.tscn",
}

## 过场动画图片路径，按关卡名和时机（"pre" / "post"）索引。
## 关卡内的中途过场在各自关卡脚本中定义。
const CUTSCENE_DATA: Dictionary = {
	"关卡1-1": {
		"pre": [
			"res://assets/cutscenes/level1-1/pre_01.png",
			"res://assets/cutscenes/level1-1/pre_02.png",
		],
		"post": [
			"res://assets/cutscenes/level1-1/post_01.png",
		],
	},
}


func get_level_scene_path(level_name: String) -> String:
	return LEVEL_SCENES.get(level_name, "")


func get_cutscene_pages(level_name: String, timing: String) -> Array[String]:
	var level_data: Dictionary = CUTSCENE_DATA.get(level_name, {})
	var pages: Array[String] = []
	pages.assign(level_data.get(timing, []))
	return pages


func has_cutscene(level_name: String, timing: String) -> bool:
	return get_cutscene_pages(level_name, timing).size() > 0
