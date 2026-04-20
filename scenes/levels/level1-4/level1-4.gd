extends BaseLevel
## 第四关《敞肩试汛》

const PLAYER_TEAM := 0
const ENEMY_TEAM := 1

var _li_chun: Unit
var _craftsmen: Array[Unit] = []
var _stone_carriers: Array[Unit] = []
var _boss: Unit

var _overall_stability := 12
var _left_pier_stability := 6
var _right_pier_stability := 6
var _pending_enemy_resolution := false
var _boss_base_atk := 24

var _left_pier: Vector2i
var _right_pier: Vector2i
var _watch_point: Vector2i
var _side_arch_cells: Dictionary = {}
var _side_arch_states := {
	"left_front": "closed",
	"left_back": "closed",
	"right_front": "closed",
	"right_back": "closed",
}

var _hero_data: UnitData = preload("res://data/units/hero_li_chun.tres")
var _hero_visual: PackedScene = preload("res://scenes/unit/visual/human/li_chun/li_chun_visual.tscn")
var _survey_data: UnitData = preload("res://data/units/survey_worker.tres")
var _craftsman_data: UnitData = preload("res://data/units/craftsman_guard.tres")

# 第四关敌方单位（独立 .tres）
var _flood_spear_data: UnitData = preload("res://data/units/flood_spear.tres")
var _siltmare_data: UnitData = preload("res://data/units/siltmare.tres")
var _pier_gnawer_data: UnitData = preload("res://data/units/pier_gnawer.tres")
var _driftwood_data: UnitData = preload("res://data/units/flood_driftwood_pack.tres")
var _wrathful_flood_data: UnitData = preload("res://data/units/wrathful_flood.tres")

# 友军技能（复用）
var _staff: SkillData = preload("res://data/skills/sw_staff_end_strike.tres")
var _mallet: SkillData = preload("res://data/skills/cg_mallet_strike.tres")
var _guard: SkillData = preload("res://data/skills/cg_guard_the_works.tres")

# 漂木群技能（复用现有 dlp_drifting_timber_crash，设计稿的 fdp_driftwood_surge 属后续步骤）
var _timber: SkillData = preload("res://data/skills/dlp_drifting_timber_crash.tres")

# 第四关敌方技能（独立 .tres）
var _torrent_ram: SkillData = preload("res://data/skills/fs_torrent_ram.tres")
var _mire_steps: SkillData = preload("res://data/skills/sm_mire_steps.tres")
var _gnaw_pier: SkillData = preload("res://data/skills/pg_gnaw_pier.tres")
var _overturn_bridge: SkillData = preload("res://data/skills/wf_overturn_bridge.tres")

# 关卡配置资源（浅拆：数值 + anchor 偏移 + 波次模板；绝对 cell 运行时算）
var _stage_config: StageConfig = preload("res://data/stages/chapter1_stage4/stage_config.tres")
var _stability_config: BridgeStabilityConfig = preload("res://data/stages/chapter1_stage4/bridge_stability_config.tres")
var _side_arch_config: SideArchConfig = preload("res://data/stages/chapter1_stage4/side_arch_config.tres")
var _wave_spawns: WaveSpawns = preload("res://data/stages/chapter1_stage4/wave_spawns.tres")


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/Player" as Unit
	return [
		{
			"name": "守桥队",
			"faction": "好人",
			"controller": "player",
			"units": [_li_chun],
		},
		{
			"name": "洪灾",
			"faction": "坏人",
			"controller": "ai",
			"units": [],
		},
	]


func get_wave_config() -> Dictionary:
	var waves: Dictionary = {}
	for entry in _wave_spawns.entries:
		if entry == null:
			continue
		var round_num: int = entry.round_number
		var unit_kind: String = entry.unit_kind
		var cell_hint: String = entry.cell_hint
		var unit_bundle := _resolve_wave_unit(unit_kind)
		if unit_bundle.is_empty():
			push_warning("wave_spawns: 未知 unit_kind '%s'" % unit_kind)
			continue
		var cell := _resolve_cell_hint(cell_hint)
		var wave_item := {
			"unit_data": unit_bundle["unit_data"],
			"cell": cell,
			"team_index": ENEMY_TEAM,
			"skills": unit_bundle["skills"],
		}
		if not waves.has(round_num):
			waves[round_num] = []
		waves[round_num].append(wave_item)
	return waves


