class_name BattleContext
## 战场快照构建器：把当前局面转成 JSON 友好的 Dictionary，喂给 LLM 做决策辅助。
##
## 设计原则：
##   - 只读取当前状态，不维护历史
##   - 每次调用都是全量快照（无累积上下文）
##   - 全知视角（含敌方 HP/AP/技能）
##   - 字段中文化，便于 LLM 直接理解，无需额外 schema 描述
##
## 用法：
##   var snapshot := BattleContext.build_snapshot(level)
##   var json := JSON.stringify(snapshot)

const _ELEMENT_NAMES := ["无", "金", "木", "水", "火", "土"]
const _SKILL_TYPE_NAMES := ["攻击", "辅助", "交互", "辅助交互"]


## 构建当前战场快照。level 必须是 BaseLevel 实例（鸭子类型，不强校验类）。
static func build_snapshot(level: Node) -> Dictionary:
	var level_name: String = ""
	if Engine.has_singleton("GameState"):
		# autoload 不能用 has_singleton 判断；改用 Engine 的 main loop 全局变量
		pass
	# GameState 是 autoload，直接访问
	level_name = GameState.selected_level if GameState.selected_level != "" else "未命名关卡"

	var snapshot := {
		"关卡": level_name,
		"回合": level.round_number,
		"当前行动队伍": _active_team_name(level),
		"本关目标": level.get_objectives_text(),
		"队伍": _build_teams(level),
	}
	return snapshot


static func _active_team_name(level: Node) -> String:
	if level.current_team_index < 0 or level.current_team_index >= level.teams.size():
		return ""
	return level.teams[level.current_team_index].team_name


static func _build_teams(level: Node) -> Array:
	var out: Array = []
	for team in level.teams:
		out.append({
			"名字": team.team_name,
			"控制方": "玩家" if team.controller == "player" else "AI",
			"单位": _build_units(team.units),
		})
	return out


static func _build_units(units: Array) -> Array:
	var out: Array = []
	for u in units:
		if u == null or not is_instance_valid(u):
			continue
		var stats: CombatStats = u.combat_stats
		if stats == null or not stats.is_alive():
			continue
		out.append({
			"名字": stats.unit_name,
			"坐标": [u.cell.x, u.cell.y],
			"HP": "%d/%d" % [stats.current_hp, stats.max_hp],
			"AP": "%d/%d" % [stats.ap_current, stats.ap_max],
			"当前属性": _format_element(stats.current_element, stats.current_element_amount),
			"固有属性": _format_element(stats.innate_element, stats.innate_element_amount),
			"本回合已行动": u.has_acted,
			"状态": _format_statuses(stats),
			"技能": _format_skills(u.unit_data, stats),
		})
	return out


static func _format_element(elem: int, amount: int) -> String:
	if elem == Enums.Element.NONE or amount <= 0:
		return "无"
	if elem < 0 or elem >= _ELEMENT_NAMES.size():
		return "未知×%d" % amount
	return "%s×%d" % [_ELEMENT_NAMES[elem], amount]


static func _format_statuses(stats: CombatStats) -> Array:
	var out: Array = []
	for s in stats.statuses:
		out.append("%s(剩%d回合)" % [s.status_id, s.remaining_turns])
	return out


static func _format_skills(data: UnitData, stats: CombatStats) -> Array:
	var out: Array = []
	if data == null:
		return out
	for skill in data.skills:
		if skill == null:
			continue
		var entry := {
			"名字": skill.skill_name,
			"类型": _skill_type_name(skill.skill_type),
			"AP消耗": skill.ap_cost,
			"伤害倍率": skill.damage_ratio,
			"属性": _ELEMENT_NAMES[skill.damage_element] if skill.damage_element >= 0 and skill.damage_element < _ELEMENT_NAMES.size() else "未知",
			"本回合可用": stats.can_use_skill(skill),
		}
		if not skill.description.is_empty():
			entry["描述"] = skill.description
		out.append(entry)
	return out


static func _skill_type_name(t: int) -> String:
	if t < 0 or t >= _SKILL_TYPE_NAMES.size():
		return "未知"
	return _SKILL_TYPE_NAMES[t]
