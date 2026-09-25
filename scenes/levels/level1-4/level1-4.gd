extends BaseLevel
## 第四关《敞肩试汛》

const PLAYER_TEAM := 0
const ENEMY_TEAM := 1

## Boss 怒水的"受击范围" TileMap：设计师在编辑器里画哪些格子算 Boss 受击。
## 运行时设为不可见；其内容会在 _setup_enemies_from_scene 里转成 _boss.extra_target_cells。
@export var boss_hit_area_tilemap: TileMapLayer

var _li_chun: Unit
var _craftsmen: Array[Unit] = []
var _stone_carriers: Array[Unit] = []
var _boss: Unit
# 开局即在场景中预置的敌方非 boss 单位；和 _boss 一样，必须在 get_teams_config
# 阶段缓存住——_on_level_ready 阶段已经被 _reparent_entities_to_obstacles 搬到
# obstacles_tilemap_layer 下，再用 $"Entities/Units/..." 找会拿到 null。
var _flood_spear_1: Unit
var _flood_spear_2: Unit
var _siltmare: Unit

var _overall_stability := 100
var _pending_enemy_resolution := false

# 整桥稳定值上限（= 初值，玩家击杀/打 boss 回血最多回到 100）
const STABILITY_MAX: int = 100

var _left_pier: Vector2i
var _right_pier: Vector2i
var _watch_point: Vector2i
var _side_arch_cells: Dictionary = {}

# ── 怒水三阶段免伤系统（设计稿见 docs/level-design 与 plan：mighty-conjuring-sky）──
# 西起东编号：1=left_back, 2=left_front, 3=right_front, 4=right_back
const PHASE_HP_THRESHOLDS: Array = [0.75, 0.50]                # 进 phase 2 / phase 3 阈值
const PHASE2_AVAILABLE: Array = ["left_back", "right_back"]    # 1 & 4
const PHASE3_INNER: Array = ["left_front", "right_front"]      # 2 & 3
const PHASE3_OUTER: Array = ["left_back", "right_back"]        # 1 & 4 (= PHASE2_AVAILABLE)
const STATUS_KNOCKBACK_IMMUNE := "knockback_immune"

var _boss_phase: int = 1
var _phase_arch_skill_used: Dictionary = {}   # arch_key → bool；_enter_phase 重置
var _arch_blocked_overlay: Dictionary = {}    # arch_key → bool；transient (敌人占位)

# 周期被动 CD：仅在"成功释放"后才进入冷却（设计：释放过后才进入 CD）。
# 初始 = base，确保前几回合按 base 节奏首发；撞期时被让位的技能 CD 维持 0，下回合即可释放。
const SLAM_CD_BASE: int = 2
const TOPPLE_CD_BASE: int = 3
var _slam_cd_remaining: int = SLAM_CD_BASE
var _topple_cd_remaining: int = TOPPLE_CD_BASE

var _hero_data: UnitData = preload("res://data/units/hero_li_chun.tres")
var _hero_visual: PackedScene = preload("res://scenes/unit/visual/human/li_chun/li_chun_visual.tscn")
var _survey_data: UnitData = preload("res://data/units/survey_worker.tres")
var _craftsman_data: UnitData = preload("res://data/units/craftsman_guard.tres")

# 第四关敌方单位（独立 .tres）
# 友方 + Boss + 开局敌方都在 .tscn 中通过 SubResource UnitData 预置（见 get_teams_config）；
# 这里只保留波次刷怪 (_resolve_wave_unit) 用到的敌方独立 .tres。
var _flood_spear_data: UnitData = preload("res://data/units/flood_spear.tres")
var _siltmare_data: UnitData = preload("res://data/units/siltmare.tres")
var _pier_gnawer_data: UnitData = preload("res://data/units/pier_gnawer.tres")
var _driftwood_data: UnitData = preload("res://data/units/flood_driftwood_pack.tres")

# 第一关自然系小怪（混入第四关刷怪池增加多样性）。
# 注：浮木群 (drift_log_pack) 是 water_only，不能上岸，第四关弃用 → 用本关原生
#     漂木群·洪水版 (flood_driftwood_pack) 替代，它有相同的 hazard_charge 直线移动。
var _dark_current_data: UnitData = preload("res://data/units/dark_current.tres")
var _whirl_pool_data: UnitData = preload("res://data/units/whirl_pool.tres")
var _mud_wraith_data: UnitData = preload("res://data/units/bank_mud_wraith.tres")

# 友军技能（复用）
var _staff: SkillData = preload("res://data/skills/sw_staff_end_strike.tres")
var _sw_open_arch: SkillData = preload("res://data/skills/sw_open_arch.tres")
var _mallet: SkillData = preload("res://data/skills/cg_mallet_strike.tres")
var _guard: SkillData = preload("res://data/skills/cg_guard_the_works.tres")

# 漂木群技能（复用现有 dlp_drifting_timber_crash，设计稿的 fdp_driftwood_surge 属后续步骤）
var _timber: SkillData = preload("res://data/skills/dlp_drifting_timber_crash.tres")

# 第四关敌方技能（独立 .tres）
var _torrent_ram: SkillData = preload("res://data/skills/fs_torrent_ram.tres")
var _mire_steps: SkillData = preload("res://data/skills/sm_mire_steps.tres")
var _gnaw_pier: SkillData = preload("res://data/skills/pg_gnaw_pier.tres")
var _overturn_bridge: SkillData = preload("res://data/skills/wf_overturn_bridge.tres")

# 第一关自然系小怪技能（沿用 level1-1.gd 的映射）
var _dc_lunge: SkillData = preload("res://data/skills/dc_hidden_current_lunge.tres")
var _wp_pull: SkillData = preload("res://data/skills/wp_spiral_pull.tres")
var _bmw_crush: SkillData = preload("res://data/skills/bmw_crumbling_bank_crush.tres")
var _slam_deck: SkillData = preload("res://data/skills/wf_slam_deck.tres")
var _topple_bank: SkillData = preload("res://data/skills/wf_topple_bank.tres")

# 关卡配置资源（浅拆：数值 + anchor 偏移 + 波次模板；绝对 cell 运行时算）
var _stage_config: StageConfig = preload("res://data/stages/chapter1_stage4/stage_config.tres")
var _stability_config: BridgeStabilityConfig = preload("res://data/stages/chapter1_stage4/bridge_stability_config.tres")
var _side_arch_config: SideArchConfig = preload("res://data/stages/chapter1_stage4/side_arch_config.tres")
var _wave_spawns: WaveSpawns = preload("res://data/stages/chapter1_stage4/wave_spawns.tres")

# 教程引导（L1-1 同款 dialogue 流程，分三段挂在 boss 阶段切换上）。
const TUTORIAL_ID_P1 := "level1-4_p1"
const TUTORIAL_ID_P2 := "level1-4_p2"
const TUTORIAL_ID_P3 := "level1-4_p3"

# P1 教程"李春攻击 boss 一次"的同步态。skill_executed 信号到达后由
# _on_p1_tutorial_skill_executed 翻成 true，主协程 await 它跳出循环。
var _p1_tutorial_hit_boss: bool = false

# 复玩进关时玩家的"是否再听一遍"选择，进 P1 时设定一次，被 P2/P3 沿用。
# 默认 true：首次进关（任意 phase 教程未看过）一切照旧；只有玩家在 P1 主动选"跳过"才会变 false。
var _wants_tutorial_replay: bool = true

# 特殊地格容器（运行时 register_special_tile）
const SmallArchTileClass := preload("res://scenes/levels/level1-4/small_arch_tile.gd")
const SiltTileClass := preload("res://scenes/levels/level1-4/silt_tile.gd")
const RapidEdgeTileClass := preload("res://scenes/levels/level1-4/rapid_edge_tile.gd")