# 把 unit_kind 字符串 → (UnitData 副本, 技能列表)。遵循原 get_wave_config 中的映射。
func _resolve_wave_unit(kind: String) -> Dictionary:
	match kind:
		"flood_spear":
			return {"unit_data": _duplicate_unit_data(_flood_spear_data), "skills": [_torrent_ram]}
		"siltmare":
			return {"unit_data": _duplicate_unit_data(_siltmare_data), "skills": [_mire_steps]}
		"pier_gnawer":
			return {"unit_data": _duplicate_unit_data(_pier_gnawer_data), "skills": [_gnaw_pier]}
		"flood_driftwood_pack":
			return {"unit_data": _duplicate_unit_data(_driftwood_data), "skills": [_timber]}
	return {}


# cell_hint 字符串 → 绝对格。依赖 _watch_point / _left_pier / _right_pier / _side_arch_cells 已就位。
func _resolve_cell_hint(hint: String) -> Vector2i:
	match hint:
		"near_left_pier_west":
			return _nearest_walkable(_left_pier + Vector2i(-2, 0))
		"near_right_pier_east":
			return _nearest_walkable(_right_pier + Vector2i(2, 0))
		"watch_north_2":
			return _watch_point + Vector2i(0, -2)
		"arch_left_front_north_2":
			return _side_arch_cells["left_front"] + Vector2i(0, -2)
		"arch_right_front_north_2":
			return _side_arch_cells["right_front"] + Vector2i(0, -2)
	push_warning("wave_spawns: 未知 cell_hint '%s'，退回 watch_point" % hint)
	return _watch_point


# 复制 UnitData 以避免多实例共享同一 Resource 副作用（原 _make_unit_data 的精简版，
# 字段全部沿用 base .tres；ally 方向仍用 _make_unit_data 做字段覆盖）。
func _duplicate_unit_data(base: UnitData) -> UnitData:
	var data := base.duplicate(true) as UnitData
	data.resource_local_to_scene = true
	return data


func get_objectives_text() -> Dictionary:
	return {
		"victory": [
			"- 开启更多小拱以减轻洪压",
			"- 保护左右桥台与整桥稳定值",
			"- 击退怒水",
		],
		"defeat": [
			"- 李春倒下",
			"- 左右桥台任一崩溃",
			"- 整桥稳定值归零",
			"- 超过第 15 回合",
		],
	}


func check_victory() -> bool:
	return _boss != null and _boss.combat_stats != null and not _boss.combat_stats.is_alive()


func check_defeat() -> String:
	if _li_chun == null or _li_chun.combat_stats == null or not _li_chun.combat_stats.is_alive():
		return "李春倒下"
	if _overall_stability <= 0:
		return "整桥稳定值耗尽"
	if _left_pier_stability <= 0:
		return "左桥台崩毁"
	if _right_pier_stability <= 0:
		return "右桥台崩毁"
	if round_number > _stage_config.turn_limit:
		return "超过第 %d 回合" % _stage_config.turn_limit
	return ""


func _on_level_ready() -> void:
	_overall_stability = _stability_config.initial_overall
	_left_pier_stability = _stability_config.initial_left_pier
	_right_pier_stability = _stability_config.initial_right_pier
	_setup_anchor_cells()
	_setup_li_chun()
	_spawn_allies()
	_spawn_enemies()
	team_turn_started.connect(_on_stage_team_turn_started)
	unit_hp_changed.connect(_on_stage_hp_changed)
	Notify.notify("李春与运石工可开启小拱；运石工可抢修桥台", Notify.Position.TOP_CENTER, Notify.Style.INFO, 3.0)


func _on_unit_moved() -> void:
	if selected_unit == null or not (selected_unit is Unit):
		return
	var unit := selected_unit as Unit
	_try_open_side_arch(unit)
	_try_repair_pier(unit)


func _on_skill_executed(caster: Unit, skill: SkillData, cast_cell: Vector2i, _exec_result: SkillExecutor.ExecuteResult) -> void:
	if caster == _li_chun and skill.skill_id == "lc_guide_flood_open_arch":
		for arch_key in _side_arch_cells.keys():
			if cast_cell == _side_arch_cells[arch_key]:
				_open_arch(arch_key, "导汛开肩")
		return

	# 洪锋 / 漂木群·洪水版 的冲撞线命中桥台 → 对应桥台 -1（设计稿 §1.3）
	if caster == null or caster.combat_stats == null:
		return
	var unit_name_str := caster.combat_stats.unit_name
	if unit_name_str != "洪锋" and unit_name_str != "漂木群·洪水版":
		return
	var path := _charge_line_cells(caster.cell, cast_cell)
	var hit_left := _left_pier in path
	var hit_right := _right_pier in path
	if hit_left:
		_left_pier_stability -= 1
		Notify.notify("%s 冲撞左桥台！稳定值 %d" % [unit_name_str, _left_pier_stability], Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 2.5)
	if hit_right:
		_right_pier_stability -= 1
		Notify.notify("%s 冲撞右桥台！稳定值 %d" % [unit_name_str, _right_pier_stability], Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 2.5)
	if hit_left or hit_right:
		_check_win_lose()


