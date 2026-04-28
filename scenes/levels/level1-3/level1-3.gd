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
# ── UI 常驻状态面板（左上角）──
var _status_panel: RichTextLabel = null
# 上一次结算时的平衡状态（"均衡" / "偏衡" / "失衡"），用于检测状态切换
var _prev_balance_state: String = "均衡"
# Boss「倾压之号」—— 整关只触发一次的急召机制
var _clutch_fired: bool = false
# 偏压移衡调用次数计数：每 2 次才真正扣 1 点，避免每回合压得太狠
var _shift_load_tick: int = 0
# 券台 / 石料场 / 拱冠点的脉动光晕标记（仿第一关撤离区）
var _left_platform_marker: Node2D = null
var _right_platform_marker: Node2D = null
var _stone_yard_markers: Array[Node2D] = []
var _crown_marker: Node2D = null
## 紫色拱冠染色 tile，初始隐藏；Boss 死 + 两侧 10 + gap≤1 时才 .visible = true
var _crown_tile: Node2D = null
## 拱冠点是否已经"激活并通知过玩家"——避免反复弹通知
var _crown_activated: bool = false

var _left_platform: Vector2i
var _right_platform: Vector2i
var _crown_point: Vector2i
var _stone_yard_cells: Array[Vector2i] = []
var _joint_cells: Array[Vector2i] = []
var _bridge_cells: Dictionary = {}  # 桥面可落脚 cell 集合（敌人刷新必须在桥上）

var _craftsman_data: UnitData = preload("res://data/units/craftsman_guard.tres")
var _mud_data: UnitData = preload("res://data/units/bank_mud_wraith.tres")
var _dark_data: UnitData = preload("res://data/units/dark_current.tres")

# 教程引导（L1-1 / L1-4 同款 dialogue 流程）。
var _li_chun_portrait: Texture2D = preload("res://assets/face/li_chun.png")
const TUTORIAL_ID := "level1-3"
# 教程"亲手用一次墨绳校券"的同步态。
var _tutorial_inkline_used: bool = false

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
# ── 我方视觉（动态生成的运石工用）──
var _visual_carrier: PackedScene = preload("res://scenes/unit/visual/human/测量工/测量工_visual.tscn")


# ── 地图固定锚点视觉（与第一关撤离区同款脉动光晕） ──
const COLOR_LEFT_PLATFORM := Color(0.95, 0.75, 0.25, 0.65)    # 金色 —— 左券台
const COLOR_RIGHT_PLATFORM := Color(0.25, 0.65, 0.95, 0.65)   # 蓝色 —— 右券台
const COLOR_STONE_YARD := Color(0.55, 0.40, 0.25, 0.35)       # 棕色 —— 石料场（较淡）
const COLOR_CROWN_PLATFORM := Color(0.75, 0.40, 0.95, 0.70)   # 紫色 —— 拱冠合龙点
const COLOR_LEFT_HALO := Color(1.0, 0.80, 0.25, 0.50)         # 金色光晕
const COLOR_RIGHT_HALO := Color(0.30, 0.70, 1.0, 0.50)        # 蓝色光晕
const COLOR_STONE_HALO := Color(0.70, 0.50, 0.30, 0.30)       # 棕色光晕（更淡）
const COLOR_CROWN_HALO := Color(0.85, 0.50, 1.0, 0.55)        # 紫色光晕

# ── 地图固定锚点（按桥面 tile 实际位置解码得出，视觉关于桥中轴 x==y 镜像对称）──
# 桥图层并集范围：grid x=[-19,16] y=[-18,17]；视觉中轴位于 x-y=0 这条竖线（即 x==y）。
# 所有桥上锚点都关于该中轴左右对称；南岸南点也都落在 x==y 中轴上。
const CROWN_CELL: Vector2i = Vector2i(-1, -1)           # 桥视觉正中
const BOSS_CELL: Vector2i = Vector2i(-10, -9)           # Boss 桥北端中央（对齐地图实际中心，视觉 x=-16）
const LEFT_PLATFORM_CELL: Vector2i = Vector2i(-11, -4)  # 左券台：视觉 (-112, -120)
const RIGHT_PLATFORM_CELL: Vector2i = Vector2i(-5, -10) # 右券台：视觉 (80, -120)
const JOINT_CELL_A: Vector2i = Vector2i(-8, -4)         # 左缝口：中轴以西 64 px
const JOINT_CELL_B: Vector2i = Vector2i(-4, -8)         # 右缝口：中轴以东 64 px（镜像）
const STONE_YARD_CELL_A: Vector2i = Vector2i(9, 19)     # 左石料场：视觉 (-160, 224)
const STONE_YARD_CELL_B: Vector2i = Vector2i(18, 10)    # 右石料场：视觉 (128, 224)


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/Player" as Unit
	_craftsmen = [
		$"Entities/Units/CraftsmanA" as Unit,
		$"Entities/Units/CraftsmanB" as Unit,
		$"Entities/Units/CraftsmanC" as Unit,
	]
	_stone_carriers = [
		$"Entities/Units/StoneCarrierA" as Unit,
		$"Entities/Units/StoneCarrierB" as Unit,
	]
	var player_units: Array = [_li_chun]
	player_units.append_array(_craftsmen)
	player_units.append_array(_stone_carriers)
	return [
		{
			"name": "施工队",
			"faction": "好人",
			"controller": "player",
			"units": player_units,
		},
		{
			"name": "偏载方",
			"faction": "坏人",
			"controller": "ai",
			"units": [],
		},
	]


