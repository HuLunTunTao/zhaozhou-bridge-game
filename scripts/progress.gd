extends Node
## 全局章节进度。负责关卡解锁、李春技能池解锁、5技能战斗配置与测试控制。

const PROGRESS_PATH := "user://progress.json"
const MAX_EQUIPPED_SKILLS := 4

const LEVEL_ORDER: Array[String] = [
	"关卡1-1",
	"关卡1-2",
	"关卡1-3",
	"关卡1-4",
]

const INITIAL_SKILL_IDS: Array[String] = [
	"lc_rule_strike",
	"lc_wedge_bank_probe",
	"lc_cast_stone_arrest_flow",
]

const SKILL_PATHS := {
	"lc_rule_strike": "res://data/skills/lc_rule_strike.tres",
	"lc_wedge_bank_probe": "res://data/skills/lc_wedge_bank_probe.tres",
	"lc_cast_stone_arrest_flow": "res://data/skills/lc_cast_stone_arrest_flow.tres",
	"lc_read_water_fix_site": "res://data/skills/lc_read_water_fix_site.tres",
	"lc_pile_bind_wave": "res://data/skills/lc_pile_bind_wave.tres",
	"lc_divider_mark_arc": "res://data/skills/lc_divider_mark_arc.tres",
	"lc_line_lock_arc": "res://data/skills/lc_line_lock_arc.tres",
	"lc_inkline_balance_arch": "res://data/skills/lc_inkline_balance_arch.tres",
	"lc_link_wedges_arch": "res://data/skills/lc_link_wedges_arch.tres",
	"lc_guide_flood_open_arch": "res://data/skills/lc_guide_flood_open_arch.tres",
}

const LEVEL_STAGE_SKILLS := {
	"关卡1-1": "lc_read_water_fix_site",
	"关卡1-2": "lc_divider_mark_arc",
	"关卡1-3": "lc_inkline_balance_arch",
	"关卡1-4": "lc_guide_flood_open_arch",
}

const LEVEL_GROWTH_OPTIONS := {
	"关卡1-1": [
		{"id": "growth_training_mobilize", "name": "操练与动员", "description": "全体我方最大生命值 +10，行动力上限 +5"},
		{"id": "growth_maps_measures", "name": "习图记尺", "description": "李春基础攻击力 +4，规尺击伤害倍率 +0.05"},
		{"id": "growth_river_master", "name": "请益河工", "description": "李春获得新技能“束桩缓波”"},
		{"id": "growth_stone_reinforce", "name": "备石加固", "description": "工匠的捍作护行持续时间 +1 回合"},
	],
	"关卡1-2": [
		{"id": "growth_drawing_discipline", "name": "墨绳习算", "description": "李春基础攻击力 +4，分规定弧伤害倍率 +0.05"},
		{"id": "growth_center_hold", "name": "护模齐作", "description": "全体工匠最大生命值 +10，基础攻击力 +2"},
		{"id": "growth_arch_refine", "name": "参校定弧", "description": "李春获得新技能“绳准锁弧”"},
		{"id": "growth_quick_measure", "name": "熟尺知度", "description": "测量工参数采集消耗 -10，李春参数确认消耗 -5，李春行动力上限 +5"},
	],
	"关卡1-3": [
		{"id": "growth_balance_method", "name": "校券有法", "description": "墨绳校券冷却 -1，李春行动力上限 +5"},
		{"id": "growth_joint_finish", "name": "收缝习熟", "description": "收缝合龙消耗 -10，李春基础攻击力 +4"},
		{"id": "growth_link_arch", "name": "连楔并拱", "description": "李春获得新技能“连楔并拱”"},
		{"id": "growth_team_hold", "name": "立券同力", "description": "全体工匠最大生命值 +10，全体运石工行动力上限 +5"},
	],
}

const GROWTH_SKILL_UNLOCKS := {
	"growth_river_master": "lc_pile_bind_wave",
	"growth_arch_refine": "lc_line_lock_arc",
	"growth_link_arch": "lc_link_wedges_arch",
}