# 从冲撞发起格到目标格的直线覆盖单元（不含起始格，含目标格）。
# 线性攻击通常沿 4 向或 8 向展开，此处用 Chebyshev 步进兼容两种情况。
func _charge_line_cells(from_cell: Vector2i, to_cell: Vector2i) -> Array:
	var cells: Array = []
	var dx := signi(to_cell.x - from_cell.x)
	var dy := signi(to_cell.y - from_cell.y)
	if dx == 0 and dy == 0:
		return cells
	var steps := maxi(absi(to_cell.x - from_cell.x), absi(to_cell.y - from_cell.y))
	var cur := from_cell
	for i in range(steps):
		cur += Vector2i(dx, dy)
		cells.append(cur)
	return cells


# ─────────────────────────────────────────────
# 防御兜底：失败条件触发测试（调试键）
# Ctrl+1 李春死亡 / Ctrl+2 整桥归零 / Ctrl+3 左桥台归零 / Ctrl+4 右桥台归零 / Ctrl+5 回合>15
# Ctrl+6 强制翻潮压桥 / Ctrl+7 强制怒涛拍面
# 注意：F5/F6/F8 被 Godot 编辑器占用（Run / Run Scene / Stop），改用 Ctrl+数字避开。
# 仅在 OS.is_debug_build() 下启用，发布版自动失效。
# ─────────────────────────────────────────────
func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if not key_event.ctrl_pressed:
		return
	match key_event.keycode:
		KEY_1:
			_debug_force_defeat("li_chun_down")
		KEY_2:
			_debug_force_defeat("overall_zero")
		KEY_3:
			_debug_force_defeat("left_pier_zero")
		KEY_4:
			_debug_force_defeat("right_pier_zero")
		KEY_5:
			_debug_force_defeat("round_over")
		KEY_6:
			_cast_overturn_bridge()
		KEY_7:
			_boss_slam_deck()


func _debug_force_defeat(kind: String) -> void:
	match kind:
		"li_chun_down":
			if _li_chun and _li_chun.combat_stats:
				_li_chun.combat_stats.current_hp = 0
				_li_chun.refresh_overhead_bars()
		"overall_zero":
			_overall_stability = 0
		"left_pier_zero":
			_left_pier_stability = 0
		"right_pier_zero":
			_right_pier_stability = 0
		"round_over":
			round_number = 16
	Notify.notify("[DEBUG] 强制触发失败：%s" % kind, Notify.Position.TOP_CENTER, Notify.Style.ERROR, 2.0)
	_check_win_lose()


# ─────────────────────────────────────────────
# Boss 怒水：翻潮压桥（敌方回合开始）+ 怒涛拍面（敌方回合结束）
# 设计稿 §5.5。翻潮压桥效果 3「激流压区」延后到 TODO 第 5 步地格做。
# ─────────────────────────────────────────────
func _cast_overturn_bridge() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	# 效果1：较低稳定桥台 -1（平局打左，与全闭态惩罚方向一致）
	if _left_pier_stability <= _right_pier_stability:
		_left_pier_stability -= 1
	else:
		_right_pier_stability -= 1
	# 效果2：开启小拱 ≤ 1 时整桥 -1
	if _open_arch_count() <= 1:
		_overall_stability -= 1
	# 效果3：TODO(step5) 在桥面边缘线叠加激流压区 1 回合（tile 级效果，依赖特殊地格基建）
	Notify.notify("怒水释放【翻潮压桥】", Notify.Position.CENTER, Notify.Style.WARNING, 2.5)
	_check_win_lose()