# 小拱 marker 的杆+下指箭头颜色：按"可交互性"语义区分。
# 黄=可开 / 紫=本阶段不可开 / 绿=已开 / 红=被敌人占位（沿用 halo 红的"塞"信号）。
const POLE_AVAILABLE := Color(1.0, 0.95, 0.55, 0.95)
const POLE_LOCKED := Color(0.75, 0.45, 0.95, 0.95)
const POLE_INTERACTED := Color(0.45, 0.95, 0.55, 0.95)
const POLE_BLOCKED := Color(1.0, 0.45, 0.45, 0.95)

var _arch_tiles: Dictionary = {}          # arch_key → SmallArchTile
var _silt_tiles: Dictionary = {}          # cell → SiltTile
var _rapid_edge_tiles: Dictionary = {}    # cell → RapidEdgeTile
var _status_panel: RichTextLabel = null


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/Player" as Unit
	_craftsmen = [
		$"Entities/Units/Craftsman1" as Unit,
		$"Entities/Units/Craftsman2" as Unit,
		$"Entities/Units/Craftsman3" as Unit,
		$"Entities/Units/Craftsman4" as Unit,
		$"Entities/Units/Craftsman5" as Unit,
	]
	_stone_carriers = [
		$"Entities/Units/StoneCarrier1" as Unit,
		$"Entities/Units/StoneCarrier2" as Unit,
	]
	_boss = $"Entities/Units/Boss" as Unit
	_flood_spear_1 = $"Entities/Units/FloodSpear1" as Unit
	_flood_spear_2 = $"Entities/Units/FloodSpear2" as Unit
	_siltmare = $"Entities/Units/Siltmare" as Unit
	var enemies: Array = [
		_boss,
		_flood_spear_1,
		_flood_spear_2,
		_siltmare,
	]
	var player_units: Array = [_li_chun]
	player_units.append_array(_craftsmen)
	player_units.append_array(_stone_carriers)
	return [
		{
			"name": "守桥队",
			"faction": "好人",
			"controller": "player",
			"units": player_units,
		},
		{
			"name": "洪灾",
			"faction": "坏人",
			"controller": "ai",
			"units": enemies,
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
		# water_only 单位（暗涌 / 水旋 / 浮木群）只能在水格活动，
		# 若 cell_hint 解析到陆地，强制改为附近水格，否则 ai_brain 会让它原地不动。
		var ud: UnitData = unit_bundle["unit_data"]
		if ud != null and ud.water_only and movement_manager != null and not movement_manager.is_water_cell(cell):
			cell = _find_water_cell_near(cell, 8)
		var wave_item := {
			"unit_data": ud,
			"cell": cell,
			"team_index": ENEMY_TEAM,
			"skills": unit_bundle["skills"],
		}
		if not waves.has(round_num):
			waves[round_num] = []
		waves[round_num].append(wave_item)
	return waves


## 1-4 的开局友方、Boss 与首批敌人由 tscn 静态定义；只有波次/阶段援军走这里动态生成。
## 复用 origin/wcx 的 _spawn_enemy 逻辑，确保刷怪落在空可走格，并按 UnitData 覆盖运行时数值。
func _process_wave(round_num: int) -> Array[Unit]:
	var waves := get_wave_config()
	if not waves.has(round_num):
		return [] as Array[Unit]
	var spawned: Array[Unit] = []
	for entry: Dictionary in waves[round_num]:
		var skills: Array[SkillData] = []
		if entry.has("skills"):
			skills.assign(entry["skills"])
		var vis: PackedScene = entry.get("visual", null)
		var unit := _spawn_enemy(entry["unit_data"], entry["cell"], skills, vis)
		if entry.has("color"):
			unit.unit_color = entry["color"]
		spawned.append(unit)
	return spawned


# 把 unit_kind 字符串 → (UnitData 副本, 技能列表)。第四关原生 + 第一关自然系混编。
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
		# 第一关自然系（沿用 level1-1.gd 的技能映射）
		"dark_current":
			return {"unit_data": _duplicate_unit_data(_dark_current_data), "skills": [_dc_lunge]}
		"whirl_pool":
			return {"unit_data": _duplicate_unit_data(_whirl_pool_data), "skills": [_wp_pull]}
		"bank_mud_wraith":
			return {"unit_data": _duplicate_unit_data(_mud_wraith_data), "skills": [_bmw_crush]}
	return {}


# cell_hint 字符串 → 绝对格。依赖 _watch_point / _left_pier / _right_pier / _side_arch_cells 已就位。
# water_* 提示通过 _find_water_cell_near 在锚点附近找水格，让 water_only 自然系能站住。
func _resolve_cell_hint(hint: String) -> Vector2i:
	match hint:
		"near_left_pier_west":
			return CellMath.nearest_walkable(movement_manager, _left_pier + Vector2i(-2, 0))
		"near_right_pier_east":
			return CellMath.nearest_walkable(movement_manager, _right_pier + Vector2i(2, 0))
		"watch_north_2":
			return _watch_point + Vector2i(0, -2)
		"arch_left_front_north_2":
			return _side_arch_cells["left_front"] + Vector2i(0, -4)
		"arch_right_front_north_2":
			return _side_arch_cells["right_front"] + Vector2i(0, -4)
		"water_north":
			return _find_water_cell_near(_watch_point + Vector2i(0, -5), 6)
		"water_south":
			return _find_water_cell_near(_watch_point + Vector2i(0, 5), 6)
		"water_near_left":
			return _find_water_cell_near(_left_pier + Vector2i(-3, 0), 6)
		"water_near_right":
			return _find_water_cell_near(_right_pier + Vector2i(3, 0), 6)
		# 地图东西两端（桥的远端两侧），所有 wave spawn 都从这里登场。
		# 这两个绝对坐标接近 surface tilemap 的左右极限。
		"map_west_edge":
			return CellMath.nearest_walkable(movement_manager, Vector2i(-20, 41))
		"map_east_edge":
			return CellMath.nearest_walkable(movement_manager, Vector2i(41, -20))
	push_warning("wave_spawns: 未知 cell_hint '%s'，退回 watch_point" % hint)
	return _watch_point


# 在 target 附近螺旋扫描一个水格（is_water_cell == true）。找不到时退回 nearest_walkable。
# water_only 单位生成必须落在水上，否则 ai_brain 会判它原地不动。
func _find_water_cell_near(target: Vector2i, max_radius: int) -> Vector2i:
	if movement_manager == null:
		return target
	if movement_manager.is_water_cell(target):
		return target
	for radius in range(1, max_radius + 1):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var candidate: Vector2i = target + Vector2i(dx, dy)
				if movement_manager.is_water_cell(candidate):
					return candidate
	push_warning("water cell hint near %s 找不到水格，退回 nearest_walkable" % target)
	return CellMath.nearest_walkable(movement_manager, target)


# 复制 UnitData 以避免多实例共享同一 Resource 副作用（原 _make_unit_data 的精简版，
# 字段全部沿用 base .tres；ally 方向仍用 _make_unit_data 做字段覆盖）。
# 复制 UnitData 以避免波次刷出的多个实例共享同一 Resource。字段全部沿用 base .tres，
# spawn_unit + setup_unit_stats 在波次回调里再覆盖运行时数值。
func _duplicate_unit_data(base: UnitData) -> UnitData:
	var data := base.duplicate(true) as UnitData
	data.resource_local_to_scene = true
	return data


func get_objectives_text() -> Dictionary:
	return {
		"victory": [
			"- 保护李春与整桥（稳定值 100，归零即败），熬过汛情",
			"- 击杀怒水即胜利",
			"- [color=#7adfff]整桥扣血[/color]：怒水存活每回合 -1；阶段未拆肩另算（见下）；桥台噬者邻 桥心观察位 -2；泥沙魇邻 桥心观察位 -1；洪锋·漂木群冲撞穿桥心 -1",
			"- [color=#7aff8c]整桥回血[/color]：怒水每受到一次攻击 +1；任意敌方倒下 +2（封顶 100）",
			"- [color=#ffcb55]阶段拆肩与压制[/color]：",
			"   • P1 (HP>75%)：无肩可开，无附加压力",
			"   • P2 (50%~75%)：解锁外两肩 1&4；都未开 -1/回合，全开 0",
			"   • P3 (<50%)：解锁四肩，对应 boss 减伤两阶段；都未开 -2；开 2&3 → -1；再开 1&4 → 0",
			"- [color=#ff5555]怒水唤援[/color]：进入 P2 召唤洪锋+桥台噬者；进入 P3 召唤漂木群+桥台噬者+泥沙魇",
			"- [color=#ff8c55]Boss 周期被动【怒涛拍面】[/color]：CD 2，横扫桥心，敌我两伤 — 对全场未护持单位（含 boss 召唤的小怪，boss 自身除外）0.5×水(附水1) 击退 2 格；护持完全豁免",
			"- [color=#ff8c55]Boss 周期被动【翻岸压塌】[/color]：CD 3，对最近 2 名我方 0.7×土(附土2) 击退 3 格；护持半减(-16伤/击退压到 1 格)；与拍面撞期本技优先",
			"- [color=#7adfff]反制[/color]：工匠「捍作护行」赋护持 2 回合 — 每回合预告下回合 boss 释放的技能，请提前调度",
		],
		"defeat": [
			"- 李春倒下",
			"- 整桥稳定值归零",
			"- 超过第 50 回合未能压退怒水",
		],
	}


func check_victory() -> bool:
	return _boss != null and _boss.combat_stats != null and not _boss.combat_stats.is_alive()


# 通关时额外写入章节旗标 + 结算记录（设计稿 §9）。
# 注意：super.complete_level() 内部会调 Progress.complete_level 标记关卡完成并
# 切场到 post 过场动画；本函数在它之前先把 summary 和 chapter flag 落盘。
func complete_level() -> void:
	if is_phase_ended():
		return
	_record_clear_summary()
	Progress.set_chapter_flag("chapter_1", true)
	super()


func _record_clear_summary() -> void:
	var full_release: bool = _open_arch_count() >= 4
	var summary: Dictionary = {
		"turns": round_number,
		"overall_stability_left": _overall_stability,
		"open_arches": _open_arch_count(),
		"full_release_kill": full_release,
		"li_chun_stage_title": "安桥者",
	}
	Progress.set_level_clear_summary("关卡1-4", summary)
	CombatLog.msg("结算: 回合 %d | 整桥 %d | 小拱 %d/4 | 全泄%s | 称号「安桥者」" % [
		summary["turns"], summary["overall_stability_left"],
		summary["open_arches"], "✓" if full_release else "✗",
	])


func check_defeat() -> String:
	if _li_chun == null or _li_chun.combat_stats == null or not _li_chun.combat_stats.is_alive():
		return "李春倒下"
	if _overall_stability <= 0:
		return "整桥稳定值耗尽"
	if round_number > _stage_config.turn_limit:
		return "超过第 %d 回合" % _stage_config.turn_limit
	return ""


func _on_level_ready() -> void:
	_overall_stability = _stability_config.initial_overall
	# _left_pier_stability = _stability_config.initial_left_pier
	# _right_pier_stability = _stability_config.initial_right_pier
	if boss_hit_area_tilemap != null:
		boss_hit_area_tilemap.visible = false
	_setup_anchor_cells()
	_setup_arch_tiles()
	_setup_status_panel()
	_setup_li_chun()
	_setup_allies_from_scene()
	_setup_enemies_from_scene()
	team_turn_started.connect(_on_stage_team_turn_started)
	unit_hp_changed.connect(_on_stage_hp_changed)
	unit_died.connect(_on_stage_unit_died)
	round_started.connect(_on_stage_round_started)
	phase_changed.connect(_on_phase_changed_for_onboarding)
	_update_status_panel()
	Notify.hint("李春与运石工可开启小拱；整桥稳定值 100 归零即败", 3.0)


# 轻教学：进入 PLAYING 阶段后用 dialogue 流程做 P1 开局引导（仿 L1-1 风格）。
# 复玩时通过 Progress.has_seen_tutorial 跳过；P2/P3 引导在 _enter_phase 触发。
func _on_phase_changed_for_onboarding(new_phase: int) -> void:
	if new_phase != LevelPhase.PLAYING:
		return
	_run_p1_tutorial()


func _run_p1_tutorial() -> void:
	if Progress.has_seen_tutorial(TUTORIAL_ID_P1):
		_wants_tutorial_replay = await _ask_tutorial_replay()
		if not _wants_tutorial_replay:
			# 复玩跳过时给一条简短 Notify 提示玩法重点
			Notify.hint("整桥稳定 100 归零即败；多打怒水/小怪可回血；工匠「捍作护行」豁免拍面", 5.0)
			return
	await get_tree().create_timer(0.4).timeout
	if is_phase_ended():
		return
	await play_dialogue([
		_lc_line("洨河汛情正盛，桥要立得住才算赢。屏顶『整桥稳定值 100』归零即败——这一仗不是拼血，是拼桥。"),
		_lc_line("怒水有 600 血、三阶段（HP 75% / 50% 是拐点）。我每打它一下整桥回 1 点，每杀一只小怪回 2 点——所以多动手。"),
		_lc_line("桥两侧有四座『小拱』要开。运石工和我自己都能开，开得越多，每回合扣的稳定值越少。boss 阶段越后，能开的肩也越多。"),
		_lc_line("工匠手里的『捍作护行』给邻接友军 2 回合『护持』——这玩意是抗 boss 大招的关键，记得每回合留一份给前排。"),
	])
	if is_phase_ended():
		return
	# ── 实战引导：让玩家亲自打 boss 一下，直观感受 boss 的"巨型受击范围"──
	await play_dialogue([
		_lc_line("最后一件事：怒水个头巨大，可见的本体小框是骗人的——它的受击区铺到桥心北边好几行水域里。"),
		_lc_line("选中我，挑一招技能朝桥心以北的水域来一下试试，会自动算到怒水头上。命中后整桥还会 +1。"),
	])
	if is_phase_ended():
		return
	Notify.hint(
		"选中李春 → 选技能 → 点桥心以北的水域（怒水的判定区覆盖到北侧 7 行内）", 14.0,
	)
	_p1_tutorial_hit_boss = false
	skill_executed.connect(_on_p1_tutorial_skill_executed)
	while not _p1_tutorial_hit_boss:
		await skill_executed
		if is_phase_ended():
			if skill_executed.is_connected(_on_p1_tutorial_skill_executed):
				skill_executed.disconnect(_on_p1_tutorial_skill_executed)
			return
	if skill_executed.is_connected(_on_p1_tutorial_skill_executed):
		skill_executed.disconnect(_on_p1_tutorial_skill_executed)
	await play_dialogue([
		_lc_line("命中——你看屏右上的回血提示，整桥稳定 +1。攻击 boss 是回血主流，记着。"),
		_lc_line("一阶段没别的花活，先熟悉布阵和开肩节奏。等怒水血量见底我再补课。"),
	])
	if is_phase_ended():
		return
	Progress.mark_tutorial_seen(TUTORIAL_ID_P1)


# 判定指定 cast_cell 是否落在 boss 的本体或 extra_target_cells（巨型受击范围）内。
# 复用 base_level / skill_executor 同一套"加大 hitbox"逻辑。
func _skill_hit_boss(cast_cell: Vector2i) -> bool:
	if _boss == null or not is_instance_valid(_boss):
		return false
	if cast_cell == _boss.cell:
		return true
	for offset in _boss.extra_target_cells:
		if cast_cell == _boss.cell + offset:
			return true
	return false


# P1 教程专用 skill_executed 监听：仅当李春命中 boss 时翻起 _p1_tutorial_hit_boss
# 标志，主协程 _run_p1_tutorial 的 while 循环据此跳出。其他施法（友军间、空地试招）
# 一律忽略，不打断教程。
func _on_p1_tutorial_skill_executed(caster: Unit, _skill: SkillData, cast_cell: Vector2i) -> void:
	if caster == _li_chun and _skill_hit_boss(cast_cell):
		_p1_tutorial_hit_boss = true


func _run_p2_tutorial() -> void:
	if Progress.has_seen_tutorial(TUTORIAL_ID_P2) and not _wants_tutorial_replay:
		return
	# 等阶段提示框关闭后再插入对话，避免抢焦点
	await get_tree().create_timer(0.3).timeout
	if is_phase_ended():
		return
	await play_dialogue([
		_lc_line("怒水开始动真格了——【怒涛拍面】每两回合一次，水属性 0.5 倍率 + 附水，敌我两伤击退 2 格。"),
		_lc_line("注意『敌我两伤』：boss 自己召的小怪也会被它一并打飞，你正好趁势补刀回稳定值。"),
		_lc_line("被『护持』覆盖的友军完全免疫这招——下回合预告会显示在右上角，提前给前排上护持。"),
		_lc_line("P2 解锁了外侧两座小拱（1、4 号）。它们都没开 → 每回合额外 -1；都开了 → 这条压力清零。"),
	])
	if is_phase_ended():
		return
	Progress.mark_tutorial_seen(TUTORIAL_ID_P2)


func _run_p3_tutorial() -> void:
	if Progress.has_seen_tutorial(TUTORIAL_ID_P3) and not _wants_tutorial_replay:
		return
	await get_tree().create_timer(0.3).timeout
	if is_phase_ended():
		return
	await play_dialogue([
		_lc_line("最后关头。怒水又掏出一招【翻岸压塌】每三回合一次——打离它最近的 2 个人，土属性 0.7 倍率 + 附土，击退 3 格。"),
		_lc_line("这招护持只能『半减』：伤害 -16、击退被压到 1 格，但不豁免；让最厚的人靠前顶一下就能扛住。"),
		_lc_line("撞期同回合时本技优先释放，拍面让位至下回合——预告还是看右上角。"),
		_lc_line("P3 四肩都解锁了。都没开 -2；先开 2&3 → -1；再开 1&4 → 压力清零。这时候 boss 也进了易伤窗口（-25%），抓紧击退它。"),
	])
	if is_phase_ended():
		return
	Progress.mark_tutorial_seen(TUTORIAL_ID_P3)


# 在 4 座小拱「2×2 区域」中心生成 TilePulsingMarker 用作状态指示。
# marker.position 偏移 Vector2(0, -8) 让 marker polygon 正好盖住 2×2 区域
# （polygon 64×32 = 2 cells 视觉宽 × 2 cells 视觉高）。
# z_index 走基类默认 1：halo/core/label 浮在地表上但被角色覆盖；Floater(120) 仍抢 top。
func _setup_arch_tiles() -> void:
	for arch_key in _side_arch_cells.keys():
		var marker := _special_tile_registry.spawn_pulsing_marker(
			_side_arch_cells[arch_key],
			SmallArchTile.COLOR_CLOSED,
			"肩",
			Vector2(0, -8),
			"ArchMarker_" + arch_key,
		) as TilePulsingMarker
		marker.show_label = true
		_arch_tiles[arch_key] = marker
	_refresh_arch_visuals()


func _setup_status_panel() -> void:
	_status_panel = RichTextLabel.new()
	_status_panel.name = "Level4StatusPanel"
	_status_panel.bbcode_enabled = true
	_status_panel.fit_content = true
	_status_panel.scroll_active = false
	_status_panel.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status_panel.anchors_preset = Control.PRESET_TOP_LEFT
	_status_panel.offset_left = 18
	_status_panel.offset_top = 84
	_status_panel.offset_right = 300
	_status_panel.offset_bottom = 120
	_status_panel.add_theme_font_size_override("normal_font_size", 16)
	_status_panel.add_theme_color_override("default_color", Color(0.96, 0.94, 0.88))
	_status_panel.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.08))
	_status_panel.add_theme_constant_override("outline_size", 3)
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gui.add_child(_status_panel)