const CLEAR_REWARDS := {
	"关卡1-1": {
		"unlock_levels": ["关卡1-2"],
		"unlock_skills": [],
	},
	"关卡1-2": {
		"unlock_levels": ["关卡1-3"],
		"unlock_skills": [],
	},
	"关卡1-3": {
		"unlock_levels": ["关卡1-4"],
		"unlock_skills": [],
	},
	"关卡1-4": {
		"unlock_levels": [],
		"unlock_skills": [],
	},
}

const LEVEL_FIXED_UNLOCKS := {
	"关卡1-2": ["lc_divider_mark_arc"],
	"关卡1-3": ["lc_inkline_balance_arch"],
	"关卡1-4": ["lc_guide_flood_open_arch"],
}

signal progress_changed

var completed_levels: Array[String] = []
var unlocked_levels: Array[String] = []
var unlocked_skill_ids: Array[String] = []
var equipped_skill_ids: Array[String] = []
var selected_growth_by_level: Dictionary = {}


func _ready() -> void:
	load_progress()
	_normalize_progress()


func load_progress() -> void:
	if not FileAccess.file_exists(PROGRESS_PATH):
		_reset_defaults(false)
		return
	var file := FileAccess.open(PROGRESS_PATH, FileAccess.READ)
	if file == null:
		_reset_defaults(false)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		completed_levels = _to_string_array(parsed.get("completed_levels", []))
		unlocked_levels = _to_string_array(parsed.get("unlocked_levels", []))
		unlocked_skill_ids = _to_string_array(parsed.get("unlocked_skill_ids", []))
		equipped_skill_ids = _to_string_array(parsed.get("equipped_skill_ids", []))
		selected_growth_by_level = _to_growth_choice_dict(parsed.get("selected_growth_by_level", {}))
	else:
		_reset_defaults(false)


func save_progress() -> void:
	var file := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Progress: 无法保存到 %s" % PROGRESS_PATH)
		return
	file.store_string(JSON.stringify({
		"completed_levels": completed_levels,
		"unlocked_levels": unlocked_levels,
		"unlocked_skill_ids": unlocked_skill_ids,
		"equipped_skill_ids": equipped_skill_ids,
		"selected_growth_by_level": selected_growth_by_level,
	}))
	file.close()


func is_level_unlocked(level_name: String) -> bool:
	return level_name in unlocked_levels


func is_level_completed(level_name: String) -> bool:
	return level_name in completed_levels


func get_level_summary() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for level_name in LEVEL_ORDER:
		rows.append({
			"level_name": level_name,
			"unlocked": is_level_unlocked(level_name),
			"completed": is_level_completed(level_name),
		})
	return rows


func get_unlocked_skill_ids() -> Array[String]:
	return unlocked_skill_ids.duplicate()


func get_equipped_skill_ids() -> Array[String]:
	return equipped_skill_ids.duplicate()


func get_effective_max_equipped() -> int:
	var equippable_count := 0
	for skill_id in unlocked_skill_ids:
		if not is_stage_limited_skill(skill_id):
			equippable_count += 1
	return mini(MAX_EQUIPPED_SKILLS, equippable_count)


