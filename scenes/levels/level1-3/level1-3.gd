extends BaseLevel
## 第三关《二十八券》

const PLAYER_TEAM := 0
const ENEMY_TEAM := 1

var _li_chun: Unit
var _craftsmen: Array[Unit] = []
var _stone_carriers: Array[Unit] = []
var _boss: Unit

var _left_arch_value := 2
var _right_arch_value := 2
var _bridge_stability := 6
var _arch_closed := false
var _pending_enemy_resolution := false
var _carrying_stone: Dictionary = {}
var _carrier_base_move_cost: Dictionary = {}
var _close_arch_ap_cost := 35
# ── UI 常驻状态面板（左上角）──
var _status_panel: RichTextLabel = null
# 上一次结算时的平衡状态（"均衡" / "偏衡" / "失衡"），用于检测状态切换
var _prev_balance_state: String = "均衡"
# Boss「倾压之号」—— 整关只触发一次的急召机制
var _clutch_fired: bool = false
# 偏压移衡调用次数计数：每 2 次才真正扣 1 点，避免每回合压得太狠
var _shift_load_tick: int = 0
# 券台 / 石料场的脉动光晕标记（仿第一关撤离区）
var _left_platform_marker: Node2D = null
var _right_platform_marker: Node2D = null
var _stone_yard_markers: Array[Node2D] = []

var _left_platform: Vector2i
var _right_platform: Vector2i
var _crown_point: Vector2i
var _stone_yard_cells: Array[Vector2i] = []
var _joint_cells: Array[Vector2i] = []

var _hero_data: UnitData = preload("res://data/units/hero_li_chun.tres")
var _hero_visual: PackedScene = preload("res://scenes/unit/visual/human/li_chun/li_chun_visual.tscn")
var _survey_data: UnitData = preload("res://data/units/survey_worker.tres")
var _craftsman_data: UnitData = preload("res://data/units/craftsman_guard.tres")
var _mud_data: UnitData = preload("res://data/units/bank_mud_wraith.tres")
var _dark_data: UnitData = preload("res://data/units/dark_current.tres")

var _staff: SkillData = preload("res://data/skills/sw_staff_end_strike.tres")
var _mallet: SkillData = preload("res://data/skills/cg_mallet_strike.tres")
var _guard: SkillData = preload("res://data/skills/cg_guard_the_works.tres")
var _divider: SkillData = preload("res://data/skills/lc_divider_mark_arc.tres")
var _inkline: SkillData = preload("res://data/skills/lc_inkline_balance_arch.tres")
var _crush: SkillData = preload("res://data/skills/bmw_crumbling_bank_crush.tres")
var _lunge: SkillData = preload("res://data/skills/dc_hidden_current_lunge.tres")
var _timber: SkillData = preload("res://data/skills/dlp_drifting_timber_crash.tres")

# ── 敌方视觉 ──
var _visual_boss: PackedScene = preload("res://scenes/unit/visual/monster/偏载怪/偏载怪_visual.tscn")
var _visual_misaligned: PackedScene = preload("res://scenes/unit/visual/monster/错券兵/错券兵_visual.tscn")
var _visual_stone_split: PackedScene = preload("res://scenes/unit/visual/monster/裂石兽/裂石兽_visual.tscn")
var _visual_rope_sever: PackedScene = preload("res://scenes/unit/visual/monster/断索鬼/断索鬼_visual.tscn")
var _visual_joint_shade: PackedScene = preload("res://scenes/unit/visual/monster/脱缝鬼/脱缝鬼_visual.tscn")


# ── 地图固定锚点视觉（与第一关撤离区同款脉动光晕） ──
const COLOR_LEFT_PLATFORM := Color(0.95, 0.75, 0.25, 0.65)    # 金色 —— 左券台
const COLOR_RIGHT_PLATFORM := Color(0.25, 0.65, 0.95, 0.65)   # 蓝色 —— 右券台
const COLOR_STONE_YARD := Color(0.55, 0.40, 0.25, 0.65)       # 棕色 —— 石料场
const COLOR_LEFT_HALO := Color(1.0, 0.80, 0.25, 0.55)         # 金色光晕
const COLOR_RIGHT_HALO := Color(0.30, 0.70, 1.0, 0.55)        # 蓝色光晕
const COLOR_STONE_HALO := Color(0.70, 0.50, 0.30, 0.55)       # 棕色光晕

