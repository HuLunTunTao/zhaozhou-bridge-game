class_name UnitFactory
extends RefCounted

## 单位工厂 + 队伍编成组件（Tactics Stack）。
## 从 BaseLevel 抽出：单位运行时生成（含外观查表）/ 技能授予-收回-替换-修改 / 战斗数值覆写 / 队伍编成。
## 通过 setup(level) 持有宿主关卡，对 _level 保持鸭子调用，不反向依赖 BaseLevel。
## 不含场景引导（_find_*_tilemap / _get_all_units 等，3.10 SceneBootstrap，本文件走 _level._xxx 鸭子调用）。

## 单个队伍的运行时数据（真源在 TurnSystem，此处保留旧类型名供注解使用）。
const TeamData = TurnSystem.TeamData

## 敌方名称 → Visual 场景映射表。spawn_unit 会根据 unit_data.unit_name 自动应用外观。
## （真源外置 data/content_tables/monster_visuals.tres，此处 preload 读取。）
const MONSTER_VISUALS: Dictionary = preload("res://data/content_tables/monster_visuals.tres").entries

## 友方名称 → Visual 场景映射表。spawn_unit 在 MONSTER_VISUALS 未命中时回落到这里。
## （真源外置 data/content_tables/human_visuals.tres，此处 preload 读取。）
const HUMAN_VISUALS: Dictionary = preload("res://data/content_tables/human_visuals.tres").entries

var _level: Node = null   # BaseLevel 宿主


func setup(level: Node) -> void:
	_level = level


# ─────────────────────────────────────────────
# 队伍编成（RosterSetup，读取场景已有节点）
# ─────────────────────────────────────────────

func setup_teams_from_config(configs: Array) -> void:
	for i in range(configs.size()):
		var cfg: Dictionary = configs[i]
		var team := TeamData.new(
			cfg.get("name", "队伍%d" % i),
			cfg.get("faction", ""),
			cfg.get("controller", "ai")
		)
		for unit: Node2D in cfg.get("units", []):
			unit.team_index = i
			unit.faction = team.faction
			unit.movement_manager = _level.movement_manager
			# 从节点在编辑器中的位置推算所在格子并对齐到格子中心
			var snapped_cell: Vector2i = _level.tilemap.local_to_map(_level.tilemap.to_local(unit.global_position))
			unit.set_cell(snapped_cell, _level.tilemap)
			team.units.append(unit)
		_level.teams.append(team)

	# 向后兼容：hero 指向第一个玩家控制队伍的第一个单位
	for team: TeamData in _level.teams:
		if team.controller == "player" and not team.units.is_empty():
			_level.hero = team.units[0]
			break


# ─────────────────────────────────────────────
# 单位生成
# ─────────────────────────────────────────────

## 运行时生成一个单位。加入指定队伍，放置在指定 cell 的脚下。
## visual 可选：传入 PackedScene 直接指定外观，否则根据 unit_data.unit_name 自动查表。
func spawn_unit(unit_data: UnitData, cell: Vector2i, team_index: int, visual: PackedScene = null) -> Unit:
	var UnitScene := preload("res://scenes/unit/unit.tscn")
	var unit: Unit = UnitScene.instantiate()
	unit.unit_data = unit_data
	# 应用外观：优先使用传入的 visual，否则根据名称自动查表（先怪后人）
	var visual_to_use: PackedScene = visual
	if visual_to_use == null and unit_data:
		if MONSTER_VISUALS.has(unit_data.unit_name):
			visual_to_use = MONSTER_VISUALS[unit_data.unit_name]
		elif HUMAN_VISUALS.has(unit_data.unit_name):
			visual_to_use = HUMAN_VISUALS[unit_data.unit_name]
	if visual_to_use:
		unit.visual_scene = visual_to_use
	# 占位诊断：若目标格已有单位 → 输出 warning（不阻断；静态布局作者意图保留）
	for existing in _level._get_all_units():
		if is_instance_valid(existing) and existing is Unit and (existing as Unit).cell == cell:
			var existing_name: String = (existing as Unit).unit_data.unit_name if (existing as Unit).unit_data else "<unknown>"
			push_warning("spawn_unit: cell %s already occupied by %s; new unit will overlap" % [cell, existing_name])
			break
	# @export 引用在导出构建里可能为 null（AGENTS Pitfalls #2），沿用 _find_*_tilemap
	# 回退范式：@export → 运行时按名字查找 → 挂到关卡节点兜底，不崩。
	var unit_parent: Node = _level.obstacles_tilemap_layer
	if unit_parent == null:
		unit_parent = _level._find_obstacle_tilemap()
	if unit_parent == null:
		push_warning("obstacles_tilemap_layer is not set; spawning unit under level node")
		unit_parent = _level
	unit_parent.add_child(unit)
	unit.movement_manager = _level.movement_manager
	unit.set_cell(cell, _level.tilemap)
	if team_index >= 0 and team_index < _level.teams.size():
		var team: TeamData = _level.teams[team_index]
		unit.team_index = team_index
		unit.faction = team.faction
		team.units.append(unit)
	_level._apply_infinite_ally_actions_to_unit(unit)
	unit.apply_faction_outline()
	return unit


