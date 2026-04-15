class_name CombatLog
## 战斗日志工具。所有战斗相关日志通过此类输出，统一格式，便于调试。
## 输出到 Godot 控制台（Output 面板）。

const TAG := "[战斗]"

static var enabled: bool = true


static func msg(text: String) -> void:
	if enabled:
		print("%s %s" % [TAG, text])


static func log_skill_use(caster_name: String, skill_name: String, caster_cell: Vector2i, cast_cell: Vector2i) -> void:
	msg("%s 在%s 释放【%s】→ 目标格%s" % [caster_name, caster_cell, skill_name, cast_cell])


static func log_targets(targets: Array) -> void:
	if not enabled:
		return
	if targets.is_empty():
		msg("  目标: 无")
		return
	for t in targets:
		var u := t as Unit
		if u and u.combat_stats:
			msg("  目标: %s 在%s (HP:%d/%d 属性:%s×%d)" % [
				u.combat_stats.unit_name, u.cell,
				u.combat_stats.current_hp, u.combat_stats.max_hp,
				_elem_name(u.combat_stats.current_element), u.combat_stats.current_element_amount,
			])


static func log_damage_calc(
	attacker_name: String, target_name: String,
	base_atk: int, damage_ratio: float, base_damage: float,
	phase_category: String, multiplier: float,
	bonus_damage: int, final_damage: int
) -> void:
	msg("  伤害计算: %s → %s" % [attacker_name, target_name])
	msg("    基础: %d × %.2f = %.1f" % [base_atk, damage_ratio, base_damage])
	msg("    化势: %s 倍率×%.2f" % [phase_category, multiplier])
	if bonus_damage > 0:
		msg("    附加伤害: +%d" % bonus_damage)
	msg("    最终伤害: %d" % final_damage)


static func log_element_change(unit_name: String, before_elem: int, before_amt: int, after_elem: int, after_amt: int) -> void:
	if before_elem == after_elem and before_amt == after_amt:
		return
	msg("  属性变化: %s %s×%d → %s×%d" % [
		unit_name,
		_elem_name(before_elem), before_amt,
		_elem_name(after_elem), after_amt,
	])


static func log_status_applied(target_name: String, status_id: String, duration: int) -> void:
	msg("  状态施加: %s 获得【%s】%d回合" % [target_name, status_id, duration])


static func log_dot(unit_name: String, status_id: String, damage: int) -> void:
	msg("  DoT: %s 受到【%s】%d伤害" % [unit_name, status_id, damage])


static func log_turn_start(team_name: String, unit_name: String, hp: int, ap: int) -> void:
	msg("回合开始: [%s] %s HP:%d AP:%d" % [team_name, unit_name, hp, ap])


static func log_unit_move(unit_name: String, from_cell: Vector2i, to_cell: Vector2i, ap_cost: int, ap_remaining: int) -> void:
	msg("%s 移动 %s → %s (消耗%dAP 剩余%dAP)" % [unit_name, from_cell, to_cell, ap_cost, ap_remaining])


static func log_defeat(attacker_name: String, target_name: String) -> void:
	msg("  击败: %s 被 %s 击退!" % [target_name, attacker_name])


static func _elem_name(elem: int) -> String:
	match elem:
		0: return "无"
		1: return "金"
		2: return "木"
		3: return "水"
		4: return "火"
		5: return "土"
	return "?"