func _update_status_panel() -> void:
	if _status_panel == null:
		return
	var ratio: float = float(_overall_stability) / float(STABILITY_MAX)
	var stability_color := "#d8f6ff"
	if ratio <= 0.30:
		stability_color = "#ff5c5c"
	elif ratio <= 0.60:
		stability_color = "#ffd66e"
	_status_panel.text = "整桥稳定 [color=%s]%d/%d[/color]" % [
		stability_color, _overall_stability, STABILITY_MAX,
	]


# 返回一座小拱占据的 2×2 cells（start + 左 + 上 + 左上，NW 展开）
func _arch_cells_for(arch_key: String) -> Array[Vector2i]:
	return CellMath.zone2x2_nw(_side_arch_cells[arch_key])


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


# 怒水免伤系统视觉刷新：根据 _boss_phase + _phase_arch_skill_used + _arch_blocked_overlay
# 一并重算每个 arch 的 marker 颜色/标签。
# 视觉优先级：blocked > interacted > available > locked
func _refresh_arch_visuals() -> void:
	for arch_key in _side_arch_cells.keys():
		var marker: TilePulsingMarker = _arch_tiles.get(arch_key)
		if marker == null:
			continue
		if _arch_blocked_overlay.get(arch_key, false):
			marker.halo_color = SmallArchTile.COLOR_BLOCKED
			marker.pole_color = POLE_BLOCKED
			marker.label_text = "塞"
		elif _phase_arch_skill_used.get(arch_key, false):
			marker.halo_color = SmallArchTile.COLOR_OPEN
			marker.pole_color = POLE_INTERACTED
			marker.label_text = "通"
		elif _is_arch_available(arch_key):
			marker.halo_color = SmallArchTile.COLOR_CLOSED
			marker.pole_color = POLE_AVAILABLE
			marker.label_text = "可开肩"
		else:
			# 锁定态仍标出肩的位置，只用暗色表达尚未进入开肩窗口。
			marker.halo_color = SmallArchTile.COLOR_CLOSED * Color(0.4, 0.4, 0.4, 1.0)
			marker.pole_color = POLE_LOCKED
			marker.label_text = "肩"


