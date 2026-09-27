class_name SurvivalWaveController
extends Node
## 无尽生存模式波次控制。
##
## 监听 BaseLevel.phase_changed → 第 1 波；监听 unit_died → 敌方全灭后跑波间序列。
##
## 波次主题：[木, 火, 土, 金, 水] 循环；每 N 波出 Boss（N = config.boss_every）。
## 波间：友方回血 → 概率召唤支援 → 三选一 buff → 下一波。
##
## 节奏公式 / buff 池 / 可学技能池的真源是 SurvivalWaveConfig（data/stages/survival/wave_config.tres）；
## 刷点的真源是地图锚点节点（survival.tscn 的 WaveSpawnAnchors/North|South/*），拖锚点即可改刷点。

const PLAYER_TEAM := 0
const AI_TEAM := 1

## 刷点锚点容器（挂在关卡场景根下）。North / South 两组保持刷点的组织分区。
const SPAWN_ANCHORS_ROOT := "WaveSpawnAnchors"

const ELEMENTS: Array[int] = [
	Enums.Element.WOOD,
	Enums.Element.FIRE,
	Enums.Element.EARTH,
	Enums.Element.METAL,
	Enums.Element.WATER,
]
const ELEMENT_NAMES: Dictionary = {
	Enums.Element.WOOD: "木势",
	Enums.Element.FIRE: "火势",
	Enums.Element.EARTH: "土势",
	Enums.Element.METAL: "金势",
	Enums.Element.WATER: "水势",
}
const ELEMENT_COLORS: Dictionary = {
	Enums.Element.WOOD: Color(0.5, 0.65, 0.2),
	Enums.Element.FIRE: Color(0.95, 0.45, 0.2),
	Enums.Element.EARTH: Color(0.7, 0.55, 0.3),
	Enums.Element.METAL: Color(0.85, 0.85, 0.92),
	Enums.Element.WATER: Color(0.35, 0.55, 0.95),
}

# ── 怪物池（按主题映射，使用现有 16 个 UnitData）──
const _UD_DRIFT_LOG := preload("res://data/units/drift_log_pack.tres")
const _UD_FLOOD_DRIFTWOOD := preload("res://data/units/flood_driftwood_pack.tres")
const _UD_FLOOD_SPEAR := preload("res://data/units/flood_spear.tres")
const _UD_WRATHFUL_FLOOD := preload("res://data/units/wrathful_flood.tres")
const _UD_BANK_MUD := preload("res://data/units/bank_mud_wraith.tres")
const _UD_HEAVY_PIER := preload("res://data/units/heavy_pier_statue.tres")
const _UD_SILTMARE := preload("res://data/units/siltmare.tres")
const _UD_PIER_GNAWER := preload("res://data/units/pier_gnawer.tres")
const _UD_RULE_GUARD := preload("res://data/units/rule_guard_head.tres")
const _UD_OLD_METHOD := preload("res://data/units/old_method_supervisor.tres")
const _UD_HIGH_ARCH := preload("res://data/units/high_arch_phantom.tres")
const _UD_DARK_CURRENT := preload("res://data/units/dark_current.tres")
const _UD_WHIRL_POOL := preload("res://data/units/whirl_pool.tres")

const _ENEMY_POOLS: Dictionary = {
	Enums.Element.WOOD: [_UD_DRIFT_LOG, _UD_FLOOD_DRIFTWOOD],
	Enums.Element.FIRE: [_UD_FLOOD_SPEAR, _UD_WRATHFUL_FLOOD],
	Enums.Element.EARTH: [_UD_BANK_MUD, _UD_SILTMARE, _UD_PIER_GNAWER, _UD_HEAVY_PIER],
	Enums.Element.METAL: [_UD_RULE_GUARD, _UD_HIGH_ARCH, _UD_OLD_METHOD],
	Enums.Element.WATER: [_UD_DARK_CURRENT, _UD_WHIRL_POOL, _UD_FLOOD_SPEAR],
}
## 每个主题的 boss（pool 中血最厚的）。
const _BOSS_BY_ELEMENT: Dictionary = {
	Enums.Element.WOOD: _UD_FLOOD_DRIFTWOOD,
	Enums.Element.FIRE: _UD_WRATHFUL_FLOOD,
	Enums.Element.EARTH: _UD_HEAVY_PIER,
	Enums.Element.METAL: _UD_OLD_METHOD,
	Enums.Element.WATER: _UD_FLOOD_SPEAR,
}

