class_name SkillExecutor
## 技能执行流水线。验证 → 收集目标 → 结算 → 应用额外效果。


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

	CombatLog.log_skill_use(stats.unit_name, skill.skill_name, unit.cell, cast_cell)

	var targets: Array = _collect_targets(skill, cast_cell, all_units, caster_faction, caster)
	CombatLog.log_targets(targets)

	stats.ap_current -= skill.ap_cost
	stats.skills_used += 1
	CombatLog.msg("  消耗 %dAP → 剩余 %dAP" % [skill.ap_cost, stats.ap_current])

	# 对每个目标结算伤害
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

	# 处理额外效果
	if skill.extra_effect_id != "":
		_apply_extra_effect(skill, unit, cast_cell, targets, all_units, caster_faction)

	result.success = true
	return result


# ─────────────────────────────────────────────
# 额外效果处理
# ─────────────────────────────────────────────

static func _apply_extra_effect(
	skill: SkillData,
	caster: Unit,
	cast_cell: Vector2i,
	targets: Array,
	all_units: Array,
	caster_faction: String
) -> void:
	match skill.extra_effect_id:
		"knockback_1":
			_effect_knockback(caster, targets, 1)
		"pull_1":
			_effect_pull(caster, targets, 1)
		"guarded_cover":
			_effect_apply_status(targets, "guarded_cover", skill.duration_turns, 0, caster.combat_stats.unit_name)
		"hindered_cross":
			_effect_aoe_status(cast_cell, all_units, caster_faction, "hindered_step", 2, caster.combat_stats.unit_name)
		"read_water":
			_effect_read_water(cast_cell, all_units, caster_faction, caster.combat_stats.unit_name)
		"complete_survey":
			CombatLog.msg("  额外效果: 踏勘量址 → 完成勘测点 (预留)")
		_:
			CombatLog.msg("  额外效果: 未知 effect_id '%s'" % skill.extra_effect_id)


## 击退：将每个目标沿施法者→目标方向推开 distance 格。
static func _effect_knockback(caster: Unit, targets: Array, distance: int) -> void:
	for t in targets:
		var tu := t as Unit
		if tu == null or tu.combat_stats == null:
			continue
		var dir := _get_direction(caster.cell, tu.cell)
		if dir == Vector2i.ZERO:
			continue
		var from := tu.cell
		var to := _force_move_cell(tu, dir, distance)
		CombatLog.msg("  额外效果: 击退%d格 (%s 从%s→%s)" % [distance, tu.combat_stats.unit_name, from, to])
		# 击退时检查剖隙状态
		_check_open_fissure(tu, caster)


## 拖拽：将每个目标沿目标→施法者方向拉近 distance 格。
static func _effect_pull(caster: Unit, targets: Array, distance: int) -> void:
	for t in targets:
		var tu := t as Unit
		if tu == null or tu.combat_stats == null:
			continue
		var dir := _get_direction(tu.cell, caster.cell)
		if dir == Vector2i.ZERO:
			continue
		var from := tu.cell
		var to := _force_move_cell(tu, dir, distance)
		CombatLog.msg("  额外效果: 拖拽%d格 (%s 从%s→%s)" % [distance, tu.combat_stats.unit_name, from, to])
		_check_open_fissure(tu, caster)


## 给目标列表中的每个单位施加状态。
static func _effect_apply_status(targets: Array, status_id: String, duration: int, source_atk: float, _caster_name: String) -> void:
	var names: Array[String] = []
	for t in targets:
		var tu := t as Unit
		if tu == null or tu.combat_stats == null:
			continue
		var si := CombatResolver.StatusInstance.new()
		si.status_id = status_id
		si.remaining_turns = duration
		si.source_base_atk = source_atk
		si.trigger_once = (status_id == "guarded_cover" or status_id == "brittle")
		tu.combat_stats.statuses.append(si)
		names.append(tu.combat_stats.unit_name)
	if names.size() > 0:
		CombatLog.msg("  额外效果: 赋予【%s】%d回合 (目标: %s)" % [status_id, duration, ", ".join(names)])


