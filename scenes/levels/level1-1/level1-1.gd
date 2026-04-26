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

# ── 教程引导资源 ──
var _li_chun_portrait: Texture2D = preload("res://assets/face/li_chun.png")
const TUTORIAL_ID := "level1-1"

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
var _survey_markers: Dictionary = {}  # cell → Marker2D
var _survey_completed_count: int = 0
const SURVEY_CELLS: Array[Vector2i] = [Vector2i(-11, 12), Vector2i(-1, 2), Vector2i(10, -10)]

# ── 候选桥位 ──
var _bridge_confirmed: bool = false
var _bridge_tile: SpecialTile = null
var _bridge_marker: Node2D = null
const BRIDGE_CELL: Vector2i = Vector2i(-1, 2)
const COLOR_BRIDGE := Color(0.2, 0.6, 0.95, 0.75)

# ── 撤离区 ──
var _evac_cells: Array[Vector2i] = []
var _evac_marker: Node2D = null
var _evac_notified: bool = false
# 撤离区中心点：地图上旗帜所在格。撤离区是以此为中心的 3×3（9 格）范围。
const EVAC_CENTER_CELL: Vector2i = Vector2i(23, 19)

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
	# 节奏：开场压一下，前期 2–3 回合一波逐步加温，中后期稳定 3 回合一波，
	# 整体展开到 r20，避免早期扎堆也不会拖到新手无事可做。
	return {
		1: [
			{"unit_data": _ud_dark_current, "cell": Vector2i(13, -24), "team_index": ENEMY_TEAM,
			 "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT},
			{"unit_data": _ud_mud_wraith, "cell": Vector2i(10, -19), "team_index": ENEMY_TEAM,
			 "skills": [_sk_crush], "color": COLOR_MUD_WRAITH},
		],
		3: [
			{"unit_data": _ud_whirl_pool, "cell": Vector2i(15, -24), "team_index": ENEMY_TEAM,
			 "skills": [_sk_pull], "color": COLOR_WHIRL_POOL},
		],
		5: [
			{"unit_data": _ud_drift_log, "cell": Vector2i(-19, 21), "team_index": ENEMY_TEAM,
			 "skills": [_sk_timber], "color": COLOR_DRIFT_LOG},
		],
		8: [
			{"unit_data": _ud_mud_wraith, "cell": Vector2i(11, -18), "team_index": ENEMY_TEAM,
			 "skills": [_sk_crush], "color": COLOR_MUD_WRAITH},
		],
		11: [
			{"unit_data": _ud_dark_current, "cell": Vector2i(-24, 20), "team_index": ENEMY_TEAM,
			 "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT},
			{"unit_data": _ud_whirl_pool, "cell": Vector2i(14, -21), "team_index": ENEMY_TEAM,
			 "skills": [_sk_pull], "color": COLOR_WHIRL_POOL},
		],
		14: [
			{"unit_data": _ud_drift_log, "cell": Vector2i(-20, 21), "team_index": ENEMY_TEAM,
			 "skills": [_sk_timber], "color": COLOR_DRIFT_LOG},
		],
		17: [
			{"unit_data": _ud_dark_current, "cell": Vector2i(14, -24), "team_index": ENEMY_TEAM,
			 "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT},
			{"unit_data": _ud_mud_wraith, "cell": Vector2i(-22, 20), "team_index": ENEMY_TEAM,
			 "skills": [_sk_crush], "color": COLOR_MUD_WRAITH},
		],
		20: [
			{"unit_data": _ud_whirl_pool, "cell": Vector2i(13, -24), "team_index": ENEMY_TEAM,
			 "skills": [_sk_pull], "color": COLOR_WHIRL_POOL},
			{"unit_data": _ud_drift_log, "cell": Vector2i(-19, 21), "team_index": ENEMY_TEAM,
			 "skills": [_sk_timber], "color": COLOR_DRIFT_LOG},
		],
	}


func get_objectives_text() -> Dictionary:
	var lines: Array[String] = []
	match _current_task:
		TaskState.TASK1_SURVEY:
			var status := " (%d/%d)" % [_survey_completed_count, SURVEY_CELLS.size()]
			lines.append("- 完成 3 个勘测点%s" % status)
			lines.append("- 李春在勘测点 (-1, 2) 执行「相水定址」")
			lines.append("- 至少 1 名测量工进入撤离区并结束回合")
		TaskState.TASK2_BRIDGE:
			lines.append("- 完成 3 个勘测点 (3/3)")
			var status := " (0/1)" if not _bridge_confirmed else " (1/1)"
			lines.append("- 李春在勘测点 (-1, 2) 执行「相水定址」%s" % status)
			lines.append("- 至少 1 名测量工进入撤离区并结束回合")
		TaskState.TASK3_EVAC:
			lines.append("- 完成 3 个勘测点 (3/3)")
			lines.append("- 李春在勘测点 (-1, 2) 执行「相水定址」 (1/1)")
			var evac_done := _is_surveyor_at_evac()
			var status := " (0/1)" if not evac_done else " (1/1)"
			lines.append("- 至少 1 名测量工进入撤离区并结束回合%s" % status)
	return {
		"victory": lines,
		"defeat": [
			"- 李春倒下",
			"- 两名测量工全部倒下",
			"- 超过第 30 回合仍未完成撤离",
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
	if round_number > 30:
		return "超过第 30 回合仍未完成撤离"
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
			if u.combat_stats and u.combat_stats.is_alive() and u.cell in _evac_cells:
				return true
	return false


func _on_level_ready() -> void:

	# ── 李春 ──
	set_unit_skills(_li_chun as Unit, Progress.get_battle_skill_resources(GameState.selected_level))
	setup_unit_stats(_li_chun as Unit, "李春", 130, 24, 100, 6, Enums.Element.NONE, 0, true)

	# ── 测量工 ──
	set_unit_skills(_survey_a as Unit, [_sk_staff, _sk_survey])
	setup_unit_stats(_survey_a as Unit, "测量工", 80, 12, 85, 9)

	set_unit_skills(_survey_b as Unit, [_sk_staff, _sk_survey])
	setup_unit_stats(_survey_b as Unit, "测量工", 80, 12, 85, 9)

	# ── 工匠 ──
	set_unit_skills(_craftsman_a as Unit, [_sk_mallet, _sk_guard])
	setup_unit_stats(_craftsman_a as Unit, "工匠", 110, 18, 90, 8)

	set_unit_skills(_craftsman_b as Unit, [_sk_mallet, _sk_guard])
	setup_unit_stats(_craftsman_b as Unit, "工匠", 110, 18, 90, 8)
	_apply_persistent_growth_effects()

	# ── 关卡机制初始化 ──
	_setup_survey_points()
	_setup_evac_tile()
	_setup_mission_hint()
	_setup_survey_points_hint()
	# 教程 / 任务提示不能在 BRIEFING 阶段就弹出，否则会与初始目标面板抢输入。
	# 统一订阅 phase_changed，等 BRIEFING → PLAYING 之后再触发。
	phase_changed.connect(_on_phase_changed_for_onboarding)


func _on_phase_changed_for_onboarding(p: int) -> void:
	if p != LevelPhase.PLAYING:
		return
	if Progress.has_seen_tutorial(TUTORIAL_ID):
		Notify.notify("任务目标一：派测量工前往 3 个勘测点施放「踏勘量址」。", Notify.Position.TOP_CENTER, Notify.Style.INFO, 4.0)
	else:
		_run_onboarding()


func _setup_survey_points() -> void:
	# 勘测点标记已在 level1-1.tscn 的 Markers 节点下预置（%SurveyMarker_A/B/C）。
	# 这里按 SURVEY_CELLS 顺序把节点映射回 cell，便于完成时 queue_free。
	var marker_names := ["SurveyMarker_A", "SurveyMarker_B", "SurveyMarker_C"]
	for i in SURVEY_CELLS.size():
		var cell := SURVEY_CELLS[i]
		var tile := _make_survey_point_tile()
		tile.name = "SurveyPoint_%d_%d" % [cell.x, cell.y]
		register_special_tile(tile, cell)
		_survey_points.append(tile)
		tile.survey_completed.connect(_on_survey_point_completed)
		_survey_markers[cell] = get_node("Markers/" + marker_names[i])


func _make_survey_point_tile() -> SurveyPointTile:
	var tile := SurveyPointTile.new()
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([0, -16, 16, -8, 0, 0, -16, -8])
	tile.add_child(visual)
	return tile


func _setup_evac_tile() -> void:
	_evac_cells.clear()
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			_evac_cells.append(EVAC_CENTER_CELL + Vector2i(dx, dy))
	# 不再为 3×3 的撤离区每格染红：现在仅靠中心的 EvacMarker 强调位置。
	_spawn_evac_marker()


## 撤离区中心的文字标记（已在 level1-1.tscn 中预置为仅文字）。
func _spawn_evac_marker() -> void:
	_evac_marker = get_node("Markers/EvacMarker")


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
			_mission_hint_label.text = "任务目标二，李春前往勘测点 (-1, 2) 使用「相水定址」【%s】" % ("0/1" if not _bridge_confirmed else "1/1")
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
	var marker: Node2D = _survey_markers.get(tile.cell)
	if marker != null and is_instance_valid(marker):
		marker.queue_free()
		_survey_markers.erase(tile.cell)
	Notify.notify("勘测点 %s 已完成！（%d/%d）" % [str(tile.cell), _survey_completed_count, SURVEY_CELLS.size()], Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 3.0)
	if _survey_completed_count >= SURVEY_CELLS.size():
		_advance_to_task2()


func _advance_to_task2() -> void:
	_current_task = TaskState.TASK2_BRIDGE
	_spawn_bridge_tile()
	_update_mission_hint()
	# 让勘测完成的弹字与技能动画过完再开对话。
	await get_tree().create_timer(0.5).timeout
	await play_dialogue([
		_lc_line("三处读数齐了。河心那一段水势最急，也最宜起拱——就是 (-1, 2) 那块。"),
		_lc_line("我亲自过去走一趟，用「相水定址」把桥位落定。"),
	])
	Notify.notify("所有勘测点已完成！请李春前往勘测点 (-1, 2) 执行「相水定址」。", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 4.0)
	_show_objectives_if_not_open()
	_focus_camera_after_delay(BRIDGE_CELL)


func _spawn_bridge_tile() -> void:
	var old_tile = _special_tile_map.get(BRIDGE_CELL)
	if old_tile != null and is_instance_valid(old_tile):
		old_tile.queue_free()
	_bridge_tile = _make_bridge_tile()
	_bridge_tile.name = "BridgeSiteTile"
	register_special_tile(_bridge_tile, BRIDGE_CELL)
	_spawn_bridge_marker()


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


func _spawn_bridge_marker() -> void:
	_bridge_marker = get_node("Markers/BridgeMarker")
	_bridge_marker.visible = true


func _advance_to_task3() -> void:
	_current_task = TaskState.TASK3_EVAC
	_update_mission_hint()
	await get_tree().create_timer(0.5).timeout
	await play_dialogue([
		_lc_line("桥位既定，剩下的是图纸的事。此地非久留之处——测量工带着读数先撤。"),
		_lc_line("桥头的旗帜那里是撤离区，旗帜周围 3×3 都算。让至少一人进去，并在那里站到回合末，这趟就算成了。"),
	])
	Notify.notify("相水定址完成！请指挥测量工前往撤离区（桥头旗帜周围 3×3）。", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 4.0)
	_show_objectives_if_not_open()
	_focus_camera_after_delay(EVAC_CENTER_CELL)


func _show_objectives_if_not_open() -> void:
	if not has_overlay():
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
			Notify.notify("请前往勘测点 (-1, 2) 执行「相水定址」。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.5)
			return
		_bridge_confirmed = true
		if _bridge_marker != null and is_instance_valid(_bridge_marker):
			_bridge_marker.queue_free()
			_bridge_marker = null
		_advance_to_task3()


func _on_unit_moved() -> void:
	if _current_task == TaskState.TASK3_EVAC:
		if _is_surveyor_at_evac():
			_update_mission_hint()
			if not _evac_notified:
				_evac_notified = true
				Notify.notify("测量工已抵达撤离区！", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 3.0)
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
	return Progress.get_level_growth_options("关卡1-1")


# 持久成长选项的应用逻辑统一在 base_level._apply_persistent_growth_effects 中处理。


# ─────────────────────────────────────────────
# 新手引导（首次进入第一关时播放一次）
# ─────────────────────────────────────────────

## 首次进入第一关触发的软引导：对话说明 + 等待玩家做动作；动作完成则进下一步。
## 流程：选中单位 → 移动 → 放技能 → 结束回合 → 回到玩家回合 → 引流到右上角规则说明。
##
## 时序协议：BaseLevel 的状态机已保证本方法只在 `phase_changed(PLAYING)` 触发后才运行，
## 因此不会与初始 BRIEFING 目标面板抢输入。所有 await 均基于 self-signal，节点被 queue_free
## 时协程静默死亡，不会触碰 freed node。
func _run_onboarding() -> void:
	# ── 步骤 1：欢迎 + 选中 ──
	await play_dialogue([
		_lc_line("赵县的洨河，我们要在这里起一座石桥。先让我看看你熟不熟悉这场仗的规矩。"),
		_lc_line("左键点一下我，就能选中我——左键用来确认，右键或 Esc 用来取消。"),
	])
	if is_phase_ended(): return
	Notify.notify("左键点击李春（或任意己方单位）。", Notify.Position.TOP_CENTER, Notify.Style.INFO, 8.0)
	while selected_unit == null:
		await selection_changed
		if is_phase_ended(): return

	# ── 步骤 2：看状态栏 + 移动 ──
	await play_dialogue([
		_lc_line("屏幕底下的状态栏里：左边是血量 HP 和行动力 AP，右边是可用技能，还有我的当前属性与固有属性。"),
		_lc_line("地图上高亮的格子，就是这回合能走到的范围。左键点其中一格试试。"),
	])
	if is_phase_ended(): return
	Notify.notify("左键点击一个高亮格让单位走过去。", Notify.Position.TOP_CENTER, Notify.Style.INFO, 8.0)
	await unit_move_completed
	if is_phase_ended(): return

	# ── 步骤 3：AP + 技能 ──
	await play_dialogue([
		_lc_line("走路花的是 AP，剩下的 AP 还能放技能。点状态栏右边的技能图标，再左键点想施放的位置。"),
		_lc_line("技能不只能打人。先挑一块空地放一下感受感受——瞄错了就按右键或 Esc 取消。"),
		_lc_line("熟了之后，再朝敌人所在的格子来一下，看看命中后会发生什么。"),
	])
	if is_phase_ended(): return
	Notify.notify("点技能图标 → 左键点目标（先试空地，再试敌人）。", Notify.Position.TOP_CENTER, Notify.Style.INFO, 12.0)
	await skill_executed
	if is_phase_ended(): return

	# ── 步骤 4：结束回合 ──
	await play_dialogue([
		_lc_line("不错。等全队都动完了，点右下角的「结束回合」，把这轮交给敌人。"),
	])
	if is_phase_ended(): return
	Notify.notify("按右下角「结束回合」结束本回合。", Notify.Position.TOP_CENTER, Notify.Style.INFO, 12.0)
	while true:
		var team_idx: int = await team_turn_started
		if is_phase_ended(): return
		if team_idx == 0:
			break

	# ── 步骤 5：引流到右上角规则说明 + 任务 ──
	await play_dialogue([
		_lc_line("基本功就这些。五行流转、化势反应、地形消耗这些细节——点右上角的 📖，规则说明里都写着。"),
		_lc_line("这一关你要做的事，是让测量工到三个勘测点上用「踏勘量址」标记。接下来就看你的了。"),
	])
	if is_phase_ended(): return

	Notify.notify("任务目标一：派测量工前往 3 个勘测点施放「踏勘量址」。", Notify.Position.TOP_CENTER, Notify.Style.INFO, 4.0)

	Progress.mark_tutorial_seen(TUTORIAL_ID)


## 李春对话单行构造的小帮手：自动带头像，放左侧。
func _lc_line(text: String) -> DialogueLine:
	return DialogueLine.create("李春", text, _li_chun_portrait, "left")