# ── 友方支援池 ──
const _UD_CRAFTSMAN := preload("res://data/units/craftsman_guard.tres")
const _UD_SURVEY := preload("res://data/units/survey_worker.tres")
const _SUPPORT_POOL: Array = [_UD_CRAFTSMAN, _UD_SURVEY]
const _SK_MALLET := preload("res://data/skills/cg_mallet_strike.tres")
const _SK_GUARD := preload("res://data/skills/cg_guard_the_works.tres")
const _SK_STAFF := preload("res://data/skills/sw_staff_end_strike.tres")
const _SK_SURVEY := preload("res://data/skills/sw_field_measure_site.tres")
const _SUPPORT_SKILLS: Dictionary = {
	"craftsman_guard": [_SK_MALLET, _SK_GUARD],
	"survey_worker": [_SK_STAFF, _SK_SURVEY],
}

# ── 敌方技能（unit_id → 技能列表）──
const _SK_TIMBER := preload("res://data/skills/dlp_drifting_timber_crash.tres")
const _SK_TORRENT := preload("res://data/skills/fs_torrent_ram.tres")
const _SK_BANK_CRUSH := preload("res://data/skills/bmw_crumbling_bank_crush.tres")
const _SK_MIRE := preload("res://data/skills/sm_mire_steps.tres")
const _SK_GNAW := preload("res://data/skills/pg_gnaw_pier.tres")
const _SK_CURRENT := preload("res://data/skills/dc_hidden_current_lunge.tres")
const _SK_SPIRAL := preload("res://data/skills/wp_spiral_pull.tres")
const _SK_OVERTURN := preload("res://data/skills/wf_overturn_bridge.tres")
const _ENEMY_SKILLS: Dictionary = {
	"drift_log_pack": [_SK_TIMBER],
	"flood_driftwood_pack": [_SK_TIMBER],
	"flood_spear": [_SK_TORRENT],
	"wrathful_flood": [_SK_OVERTURN],
	"bank_mud_wraith": [_SK_BANK_CRUSH],
	"siltmare": [_SK_MIRE],
	"pier_gnawer": [_SK_GNAW],
	"dark_current": [_SK_CURRENT],
	"whirl_pool": [_SK_SPIRAL],
}

# ── 状态 ──
var _level: BaseLevel
## 波次配置（节奏公式 + buff 池 + 可学技能池）。真源 data/stages/survival/wave_config.tres。
var _config: SurvivalWaveConfig
## 地图锚点解析出的刷点格（顺序：North 组在前，South 组在后，各自按场景树顺序）。
var _spawn_cells: Array[Vector2i] = []
## 类型用 Node 而不是 WaveBuffHud：避免 class_name 加载顺序问题。运行时通过 add_buff/set_wave 鸭子调用。
var _hud: Node
var _wave_index: int = 0
var _between_waves_running: bool = false


func setup(level: BaseLevel, hud: Node, config: SurvivalWaveConfig) -> void:
	_level = level
	_hud = hud
	# 缺配置时用类默认值兜底（等价于旧常量），不让 null 打穿整套节奏。
	_config = config if config != null else SurvivalWaveConfig.new()
	_spawn_cells = _resolve_spawn_anchor_cells()
	_level.phase_changed.connect(_on_phase_changed)
	_level.unit_died.connect(_on_unit_died)


func get_wave_index() -> int:
	return _wave_index


func _on_phase_changed(p: int) -> void:
	if p != BaseLevel.LevelPhase.PLAYING:
		return
	# 进入 PLAYING 立刻刷第一波
	_start_wave(1)


func _start_wave(n: int) -> void:
	_wave_index = n
	var element: int = ELEMENTS[(n - 1) % ELEMENTS.size()]
	var is_boss: bool = (n % _config.boss_every == 0)
	if _hud:
		_hud.set_wave(n)
	_announce_wave(n, element, is_boss)
	_spawn_wave(n, element, is_boss)


