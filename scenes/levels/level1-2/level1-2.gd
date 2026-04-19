extends BaseLevel
## 第二关《弧拱定式》
##
## 任务四段：TASK1 取参 → TASK2 李春抵达绘样台 → TASK3 执墨定拱 → TASK4 击退 8 只小怪。
## 仿 1-1 使用 SpecialTile + 技能施放式交互。
## 旧制监工为唯一 Boss：不动、不攻击、完全免疫，只做按回合召唤 + 督令增益。

const ParameterPointTile := preload("res://scenes/levels/base_level/parameter_point_tile.gd")

const ENEMY_TEAM := 1
const REQUIRED_DEFEATS := 8
const ENEMY_FIELD_CAP := 5
const TURN_LIMIT := 30

const PARAMETER_CELLS: Array[Vector2i] = [Vector2i(-11, 12), Vector2i(-1, 2), Vector2i(10, -10)]
const PARAMETER_LABELS := ["河宽", "坡度", "石重"]
const DRAFTING_CELLS: Array[Vector2i] = [
	Vector2i(-11, -11), Vector2i(-11, -10),
	Vector2i(-12, -10), Vector2i(-12, -11),
]
const BOSS_CELL := Vector2i(-12, -12)
const ENEMY_SPAWN_ANCHORS: Array[Vector2i] = [Vector2i(13, -24), Vector2i(10, -19)]

const SUMMON_CYCLE: Array[StringName] = [
	&"循旧匠首", &"高拱幻影", &"循旧匠首", &"循旧匠首", &"重墩石像",
]

# ── 敌方颜色（沿用 1-1 的视觉惯例） ──
const COLOR_RULE_GUARD := Color(0.75, 0.55, 0.3)
const COLOR_HIGH_ARCH := Color(0.55, 0.65, 0.95)
const COLOR_HEAVY_PIER := Color(0.65, 0.6, 0.5)
const COLOR_BOSS := Color(0.8, 0.25, 0.25)

enum TaskState { TASK1_PARAMETERS, TASK2_PLATFORM, TASK3_ARCH, TASK4_HUNT }
var _current_task: TaskState = TaskState.TASK1_PARAMETERS

# ── 预加载 ──
var _hero_data: UnitData = preload("res://data/units/hero_li_chun.tres")
var _hero_visual: PackedScene = preload("res://scenes/unit/visual/human/li_chun/li_chun_visual.tscn")
var _rule_guard_data: UnitData = preload("res://data/units/rule_guard_head.tres")
var _heavy_pier_data: UnitData = preload("res://data/units/heavy_pier_statue.tres")
var _high_arch_data: UnitData = preload("res://data/units/high_arch_phantom.tres")
var _boss_data: UnitData = preload("res://data/units/old_method_supervisor.tres")
var _high_arch_visual: PackedScene = preload("res://scenes/unit/visual/monster/高拱幻影/高拱幻影_visual.tscn")

var _staff: SkillData = preload("res://data/skills/sw_staff_end_strike.tres")
var _take_parameters: SkillData = preload("res://data/skills/sw_take_parameters.tres")
var _confirm_parameter: SkillData = preload("res://data/skills/lc_confirm_parameter.tres")
var _ink_set_arch: SkillData = preload("res://data/skills/lc_ink_set_arch.tres")
var _divider_arc: SkillData = preload("res://data/skills/lc_divider_mark_arc.tres")
var _line_lock_arc: SkillData = preload("res://data/skills/lc_line_lock_arc.tres")
var _mallet: SkillData = preload("res://data/skills/cg_mallet_strike.tres")
var _guard: SkillData = preload("res://data/skills/cg_guard_the_works.tres")
var _pull: SkillData = preload("res://data/skills/wp_spiral_pull.tres")
var _crush: SkillData = preload("res://data/skills/bmw_crumbling_bank_crush.tres")

# ── 单位引用 ──
var _li_chun: Unit
var _survey_worker: Unit  # 主测量工（兼容旧代码路径）
var _survey_workers: Array[Unit] = []
var _craftsmen: Array[Unit] = []
var _boss: Unit

