extends BaseLevel
## 怪物全展示关卡：展示所有怪物外观，用于测试。

var _ud_generic: UnitData = preload("res://data/units/dark_current.tres")

var _monster_list: Array[Dictionary] = [
	{"name": "暗涌", "visual": preload("res://scenes/unit/visual/monster/暗涌/暗涌_visual.tscn")},
	{"name": "水旋", "visual": preload("res://scenes/unit/visual/monster/水旋/水旋_visual.tscn")},
	{"name": "坍岸泥鬼", "visual": preload("res://scenes/unit/visual/monster/坍岸泥鬼/坍岸泥鬼_visual.tscn")},
	{"name": "浮木群", "visual": preload("res://scenes/unit/visual/monster/浮木群/浮木群_visual.tscn")},
	{"name": "洪峰", "visual": preload("res://scenes/unit/visual/monster/洪峰/洪峰_visual.tscn")},
	{"name": "断索鬼", "visual": preload("res://scenes/unit/visual/monster/断索鬼/断索鬼_visual.tscn")},
	{"name": "桥台噬者", "visual": preload("res://scenes/unit/visual/monster/桥台噬者/桥台噬者_visual.tscn")},
	{"name": "泥沙魇", "visual": preload("res://scenes/unit/visual/monster/泥沙魇/泥沙魇_visual.tscn")},
	{"name": "脱缝鬼", "visual": preload("res://scenes/unit/visual/monster/脱缝鬼/脱缝鬼_visual.tscn")},
	{"name": "错券兵", "visual": preload("res://scenes/unit/visual/monster/错券兵/错券兵_visual.tscn")},
	{"name": "漂木群洪水版", "visual": preload("res://scenes/unit/visual/monster/漂木群洪水版/漂木群洪水版_visual.tscn")},
	{"name": "守法匠首", "visual": preload("res://scenes/unit/visual/monster/守法匠首/守法匠首_visual.tscn")},
	{"name": "旧制监工", "visual": preload("res://scenes/unit/visual/monster/旧制监工/旧制监工_visual.tscn")},
	{"name": "裂石兽", "visual": preload("res://scenes/unit/visual/monster/裂石兽/裂石兽_visual.tscn")},
	{"name": "重墩石像", "visual": preload("res://scenes/unit/visual/monster/重墩石像/重墩石像_visual.tscn")},
]

var _player: Node2D


func get_teams_config() -> Array:
	_player = $"Entities/Units/Player"
	return [
		{
			"name": "玩家",
			"faction": "好人",
			"controller": "player",
			"units": [_player],
		},
		{
			"name": "怪物展示",
			"faction": "坏人",
			"controller": "ai",
			"units": [],
		},
	]


func _on_level_ready() -> void:
	setup_unit_stats(_player as Unit, "李春", 999, 0, 999, 8, Enums.Element.NONE, 0, true)
	_spawn_all_monsters()


func _spawn_all_monsters() -> void:
	# 敌方：起始位置 (4, -2)，每行 5 个，间隔 2 格
	var cols := 5
	var enemy_start := Vector2i(4, -2)
	for i in range(_monster_list.size()):
		var entry: Dictionary = _monster_list[i]
		var col := i % cols
		@warning_ignore("integer_division")
		var row := i / cols
		var cell := enemy_start + Vector2i(col * 2, row * 2)
		var unit := spawn_unit(_ud_generic, cell, 1, entry["visual"])
		setup_unit_stats(unit, entry["name"], 100, 10, 100, 10)

	# 玩家方：同样的怪物，放在左侧区域
	var ally_start := Vector2i(-20, -2)
	for i in range(_monster_list.size()):
		var entry: Dictionary = _monster_list[i]
		var col := i % cols
		@warning_ignore("integer_division")
		var row := i / cols
		var cell := ally_start + Vector2i(col * 2, row * 2)
		var unit := spawn_unit(_ud_generic, cell, 0, entry["visual"])
		setup_unit_stats(unit, entry["name"] + "(友)", 100, 10, 100, 10)


func get_objectives_text() -> Dictionary:
	return {
		"victory": ["- 展示关卡，无胜利条件"],
		"defeat": [],
	}


func check_defeat() -> String:
	return ""


func check_victory() -> bool:
	return false