func get_wave_config() -> Dictionary:
	# 节奏：前 25 回合自然刷怪（9 波，单只与双只混合），r25 之后不再刷怪，
	# 进入 Boss 攻坚阶段。开场已有 Boss + 2 错券兵 + 1 裂石兽。
	# boss clutch 急召是独立触发。
	var left_flank := _nearest_bridge_cell(_left_platform + Vector2i(-2, 0))
	var right_flank := _nearest_bridge_cell(_right_platform + Vector2i(2, 0))
	var center_front := _nearest_bridge_cell(_crown_point + Vector2i(0, 1))
	var stone_yard_left := _nearest_bridge_cell(_stone_yard_cells[0] + Vector2i(-1, -2))
	var stone_yard_right := _nearest_bridge_cell(_stone_yard_cells[1] + Vector2i(-2, -1))
	var misaligned_flank: Vector2i
	if _right_arch_value > _left_arch_value:
		misaligned_flank = right_flank
	else:
		misaligned_flank = left_flank
	return {
		3: [
			{"unit_data": _make_unit_data(_dark_data, "断索鬼", 66, 18, 100, 7, Enums.Element.WOOD, 2),
				"cell": stone_yard_left, "team_index": ENEMY_TEAM,
				"skills": [_timber], "visual": _visual_rope_sever},
		],
		5: [
			{"unit_data": _make_unit_data(_craftsman_data, "错券兵", 77, 17, 90, 9),
				"cell": misaligned_flank, "team_index": ENEMY_TEAM,
				"skills": [_mallet], "visual": _visual_misaligned},
		],
		7: [
			{"unit_data": _make_unit_data(_mud_data, "裂石兽", 95, 22, 90, 10, Enums.Element.EARTH, 2),
				"cell": center_front, "team_index": ENEMY_TEAM,
				"skills": [_crush], "visual": _visual_stone_split},
			{"unit_data": _make_unit_data(_craftsman_data, "错券兵", 77, 17, 90, 9),
				"cell": misaligned_flank, "team_index": ENEMY_TEAM,
				"skills": [_mallet], "visual": _visual_misaligned},
		],
		10: [
			{"unit_data": _make_unit_data(_dark_data, "脱缝鬼", 60, 15, 95, 8, Enums.Element.WATER, 2),
				"cell": _joint_cells[0], "team_index": ENEMY_TEAM,
				"skills": [_lunge], "visual": _visual_joint_shade},
		],
		13: [
			{"unit_data": _make_unit_data(_craftsman_data, "错券兵", 77, 17, 90, 9),
				"cell": misaligned_flank, "team_index": ENEMY_TEAM,
				"skills": [_mallet], "visual": _visual_misaligned},
		],
		15: [
			{"unit_data": _make_unit_data(_dark_data, "断索鬼", 66, 18, 100, 7, Enums.Element.WOOD, 2),
				"cell": stone_yard_right, "team_index": ENEMY_TEAM,
				"skills": [_timber], "visual": _visual_rope_sever},
			{"unit_data": _make_unit_data(_mud_data, "裂石兽", 95, 22, 90, 10, Enums.Element.EARTH, 2),
				"cell": right_flank, "team_index": ENEMY_TEAM,
				"skills": [_crush], "visual": _visual_stone_split},
		],
		18: [
			{"unit_data": _make_unit_data(_dark_data, "脱缝鬼", 60, 15, 95, 8, Enums.Element.WATER, 2),
				"cell": _joint_cells[1], "team_index": ENEMY_TEAM,
				"skills": [_lunge], "visual": _visual_joint_shade},
		],
		21: [
			{"unit_data": _make_unit_data(_craftsman_data, "错券兵", 77, 17, 90, 9),
				"cell": misaligned_flank, "team_index": ENEMY_TEAM,
				"skills": [_mallet], "visual": _visual_misaligned},
		],
		24: [
			{"unit_data": _make_unit_data(_dark_data, "断索鬼", 66, 18, 100, 7, Enums.Element.WOOD, 2),
				"cell": stone_yard_left, "team_index": ENEMY_TEAM,
				"skills": [_timber], "visual": _visual_rope_sever},
			{"unit_data": _make_unit_data(_craftsman_data, "错券兵", 77, 17, 90, 9),
				"cell": misaligned_flank, "team_index": ENEMY_TEAM,
				"skills": [_mallet], "visual": _visual_misaligned},
		],
	}