# ── 关卡机制 ──
var _parameter_tiles: Dictionary = {}  # cell → ParameterPointTile
var _parameters_done_count: int = 0
var _li_chun_parameter_round: int = -1
var _finalized: bool = false
var _minion_kills: int = 0
var _summon_cycle_index: int = 0
var _pending_summon_bonus: int = 0
var _platform_visit_cache: Dictionary = {}  # instance_id → true
var _drafting_marker: Node2D = null
var _mission_hint_label: Label = null
var _params_status_label: Label = null


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/Player" as Unit
	_survey_worker = $"Entities/Units/SurveyWorker" as Unit
	_survey_workers = [
		_survey_worker,
		$"Entities/Units/SurveyWorkerB" as Unit,
		$"Entities/Units/SurveyWorkerC" as Unit,
	]
	_craftsmen = [
		$"Entities/Units/CraftsmanA" as Unit,
		$"Entities/Units/CraftsmanB" as Unit,
		$"Entities/Units/CraftsmanC" as Unit,
	]
	return [
		{
			"name": "营造队",
			"faction": "好人",
			"controller": "player",
			"units": [_li_chun, _survey_workers[0], _survey_workers[1], _survey_workers[2], _craftsmen[0], _craftsmen[1], _craftsmen[2]],
		},
		{
			"name": "旧制势力",
			"faction": "坏人",
			"controller": "ai",
			"units": [],
		},
	]


func get_objectives_text() -> Dictionary:
	var lines: Array[String] = []
	match _current_task:
		TaskState.TASK1_PARAMETERS:
			var status := " (%d/%d)" % [_parameters_done_count, PARAMETER_CELLS.size()]
			lines.append("- 完成 3 个参数点%s" % status)
			lines.append("- 李春抵达中央绘样台")
			lines.append("- 李春执行「执墨定拱」")
			lines.append("- 累计击退 8 名受驱役敌人")
		TaskState.TASK2_PLATFORM:
			lines.append("- 完成 3 个参数点 (3/3)")
			lines.append("- 李春抵达中央绘样台 (0/1)")
			lines.append("- 李春执行「执墨定拱」")
			lines.append("- 累计击退 8 名受驱役敌人")
		TaskState.TASK3_ARCH:
			lines.append("- 完成 3 个参数点 (3/3)")
			lines.append("- 李春抵达中央绘样台 (1/1)")
			var arch_status := " (0/1)" if not _finalized else " (1/1)"
			lines.append("- 李春执行「执墨定拱」%s" % arch_status)
			lines.append("- 累计击退 8 名受驱役敌人")
		TaskState.TASK4_HUNT:
			lines.append("- 完成 3 个参数点 (3/3)")
			lines.append("- 李春抵达中央绘样台 (1/1)")
			lines.append("- 李春执行「执墨定拱」 (1/1)")
			lines.append("- 累计击退 8 名受驱役敌人 (%d/%d)" % [_minion_kills, REQUIRED_DEFEATS])
	return {
		"victory": lines,
		"defeat": [
			"- 李春倒下",
			"- 超过第 %d 回合" % TURN_LIMIT,
		],
	}


func check_victory() -> bool:
	return _current_task == TaskState.TASK4_HUNT and _minion_kills >= REQUIRED_DEFEATS


func check_defeat() -> String:
	if _li_chun == null or _li_chun.combat_stats == null or not _li_chun.combat_stats.is_alive():
		return "李春倒下"
	if round_number > TURN_LIMIT:
		return "超过第 %d 回合" % TURN_LIMIT
	return ""


func _on_level_ready() -> void:
	_setup_li_chun()
	_setup_allies_from_scene()
	_setup_parameter_tiles()
	_setup_drafting_marker()
	_spawn_boss()
	_spawn_initial_minions()
	_apply_persistent_growth_effects()
	_setup_mission_hint()
	_setup_params_status_hint()

	unit_died.connect(_on_stage_unit_died)
	unit_hp_changed.connect(_on_stage_hp_changed)
	team_turn_started.connect(_on_stage_team_turn_started)
	unit_move_completed.connect(_on_stage_unit_move_completed)

	Notify.notify("派测量工到 3 个参数点施放「测尺取参」。", Notify.Position.TOP_CENTER, Notify.Style.INFO, 3.5)


