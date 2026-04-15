extends BaseLevel
## 第一关《踏勘洨河》

# ── 预加载技能 ──
var _sk_staff: SkillData = preload("res://data/skills/sw_staff_end_strike.tres")
var _sk_survey: SkillData = preload("res://data/skills/sw_field_measure_site.tres")
var _sk_mallet: SkillData = preload("res://data/skills/cg_mallet_strike.tres")
var _sk_guard: SkillData = preload("res://data/skills/cg_guard_the_works.tres")
var _sk_lunge: SkillData = preload("res://data/skills/dc_hidden_current_lunge.tres")
var _sk_pull: SkillData = preload("res://data/skills/wp_spiral_pull.tres")
var _sk_crush: SkillData = preload("res://data/skills/bmw_crumbling_bank_crush.tres")
var _sk_timber: SkillData = preload("res://data/skills/dlp_drifting_timber_crash.tres")

# ── 预加载敌方单位数据 ──
var _ud_dark_current: UnitData = preload("res://data/units/dark_current.tres")
var _ud_whirl_pool: UnitData = preload("res://data/units/whirl_pool.tres")
var _ud_mud_wraith: UnitData = preload("res://data/units/bank_mud_wraith.tres")
var _ud_drift_log: UnitData = preload("res://data/units/drift_log_pack.tres")

# ── 敌方队伍索引 ──
const ENEMY_TEAM := 1

# ── 敌方颜色 ──
const COLOR_DARK_CURRENT := Color(0.3, 0.4, 0.9)    # 蓝 - 暗涌（水）
const COLOR_WHIRL_POOL := Color(0.6, 0.3, 0.9)       # 紫蓝 - 水旋（水/控制）
const COLOR_MUD_WRAITH := Color(0.7, 0.5, 0.25)      # 棕 - 坍岸泥流（土）
const COLOR_DRIFT_LOG := Color(0.5, 0.65, 0.2)       # 黄绿 - 浮木群（木）

# ── 单位引用 ──
var _li_chun: Node2D
var _survey_a: Node2D
var _survey_b: Node2D
var _craftsman_a: Node2D
var _craftsman_b: Node2D

# ── 关卡任务状态 ──
enum TaskState { TASK1_SURVEY, TASK2_BRIDGE, TASK3_EVAC }
var _current_task: TaskState = TaskState.TASK1_SURVEY

# ── 勘测点 ──
var _survey_points: Array[SurveyPointTile] = []
var _survey_completed_count: int = 0
const SURVEY_CELLS: Array[Vector2i] = [Vector2i(-11, 12), Vector2i(-1, 2), Vector2i(10, -10)]

# ── 候选桥位 ──
var _bridge_confirmed: bool = false
var _bridge_tile: SpecialTile = null
const BRIDGE_CELL: Vector2i = Vector2i(0, 0)
const COLOR_BRIDGE := Color(0.2, 0.6, 0.95, 0.75)

# ── 撤离点 ──
var _evac_tile: SpecialTile = null
var _evac_notified: bool = false
const EVAC_CELL: Vector2i = Vector2i(23, 19)
const COLOR_EVAC := Color(0.9, 0.3, 0.3, 0.6)

# ── 任务提示 UI ──
var _mission_hint_label: Label = null
var _survey_points_label: Label = null


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/LiChun"
	_survey_a = $"Entities/Units/SurveyWorkerA"
	_survey_b = $"Entities/Units/SurveyWorkerB"
	_craftsman_a = $"Entities/Units/CraftsmanA"
	_craftsman_b = $"Entities/Units/CraftsmanB"
	return [
		{
			"name": "玩家队伍",
			"faction": "好人",
			"controller": "player",
			"units": [_li_chun,_survey_a, _survey_b, _craftsman_a, _craftsman_b],
			
		},
		{
			"name": "敌方",
			"faction": "坏人",
			"controller": "ai",
			"units": [],
		},
	]


