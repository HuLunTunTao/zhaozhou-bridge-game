class_name SurvivalLevel
extends BaseLevel
## 无尽生存额外关卡。
##
## 复用 level1-1 的地图（继承场景），但清掉所有预置单位/标记，由 SurvivalWaveController
## 在运行时刷怪。玩家起手由 _on_level_ready spawn 一队工匠/测量工/李春。
##
## 胜利条件：永远不胜利（无尽）。
## 失败条件：玩家队全灭，reason = "你坚守了 N 波"。

const _WaveBuffHudScene := preload("res://scenes/levels/survival/wave_buff_hud.tscn")
const _WaveControllerScript := preload("res://scenes/levels/survival/wave_controller.gd")

# ── 玩家起手单位 ──
const _UD_LI_CHUN := preload("res://data/units/hero_li_chun.tres")
const _UD_CRAFTSMAN := preload("res://data/units/craftsman_guard.tres")
const _UD_SURVEY := preload("res://data/units/survey_worker.tres")

# ── 起手技能（参考 level1-1 配置） ──
const _SK_MALLET := preload("res://data/skills/cg_mallet_strike.tres")
const _SK_GUARD := preload("res://data/skills/cg_guard_the_works.tres")
const _SK_STAFF := preload("res://data/skills/sw_staff_end_strike.tres")
const _SK_SURVEY := preload("res://data/skills/sw_field_measure_site.tres")
# ── 李春起手技能 ──
const _SK_LC_RULE := preload("res://data/skills/lc_rule_strike.tres")
const _SK_LC_LINE_LOCK := preload("res://data/skills/lc_line_lock_arc.tres")
# ── 李春可学池（buff 抽卡候选） ──
const _SK_LC_INKLINE := preload("res://data/skills/lc_inkline_balance_arch.tres")
const _SK_LC_INK_SET := preload("res://data/skills/lc_ink_set_arch.tres")
const _SK_LC_DIVIDER := preload("res://data/skills/lc_divider_mark_arc.tres")
const _SK_LC_LINK := preload("res://data/skills/lc_link_wedges_arch.tres")
const _SK_LC_PILE_BIND := preload("res://data/skills/lc_pile_bind_wave.tres")
const _SK_LC_GUIDE_FLOOD := preload("res://data/skills/lc_guide_flood_open_arch.tres")
const _SK_LC_WEDGE_BANK := preload("res://data/skills/lc_wedge_bank_probe.tres")
const _SK_LC_CAST_STONE := preload("res://data/skills/lc_cast_stone_arrest_flow.tres")

# ── 起手放置位置（基于 level1-1 中心区域可走格） ──
const _HERO_CELL := Vector2i(-1, 2)
const _CRAFTSMAN_A_CELL := Vector2i(-2, 2)
const _CRAFTSMAN_B_CELL := Vector2i(0, 2)
const _SURVEY_CELL := Vector2i(-1, 3)

const _HERO_COLOR := Color(1, 0.85, 0, 1)
const _CRAFTSMAN_COLOR := Color(0.4, 0.8, 0.9, 1)
const _SURVEY_COLOR := Color(0.3, 0.9, 0.5, 1)

## 类型用 Node 而不是 class_name：避免 class_name 注册顺序导致的解析错误。
var _wave_controller: Node = null
var _hud: Node = null


func get_teams_config() -> Array:
	# 清掉 level1-1 留下的占位单位与标记节点
	if has_node("Entities/Units"):
		for child in $"Entities/Units".get_children():
			$"Entities/Units".remove_child(child)
			child.queue_free()
	if has_node("Markers"):
		var markers := $Markers
		markers.get_parent().remove_child(markers)
		markers.queue_free()
	# level1-1 还有桥台标记 / SpecialTiles 容器，不动；空 SpecialTiles 没影响
	return [
		{
			"name": "玩家队伍",
			"faction": "好人",
			"controller": "player",
			"units": [],
		},
		{
			"name": "敌方",
			"faction": "坏人",
			"controller": "ai",
			"units": [],
		},
	]