# ── 地图固定锚点（按桥面 tile 实际位置解码得出，视觉关于桥中轴 x==y 镜像对称）──
# 桥图层并集范围：grid x=[-19,16] y=[-18,17]；视觉中轴位于 x-y=0 这条竖线（即 x==y）。
# 所有桥上锚点都关于该中轴左右对称；南岸南点也都落在 x==y 中轴上。
const CROWN_CELL: Vector2i = Vector2i(-1, -1)           # 桥视觉正中
const BOSS_CELL: Vector2i = Vector2i(-10, -10)          # 桥北端中轴（最偏北）
const LEFT_PLATFORM_CELL: Vector2i = Vector2i(-11, -4)  # 左券台：视觉 (-112, -120)
const RIGHT_PLATFORM_CELL: Vector2i = Vector2i(-5, -10) # 右券台：视觉 (80, -120)
const JOINT_CELL_A: Vector2i = Vector2i(-8, -4)         # 左缝口：中轴以西 64 px
const JOINT_CELL_B: Vector2i = Vector2i(-4, -8)         # 右缝口：中轴以东 64 px（镜像）
const LI_CHUN_START_CELL: Vector2i = Vector2i(14, 14)   # 李春在南岸未上桥处的视觉中轴
const STONE_YARD_CELL_A: Vector2i = Vector2i(9, 19)     # 左石料场：视觉 (-160, 224)
const STONE_YARD_CELL_B: Vector2i = Vector2i(18, 10)    # 右石料场：视觉 (128, 224)


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/Player" as Unit
	return [
		{
			"name": "施工队",
			"faction": "好人",
			"controller": "player",
			"units": [_li_chun],
		},
		{
			"name": "偏载方",
			"faction": "坏人",
			"controller": "ai",
			"units": [],
		},
	]


func get_wave_config() -> Dictionary:
	# 位置参考点：石料场、缝口位、左右券台。第 n 回合敌方开始前刷出。
	var left_flank := _nearest_walkable(_left_platform + Vector2i(-2, 0))
	var right_flank := _nearest_walkable(_right_platform + Vector2i(2, 0))
	var center_front := _nearest_walkable(_crown_point + Vector2i(0, 1))
	var stone_yard_left := _nearest_walkable(_stone_yard_cells[0] + Vector2i(-1, 0))
	var stone_yard_right := _nearest_walkable(_stone_yard_cells[1] + Vector2i(1, 0))
	# 错券兵刷在当前较高一侧，强化"必须先护哪边"的决策
	var misaligned_flank: Vector2i
	if _right_arch_value > _left_arch_value:
		misaligned_flank = right_flank
	else:
		misaligned_flank = left_flank
	return {
		2: [
			{"unit_data": _make_unit_data(_dark_data, "断索鬼", 78, 18, 100, 7, Enums.Element.WOOD, 2),
				"cell": stone_yard_left, "team_index": ENEMY_TEAM,
				"skills": [_timber], "visual": _visual_rope_sever},
		],
		3: [
			{"unit_data": _make_unit_data(_mud_data, "裂石兽", 112, 22, 90, 10, Enums.Element.EARTH, 2),
				"cell": center_front, "team_index": ENEMY_TEAM,
				"skills": [_crush], "visual": _visual_stone_split},
		],
		4: [
			{"unit_data": _make_unit_data(_dark_data, "脱缝鬼", 70, 15, 95, 8, Enums.Element.WATER, 2),
				"cell": _joint_cells[0], "team_index": ENEMY_TEAM,
				"skills": [_lunge], "visual": _visual_joint_shade},
		],
		6: [
			{"unit_data": _make_unit_data(_craftsman_data, "错券兵", 90, 17, 90, 9),
				"cell": misaligned_flank, "team_index": ENEMY_TEAM,
				"skills": [_mallet], "visual": _visual_misaligned},
			{"unit_data": _make_unit_data(_dark_data, "断索鬼", 78, 18, 100, 7, Enums.Element.WOOD, 2),
				"cell": stone_yard_right, "team_index": ENEMY_TEAM,
				"skills": [_timber], "visual": _visual_rope_sever},
		],
		8: [
			{"unit_data": _make_unit_data(_dark_data, "脱缝鬼", 70, 15, 95, 8, Enums.Element.WATER, 2),
				"cell": _joint_cells[1], "team_index": ENEMY_TEAM,
				"skills": [_lunge], "visual": _visual_joint_shade},
		],
		10: [
			{"unit_data": _make_unit_data(_mud_data, "裂石兽", 112, 22, 90, 10, Enums.Element.EARTH, 2),
				"cell": right_flank, "team_index": ENEMY_TEAM,
				"skills": [_crush], "visual": _visual_stone_split},
		],
	}