func get_objectives_text() -> Dictionary:
	var boss_alive := _is_boss_alive()
	var gap := _arch_gap()
	return {
		"victory": [
			"- 左券值达到 10（当前 %d/10）" % _left_arch_value,
			"- 右券值达到 10（当前 %d/10）" % _right_arch_value,
			"- 左右差值保持 ≤1（当前 %d）" % gap,
			"- 击败偏载傀（%s）" % ("已击败" if not boss_alive else "存活"),
			"- 上述三项满足后，李春用「墨绳校券」命中桥中央[color=#c060f0]紫色拱冠点[/color]完成合龙（%s）" % ("已完成" if _arch_closed else "未完成"),
		],
		"defeat": [
			"- 李春倒下",
			"- 桥体稳定值归零（当前 %d/6）" % _bridge_stability,
			"- 超过第 50 回合（当前第 %d 回合）" % round_number,
		],
	}


func check_victory() -> bool:
	return _arch_closed and not _is_boss_alive()


func check_defeat() -> String:
	if _li_chun == null or _li_chun.combat_stats == null or not _li_chun.combat_stats.is_alive():
		return "李春倒下"
	if _bridge_stability <= 0:
		return "桥体稳定值耗尽"
	if round_number > 50:
		return "超过第 50 回合"
	return ""


func _on_level_ready() -> void:
	# 李春与队友节点都在 .tscn 里预置；base_level 的 _reparent_entities_to_obstacles
	# 会按 global_position 吸附到最近 cell。桥面固定锚点走 _setup_anchor_cells 常量。
	_build_bridge_cells()
	_setup_anchor_cells()
	_setup_li_chun()
	_setup_allies_from_scene()
	_spawn_enemies()
	_setup_status_panel()
	team_turn_started.connect(_on_stage_team_turn_started)
	unit_hp_changed.connect(_on_stage_hp_changed)
	round_started.connect(_on_stage_round_started)
	# 教程对话不能在 BRIEFING 阶段就跑（会和初始目标面板抢输入），等 PLAYING 之后再触发。
	phase_changed.connect(_on_phase_changed_for_onboarding)
	_update_status_panel()
	_update_crown_visibility()
	_prev_balance_state = _balance_state()


func _on_phase_changed_for_onboarding(p: int) -> void:
	if p != LevelPhase.PLAYING:
		return
	_run_onboarding()


# 完整对话教程（仿 L1-1 / L1-4 P1）。复玩走 has_seen_tutorial 自动跳过。
# 设计：四段对话 + 一次实操（用一次墨绳校券）+ 收尾确认。
#   ① 战场目标与三件事（券值 / 合龙 / boss）
#   ② 推券两条路：取送石 vs 墨绳校券；CD/AP 数值
#   ③ 平衡机制：均衡 / 偏衡 / 失衡 → boss 受伤上限
#   ④ 让玩家亲自打一发墨绳校券（最直观的"我也能改券值"反馈）
#   ⑤ 命中确认 + 拱冠合龙 + 失败条件
func _run_onboarding() -> void:
	if Progress.has_seen_tutorial(TUTORIAL_ID):
		if not await _ask_tutorial_replay():
			Notify.notify(
				"运石工取送石 +1 / 李春「墨绳校券」远程 +1（CD 2）；两侧 10 + 击败偏载傀 → 紫色拱冠点合龙",
				Notify.Position.TOP_CENTER, Notify.Style.INFO, 6.0,
			)
			return
	await get_tree().create_timer(0.4).timeout
	if is_phase_ended():
		return
	# ── ① 战场目标 ──
	await play_dialogue([
		_lc_line("二十八券要在这里成形——这一关不是杀光全场，而是把桥『券』够。"),
		_lc_line("左上券值面板看着：左、右两侧各要凑到 [b]10[/b]，差值要 [b]≤1[/b]，再把『偏载傀』那只大家伙打掉。"),
		_lc_line("条件全满之后，桥中央会亮起[color=#c060f0]紫色拱冠点[/color]——我用『墨绳校券』点上去就算合龙。"),
	])
	if is_phase_ended():
		return
	# ── ② 推券两条路 ──
	await play_dialogue([
		_lc_line("券值有两条推法。一条是工人路：让运石工到[b]棕色石料场[/b]取石，再走到[color=#e0a830]金券台[/color]或[color=#3098e8]蓝券台[/color]旁边，自动把这一侧 +1。"),
		_lc_line("另一条是我自己——『墨绳校券』，远程 [b]+1[/b]，CD 2 回合。可以隔着场子单方加券，关键时候用来抢节奏。"),
		_lc_line("注意：这招命中券台后，命中侧 +1 同时对侧 [b]-1[/b]。是『调拨』不是『凭空印』——平衡两边时是神技，乱用会失衡。"),
	])
	if is_phase_ended():
		return
	# ── ③ 平衡机制 + boss ──
	await play_dialogue([
		_lc_line("讲到失衡：左右券值差是关卡的命脉。差 0 → [color=#7aff8c]均衡[/color]，正常打偏载傀；差 ≥2 → [color=#ffc855]偏衡[/color]，它每次最多挨 10 伤；差 ≥4 → [color=#ff5555]失衡[/color]，几乎免伤，每个敌方回合末桥体还 -1。"),
		_lc_line("所以打偏载傀的窗口只在『均衡』。一边赶券、一边别让差值拉开是这关的核心。"),
		_lc_line("整桥稳定值 6，归零即败。再加上 50 回合时限——别拖。"),
	])
	if is_phase_ended():
		return
	# ── ④ 实战：先打一发墨绳校券 ──
	await play_dialogue([
		_lc_line("光说不练假把式。选中我，对着[color=#e0a830]金券台[/color]或[color=#3098e8]蓝券台[/color]来一发『墨绳校券』，看看券值面板的变化。"),
	])
	if is_phase_ended():
		return
	Notify.notify(
		"选中李春 → 选「墨绳校券」→ 点金券台或蓝券台 2×2 任意一格",
		Notify.Position.TOP_CENTER, Notify.Style.INFO, 14.0,
	)
	_tutorial_inkline_used = false
	skill_executed.connect(_on_tutorial_skill_executed)
	while not _tutorial_inkline_used:
		await skill_executed
		if is_phase_ended():
			if skill_executed.is_connected(_on_tutorial_skill_executed):
				skill_executed.disconnect(_on_tutorial_skill_executed)
			return
	if skill_executed.is_connected(_on_tutorial_skill_executed):
		skill_executed.disconnect(_on_tutorial_skill_executed)
	# ── ⑤ 收尾确认 ──
	await play_dialogue([
		_lc_line("看到了吧——命中侧 +1，对侧 -1。等之后两边都到 10、差值 ≤1、boss 倒了，紫色拱冠点会亮起，再来这一招就合龙。"),
		_lc_line("剩下的就交给你了——把券推满、把那只大家伙拉到均衡里打死、最后一击我来。"),
	])
	if is_phase_ended():
		return
	Progress.mark_tutorial_seen(TUTORIAL_ID)


