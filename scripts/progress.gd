extends Node
## 全局章节进度。负责关卡解锁、李春技能池解锁、5技能战斗配置与测试控制。

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
	"lc_plumb_line",
]

const SKILL_PATHS := {
	"lc_rule_strike": "res://data/skills/lc_rule_strike.tres",
	"lc_wedge_bank_probe": "res://data/skills/lc_wedge_bank_probe.tres",
	"lc_cast_stone_arrest_flow": "res://data/skills/lc_cast_stone_arrest_flow.tres",
	"lc_plumb_line": "res://data/skills/lc_plumb_line.tres",
	"lc_settle_pile": "res://data/skills/lc_settle_pile.tres",
	"lc_water_push": "res://data/skills/lc_water_push.tres",
	"lc_pile_bind_wave": "res://data/skills/lc_pile_bind_wave.tres",
	"lc_ruler_eight": "res://data/skills/lc_ruler_eight.tres",
	"lc_line_lock_arc": "res://data/skills/lc_line_lock_arc.tres",
	"lc_anchor_pile": "res://data/skills/lc_anchor_pile.tres",
	"lc_link_wedges_arch": "res://data/skills/lc_link_wedges_arch.tres",
	"lc_divider_mark_arc": "res://data/skills/lc_divider_mark_arc.tres",
	"lc_read_water_fix_site": "res://data/skills/lc_read_water_fix_site.tres",
	"lc_ink_set_arch": "res://data/skills/lc_ink_set_arch.tres",
	"lc_inkline_balance_arch": "res://data/skills/lc_inkline_balance_arch.tres",
	"lc_guide_flood_open_arch": "res://data/skills/lc_guide_flood_open_arch.tres",
}

const LEVEL_STAGE_SKILLS := {
	"关卡1-1": "lc_read_water_fix_site",
	"关卡1-2": "lc_ink_set_arch",   # 原为 lc_divider_mark_arc
	"关卡1-3": "lc_inkline_balance_arch",
	"关卡1-4": "lc_guide_flood_open_arch",
}