func get_wave_config() -> Dictionary:
	return {
		1: [
			{"unit_data": _ud_dark_current, "cell": Vector2i(13,-24), "team_index": ENEMY_TEAM,
			 "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT},
			{"unit_data": _ud_dark_current, "cell": Vector2i(14, -24), "team_index": ENEMY_TEAM,
			 "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT},
		],
		2: [
			{"unit_data": _ud_dark_current, "cell": Vector2i(-24, 20), "team_index": ENEMY_TEAM,
			 "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT},
		],
		3: [
			{"unit_data": _ud_whirl_pool, "cell": Vector2i(15,-24), "team_index": ENEMY_TEAM,
			 "skills": [_sk_pull], "color": COLOR_WHIRL_POOL},
		],
		4: [
			{"unit_data": _ud_mud_wraith, "cell": Vector2i(10, -19), "team_index": ENEMY_TEAM,
			 "skills": [_sk_crush], "color": COLOR_MUD_WRAITH},
		],
		5: [
			{"unit_data": _ud_dark_current, "cell": Vector2i(-22, 20), "team_index": ENEMY_TEAM,
			 "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT},
			{"unit_data": _ud_drift_log, "cell": Vector2i(-19, 21), "team_index": ENEMY_TEAM,
			 "skills": [_sk_timber], "color": COLOR_DRIFT_LOG},
		],
		7: [
			{"unit_data": _ud_whirl_pool, "cell": Vector2i(14, -21), "team_index": ENEMY_TEAM,
			 "skills": [_sk_pull], "color": COLOR_WHIRL_POOL},
		],
	}


func get_objectives_text() -> Dictionary:
	var lines: Array[String] = []
	match _current_task:
		TaskState.TASK1_SURVEY:
			var status := " (%d/%d)" % [_survey_completed_count, SURVEY_CELLS.size()]
			lines.append("- 完成 3 个勘测点%s" % status)
			lines.append("- 李春在候选桥位执行「相水定址」")
			lines.append("- 至少 1 名测量工进入撤离区并结束回合")
		TaskState.TASK2_BRIDGE:
			lines.append("- 完成 3 个勘测点 (3/3)")
			var status := " (0/1)" if not _bridge_confirmed else " (1/1)"
			lines.append("- 李春在候选桥位执行「相水定址」%s" % status)
			lines.append("- 至少 1 名测量工进入撤离区并结束回合")
		TaskState.TASK3_EVAC:
			lines.append("- 完成 3 个勘测点 (3/3)")
			lines.append("- 李春在候选桥位执行「相水定址」 (1/1)")
			var evac_done := _is_surveyor_at_evac()
			var status := " (0/1)" if not evac_done else " (1/1)"
			lines.append("- 至少 1 名测量工进入撤离区并结束回合%s" % status)
	return {
		"victory": lines,
		"defeat": [
			"- 李春倒下",
			"- 两名测量工全部倒下",
			"- 超过第 20 回合仍未完成撤离",
		],
	}


func check_defeat() -> String:
	# 李春倒下
	if not is_instance_valid(_li_chun):
		return "李春倒下"
	var lc := _li_chun as Unit
	if lc.combat_stats and not lc.combat_stats.is_alive():
		return "李春倒下"
	# 两名测量工全部倒下
	var a_dead := not is_instance_valid(_survey_a) or not (_survey_a as Unit).combat_stats.is_alive()
	var b_dead := not is_instance_valid(_survey_b) or not (_survey_b as Unit).combat_stats.is_alive()
	if a_dead and b_dead:
		return "两名测量工全部倒下"
	# 超过第 20 回合
	if round_number > 20:
		return "超过第 20 回合仍未完成撤离"
	return ""


func check_victory() -> bool:
	if _current_task != TaskState.TASK3_EVAC:
		return false
	if not _bridge_confirmed:
		return false
	return _is_surveyor_at_evac()


func _is_surveyor_at_evac() -> bool:
	for surveyor in [_survey_a, _survey_b]:
		if is_instance_valid(surveyor) and surveyor is Unit:
			var u := surveyor as Unit
			if u.combat_stats and u.combat_stats.is_alive() and u.cell == EVAC_CELL:
				return true
	return false


func _on_level_ready() -> void:

	# ── 李春 ──
	set_unit_skills(_li_chun as Unit, Progress.get_battle_skill_resources(GameState.selected_level))
	setup_unit_stats(_li_chun as Unit, "李春", 130, 24, 100, 8, Enums.Element.NONE, 0, true)

	# ── 测量工 ──
	set_unit_skills(_survey_a as Unit, [_sk_staff, _sk_survey])
	setup_unit_stats(_survey_a as Unit, "测量工", 80, 12, 85, 10)

	set_unit_skills(_survey_b as Unit, [_sk_staff, _sk_survey])
	setup_unit_stats(_survey_b as Unit, "测量工", 80, 12, 85, 10)

	# ── 工匠 ──
	set_unit_skills(_craftsman_a as Unit, [_sk_mallet, _sk_guard])
	setup_unit_stats(_craftsman_a as Unit, "工匠", 110, 18, 90, 9)

	set_unit_skills(_craftsman_b as Unit, [_sk_mallet, _sk_guard])
	setup_unit_stats(_craftsman_b as Unit, "工匠", 110, 18, 90, 9)
	_apply_persistent_growth_effects()

	# ── 关卡机制初始化 ──
	_setup_survey_points()
	_setup_evac_tile()
	_setup_mission_hint()
	_setup_survey_points_hint()
	Notify.notify("任务目标一：派测量工前往 3 个勘测点施放「踏勘量址」。", Notify.Position.TOP_CENTER, Notify.Style.INFO, 4.0)


func _setup_survey_points() -> void:
	for cell in SURVEY_CELLS:
		var tile := _make_survey_point_tile()
		tile.name = "SurveyPoint_%d_%d" % [cell.x, cell.y]
		register_special_tile(tile, cell)
		_survey_points.append(tile)
		tile.survey_completed.connect(_on_survey_point_completed)


func _make_survey_point_tile() -> SurveyPointTile:
	var tile := SurveyPointTile.new()
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([0, -16, 16, -8, 0, 0, -16, -8])
	tile.add_child(visual)
	return tile


func _setup_evac_tile() -> void:
	_evac_tile = _make_special_tile(COLOR_EVAC)
	_evac_tile.name = "EvacuationTile"
	register_special_tile(_evac_tile, EVAC_CELL)


func _make_special_tile(color: Color) -> SpecialTile:
	var tile := SpecialTile.new()
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([0, -16, 16, -8, 0, 0, -16, -8])
	visual.color = color
	tile.add_child(visual)
	return tile


func _setup_mission_hint() -> void:
	_mission_hint_label = Label.new()
	_mission_hint_label.name = "MissionHint"
	_mission_hint_label.anchors_preset = Control.PRESET_TOP_WIDE
	_mission_hint_label.offset_top = 36
	_mission_hint_label.offset_bottom = 66
	_mission_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mission_hint_label.add_theme_font_size_override("font_size", 18)
	_mission_hint_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_mission_hint_label.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.1))
	_mission_hint_label.add_theme_constant_override("outline_size", 4)
	gui.add_child(_mission_hint_label)
	_update_mission_hint()


func _setup_survey_points_hint() -> void:
	_survey_points_label = Label.new()
	_survey_points_label.name = "SurveyPointsHint"
	_survey_points_label.anchors_preset = Control.PRESET_TOP_LEFT
	_survey_points_label.offset_left = 18
	_survey_points_label.offset_top = 84
	_survey_points_label.offset_right = 320
	_survey_points_label.offset_bottom = 200
	_survey_points_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_survey_points_label.add_theme_font_size_override("font_size", 16)
	_survey_points_label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
	_survey_points_label.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.08))
	_survey_points_label.add_theme_constant_override("outline_size", 3)
	gui.add_child(_survey_points_label)
	_update_survey_points_hint()