# 教程专用 skill_executed 监听：仅当李春释放「墨绳校券」时翻起 _tutorial_inkline_used。
# 其它操作（取送石、技能试招）不打断教程主协程。
func _on_tutorial_skill_executed(caster: Unit, skill: SkillData, _cast_cell: Vector2i) -> void:
	if caster == _li_chun and skill != null and skill.skill_id == "lc_inkline_balance_arch":
		_tutorial_inkline_used = true


# 李春对话单行构造的小帮手：自动带头像，放左侧。仿 L1-1 / L1-4 同名函数。
func _lc_line(text: String) -> DialogueLine:
	return DialogueLine.create("李春", text, _li_chun_portrait, "left")


func _on_unit_moved() -> void:
	if selected_unit == null or not (selected_unit is Unit):
		return
	var unit := selected_unit as Unit
	_try_pick_or_deliver_stone(unit)


func _on_skill_executed(caster: Unit, skill: SkillData, cast_cell: Vector2i, exec_result: SkillExecutor.ExecuteResult) -> void:
	# 李春墨绳校券：命中左/右券台 2×2 → 命中侧 +1，同时对侧 -1（左右调拨）。
	# 总和不变，但能瞬间矫正失衡，让玩家有手段把扰券侧的扣减"挪"到富余侧。
	if caster == _li_chun and skill.skill_id == "lc_inkline_balance_arch":
		# 命中拱冠点 / 站在拱冠点上自施 → 收缝合龙
		# 视觉光晕覆盖多格，命中点接受 _crown_point 切比雪夫半径 ≤1 范围（容差）
		var hit_crown: bool = (
			_is_adjacent_or_same(caster.cell, _crown_point)
			or _is_adjacent_or_same(cast_cell, _crown_point)
		)
		if hit_crown:
			if _close_arch_conditions_met():
				_close_arch_via_skill()
			else:
				caster.combat_stats.ap_current = mini(
					caster.combat_stats.ap_current + skill.ap_cost,
					caster.combat_stats.ap_max,
				)
				caster.refresh_overhead_bars()
				Notify.notify(
					"合龙条件未满足：%s" % _close_arch_failure_reason(),
					Notify.Position.TOP_CENTER, Notify.Style.WARNING, 3.5,
				)
			return
		if _is_in_zone(cast_cell, _left_platform):
			_adjust_arch_value(true, 1, "墨绳校券（左 +1）")
			_adjust_arch_value(false, -1, "墨绳校券（右 -1）")
			_update_status_panel()
		elif _is_in_zone(cast_cell, _right_platform):
			_adjust_arch_value(false, 1, "墨绳校券（右 +1）")
			_adjust_arch_value(true, -1, "墨绳校券（左 -1）")
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
	# Boss HP 变化（含被打死）→ 重新评估拱冠是否激活
	_update_crown_visibility()


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
	_setup_crown_marker()
	print("[Level1-3] markers spawned: left=", _left_platform_marker, " right=", _right_platform_marker, " stone_yard_markers=", _stone_yard_markers.size(), " crown=", _crown_marker)