# 当前阶段下某 arch 是否"可用"（玩家技能命中是否生效，且视觉是否亮起）。
# Phase 1：全锁；Phase 2：仅 PHASE2_AVAILABLE；Phase 3：四肩全开。
# 注意：Phase 3 的"先 2&3 后 1&4"是 DR 判定顺序（见 _compute_boss_dr），不是视觉门禁。
func _is_arch_available(arch_key: String) -> bool:
	match _boss_phase:
		2:
			return arch_key in PHASE2_AVAILABLE
		3:
			return arch_key in PHASE3_INNER or arch_key in PHASE3_OUTER
	return false


# 检查指定的 arch_keys 列表是否全部已被本阶段技能标记。
func _all_done(arch_keys: Array) -> bool:
	for k in arch_keys:
		if not _phase_arch_skill_used.get(k, false):
			return false
	return true


func _on_stage_round_started(_r: int) -> void:
	_expire_transient_tiles()


# 定期清理过期的临时地格（淤泥 2 回合 / 激流桥缘 1 回合）。
func _expire_transient_tiles() -> void:
	var round_now := round_number
	for cell in _silt_tiles.keys().duplicate():
		var tile: SiltTile = _silt_tiles[cell]
		if tile == null or not is_instance_valid(tile) or tile.is_expired(round_now):
			if is_instance_valid(tile):
				_special_tile_registry.unregister(tile, cell)
				tile.queue_free()
			_silt_tiles.erase(cell)
	for cell in _rapid_edge_tiles.keys().duplicate():
		var tile: RapidEdgeTile = _rapid_edge_tiles[cell]
		if tile == null or not is_instance_valid(tile) or tile.is_expired(round_now):
			if is_instance_valid(tile):
				_special_tile_registry.unregister(tile, cell)
				tile.queue_free()
			_rapid_edge_tiles.erase(cell)