## 对释放点十字范围内的敌方单位施加状态（如迟滞）。
static func _effect_aoe_status(cast_cell: Vector2i, all_units: Array, caster_faction: String, status_id: String, duration: int, _caster_name: String) -> void:
	var cross_cells: Dictionary = {}
	for offset in OffsetPresets.cross(1):
		cross_cells[cast_cell + offset] = true

	var names: Array[String] = []
	for u in all_units:
		var tu := u as Unit
		if tu == null or tu.combat_stats == null:
			continue
		if not cross_cells.has(tu.cell):
			continue
		if tu.faction == caster_faction:
			continue
		var si := CombatResolver.StatusInstance.new()
		si.status_id = status_id
		si.remaining_turns = duration
		tu.combat_stats.statuses.append(si)
		names.append(tu.combat_stats.unit_name)
	if names.size() > 0:
		CombatLog.msg("  额外效果: 十字范围施加【%s】%d回合 (命中: %s)" % [status_id, duration, ", ".join(names)])
	else:
		CombatLog.msg("  额外效果: 十字范围施加【%s】→ 范围内无敌方单位" % status_id)


## 相水定址：给释放点十字范围内的友方添加稳步。
static func _effect_read_water(cast_cell: Vector2i, all_units: Array, caster_faction: String, _caster_name: String) -> void:
	var cross_cells: Dictionary = {}
	for offset in OffsetPresets.cross(1):
		cross_cells[cast_cell + offset] = true

	var names: Array[String] = []
	for u in all_units:
		var tu := u as Unit
		if tu == null or tu.combat_stats == null:
			continue
		if not cross_cells.has(tu.cell):
			continue
		if tu.faction != caster_faction:
			continue
		var si := CombatResolver.StatusInstance.new()
		si.status_id = "steady_step"
		si.remaining_turns = 1
		tu.combat_stats.statuses.append(si)
		names.append(tu.combat_stats.unit_name)
	if names.size() > 0:
		CombatLog.msg("  额外效果: 相水定址 → 赋予【稳步】1回合 (目标: %s)" % ", ".join(names))
	CombatLog.msg("  额外效果: 相水定址 → 显示危险地格2回合 (预留)")


## 击退/拖拽时检查剖隙状态，触发额外伤害。
static func _check_open_fissure(target: Unit, _attacker: Unit) -> void:
	for s in target.combat_stats.statuses:
		if s.status_id == "open_fissure" and not s.triggered:
			var bonus := roundi(s.source_base_atk * 0.50)
			target.combat_stats.current_hp = maxi(target.combat_stats.current_hp - bonus, 0)
			s.triggered = true
			CombatLog.msg("  击退触发【剖隙】: %s 额外受到 %d 伤害 (施术者ATK×0.50)" % [target.combat_stats.unit_name, bonus])


## 计算从 from 到 to 的主方向（等距4方向之一）。
static func _get_direction(from: Vector2i, to: Vector2i) -> Vector2i:
	var diff := to - from
	if diff == Vector2i.ZERO:
		return Vector2i.ZERO
	# 取绝对值更大的轴
	if absi(diff.x) >= absi(diff.y):
		return Vector2i(signi(diff.x), 0)
	else:
		return Vector2i(0, signi(diff.y))


## 强制移动单位（击退/拖拽）。返回最终位置。
## 简化实现：只检查目标格是否被其他单位占据，不检查地形通行性（后续可扩展）。
static func _force_move_cell(target: Unit, direction: Vector2i, distance: int) -> Vector2i:
	var current := target.cell
	for i in range(distance):
		var next := current + direction
		# TODO: 检查地形通行性（需要 movement_manager 引用）
		current = next
	target.cell = current
	# 更新视觉位置（需要 tilemap，通过 movement_manager 间接获取）
	if target.movement_manager and target.movement_manager.has_method("has_tile"):
		# 简化：直接设置位置，不做动画
		var tm: TileMapLayer = null
		if target.movement_manager.movement_tilemaps.size() > 0:
			tm = target.movement_manager.movement_tilemaps[0]
		if tm:
			target.position = tm.map_to_local(current)
	return current


# ─────────────────────────────────────────────
# 目标收集
# ─────────────────────────────────────────────

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
