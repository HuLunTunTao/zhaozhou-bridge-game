extends BaseLevel
## 第二关《弧拱定式》

# ── 预加载技能 ──
var _sk_rule_strike: SkillData = preload("res://data/skills/lc_rule_strike.tres")
var _sk_wedge: SkillData = preload("res://data/skills/lc_wedge_bank_probe.tres")
var _sk_stone: SkillData = preload("res://data/skills/lc_cast_stone_arrest_flow.tres")
var _sk_pile_bind: SkillData = preload("res://data/skills/lc_pile_bind_wave.tres")
var _sk_staff: SkillData = preload("res://data/skills/sw_staff_end_strike.tres")
var _sk_survey: SkillData = preload("res://data/skills/sw_field_measure_site.tres")
var _sk_mallet: SkillData = preload("res://data/skills/cg_mallet_strike.tres")
var _sk_guard: SkillData = preload("res://data/skills/cg_guard_the_works.tres")
var _sk_lunge: SkillData = preload("res://data/skills/dc_hidden_current_lunge.tres")
var _sk_pull: SkillData = preload("res://data/skills/wp_spiral_pull.tres")
var _sk_crush: SkillData = preload("res://data/skills/bmw_crumbling_bank_crush.tres")
var _sk_timber: SkillData = preload("res://data/skills/dlp_drifting_timber_crash.tres")

# ── 预加载敌方单位数据 ──
var _ud_dark_current: UnitData = preload("res://data/units/dark_current.tres")
var _ud_whirl_pool: UnitData = preload("res://data/units/whirl_pool.tres")
var _ud_mud_wraith: UnitData = preload("res://data/units/bank_mud_wraith.tres")
var _ud_drift_log: UnitData = preload("res://data/units/drift_log_pack.tres")

# ── 敌方队伍索引 ──
const ENEMY_TEAM := 1

# ── 敌方颜色 ──
const COLOR_DARK_CURRENT := Color(0.3, 0.4, 0.9)
const COLOR_WHIRL_POOL := Color(0.6, 0.3, 0.9)
const COLOR_MUD_WRAITH := Color(0.7, 0.5, 0.25)
const COLOR_DRIFT_LOG := Color(0.5, 0.65, 0.2)

# ── 单位引用 ──
var _li_chun: Node2D


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/Player"
	return [
		{
			"name": "玩家",
			"faction": "好人",
			"controller": "player",
			"units": [_li_chun],
		},
		{
			"name": "敌方",
			"faction": "坏人",
			"controller": "ai",
			"units": [],
		},
	]


func get_wave_config() -> Dictionary:
	return {
		1: [
			{"unit_data": _ud_mud_wraith, "cell": Vector2i(6, -3), "team_index": ENEMY_TEAM,
			 "skills": [_sk_crush], "color": COLOR_MUD_WRAITH},
		],
		2: [
			{"unit_data": _ud_dark_current, "cell": Vector2i(8, -4), "team_index": ENEMY_TEAM,
			 "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT},
			{"unit_data": _ud_dark_current, "cell": Vector2i(10, -3), "team_index": ENEMY_TEAM,
			 "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT},
		],
		4: [
			{"unit_data": _ud_whirl_pool, "cell": Vector2i(9, -2), "team_index": ENEMY_TEAM,
			 "skills": [_sk_pull], "color": COLOR_WHIRL_POOL},
			{"unit_data": _ud_drift_log, "cell": Vector2i(7, -6), "team_index": ENEMY_TEAM,
			 "skills": [_sk_timber], "color": COLOR_DRIFT_LOG},
		],
		6: [
			{"unit_data": _ud_mud_wraith, "cell": Vector2i(5, -3), "team_index": ENEMY_TEAM,
			 "skills": [_sk_crush], "color": COLOR_MUD_WRAITH},
			{"unit_data": _ud_dark_current, "cell": Vector2i(11, -4), "team_index": ENEMY_TEAM,
			 "skills": [_sk_lunge], "color": COLOR_DARK_CURRENT},
		],
	}


func get_objectives_text() -> Dictionary:
	return {
		"victory": [
			"- 击败所有敌人",
		],
		"defeat": [
			"- 李春死亡",
			"- 超过第 12 回合",
		],
	}


func check_victory() -> bool:
	if teams.size() <= ENEMY_TEAM:
		return false
	var enemy_team: TeamData = teams[ENEMY_TEAM]
	for unit: Node2D in enemy_team.units:
		if is_instance_valid(unit) and unit is Unit:
			if (unit as Unit).combat_stats and (unit as Unit).combat_stats.is_alive():
				return false
	return round_number > 1


func check_defeat() -> String:
	if not is_instance_valid(_li_chun):
		return "李春阵亡"
	var lc := _li_chun as Unit
	if lc.combat_stats and not lc.combat_stats.is_alive():
		return "李春阵亡"
	if round_number > 12:
		return "超过第 12 回合"
	return ""


func _on_level_ready() -> void:
	# ── 李春 ──
	set_unit_skills(_li_chun as Unit, [_sk_rule_strike, _sk_wedge, _sk_stone, _sk_pile_bind])
	setup_unit_stats(_li_chun as Unit, "李春", 130, 24, 100, 8, Enums.Element.NONE, 0, true)


func _process_wave(round_num: int) -> void:
	var waves := get_wave_config()
	if not waves.has(round_num):
		return
	for entry: Dictionary in waves[round_num]:
		var unit := spawn_unit(entry["unit_data"], entry["cell"], entry["team_index"])
		if entry.has("skills"):
			set_unit_skills(unit, entry["skills"])
		if entry.has("color"):
			unit.unit_color = entry["color"]