func get_wave_config() -> Dictionary:
	# WaveController 自管波次，不走 base_level 的回合自动刷怪
	return {}


func get_objectives_text() -> Dictionary:
	# 不显示 BRIEFING 面板，直接进 PLAYING
	return {"victory": [], "defeat": []}


func _on_level_ready() -> void:
	# 1. 起手玩家队伍
	_spawn_initial_player_team()
	# 2. HUD
	_hud = _WaveBuffHudScene.instantiate()
	add_child(_hud)
	# 3. WaveController
	_wave_controller = _WaveControllerScript.new()
	add_child(_wave_controller)
	_wave_controller.setup(self, _hud, _build_learnable_skills())


func _spawn_initial_player_team() -> void:
	var li_chun := spawn_unit(_UD_LI_CHUN, _HERO_CELL, 0)
	li_chun.unit_color = _HERO_COLOR
	# 李春技能：优先用玩家在 prebattle_setup 选好的；为空时兜底起手两技
	var hero_skills: Array[SkillData] = Progress.get_battle_skill_resources(GameState.selected_level)
	if hero_skills.is_empty():
		hero_skills = [_SK_LC_RULE, _SK_LC_LINE_LOCK]
	set_unit_skills(li_chun, hero_skills)
	setup_unit_stats(li_chun, "李春", 130, 24, 100, 6, Enums.Element.NONE, 0, true)
	hero = li_chun

	var c_a := spawn_unit(_UD_CRAFTSMAN, _CRAFTSMAN_A_CELL, 0)
	c_a.unit_color = _CRAFTSMAN_COLOR
	set_unit_skills(c_a, [_SK_MALLET, _SK_GUARD])
	setup_unit_stats(c_a, "工匠", 110, 18, 90, 8)

	var c_b := spawn_unit(_UD_CRAFTSMAN, _CRAFTSMAN_B_CELL, 0)
	c_b.unit_color = _CRAFTSMAN_COLOR
	set_unit_skills(c_b, [_SK_MALLET, _SK_GUARD])
	setup_unit_stats(c_b, "工匠", 110, 18, 90, 8)

	var sw := spawn_unit(_UD_SURVEY, _SURVEY_CELL, 0)
	sw.unit_color = _SURVEY_COLOR
	set_unit_skills(sw, [_SK_STAFF, _SK_SURVEY])
	setup_unit_stats(sw, "测量工", 80, 12, 85, 9)


func _build_learnable_skills() -> Array[SkillData]:
	# 李春可学池（已学的 _SK_LC_RULE / _SK_LC_LINE_LOCK 不重复入池；buff 系统会再过滤）
	return [
		_SK_LC_INKLINE,
		_SK_LC_INK_SET,
		_SK_LC_DIVIDER,
		_SK_LC_LINK,
		_SK_LC_PILE_BIND,
		_SK_LC_GUIDE_FLOOD,
		_SK_LC_WEDGE_BANK,
		_SK_LC_CAST_STONE,
	]


# ─────────────────────────────────────────────
# 胜负
# ─────────────────────────────────────────────

func check_victory() -> bool:
	# 无尽
	return false


func check_defeat() -> String:
	if teams.is_empty():
		return ""
	var team = teams[0]
	if team.units.is_empty():
		return ""
	var any_alive := false
	for u in team.units:
		if is_instance_valid(u) and u is Unit and u.combat_stats != null and u.combat_stats.is_alive():
			any_alive = true
			break
	if not any_alive:
		var n: int = _wave_controller.get_wave_index() if _wave_controller else 0
		return "你坚守了 %d 波" % n
	return ""


# ─────────────────────────────────────────────
# 由 WaveController 调用
# ─────────────────────────────────────────────

func show_wave_banner(phase_name: String, category: String) -> void:
	if _phase_notification != null and _phase_notification.has_method("show_phase"):
		_phase_notification.show_phase(phase_name, category)
