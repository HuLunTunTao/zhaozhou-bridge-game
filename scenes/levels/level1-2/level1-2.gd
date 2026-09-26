extends BaseLevel
## 第二关《弧拱定式》
##
## 任务四段：TASK1 取参 → TASK2 李春抵达绘样台 → TASK3 执墨定拱 → TASK4 击退 8 只小怪。
## 仿 1-1 使用 SpecialTile + 技能施放式交互。
## 旧制监工为唯一 Boss：不动、不攻击、完全免疫，只做按回合召唤 + 督令增益。

const ENEMY_TEAM := 1
const REQUIRED_DEFEATS := 8
const ENEMY_FIELD_CAP := 5
const TURN_LIMIT := 30

const PARAMETER_CELL := Vector2i(-1, 2)
const PARAMETER_REQUIRED_USES := 3
const DRAFTING_CELLS: Array[Vector2i] = [
	Vector2i(-11, -11), Vector2i(-11, -10),
	Vector2i(-12, -10), Vector2i(-12, -11),
]
const BOSS_CELL := Vector2i(-12, -12)
const ENEMY_SPAWN_ANCHORS: Array[Vector2i] = [Vector2i(13, -24), Vector2i(10, -19)]

const SUMMON_CYCLE: Array[StringName] = [
	&"循旧匠首", &"高拱幻影", &"循旧匠首", &"重墩石像",
]

# ── 敌方颜色（沿用 1-1 的视觉惯例） ──
const COLOR_RULE_GUARD := Color(0.75, 0.55, 0.3)
const COLOR_HIGH_ARCH := Color(0.55, 0.65, 0.95)
const COLOR_HEAVY_PIER := Color(0.65, 0.6, 0.5)
const COLOR_BOSS := Color(0.8, 0.25, 0.25)

# ── 关卡任务链（TaskChain：parameters → platform → arch → hunt）──
var _task_chain: TaskChain = TaskChain.new()

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
var _parameter_tile: InteractionTile = null
var _parameter_use_count: int = 0
var _li_chun_parameter_round: int = -1
var _finalized: bool = false
var _minion_kills: int = 0
var _summon_cycle_index: int = 0
var _pending_summon_bonus: int = 0
var _platform_visit_cache: Dictionary = {}  # instance_id → true
var _drafting_marker: Node2D = null
var _task2_pulsing_marker: TilePulsingMarker = null
var _mission_hint_label: Label = null
var _params_status_label: Label = null
# 参数点交互派发表（InteractionTile：测尺取参 + 参数确认，同格两条规则）
var _interactions: Array[InteractionTile] = []
# Boss 减伤策略（Step 4.4）：CAP 模式，上限恒 0 = 旧制监工完全免伤
var _boss_dr: BossDRPolicy = null
const COLOR_PARAM_INCOMPLETE := Color(0.95, 0.72, 0.2, 0.55)
const COLOR_PARAM_COMPLETE := Color(0.3, 0.85, 0.4, 0.55)


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/Player" as Unit
	_survey_worker = $"Entities/Units/SurveyWorker" as Unit
	_survey_workers = [
		_survey_worker,
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
			"units": [_li_chun, _survey_workers[0], _craftsmen[0], _craftsmen[1], _craftsmen[2]],
		},
		{
			"name": "旧制势力",
			"faction": "坏人",
			"controller": "ai",
			"units": [],
		},
	]


func get_objectives_text() -> Dictionary:
	return {
		"victory": _task_chain.get_objective_lines(),
		"defeat": [
			"- 李春倒下",
			"- 超过第 %d 回合" % TURN_LIMIT,
		],
	}


func check_victory() -> bool:
	return _task_chain.is_at_id(&"hunt") and _minion_kills >= REQUIRED_DEFEATS


func check_defeat() -> String:
	if _li_chun == null or _li_chun.combat_stats == null or not _li_chun.combat_stats.is_alive():
		return "李春倒下"
	if round_number > TURN_LIMIT:
		return "超过第 %d 回合" % TURN_LIMIT
	return ""