# ─────────────────────────────────────────────
# 开局配置
# ─────────────────────────────────────────────

func _setup_li_chun() -> void:
	_li_chun.apply_runtime_setup(_hero_data, _hero_visual, Color(1, 0.85, 0, 1))
	var skills: Array[SkillData] = Progress.get_battle_skill_resources(GameState.selected_level)
	# 关卡核心交互 & 分规定弧 默认写入李春技能池（若 Progress 没提供）。
	for mandatory in [_confirm_parameter, _ink_set_arch, _divider_arc]:
		if not _skill_list_contains(skills, mandatory.skill_id):
			skills.append(mandatory)
	set_unit_skills(_li_chun, skills)
	setup_unit_stats(_li_chun, "李春", 130, 24, 100, 8, Enums.Element.NONE, 0, true)


func _setup_allies_from_scene() -> void:
	# 场景里已放好 SurveyWorker*/CraftsmanA-C 节点；位置由场景 position 决定
	# （基类 _reparent_entities_to_obstacles 会按 global_position 吸附到最近格）。
	# 这里只补齐 skills / 数值。
	for sw in _survey_workers:
		set_unit_skills(sw, [_staff, _take_parameters])
		setup_unit_stats(sw, "测量工", 80, 12, 85, 10)
	for craftsman in _craftsmen:
		set_unit_skills(craftsman, [_mallet, _guard])
		setup_unit_stats(craftsman, "工匠", 110, 18, 90, 9)


func _setup_parameter_tiles() -> void:
	# 参数点的脉动标记已在 level1-2.tscn 的 Markers 节点下预置。
	for i in PARAMETER_CELLS.size():
		var cell := PARAMETER_CELLS[i]
		var tile := _make_parameter_tile()
		tile.name = "ParameterPoint_%d_%d" % [cell.x, cell.y]
		tile.parameter_key = StringName(PARAMETER_LABELS[i])
		tile.parameter_label = PARAMETER_LABELS[i]
		register_special_tile(tile, cell)
		_parameter_tiles[cell] = tile
		tile.parameter_completed.connect(_on_parameter_completed)


func _make_parameter_tile() -> ParameterPointTile:
	var tile: ParameterPointTile = ParameterPointTile.new()
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([0, -16, 16, -8, 0, 0, -16, -8])
	tile.add_child(visual)
	return tile


func _setup_drafting_marker() -> void:
	# 4 格中心在 (-11.5, -10.5)（cell 坐标）。
	var center_local := (tilemap.map_to_local(DRAFTING_CELLS[0])
			+ tilemap.map_to_local(DRAFTING_CELLS[1])
			+ tilemap.map_to_local(DRAFTING_CELLS[2])
			+ tilemap.map_to_local(DRAFTING_CELLS[3])) / 4.0
	# 把场景里已有的测绘台 Sprite2D 对齐到绘样台几何中心。
	var platform_sprite: Sprite2D = get_node_or_null("TileMaps/obstacle z=2/测绘台64") as Sprite2D
	if platform_sprite:
		platform_sprite.position = center_local + Vector2(0, -8)

	_drafting_marker = Node2D.new()
	_drafting_marker.name = "DraftingPlatformMarker"
	_drafting_marker.z_as_relative = false
	_drafting_marker.z_index = 40
	_drafting_marker.position = center_local
	add_child(_drafting_marker)
	var outline := Polygon2D.new()
	outline.polygon = PackedVector2Array([0, -20, 32, 0, 0, 20, -32, 0])
	outline.color = Color(0.6, 0.85, 0.95, 0.28)
	_drafting_marker.add_child(outline)


func _spawn_boss() -> void:
	var cell := _nearest_walkable(BOSS_CELL)
	_boss = spawn_unit(_boss_data, cell, ENEMY_TEAM)
	set_unit_skills(_boss, [])
	setup_unit_stats(_boss, _boss_data.unit_name, _boss_data.max_hp, 0, 0, 99, Enums.Element.NONE, 0)