func _announce_wave(n: int, element: int, is_boss: bool) -> void:
	var phase_name: String = ELEMENT_NAMES.get(element, "")
	if is_boss:
		phase_name = "BOSS · " + phase_name
	var category := "第 %d 波" % n
	if _level and _level.has_method("show_wave_banner"):
		_level.show_wave_banner(phase_name, category)


func _spawn_wave(n: int, element: int, is_boss: bool) -> void:
	var pool: Array = _ENEMY_POOLS.get(element, [])
	if pool.is_empty():
		push_warning("[Survival] 元素 %d 没有怪物池" % element)
		return
	var color: Color = ELEMENT_COLORS.get(element, Color.WHITE)
	var spawn_cells := _pick_spawn_cells(_pack_count(n, is_boss))
	if is_boss:
		var boss_data: UnitData = _BOSS_BY_ELEMENT.get(element, pool[0])
		_spawn_one(boss_data, spawn_cells.pop_front(), color, n, true)
		@warning_ignore("integer_division")
		var minion_count: int = n / _config.boss_minion_divisor
		for i in minion_count:
			if spawn_cells.is_empty():
				break
			var data: UnitData = pool[randi() % pool.size()]
			_spawn_one(data, spawn_cells.pop_front(), color, n, false)
	else:
		for cell: Vector2i in spawn_cells:
			var data: UnitData = pool[randi() % pool.size()]
			_spawn_one(data, cell, color, n, false)


func _pack_count(n: int, is_boss: bool) -> int:
	if is_boss:
		@warning_ignore("integer_division")
		var bonus: int = n / _config.boss_pack_bonus_divisor
		return 1 + bonus
	@warning_ignore("integer_division")
	var grow: int = n / _config.pack_grow_divisor
	return mini(_config.pack_base + grow, _config.pack_max)


func _pick_spawn_cells(count: int) -> Array[Vector2i]:
	# 北/南交替挑，避开已被占用的格
	var pool: Array[Vector2i] = []
	pool.append_array(_spawn_cells)
	pool.shuffle()
	var occupied := _occupied_cells()
	var picked: Array[Vector2i] = []
	for c in pool:
		if c in occupied or c in picked:
			continue
		picked.append(c)
		if picked.size() >= count:
			break
	# 不够格子就少出几只，不再重叠占首格——视觉上比"两只敌人共格"更可接受
	return picked


## 读地图锚点节点 → 刷点格。锚点所在格即刷点（同 UnitFactory 从节点位置反推 cell 的惯例）。
## North / South 两组只是组织分区；返回顺序保持「North 全部 → South 全部」，各自按场景树顺序。
func _resolve_spawn_anchor_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var root := _level.get_node_or_null(SPAWN_ANCHORS_ROOT)
	if root == null:
		push_warning("[Survival] 场景缺少 %s 锚点节点，波次将无处刷怪" % SPAWN_ANCHORS_ROOT)
		return out
	if _level.tilemap == null:
		push_warning("[Survival] 无可走 tilemap，锚点刷点无法换算成格子")
		return out
	for group_name: String in ["North", "South"]:
		var group := root.get_node_or_null(group_name)
		if group == null:
			continue
		for child in group.get_children():
			if child is Node2D:
				out.append(_cell_of_anchor(child as Node2D))
	return out


func _cell_of_anchor(anchor: Node2D) -> Vector2i:
	return _level.tilemap.local_to_map(_level.tilemap.to_local(anchor.global_position))


func _occupied_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for team in _level.teams:
		for unit in team.units:
			if is_instance_valid(unit) and unit is Unit:
				out.append((unit as Unit).cell)
	return out


func _spawn_one(unit_data: UnitData, cell: Vector2i, color: Color, wave: int, is_boss: bool) -> Unit:
	var unit := _level._get_unit_factory().spawn_unit(unit_data, cell, AI_TEAM)
	if unit == null:
		return null
	unit.unit_color = color
	# 难度缩放：从 scaling_start_wave 起按 scaling_per_wave / 波 提升 HP / ATK
	if wave >= _config.scaling_start_wave and unit.combat_stats != null:
		var mult := 1.0 + (wave - _config.scaling_start_wave) * _config.scaling_per_wave
		unit.combat_stats.max_hp = int(unit.combat_stats.max_hp * mult)
		unit.combat_stats.current_hp = unit.combat_stats.max_hp
		unit.combat_stats.base_atk = int(unit.combat_stats.base_atk * mult)
		unit.refresh_overhead_bars()
	# Boss 再加成
	if is_boss and unit.combat_stats != null:
		unit.combat_stats.max_hp = int(unit.combat_stats.max_hp * _config.boss_hp_mult)
		unit.combat_stats.current_hp = unit.combat_stats.max_hp
		unit.refresh_overhead_bars()
	var enemy_skills: Array = _ENEMY_SKILLS.get(unit_data.unit_id, [])
	if not enemy_skills.is_empty():
		_level._get_unit_factory().set_unit_skills(unit, enemy_skills)
	return unit