func _on_unit_moved() -> void:
	# 整桥单一稳定值版本：无桥台抢修玩法，钩子保留以便后续接入。
	pass


func _on_skill_executed(caster: Unit, skill: SkillData, cast_cell: Vector2i, _exec_result: SkillExecutor.ExecuteResult) -> void:
	if skill != null and skill.extra_effect_id == "stage_open_arch":
		for arch_key in _side_arch_cells.keys():
			if cast_cell in _arch_cells_for(arch_key):
				_try_mark_arch_interacted(arch_key)
				break
		return

	# 洪锋 / 漂木群·洪水版 的冲撞线命中桥心 watch_point → 整桥 -1
	if caster == null or caster.combat_stats == null:
		return
	var unit_name_str := caster.combat_stats.unit_name
	if unit_name_str != "洪锋" and unit_name_str != "漂木群·洪水版":
		return
	var path := _charge_line_cells(caster.cell, cast_cell)
	if _watch_point in path:
		_overall_stability = maxi(_overall_stability - 1, 0)
		_update_status_panel()
		Notify.warn("%s 冲撞桥心！整桥 −1 → %d" % [unit_name_str, _overall_stability])
		_get_objectives_tracker().check_win_lose()

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
	_get_objectives_tracker().check_win_lose()


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
# Boss 怒水：翻潮压桥（敌方回合开始）+ 怒涛拍面（敌方回合结束）
# 设计稿 §5.5。
# ─────────────────────────────────────────────
func _cast_overturn_bridge() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	# 桥稳压制现在统一在 _resolve_enemy_pressure（基于已开肩数）结算，本技保留：
	# 桥面上下边缘生成激流桥缘 1 回合（位移陷阱）+ 视觉/语义上的 boss 大招感
	_spawn_rapid_edges_for_overturn()
	Notify.warn("怒水释放【翻潮压桥】（桥缘激流持续 1 回合）")
	_get_objectives_tracker().check_win_lose()


func _boss_slam_deck() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	# 怒涛拍面横扫桥心，无差别打击：
	#   • 友方未护持单位（玩家可用工匠「捍作护行」豁免）
	#   • 敌方所有小怪（boss 自己除外）— 友军伤害平衡设计：boss 召唤越多怪自己被打越多
	var targets: Array = []
	for ally in _get_query_api().get_friendly_units():
		if ally == null or ally.combat_stats == null or not ally.combat_stats.is_alive():
			continue
		if _has_guarding_status(ally):
			continue
		targets.append(ally)
	if teams.size() > ENEMY_TEAM:
		for enemy in teams[ENEMY_TEAM].units:
			if not (enemy is Unit) or enemy.combat_stats == null or not enemy.combat_stats.is_alive():
				continue
			if enemy == _boss:
				continue
			if _has_guarding_status(enemy):
				continue
			targets.append(enemy)
	if targets.is_empty():
		Notify.notify("怒涛拍面：全员护持/无目标", Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 2.0)
		return
	Notify.warn("怒水释放【怒涛拍面】（横扫桥心，敌我两伤）")
	CombatLog.msg("怒涛拍面: 命中 %d 名（含敌方小怪）" % targets.size())
	for target in targets:
		var hit: CombatResolver.HitResult = CombatResolver.resolve_hit(_boss.combat_stats, target.combat_stats, _slam_deck, 0.5)
		var old_hp: int = target.combat_stats.current_hp
		CombatResolver.apply_hit(target.combat_stats, _slam_deck, hit)
		target.refresh_overhead_bars()
		_get_skill_cast_controller().report_unit_damaged(target, old_hp, target.combat_stats.current_hp)
		if target.combat_stats.current_hp <= 0:
			continue
		_knockback_cells(target, _boss.cell, 2)
	_apply_rapid_edge_if_present()


# 翻岸压塌：每 3 回合 1 次。对最近 2 名我方造成 0.7×土属性伤害（附土 2），击退 3 格。
# 与怒涛拍面不同：本技 [b]不[/b] 跳过含护持的目标——护持只走 resolver 的 -16 减伤
# + 在此处把击退距离压到 1 格，作为"半减"而非完全豁免。
func _boss_topple_bank() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	var alive: Array = []
	for ally in _get_query_api().get_friendly_units():
		if ally == null or ally.combat_stats == null or not ally.combat_stats.is_alive():
			continue
		alive.append(ally)
	if alive.is_empty():
		return
	var boss_cell := _boss.cell
	alive.sort_custom(func(a: Unit, b: Unit) -> bool:
		return CellMath.manhattan(a.cell, boss_cell) < CellMath.manhattan(b.cell, boss_cell)
	)
	var targets: Array = alive.slice(0, mini(2, alive.size()))
	Notify.warn("怒水释放【翻岸压塌】")
	CombatLog.msg("翻岸压塌: 命中 %d 名最近单位" % targets.size())
	for target in targets:
		var hit: CombatResolver.HitResult = CombatResolver.resolve_hit(_boss.combat_stats, target.combat_stats, _topple_bank, 0.7)
		var old_hp: int = target.combat_stats.current_hp
		CombatResolver.apply_hit(target.combat_stats, _topple_bank, hit)
		target.refresh_overhead_bars()
		_get_skill_cast_controller().report_unit_damaged(target, old_hp, target.combat_stats.current_hp)
		if target.combat_stats.current_hp <= 0:
			continue
		# 护持半减：击退 3 → 1（与设定文档「护持抗位移最多 1 格」一致）
		var kb_dist: int = 1 if _has_guarding_status(target) else 3
		_knockback_cells(target, _boss.cell, kb_dist)
	_apply_rapid_edge_if_present()


# 朝"远离 from_cell"的方向逐格击退 target，最多 distance 格。地形不可走或被其他单位占据则提前停步。
func _knockback_cells(target: Unit, from_cell: Vector2i, distance: int) -> void:
	if target == null or movement_manager == null or distance <= 0:
		return
	if _has_knockback_immune_status(target):
		CombatLog.msg("  击退: %s 拥有【抗击退】，免疫击退%d格" % [target.combat_stats.unit_name, distance])
		return
	var diff: Vector2i = target.cell - from_cell
	if diff == Vector2i.ZERO:
		return
	var dir: Vector2i
	if absi(diff.x) >= absi(diff.y):
		dir = Vector2i(signi(diff.x), 0)
	else:
		dir = Vector2i(0, signi(diff.y))
	var from := target.cell
	var current := target.cell
	for i in range(distance):
		var next: Vector2i = current + dir
		if movement_manager.get_movement_cost(next) == TileType.IMPASSABLE:
			break
		var blocked := false
		for team in teams:
			for u in team.units:
				if u is Unit and u != target and (u as Unit).cell == next:
					blocked = true
					break
			if blocked:
				break
		if blocked:
			break
		current = next
	if current == from:
		return
	target.cell = current
	if movement_manager.movement_tilemaps.size() > 0:
		var tm: TileMapLayer = movement_manager.movement_tilemaps[0]
		target.position = tm.map_to_local(current)
	CombatLog.msg("  击退: %s (%s → %s)" % [target.combat_stats.unit_name, from, current])


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


func _has_knockback_immune_status(unit: Unit) -> bool:
	if unit == null or unit.combat_stats == null:
		return false
	return unit.combat_stats.has_status(STATUS_KNOCKBACK_IMMUNE)