func get_objectives_text() -> Dictionary:
	var boss_alive := _boss != null and _boss.combat_stats != null and _boss.combat_stats.is_alive()
	var gap := _arch_gap()
	return {
		"victory": [
			"- 左券值达到 10（当前 %d/10）" % _left_arch_value,
			"- 右券值达到 10（当前 %d/10）" % _right_arch_value,
			"- 左右差值保持 ≤1（当前 %d）" % gap,
			"- 李春在拱冠点执行「收缝合龙」（%s）" % ("已完成" if _arch_closed else "未完成"),
			"- 击败偏载傀（%s）" % ("已击败" if not boss_alive else "存活"),
		],
		"defeat": [
			"- 李春倒下",
			"- 桥体稳定值归零（当前 %d/6）" % _bridge_stability,
			"- 超过第 30 回合（当前第 %d 回合）" % round_number,
		],
	}


func check_victory() -> bool:
	return _arch_closed and _boss != null and _boss.combat_stats != null and not _boss.combat_stats.is_alive()


func check_defeat() -> String:
	if _li_chun == null or _li_chun.combat_stats == null or not _li_chun.combat_stats.is_alive():
		return "李春倒下"
	if _bridge_stability <= 0:
		return "桥体稳定值耗尽"
	if round_number > 30:
		return "超过第 30 回合"
	return ""


func _on_level_ready() -> void:
	# 先把李春明确放到南岸未上桥处；桥面固定锚点在 _setup_anchor_cells 里取常量，
	# 不再依赖李春的初始格。
	_li_chun.set_cell(LI_CHUN_START_CELL, tilemap)
	_setup_anchor_cells()
	_setup_li_chun()
	_spawn_allies()
	_spawn_enemies()
	_setup_status_panel()
	team_turn_started.connect(_on_stage_team_turn_started)
	unit_hp_changed.connect(_on_stage_hp_changed)
	round_started.connect(_on_stage_round_started)
	_update_status_panel()
	_prev_balance_state = _balance_state()
	Notify.notify("推进券值：运石工去棕色石料场取石，再走到金/蓝券台旁 +1；或李春用「墨绳校券」远程 +1（CD 2）", Notify.Position.TOP_CENTER, Notify.Style.INFO, 5.0)


func _on_unit_moved() -> void:
	if selected_unit == null or not (selected_unit is Unit):
		return
	var unit := selected_unit as Unit
	_try_pick_or_deliver_stone(unit)
	_try_close_arch(unit)


func _on_skill_executed(caster: Unit, skill: SkillData, cast_cell: Vector2i, exec_result: SkillExecutor.ExecuteResult) -> void:
	# 李春墨绳校券：命中左/右券台即 +1
	if caster == _li_chun and skill.skill_id == "lc_inkline_balance_arch":
		if cast_cell == _left_platform:
			_adjust_arch_value(true, 1, "墨绳校券")
			_update_status_panel()
		elif cast_cell == _right_platform:
			_adjust_arch_value(false, 1, "墨绳校券")
			_update_status_panel()
		return

	# 敌方被动只关心对我方造成伤害的一击
	if caster == null or caster.combat_stats == null:
		return
	var caster_name := caster.combat_stats.unit_name
	if caster_name != "裂石兽" and caster_name != "断索鬼":
		return
	if exec_result == null:
		return

	for hit_entry in exec_result.hit_results:
		var target: Unit = hit_entry.get("unit") as Unit
		if target == null or target.combat_stats == null or not target.combat_stats.is_alive():
			continue
		if target not in _stone_carriers:
			continue
		var key := target.get_instance_id()
		var carrying: bool = _carrying_stone.get(key, false)
		if not carrying:
			continue
		# 裂石兽「袭石」：对携石运石工的这一击追加 15% 伤害
		if caster_name == "裂石兽":
			var hit = hit_entry.get("hit", null)
			var base_damage: int = 0
			if hit != null and "damage" in hit:
				base_damage = hit.damage
			var extra := maxi(int(base_damage * 0.15), 1)
			target.combat_stats.current_hp = maxi(target.combat_stats.current_hp - extra, 0)
			target.refresh_overhead_bars()
			Notify.notify("裂石兽袭石（+%d HP）" % extra, Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 1.5)
		# 断索鬼「断索」：命中携石运石工则直接卸货
		elif caster_name == "断索鬼":
			_carrying_stone[key] = false
			_set_carrier_loaded(target, false)
			target.refresh_overhead_bars()
			Notify.notify("%s 被断索鬼夺下石料" % target.combat_stats.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.ERROR, 2.0)


