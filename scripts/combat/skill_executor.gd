class_name SkillExecutor
## 技能执行流水线。验证 → 收集目标 → 结算 → 应用结果。


## 执行结果。
class ExecuteResult:
	var success: bool = false
	var hit_results: Array = []    # Array[{unit: Node2D, hit: HitResult}]
	var error: String = ""


## 验证并执行技能。
## caster: 施法单位, skill: 技能, cast_cell: 释放点, all_units: 场上所有单位。
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

	# 1. 验证 AP
	if stats.ap_current < skill.ap_cost:
		result.error = "AP 不足"
		return result

	# 2. 验证次数
	if not stats.can_use_skill(skill):
		result.error = "技能次数已用尽"
		return result

	# 3. 收集目标
	var targets: Array = _collect_targets(skill, cast_cell, all_units, caster_faction, caster)

	# 4. 扣 AP + 计数
	stats.ap_current -= skill.ap_cost
	stats.skills_used += 1

	# 5. 对每个目标结算
	for target_unit: Node2D in targets:
		var tu := target_unit as Unit
		if tu == null or tu.combat_stats == null:
			continue
		if skill.damage_ratio > 0.0:
			var hit := CombatResolver.resolve_hit(stats, tu.combat_stats, skill)
			CombatResolver.apply_hit(tu.combat_stats, skill, hit)
			result.hit_results.append({"unit": target_unit, "hit": hit})
		else:
			# 非伤害技能（辅助/交互）仍做属性附着
			if skill.attach_amount > 0:
				ElementSystem.apply_skill_element(tu.combat_stats, skill.damage_element, skill.attach_amount)

	result.success = true
	return result


## 收集技能影响区域内的合法目标。
static func _collect_targets(
	skill: SkillData,
	cast_cell: Vector2i,
	all_units: Array,
	caster_faction: String,
	caster: Node2D
) -> Array:
	# 计算影响区域的绝对坐标
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
		# 按技能类型筛选阵营
		match skill.skill_type:
			Enums.SkillType.ATTACK:
				if u.faction == caster_faction:
					continue  # 不打友方
			Enums.SkillType.ASSIST:
				if u.faction != caster_faction:
					continue  # 不辅助敌方
				if u == caster:
					continue  # 不辅助自己（可选）
			_:
				pass  # INTERACT / ASSIST_INTERACT 不筛阵营
		targets.append(unit)

	return targets