func _on_stage_team_turn_started(team_index: int) -> void:
	if team_index == ENEMY_TEAM:
		_pending_enemy_resolution = true
		_cast_overturn_bridge()
		# 洪锋「涌锋」被动：首次移动 +1 格。AP 重置在 emit 之后才跑，所以 defer 到重置后再给。
		_apply_flood_spear_surge.call_deferred()
		# 淤泥「淤行」持续效果：上回合在淤泥上结束行动的，本回合 -2 AP
		_apply_silt_lingering_penalty.call_deferred(ENEMY_TEAM)
	elif team_index == PLAYER_TEAM and _pending_enemy_resolution:
		_pending_enemy_resolution = false
		_resolve_enemy_pressure()
		# 周期被动调度：翻岸压塌（每 3 回合）优先于怒涛拍面（每 2 回合），
		# 同一回合两者撞期时只发 topple_bank，slam 让位（设计稿"不能同时释放"）。
		_boss_decide_periodic_skill()
		_apply_silt_lingering_penalty.call_deferred(PLAYER_TEAM)


# 选择本回合 boss 释放哪个周期被动；并给出下回合的预警 Notify。
# 调度规则：
#   1. 每个玩家回合开始先 cd-=1（clamp ≥0）。CD==0 即可释放。
#   2. 同回合两者都到 0 时，翻岸压塌 优先；怒涛拍面 让位（CD 不重置，下回合再发）。
#   3. 仅"成功释放"后才把 CD 重置为 base — 这是用户要求的"释放过后才进入 CD"。
func _boss_decide_periodic_skill() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	_slam_cd_remaining = maxi(_slam_cd_remaining - 1, 0)
	_topple_cd_remaining = maxi(_topple_cd_remaining - 1, 0)
	if _topple_cd_remaining == 0:
		_boss_topple_bank()
		_topple_cd_remaining = TOPPLE_CD_BASE
		# slam 若同回合也 ready，cd 维持 0 → 下回合即释放（让位语义）
	elif _slam_cd_remaining == 0:
		_boss_slam_deck()
		_slam_cd_remaining = SLAM_CD_BASE
	_show_next_round_preview()


# 每回合都展示下回合 boss 将释放的技能（用户要求）。
# 通过模拟 cd-=1 来预测，逻辑与 _boss_decide_periodic_skill 一致。
func _show_next_round_preview() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	var sim_slam: int = maxi(_slam_cd_remaining - 1, 0)
	var sim_topple: int = maxi(_topple_cd_remaining - 1, 0)
	var label: String
	if sim_topple == 0:
		label = "【翻岸压塌】（土，最近 2 名 0.7×+附土 2，击退 3 格）— 护持只能半减(-16伤/击退压到1格)，无法豁免"
	elif sim_slam == 0:
		label = "【怒涛拍面】（水，横扫桥心敌我两伤 0.5×+附水 1，击退 2 格）— 工匠「捍作护行」可豁免；boss 也会攻击自家小怪"
	else:
		label = "蓄力中（无周期被动；可推进开肩）"
	Notify.info("下回合怒水：%s" % label, 4.0)


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
	if unit != _boss:
		return
	# 怒水受击 → 整桥 +1（伤害下降才算，治疗或同值不算）。
	if new_hp < old_hp and _boss.combat_stats != null and _boss.combat_stats.is_alive():
		_gain_stability(1, "怒水受击")
	# 阶段切换由 HP 阈值驱动；DR 已在 CombatResolver 通过 incoming_damage_factor 生效。
	_check_phase_transition()


# 任意敌方单位死亡 → 整桥 +2。Boss 死亡也会触发，但此时已胜利结算，加血只影响 summary。
func _on_stage_unit_died(unit: Unit) -> void:
	if unit == null or unit.combat_stats == null:
		return
	if teams.size() <= ENEMY_TEAM:
		return
	var is_enemy: bool = false
	for u in teams[ENEMY_TEAM].units:
		if u == unit:
			is_enemy = true
			break
	if not is_enemy:
		return
	_gain_stability(2, "%s 倒下" % unit.combat_stats.unit_name)


# 整桥 +amount，封顶 STABILITY_MAX。amount<=0 时不操作。
func _gain_stability(amount: int, reason: String) -> void:
	if amount <= 0:
		return
	var before: int = _overall_stability
	_overall_stability = mini(_overall_stability + amount, STABILITY_MAX)
	_update_status_panel()
	var actual: int = _overall_stability - before
	if actual <= 0:
		return
	Notify.notify(
		"整桥 +%d → %d（%s）" % [actual, _overall_stability, reason],
		Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 2.0,
	)
	CombatLog.msg("整桥稳定 +%d (%s) → %d" % [actual, reason, _overall_stability])


# 怒水当前阶段的免伤值（>0 = 减伤；<0 = 易伤；=0 = 无修正）。
# Phase 1: 0 / Phase 2: 0.75（PHASE2_AVAILABLE 全 done 后 0）
# Phase 3: 0.75 → 0.25（内对全 done）→ -0.25（再外对全 done）
func _compute_boss_dr() -> float:
	match _boss_phase:
		2:
			return 0.0 if _all_done(PHASE2_AVAILABLE) else 0.75
		3:
			var inner_done := _all_done(PHASE3_INNER)
			var outer_done := _all_done(PHASE3_OUTER)
			if inner_done and outer_done:
				return -0.25
			if inner_done:
				return 0.25
			return 0.75
	return 0.0


# 把 _compute_boss_dr 写入 boss.combat_stats.incoming_damage_factor。
# CombatResolver.resolve_hit 会在 step 8 自动乘上它。
func _refresh_boss_dr() -> void:
	if _boss == null or _boss.combat_stats == null:
		return
	_boss.combat_stats.incoming_damage_factor = 1.0 - _compute_boss_dr()


# Boss HP 跨阈值时自动进入下一阶段。单向（只升不降）。
func _check_phase_transition() -> void:
	if _boss == null or _boss.combat_stats == null or not _boss.combat_stats.is_alive():
		return
	var ratio: float = float(_boss.combat_stats.current_hp) / float(_boss.combat_stats.max_hp)
	var target_phase: int = 1
	if ratio <= PHASE_HP_THRESHOLDS[1]:
		target_phase = 3
	elif ratio <= PHASE_HP_THRESHOLDS[0]:
		target_phase = 2
	if target_phase > _boss_phase:
		_enter_phase(target_phase)


# 阶段进入：清空所有 4 个肩的 interacted 标记，刷新 marker 与 DR。
func _enter_phase(phase: int) -> void:
	_boss_phase = phase
	_phase_arch_skill_used.clear()
	_refresh_arch_visuals()
	_refresh_boss_dr()
	var dr_pct: int = int(round(_compute_boss_dr() * 100))
	Notify.notify(
		"怒水进入第 %d 阶段（免伤 %d%%）" % [phase, dr_pct],
		Notify.Position.TOP_CENTER, Notify.Style.WARNING, 3.0,
	)
	CombatLog.msg("怒水进入第 %d 阶段，免伤 %d%%" % [phase, dr_pct])
	_spawn_phase_reinforcements(phase)
	# 阶段教程：仅首次进入时弹 dialogue；复玩走 has_seen_tutorial 自动跳过
	match phase:
		2:
			_run_p2_tutorial()
		3:
			_run_p3_tutorial()


