extends Node

var selected_level: String = ""

## Transient data for passing cutscene info across scene changes.
var pending_cutscene_pages: Array = []
var pending_next_scene: String = ""
var pending_battle_scene: String = ""

## 场景切换过渡层。
var _transition_layer: CanvasLayer
var _transition_rect: ColorRect


func _ready() -> void:
	_setup_transition()


func _setup_transition() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.layer = 100
	_transition_rect = ColorRect.new()
	_transition_rect.color = Color.BLACK
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition_rect.modulate.a = 0.0
	_transition_layer.add_child(_transition_rect)
	add_child(_transition_layer)


## 带黑幕 fade 的场景切换。替代 get_tree().change_scene_to_file()。
func transition_to_scene(scene_path: String) -> void:
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_transition_rect, "modulate:a", 1.0, 0.3)
	await tween.finished
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	var tween_in := create_tween()
	tween_in.tween_property(_transition_rect, "modulate:a", 0.0, 0.3)
	await tween_in.finished
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

## 关卡名 → 场景路径。字典的插入顺序即关卡按钮的显示顺序。
## 开发者只需在此处添加条目，选关界面会自动生成对应按钮。
const LEVEL_SCENES: Dictionary = {
	"关卡1-1": "res://scenes/levels/level1-1/level1-1.tscn",
	"关卡1-2": "res://scenes/levels/level1-2/level1-2.tscn",
	"关卡1-3": "res://scenes/levels/level1-3/level1-3.tscn",
	"关卡1-4": "res://scenes/levels/level1-4/level1-4.tscn",
}

## 额外关卡 / 挑战模式：不走主线解锁链，常驻可见可玩。
## 与 LEVEL_SCENES 的区别在于不查 Progress.is_level_unlocked，也不参与通关奖励 / 关卡顺序。
const EXTRA_LEVEL_SCENES: Dictionary = {
	"无尽生存": "res://scenes/levels/survival/survival.tscn",
}

## 仅在测试模式下显示的关卡，始终解锁。
const TEST_LEVEL_SCENES: Dictionary = {
	"关卡测试": "res://scenes/levels/test/test.tscn",
	"敌方全展示": "res://scenes/levels/monster_showcase/monster_showcase.tscn",
}

## 过场动画内容，按关卡名和时机（"pre" / "post"）索引。
## 支持两种内容格式：
## 1. 字符串：图片路径（旧格式兼容
## 2. 字典：视频内容，格式：
##    {
##      "type": "video",
##      "path": "res://path/to/video.mp4",
##      "pause_points": [3.5, 7.2, 10.0]  # 可选，暂停时间点（秒）
##    }
## 关卡内的中途过场在各自关卡脚本中定义。
const CUTSCENE_DATA: Dictionary = {
	"关卡1-1": {
		"pre": [
			# "res://assets/cutscenes/level1-1/pre_01.png",
			# "res://assets/cutscenes/level1-1/pre_02.png",
			{
				"type": "video",
				"path": "res://assets/cutscenes/level1-1/1-1-begin.ogv",
				"pause_points": [4.0, 8.0, 16.0, 21.0, 25.0],
			},
		],
		"post": [
			{
				"type": "video",
				"path": "res://assets/cutscenes/level1-1/1-1-end.ogv",
				"pause_points": [4.0, 7.0],
			}
		],
	},
	"关卡1-2": {
		"pre": [
			{
				"type": "video",
				"path": "res://assets/cutscenes/level1-2/1-2-begin.ogv",
				"pause_points": [3.0, 6.0, 11.0, 15.0 ,18.0, 20.0, 23.0],
			},
		],
		"post": [
			{
				"type": "video",
				"path": "res://assets/cutscenes/level1-2/1-2-end.ogv",
				"pause_points": [],
			}
		],
	},
	"关卡1-3": {
		"pre": [
			{
				"type": "video",
				"path": "res://assets/cutscenes/level1-3/1-3-begin.ogv",
				"pause_points":[4.0, 8.0, 13.0, 19.0, 21.0]
			},
		],
		"post": [
			{
				"type": "video",
				"path": "res://assets/cutscenes/level1-3/1-3-end.ogv",
				"pause_points": [],
			}
		],
	},
	"关卡1-4": {
		"pre": [
			{
				"type": "video",
				"path": "res://assets/cutscenes/level1-4/1-4-begin.ogv",
				"pause_points": [2.0,6.0,9.0],
			},
		],
		"post": [
			{
				"type": "video",
				"path": "res://assets/cutscenes/level1-4/1-4-end.ogv",
				"pause_points": [2.0, 3.0, 6.0, 8.5],
			}
		],
	},
}


func get_level_scene_path(level_name: String) -> String:
	var path: String = LEVEL_SCENES.get(level_name, "")
	if path.is_empty():
		path = EXTRA_LEVEL_SCENES.get(level_name, "")
	if path.is_empty():
		path = TEST_LEVEL_SCENES.get(level_name, "")
	return path


func get_cutscene_pages(level_name: String, timing: String) -> Array:
	var level_data: Dictionary = CUTSCENE_DATA.get(level_name, {})
	var pages: Array = []
	pages.assign(level_data.get(timing, []))
	return pages


func has_cutscene(level_name: String, timing: String) -> bool:
	return get_cutscene_pages(level_name, timing).size() > 0
