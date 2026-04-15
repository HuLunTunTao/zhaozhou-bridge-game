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
	"lc_read_water_fix_site",
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

const CLEAR_REWARDS := {
	"关卡1-1": {
		"unlock_levels": ["关卡1-2"],
		"unlock_skills": ["lc_pile_bind_wave"],
	},
	"关卡1-2": {
		"unlock_levels": ["关卡1-3"],
		"unlock_skills": ["lc_line_lock_arc"],
	},
	"关卡1-3": {
		"unlock_levels": ["关卡1-4"],
		"unlock_skills": ["lc_link_wedges_arch"],
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


func complete_level(level_name: String) -> void:
	if not is_level_completed(level_name):
		completed_levels.append(level_name)
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
	for skill_id in INITIAL_SKILL_IDS:
		if is_stage_limited_skill(skill_id):
			continue
		if normalized_equipped.size() >= MAX_EQUIPPED_SKILLS:
			break
		if skill_id in unlocked_skill_ids and skill_id not in normalized_equipped:
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