# 阶段进入时怒水召唤援军（第四关原生小怪为主，强调"boss 唤援"叙事）。
# P2: 2 个 L4（洪锋 + 桥台噬者）— 中段双线压力
# P3: 3 个 L4（漂木群·洪水版 + 桥台噬者 + 泥沙魇）— 高强度收尾威胁
# 用 _resolve_wave_unit + _resolve_cell_hint 复用 wave 系统的解析层。
func _spawn_phase_reinforcements(phase: int) -> void:
	var bundles: Array[String] = []
	var hints: Array[String] = []
	match phase:
		2:
			bundles = ["flood_spear", "pier_gnawer"]
			hints = ["map_west_edge", "map_east_edge"]
			Notify.notify(
				"怒水唤援：洪锋（西） + 桥台噬者（东） 入场",
				Notify.Position.TOP_CENTER, Notify.Style.WARNING, 3.5,
			)
		3:
			bundles = ["flood_driftwood_pack", "pier_gnawer", "siltmare"]
			hints = ["map_east_edge", "map_west_edge", "map_east_edge"]
			Notify.notify(
				"怒水洪魁灌涌：漂木群 + 桥台噬者 + 泥沙魇 从两端入场",
				Notify.Position.TOP_CENTER, Notify.Style.WARNING, 4.0,
			)
		_:
			return
	for i in bundles.size():
		var bundle: Dictionary = _resolve_wave_unit(bundles[i])
		if bundle.is_empty():
			continue
		var skills: Array[SkillData] = []
		skills.assign(bundle["skills"])
		var cell: Vector2i = _resolve_cell_hint(hints[i])
		var ud: UnitData = bundle["unit_data"]
		# 与 wave 系统相同的 water_only 兜底
		if ud != null and ud.water_only and movement_manager != null and not movement_manager.is_water_cell(cell):
			cell = _find_water_cell_near(cell, 8)
		_spawn_enemy(ud, cell, skills)
		CombatLog.msg("阶段 %d 召唤: %s @ %s" % [phase, bundles[i], cell])


func _setup_anchor_cells() -> void:
	var anchor := _li_chun.cell
	_watch_point = CellMath.nearest_walkable(movement_manager, anchor + Vector2i(0, -1))
	_left_pier = CellMath.nearest_walkable(movement_manager, anchor + Vector2i(-4, 0))
	_right_pier = CellMath.nearest_walkable(movement_manager, anchor + Vector2i(4, 0))
	# 4 座小拱：surface z=0 的绝对 cell 坐标，每座是 2×2 区域（start + 左 + 上 + 左上）。
	# 原始读数在 TileMaps/bridge1（position=Vector2(0,440)）的 cell 系下；surface z=0 在
	# 原点，两者 tile_set 一致（iso DIAMOND_DOWN, tile_size=32x16），因此换算为
	# surface_cell = bridge1_cell + Vector2i(27, 27)（local_to_map floor 后的等价偏移）。
	_side_arch_cells = {
		"left_back": Vector2i(-16, 15),     # 西侧后肩  (bridge1: -43,-12)
		"left_front": Vector2i(-13, 11),    # 西侧前肩  (bridge1: -40,-16)
		"right_front": Vector2i(9, -12),    # 东侧前肩  (bridge1: -18,-39)
		"right_back": Vector2i(14, -15),    # 东侧后肩  (bridge1: -13,-42)
	}


func _setup_li_chun() -> void:
	_get_unit_factory().set_unit_skills(_li_chun, Progress.get_battle_skill_resources(GameState.selected_level))
	_get_unit_factory().setup_unit_stats(_li_chun, "李春", 138, 26, 105, 8, Enums.Element.NONE, 0, true)


# 友方 / 敌方均在 .tscn 里预置（unit_data + visual_scene + position 都已配齐）；
# 这里只补技能 + 战斗数值。setup_unit_stats 会覆盖 combat_stats 的基线。
func _setup_allies_from_scene() -> void:
	for craftsman in _craftsmen:
		_get_unit_factory().set_unit_skills(craftsman, [_mallet, _guard])
		_get_unit_factory().setup_unit_stats(craftsman, "工匠", 120, 20, 95, 9)
	for carrier in _stone_carriers:
		_get_unit_factory().set_unit_skills(carrier, [_staff, _sw_open_arch])
		_get_unit_factory().setup_unit_stats(carrier, "运石工", 92, 14, 95, 9)
	_apply_persistent_growth_effects()


# 持久成长选项的应用逻辑统一在 base_level._apply_persistent_growth_effects 中处理。


func _setup_enemies_from_scene() -> void:
	# Boss 怒水：固定不动（move_cost_per_tile=99 / ap_max=1），受击范围由
	# TileMaps/boss_hit_area 这层 TileMap 定义——设计师在编辑器里画哪些桥面格
	# 算"打到 Boss"。运行时把这些绝对格子转成相对偏移塞进 extra_target_cells，
	# 让 base_level 的 targeting overlay + skill_executor 的命中判定都直接复用。
	_get_unit_factory().setup_unit_stats(_boss, "怒水", 600, 24, 1, 99, Enums.Element.WATER, 2)
	_apply_permanent_status(_boss, STATUS_KNOCKBACK_IMMUNE)
	_get_unit_factory().set_unit_skills(_boss, [_overturn_bridge])
	_populate_boss_hit_area()

	_get_unit_factory().setup_unit_stats(_flood_spear_1, "洪锋", 70, 21, 90, 10, Enums.Element.WATER, 2)
	_get_unit_factory().set_unit_skills(_flood_spear_1, [_torrent_ram])

	_get_unit_factory().setup_unit_stats(_flood_spear_2, "洪锋", 70, 21, 90, 10, Enums.Element.WATER, 2)
	_get_unit_factory().set_unit_skills(_flood_spear_2, [_torrent_ram])

	# 与 wave 系统保持一致：开局两只洪锋也从地图东西两端登场，而不是 .tscn 里的预置点。
	_relocate_unit_to_edge(_flood_spear_1, "map_west_edge")
	_relocate_unit_to_edge(_flood_spear_2, "map_east_edge")

	_get_unit_factory().setup_unit_stats(_siltmare, "泥沙魇", 105, 15, 90, 10, Enums.Element.EARTH, 2)
	_get_unit_factory().set_unit_skills(_siltmare, [_mire_steps])


func _apply_permanent_status(unit: Unit, status_id: String) -> void:
	if unit == null or unit.combat_stats == null:
		return
	for s in unit.combat_stats.statuses:
		if s.status_id == status_id:
			s.remaining_turns = -1
			return
	var si := CombatResolver.StatusInstance.new()
	si.status_id = status_id
	si.remaining_turns = -1
	unit.combat_stats.statuses.append(si)
	unit.refresh_overhead_bars()


# 将场景预置的敌方单位搬到 _resolve_cell_hint 指定的锚点，复用 wave 系统的查格 + 占位避让。
func _relocate_unit_to_edge(unit: Unit, hint: String) -> void:
	if unit == null or tilemap == null:
		return
	var target := _resolve_cell_hint(hint)
	var cell := _get_scene_bootstrap().find_empty_walkable_cell(target)
	unit.set_cell(cell, tilemap)


# 把 boss_hit_area_tilemap 上画好的绝对格子转成相对 _boss.cell 的偏移，写进
# _boss.extra_target_cells。base_level 的 hover overlay（_show_skill_targeting_for）
# 与 skill_executor 的命中判定（_unit_in_effect）都消费这个数组——零改基类即可生效。
func _populate_boss_hit_area() -> void:
	if _boss == null:
		return
	if boss_hit_area_tilemap == null:
		push_warning("[Level1-4] boss_hit_area_tilemap 未配置，Boss 受击范围退化为本格")
		return
	var origin: Vector2i = _boss.cell
	var offsets: Array[Vector2i] = []
	for cell in boss_hit_area_tilemap.get_used_cells():
		offsets.append(cell - origin)
	_boss.extra_target_cells = offsets


func _try_mark_arch_interacted(arch_key: String) -> void:
	if not _is_arch_available(arch_key):
		var hint: String
		if _boss_phase < 2:
			hint = "此交互点尚未开放"
		else:
			hint = "二阶段仅外侧两肩可拆"
		Notify.warn(hint, 2.0)
		return
	if _phase_arch_skill_used.get(arch_key, false):
		Notify.info("此交互点本阶段已生效", 1.5)
		return
	var dr_before: float = _compute_boss_dr()
	_phase_arch_skill_used[arch_key] = true
	_refresh_arch_visuals()
	_refresh_boss_dr()
	var dr_after: float = _compute_boss_dr()
	var label: String = ("易伤 %d%%" % int(round(-dr_after * 100))) if dr_after < 0.0 else ("免伤 %d%%" % int(round(dr_after * 100)))
	if is_equal_approx(dr_before, dr_after):
		# Phase 3 先打 1/4 时会到这里：标记登记成功，但 DR 还要等 2&3 都 done 才落地
		Notify.info(
			"导汛开肩 → 已登记（怒水 %s，待中间两肩拆完后联动）" % label
		)
	else:
		Notify.notify(
			"导汛开肩 → 怒水当前 %s" % label,
			Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 2.5,
		)
	CombatLog.msg("拆肩: %s 已交互；当前 %s" % [arch_key, label])


