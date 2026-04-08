class_name CombatResolver
## 伤害计算纯函数。无状态，返回 HitResult 结构体。


## 单次命中的结算结果。
class HitResult:
	var damage: int = 0
	var phase_result: PhaseTable.PhaseResult = null
	var element_applied: bool = false
	var statuses_to_apply: Array = []
	var is_kill: bool = false
	var non_element_bonus: bool = false


static func resolve_hit(attacker: CombatStats, target: CombatStats, skill: SkillData) -> HitResult:
	var result := HitResult.new()

	# 1. 基础伤害
	var base_damage: float = attacker.base_atk * skill.damage_ratio

	# 2. 化势判定
	var phase := PhaseTable.lookup(skill.damage_element, target.current_element)
	result.phase_result = phase
	var multiplier: float = phase.multiplier
	var phase_name := "普通"
	if phase.phase_data:
		phase_name = phase.phase_data.phase_name
	elif phase.category == Enums.PhaseCategory.ADVERSE:
		phase_name = "逆势"
	elif phase.category == Enums.PhaseCategory.SAME:
		phase_name = "同气"

	# 3. 无属性→无属性加成
	if skill.damage_element == Enums.Element.NONE and target.current_element == Enums.Element.NONE:
		multiplier = 1.15
		result.non_element_bonus = true
		phase_name = "无属性加成"

	# 4. 攻击方状态修正
	for s in attacker.statuses:
		match s.status_id:
			"weakened":
				multiplier *= 0.8
				CombatLog.msg("    攻击方状态【攻衰】: 倍率×0.8")

	# 5. 目标状态修正
	for s in target.statuses:
		match s.status_id:
			"brittle":
				if not s.triggered:
					multiplier *= 1.2
					s.triggered = true
					CombatLog.msg("    目标状态【脆裂】: 倍率×1.2 (已触发)")

	# 6. 最终伤害
	var final_damage: int = roundi(base_damage * multiplier)

	# 7. 化势附加伤害
	var bonus := 0
	if phase.phase_data != null:
		bonus = _calc_bonus_damage(phase.phase_data, attacker, target)
		final_damage += bonus

	result.damage = maxi(final_damage, 0)
	result.is_kill = target.current_hp - result.damage <= 0

	# 日志: 伤害计算过程
	CombatLog.log_damage_calc(
		attacker.unit_name, target.unit_name,
		attacker.base_atk, skill.damage_ratio, base_damage,
		phase_name, multiplier, bonus, result.damage
	)

	if result.is_kill:
		CombatLog.log_kill(attacker.unit_name, target.unit_name)

	# 8. 化势施加状态
	if phase.phase_data != null and phase.phase_data.apply_status_id != "":
		result.statuses_to_apply.append({
			"id": phase.phase_data.apply_status_id,
			"duration": phase.phase_data.status_duration,
			"source_atk": attacker.base_atk,
		})

	# 9. 标记是否会发生属性变化
	result.element_applied = (
		skill.attach_amount > 0
		and skill.damage_element != Enums.Element.NONE
		and skill.damage_element != target.current_element
	)

	return result


static func apply_hit(target: CombatStats, skill: SkillData, hit: HitResult) -> void:
	# 记录属性变化前状态
	var before_elem: int = target.current_element
	var before_amt: int = target.current_element_amount

	# 扣血
	target.current_hp = maxi(target.current_hp - hit.damage, 0)

	# 属性对消/附着
	if skill.attach_amount > 0:
		ElementSystem.apply_skill_element(target, skill.damage_element, skill.attach_amount)

	# 化势额外属性消耗
	if hit.phase_result and hit.phase_result.phase_data:
		var extra := hit.phase_result.phase_data.extra_element_consume
		if extra > 0 and target.current_element_amount > 0:
			target.current_element_amount = maxi(target.current_element_amount - extra, 0)

	# 日志: 属性变化
	CombatLog.log_element_change(target.unit_name, before_elem, before_amt, target.current_element, target.current_element_amount)

	# 施加状态
	for s_info in hit.statuses_to_apply:
		var si := StatusInstance.new()
		si.status_id = s_info["id"]
		si.remaining_turns = s_info["duration"]
		si.source_base_atk = s_info["source_atk"]
		target.statuses.append(si)
		CombatLog.log_status_applied(target.unit_name, si.status_id, si.remaining_turns)


static func _calc_bonus_damage(pd: PhaseData, attacker: CombatStats, target: CombatStats) -> int:
	if pd.bonus_damage_type == "":
		return 0
	var bonus: float = 0.0
	match pd.bonus_damage_type:
		"target_max_hp_ratio":
			bonus = target.max_hp * pd.bonus_damage_value
	if pd.bonus_damage_cap != "":
		var cap := _eval_cap(pd.bonus_damage_cap, attacker)
		if cap > 0:
			bonus = minf(bonus, cap)
	return roundi(bonus)


static func _eval_cap(expr: String, attacker: CombatStats) -> float:
	if expr.begins_with("attacker_base_atk"):
		var parts := expr.split("*")
		if parts.size() == 2:
			return attacker.base_atk * parts[1].strip_edges().to_float()
	return 0.0


class StatusInstance:
	var status_id: String
	var remaining_turns: int
	var source_base_atk: float = 0.0
	var trigger_once: bool = false
	var triggered: bool = false