func _spawn_initial_minions() -> void:
	_spawn_minion(&"循旧匠首", _nearest_walkable(ENEMY_SPAWN_ANCHORS[0]))
	_spawn_minion(&"高拱幻影", _nearest_walkable(ENEMY_SPAWN_ANCHORS[0] + Vector2i(1, 1)))
	_spawn_minion(&"循旧匠首", _nearest_walkable(ENEMY_SPAWN_ANCHORS[1]))
	_spawn_minion(&"重墩石像", _nearest_walkable(ENEMY_SPAWN_ANCHORS[1] + Vector2i(1, 1)))


# ─────────────────────────────────────────────
# 技能执行响应：关卡交互
# ─────────────────────────────────────────────

func _on_skill_executed(caster: Unit, skill: SkillData, cast_cell: Vector2i, _exec_result: SkillExecutor.ExecuteResult) -> void:
	match skill.extra_effect_id:
		"take_parameter":
			_handle_take_parameter(caster, cast_cell)
		"confirm_parameter":
			_handle_confirm_parameter(caster, cast_cell)
		"ink_set_arch":
			_handle_ink_set_arch(caster, cast_cell)


func _handle_take_parameter(caster: Unit, cast_cell: Vector2i) -> void:
	if not (caster in _survey_workers):
		Notify.notify("只有测量工可以使用「测尺取参」。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
		return
	var tile: ParameterPointTile = _parameter_tiles.get(cast_cell)
	if tile == null:
		Notify.notify("此处不是参数点。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
		return
	if tile.completed:
		Notify.notify("该参数点已完成。", Notify.Position.TOP_CENTER, Notify.Style.INFO, 2.0)
		return
	tile.complete()


func _handle_confirm_parameter(caster: Unit, cast_cell: Vector2i) -> void:
	if caster != _li_chun:
		Notify.notify("只有李春可以使用「参数确认」。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
		return
	var tile: ParameterPointTile = _parameter_tiles.get(cast_cell)
	if tile == null:
		Notify.notify("此处不是参数点。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
		return
	if tile.completed:
		Notify.notify("该参数点已完成。", Notify.Position.TOP_CENTER, Notify.Style.INFO, 2.0)
		return
	if _li_chun_parameter_round == round_number:
		Notify.notify("李春本回合已确认过一次参数。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
		return
	_li_chun_parameter_round = round_number
	tile.complete()


func _handle_ink_set_arch(caster: Unit, cast_cell: Vector2i) -> void:
	if caster != _li_chun:
		Notify.notify("只有李春可以执行「执墨定拱」。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
		return
	if not _all_parameters_done():
		Notify.notify("需先完成全部 3 个参数点。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.5)
		return
	if not (cast_cell in DRAFTING_CELLS):
		Notify.notify("请站在绘样台 2×2 区域上再执行「执墨定拱」。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.5)
		return
	if _finalized:
		return
	_finalized = true
	_advance_to_task4()


func _on_parameter_completed(tile: ParameterPointTile) -> void:
	_parameters_done_count += 1
	Notify.notify("参数点【%s】完成！(%d/%d)" % [tile.parameter_label, _parameters_done_count, PARAMETER_CELLS.size()], Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.5)
	_update_mission_hint()
	_update_params_status_hint()
	if _parameters_done_count >= PARAMETER_CELLS.size() and _current_task == TaskState.TASK1_PARAMETERS:
		_advance_to_task2()


# ─────────────────────────────────────────────
# 任务 UI 提示
# ─────────────────────────────────────────────

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


func _setup_params_status_hint() -> void:
	_params_status_label = Label.new()
	_params_status_label.name = "ParamsStatusHint"
	_params_status_label.anchors_preset = Control.PRESET_TOP_LEFT
	_params_status_label.offset_left = 18
	_params_status_label.offset_top = 84
	_params_status_label.offset_right = 320
	_params_status_label.offset_bottom = 240
	_params_status_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_params_status_label.add_theme_font_size_override("font_size", 16)
	_params_status_label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
	_params_status_label.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.08))
	_params_status_label.add_theme_constant_override("outline_size", 3)
	gui.add_child(_params_status_label)
	_update_params_status_hint()


func _update_mission_hint() -> void:
	if _mission_hint_label == null:
		return
	match _current_task:
		TaskState.TASK1_PARAMETERS:
			_mission_hint_label.text = "任务目标一，完成 3 个参数点【%d/%d】" % [_parameters_done_count, PARAMETER_CELLS.size()]
		TaskState.TASK2_PLATFORM:
			_mission_hint_label.text = "任务目标二，李春前往中央绘样台"
		TaskState.TASK3_ARCH:
			var done := " (1/1)" if _finalized else " (0/1)"
			_mission_hint_label.text = "任务目标三，李春在绘样台执行「执墨定拱」%s" % done
		TaskState.TASK4_HUNT:
			_mission_hint_label.text = "任务目标四，累计击退 8 名受驱役敌人【%d/%d】" % [_minion_kills, REQUIRED_DEFEATS]


func _update_params_status_hint() -> void:
	if _params_status_label == null:
		return
	var lines: Array[String] = ["参数点进度："]
	for i in PARAMETER_CELLS.size():
		var cell := PARAMETER_CELLS[i]
		var tile: ParameterPointTile = _parameter_tiles.get(cell)
		var done := tile != null and tile.completed
		var prefix := "[已完成]" if done else "[未完成]"
		lines.append("%s %s (%d, %d)" % [prefix, PARAMETER_LABELS[i], cell.x, cell.y])
	_params_status_label.text = "\n".join(lines)


# ─────────────────────────────────────────────
# 任务推进
# ─────────────────────────────────────────────

func _advance_to_task2() -> void:
	_current_task = TaskState.TASK2_PLATFORM
	Notify.notify("三处参数已成。请李春前往中央绘样台。", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 3.5)
	_update_mission_hint()
	_show_objectives_if_not_open()


func _advance_to_task3() -> void:
	_current_task = TaskState.TASK3_ARCH
	Notify.notify("李春抵达绘样台！执行「执墨定拱」落定桥法。", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 3.5)
	_update_mission_hint()
	_show_objectives_if_not_open()


func _advance_to_task4() -> void:
	_current_task = TaskState.TASK4_HUNT
	if _drafting_marker != null and is_instance_valid(_drafting_marker):
		_drafting_marker.modulate = Color(1, 1, 1, 0.4)
	Notify.notify("执墨定拱完成！继续击退受驱役之敌，直至 %d 名。" % REQUIRED_DEFEATS, Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 3.5)
	_update_mission_hint()
	_show_objectives_if_not_open()


func _show_objectives_if_not_open() -> void:
	if not has_overlay():
		show_objectives()


func _on_stage_unit_move_completed(unit: Unit) -> void:
	if unit == _li_chun and _current_task == TaskState.TASK2_PLATFORM and unit.cell in DRAFTING_CELLS:
		_advance_to_task3()


# ─────────────────────────────────────────────
# Boss 回合 & 死亡
# ─────────────────────────────────────────────

func _on_stage_team_turn_started(team_index: int) -> void:
	if team_index == ENEMY_TEAM:
		_boss_turn()
	else:
		_scan_platform_visits()


func _scan_platform_visits() -> void:
	# 玩家回合开始（= 敌方回合结束）时扫描小怪占台：每只一次性。
	for unit in teams[ENEMY_TEAM].units:
		if unit == _boss or not (unit is Unit):
			continue
		var minion := unit as Unit
		if minion.combat_stats == null or not minion.combat_stats.is_alive():
			continue
		if not (minion.cell in DRAFTING_CELLS):
			continue
		var id := minion.get_instance_id()
		if _platform_visit_cache.has(id):
			continue
		_platform_visit_cache[id] = true
		_pending_summon_bonus += 1
		Notify.notify("%s 抵达绘样台！Boss 下回合召唤 +1。" % minion.combat_stats.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 2.5)


func _boss_turn() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return

	# 1. 群体督令：所有存活小怪 +10% 伤害本回合
	var minions := _alive_minions()
	for m in minions:
		_apply_minion_buff(m, "rule_group_boost", 1)
	if not minions.is_empty():
		Notify.notify("旧制监工下达【督令·群体】，我方气势大振！", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)

	# 2. 单体督令：选一只 HP 最高的小怪 +30% 伤害本回合
	var single_target := _select_single_buff_target(minions)
	if single_target != null:
		_apply_minion_buff(single_target, "rule_single_boost", 1)
		Notify.notify("旧制监工下达【督令·单体】：%s 伤害+30%%" % single_target.combat_stats.unit_name, Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)

	# 3. 召唤
	var summon_count := 1 + _pending_summon_bonus
	_pending_summon_bonus = 0
	var spawned := 0
	for i in summon_count:
		if _count_minions() >= ENEMY_FIELD_CAP:
			break
		var summon_kind: StringName = SUMMON_CYCLE[_summon_cycle_index % SUMMON_CYCLE.size()]
		_summon_cycle_index += 1
		_spawn_minion(summon_kind, _random_enemy_spawn_cell())
		spawned += 1
	if spawned > 0:
		Notify.notify("旧制监工召唤了 %d 名受驱役之敌。" % spawned, Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 2.0)


func _select_single_buff_target(minions: Array[Unit]) -> Unit:
	var best: Unit = null
	var best_hp := -1
	for m in minions:
		if m.combat_stats.current_hp > best_hp:
			best_hp = m.combat_stats.current_hp
			best = m
	return best


func _apply_minion_buff(target: Unit, status_id: String, duration: int) -> void:
	var si := CombatResolver.StatusInstance.new()
	si.status_id = status_id
	si.remaining_turns = duration
	target.combat_stats.statuses.append(si)


func _alive_minions() -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in teams[ENEMY_TEAM].units:
		if unit == _boss or not (unit is Unit):
			continue
		var m := unit as Unit
		if m.combat_stats and m.combat_stats.is_alive():
			result.append(m)
	return result


func _count_minions() -> int:
	return _alive_minions().size()


func _on_stage_unit_died(unit: Unit) -> void:
	if unit == _boss:
		return
	if unit.team_index != ENEMY_TEAM:
		return
	_minion_kills += 1
	Notify.notify("击退受驱役之敌 (%d/%d)" % [_minion_kills, REQUIRED_DEFEATS], Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 2.0)
	_update_mission_hint()
	_check_win_lose()


func _on_stage_hp_changed(unit: Unit, old_hp: int, new_hp: int) -> void:
	# Boss 完全免疫伤害：血量下降时回滚。
	if unit != _boss or old_hp <= new_hp:
		return
	unit.combat_stats.current_hp = old_hp
	unit.refresh_overhead_bars()


# ─────────────────────────────────────────────
# 召唤 / 生成
# ─────────────────────────────────────────────

func _spawn_minion(kind: StringName, cell: Vector2i) -> Unit:
	match kind:
		&"循旧匠首":
			return _spawn_enemy(_rule_guard_data, "循旧匠首", 84, 20, 90, 9, cell, [_mallet], null)
		&"高拱幻影":
			return _spawn_enemy(_high_arch_data, "高拱幻影", 76, 18, 90, 8, cell, [_pull], _high_arch_visual)
		&"重墩石像":
			return _spawn_enemy(_heavy_pier_data, "重墩石像", 120, 16, 85, 14, cell, [_crush], null, Enums.Element.EARTH, 2)
		_:
			return null


func _random_enemy_spawn_cell() -> Vector2i:
	var candidates: Array[Vector2i] = []
	for anchor in ENEMY_SPAWN_ANCHORS:
		candidates.append(_nearest_walkable(anchor))
		candidates.append(_nearest_walkable(anchor + Vector2i(1, 0)))
		candidates.append(_nearest_walkable(anchor + Vector2i(-1, 0)))
		candidates.append(_nearest_walkable(anchor + Vector2i(0, 1)))
		candidates.append(_nearest_walkable(anchor + Vector2i(1, 1)))
	candidates.shuffle()
	for cell in candidates:
		if not _cell_occupied(cell):
			return cell
	return candidates[0]


func _spawn_enemy(base: UnitData, uname: String, hp: int, atk: int, ap: int, move_cost: int, cell: Vector2i, skills: Array[SkillData], visual: PackedScene = null, element: Enums.Element = Enums.Element.NONE, element_amount: int = 0) -> Unit:
	var unit := spawn_unit(base, _nearest_walkable(cell), ENEMY_TEAM, visual)
	set_unit_skills(unit, skills)
	setup_unit_stats(unit, uname, hp, atk, ap, move_cost, element, element_amount)
	return unit


# ─────────────────────────────────────────────
# 辅助工具
# ─────────────────────────────────────────────

func _all_parameters_done() -> bool:
	for tile in _parameter_tiles.values():
		if not tile.completed:
			return false
	return true


func _skill_list_contains(list: Array, skill_id: String) -> bool:
	for s in list:
		if s is SkillData and (s as SkillData).skill_id == skill_id:
			return true
	return false


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


func _cell_occupied(cell: Vector2i) -> bool:
	for unit in _get_all_units():
		if unit is Unit and (unit as Unit).combat_stats and (unit as Unit).combat_stats.is_alive() and (unit as Unit).cell == cell:
			return true
	return false


# ─────────────────────────────────────────────
# 成长
# ─────────────────────────────────────────────

func get_post_level_growth_options() -> Array[Dictionary]:
	return [
		{"id": "growth_drawing_discipline", "name": "墨绳习算", "description": "李春基础攻击力 +4，分规定弧伤害倍率 +0.05"},
		{"id": "growth_center_hold", "name": "护模齐作", "description": "全体工匠最大生命值 +10，基础攻击力 +2"},
		{"id": "growth_arch_refine", "name": "参校定弧", "description": "李春获得新技能绳准锁弧"},
		{"id": "growth_quick_measure", "name": "熟尺知度", "description": "测尺取参 AP -10，相水定址 AP -5，李春行动力上限 +5"},
	]


func _apply_persistent_growth_effects() -> void:
	# 第一关成长继承
	if Progress.has_growth_option("growth_training_mobilize"):
		for unit in get_friendly_units():
			apply_unit_growth_bonus(unit, 10, 0, 5)
	if Progress.has_growth_option("growth_maps_measures"):
		var hero_unit := get_hero_unit()
		if hero_unit:
			apply_unit_growth_bonus(hero_unit, 0, 4, 0)
			modify_unit_skill(hero_unit, "lc_rule_strike", {"damage_ratio": 1.05})
	if Progress.has_growth_option("growth_stone_reinforce"):
		for craftsman in _craftsmen:
			modify_unit_skill(craftsman, "cg_guard_the_works", {"duration_turns": 3})

	# 第二关成长（若玩家已完本关，二周目继承）
	if Progress.has_growth_option("growth_drawing_discipline"):
		var hero_unit := get_hero_unit()
		if hero_unit:
			apply_unit_growth_bonus(hero_unit, 0, 4, 0)
			modify_unit_skill(hero_unit, "lc_divider_mark_arc", {"damage_ratio": 0.95})
	if Progress.has_growth_option("growth_center_hold"):
		for craftsman in _craftsmen:
			apply_unit_growth_bonus(craftsman, 10, 2, 0)
	if Progress.has_growth_option("growth_arch_refine"):
		var hero_unit := get_hero_unit()
		if hero_unit:
			var replace_candidates: Array[String] = ["lc_rule_strike", "lc_wedge_bank_probe"]
			add_skill_to_unit(hero_unit, _line_lock_arc, replace_candidates)
	if Progress.has_growth_option("growth_quick_measure"):
		for sw in _survey_workers:
			modify_unit_skill(sw, "sw_take_parameters", {"ap_cost": 30})
		var hero_unit := get_hero_unit()
		if hero_unit:
			modify_unit_skill(hero_unit, "lc_read_water_fix_site", {"ap_cost": 25})
			apply_unit_growth_bonus(hero_unit, 0, 0, 5)
