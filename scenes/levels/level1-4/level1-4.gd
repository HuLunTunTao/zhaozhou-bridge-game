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

# 特殊地格容器（运行时 register_special_tile）
const SmallArchTileClass := preload("res://scenes/levels/level1-4/small_arch_tile.gd")
const SiltTileClass := preload("res://scenes/levels/level1-4/silt_tile.gd")
const RapidEdgeTileClass := preload("res://scenes/levels/level1-4/rapid_edge_tile.gd")

var _arch_tiles: Dictionary = {}          # arch_key → SmallArchTile
var _silt_tiles: Dictionary = {}          # cell → SiltTile
var _rapid_edge_tiles: Dictionary = {}    # cell → RapidEdgeTile


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
			"- 保护李春与左右桥台，熬过汛情",
			"- 引导运石工与李春开启小拱泄洪（共 4 座）",
			"- 开肩越多，怒水压制越弱；全开后击退怒水即可收束",
		],
		"defeat": [
			"- 李春倒下",
			"- 左右桥台任一崩溃（稳定值降至 0）",
			"- 整桥稳定值归零",
			"- 超过第 15 回合未能压退怒水",
		],
	}


func check_victory() -> bool:
	return _boss != null and _boss.combat_stats != null and not _boss.combat_stats.is_alive()


# 通关时额外写入章节旗标 + 结算记录（设计稿 §9）。
# 注意：super.complete_level() 内部会调 Progress.complete_level 标记关卡完成并
# 切场到 post 过场动画；本函数在它之前先把 summary 和 chapter flag 落盘。
func complete_level() -> void:
	_record_clear_summary()
	Progress.set_chapter_flag("chapter_1", true)
	super()


func _record_clear_summary() -> void:
	var full_release: bool = _open_arch_count() >= 4
	var summary: Dictionary = {
		"turns": round_number,
		"overall_stability_left": _overall_stability,
		"left_pier_stability_left": _left_pier_stability,
		"right_pier_stability_left": _right_pier_stability,
		"open_arches": _open_arch_count(),
		"full_release_kill": full_release,
		"li_chun_stage_title": "安桥者",
	}
	Progress.set_level_clear_summary("关卡1-4", summary)
	CombatLog.msg("结算: 回合 %d | 整桥 %d | 左/右 %d/%d | 小拱 %d/4 | 全泄%s | 称号「安桥者」" % [
		summary["turns"], summary["overall_stability_left"],
		summary["left_pier_stability_left"], summary["right_pier_stability_left"],
		summary["open_arches"], "✓" if full_release else "✗",
	])


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
	_setup_arch_tiles()
	_setup_li_chun()
	_spawn_allies()
	_spawn_enemies()
	team_turn_started.connect(_on_stage_team_turn_started)
	unit_hp_changed.connect(_on_stage_hp_changed)
	round_started.connect(_on_stage_round_started)
	phase_changed.connect(_on_phase_changed_for_onboarding)
	Notify.notify("李春与运石工可开启小拱；运石工可抢修桥台", Notify.Position.TOP_CENTER, Notify.Style.INFO, 3.0)


# 轻教学：进入 PLAYING 阶段后在开局几回合分段 Notify 提示关键机制。
# 不做 level1-1 那种完整对话教程，仅给关键词提醒。
func _on_phase_changed_for_onboarding(new_phase: int) -> void:
	if new_phase != LevelPhase.PLAYING:
		return
	_onboarding_hints()


func _onboarding_hints() -> void:
	# 开场即提示；每条间隔 0.8 秒避免重叠。
	await get_tree().create_timer(0.6).timeout
	if is_phase_ended():
		return
	Notify.notify("怒水登场：每回合压桥 + 桥面边缘生成激流带", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 4.0)
	await get_tree().create_timer(0.8).timeout
	if is_phase_ended():
		return
	Notify.notify("李春开肩 30AP / 运石工开肩 35AP；运石工抢修桥台 40AP", Notify.Position.TOP_CENTER, Notify.Style.INFO, 4.0)
	await get_tree().create_timer(0.8).timeout
	if is_phase_ended():
		return
	Notify.notify("开 1/2/3/4 肩 → Boss 伤害上限 1/6/12/∞；全开 Boss -15% 伤", Notify.Position.TOP_CENTER, Notify.Style.INFO, 5.0)


# 在 4 个小拱格注册 SmallArchTile 用作状态指示（closed/open/blocked）。
# 实际状态仍存在 _side_arch_states，这些 tile 只是它的视觉镜像。
func _setup_arch_tiles() -> void:
	for arch_key in _side_arch_cells.keys():
		var tile: SmallArchTile = _make_small_arch_tile()
		var cell: Vector2i = _side_arch_cells[arch_key]
		register_special_tile(tile, cell)
		_arch_tiles[arch_key] = tile