func _on_stage_team_turn_started(team_index: int) -> void:
	if team_index == ENEMY_TEAM:
		_pending_enemy_resolution = true
		_shift_load()
		_maybe_boss_clutch_summon()
	elif team_index == PLAYER_TEAM and _pending_enemy_resolution:
		_pending_enemy_resolution = false
		_resolve_enemy_pressure()


func _on_stage_hp_changed(unit: Unit, old_hp: int, new_hp: int) -> void:
	if unit != _boss or new_hp >= old_hp:
		return
	var damage := old_hp - new_hp
	var cap := _boss_damage_cap()
	if damage > cap:
		unit.combat_stats.current_hp = old_hp - cap
		unit.refresh_overhead_bars()


func _setup_anchor_cells() -> void:
	# 桥面锚点都是地图固定坐标，不再从李春的 cell 派生；以后李春可以任意开局位置，
	# 拱冠 / 券台 / 缝口 / 石料场都不动。
	_crown_point = _nearest_walkable(CROWN_CELL)
	_left_platform = _nearest_walkable(LEFT_PLATFORM_CELL)
	_right_platform = _nearest_walkable(RIGHT_PLATFORM_CELL)
	_stone_yard_cells = [
		_nearest_walkable(STONE_YARD_CELL_A),
		_nearest_walkable(STONE_YARD_CELL_B),
	]
	_joint_cells = [
		_nearest_walkable(JOINT_CELL_A),
		_nearest_walkable(JOINT_CELL_B),
	]
	# ── 调试 ──
	print("[Level1-3] anchors:")
	print("  LEFT_PLATFORM_CELL=", LEFT_PLATFORM_CELL, " → snap=", _left_platform)
	print("  RIGHT_PLATFORM_CELL=", RIGHT_PLATFORM_CELL, " → snap=", _right_platform)
	print("  STONE_YARD_CELL_A=", STONE_YARD_CELL_A, " → snap=", _stone_yard_cells[0])
	print("  STONE_YARD_CELL_B=", STONE_YARD_CELL_B, " → snap=", _stone_yard_cells[1])
	_setup_platform_markers()
	_setup_stone_yard_markers()
	print("[Level1-3] markers spawned: left=", _left_platform_marker, " right=", _right_platform_marker, " stone_yard_markers=", _stone_yard_markers.size())


## 左/右券台视觉：彩色地块 + 脉动光晕（仿第一关撤离区）
func _setup_platform_markers() -> void:
	var left_tile := _make_platform_tile(COLOR_LEFT_PLATFORM)
	left_tile.name = "LeftArchPlatform"
	register_special_tile(left_tile, _left_platform)
	_left_platform_marker = _spawn_pulsing_marker(_left_platform, "LeftArchMarker", COLOR_LEFT_HALO, "左券台")

	var right_tile := _make_platform_tile(COLOR_RIGHT_PLATFORM)
	right_tile.name = "RightArchPlatform"
	register_special_tile(right_tile, _right_platform)
	_right_platform_marker = _spawn_pulsing_marker(_right_platform, "RightArchMarker", COLOR_RIGHT_HALO, "右券台")


## 石料场视觉：彩色地块 + 脉动光晕
func _setup_stone_yard_markers() -> void:
	for i in _stone_yard_cells.size():
		var cell: Vector2i = _stone_yard_cells[i]
		var tile := _make_platform_tile(COLOR_STONE_YARD)
		tile.name = "StoneYard_%d" % i
		register_special_tile(tile, cell)
		var marker := _spawn_pulsing_marker(cell, "StoneYardMarker_%d" % i, COLOR_STONE_HALO, "石料场")
		_stone_yard_markers.append(marker)