func _boss_slam_deck() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	var candidates: Array = []
	for ally in get_friendly_units():
		if ally == null or ally.combat_stats == null or not ally.combat_stats.is_alive():
			continue
		if not _is_on_main_bridge(ally.cell):
			continue
		if _has_guarding_status(ally):
			continue
		candidates.append(ally)
	if candidates.is_empty():
		return
	var boss_cell := _boss.cell
	candidates.sort_custom(func(a: Unit, b: Unit) -> bool:
		return _manhattan(a.cell, boss_cell) < _manhattan(b.cell, boss_cell)
	)
	var target: Unit = candidates[0]
	var dmg := roundi(float(_boss.combat_stats.base_atk) * 0.5)
	var old_hp := target.combat_stats.current_hp
	target.combat_stats.current_hp = maxi(old_hp - dmg, 0)
	target.refresh_overhead_bars()
	unit_hp_changed.emit(target, old_hp, target.combat_stats.current_hp)
	Notify.notify("怒涛拍面：%s 受 %d 伤害" % [target.combat_stats.unit_name, dmg], Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 2.5)
	if target.combat_stats.current_hp <= 0:
		unit_died.emit(target)
	_check_win_lose()


func _is_on_main_bridge(cell: Vector2i) -> bool:
	# 主桥面 = 以 _watch_point 为中轴的 3 格横带。第 5 步做特殊地格后用 tile 类型替换。
	return absi(cell.y - _watch_point.y) <= 1


func _has_guarding_status(unit: Unit) -> bool:
	if unit == null or unit.combat_stats == null:
		return false
	for s in unit.combat_stats.statuses:
		# guarded_cover：工匠「捍作护行」已实现
		# steady_bridge：李春「导汛开肩」赠送（尚未接入，钩子预留）
		if s.status_id == "guarded_cover" or s.status_id == "steady_bridge":
			return true
	return false


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _on_stage_team_turn_started(team_index: int) -> void:
	if team_index == ENEMY_TEAM:
		_pending_enemy_resolution = true
		_sync_boss_pressure()
		_cast_overturn_bridge()
	elif team_index == PLAYER_TEAM and _pending_enemy_resolution:
		_pending_enemy_resolution = false
		_resolve_enemy_pressure()
		_boss_slam_deck()
		_sync_boss_pressure()


func _on_stage_hp_changed(unit: Unit, old_hp: int, new_hp: int) -> void:
	if unit != _boss or new_hp >= old_hp:
		return
	var damage := old_hp - new_hp
	var cap := _boss_damage_cap()
	if damage > cap:
		unit.combat_stats.current_hp = old_hp - cap
		unit.refresh_overhead_bars()


func _setup_anchor_cells() -> void:
	var anchor := _li_chun.cell
	_watch_point = _nearest_walkable(anchor + Vector2i(0, -1))
	_left_pier = _nearest_walkable(anchor + Vector2i(-4, 0))
	_right_pier = _nearest_walkable(anchor + Vector2i(4, 0))
	_side_arch_cells = {
		"left_front": _nearest_walkable(anchor + _side_arch_config.left_front_offset),
		"left_back": _nearest_walkable(anchor + _side_arch_config.left_back_offset),
		"right_front": _nearest_walkable(anchor + _side_arch_config.right_front_offset),
		"right_back": _nearest_walkable(anchor + _side_arch_config.right_back_offset),
	}


func _setup_li_chun() -> void:
	_li_chun.apply_runtime_setup(_hero_data, _hero_visual, Color(1, 0.85, 0, 1))
	set_unit_skills(_li_chun, Progress.get_battle_skill_resources(GameState.selected_level))
	setup_unit_stats(_li_chun, "李春", 138, 26, 105, 8, Enums.Element.NONE, 0, true)


func _spawn_allies() -> void:
	_craftsmen = [
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 120, 20, 95, 9), _nearest_walkable(_left_pier + Vector2i(0, -1)), [_mallet, _guard]),
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 120, 20, 95, 9), _nearest_walkable(_right_pier + Vector2i(0, -1)), [_mallet, _guard]),
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 120, 20, 95, 9), _nearest_walkable(_watch_point + Vector2i(0, 1)), [_mallet, _guard]),
	]
	_stone_carriers = [
		_spawn_ally(_make_unit_data(_survey_data, "运石工", 92, 14, 95, 9), _nearest_walkable(_side_arch_cells["left_back"] + Vector2i(-1, 1)), [_staff]),
		_spawn_ally(_make_unit_data(_survey_data, "运石工", 92, 14, 95, 9), _nearest_walkable(_side_arch_cells["right_back"] + Vector2i(1, 1)), [_staff]),
	]
	_apply_persistent_growth_effects()