func _resolve_enemy_pressure() -> void:
	# 重算 blocked overlay：开始时清空，再按当前敌人占位重新刷一遍。
	# blocked 仅是视觉提示（红 "塞"），不影响 _phase_arch_skill_used 与 boss DR。
	_arch_blocked_overlay.clear()
	for enemy in teams[ENEMY_TEAM].units:
		if not (enemy is Unit) or enemy.combat_stats == null or not enemy.combat_stats.is_alive():
			continue
		# 漂木群「塞肩」+ 泥沙魇「淤行」：行动结束停在小拱上 → 该小拱 blocked overlay
		var u_name: String = enemy.combat_stats.unit_name
		if u_name == "漂木群·洪水版" or u_name == "泥沙魇":
			for arch_key in _side_arch_cells.keys():
				if enemy.cell in _arch_cells_for(arch_key):
					_arch_blocked_overlay[arch_key] = true
		# 泥沙魇「淤行」第二部分：若行动结束不在小拱上，自身格生成淤泥 2 回合
		if u_name == "泥沙魇" and not _cell_is_small_arch(enemy.cell):
			_spawn_silt_at(enemy.cell)
	_refresh_arch_visuals()

	# ── 整桥稳定值压力（单一值，初始 100，归零即败）──
	# A. 怒水存活基础：boss 活着每回合 -1。
	# B. 阶段未拆肩附加：
	#    P1 (HP>75%) — 没有肩可以开 → 0 附加
	#    P2 (50%<HP≤75%) — 解锁外两肩(1=left_back,4=right_back)；都未开 -1，全开 0
	#    P3 (HP≤50%) — 解锁四肩，对应 boss 减伤的两个阶段：
	#      0 阶段未做（默认）：-2
	#      已开 inner(2&3) → -1（DR 75%→25%）
	#      再开 outer(1&4) → 0（DR 25%→-25% 易伤）
	# C. 邻接事件（保留小怪机制）：桥台噬者邻 watch_point -2；泥沙魇邻 watch_point -1。
	# 玩家正向收益（在 hp_changed/unit_died 钩子里给）：
	#    怒水受击 +1 ｜ 任意敌方倒下 +2（封顶 100）
	var boss_alive: bool = _boss != null and _boss.combat_stats != null and _boss.combat_stats.is_alive()
	var alive_dmg: int = 1 if boss_alive else 0
	var phase_dmg: int = _compute_phase_arch_pressure() if boss_alive else 0

	var event_dmg: int = 0
	for enemy in teams[ENEMY_TEAM].units:
		if not (enemy is Unit) or enemy.combat_stats == null or not enemy.combat_stats.is_alive():
			continue
		var u_name: String = enemy.combat_stats.unit_name
		if not CellMath.is_adjacent_or_same(enemy.cell, _watch_point):
			continue
		if u_name == "桥台噬者":
			event_dmg += 2
		elif u_name == "泥沙魇":
			event_dmg += 1

	var total: int = alive_dmg + phase_dmg + event_dmg
	if total > 0:
		_overall_stability = maxi(_overall_stability - total, 0)
		_update_status_panel()

	Notify.warn(
		"整桥:%d 已拆肩:%d/4（怒水 -%d｜阶段 -%d｜邻桥心 -%d）" % [
			_overall_stability, _open_arch_count(), alive_dmg, phase_dmg, event_dmg,
		]
	)
	_get_objectives_tracker().check_win_lose()


# 阶段相关肩压力。归位规则镜像 boss DR 的进程，给玩家一致的"拆肩 = 减压"反馈。
func _compute_phase_arch_pressure() -> int:
	match _boss_phase:
		2:
			return 0 if _all_done(PHASE2_AVAILABLE) else 1
		3:
			var inner_done: bool = _all_done(PHASE3_INNER)
			var outer_done: bool = _all_done(PHASE3_OUTER)
			if inner_done and outer_done:
				return 0
			if inner_done:
				return 1
			return 2
	return 0


func _get_ai_context() -> Dictionary:
	return {
		"drift_directions": {
			"漂木群·洪水版": Vector2i(0, 1),
		},
		"priority_targets": _build_priority_targets(),
	}


# 每个敌方回合开始时重算：当前运石工存活、小拱关闭状态都会影响谁最该被盯。
# 设计稿 §2 敌方 AI（整桥单值版本）：
#   洪锋     → 桥面我方优先；同区段按「到 watch_point 曼哈顿距离」排序
#   桥台噬者 → 任意我方，按「到 watch_point 曼哈顿距离」排序（贴桥心 -2 整桥）
#   泥沙魇   → 运石工优先，按「到最近未交互肩距离」排序
#   漂木群   → hazard_charge 直线模板，方向在 drift_directions
func _build_priority_targets() -> Dictionary:
	var priorities: Dictionary = {}

	var alive_allies: Array = []
	for a in _get_query_api().get_friendly_units():
		if a is Unit and a.combat_stats != null and a.combat_stats.is_alive():
			alive_allies.append(a)

	# 洪锋：桥面我方优先；同区段越靠近 watch_point 越靠前
	var flood_spear_list: Array = alive_allies.duplicate()
	flood_spear_list.sort_custom(func(x: Unit, y: Unit) -> bool:
		var x_on: int = 0 if _is_on_main_bridge(x.cell) else 1
		var y_on: int = 0 if _is_on_main_bridge(y.cell) else 1
		if x_on != y_on:
			return x_on < y_on
		return CellMath.manhattan(x.cell, _watch_point) < CellMath.manhattan(y.cell, _watch_point)
	)
	priorities["洪锋"] = flood_spear_list

	# 桥台噬者：任何我方，按到 watch_point 曼哈顿距离排序（趋近桥心制造 -2 压力）
	var gnawer_list: Array = alive_allies.duplicate()
	gnawer_list.sort_custom(func(x: Unit, y: Unit) -> bool:
		return CellMath.manhattan(x.cell, _watch_point) < CellMath.manhattan(y.cell, _watch_point)
	)
	priorities["桥台噬者"] = gnawer_list

	# 泥沙魇：运石工优先；按到最近"未交互肩"距离排序
	var closed_arches: Array = []
	for arch_key in _side_arch_cells.keys():
		if not _phase_arch_skill_used.get(arch_key, false):
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


func _cell_is_small_arch(cell: Vector2i) -> bool:
	for arch_key in _side_arch_cells.keys():
		if cell in _arch_cells_for(arch_key):
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
	_special_tile_registry.register(tile, cell)
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
	_special_tile_registry.register(tile, cell)
	_rapid_edge_tiles[cell] = tile


# 本阶段已交互（"通"）的肩数。供稳定值压力计算与结算 summary 使用。
func _open_arch_count() -> int:
	var count := 0
	for arch_key in _side_arch_cells.keys():
		if _phase_arch_skill_used.get(arch_key, false):
			count += 1
	return count


func _spawn_enemy(data: UnitData, cell: Vector2i, skills: Array[SkillData], visual: PackedScene = null) -> Unit:
	var unit := _get_unit_factory().spawn_unit(data, _get_scene_bootstrap().find_empty_walkable_cell(cell), ENEMY_TEAM, visual)
	_get_unit_factory().set_unit_skills(unit, skills)
	_get_unit_factory().setup_unit_stats(
			unit,
			data.unit_name,
			data.max_hp,
			data.base_atk,
			data.ap_max,
			data.move_cost_per_tile,
			data.innate_element,
			data.innate_element_amount)
	return unit