## 左/右券台视觉：2×2 彩色地块 + 预置的脉动光晕（见 level1-3.tscn 的 Markers 节点）。
func _setup_platform_markers() -> void:
	for c in _zone_cells(_left_platform):
		var t := _make_platform_tile(COLOR_LEFT_PLATFORM)
		t.name = "LeftArchTile_%d_%d" % [c.x, c.y]
		register_special_tile(t, c)
	_left_platform_marker = get_node("Markers/LeftArchMarker")

	for c in _zone_cells(_right_platform):
		var t := _make_platform_tile(COLOR_RIGHT_PLATFORM)
		t.name = "RightArchTile_%d_%d" % [c.x, c.y]
		register_special_tile(t, c)
	_right_platform_marker = get_node("Markers/RightArchMarker")


## 石料场视觉：2×2 彩色地块 + 预置的脉动光晕。
func _setup_stone_yard_markers() -> void:
	for i in _stone_yard_cells.size():
		var anchor: Vector2i = _stone_yard_cells[i]
		for c in _zone_cells(anchor):
			var tile := _make_platform_tile(COLOR_STONE_YARD)
			tile.name = "StoneYardTile_%d_%d_%d" % [i, c.x, c.y]
			register_special_tile(tile, c)
		_stone_yard_markers.append(get_node("Markers/StoneYardMarker_%d" % i))


## 拱冠合龙点视觉：单格紫色染色 + 预置的脉动光晕。
## 初始**隐藏**——Boss 死 + 两侧凑满 10 + gap≤1 时由 _update_crown_visibility 显示。
## 这是关卡"最终交互点"：所有前置完成后才浮现，李春走过去合龙即胜利。
func _setup_crown_marker() -> void:
	var tile := _make_platform_tile(COLOR_CROWN_PLATFORM)
	tile.name = "CrownTile_%d_%d" % [_crown_point.x, _crown_point.y]
	register_special_tile(tile, _crown_point)
	tile.visible = false
	_crown_tile = tile
	if has_node("Markers/CrownMarker"):
		_crown_marker = get_node("Markers/CrownMarker")
		_crown_marker.visible = false


## 检查拱冠激活条件并切换可见性 + 首次激活弹通知。
## 条件：Boss 死亡 + 左右券值都 ≥10 + gap≤1 + 尚未合龙。
## 任意券值变动 / Boss HP 变动后调用一次即可。
func _update_crown_visibility() -> void:
	if _arch_closed:
		return
	var boss_dead: bool = not _is_boss_alive()
	var arches_full: bool = _left_arch_value >= 10 and _right_arch_value >= 10 and _arch_gap() <= 1
	var should_show: bool = boss_dead and arches_full
	if _crown_tile != null:
		_crown_tile.visible = should_show
	if _crown_marker != null:
		_crown_marker.visible = should_show
	if should_show and not _crown_activated:
		_crown_activated = true
		Notify.notify(
			"拱冠合龙点已激活！李春用「墨绳校券」命中桥中央紫色拱冠点即胜利",
			Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 5.0,
		)


func _make_platform_tile(color: Color) -> SpecialTile:
	var tile := SpecialTile.new()
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([0, -16, 16, -8, 0, 0, -16, -8])
	visual.color = color
	tile.add_child(visual)
	return tile


func _setup_li_chun() -> void:
	set_unit_skills(_li_chun, Progress.get_battle_skill_resources(GameState.selected_level))
	setup_unit_stats(_li_chun, "李春", 130, 24, 100, 8, Enums.Element.NONE, 0, true)


func _setup_allies_from_scene() -> void:
	# 工匠 / 运石工已在 .tscn 预置（unit_data + visual_scene + position）；
	# 这里只补齐技能与战斗数值，并记录运石工的基础移动消耗用于载石后 +1。
	# 同时在两石料场旁各动态生成 1 名额外运石工，加速运石节奏。
	_spawn_extra_carriers()
	for craftsman in _craftsmen:
		set_unit_skills(craftsman, [_mallet, _guard])
		setup_unit_stats(craftsman, "工匠", 118, 20, 92, 9)
	for carrier in _stone_carriers:
		set_unit_skills(carrier, [_staff])
		setup_unit_stats(carrier, "运石工", 88, 13, 100, 8)
		_carrier_base_move_cost[carrier.get_instance_id()] = carrier.combat_stats.move_cost_per_tile
	_apply_persistent_growth_effects()
	# 墨绳校券改为无 CD 的「左右调拨」式机制（命中侧 +1 / 对侧 -1），
	# 在所有成长应用之后强制覆盖一次以确保 CD=0（防止以后再加成长项时被改回）。
	modify_unit_skill(_li_chun, "lc_inkline_balance_arch", {"cooldown_turns": 0})