func _apply_persistent_growth_effects() -> void:
	if Progress.has_growth_option("growth_training_mobilize"):
		for unit in get_friendly_units():
			apply_unit_growth_bonus(unit, 10, 0, 5)
	if Progress.has_growth_option("growth_maps_measures"):
		apply_unit_growth_bonus(get_hero_unit(), 0, 4, 0)
		modify_unit_skill(get_hero_unit(), "lc_rule_strike", {"damage_ratio": 1.05})
	if Progress.has_growth_option("growth_stone_reinforce"):
		for craftsman in _craftsmen:
			modify_unit_skill(craftsman, "cg_guard_the_works", {"duration_turns": 3})
	if Progress.has_growth_option("growth_drawing_discipline"):
		apply_unit_growth_bonus(get_hero_unit(), 0, 4, 0)
		modify_unit_skill(get_hero_unit(), "lc_divider_mark_arc", {"damage_ratio": 0.95})
	if Progress.has_growth_option("growth_center_hold"):
		for craftsman in _craftsmen:
			apply_unit_growth_bonus(craftsman, 10, 2, 0)
	if Progress.has_growth_option("growth_balance_method"):
		apply_unit_growth_bonus(get_hero_unit(), 0, 0, 5)
		modify_unit_skill(get_hero_unit(), "lc_inkline_balance_arch", {"cooldown_turns": 1})
	if Progress.has_growth_option("growth_joint_finish"):
		apply_unit_growth_bonus(get_hero_unit(), 0, 4, 0)
	if Progress.has_growth_option("growth_team_hold"):
		for craftsman in _craftsmen:
			apply_unit_growth_bonus(craftsman, 10, 0, 0)
		for carrier in _stone_carriers:
			apply_unit_growth_bonus(carrier, 0, 0, 5)


func _spawn_enemies() -> void:
	_boss = _spawn_enemy(_make_unit_data(_wrathful_flood_data, "怒水", 360, 24, 1, 99, Enums.Element.WATER, 2), _watch_point + Vector2i(0, -3), [_overturn_bridge], preload("res://scenes/unit/visual/monster/洪峰/洪峰_visual.tscn"))
	_spawn_enemy(_make_unit_data(_flood_spear_data, "洪锋", 98, 24, 90, 10, Enums.Element.WATER, 2), _watch_point + Vector2i(0, -1), [_torrent_ram], preload("res://scenes/unit/visual/monster/洪峰/洪峰_visual.tscn"))
	_spawn_enemy(_make_unit_data(_flood_spear_data, "洪锋", 98, 24, 90, 10, Enums.Element.WATER, 2), _right_pier + Vector2i(1, -1), [_torrent_ram], preload("res://scenes/unit/visual/monster/洪峰/洪峰_visual.tscn"))
	_spawn_enemy(_make_unit_data(_siltmare_data, "泥沙魇", 84, 18, 90, 10, Enums.Element.EARTH, 2), _side_arch_cells["left_front"] + Vector2i(-1, 0), [_mire_steps], preload("res://scenes/unit/visual/monster/泥沙魇/泥沙魇_visual.tscn"))


func _try_open_side_arch(unit: Unit) -> void:
	if unit != _li_chun and unit not in _stone_carriers:
		return
	for arch_key in _side_arch_cells.keys():
		if not _is_adjacent_or_same(unit.cell, _side_arch_cells[arch_key]):
			continue
		var cost := 30 if unit == _li_chun else 35
		if unit.combat_stats.ap_current < cost:
			return
		unit.combat_stats.ap_current -= cost
		unit.refresh_overhead_bars()
		_open_arch(arch_key, "%s 启肩泄洪" % unit.combat_stats.unit_name)
		return


func _try_repair_pier(unit: Unit) -> void:
	if unit not in _stone_carriers or unit.combat_stats.ap_current < 40:
		return
	if _is_adjacent_or_same(unit.cell, _left_pier) and _left_pier_stability < _stability_config.pier_max:
		unit.combat_stats.ap_current -= 40
		unit.refresh_overhead_bars()
		_left_pier_stability = mini(_left_pier_stability + 1, _stability_config.pier_max)
		Notify.notify("左桥台抢修完成，稳定值 %d" % _left_pier_stability, Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 2.0)
	elif _is_adjacent_or_same(unit.cell, _right_pier) and _right_pier_stability < _stability_config.pier_max:
		unit.combat_stats.ap_current -= 40
		unit.refresh_overhead_bars()
		_right_pier_stability = mini(_right_pier_stability + 1, _stability_config.pier_max)
		Notify.notify("右桥台抢修完成，稳定值 %d" % _right_pier_stability, Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 2.0)