func get_level_growth_options(level_name: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in LEVEL_GROWTH_OPTIONS.get(level_name, []):
		rows.append((row as Dictionary).duplicate(true))
	return rows


func get_level_growth_choice_ids(level_name: String) -> Array[String]:
	return _to_string_array(selected_growth_by_level.get(level_name, []))


func has_level_growth_choices(level_name: String) -> bool:
	return not get_level_growth_choice_ids(level_name).is_empty()


func get_growth_option_name(option_id: String) -> String:
	for level_name in LEVEL_GROWTH_OPTIONS.keys():
		for option in LEVEL_GROWTH_OPTIONS[level_name]:
			var data := option as Dictionary
			if str(data.get("id", "")) == option_id:
				return str(data.get("name", option_id))
	return option_id


func has_growth_option(option_id: String) -> bool:
	for level_name in selected_growth_by_level.keys():
		if option_id in get_level_growth_choice_ids(str(level_name)):
			return true
	return false


func is_skill_unlocked(skill_id: String) -> bool:
	return skill_id in unlocked_skill_ids


func is_skill_equipped(skill_id: String) -> bool:
	return skill_id in equipped_skill_ids


func is_stage_limited_skill(skill_id: String) -> bool:
	return skill_id in LEVEL_STAGE_SKILLS.values()


func get_stage_skill_id(level_name: String = GameState.selected_level) -> String:
	return str(LEVEL_STAGE_SKILLS.get(level_name, ""))


func set_skill_equipped(skill_id: String, equipped: bool) -> bool:
	if not is_skill_unlocked(skill_id):
		return false
	if is_stage_limited_skill(skill_id):
		return false
	if equipped:
		if is_skill_equipped(skill_id):
			return true
		if equipped_skill_ids.size() >= MAX_EQUIPPED_SKILLS:
			return false
		equipped_skill_ids.append(skill_id)
	else:
		equipped_skill_ids.erase(skill_id)
	_normalize_progress()
	return true


func set_equipped_skill_ids(skill_ids: Array[String]) -> void:
	equipped_skill_ids.clear()
	for skill_id in skill_ids:
		if not is_skill_unlocked(skill_id):
			continue
		if is_stage_limited_skill(skill_id):
			continue
		if equipped_skill_ids.size() >= MAX_EQUIPPED_SKILLS:
			break
		if skill_id in equipped_skill_ids:
			continue
		equipped_skill_ids.append(skill_id)
	_normalize_progress()


func get_equipped_skill_resources() -> Array[SkillData]:
	var skills: Array[SkillData] = []
	for skill_id in equipped_skill_ids:
		var skill := get_skill_resource(skill_id)
		if skill != null:
			skills.append(skill)
	return skills


func get_battle_skill_ids(level_name: String = GameState.selected_level) -> Array[String]:
	var battle_ids: Array[String] = []
	for skill_id in equipped_skill_ids:
		if is_stage_limited_skill(skill_id):
			continue
		if skill_id not in battle_ids:
			battle_ids.append(skill_id)
	var stage_skill_id := get_stage_skill_id(level_name)
	if not stage_skill_id.is_empty() and stage_skill_id not in battle_ids:
		battle_ids.append(stage_skill_id)
	return battle_ids


func get_battle_skill_resources(level_name: String = GameState.selected_level) -> Array[SkillData]:
	var skills: Array[SkillData] = []
	for skill_id in get_battle_skill_ids(level_name):
		var skill := get_skill_resource(skill_id)
		if skill != null:
			skills.append(skill)
	return skills


func get_unlocked_skill_resources() -> Array[SkillData]:
	var skills: Array[SkillData] = []
	for skill_id in unlocked_skill_ids:
		var skill := get_skill_resource(skill_id)
		if skill != null:
			skills.append(skill)
	return skills


func get_skill_resource(skill_id: String) -> SkillData:
	var path: String = SKILL_PATHS.get(skill_id, "")
	if path.is_empty():
		return null
	var res := load(path)
	return res as SkillData


func complete_level(level_name: String, growth_option_ids: Array[String] = []) -> void:
	if not is_level_completed(level_name):
		completed_levels.append(level_name)
	if not growth_option_ids.is_empty():
		set_level_growth_choices(level_name, growth_option_ids)
	var reward: Dictionary = CLEAR_REWARDS.get(level_name, {})
	for next_level: String in reward.get("unlock_levels", []):
		_unlock_level_content(next_level)
	for skill_id: String in reward.get("unlock_skills", []):
		if skill_id not in unlocked_skill_ids:
			unlocked_skill_ids.append(skill_id)
	_normalize_progress()


func reset_progress() -> void:
	_reset_defaults(true)


func unlock_all_progress() -> void:
	completed_levels = LEVEL_ORDER.duplicate()
	unlocked_levels = LEVEL_ORDER.duplicate()
	unlocked_skill_ids = _to_string_array(SKILL_PATHS.keys())
	unlocked_skill_ids.sort()
	equipped_skill_ids = []
	for skill_id in unlocked_skill_ids:
		if is_stage_limited_skill(skill_id):
			continue
		if equipped_skill_ids.size() >= MAX_EQUIPPED_SKILLS:
			break
		equipped_skill_ids.append(skill_id)
	_normalize_progress()


func apply_debug_stage_preset(level_name: String) -> void:
	reset_progress()
	match level_name:
		"关卡1-2":
			complete_level("关卡1-1")
		"关卡1-3":
			complete_level("关卡1-1")
			complete_level("关卡1-2")
		"关卡1-4":
			complete_level("关卡1-1")
			complete_level("关卡1-2")
			complete_level("关卡1-3")
		_:
			pass


func _reset_defaults(emit_change: bool) -> void:
	completed_levels = []
	unlocked_levels = ["关卡1-1"]
	unlocked_skill_ids = INITIAL_SKILL_IDS.duplicate()
	equipped_skill_ids = INITIAL_SKILL_IDS.duplicate()
	selected_growth_by_level = {}
	if emit_change:
		_normalize_progress()


func _unlock_level_content(level_name: String) -> void:
	if level_name not in unlocked_levels:
		unlocked_levels.append(level_name)
	for skill_id: String in LEVEL_FIXED_UNLOCKS.get(level_name, []):
		if skill_id not in unlocked_skill_ids:
			unlocked_skill_ids.append(skill_id)


func _normalize_progress() -> void:
	completed_levels = _unique_in_level_order(completed_levels)
	unlocked_levels = _unique_in_level_order(unlocked_levels)
	selected_growth_by_level = _normalize_growth_choice_dict(selected_growth_by_level)
	for level_name in completed_levels:
		if level_name not in unlocked_levels:
			unlocked_levels.append(level_name)

	var unique_skills: Array[String] = []
	for skill_id in unlocked_skill_ids:
		if skill_id.is_empty():
			continue
		if not SKILL_PATHS.has(skill_id):
			continue
		if skill_id not in unique_skills:
			unique_skills.append(skill_id)
	for skill_id in INITIAL_SKILL_IDS:
		if skill_id not in unique_skills:
			unique_skills.append(skill_id)
	for option_id in get_all_growth_option_ids():
		var growth_skill_id := str(GROWTH_SKILL_UNLOCKS.get(option_id, ""))
		if not growth_skill_id.is_empty() and growth_skill_id not in unique_skills:
			unique_skills.append(growth_skill_id)
	unlocked_skill_ids = unique_skills

	var normalized_equipped: Array[String] = []
	for skill_id in equipped_skill_ids:
		if skill_id not in unlocked_skill_ids:
			continue
		if is_stage_limited_skill(skill_id):
			continue
		if skill_id in normalized_equipped:
			continue
		if normalized_equipped.size() >= MAX_EQUIPPED_SKILLS:
			break
		normalized_equipped.append(skill_id)
	equipped_skill_ids = normalized_equipped

	save_progress()
	progress_changed.emit()


func _unique_in_level_order(input_levels: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for level_name in LEVEL_ORDER:
		if level_name in input_levels and level_name not in result:
			result.append(level_name)
	return result


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


func set_level_growth_choices(level_name: String, option_ids: Array[String]) -> bool:
	var available_ids: Array[String] = []
	for option in LEVEL_GROWTH_OPTIONS.get(level_name, []):
		available_ids.append(str((option as Dictionary).get("id", "")))
	if available_ids.is_empty():
		return false
	var normalized_ids: Array[String] = []
	for option_id in option_ids:
		var growth_id := str(option_id)
		if growth_id.is_empty() or growth_id not in available_ids:
			continue
		if growth_id in normalized_ids:
			continue
		normalized_ids.append(growth_id)
		if normalized_ids.size() >= 2:
			break
	if normalized_ids.size() != 2:
		return false
	selected_growth_by_level[level_name] = normalized_ids
	_normalize_progress()
	return true


func get_all_growth_option_ids() -> Array[String]:
	var result: Array[String] = []
	for level_name in LEVEL_ORDER:
		for option_id in get_level_growth_choice_ids(level_name):
			if option_id not in result:
				result.append(option_id)
	return result


func _normalize_growth_choice_dict(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for level_name in LEVEL_ORDER:
		var option_ids := _to_string_array(value.get(level_name, []))
		if option_ids.is_empty():
			continue
		var available_ids: Array[String] = []
		for option in LEVEL_GROWTH_OPTIONS.get(level_name, []):
			available_ids.append(str((option as Dictionary).get("id", "")))
		var normalized_ids: Array[String] = []
		for option_id in option_ids:
			if option_id not in available_ids or option_id in normalized_ids:
				continue
			normalized_ids.append(option_id)
			if normalized_ids.size() >= 2:
				break
		if normalized_ids.size() == 2:
			result[level_name] = normalized_ids
	return result


func _to_growth_choice_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value.duplicate(true)
	return {}