## 各关 `_spawn_enemy` 的共享底座：生成单位 + 配技能 + 覆写战斗数值。
## stats_override 可逐项覆盖（键：unit_name / max_hp / base_atk / ap_max / move_cost /
## element / element_amount），缺省按 unit_data 自身数值（1-3 / 1-4 形态）；1-2 传显式数值。
func spawn_enemy_unit(unit_data: UnitData, cell: Vector2i, team_index: int, skills: Array,
		visual: PackedScene = null, stats_override: Dictionary = {}) -> Unit:
	var unit := spawn_unit(unit_data, cell, team_index, visual)
	set_unit_skills(unit, skills)
	setup_unit_stats(
		unit,
		str(stats_override.get("unit_name", unit_data.unit_name)),
		int(stats_override.get("max_hp", unit_data.max_hp)),
		int(stats_override.get("base_atk", unit_data.base_atk)),
		int(stats_override.get("ap_max", unit_data.ap_max)),
		int(stats_override.get("move_cost", unit_data.move_cost_per_tile)),
		stats_override.get("element", unit_data.innate_element),
		int(stats_override.get("element_amount", unit_data.innate_element_amount)))
	return unit


# ─────────────────────────────────────────────
# 技能授予 / 收回 / 替换 / 修改
# ─────────────────────────────────────────────

## 授予单位一个新技能。幂等：若单位已有该技能则不做任何操作，不 emit 信号。
func grant_skill(unit: Unit, skill: SkillData) -> void:
	if unit == null or unit.unit_data == null or skill == null:
		return
	# 确保 unit_data 已 duplicate，避免污染磁盘资源
	if not unit.unit_data.resource_local_to_scene:
		unit.unit_data = unit.unit_data.duplicate()
		unit.unit_data.resource_local_to_scene = true
	if skill in unit.unit_data.skills:
		return
	unit.unit_data.skills.append(skill)
	_level.unit_gained_skill.emit(unit, skill)
	# 若正是当前选中单位，刷新状态栏
	if _level.selected_unit == unit:
		_level._update_status_bar_for_unit(unit, true)


## 收回单位的一个技能。若单位没有该技能则不做任何操作，不 emit 信号。
func revoke_skill(unit: Unit, skill: SkillData) -> void:
	if unit == null or unit.unit_data == null or skill == null:
		return
	if not skill in unit.unit_data.skills:
		return
	unit.unit_data.skills.erase(skill)
	_level.unit_lost_skill.emit(unit, skill)
	if _level.selected_unit == unit:
		_level._update_status_bar_for_unit(unit, true)


## 替换单位的全部技能列表。会 duplicate unit_data 避免修改共享资源。
func set_unit_skills(unit: Unit, skills: Array) -> void:
	if unit == null or unit.unit_data == null:
		return
	if not unit.unit_data.resource_local_to_scene:
		unit.unit_data = unit.unit_data.duplicate()
		unit.unit_data.resource_local_to_scene = true
	unit.unit_data.skills.clear()
	for s in skills:
		unit.unit_data.skills.append(s)
		_level.unit_gained_skill.emit(unit, s)
	if _level.selected_unit == unit:
		_level._update_status_bar_for_unit(unit, true)


func modify_unit_skill(unit: Unit, skill_id: String, changes: Dictionary) -> bool:
	if unit == null or unit.unit_data == null:
		return false
	for i in range(unit.unit_data.skills.size()):
		var skill := unit.unit_data.skills[i] as SkillData
		if skill == null or skill.skill_id != skill_id:
			continue
		var local_skill := skill.duplicate(true) as SkillData
		local_skill.resource_local_to_scene = true
		if changes.has("ap_cost"):
			local_skill.ap_cost = maxi(int(changes["ap_cost"]), 0)
		if changes.has("damage_ratio"):
			local_skill.damage_ratio = float(changes["damage_ratio"])
		if changes.has("duration_turns"):
			local_skill.duration_turns = maxi(int(changes["duration_turns"]), 0)
		if changes.has("cooldown_turns"):
			local_skill.cooldown_turns = maxi(int(changes["cooldown_turns"]), 0)
		unit.unit_data.skills[i] = local_skill
		if _level.selected_unit == unit:
			_level._update_status_bar_for_unit(unit, true)
		return true
	return false