func _update_mission_hint() -> void:
	if _mission_hint_label == null:
		return
	match _current_task:
		TaskState.TASK1_SURVEY:
			_mission_hint_label.text = "任务目标一，完成3个勘测点【%d/%d】" % [_survey_completed_count, SURVEY_CELLS.size()]
		TaskState.TASK2_BRIDGE:
			_mission_hint_label.text = "任务目标二，李春前往地图中心使用「相水定址」【%s】" % ("0/1" if not _bridge_confirmed else "1/1")
		TaskState.TASK3_EVAC:
			var evac_done := _is_surveyor_at_evac()
			_mission_hint_label.text = "任务目标三，至少让一名测量工人撤离【%s】" % ("0/1" if not evac_done else "1/1")


func _update_survey_points_hint() -> void:
	if _survey_points_label == null:
		return
	var lines: Array[String] = ["已勘测点位："]
	for cell in SURVEY_CELLS:
		var tile := _special_tile_map.get(cell) as SurveyPointTile
		var done := tile != null and tile.completed
		var prefix := "[已完成]" if done else "[未完成]"
		lines.append("%s (%d, %d)" % [prefix, cell.x, cell.y])
	_survey_points_label.text = "\n".join(lines)


func _on_survey_point_completed(tile: SurveyPointTile) -> void:
	_survey_completed_count += 1
	_update_mission_hint()
	_update_survey_points_hint()
	Notify.notify("勘测点 %s 已完成！（%d/%d）" % [str(tile.cell), _survey_completed_count, SURVEY_CELLS.size()], Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 3.0)
	if _survey_completed_count >= SURVEY_CELLS.size():
		_advance_to_task2()