## 在两个石料场旁各生成 1 名额外运石工。让运石节奏跟得上敌方扣券速度。
## 生成的单位会被加入 _stone_carriers，由 _setup_allies_from_scene 的循环统一配齐技能/数值。
func _spawn_extra_carriers() -> void:
	var carrier_data: UnitData = preload("res://data/units/survey_worker.tres")
	var spawn_targets: Array[Vector2i] = [
		_stone_yard_cells[0] + Vector2i(0, -1),   # 左石料场北侧（靠桥一侧）
		_stone_yard_cells[1] + Vector2i(-1, 0),   # 右石料场西侧（靠桥一侧）
	]
	for target in spawn_targets:
		var cell := _nearest_walkable(target)
		var carrier := spawn_unit(carrier_data, cell, PLAYER_TEAM, _visual_carrier)
		_stone_carriers.append(carrier)


func _spawn_enemies() -> void:
	# Boss 在桥北端正中（BOSS_CELL 是地图常量），初始固定位（AP=1 / move_cost=99 / 空技能表）
	# —— **倾压之号触发前不能动也不能主动出手**，只靠被动机制（偏压移衡 / 压台）压玩家。
	# 倾压之号触发时调 _unlock_boss 放开机动 + 补土系近战，Boss 开始下桥还手。
	# 玩家仍可远程打 Boss，Boss 受击伤害仍按 _boss_damage_cap 截断。
	_boss = _spawn_enemy(_make_unit_data(_mud_data, "偏载傀", 420, 18, 1, 99, Enums.Element.EARTH, 2), _nearest_bridge_cell(BOSS_CELL), [], _visual_boss)
	# 两个错券兵分别贴在左右券台外侧（关于桥中轴镜像），与券台 2×2 相邻以便扰券。
	_spawn_enemy(_make_unit_data(_craftsman_data, "错券兵", 77, 17, 90, 9), _nearest_bridge_cell(_left_platform + Vector2i(-1, -1)), [_mallet], _visual_misaligned)
	_spawn_enemy(_make_unit_data(_craftsman_data, "错券兵", 77, 17, 90, 9), _nearest_bridge_cell(_right_platform + Vector2i(1, 1)), [_mallet], _visual_misaligned)
	_spawn_enemy(_make_unit_data(_mud_data, "裂石兽", 95, 22, 90, 10, Enums.Element.EARTH, 2), _nearest_bridge_cell(_crown_point + Vector2i(0, 1)), [_crush], _visual_stone_split)


func _try_pick_or_deliver_stone(unit: Unit) -> void:
	if unit not in _stone_carriers:
		return
	var key := unit.get_instance_id()
	# 取石：进入 2×2 石料场区域且空手 → 自动取石（不再扣 AP）
	if _is_in_any_zone(unit.cell, _stone_yard_cells) and not _carrying_stone.get(key, false):
		_carrying_stone[key] = true
		_set_carrier_loaded(unit, true)
		unit.refresh_overhead_bars()
		Notify.notify("%s 已取石" % unit.combat_stats.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.INFO, 1.5)
		return
	if not _carrying_stone.get(key, false):
		return
	# 交石：载石时进入 2×2 券台区域 → 自动卸石 + 对应侧 +1（不再扣 AP）
	if _is_in_zone(unit.cell, _left_platform):
		_adjust_arch_value(true, 3, "%s 运石入左券" % unit.combat_stats.unit_name)
		_carrying_stone[key] = false
		_set_carrier_loaded(unit, false)
		unit.refresh_overhead_bars()
	elif _is_in_zone(unit.cell, _right_platform):
		_adjust_arch_value(false, 3, "%s 运石入右券" % unit.combat_stats.unit_name)
		_carrying_stone[key] = false
		_set_carrier_loaded(unit, false)
		unit.refresh_overhead_bars()


func _close_arch_conditions_met() -> bool:
	if _arch_closed:
		return false
	if _left_arch_value < 10 or _right_arch_value < 10 or _arch_gap() > 1:
		return false
	if _is_boss_alive():
		return false
	return true


## Boss 是否仍存活。queue_free 后 _boss == null 在 Godot 4 不可靠，必须用 is_instance_valid。
func _is_boss_alive() -> bool:
	if not is_instance_valid(_boss):
		return false
	if _boss.combat_stats == null:
		return false
	return _boss.combat_stats.is_alive()


## 把"未满足"原因拼成一句简短文案，方便玩家定位差哪一项。
func _close_arch_failure_reason() -> String:
	var reasons: Array[String] = []
	if _is_boss_alive():
		reasons.append("偏载傀未击败（HP %d）" % _boss.combat_stats.current_hp)
	if _left_arch_value < 10 or _right_arch_value < 10:
		reasons.append("券值不足（左 %d/10，右 %d/10）" % [_left_arch_value, _right_arch_value])
	if _arch_gap() > 1:
		reasons.append("差值过大（差 %d，需 ≤1）" % _arch_gap())
	if reasons.is_empty():
		return "未知原因"
	return "、".join(reasons)