## 一个固定位置上生成一个脉动光晕节点（仿第一关 _spawn_evac_marker）。
## label_text 非空时在顶上额外加一个文字标签，避免完全看不到。
func _spawn_pulsing_marker(cell: Vector2i, node_name: String, halo_color: Color, label_text: String = "") -> Node2D:
	var marker := Node2D.new()
	marker.name = node_name
	marker.z_as_relative = false
	marker.z_index = 120
	marker.position = tilemap.map_to_local(cell) + Vector2(0, -18)
	add_child(marker)

	var halo := Polygon2D.new()
	halo.polygon = PackedVector2Array([
		Vector2(0, -30), Vector2(30, -15), Vector2(0, 0), Vector2(-30, -15),
	])
	halo.color = halo_color
	marker.add_child(halo)

	var core := Polygon2D.new()
	core.polygon = PackedVector2Array([
		Vector2(0, -18), Vector2(18, -9), Vector2(0, 0), Vector2(-18, -9),
	])
	core.color = Color(1.0, 0.92, 0.80, 0.95)
	core.position = Vector2(0, -2)
	marker.add_child(core)

	if label_text != "":
		var label := Label.new()
		label.text = label_text
		label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6, 1.0))
		label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05, 1.0))
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_font_size_override("font_size", 12)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(-40, -48)
		label.size = Vector2(80, 16)
		marker.add_child(label)

	var tween := create_tween().set_loops()
	tween.tween_property(marker, "position:y", marker.position.y - 6.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(marker, "position:y", marker.position.y, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	print("[Level1-3]   marker '", node_name, "' at cell ", cell, " global_pos=", marker.global_position)
	return marker


func _make_platform_tile(color: Color) -> SpecialTile:
	var tile := SpecialTile.new()
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([0, -16, 16, -8, 0, 0, -16, -8])
	visual.color = color
	tile.add_child(visual)
	return tile


func _setup_li_chun() -> void:
	_li_chun.apply_runtime_setup(_hero_data, _hero_visual, Color(1, 0.85, 0, 1))
	set_unit_skills(_li_chun, Progress.get_battle_skill_resources(GameState.selected_level))
	setup_unit_stats(_li_chun, "李春", 130, 24, 100, 8, Enums.Element.NONE, 0, true)


func _spawn_allies() -> void:
	# 李春已经在 LI_CHUN_START_CELL = (14, 14) 的南岸视觉中轴（视觉 0, 224）。
	# 队友以他为锚点，分布在他的正南/南偏左/南偏右，视觉上李春在最前（最北）。
	# 等距 tile 下：offset (a, b) 视觉 = ((a-b)*16, (a+b)*8)
	#   (a-b) 决定左右（负=左），(a+b) 决定南北（正=南）
	var anchor := _li_chun.cell
	_craftsmen = [
		# 左翼工匠：视觉左下（48 左，32 下）
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 118, 20, 92, 9), _nearest_walkable(anchor + Vector2i(-1, 2)), [_mallet, _guard]),
		# 中线工匠：视觉正下（0 左右，48 下）
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 118, 20, 92, 9), _nearest_walkable(anchor + Vector2i(3, 3)), [_mallet, _guard]),
		# 右翼工匠：视觉右下（48 右，24 下）
		_spawn_ally(_make_unit_data(_craftsman_data, "工匠", 118, 20, 92, 9), _nearest_walkable(anchor + Vector2i(3, 0)), [_mallet, _guard]),
	]
	_stone_carriers = [
		# 左运石工：视觉左偏下（32 左，32 下）
		_spawn_ally(_make_unit_data(_survey_data, "运石工", 88, 13, 90, 9), _nearest_walkable(anchor + Vector2i(1, 3)), [_staff]),
		# 右运石工：视觉右偏下（32 右，48 下）
		_spawn_ally(_make_unit_data(_survey_data, "运石工", 88, 13, 90, 9), _nearest_walkable(anchor + Vector2i(4, 2)), [_staff]),
	]
	for carrier in _stone_carriers:
		_carrier_base_move_cost[carrier.get_instance_id()] = carrier.combat_stats.move_cost_per_tile
	_apply_persistent_growth_effects()


func _spawn_enemies() -> void:
	# Boss 在桥北端正中（BOSS_CELL 是地图常量），合龙前不动、不主动出手；
	# 只靠被动的偏压移衡扣券值 + 压台对相邻我方扣血。空技能表 + AP 1 / move_cost 99
	# 保证 AI 不会尝试攻击或移动。合龙后由 _unlock_boss 解锁机动与近战。
	_boss = _spawn_enemy(_make_unit_data(_mud_data, "偏载傀", 320, 22, 1, 99, Enums.Element.EARTH, 2), _nearest_walkable(BOSS_CELL), [], _visual_boss)
	# 两个错券兵分别贴在左右券台外侧，关于桥中轴镜像对称。
	_spawn_enemy(_make_unit_data(_craftsman_data, "错券兵", 90, 17, 90, 9), _nearest_walkable(_left_platform + Vector2i(-1, 1)), [_mallet], _visual_misaligned)
	_spawn_enemy(_make_unit_data(_craftsman_data, "错券兵", 90, 17, 90, 9), _nearest_walkable(_right_platform + Vector2i(1, -1)), [_mallet], _visual_misaligned)
	_spawn_enemy(_make_unit_data(_mud_data, "裂石兽", 112, 22, 90, 10, Enums.Element.EARTH, 2), _nearest_walkable(_crown_point + Vector2i(0, 1)), [_crush], _visual_stone_split)