func _on_level_ready() -> void:
	_task_chain.setup(self)
	_task_chain.configure(_build_task_chain_tasks())
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

	Notify.hint("派测量工到参数点 (-1, 2) 测定河宽 / 河床 / 汛位 3 项数据（「测尺取参」每回合不限），或李春「参数确认」补刀（每回合 1 次）。", 4.0)


# ─────────────────────────────────────────────
# 任务链（TaskChain）数据与文案
# ─────────────────────────────────────────────

## 任务链数据：parameters → platform → arch → hunt。目标 / 提示文案与旧 TaskState 版逐字一致。
func _build_task_chain_tasks() -> Array[Dictionary]:
	return [
		TaskChain.task(&"parameters", _obj_parameters, _hint_parameters, Callable(), PARAMETER_CELL),
		TaskChain.task(&"platform", _obj_platform, "任务目标二，李春前往中央绘样台", _on_enter_platform, DRAFTING_CELLS[0]),
		TaskChain.task(&"arch", _obj_arch, _hint_arch, _on_enter_arch, DRAFTING_CELLS[0]),
		TaskChain.task(&"hunt", _obj_hunt, _hint_hunt, _on_enter_hunt, BOSS_CELL),
	]


func _obj_parameters(mode: int) -> String:
	match mode:
		TaskChain.DisplayMode.DONE:
			return "- 在参数点测定 河宽 / 河床 / 汛位 3 项数据 (3/3)"
		TaskChain.DisplayMode.ACTIVE:
			var status := " (%d/%d)" % [_parameter_use_count, PARAMETER_REQUIRED_USES]
			return "- 在参数点 (-1, 2) 测定 河宽 / 河床 / 汛位 3 项数据（「测尺取参 / 参数确认」%s）" % status
		_:
			return "- 在参数点测定 河宽 / 河床 / 汛位 3 项数据"


func _obj_platform(mode: int) -> String:
	match mode:
		TaskChain.DisplayMode.DONE:
			return "- 李春抵达中央绘样台 (1/1)"
		TaskChain.DisplayMode.ACTIVE:
			return "- 李春抵达中央绘样台 (0/1)"
		_:
			return "- 李春抵达中央绘样台"


func _obj_arch(mode: int) -> String:
	match mode:
		TaskChain.DisplayMode.DONE:
			return "- 李春执行「执墨定拱」 (1/1)"
		TaskChain.DisplayMode.ACTIVE:
			return "- 李春执行「执墨定拱」%s" % (" (0/1)" if not _finalized else " (1/1)")
		_:
			return "- 李春执行「执墨定拱」"


func _obj_hunt(mode: int) -> String:
	if mode == TaskChain.DisplayMode.PENDING:
		return "- 累计击退 8 名受驱役敌人"
	return "- 累计击退 8 名受驱役敌人(%d/%d)" % [_minion_kills, REQUIRED_DEFEATS]


func _hint_parameters() -> String:
	return "任务目标一，在参数点 (-1, 2) 测定河宽 / 河床 / 汛位 3 项数据【%d/%d】" % [_parameter_use_count, PARAMETER_REQUIRED_USES]


func _hint_arch() -> String:
	var done := " (1/1)" if _finalized else " (0/1)"
	return "任务目标三，李春在绘样台执行「执墨定拱」%s" % done


func _hint_hunt() -> String:
	return "任务目标四，李春「绳准锁弧」已解锁，累计击退 8 名受驱役敌人【%d/%d】" % [_minion_kills, REQUIRED_DEFEATS]


# ─────────────────────────────────────────────
# 开局配置
# ─────────────────────────────────────────────

func _setup_li_chun() -> void:
	_li_chun.apply_runtime_setup(_hero_data, _hero_visual, Color(1, 0.85, 0, 1))
	# 关卡核心交互 & 分规定弧 默认写入李春技能池（若 Progress 没提供）。
	_get_unit_factory().setup_hero_unit(_li_chun, "李春", 130, 24, 100, 8, [_confirm_parameter, _ink_set_arch, _divider_arc])