func add_skill_to_unit(unit: Unit, skill: SkillData, replace_candidates: Array[String] = []) -> void:
	if unit == null or unit.unit_data == null or skill == null:
		return
	for existing in unit.unit_data.skills:
		var existing_skill := existing as SkillData
		if existing_skill != null and existing_skill.skill_id == skill.skill_id:
			return
	var new_skills: Array[SkillData] = []
	for existing in unit.unit_data.skills:
		new_skills.append(existing)
	if new_skills.size() >= 5:
		for replace_skill_id in replace_candidates:
			for i in range(new_skills.size()):
				if new_skills[i].skill_id == replace_skill_id:
					new_skills.remove_at(i)
					break
			if new_skills.size() < 5:
				break
	new_skills.append(skill)
	set_unit_skills(unit, new_skills)


# ─────────────────────────────────────────────
# 战斗数值
# ─────────────────────────────────────────────

## 在运行时覆写单位的战斗数值。修改后自动刷新头顶 UI。
## 注：hp / atk / ap 是"设计师视角的基线值"，会在 CombatStats.set_base_stats() 里
## 按当前难度系数烤进实际属性。这样难度切换对脚本生成的单位也生效。
func setup_unit_stats(unit: Unit, uname: String, hp: int, atk: int,
		ap: int, move_cost: int, elem: Enums.Element = Enums.Element.NONE,
		elem_amt: int = 0, is_hero_flag: bool = false) -> void:
	if unit == null or unit.combat_stats == null:
		return
	var s := unit.combat_stats
	s.unit_name = uname
	s.set_base_stats(hp, atk, ap)
	s.move_cost_per_tile = move_cost
	s.innate_element = elem
	s.innate_element_amount = elem_amt
	s.current_element = elem
	s.current_element_amount = elem_amt
	s.is_hero = is_hero_flag
	_level._apply_infinite_ally_actions_to_unit(unit)
	unit.refresh_overhead_bars()
	if unit.has_method("apply_faction_outline"):
		unit.apply_faction_outline()


# ─────────────────────────────────────────────
# 关卡开局装配底座（各关 _setup_li_chun / _setup_allies_from_scene 共用）
# ─────────────────────────────────────────────

## 英雄装配：Progress 技能池 + 强制补入缺失的核心交互技能 + 战斗数值覆写（is_hero=true）。
## 属性取自 roster 行（data/units/roster_*.tres，Step 4.8）；
## 技能表缺省取当前选中关卡的 Progress 配装。
func setup_hero_unit(unit: Unit, roster: RosterEntry, mandatory_skills: Array = []) -> void:
	if roster == null:
		push_warning("setup_hero_unit: roster 行缺失")
		return
	var skills: Array[SkillData] = Progress.get_battle_skill_resources(GameState.selected_level)
	for m in mandatory_skills:
		var skill := m as SkillData
		if skill != null and not skill_list_contains(skills, skill.skill_id):
			skills.append(skill)
	set_unit_skills(unit, skills)
	setup_unit_stats(unit, roster.unit_name, roster.max_hp, roster.base_atk, roster.ap_max,
			roster.move_cost, Enums.Element.NONE, 0, true)


## 批量装配队友：统一技能表 + 战斗数值（属性取自 roster 行）。
func setup_ally_group(units: Array, skills: Array, roster: RosterEntry) -> void:
	if roster == null:
		push_warning("setup_ally_group: roster 行缺失")
		return
	for u in units:
		var unit := u as Unit
		if unit == null:
			continue
		set_unit_skills(unit, skills)
		setup_unit_stats(unit, roster.unit_name, roster.max_hp, roster.base_atk, roster.ap_max,
				roster.move_cost)


## 按 roster 行覆写战斗数值的便捷入口（survival / test 等走 setup_unit_stats 的调用点用）。
func setup_unit_stats_from_roster(unit: Unit, roster: RosterEntry,
		elem: Enums.Element = Enums.Element.NONE, elem_amt: int = 0,
		is_hero_flag: bool = false) -> void:
	if roster == null:
		push_warning("setup_unit_stats_from_roster: roster 行缺失")
		return
	setup_unit_stats(unit, roster.unit_name, roster.max_hp, roster.base_atk, roster.ap_max,
			roster.move_cost, elem, elem_amt, is_hero_flag)


## 技能表里是否已有指定 skill_id。
func skill_list_contains(list: Array, skill_id: String) -> bool:
	for s in list:
		if s is SkillData and (s as SkillData).skill_id == skill_id:
			return true
	return false
