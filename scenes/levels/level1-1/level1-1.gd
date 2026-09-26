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

# ── 关卡任务链（TaskChain：survey → bridge → evac）──
var _task_chain: TaskChain = TaskChain.new()

# ── 勘测点（InteractionTile 参数化交互）──
var _interactions: Array[InteractionTile] = []
var _survey_markers: Dictionary = {}  # cell → Marker2D
var _survey_completed_count: int = 0
const SURVEY_CELLS: Array[Vector2i] = [Vector2i(-11, 12), Vector2i(-1, 2), Vector2i(10, -10)]
const COLOR_SURVEY_INCOMPLETE := Color(0.9, 0.8, 0.2, 0.6)
const COLOR_SURVEY_COMPLETE := Color(0.2, 0.85, 0.3, 0.6)

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


# 波次表（WaveSpawns，Step 4.7）：节奏模板外置 data/stages/chapter1_stage1/wave_spawns.tres。
# 节奏：开场压一下，前期 2–3 回合一波逐步加温，中后期稳定 3 回合一波，
# 整体展开到 r20，避免早期扎堆也不会拖到新手无事可做。
var _wave_spawns: WaveSpawns = preload("res://data/stages/chapter1_stage1/wave_spawns.tres")

# 我方属性表（Step 4.8）：李春 / 测量工 / 工匠 的数值外置 data/units/roster_level1-1.tres。
var _roster: UnitRoster = preload("res://data/units/roster_level1-1.tres")


func get_wave_config() -> Dictionary:
	var waves: Dictionary = {}
	for res in _wave_spawns.entries:
		var entry := res as WaveEntry
		if entry == null:
			continue
		var unit_bundle := _resolve_wave_unit(entry.unit_kind)
		if unit_bundle.is_empty():
			push_warning("wave_spawns: 未知 unit_kind '%s'" % entry.unit_kind)
			continue
		if entry.cell == WaveEntry.NO_CELL:
			push_warning("wave_spawns: 条目缺 cell（unit_kind '%s'）" % entry.unit_kind)
			continue
		var round_num: int = entry.round_number
		if not waves.has(round_num):
			waves[round_num] = []
		waves[round_num].append({
			"unit_data": unit_bundle["unit_data"],
			"cell": entry.cell,
			"team_index": ENEMY_TEAM,
			"skills": unit_bundle["skills"],
			"color": unit_bundle["color"],
		})
	return waves