func _setup_allies_from_scene() -> void:
	# 场景里已放好 SurveyWorker*/CraftsmanA-C 节点；位置由场景 position 决定
	# （基类 _reparent_entities_to_obstacles 会按 global_position 吸附到最近格）。
	# 这里只补齐 skills / 数值。
	var factory := _get_unit_factory()
	factory.setup_ally_group(_survey_workers, [_staff, _take_parameters], "测量工", 80, 12, 85, 10)
	factory.setup_ally_group(_craftsmen, [_mallet, _guard], "工匠", 110, 18, 90, 9)


func _setup_parameter_tiles() -> void:
	# 交互条件（测尺取参 / 测量工 / 可重复三次）参数化进 InteractionTile。
	var tile := InteractionTile.create(
		[PARAMETER_CELL], &"take_parameter", _take_parameter_filter,
		_on_take_parameter_effect, false)
	tile.name = "ParameterPoint_%d_%d" % [PARAMETER_CELL.x, PARAMETER_CELL.y]
	tile.tile_color = COLOR_PARAM_INCOMPLETE
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([0, -16, 16, -8, 0, 0, -16, -8])
	tile.add_child(visual)
	tile.on_cell_miss = _parameter_cell_miss
	_special_tile_registry.register(tile, PARAMETER_CELL)
	_parameter_tile = tile
	_interactions.append(tile)
	# 「参数确认」（李春补刀，每回合 1 次）是同格第二条交互规则：纯逻辑点，不占视觉位。
	var confirm := InteractionTile.create(
		[PARAMETER_CELL], &"confirm_parameter", _confirm_parameter_filter,
		_on_confirm_parameter_effect, false)
	confirm.on_cell_miss = _parameter_cell_miss
	_interactions.append(confirm)
	_spawn_parameter_flag(PARAMETER_CELL)


