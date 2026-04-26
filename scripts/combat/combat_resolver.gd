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
	## 攻击前目标的附着属性（供 UI 显示化势前状态）。
	var pre_target_element: Enums.Element = Enums.Element.NONE
	var pre_target_amount: int = 0
	## 技能所带属性（供 UI 显示化势对比）。
	var skill_attach_element: Enums.Element = Enums.Element.NONE
	var skill_attach_amount: int = 0
	## 化势附加伤害（供 UI 显示）。
	var phase_bonus_damage: int = 0


static func resolve_hit(attacker: CombatStats, target: CombatStats, skill: SkillData, ratio_override: float = -1.0) -> HitResult:
	var result := HitResult.new()

	# 0. 记录攻击前状态供 UI 使用
	result.pre_target_element = target.current_element
	result.pre_target_amount = target.current_element_amount
	result.skill_attach_element = skill.damage_element
	result.skill_attach_amount = skill.attach_amount

	# 1. 决定本次结算使用的伤害倍率：
	#    - ratio_override 由 SkillExecutor 传入（中心/周围分倍率、命中数缩放等场合用）。
	#    - 否则：若 skill.conditional_ratio > 0 且 extra_effect_id 对应条件命中，改用 conditional_ratio。
	var ratio: float = skill.damage_ratio
	var conditional_used := false
	if ratio_override >= 0.0:
		ratio = ratio_override
	elif skill.conditional_ratio > 0.0:
		match skill.extra_effect_id:
			"cond_no_attached_bonus":
				if target.current_element_amount == 0:
					ratio = skill.conditional_ratio
					conditional_used = true
			"low_hp_bonus":
				if target.max_hp > 0 and float(target.current_hp) / float(target.max_hp) < 0.30:
					ratio = skill.conditional_ratio
					conditional_used = true
			"cond_attached_earth_knockback":
				if target.current_element == Enums.Element.EARTH:
					ratio = skill.conditional_ratio
					conditional_used = true
	if conditional_used:
		CombatLog.msg("    技能条件命中【%s】: 倍率改为 %.2f" % [skill.extra_effect_id, ratio])
	var base_damage: float = attacker.base_atk * ratio

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

	# 3.5 技能条件性 multiplier（叠加在最终 multiplier 上，与化势/状态共同作用）
	match skill.extra_effect_id:
		"cond_has_attached_aoe":
			if target.current_element_amount > 0:
				multiplier *= 1.20
				CombatLog.msg("    技能条件【已附着AOE】: 倍率×1.20")

	# 4. 攻击方状态修正
	for s in attacker.statuses:
		match s.status_id:
			"weakened":
				multiplier *= 0.8
				CombatLog.msg("    攻击方状态【攻衰】: 倍率×0.8")
			"rule_single_boost":
				multiplier *= 1.30
				CombatLog.msg("    攻击方状态【督令·单体】: 倍率×1.30")
			"rule_group_boost":
				multiplier *= 1.10
				CombatLog.msg("    攻击方状态【督令·群体】: 倍率×1.10")

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

	# 6.5 护持减伤（固定值减伤，在倍率计算之后）
	for s in target.statuses:
		if s.status_id == "guarded_cover" and not s.triggered:
			var before := final_damage
			final_damage = maxi(final_damage - 12, 0)
			s.triggered = true
			CombatLog.msg("    状态【护持】: 减伤12 (%s 伤害 %d → %d)" % [target.unit_name, before, final_damage])

	# 7. 化势附加伤害
	var bonus := 0
	if phase.phase_data != null:
		bonus = _calc_bonus_damage(phase.phase_data, attacker, target)
		final_damage += bonus
	result.phase_bonus_damage = bonus

	# 8. 入站伤害乘子（关卡机制：免伤 / 易伤）。叠在所有计算之后，对总伤生效。
	if not is_equal_approx(target.incoming_damage_factor, 1.0):
		var before_factor := final_damage
		final_damage = roundi(final_damage * target.incoming_damage_factor)
		CombatLog.msg("    入站伤害乘子: ×%.2f (%s 伤害 %d → %d)" % [
			target.incoming_damage_factor, target.unit_name, before_factor, final_damage,
		])

	result.damage = maxi(final_damage, 0)
	result.is_kill = target.current_hp - result.damage <= 0

	# 日志: 伤害计算过程（使用最终采用的 ratio，不再是 skill.damage_ratio）
	CombatLog.log_damage_calc(
		attacker.unit_name, target.unit_name,
		attacker.base_atk, ratio, base_damage,
		phase_name, multiplier, bonus, result.damage
	)

	if result.is_kill:
		CombatLog.log_defeat(attacker.unit_name, target.unit_name)

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