func _close_arch_via_skill() -> void:
	_arch_closed = true
	if _crown_tile != null:
		_crown_tile.visible = false
	if _crown_marker != null:
		_crown_marker.visible = false
	_update_status_panel()
	Notify.notify("收缝合龙完成，安济桥成！", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 3.0)


func _shift_load() -> void:
	if not _is_boss_alive():
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
## 当任一侧券值已经 > 8（即 ≥9）、且玩家还没合龙，偏载傀立刻把那一侧 −1（瞬间打断"凑满"
## 节奏），然后从同一侧召唤 2 名错券兵；下回合末错券兵的扰券被动会再把那侧 −2。
## 总效果：触发侧瞬时 −1 + 下回合 −2 = −3，玩家从"差一步合龙"被推回需要先清兵再补券。
##
## 与 _shift_load 互补：shift_load 是慢性压力，倾压之号是临门一脚的爆发。
## 触发后 _clutch_fired 置 true，整关不再触发。
##
## 历史上用过 `mini(...) < 9 + gap <= 1` 双闸门——shift_load 持续压高侧导致 min 长期不到 9，
## clutch 几乎死代码。改为"任一侧 > 8 即触发，不看差值"，让此机制必然出现一次。
func _maybe_boss_clutch_summon() -> void:
	if _clutch_fired or _arch_closed:
		return
	if not _is_boss_alive():
		return
	if maxi(_left_arch_value, _right_arch_value) <= 8:
		return
	# 选定较高一侧；相等则随机
	var target_left: bool
	if _left_arch_value > _right_arch_value:
		target_left = true
	elif _right_arch_value > _left_arch_value:
		target_left = false
	else:
		target_left = randi() % 2 == 0
	# 触发瞬间先扣 1：把"凑满"节奏直接打断，再让召唤的错券兵继续扰券
	_adjust_arch_value(target_left, -1, "倾压之号瞬时扣券")
	_update_status_panel()
	var platform: Vector2i = _left_platform if target_left else _right_platform
	var side_name: String = "左" if target_left else "右"
	var offsets: Array[Vector2i]
	if target_left:
		offsets = [Vector2i(-1, -1), Vector2i(-1, 1)]
	else:
		offsets = [Vector2i(1, -1), Vector2i(1, 1)]
	var summoned: Array[Unit] = []
	for off in offsets:
		var cell := _nearest_bridge_cell(platform + off)
		var unit := _spawn_enemy(
			_make_unit_data(_craftsman_data, "错券兵", 77, 17, 90, 9),
			cell, [_mallet], _visual_misaligned,
		)
		summoned.append(unit)
	_clutch_fired = true
	_unlock_boss()                      # 倾压之号触发后 Boss 才能下桥行动
	Notify.notify(
		"偏载傀倾压之号！%s侧瞬时 −1 + 突现 2 名错券兵（下回合末再扰券 −2），偏载傀开始下桥还手" % side_name,
		Notify.Position.TOP_CENTER, Notify.Style.ERROR, 4.0,
	)
	if not summoned.is_empty():
		_camera_focus_spawned(summoned)


## 让偏载傀进入"全程活跃"配置：放开移动、补土系近战。
## 在倾压之号触发时（_maybe_boss_clutch_summon 末尾）调用——这是 Boss 下桥还手的节点。
func _unlock_boss() -> void:
	if not _is_boss_alive():
		return
	_boss.combat_stats.move_cost_per_tile = 9
	_boss.combat_stats.ap_max = 90
	_boss.combat_stats.ap_current = _boss.combat_stats.ap_max
	_boss.refresh_overhead_bars()
	set_unit_skills(_boss, [_crush])


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

	# 4. 偏载傀「压台」——以 Boss 为中心 12×12 范围（切比雪夫半径 6）内，按距离最近选至多 2 个我方扣 base_atk × 0.5 无属伤
	if _is_boss_alive():
		var press_damage := int(_boss.combat_stats.base_atk * 0.5)
		var press_radius := 6                       # 12×12 = 中心 ±6 切比雪夫
		var press_max_targets := 2
		var candidates: Array[Dictionary] = []
		for ally in teams[PLAYER_TEAM].units:
			if not (ally is Unit) or ally.combat_stats == null or not ally.combat_stats.is_alive():
				continue
			if ally.cell == _boss.cell:
				continue
			var d: int = maxi(absi(ally.cell.x - _boss.cell.x), absi(ally.cell.y - _boss.cell.y))
			if d > press_radius:
				continue
			candidates.append({"ally": ally, "dist": d})
		# 按距离升序——同距离稳定保留输入顺序，不引入随机
		candidates.sort_custom(func(a, b): return a.dist < b.dist)
		var hit_count: int = mini(candidates.size(), press_max_targets)
		for i in hit_count:
			var ally: Unit = candidates[i].ally
			ally.combat_stats.current_hp = maxi(ally.combat_stats.current_hp - press_damage, 0)
			ally.refresh_overhead_bars()
			Notify.notify("%s 被偏载傀压台击中（-%d HP）" % [ally.combat_stats.unit_name, press_damage], Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 1.5)

	_update_status_panel()
	_maybe_notify_balance_transition()
	_check_win_lose()