func _spawn_parameter_flag(cell: Vector2i) -> void:
	var marker := Node2D.new()
	marker.name = "ParameterFlag_%d_%d" % [cell.x, cell.y]
	marker.z_as_relative = false
	marker.z_index = 115
	marker.position = tilemap.map_to_local(cell) + Vector2(0, -18)
	add_child(marker)

	var pole := Line2D.new()
	pole.points = PackedVector2Array([Vector2(0, -28), Vector2(0, -4)])
	pole.width = 2.0
	pole.default_color = Color(0.95, 0.9, 0.72, 0.95)
	marker.add_child(pole)

	var flag := Polygon2D.new()
	flag.polygon = PackedVector2Array([0, -28, 16, -22, 0, -16])
	flag.color = Color(0.95, 0.72, 0.2, 0.95)
	marker.add_child(flag)

	var tween := create_tween().set_loops()
	tween.tween_property(marker, "position:y", marker.position.y - 4.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(marker, "position:y", marker.position.y, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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
	var cell := CellMath.nearest_walkable(movement_manager, BOSS_CELL, 6)
	_boss = _get_unit_factory().spawn_unit(_boss_data, cell, ENEMY_TEAM)
	_get_unit_factory().set_unit_skills(_boss, [])
	_get_unit_factory().setup_unit_stats(_boss, _boss_data.unit_name, _boss_data.max_hp, 0, 0, 99, Enums.Element.NONE, 0)
	# Boss 每回合固定开口（prob=1.0），对话伙伴池放开到全地图（boss 在角落）
	_boss.chatter_round_prob = 1.0
	_boss.chatter_full_map_range = true
	# Boss 减伤策略：单次伤害上限恒 0（完全免伤）
	_boss_dr = BossDRPolicy.cap(_boss, self._boss_damage_cap)


## 旧制监工完全免伤：单次伤害上限恒 0（BossDRPolicy CAP 模式）。
func _boss_damage_cap() -> int:
	return 0


func _spawn_initial_minions() -> void:
	_spawn_minion(&"循旧匠首", CellMath.nearest_walkable(movement_manager, ENEMY_SPAWN_ANCHORS[0], 6))
	_spawn_minion(&"高拱幻影", CellMath.nearest_walkable(movement_manager, ENEMY_SPAWN_ANCHORS[0] + Vector2i(1, 1), 6))
	_spawn_minion(&"循旧匠首", CellMath.nearest_walkable(movement_manager, ENEMY_SPAWN_ANCHORS[1], 6))
	_spawn_minion(&"重墩石像", CellMath.nearest_walkable(movement_manager, ENEMY_SPAWN_ANCHORS[1] + Vector2i(1, 1), 6))


# ─────────────────────────────────────────────
# 技能执行响应：关卡交互（参数点走 InteractionTile 参数化派发）
# ─────────────────────────────────────────────

func _on_skill_executed(caster: Unit, skill: SkillData, cast_cell: Vector2i, _exec_result: SkillExecutor.ExecuteResult) -> void:
	if InteractionTile.dispatch_skill(_interactions, caster, skill, cast_cell):
		return
	if skill.extra_effect_id == "ink_set_arch":
		_handle_ink_set_arch(caster, cast_cell)


## 「测尺取参」闸门：仅测量工（旧 _handle_take_parameter 前半逐字）。
func _take_parameter_filter(caster: Unit) -> bool:
	if not (caster in _survey_workers):
		Notify.notify("只有测量工可以使用「测尺取参」。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
		return false
	return true


func _on_take_parameter_effect(_tile: InteractionTile, caster: Unit, _cell: Vector2i) -> void:
	_register_parameter_use(caster.combat_stats.unit_name)


## 「参数确认」闸门：仅李春（旧 _handle_confirm_parameter 前半逐字）。
func _confirm_parameter_filter(caster: Unit) -> bool:
	if caster != _li_chun:
		Notify.notify("只有李春可以使用「参数确认」。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
		return false
	return true


func _on_confirm_parameter_effect(_tile: InteractionTile, caster: Unit, _cell: Vector2i) -> void:
	# 每回合 1 次的补刀限次（旧分支顺序：人 → 格 → 限次，逐字保留）
	if _li_chun_parameter_round == round_number:
		Notify.notify("李春本回合已确认过一次参数。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
		return
	_li_chun_parameter_round = round_number
	_register_parameter_use(caster.combat_stats.unit_name)


func _parameter_cell_miss() -> void:
	Notify.notify("此处不是参数点。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)


func _register_parameter_use(caster_name: String) -> void:
	if _parameter_use_count >= PARAMETER_REQUIRED_USES:
		Notify.hint("参数点已完成三次取参，无需再施放。", 2.0)
		return
	_parameter_use_count += 1
	Notify.success("%s 取参成功 (%d/%d)" % [caster_name, _parameter_use_count, PARAMETER_REQUIRED_USES])
	_update_mission_hint()
	_update_params_status_hint()
	if _parameter_use_count >= PARAMETER_REQUIRED_USES:
		if _parameter_tile != null and not _parameter_tile.completed:
			_parameter_tile.complete()
			_parameter_tile.tile_color = COLOR_PARAM_COMPLETE
		if _task_chain.is_at_id(&"parameters"):
			_task_chain.advance_next()


func _handle_ink_set_arch(caster: Unit, cast_cell: Vector2i) -> void:
	if caster != _li_chun:
		Notify.notify("只有李春可以执行「执墨定拱」。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
		return
	if _parameter_use_count < PARAMETER_REQUIRED_USES:
		Notify.notify("需先在参数点完成 3 次取参。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.5)
		return
	if not (cast_cell in DRAFTING_CELLS):
		Notify.notify("请站在绘样台 2×2 区域上再执行「执墨定拱」。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.5)
		return
	if _finalized:
		return
	_finalized = true
	_task_chain.advance_next()


# ─────────────────────────────────────────────
# 任务 UI 提示
# ─────────────────────────────────────────────

func _setup_mission_hint() -> void:
	_mission_hint_label = LevelHudFactory.create_mission_hint_label()
	gui.add_child(_mission_hint_label)
	_update_mission_hint()


func _setup_params_status_hint() -> void:
	_params_status_label = LevelHudFactory.create_side_hint_label("ParamsStatusHint", 240)
	gui.add_child(_params_status_label)
	_update_params_status_hint()


func _update_mission_hint() -> void:
	if _mission_hint_label == null:
		return
	_mission_hint_label.text = _task_chain.get_current_hint()


func _update_params_status_hint() -> void:
	if _params_status_label == null:
		return
	var status := "已完成" if _parameter_use_count >= PARAMETER_REQUIRED_USES else "%d/%d" % [_parameter_use_count, PARAMETER_REQUIRED_USES]
	_params_status_label.text = "参数点进度：\n河宽 / 河床 / 汛位 (%d, %d) [%s]" % [PARAMETER_CELL.x, PARAMETER_CELL.y, status]


# ─────────────────────────────────────────────
# 任务推进
# ─────────────────────────────────────────────

## 进入「绘样台」任务的进场动作（旧 _advance_to_task2 主体）。
func _on_enter_platform() -> void:
	Notify.success("三处参数已成。请李春前往中央绘样台。", 3.5)
	_update_mission_hint()
	_show_objectives_if_not_open()
	_spawn_task2_marker()


## 在中央绘样台 4 格中心 spawn 一个 TilePulsingMarker，作为"现在去这里"的动态指引。
## 进 TASK4 时由 _on_enter_hunt 主动 queue_free 撤除。
func _spawn_task2_marker() -> void:
	if _task2_pulsing_marker != null and is_instance_valid(_task2_pulsing_marker):
		return
	var center_local := (tilemap.map_to_local(DRAFTING_CELLS[0])
			+ tilemap.map_to_local(DRAFTING_CELLS[1])
			+ tilemap.map_to_local(DRAFTING_CELLS[2])
			+ tilemap.map_to_local(DRAFTING_CELLS[3])) / 4.0
	var base_local := tilemap.map_to_local(DRAFTING_CELLS[0])
	_task2_pulsing_marker = _special_tile_registry.spawn_pulsing_marker(
		DRAFTING_CELLS[0],
		Color(0.4, 0.85, 1.0, 0.55),
		"中央绘样台",
		center_local - base_local,
		"Task2PulsingMarker",
		2,
	) as TilePulsingMarker


## 进入「执墨定拱」任务的进场动作（旧 _advance_to_task3 主体）。
func _on_enter_arch() -> void:
	Notify.success("李春抵达绘样台！执行「执墨定拱」落定桥法。", 3.5)
	_update_mission_hint()
	_show_objectives_if_not_open()


## 进入「清退」任务的进场动作（旧 _advance_to_task4 主体）。
func _on_enter_hunt() -> void:
	if _drafting_marker != null and is_instance_valid(_drafting_marker):
		_drafting_marker.modulate = Color(1, 1, 1, 0.4)
	if _task2_pulsing_marker != null and is_instance_valid(_task2_pulsing_marker):
		_task2_pulsing_marker.queue_free()
	_task2_pulsing_marker = null
	Notify.success("执墨定拱完成！李春解锁「绳准锁弧」（直线穿透+拖拽），用它清退 %d 名受驱役之敌。" % REQUIRED_DEFEATS, 4.0)
	_update_mission_hint()
	_show_objectives_if_not_open()


func _show_objectives_if_not_open() -> void:
	if not has_overlay():
		_get_ui_bridge().show_objectives()


func _on_stage_unit_move_completed(unit: Unit) -> void:
	if unit == _li_chun and _task_chain.is_at_id(&"platform") and unit.cell in DRAFTING_CELLS:
		_task_chain.advance_next()


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
		Notify.warn("%s 抵达绘样台！Boss 下回合召唤 +1。" % minion.combat_stats.unit_name)


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
		Notify.warn("旧制监工召唤了 %d 名受驱役之敌。" % spawned, 2.0)


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
	_get_objectives_tracker().check_win_lose()


func _on_stage_hp_changed(unit: Unit, old_hp: int, new_hp: int) -> void:
	if unit == _boss and new_hp < old_hp:
		# Boss 免疫已在 _finalize_skill_hit_damage 中于战斗反馈前处理。
		pass


func _finalize_skill_hit_damage(_caster: Unit, _skill: SkillData, target: Unit, hit: CombatResolver.HitResult) -> void:
	# BossDRPolicy（CAP 模式，上限 0）：旧制监工伤害归零，HP 回到命中前
	var info := _boss_dr.limit_hit(target, hit)
	if not info.get("changed", false):
		return
	hit.damage_limit_message = "旧制监工不可被直接击退，请优先完成本关任务目标。"
	CombatLog.msg("    关卡机制: %s（原伤害 %d → 实际 0）" % [hit.damage_limit_message, info["raw"]])


# ─────────────────────────────────────────────
# 召唤 / 生成
# ─────────────────────────────────────────────

func _spawn_minion(kind: StringName, cell: Vector2i) -> Unit:
	match kind:
		&"循旧匠首":
			return _spawn_enemy(_rule_guard_data, "循旧匠首", 84, 17, 90, 9, cell, [_mallet], null)
		&"高拱幻影":
			return _spawn_enemy(_high_arch_data, "高拱幻影", 76, 15, 90, 8, cell, [_pull], _high_arch_visual)
		&"重墩石像":
			return _spawn_enemy(_heavy_pier_data, "重墩石像", 120, 13, 85, 14, cell, [_crush], null, Enums.Element.EARTH, 2)
		_:
			return null


func _random_enemy_spawn_cell() -> Vector2i:
	var candidates: Array[Vector2i] = []
	for anchor in ENEMY_SPAWN_ANCHORS:
		candidates.append(CellMath.nearest_walkable(movement_manager, anchor, 6))
		candidates.append(CellMath.nearest_walkable(movement_manager, anchor + Vector2i(1, 0), 6))
		candidates.append(CellMath.nearest_walkable(movement_manager, anchor + Vector2i(-1, 0), 6))
		candidates.append(CellMath.nearest_walkable(movement_manager, anchor + Vector2i(0, 1), 6))
		candidates.append(CellMath.nearest_walkable(movement_manager, anchor + Vector2i(1, 1), 6))
	candidates.shuffle()
	for cell in candidates:
		if not _cell_occupied(cell):
			return cell
	return candidates[0]


func _spawn_enemy(base: UnitData, uname: String, hp: int, atk: int, ap: int, move_cost: int, cell: Vector2i, skills: Array[SkillData], visual: PackedScene = null, element: Enums.Element = Enums.Element.NONE, element_amount: int = 0) -> Unit:
	return _get_unit_factory().spawn_enemy_unit(base, _get_scene_bootstrap().find_empty_walkable_cell(cell), ENEMY_TEAM, skills, visual, {
		"unit_name": uname, "max_hp": hp, "base_atk": atk, "ap_max": ap,
		"move_cost": move_cost, "element": element, "element_amount": element_amount,
	})


# ─────────────────────────────────────────────
# 辅助工具
# ─────────────────────────────────────────────

func _cell_occupied(cell: Vector2i) -> bool:
	for unit in _get_scene_bootstrap().get_all_units():
		if unit is Unit and (unit as Unit).combat_stats and (unit as Unit).combat_stats.is_alive() and (unit as Unit).cell == cell:
			return true
	return false


# ─────────────────────────────────────────────
# 成长
# ─────────────────────────────────────────────

func get_post_level_growth_options() -> Array[Dictionary]:
	return Progress.get_level_growth_options("关卡1-2")


# 持久成长选项的应用逻辑统一在 base_level._apply_persistent_growth_effects 中处理。