func _advance_to_task2() -> void:
	_current_task = TaskState.TASK2_BRIDGE
	Notify.notify("所有勘测点已完成！新的候选桥位已出现在地图中心。", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 4.0)
	_spawn_bridge_tile()
	_update_mission_hint()
	_show_objectives_if_not_open()
	_focus_camera_after_delay(BRIDGE_CELL)


func _spawn_bridge_tile() -> void:
	_bridge_tile = _make_bridge_tile()
	_bridge_tile.name = "BridgeSiteTile"
	register_special_tile(_bridge_tile, BRIDGE_CELL)


func _make_bridge_tile() -> SpecialTile:
	var tile := SpecialTile.new()
	tile.tile_color = COLOR_BRIDGE

	var outer := Polygon2D.new()
	outer.name = "Visual"
	outer.polygon = PackedVector2Array([0, -22, 22, -10, 0, 2, -22, -10])
	outer.color = COLOR_BRIDGE
	tile.add_child(outer)

	var inner := Polygon2D.new()
	inner.polygon = PackedVector2Array([0, -14, 14, -7, 0, 0, -14, -7])
	inner.color = Color(1.0, 0.97, 0.75, 0.92)
	inner.position = Vector2(0, -2)
	tile.add_child(inner)

	return tile


func _advance_to_task3() -> void:
	_current_task = TaskState.TASK3_EVAC
	Notify.notify("相水定址完成！请指挥测量工前往撤离点 (23, 19)。", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 4.0)
	_update_mission_hint()
	_show_objectives_if_not_open()
	_focus_camera_after_delay(EVAC_CELL)


func _show_objectives_if_not_open() -> void:
	if not _objectives_open:
		show_objectives()


func _focus_camera_after_delay(cell: Vector2i) -> void:
	# 延迟到技能演出结束后再移动镜头，避免与基类的镜头锁定冲突
	await get_tree().create_timer(0.6).timeout
	await _focus_camera_on_cell(cell, 1.3, 1.2)