func _try_pick_or_deliver_stone(unit: Unit) -> void:
	if unit not in _stone_carriers:
		return
	var key := unit.get_instance_id()
	if _is_adjacent_to_any(unit.cell, _stone_yard_cells) and not _carrying_stone.get(key, false):
		if unit.combat_stats.ap_current < 40:
			return
		unit.combat_stats.ap_current -= 40
		_carrying_stone[key] = true
		_set_carrier_loaded(unit, true)
		unit.refresh_overhead_bars()
		Notify.notify("%s 已取石" % unit.combat_stats.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.INFO, 1.5)
		return
	if not _carrying_stone.get(key, false):
		return
	if _is_adjacent_or_same(unit.cell, _left_platform):
		if unit.combat_stats.ap_current < 40:
			return
		unit.combat_stats.ap_current -= 40
		_adjust_arch_value(true, 1, "%s 运石入左券" % unit.combat_stats.unit_name)
		_carrying_stone[key] = false
		_set_carrier_loaded(unit, false)
		unit.refresh_overhead_bars()
	elif _is_adjacent_or_same(unit.cell, _right_platform):
		if unit.combat_stats.ap_current < 40:
			return
		unit.combat_stats.ap_current -= 40
		_adjust_arch_value(false, 1, "%s 运石入右券" % unit.combat_stats.unit_name)
		_carrying_stone[key] = false
		_set_carrier_loaded(unit, false)
		unit.refresh_overhead_bars()


func _try_close_arch(unit: Unit) -> void:
	if unit != _li_chun or _arch_closed:
		return
	if unit.cell != _crown_point:
		return
	if _left_arch_value < 10 or _right_arch_value < 10 or _arch_gap() > 1:
		return
	if unit.combat_stats.ap_current < _close_arch_ap_cost:
		return
	unit.combat_stats.ap_current -= _close_arch_ap_cost
	unit.refresh_overhead_bars()
	_arch_closed = true
	_unlock_boss()
	_update_status_panel()
	Notify.notify("收缝合龙完成，偏载傀的核心开始暴露", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 3.0)


func _shift_load() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	# 每 2 个敌方回合才真正压一次，给玩家留出推进节奏
	_shift_load_tick += 1
	if _shift_load_tick % 2 != 0:
		return
	if _left_arch_value == _right_arch_value:
		_adjust_arch_value(randi() % 2 == 0, -1, "偏载傀扰动平衡")
	elif _left_arch_value > _right_arch_value:
		_adjust_arch_value(false, -1, "偏载傀压右券")
	else:
		_adjust_arch_value(true, -1, "偏载傀压左券")


## 偏载傀「倾压之号」：整关只触发一次的急召。
##
## 当两侧施工都逼近上限（min >= 7）且差值已收拢（<= 1）、但玩家还没合龙，
## 偏载傀从较高一侧突然召唤 2 名错券兵。错券兵本身带扰券被动——下回合末
## 会把那一侧 −2，瞬间把玩家从"就差合龙一步"推回"需要先清兵再合龙"的决策点。
##
## 这个机制与 _shift_load（每回合温和地 −1）互补：shift_load 是慢性压力，
## 倾压之号是临门一脚的爆发。触发后 _clutch_fired 置 true，整关不再触发。
func _maybe_boss_clutch_summon() -> void:
	if _clutch_fired or _arch_closed:
		return
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	if mini(_left_arch_value, _right_arch_value) < 9:
		return
	if _arch_gap() > 1:
		return
	# 选定较高一侧；相等则随机
	var target_left: bool
	if _left_arch_value > _right_arch_value:
		target_left = true
	elif _right_arch_value > _left_arch_value:
		target_left = false
	else:
		target_left = randi() % 2 == 0
	var platform: Vector2i = _left_platform if target_left else _right_platform
	var side_name: String = "左" if target_left else "右"
	var offsets: Array[Vector2i]
	if target_left:
		offsets = [Vector2i(-1, -1), Vector2i(-1, 1)]
	else:
		offsets = [Vector2i(1, -1), Vector2i(1, 1)]
	var summoned: Array[Unit] = []
	for off in offsets:
		var cell := _nearest_walkable(platform + off)
		var unit := _spawn_enemy(
			_make_unit_data(_craftsman_data, "错券兵", 90, 17, 90, 9),
			cell, [_mallet], _visual_misaligned,
		)
		summoned.append(unit)
	_clutch_fired = true
	Notify.notify(
		"偏载傀倾压之号！%s侧突现 2 名错券兵，下回合末将扰券 −2" % side_name,
		Notify.Position.TOP_CENTER, Notify.Style.ERROR, 4.0,
	)
	if not summoned.is_empty():
		_camera_focus_spawned(summoned)