const LEVEL_GROWTH_OPTIONS := {
	"关卡1-1": [
		{"id": "g1_1_river", "name": "请益河工", "skill_id": "lc_pile_bind_wave"},
		{"id": "g1_1_push", "name": "顺水推舟", "skill_id": "lc_water_push"},
		{"id": "g1_1_pile", "name": "镇基沉桩", "skill_id": "lc_settle_pile"},
		{"id": "g1_1_atk", "name": "习图记尺", "description": "李春基础攻击力 +4"},
		{"id": "g1_1_ap", "name": "操练与动员", "description": "全体我方行动力上限 +5"},
	],
	"关卡1-2": [
		{"id": "g1_2_ring", "name": "围尺八方", "skill_id": "lc_ruler_eight"},
		{"id": "g1_2_lock", "name": "参校定弧", "skill_id": "lc_line_lock_arc"},
		{"id": "g1_2_atk", "name": "墨绳习算", "description": "李春基础攻击力 +4"},
		{"id": "g1_2_ap", "name": "熟尺知度", "description": "全体我方行动力上限 +5"},
		{"id": "g1_2_craft", "name": "护模齐作", "description": "全体工匠最大生命值 +10，基础攻击力 +2"},
	],
	"关卡1-3": [
		{"id": "g1_3_link", "name": "连楔并拱", "skill_id": "lc_link_wedges_arch"},
		{"id": "g1_3_anchor", "name": "阵心立桩", "skill_id": "lc_anchor_pile"},
		{"id": "g1_3_atk", "name": "收缝习熟", "description": "李春基础攻击力 +4"},
		{"id": "g1_3_ap", "name": "立券同力", "description": "全体我方行动力上限 +5"},
		{"id": "g1_3_team", "name": "同心护城", "description": "全体我方最大生命值 +10，运石工行动力上限 +5"},
	],
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
		# 通关 1-4 → 把所有伤害技能补齐，作为生存挑战模式准备。
		"unlock_skills": [
			"lc_rule_strike",
			"lc_wedge_bank_probe",
			"lc_cast_stone_arrest_flow",
			"lc_plumb_line",
			"lc_settle_pile",
			"lc_water_push",
			"lc_pile_bind_wave",
			"lc_ruler_eight",
			"lc_line_lock_arc",
			"lc_anchor_pile",
			"lc_link_wedges_arch",
			"lc_divider_mark_arc",
		],
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
## 教程已观看标记：{"level1-1": true, ...}。Key 由教程侧自行定义。
var tutorial_flags: Dictionary = {}
## 章节通关标记：{"chapter_1": true, ...}。由各关卡脚本在通关时写入。
var chapter_flags: Dictionary = {}
## 各关通关结算记录：{"关卡1-4": {"turns": 12, ...}}。关卡脚本自定字段。
var level_clear_summary: Dictionary = {}


func _ready() -> void:
	load_progress()
	normalize_and_save()


func load_progress() -> void:
	var path := _get_progress_path()
	if not FileAccess.file_exists(path):
		_reset_defaults(false)
		return
	var file := FileAccess.open(path, FileAccess.READ)
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
		tutorial_flags = _to_bool_dict(parsed.get("tutorial_flags", {}))
		chapter_flags = _to_bool_dict(parsed.get("chapter_flags", {}))
		level_clear_summary = _to_summary_dict(parsed.get("level_clear_summary", {}))
	else:
		_reset_defaults(false)


func save_progress() -> void:
	var path := _get_progress_path()
	if not SaveSlots.ensure_slot_dir():
		push_error("Progress: 无法创建存档位目录")
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Progress: 无法保存到 %s" % path)
		return
	file.store_string(JSON.stringify({
		"completed_levels": completed_levels,
		"unlocked_levels": unlocked_levels,
		"unlocked_skill_ids": unlocked_skill_ids,
		"equipped_skill_ids": equipped_skill_ids,
		"selected_growth_by_level": selected_growth_by_level,
		"tutorial_flags": tutorial_flags,
		"chapter_flags": chapter_flags,
		"level_clear_summary": level_clear_summary,
	}))
	file.close()


func normalize_and_save() -> void:
	_normalize_progress()


func _get_progress_path() -> String:
	return SaveSlots.get_progress_path()


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
		rows.append(_build_growth_option_display(row as Dictionary))
	return rows


func get_level_growth_choice_ids(level_name: String) -> Array[String]:
	return _to_string_array(selected_growth_by_level.get(level_name, []))


func has_level_growth_choices(level_name: String) -> bool:
	return not get_level_growth_choice_ids(level_name).is_empty()


func get_growth_option_name(option_id: String) -> String:
	var option := _get_growth_option_data(option_id)
	if not option.is_empty():
		return str(_build_growth_option_display(option).get("name", option_id))
	return option_id


func _build_growth_option_display(option: Dictionary) -> Dictionary:
	var row := option.duplicate(true)
	var skill_id := str(row.get("skill_id", ""))
	if skill_id.is_empty():
		return row

	var growth_name := str(row.get("name", ""))
	var skill_label := skill_id
	var description := ""
	var skill := get_skill_resource(skill_id)
	if skill != null:
		if not skill.skill_name.is_empty():
			skill_label = skill.skill_name
		description = skill.description.strip_edges()

	if growth_name.is_empty():
		row["name"] = skill_label
	else:
		row["name"] = "%s：%s" % [growth_name, skill_label]
	if description.is_empty():
		row["description"] = "获得新技能：%s" % skill_label
	else:
		row["description"] = description
	return row


func _get_growth_option_data(option_id: String) -> Dictionary:
	for level_name in LEVEL_GROWTH_OPTIONS.keys():
		for option in LEVEL_GROWTH_OPTIONS[level_name]:
			var data := option as Dictionary
			if str(data.get("id", "")) == option_id:
				return data
	return {}


func _get_growth_option_skill_id(option_id: String) -> String:
	return str(_get_growth_option_data(option_id).get("skill_id", ""))


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


## 清除所有进度（仅更新内存状态，不落盘）
func clear_all_in_memory() -> void:
	_reset_defaults(false)
	progress_changed.emit()


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
	tutorial_flags = {}
	chapter_flags = {}
	level_clear_summary = {}
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
		var growth_skill_id := _get_growth_option_skill_id(option_id)
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
		if normalized_ids.size() >= 3:
			break
	if normalized_ids.size() != 3:
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
			if normalized_ids.size() >= 3:
				break
		if normalized_ids.size() == 3:
			result[level_name] = normalized_ids
	return result


func _to_growth_choice_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value.duplicate(true)
	return {}


## 从 JSON 读出的 tutorial_flags；只保留值为 true 的布尔字段。
func _to_bool_dict(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if value is Dictionary:
		for key in value.keys():
			var v: Variant = value[key]
			if v is bool and v:
				result[str(key)] = true
	return result


## 教程是否已观看过。id 由教程侧约定（如 "level1-1"）。
func has_seen_tutorial(id: String) -> bool:
	return tutorial_flags.get(id, false) == true


## 标记教程已观看并立即落盘。
func mark_tutorial_seen(id: String) -> void:
	if tutorial_flags.get(id, false) == true:
		return
	tutorial_flags[id] = true
	save_progress()


## 章节通关标记是否设置。key 例如 "chapter_1"。
func has_chapter_flag(key: String) -> bool:
	return chapter_flags.get(key, false) == true


## 标记章节通关并立即落盘。
func set_chapter_flag(key: String, value: bool = true) -> void:
	if chapter_flags.get(key, false) == value:
		return
	if value:
		chapter_flags[key] = true
	else:
		chapter_flags.erase(key)
	save_progress()


## 记录某关通关结算。summary 字段由关卡脚本自定（turns / stability 等）。
func set_level_clear_summary(level_name: String, summary: Dictionary) -> void:
	level_clear_summary[level_name] = summary.duplicate(true)
	save_progress()


func get_level_clear_summary(level_name: String) -> Dictionary:
	var entry: Variant = level_clear_summary.get(level_name, {})
	if entry is Dictionary:
		return (entry as Dictionary).duplicate(true)
	return {}


## 从 JSON 读取 level_clear_summary：只保留顶层值仍为字典的条目。
func _to_summary_dict(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if value is Dictionary:
		for key in value.keys():
			var v: Variant = value[key]
			if v is Dictionary:
				result[str(key)] = (v as Dictionary).duplicate(true)
	return result