func _make_small_arch_tile() -> SmallArchTile:
	var tile := SmallArchTileClass.new() as SmallArchTile
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([0, -16, 16, -8, 0, 0, -16, -8])
	tile.add_child(visual)
	return tile


func _make_silt_tile() -> SiltTile:
	var tile := SiltTileClass.new() as SiltTile
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([0, -16, 16, -8, 0, 0, -16, -8])
	tile.add_child(visual)
	return tile


func _make_rapid_edge_tile() -> RapidEdgeTile:
	var tile := RapidEdgeTileClass.new() as RapidEdgeTile
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([0, -16, 16, -8, 0, 0, -16, -8])
	tile.add_child(visual)
	return tile


# SmallArchTile 状态同步：每次改 _side_arch_states 都走这里。
func _set_arch_state(arch_key: String, new_state: String) -> void:
	_side_arch_states[arch_key] = new_state
	var tile: SmallArchTile = _arch_tiles.get(arch_key)
	if tile != null:
		tile.set_state(new_state)


func _on_stage_round_started(_r: int) -> void:
	_expire_transient_tiles()


# 定期清理过期的临时地格（淤泥 2 回合 / 激流桥缘 1 回合）。
func _expire_transient_tiles() -> void:
	var round_now := round_number
	for cell in _silt_tiles.keys().duplicate():
		var tile: SiltTile = _silt_tiles[cell]
		if tile == null or not is_instance_valid(tile) or tile.is_expired(round_now):
			if is_instance_valid(tile):
				tile.queue_free()
			_silt_tiles.erase(cell)
	for cell in _rapid_edge_tiles.keys().duplicate():
		var tile: RapidEdgeTile = _rapid_edge_tiles[cell]
		if tile == null or not is_instance_valid(tile) or tile.is_expired(round_now):
			if is_instance_valid(tile):
				tile.queue_free()
			_rapid_edge_tiles.erase(cell)


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

	# 击退可能把单位推到激流桥缘上；_force_move_cell 直接改 cell 不走
	# tile_entered 信号，所以这里统一扫一遍所有单位。
	_apply_rapid_edge_if_present()


# 扫描所有单位当前格，若踩在 RapidEdgeTile 上就触发其伤害逻辑。
# 限用于技能结算后（击退 / 拖拽都在 skill_executor 里完成，结算完才落格）。
func _apply_rapid_edge_if_present() -> void:
	if _rapid_edge_tiles.is_empty():
		return
	for team in teams:
		for node in team.units:
			if not (node is Unit):
				continue
			var u := node as Unit
			if u.combat_stats == null or not u.combat_stats.is_alive():
				continue
			var tile: RapidEdgeTile = _rapid_edge_tiles.get(u.cell)
			if tile == null or not is_instance_valid(tile):
				continue
			tile.apply_knockback_damage(u)
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
# Ctrl+6 强制翻潮压桥 / Ctrl+7 强制怒涛拍面 / Ctrl+8 强杀 Boss 验证结算
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
		KEY_8:
			_debug_force_boss_kill()


func _debug_force_boss_kill() -> void:
	if _boss == null or _boss.combat_stats == null:
		return
	var old_hp: int = _boss.combat_stats.current_hp
	_boss.combat_stats.current_hp = 0
	_boss.refresh_overhead_bars()
	unit_hp_changed.emit(_boss, old_hp, 0)
	unit_died.emit(_boss)
	Notify.notify("[DEBUG] 强杀 Boss → 验证结算", Notify.Position.TOP_CENTER, Notify.Style.INFO, 2.0)
	_check_win_lose()


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
	# 效果3：桥面上下边缘生成激流桥缘 1 回合
	_spawn_rapid_edges_for_overturn()
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
		# 洪锋「涌锋」被动：首次移动 +1 格。AP 重置在 emit 之后才跑，所以 defer 到重置后再给。
		_apply_flood_spear_surge.call_deferred()
		# 淤泥「淤行」持续效果：上回合在淤泥上结束行动的，本回合 -2 AP
		_apply_silt_lingering_penalty.call_deferred(ENEMY_TEAM)
	elif team_index == PLAYER_TEAM and _pending_enemy_resolution:
		_pending_enemy_resolution = false
		_resolve_enemy_pressure()
		_boss_slam_deck()
		_sync_boss_pressure()
		_apply_silt_lingering_penalty.call_deferred(PLAYER_TEAM)


