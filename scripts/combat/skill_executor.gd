class_name SkillExecutor
## 技能执行流水线。验证 → 收集目标 → 结算 → 应用结果。


class ExecuteResult:
	var success: bool = false
	var hit_results: Array = []
	var error: String = ""


static func execute(
	caster: Node2D,
	skill: SkillData,
	cast_cell: Vector2i,
	all_units: Array,
	caster_faction: String
) -> ExecuteResult:
	var result := ExecuteResult.new()
	var unit := caster as Unit
	if unit == null or unit.combat_stats == null:
		result.error = "无效的施法单位"
		return result

	var stats := unit.combat_stats

	if stats.ap_current < skill.ap_cost:
		result.error = "AP 不足"
		return result

	if not stats.can_use_skill(skill):
		result.error = "技能次数已用尽"
		return result

	# 日志: 技能释放
	CombatLog.log_skill_use(stats.unit_name, skill.skill_name, unit.cell, cast_cell)

	# 收集目标
	var targets: Array = _collect_targets(skill, cast_cell, all_units, caster_faction, caster)
	CombatLog.log_targets(targets)

	# 扣 AP + 计数
	stats.ap_current -= skill.ap_cost
	stats.skills_used += 1
	CombatLog.msg("  消耗 %dAP → 剩余 %dAP" % [skill.ap_cost, stats.ap_current])

	# 对每个目标结算
	for target_unit: Node2D in targets:
		var tu := target_unit as Unit
		if tu == null or tu.combat_stats == null:
			continue
		if skill.damage_ratio > 0.0:
			var hit := CombatResolver.resolve_hit(stats, tu.combat_stats, skill)
			CombatResolver.apply_hit(tu.combat_stats, skill, hit)
			result.hit_results.append({"unit": target_unit, "hit": hit})
			CombatLog.msg("  结果: %s HP %d → %d" % [
				tu.combat_stats.unit_name,
				tu.combat_stats.current_hp + hit.damage,
				tu.combat_stats.current_hp,
			])
		else:
			if skill.attach_amount > 0:
				ElementSystem.apply_skill_element(tu.combat_stats, skill.damage_element, skill.attach_amount)
				CombatLog.msg("  辅助/交互: 对 %s 附着属性" % tu.combat_stats.unit_name)

	result.success = true
	return result


static func _collect_targets(
	skill: SkillData,
	cast_cell: Vector2i,
	all_units: Array,
	caster_faction: String,
	caster: Node2D
) -> Array:
	var effect_cells: Dictionary = {}
	for offset in skill.effect_offsets:
		effect_cells[cast_cell + offset] = true

	var targets: Array = []
	for unit: Node2D in all_units:
		if not unit is Unit:
			continue
		var u := unit as Unit
		if u.combat_stats == null:
			continue
		if not effect_cells.has(u.cell):
			continue
		match skill.skill_type:
			Enums.SkillType.ATTACK:
				if u.faction == caster_faction:
					continue
			Enums.SkillType.ASSIST:
				if u.faction != caster_faction:
					continue
				if u == caster:
					continue
			_:
				pass
		targets.append(unit)

	return targets