func _open_arch(arch_key: String, reason: String) -> void:
	_side_arch_states[arch_key] = "open"
	Notify.notify("%s  已开启小拱 %d / 4" % [reason, _open_arch_count()], Notify.Position.TOP_RIGHT, Notify.Style.INFO, 2.0)


func _sync_boss_pressure() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	_boss.combat_stats.base_atk = roundi(_boss_base_atk * 0.85) if _open_arch_count() >= 4 else _boss_base_atk


func _resolve_enemy_pressure() -> void:
	for arch_key in _side_arch_cells.keys():
		if _side_arch_states[arch_key] == "blocked":
			_side_arch_states[arch_key] = "closed"
	for enemy in teams[ENEMY_TEAM].units:
		if not (enemy is Unit) or enemy.combat_stats == null or not enemy.combat_stats.is_alive():
			continue
		if enemy.combat_stats.unit_name == "漂木群·洪水版":
			for arch_key in _side_arch_cells.keys():
				if enemy.cell == _side_arch_cells[arch_key]:
					_side_arch_states[arch_key] = "blocked"

	var open_count := _open_arch_count()
	if open_count == 0:
		_overall_stability -= 2
		if _left_pier_stability <= _right_pier_stability:
			_left_pier_stability -= 1
		else:
			_right_pier_stability -= 1
	elif open_count == 1:
		_overall_stability -= 2
	elif open_count == 2:
		_overall_stability -= 1

	for enemy in teams[ENEMY_TEAM].units:
		if not (enemy is Unit) or enemy.combat_stats == null or not enemy.combat_stats.is_alive():
			continue
		if enemy.combat_stats.unit_name == "桥台噬者":
			if _is_adjacent_or_same(enemy.cell, _left_pier):
				_left_pier_stability -= 1
			if _is_adjacent_or_same(enemy.cell, _right_pier):
				_right_pier_stability -= 1
		if enemy.combat_stats.unit_name == "泥沙魇" and _is_adjacent_or_same(enemy.cell, _watch_point):
			_overall_stability -= 1

	Notify.notify("整桥:%d 左桥台:%d 右桥台:%d 小拱:%d/4" % [_overall_stability, _left_pier_stability, _right_pier_stability, open_count], Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 2.5)
	_check_win_lose()


func _get_ai_context() -> Dictionary:
	return {
		"drift_directions": {
			"漂木群·洪水版": Vector2i(0, 1),
		}
	}


func _is_adjacent_or_same(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) <= 1


func _open_arch_count() -> int:
	var count := 0
	for arch_key in _side_arch_states.keys():
		if _side_arch_states[arch_key] == "open":
			count += 1
	return count


func _boss_damage_cap() -> int:
	match _open_arch_count():
		0:
			return 1
		1:
			return 6
		2:
			return 12
		_:
			return 9999


func _spawn_ally(data: UnitData, cell: Vector2i, skills: Array[SkillData]) -> Unit:
	var unit := spawn_unit(data, cell, PLAYER_TEAM)
	set_unit_skills(unit, skills)
	setup_unit_stats(unit, data.unit_name, data.max_hp, data.base_atk, data.ap_max, data.move_cost_per_tile)
	return unit


func _spawn_enemy(data: UnitData, cell: Vector2i, skills: Array[SkillData], visual: PackedScene = null) -> Unit:
	var unit := spawn_unit(data, _nearest_walkable(cell), ENEMY_TEAM, visual)
	set_unit_skills(unit, skills)
	setup_unit_stats(unit, data.unit_name, data.max_hp, data.base_atk, data.ap_max, data.move_cost_per_tile, data.innate_element, data.innate_element_amount)
	return unit


func _make_unit_data(base: UnitData, unit_name: String, max_hp: int, base_atk: int, ap_max: int, move_cost: int, element: Enums.Element = Enums.Element.NONE, element_amount: int = 0) -> UnitData:
	var data := base.duplicate(true) as UnitData
	data.resource_local_to_scene = true
	data.unit_name = unit_name
	data.max_hp = max_hp
	data.base_atk = base_atk
	data.ap_max = ap_max
	data.move_cost_per_tile = move_cost
	data.innate_element = element
	data.innate_element_amount = element_amount
	return data


func _nearest_walkable(target: Vector2i) -> Vector2i:
	if movement_manager.get_movement_cost(target) != TileType.IMPASSABLE:
		return target
	for radius in range(1, 4):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var candidate := target + Vector2i(dx, dy)
				if movement_manager.get_movement_cost(candidate) != TileType.IMPASSABLE:
					return candidate
	return target