## 合龙成功后解锁偏载傀：从固定位 AP=1 / move_cost=99 放开到正常值，
## 并补上一把土系近战技能。Boss 从此可以下桥还手。
func _unlock_boss() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	_boss.combat_stats.move_cost_per_tile = 9
	_boss.combat_stats.ap_max = 90
	_boss.combat_stats.ap_current = _boss.combat_stats.ap_max
	_boss.refresh_overhead_bars()
	set_unit_skills(_boss, [_crush])
	Notify.notify("偏载傀开始下桥还手", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 3.0)


func _resolve_enemy_pressure() -> void:
	# 1. 错券兵「扰券」——在失衡判定前扣券值，才可能把本回合推入失衡
	for enemy in teams[ENEMY_TEAM].units:
		if not (enemy is Unit):
			continue
		if enemy.combat_stats == null or not enemy.combat_stats.is_alive():
			continue
		if enemy.combat_stats.unit_name != "错券兵":
			continue
		if _is_adjacent_or_same(enemy.cell, _left_platform):
			_adjust_arch_value(true, -1, "错券兵扰券（左）")
		elif _is_adjacent_or_same(enemy.cell, _right_platform):
			_adjust_arch_value(false, -1, "错券兵扰券（右）")

	# 2. 失衡扣桥体稳定
	if _arch_gap() >= 4:
		_bridge_stability -= 1
		Notify.notify("左右失衡！桥体稳定值 -1", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)

	# 3. 脱缝鬼在缝口位扣稳定
	for enemy in teams[ENEMY_TEAM].units:
		if not (enemy is Unit):
			continue
		if enemy.combat_stats == null or not enemy.combat_stats.is_alive():
			continue
		if enemy.combat_stats.unit_name != "脱缝鬼":
			continue
		if enemy.cell in _joint_cells:
			_bridge_stability -= 1
			Notify.notify("脱缝鬼侵蚀缝口，桥体稳定值 -1", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)

	# 4. 偏载傀「压台」——周围 1 格内我方扣 base_atk × 0.5 无属伤
	if _boss != null and _boss.combat_stats != null and _boss.combat_stats.is_alive():
		var press_damage := int(_boss.combat_stats.base_atk * 0.5)
		for ally in teams[PLAYER_TEAM].units:
			if not (ally is Unit) or ally.combat_stats == null or not ally.combat_stats.is_alive():
				continue
			if _is_adjacent_or_same(ally.cell, _boss.cell) and ally.cell != _boss.cell:
				ally.combat_stats.current_hp = maxi(ally.combat_stats.current_hp - press_damage, 0)
				ally.refresh_overhead_bars()
				Notify.notify("%s 被偏载傀压台击中（-%d HP）" % [ally.combat_stats.unit_name, press_damage], Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 1.5)

	_update_status_panel()
	_maybe_notify_balance_transition()
	_check_win_lose()


func _boss_damage_cap() -> int:
	if not _arch_closed:
		return 1
	if _arch_gap() >= 4:
		return 1
	if _arch_gap() >= 2:
		return 8
	return 9999


func _arch_gap() -> int:
	return absi(_left_arch_value - _right_arch_value)


func _adjust_arch_value(is_left: bool, delta: int, reason: String) -> void:
	if is_left:
		_left_arch_value = clampi(_left_arch_value + delta, 0, 10)
	else:
		_right_arch_value = clampi(_right_arch_value + delta, 0, 10)
	Notify.notify("%s  左券:%d 右券:%d 稳定:%d" % [reason, _left_arch_value, _right_arch_value, _bridge_stability], Notify.Position.TOP_RIGHT, Notify.Style.INFO, 2.5)
	_update_status_panel()