# unit_kind → (UnitData, 技能表, 敌方颜色)。波次模板只写 kind，具体配置在此（1-4 同款解析层）。
func _resolve_wave_unit(kind: String) -> Dictionary:
	match kind:
		"dark_current":
			return {"unit_data": _ud_dark_current, "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT}
		"whirl_pool":
			return {"unit_data": _ud_whirl_pool, "skills": [_sk_pull], "color": COLOR_WHIRL_POOL}
		"bank_mud_wraith":
			return {"unit_data": _ud_mud_wraith, "skills": [_sk_crush], "color": COLOR_MUD_WRAITH}
		"drift_log_pack":
			return {"unit_data": _ud_drift_log, "skills": [_sk_timber], "color": COLOR_DRIFT_LOG}
	return {}


func get_objectives_text() -> Dictionary:
	return {
		"victory": _task_chain.get_objective_lines(),
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
	if not _task_chain.is_at_id(&"evac"):
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
	_task_chain.setup(self)
	_task_chain.configure(_build_task_chain_tasks())

	# ── 李春 / 测量工 / 工匠（属性外置 data/units/roster_level1-1.tres，走共享装配底座）──
	var factory := _get_unit_factory()
	factory.setup_hero_unit(_li_chun as Unit, _roster.find("李春"))
	factory.setup_ally_group([_survey_a, _survey_b], [_sk_staff, _sk_survey], _roster.find("测量工"))
	factory.setup_ally_group([_craftsman_a, _craftsman_b], [_sk_mallet, _sk_guard], _roster.find("工匠"))
	_apply_persistent_growth_effects()

	# ── 关卡机制初始化 ──
	_setup_survey_points()
	_setup_evac_tile()
	_setup_mission_hint()
	_setup_survey_points_hint()
	# 教程 / 任务提示不能在 BRIEFING 阶段就弹出，否则会与初始目标面板抢输入。
	# 统一订阅 phase_changed，等 BRIEFING → PLAYING 之后再触发。
	phase_changed.connect(_on_phase_changed_for_onboarding)


# ─────────────────────────────────────────────
# 任务链（TaskChain）数据与文案
# ─────────────────────────────────────────────

## 任务链数据：survey → bridge → evac。目标 / 提示文案与旧 TaskState 版逐字一致。
func _build_task_chain_tasks() -> Array[Dictionary]:
	return [
		TaskChain.task(&"survey", _obj_survey, _hint_survey, Callable(), SURVEY_CELLS[0]),
		TaskChain.task(&"bridge", _obj_bridge, _hint_bridge, _on_enter_bridge, BRIDGE_CELL),
		TaskChain.task(&"evac", _obj_evac, _hint_evac, _on_enter_evac, EVAC_CENTER_CELL),
	]


func _obj_survey(mode: int) -> String:
	match mode:
		TaskChain.DisplayMode.DONE:
			return "- 完成 3 个勘测点 (3/3)"
		TaskChain.DisplayMode.ACTIVE:
			var status := " (%d/%d)" % [_survey_completed_count, SURVEY_CELLS.size()]
			return "- 完成 3 个勘测点%s" % status
		_:
			return "- 完成 3 个勘测点"


func _obj_bridge(mode: int) -> String:
	match mode:
		TaskChain.DisplayMode.DONE:
			return "- 李春在勘测点 (-1, 2) 执行「相水定址」 (1/1)"
		TaskChain.DisplayMode.ACTIVE:
			return "- 李春在勘测点 (-1, 2) 执行「相水定址」%s" % (" (0/1)" if not _bridge_confirmed else " (1/1)")
		_:
			return "- 李春在勘测点 (-1, 2) 执行「相水定址」"


func _obj_evac(mode: int) -> String:
	if mode == TaskChain.DisplayMode.PENDING:
		return "- 至少 1 名测量工进入撤离区并结束回合"
	var evac_done := _is_surveyor_at_evac()
	return "- 至少 1 名测量工进入撤离区并结束回合%s" % (" (0/1)" if not evac_done else " (1/1)")


func _hint_survey() -> String:
	return "任务目标一，完成3个勘测点【%d/%d】" % [_survey_completed_count, SURVEY_CELLS.size()]


func _hint_bridge() -> String:
	return "任务目标二，李春前往勘测点 (-1, 2) 使用「相水定址」【%s】" % ("0/1" if not _bridge_confirmed else "1/1")


func _hint_evac() -> String:
	var evac_done := _is_surveyor_at_evac()
	return "任务目标三，至少让一名测量工人撤离【%s】" % ("0/1" if not evac_done else "1/1")


func _on_phase_changed_for_onboarding(p: int) -> void:
	if p != LevelPhase.PLAYING:
		return
	if Progress.has_seen_tutorial(TUTORIAL_ID):
		if not await _ask_tutorial_replay():
			Notify.hint("任务目标一：派测量工前往 3 个勘测点施放「踏勘量址」。", 4.0)
			return
	_run_onboarding()


func _setup_survey_points() -> void:
	# 勘测点标记已在 level1-1.tscn 的 Markers 节点下预置（%SurveyMarker_A/B/C）。
	# 这里按 SURVEY_CELLS 顺序把节点映射回 cell，便于完成时 queue_free。
	# 交互条件（踏勘量址 / 测量工 / 一次性）已参数化进 InteractionTile。
	var marker_names := ["SurveyMarker_A", "SurveyMarker_B", "SurveyMarker_C"]
	for i in SURVEY_CELLS.size():
		var cell := SURVEY_CELLS[i]
		var tile := InteractionTile.create(
			[cell], &"complete_survey", _survey_unit_filter, _on_survey_completed_effect)
		tile.name = "SurveyPoint_%d_%d" % [cell.x, cell.y]
		tile.tile_color = COLOR_SURVEY_INCOMPLETE
		var visual := Polygon2D.new()
		visual.name = "Visual"
		visual.polygon = PackedVector2Array([0, -16, 16, -8, 0, 0, -16, -8])
		tile.add_child(visual)
		tile.on_cell_miss = _survey_cell_miss
		tile.on_already = _survey_already_done
		_special_tile_registry.register(tile, cell)
		_interactions.append(tile)
		_survey_markers[cell] = get_node("Markers/" + marker_names[i])


## 勘测点交互闸门：仅「勘测」任务阶段的测量工可用（旧 _on_skill_executed 分支逐字）。
func _survey_unit_filter(caster: Unit) -> bool:
	if not _task_chain.is_at_id(&"survey"):
		return false
	if caster.combat_stats.unit_name != "测量工":
		Notify.notify("只有测量工可以完成勘测点。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
		return false
	return true


func _survey_cell_miss() -> void:
	Notify.notify("此处不是勘测点，踏勘量址没有记录结果。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.5)


func _survey_already_done() -> void:
	Notify.hint("该勘测点已经完成过了。", 2.0)


## 勘测点完成效果（旧 tile.complete() 变色 + _on_survey_point_completed）。
func _on_survey_completed_effect(tile: InteractionTile, _caster: Unit, _cell: Vector2i) -> void:
	tile.tile_color = COLOR_SURVEY_COMPLETE
	_on_survey_point_completed(tile)


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
	_mission_hint_label = LevelHudFactory.create_mission_hint_label()
	gui.add_child(_mission_hint_label)
	_update_mission_hint()


func _setup_survey_points_hint() -> void:
	_survey_points_label = LevelHudFactory.create_side_hint_label("SurveyPointsHint", 200)
	gui.add_child(_survey_points_label)
	_update_survey_points_hint()


func _update_mission_hint() -> void:
	if _mission_hint_label == null:
		return
	_mission_hint_label.text = _task_chain.get_current_hint()


func _update_survey_points_hint() -> void:
	if _survey_points_label == null:
		return
	var lines: Array[String] = ["已勘测点位："]
	for cell in SURVEY_CELLS:
		var tile := _special_tile_map.get(cell) as InteractionTile
		var done := tile != null and tile.completed
		var prefix := "[已完成]" if done else "[未完成]"
		lines.append("%s (%d, %d)" % [prefix, cell.x, cell.y])
	_survey_points_label.text = "\n".join(lines)


func _on_survey_point_completed(tile: InteractionTile) -> void:
	_survey_completed_count += 1
	_update_mission_hint()
	_update_survey_points_hint()
	var marker: Node2D = _survey_markers.get(tile.cell)
	if marker != null and is_instance_valid(marker):
		marker.queue_free()
		_survey_markers.erase(tile.cell)
	Notify.success("勘测点 %s 已完成！（%d/%d）" % [str(tile.cell), _survey_completed_count, SURVEY_CELLS.size()], 3.0)
	if _survey_completed_count >= SURVEY_CELLS.size():
		_task_chain.advance_next()


## 进入「桥位」任务的进场动作（旧 _advance_to_task2 主体）。
func _on_enter_bridge() -> void:
	_spawn_bridge_tile()
	_update_mission_hint()
	# 让勘测完成的弹字与技能动画过完再开对话。
	await get_tree().create_timer(0.5).timeout
	await play_dialogue([
		_lc_line("三处读数齐了。河心那一段水势最急，也最宜起拱——就是 (-1, 2) 那块。"),
		_lc_line("我亲自过去走一趟，用「相水定址」把桥位落定。"),
	])
	Notify.success("所有勘测点已完成！请李春前往勘测点 (-1, 2) 执行「相水定址」。", 4.0)
	_show_objectives_if_not_open()
	_focus_camera_after_delay(BRIDGE_CELL)


func _spawn_bridge_tile() -> void:
	var old_tile = _special_tile_map.get(BRIDGE_CELL)
	if old_tile != null and is_instance_valid(old_tile):
		old_tile.queue_free()
	_bridge_tile = _make_bridge_tile()
	_bridge_tile.name = "BridgeSiteTile"
	_special_tile_registry.register(_bridge_tile, BRIDGE_CELL)
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


## 进入「撤离」任务的进场动作（旧 _advance_to_task3 主体）。
func _on_enter_evac() -> void:
	_update_mission_hint()
	await get_tree().create_timer(0.5).timeout
	await play_dialogue([
		_lc_line("桥位既定，剩下的是图纸的事。此地非久留之处——测量工带着读数先撤。"),
		_lc_line("桥头的旗帜那里是撤离区，旗帜周围 3×3 都算。让至少一人进去，并在那里站到回合末，这趟就算成了。"),
	])
	Notify.success("相水定址完成！请指挥测量工前往撤离区（桥头旗帜周围 3×3）。", 4.0)
	_show_objectives_if_not_open()
	_focus_camera_after_delay(EVAC_CENTER_CELL)


func _show_objectives_if_not_open() -> void:
	if not has_overlay():
		_get_ui_bridge().show_objectives()


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
	# 勘测点交互（complete_survey）走 InteractionTile 参数化派发
	if InteractionTile.dispatch_skill(_interactions, caster, skill, cast_cell):
		return

	if skill.extra_effect_id == "read_water":
		if not _task_chain.is_at_id(&"bridge"):
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
		_task_chain.advance_next()


func _on_unit_moved() -> void:
	if _task_chain.is_at_id(&"evac"):
		if _is_surveyor_at_evac():
			_update_mission_hint()
			if not _evac_notified:
				_evac_notified = true
				Notify.success("测量工已抵达撤离区！", 3.0)
			_get_objectives_tracker().check_win_lose()
		else:
			_update_mission_hint()


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
## 步进数据在 _build_onboarding_steps()，由 TutorialRunner.run_steps 驱动。
##
## 时序协议：BaseLevel 的状态机已保证本方法只在 `phase_changed(PLAYING)` 触发后才运行，
## 因此不会与初始 BRIEFING 目标面板抢输入。所有 await 均基于 self-signal，节点被 queue_free
## 时协程静默死亡，不会触碰 freed node。
func _run_onboarding() -> void:
	set_tutorial_onboarding_active(true)
	await _get_tutorial_runner().run_steps(_build_onboarding_steps())
	if not is_phase_ended():
		Progress.mark_tutorial_seen(TUTORIAL_ID)
	_finish_onboarding()


## 新手引导步进数据。顺序 / 文案 / 等待条件与旧手写版一一对应。
func _build_onboarding_steps() -> Array[TutorialStep]:
	var steps: Array[TutorialStep] = []
	# ── 步骤 1：欢迎 + 选中 ──
	steps.append(TutorialStep.create("select_hero", [
		{"text": "接下来的引导非常重要，我将为你介绍关卡机制和玩法，与我们能否打赢这场硬仗息息相关。", "can_skip": false},
		{"text": "赵县的洨河，我们要在这里起一座石桥。先让我看看你熟不熟悉这场仗的规矩。"},
		{"text": "左键点一下我，就能选中我——左键用来确认，右键或 Esc 用来取消。"},
	], "左键点击李春（或任意己方单位）。", 8.0,
		TutorialStep.WaitMode.PREDICATE, &"selection_changed",
		func(_args: Array) -> bool: return selected_unit != null))
	# ── 步骤 2：看状态栏 + 移动 ──
	steps.append(TutorialStep.create("move_unit", [
		{"text": "屏幕底下的状态栏里：左边是血量 HP 和行动力 AP，右边是可用技能，还有我的当前属性与固有属性。"},
		{"text": "地图上高亮的格子，就是这回合能走到的范围。左键点其中一格试试。"},
	], "左键点击一个高亮格让单位走过去。", 8.0,
		TutorialStep.WaitMode.SIGNAL, &"unit_move_completed"))
	# ── 步骤 3：AP + 技能 ──
	steps.append(TutorialStep.create("cast_skill", [
		{"text": "走路花的是 AP，剩下的 AP 还能放技能。点状态栏右边的技能图标，再左键点想施放的位置。"},
		{"text": "技能不只能进攻。先挑一块空地放一下感受感受——瞄错了就按右键或 Esc 取消。"},
		{"text": "熟了之后，再朝敌人所在的格子来一下，看看命中后会发生什么。"},
	], "点技能图标 → 左键点目标（先试空地，再试敌人）。", 12.0,
		TutorialStep.WaitMode.SIGNAL, &"skill_executed"))
	# ── 步骤 4：结束回合 ──
	steps.append(TutorialStep.create("end_turn", [
		{"text": "不错。等全队都动完了，点右下角的「结束回合」，把这轮交给敌人。"},
		{"text": "如果回合AP没有消耗完，需要点击两次「结束回合」才能真正结束，这是为了防止误触。"},
	], "按右下角「结束回合」结束本回合。", 12.0,
		TutorialStep.WaitMode.PREDICATE, &"team_turn_started",
		# 等价原 `while true: var team_idx = await team_turn_started; if team_idx == 0: break`
		func(args: Array) -> bool: return not args.is_empty() and args[0] == 0))
	# ── 步骤 4.5：难度可调（基本操作教学结束后的友情提示）──
	steps.append(TutorialStep.create("difficulty_hint", [
		{"text": "基本操作就是这些。再交代一句：屏幕右上角的 ⚙ 是设置（按 Esc 也能打开），里面可以随时调『难度』。"},
		{"text": "觉得吃力就调低一档，觉得没劲就调高一档——敌人的血量和攻击会跟着变，自家不影响。"},
	]))
	# ── 步骤 5：引流到右上角规则说明 + 任务 ──
	steps.append(TutorialStep.create("rules_and_task", [
		{"text": "基本功就这些。五行流转、化势反应、地形消耗这些细节——点右上角的 📖，规则说明里都写着。"},
		{"text": "这一关你要做的事，是让测量工到三个勘测点上用「踏勘量址」标记。接下来就看你的了。"},
	], "任务目标一：派测量工前往 3 个勘测点施放「踏勘量址」。", 4.0))
	return steps


func _finish_onboarding() -> void:
	set_tutorial_onboarding_active(false)