# 洪锋·被动【涌锋】：本回合首次移动 +1 格。
# AI 每回合只行动一次，等价于给它本回合多 1 格 AP。base_level._start_team_turn
# 在 emit team_turn_started 之后才调 reset_turn_counters，所以这里用 call_deferred
# 延后到重置之后再加，保证不被 ap_max 覆盖。
func _apply_flood_spear_surge() -> void:
	if teams.size() <= ENEMY_TEAM:
		return
	for enemy in teams[ENEMY_TEAM].units:
		if not (enemy is Unit):
			continue
		var u := enemy as Unit
		if u.combat_stats == null or not u.combat_stats.is_alive():
			continue
		if u.combat_stats.unit_name != "洪锋":
			continue
		u.combat_stats.ap_current += u.combat_stats.move_cost_per_tile
		u.refresh_overhead_bars()


# 淤泥「淤行」第二层效果：上回合在淤泥上结束行动 → 本回合开头扣 2 AP
# （等价于"下回合首次移动额外 -2 AP"——AI/玩家用同一个 AP 池，先扣等于首次移动多花 2）。
# 敌方回合和我方回合各自独立触发；单位当前格就是「上回合结束位置」。
func _apply_silt_lingering_penalty(team_index: int) -> void:
	if _silt_tiles.is_empty() or teams.size() <= team_index:
		return
	for node in teams[team_index].units:
		if not (node is Unit):
			continue
		var u := node as Unit
		if u.combat_stats == null or not u.combat_stats.is_alive():
			continue
		if not _silt_tiles.has(u.cell):
			continue
		var before: int = u.combat_stats.ap_current
		u.combat_stats.ap_current = maxi(before - 2, 0)
		u.refresh_overhead_bars()
		CombatLog.msg("  淤行持续: %s 从淤泥中起步 -2AP (%d → %d)" % [u.combat_stats.unit_name, before, u.combat_stats.ap_current])


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
	_boss = _spawn_enemy(_make_unit_data(_wrathful_flood_data, "怒水", 360, 24, 1, 99, Enums.Element.WATER, 2), _watch_point + Vector2i(0, -3), [_overturn_bridge], preload("res://scenes/unit/visual/monster/怒水/怒水_visual.tscn"))
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
	_set_arch_state(arch_key, "open")
	Notify.notify("%s  已开启小拱 %d / 4" % [reason, _open_arch_count()], Notify.Position.TOP_RIGHT, Notify.Style.INFO, 2.0)


func _sync_boss_pressure() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	_boss.combat_stats.base_atk = roundi(_boss_base_atk * 0.85) if _open_arch_count() >= 4 else _boss_base_atk


func _resolve_enemy_pressure() -> void:
	for arch_key in _side_arch_cells.keys():
		if _side_arch_states[arch_key] == "blocked":
			_set_arch_state(arch_key, "closed")
	for enemy in teams[ENEMY_TEAM].units:
		if not (enemy is Unit) or enemy.combat_stats == null or not enemy.combat_stats.is_alive():
			continue
		# 漂木群「塞肩」+ 泥沙魇「淤行」：行动结束停在小拱上 → 该小拱 blocked
		var u_name: String = enemy.combat_stats.unit_name
		if u_name == "漂木群·洪水版" or u_name == "泥沙魇":
			for arch_key in _side_arch_cells.keys():
				if enemy.cell == _side_arch_cells[arch_key]:
					_set_arch_state(arch_key, "blocked")
		# 泥沙魇「淤行」第二部分：若行动结束不在小拱上，自身格生成淤泥 2 回合
		if u_name == "泥沙魇" and not _cell_is_small_arch(enemy.cell):
			_spawn_silt_at(enemy.cell)

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
		},
		"priority_targets": _build_priority_targets(),
	}