func _focus_camera_on_cell(cell: Vector2i, zoom: float = 1.3, duration: float = 1.0) -> void:
	var lv_camera := camera as LevelCamera
	if lv_camera == null:
		return
	var marker := Node2D.new()
	add_child(marker)
	marker.global_position = tilemap.map_to_local(cell)
	lv_camera.lock_on(marker, zoom)
	await get_tree().create_timer(duration).timeout
	lv_camera.unlock()
	marker.queue_free()


func _on_skill_executed(caster: Unit, skill: SkillData, cast_cell: Vector2i, _exec_result: SkillExecutor.ExecuteResult) -> void:
	if skill.extra_effect_id == "complete_survey":
		if _current_task != TaskState.TASK1_SURVEY:
			return
		var tile := _special_tile_map.get(cast_cell) as SurveyPointTile
		if caster.combat_stats.unit_name != "测量工":
			Notify.notify("只有测量工可以完成勘测点。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
			return
		if tile == null:
			Notify.notify("此处不是勘测点，踏勘量址没有记录结果。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.5)
			return
		if tile.completed:
			Notify.notify("该勘测点已经完成过了。", Notify.Position.TOP_CENTER, Notify.Style.INFO, 2.0)
			return
		tile.complete()

	elif skill.extra_effect_id == "read_water":
		if _current_task != TaskState.TASK2_BRIDGE:
			return
		if caster != _li_chun:
			Notify.notify("只有李春可以执行「相水定址」。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
			return
		if cast_cell != BRIDGE_CELL:
			Notify.notify("请前往地图中心的候选桥位执行「相水定址」。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.5)
			return
		_bridge_confirmed = true
		_advance_to_task3()


func _on_unit_moved() -> void:
	if _current_task == TaskState.TASK3_EVAC:
		if _is_surveyor_at_evac():
			_update_mission_hint()
			if not _evac_notified:
				_evac_notified = true
				Notify.notify("测量工已抵达撤离点！", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 3.0)
			_check_win_lose()
		else:
			_update_mission_hint()


func _nearest_walkable(target: Vector2i) -> Vector2i:
	if movement_manager.get_movement_cost(target) != TileType.IMPASSABLE:
		return target
	for radius in range(1, 6):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var candidate := target + Vector2i(dx, dy)
				if movement_manager.get_movement_cost(candidate) != TileType.IMPASSABLE:
					return candidate
	return target


func _get_ai_context() -> Dictionary:
	return {
		"escort_units": [_survey_a, _survey_b],
	}


func get_post_level_growth_options() -> Array[Dictionary]:
	return [
		{"id": "growth_training_mobilize", "name": "操练与动员", "description": "全体我方最大生命值 +10，行动力上限 +5"},
		{"id": "growth_maps_measures", "name": "习图记尺", "description": "李春基础攻击力 +4，规尺击伤害倍率 +0.05"},
		{"id": "growth_river_master", "name": "请益河工", "description": "李春获得束桩缓波，可替换规尺击或木楔勘岸"},
		{"id": "growth_stone_reinforce", "name": "备石加固", "description": "工匠的捍作护行持续时间 +1 回合"},
	]


func _apply_persistent_growth_effects() -> void:
	if Progress.has_growth_option("growth_training_mobilize"):
		for unit in get_friendly_units():
			apply_unit_growth_bonus(unit, 10, 0, 5)
	if Progress.has_growth_option("growth_maps_measures"):
		var hero_unit := get_hero_unit()
		apply_unit_growth_bonus(hero_unit, 0, 4, 0)
		modify_unit_skill(hero_unit, "lc_rule_strike", {"damage_ratio": 1.05})
	if Progress.has_growth_option("growth_stone_reinforce"):
		for unit in get_friendly_units():
			if unit.combat_stats.unit_name == "工匠":
				modify_unit_skill(unit, "cg_guard_the_works", {"duration_turns": 3})