# ─────────────────────────────────────────────
# 波间序列
# ─────────────────────────────────────────────

func _on_unit_died(unit: Unit) -> void:
	if _between_waves_running:
		return
	if not is_instance_valid(unit):
		return
	if unit.team_index != AI_TEAM:
		return
	# 延一帧让连锁伤害结算完，再判全灭
	await get_tree().process_frame
	if _between_waves_running or _level.is_phase_ended():
		return
	if _ai_alive_count() > 0:
		return
	_run_between_waves()


func _ai_alive_count() -> int:
	if AI_TEAM >= _level.teams.size():
		return 0
	var team = _level.teams[AI_TEAM]
	var n := 0
	for u in team.units:
		if is_instance_valid(u) and u is Unit and (u as Unit).combat_stats != null and (u as Unit).combat_stats.is_alive():
			n += 1
	return n


func _run_between_waves() -> void:
	_between_waves_running = true
	# 1. 友方回血
	_heal_player_team()
	# 2. 概率召唤支援
	if randf() < _config.support_prob:
		_spawn_support()
	# 3. 等正在跑的 chatter / overlay 收尾（overlay_closed 信号唤醒，不再逐帧轮询）
	while _level.has_overlay():
		await _level.overlay_closed
		if _level.is_phase_ended():
			_between_waves_running = false
			return
	# 4. 三选一 buff（仅在波 >= 1 时弹；首波结束后第二波前生效）
	await _prompt_buff_choice()
	if _level.is_phase_ended():
		_between_waves_running = false
		return
	_between_waves_running = false
	_start_wave(_wave_index + 1)


func _heal_player_team() -> void:
	if PLAYER_TEAM >= _level.teams.size():
		return
	var team = _level.teams[PLAYER_TEAM]
	for u in team.units:
		if not is_instance_valid(u) or not (u is Unit):
			continue
		var unit := u as Unit
		if unit.combat_stats == null or not unit.combat_stats.is_alive():
			continue
		var ratio: float = randf_range(_config.heal_min_ratio, _config.heal_max_ratio)
		var amount: int = int(unit.combat_stats.max_hp * ratio)
		var old_hp: int = unit.combat_stats.current_hp
		unit.combat_stats.current_hp = mini(unit.combat_stats.max_hp, old_hp + amount)
		var new_hp: int = unit.combat_stats.current_hp
		if new_hp != old_hp:
			_level.unit_hp_changed.emit(unit, old_hp, new_hp)
		unit.refresh_overhead_bars()


func _spawn_support() -> void:
	var data: UnitData = _SUPPORT_POOL[randi() % _SUPPORT_POOL.size()]
	var cell := _pick_support_cell()
	var unit := _level._get_unit_factory().spawn_unit(data, cell, PLAYER_TEAM)
	if unit == null:
		return
	var skills: Array = _SUPPORT_SKILLS.get(data.unit_id, [])
	if not skills.is_empty():
		_level._get_unit_factory().set_unit_skills(unit, skills)
	Notify.notify("支援抵达：%s" % data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 4.0)


func _pick_support_cell() -> Vector2i:
	# 玩家中心附近找空格：以李春位置为锚，向外扩散
	var hero_cell := Vector2i(0, 0)
	if _level.hero != null and is_instance_valid(_level.hero) and _level.hero is Unit:
		hero_cell = (_level.hero as Unit).cell
	var occupied := _occupied_cells()
	var candidates: Array[Vector2i] = [
		hero_cell + Vector2i(-2, 0),
		hero_cell + Vector2i(2, 0),
		hero_cell + Vector2i(0, 2),
		hero_cell + Vector2i(0, -2),
		hero_cell + Vector2i(-2, 2),
		hero_cell + Vector2i(2, -2),
		hero_cell + Vector2i(-3, 0),
		hero_cell + Vector2i(3, 0),
	]
	for c in candidates:
		if not (c in occupied):
			return c
	return hero_cell + Vector2i(1, 1)