# 每个敌方回合开始时重算：当前桥台强弱、运石工存活、小拱关闭状态都会影响谁最该被盯。
# 设计稿 §2 敌方 AI：
#   洪锋     → 桥台相邻格 > 桥面我方 > 最近（用「靠近较弱桥台的桥面我方」作 proxy）
#   泥沙魇   → 小拱 > 运石工 > 最近（先选「最近关闭小拱的运石工」，再全部运石工）
#   桥台噬者 → 较低稳定桥台 > 任意桥台 > 运石工（和洪锋同 proxy，顺带把运石工压后）
#   漂木群·洪水版 → hazard_charge 直线模板，方向在 drift_directions，无优先表
func _build_priority_targets() -> Dictionary:
	var priorities: Dictionary = {}
	var weak_pier: Vector2i = _left_pier if _left_pier_stability <= _right_pier_stability else _right_pier

	var alive_allies: Array = []
	for a in get_friendly_units():
		if a is Unit and a.combat_stats != null and a.combat_stats.is_alive():
			alive_allies.append(a)

	# 洪锋：桥面我方优先，且越靠近弱桥台越靠前；不在桥面的放后面
	var flood_spear_list: Array = alive_allies.duplicate()
	flood_spear_list.sort_custom(func(x: Unit, y: Unit) -> bool:
		var x_on: int = 0 if _is_on_main_bridge(x.cell) else 1
		var y_on: int = 0 if _is_on_main_bridge(y.cell) else 1
		if x_on != y_on:
			return x_on < y_on
		return _manhattan(x.cell, weak_pier) < _manhattan(y.cell, weak_pier)
	)
	priorities["洪锋"] = flood_spear_list

	# 桥台噬者：任何我方，按「到弱桥台曼哈顿」排序
	var gnawer_list: Array = alive_allies.duplicate()
	gnawer_list.sort_custom(func(x: Unit, y: Unit) -> bool:
		return _manhattan(x.cell, weak_pier) < _manhattan(y.cell, weak_pier)
	)
	# 同距离下把运石工压后（让它先去蹭桥台，再考虑敲运石工）
	priorities["桥台噬者"] = gnawer_list

	# 泥沙魇：运石工优先；按到最近关闭小拱距离排序
	var closed_arches: Array = []
	for arch_key in _side_arch_cells.keys():
		if _side_arch_states[arch_key] == "closed":
			closed_arches.append(_side_arch_cells[arch_key])
	var silt_list: Array = []
	for c in _stone_carriers:
		if c is Unit and c.combat_stats != null and c.combat_stats.is_alive():
			silt_list.append(c)
	if not closed_arches.is_empty():
		silt_list.sort_custom(func(x: Unit, y: Unit) -> bool:
			return _min_dist_to_cells(x.cell, closed_arches) < _min_dist_to_cells(y.cell, closed_arches)
		)
	priorities["泥沙魇"] = silt_list

	return priorities


func _min_dist_to_cells(from_cell: Vector2i, cells: Array) -> int:
	var best := 999999
	for c in cells:
		var d := absi(from_cell.x - c.x) + absi(from_cell.y - c.y)
		if d < best:
			best = d
	return best


func _is_adjacent_or_same(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) <= 1


func _cell_is_small_arch(cell: Vector2i) -> bool:
	for arch_key in _side_arch_cells.keys():
		if _side_arch_cells[arch_key] == cell:
			return true
	return false


func _spawn_silt_at(cell: Vector2i) -> void:
	if _silt_tiles.has(cell):
		var existing: SiltTile = _silt_tiles[cell]
		if is_instance_valid(existing):
			existing.configure(round_number, "泥沙魇")
			return
	var tile: SiltTile = _make_silt_tile()
	tile.configure(round_number, "泥沙魇")
	register_special_tile(tile, cell)
	_silt_tiles[cell] = tile
	CombatLog.msg("  淤泥格生成: %s (2 回合)" % [cell])


func _spawn_rapid_edges_for_overturn() -> void:
	# Boss 翻潮压桥 效果 3：沿桥面上下边缘生成 1 回合激流桥缘
	# 桥面在 y ∈ [_watch_point.y-1, _watch_point.y+1] 的 3 格横带；
	# 边缘 = y == watch_point.y-1（北缘） 与 y == watch_point.y+1（南缘）
	# 取左右桥台 x 范围内的格子。每侧 3 格，共 6 格。
	var y_north: int = _watch_point.y - 1
	var y_south: int = _watch_point.y + 1
	var x_min: int = mini(_left_pier.x, _right_pier.x) + 1
	var x_max: int = maxi(_left_pier.x, _right_pier.x) - 1
	for x in range(x_min, x_max + 1):
		_spawn_rapid_edge_at(Vector2i(x, y_north))
		_spawn_rapid_edge_at(Vector2i(x, y_south))


func _spawn_rapid_edge_at(cell: Vector2i) -> void:
	if movement_manager.get_movement_cost(cell) == TileType.IMPASSABLE:
		return
	if _rapid_edge_tiles.has(cell):
		var existing: RapidEdgeTile = _rapid_edge_tiles[cell]
		if is_instance_valid(existing):
			existing.configure(round_number)
			return
	var tile: RapidEdgeTile = _make_rapid_edge_tile()
	tile.configure(round_number)
	register_special_tile(tile, cell)
	_rapid_edge_tiles[cell] = tile


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
	var unit := spawn_unit(data, _find_empty_walkable_cell(cell), ENEMY_TEAM, visual)
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