## Boss 受击伤害上限：和"平衡状态"挂钩，玩家必须维持左右差值才能高效打 Boss。
## 差值 ≤1（均衡）= 无限；2-3（偏衡）= 10；≥4（失衡）= 1。
func _boss_damage_cap() -> int:
	if _arch_gap() >= 4:
		return 1
	if _arch_gap() >= 2:
		return 10
	return 9999


func _arch_gap() -> int:
	return absi(_left_arch_value - _right_arch_value)


func _adjust_arch_value(is_left: bool, delta: int, reason: String) -> void:
	if is_left:
		_left_arch_value = clampi(_left_arch_value + delta, 0, 10)
	else:
		_right_arch_value = clampi(_right_arch_value + delta, 0, 10)
	Notify.notify("%s  左券:%d 右券:%d 稳定:%d" % [reason, _left_arch_value, _right_arch_value, _bridge_stability], Notify.Position.TOP_RIGHT, Notify.Style.INFO, 2.5)
	_update_crown_visibility()
	_update_status_panel()


func _set_carrier_loaded(unit: Unit, loaded: bool) -> void:
	var key := unit.get_instance_id()
	var base_cost := int(_carrier_base_move_cost.get(key, unit.combat_stats.move_cost_per_tile))
	unit.combat_stats.move_cost_per_tile = base_cost + 3 if loaded else base_cost


func _spawn_enemy(data: UnitData, cell: Vector2i, skills: Array[SkillData], visual: PackedScene = null) -> Unit:
	# 敌人必须落在桥上（避免刷到桥下水里）；外部通常已经过 _nearest_bridge_cell，
	# 这里再保一次兜底，防止新调用点遗漏。
	var unit := spawn_unit(data, _nearest_bridge_cell(cell), ENEMY_TEAM, visual)
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


## 扫描桥图层，登记所有桥面 cell。敌人刷新点必须落在桥上。
func _build_bridge_cells() -> void:
	_bridge_cells.clear()
	var container: Node2D = tilemap_container
	if container == null:
		return
	for node in container.find_children("*", "TileMapLayer", true, false):
		var tml := node as TileMapLayer
		if tml == null:
			continue
		if "bridge" not in tml.name.to_lower():
			continue
		for cell in tml.get_used_cells():
			_bridge_cells[cell] = true


## 从 target 螺旋搜索最近的桥面可通行 cell；找不到则回退给 _nearest_walkable。
func _nearest_bridge_cell(target: Vector2i) -> Vector2i:
	if _bridge_cells.has(target) and movement_manager.get_movement_cost(target) != TileType.IMPASSABLE:
		return target
	for radius in range(1, 12):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var c := target + Vector2i(dx, dy)
				if _bridge_cells.has(c) and movement_manager.get_movement_cost(c) != TileType.IMPASSABLE:
					return c
	push_warning("[Level1-3] _nearest_bridge_cell 找不到桥上可通行格，回退到 _nearest_walkable: %s" % target)
	return _nearest_walkable(target)


func _is_adjacent_or_same(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) <= 1


func _is_adjacent_to_any(cell: Vector2i, targets: Array[Vector2i]) -> bool:
	for target in targets:
		if _is_adjacent_or_same(cell, target):
			return true
	return false


## 2×2 判定区：anchor 为西北角，区域含 anchor / +(1,0) / +(0,1) / +(1,1) 四格。
func _zone_cells(anchor: Vector2i) -> Array[Vector2i]:
	return [
		anchor,
		anchor + Vector2i(1, 0),
		anchor + Vector2i(0, 1),
		anchor + Vector2i(1, 1),
	]


func _is_in_zone(cell: Vector2i, anchor: Vector2i) -> bool:
	return cell.x >= anchor.x and cell.x <= anchor.x + 1 \
		and cell.y >= anchor.y and cell.y <= anchor.y + 1


func _is_in_any_zone(cell: Vector2i, anchors: Array[Vector2i]) -> bool:
	for a in anchors:
		if _is_in_zone(cell, a):
			return true
	return false


func get_post_level_growth_options() -> Array[Dictionary]:
	return Progress.get_level_growth_options("关卡1-3")


# 持久成长选项的应用逻辑统一在 base_level._apply_persistent_growth_effects 中处理。


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
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
			Notify.notify("左右偏衡，偏载傀直接受到的伤害上限 10。", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 3.0)
		"失衡":
			Notify.notify("左右失衡！偏载傀几乎无伤，每敌方回合末桥体 -1。", Notify.Position.TOP_CENTER, Notify.Style.ERROR, 3.5)
	_prev_balance_state = new_state


## 大回合开始时：若本回合有波次配置，提前通知。
func _on_stage_round_started(round_num: int) -> void:
	if get_wave_config().has(round_num):
		Notify.notify("第 %d 回合：敌方支援到场" % round_num, Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.5)
	_update_status_panel()