# ─────────────────────────────────────────────
# 三选一 Buff
# ─────────────────────────────────────────────

func _prompt_buff_choice() -> void:
	if _level.has_overlay():
		return
	var options: Array[Dictionary] = _build_buff_options()
	if options.is_empty():
		return
	var GrowthChoicePanelScript := preload("res://scenes/ui/growth_choice_panel.gd")
	var panel: Node = GrowthChoicePanelScript.new()
	panel.set("panel_title", "波间增益")
	panel.set("options", options)
	panel.set("required_selection_count", 1)
	if not _level._open_overlay(BaseLevel.ActiveOverlay.GROWTH_CHOICE, panel, &"options_confirmed"):
		panel.queue_free()
		return
	var ids: Array = await panel.options_confirmed
	if ids.is_empty():
		return
	for id in ids:
		var picked: Dictionary = _find_option_by_id(options, String(id))
		if picked.is_empty():
			continue
		_apply_buff(picked)


func _find_option_by_id(options: Array[Dictionary], id: String) -> Dictionary:
	for opt in options:
		if opt.get("id", "") == id:
			return opt
	return {}


func _build_buff_options() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	# 静态 buff 池：逐条读 WaveBuffDef（unlock_wave 未到的不入池）
	for raw in _config.buffs:
		var def := raw as WaveBuffDef
		if def == null:
			continue
		if def.unlock_wave > 0 and _wave_index < def.unlock_wave:
			continue
		var opt := {
			"id": def.id,
			"name": def.display_name,
			"description": def.description,
			"_kind": def.kind,
			"_amount": def.amount,
			"_label": def.label,
		}
		if def.kind == "element_attach":
			opt["_element"] = def.element
		pool.append(opt)
	# 学技卡（filter已学）：名称 / 描述取自 SkillData，不进 .tres
	var hero_unit: Unit = _level.hero as Unit
	var hero_skills: Array = []
	if hero_unit != null and hero_unit.unit_data != null:
		hero_skills = hero_unit.unit_data.skills
	for sk in _config.learnable_skills:
		if sk in hero_skills:
			continue
		pool.append({
			"id": "grant_skill_%s" % sk.resource_path.get_file().get_basename(),
			"name": "学技：%s" % sk.skill_name,
			"description": sk.description,
			"_kind": "grant_skill", "_skill": sk,
			"_label": "技：" + sk.skill_name,
		})
	# 抽 3 个不同的
	pool.shuffle()
	var picked: Array[Dictionary] = []
	for opt in pool:
		picked.append(opt)
		if picked.size() >= 3:
			break
	return picked


func _apply_buff(opt: Dictionary) -> void:
	var hero_unit: Unit = _level.hero as Unit
	if hero_unit == null or hero_unit.combat_stats == null:
		return
	var stats: CombatStats = hero_unit.combat_stats
	match opt.get("_kind", ""):
		"hp_cap":
			var amt: int = int(opt.get("_amount", 0))
			var old_hp := stats.current_hp
			stats.max_hp += amt
			stats.current_hp = stats.max_hp
			_level.unit_hp_changed.emit(hero_unit, old_hp, stats.current_hp)
			hero_unit.refresh_overhead_bars()
		"ap_cap":
			var ap_amt: int = int(opt.get("_amount", 10))
			stats.ap_max += ap_amt
			stats.ap_current = mini(stats.ap_current + ap_amt, stats.ap_max)
			hero_unit.refresh_overhead_bars()
		"element_attach":
			var elt: int = int(opt.get("_element", Enums.Element.NONE))
			stats.current_element = elt as Enums.Element
			stats.current_element_amount = int(opt.get("_amount", 0))
			hero_unit.refresh_overhead_bars()
		"grant_skill":
			var sk: SkillData = opt.get("_skill", null)
			if sk:
				_level._get_unit_factory().grant_skill(hero_unit, sk)
	if _hud:
		_hud.add_buff(String(opt.get("_label", opt.get("name", ""))))