func _set_carrier_loaded(unit: Unit, loaded: bool) -> void:
	var key := unit.get_instance_id()
	var base_cost := int(_carrier_base_move_cost.get(key, unit.combat_stats.move_cost_per_tile))
	unit.combat_stats.move_cost_per_tile = base_cost + 1 if loaded else base_cost


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


func _is_adjacent_or_same(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) <= 1


func _is_adjacent_to_any(cell: Vector2i, targets: Array[Vector2i]) -> bool:
	for target in targets:
		if _is_adjacent_or_same(cell, target):
			return true
	return false


func get_post_level_growth_options() -> Array[Dictionary]:
	return [
		{"id": "growth_balance_method", "name": "校券有法", "description": "墨绳校券冷却 -1，李春行动力上限 +5"},
		{"id": "growth_joint_finish", "name": "收缝习熟", "description": "收缝合龙消耗 -10，李春基础攻击力 +4"},
		{"id": "growth_link_arch", "name": "连楔并拱", "description": "李春获得连楔并拱，可替换规尺击或木楔勘岸"},
		{"id": "growth_team_hold", "name": "立券同力", "description": "全体工匠最大生命值 +10，全体运石工行动力上限 +5"},
	]


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
		_close_arch_ap_cost = 25
		apply_unit_growth_bonus(get_hero_unit(), 0, 4, 0)
	if Progress.has_growth_option("growth_team_hold"):
		for craftsman in _craftsmen:
			apply_unit_growth_bonus(craftsman, 10, 0, 0)
		for carrier in _stone_carriers:
			apply_unit_growth_bonus(carrier, 0, 0, 5)


# ─────────────────────────────────────────────
# 状态面板 / UI 可见性
# ─────────────────────────────────────────────

func _setup_status_panel() -> void:
	_status_panel = RichTextLabel.new()
	_status_panel.name = "Level3StatusPanel"
	_status_panel.bbcode_enabled = true
	_status_panel.fit_content = true
	_status_panel.scroll_active = false
	_status_panel.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status_panel.anchors_preset = Control.PRESET_TOP_LEFT
	_status_panel.offset_left = 18
	_status_panel.offset_top = 84
	_status_panel.offset_right = 380
	_status_panel.offset_bottom = 160
	_status_panel.add_theme_font_size_override("normal_font_size", 16)
	_status_panel.add_theme_color_override("default_color", Color(0.96, 0.94, 0.88))
	_status_panel.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.08))
	_status_panel.add_theme_constant_override("outline_size", 3)
	gui.add_child(_status_panel)


func _balance_state() -> String:
	var gap := _arch_gap()
	if gap <= 1:
		return "均衡"
	if gap <= 3:
		return "偏衡"
	return "失衡"


func _update_status_panel() -> void:
	if _status_panel == null:
		return
	var gap := _arch_gap()
	var state := _balance_state()
	var state_color := "#6edc6e"
	if state == "偏衡":
		state_color = "#e8c28c"
	elif state == "失衡":
		state_color = "#e6463c"
	var closed_text := "已合龙" if _arch_closed else "未合龙"
	_status_panel.text = "左券 %d/10    右券 %d/10    差值 %d\n桥体稳定 %d/6    [color=%s]%s[/color]    %s" % [
		_left_arch_value, _right_arch_value, gap,
		_bridge_stability, state_color, state, closed_text,
	]


## 检测自上次结算以来平衡状态是否切换，切换了弹一次 Notify。
func _maybe_notify_balance_transition() -> void:
	var new_state := _balance_state()
	if new_state == _prev_balance_state:
		return
	match new_state:
		"均衡":
			Notify.notify("左右回到均衡。", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.5)
		"偏衡":
			Notify.notify("左右偏衡，偏载傀直接受到的伤害上限 8。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 3.0)
		"失衡":
			Notify.notify("左右失衡！偏载傀几乎无伤，每敌方回合末桥体 -1。", Notify.Position.TOP_CENTER, Notify.Style.ERROR, 3.5)
	_prev_balance_state = new_state


## 大回合开始时：若本回合有波次配置，提前通知。
func _on_stage_round_started(round_num: int) -> void:
	if get_wave_config().has(round_num):
		Notify.notify("第 %d 回合：敌方支援到场" % round_num, Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.5)
	_update_status_panel()
