class_name SkillExecutor
## 技能执行流水线。验证 → 收集目标 → 结算 → 应用额外效果。

const STATUS_KNOCKBACK_IMMUNE := "knockback_immune"


class ExecuteResult:
	var success: bool = false
	var hit_results: Array = []
	var targets: Array = []
	var error: String = ""


class DisplacementResult:
	var from_cell: Vector2i
	var to_cell: Vector2i
	var immune: bool = false

	func _init(p_from_cell: Vector2i, p_to_cell: Vector2i, p_immune: bool = false) -> void:
		from_cell = p_from_cell
		to_cell = p_to_cell
		immune = p_immune


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

	if not stats.has_infinite_actions() and stats.ap_current < skill.ap_cost:
		result.error = "AP 不足"
		return result

	if not stats.can_use_skill(skill):
		result.error = "技能次数已用尽"
		return result

	CombatLog.log_skill_use(stats.unit_name, skill.skill_name, unit.cell, cast_cell)

	var targets: Array = _collect_targets(skill, cast_cell, all_units, caster_faction, caster)
	result.targets = targets
	CombatLog.log_targets(targets)

	if stats.has_infinite_actions():
		CombatLog.msg("  测试无限AP: 不消耗AP，不计入技能次数")
	else:
		stats.ap_current -= skill.ap_cost
		stats.skills_used += 1
		CombatLog.msg("  消耗 %dAP → 剩余 %dAP" % [skill.ap_cost, stats.ap_current])

	# 命中前预扫描：统计有效目标数，决定全局倍率乘数（环形命中数缩放、连击门槛等）
	var damage_targets: Array = []
	for target_unit: Node2D in targets:
		var tu := target_unit as Unit
		if tu == null or tu.combat_stats == null:
			continue
		if skill.damage_ratio > 0.0:
			damage_targets.append(target_unit)

	var hit_count: int = damage_targets.size()
	var global_ratio_mult: float = 1.0
	match skill.extra_effect_id:
		"ring_per_hit_scale":
			# 围尺八方：每命中 +0.1，最多 ×1.4
			global_ratio_mult = minf(1.0 + 0.1 * float(hit_count), 1.4)
			if global_ratio_mult > 1.0 and hit_count > 0:
				CombatLog.msg("  环形命中数缩放: %d 命中 → 倍率×%.2f" % [hit_count, global_ratio_mult])
		"ap_refund_and_count_bonus":
			# 连楔并拱：≥3 命中 → 全员 ×1.2
			if hit_count >= 3:
				global_ratio_mult = 1.2
				CombatLog.msg("  连击加成: %d 命中 → 倍率×1.20" % hit_count)

	# 对每个目标结算伤害
	for target_unit: Node2D in targets:
		var tu := target_unit as Unit
		if tu == null or tu.combat_stats == null:
			continue
		if skill.damage_ratio > 0.0:
			# 计算本目标使用的倍率：考虑中心/周围分倍率 + 全局乘数
			var per_ratio: float = -1.0
			if skill.surround_ratio >= 0.0 and tu.cell != cast_cell:
				per_ratio = skill.surround_ratio
			if global_ratio_mult != 1.0:
				var base_for_mult: float = (skill.damage_ratio if per_ratio < 0.0 else per_ratio)
				per_ratio = base_for_mult * global_ratio_mult
			var hit := CombatResolver.resolve_hit(stats, tu.combat_stats, skill, per_ratio)
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
		_apply_extra_effect(skill, unit, cast_cell, targets, all_units, caster_faction, result.hit_results, hit_count)

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
	caster_faction: String,
	hit_results: Array = [],
	hit_count: int = 0
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
		"line_bind":
			_effect_first_target_status(targets, "overgrow_bind", skill.duration_turns, caster.combat_stats.unit_name)
		"pull_first":
			_effect_pull_first(caster, targets, 1)
		"pull_all":
			_effect_pull(caster, targets, 1)
		"brittle_all":
			_effect_apply_status(targets, "brittle", skill.duration_turns, 0, caster.combat_stats.unit_name)
		"read_water":
			_effect_read_water(cast_cell, all_units, caster_faction, caster.combat_stats.unit_name)
		"stage_balance_arch", "stage_open_arch":
			CombatLog.msg("  额外效果: 关卡机制技能命中")
		"complete_survey":
			CombatLog.msg("  额外效果: 踏勘量址 → 完成勘测点 (预留)")
		"take_parameter", "confirm_parameter", "ink_set_arch":
			CombatLog.msg("  额外效果: 关卡交互 '%s' (由关卡脚本处理)" % skill.extra_effect_id)
		"line_piercing":
			# 穿刺已在 _collect_targets 内通过 get_line_piercing_cells 扩大目标；此处无须重复处理
			pass
		# ── 李春技能新条件 ──────────────────────────────
		"cond_attached_earth_knockback":
			# 投石遏流：击退 1 格（条件加伤已在 resolver 处理）
			_effect_knockback(caster, targets, 1)
		"knockback_1_wall_bonus":
			# 分波束桩：击退 1 格；推不动则追加 30% 伤害
			_effect_knockback_with_block_bonus(caster, hit_results, 1, 0.30)
		"knockback_2_water_bonus":
			# 顺水推舟：击退 2 格；推到水格追加 50% 伤害
			_effect_knockback_with_water_bonus(caster, hit_results, 2, 0.50)
		"ap_refund_and_count_bonus":
			# 连楔并拱：每命中回 5 AP（最多 25）
			var refund: int = mini(hit_count * 5, 25)
			caster.combat_stats.ap_current = mini(caster.combat_stats.ap_max, caster.combat_stats.ap_current + refund)
			CombatLog.msg("  额外效果: 连楔回 %d AP（命中 %d 人）" % [refund, hit_count])
		"ring_per_hit_scale", "cond_no_attached_bonus", "cond_has_attached_aoe", "low_hp_bonus", "non_element_bonus":
			# 这些条件 / 缩放在 resolver 与执行循环里已经处理，此处无额外位移效果
			pass
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
		var move := _apply_displacement(tu, dir, distance, "击退")
		if move.immune:
			continue
		# 击退时检查剖隙状态
		_check_open_fissure(tu, caster)


## 击退 N 格；若推不动（cell 没变），对该目标按本次原伤害的 bonus_ratio 追加伤害。
static func _effect_knockback_with_block_bonus(caster: Unit, hit_results: Array, distance: int, bonus_ratio: float) -> void:
	for entry in hit_results:
		var tu: Unit = entry.get("unit") as Unit
		var hit = entry.get("hit")
		if tu == null or tu.combat_stats == null or hit == null:
			continue
		var dir := _get_direction(caster.cell, tu.cell)
		if dir == Vector2i.ZERO:
			continue
		var move := _apply_displacement(tu, dir, distance, "击退")
		if move.immune:
			continue
		_check_open_fissure(tu, caster)
		if move.to_cell == move.from_cell:
			# 推不动 → 追加伤害
			var bonus_dmg: int = roundi(hit.damage * bonus_ratio)
			if bonus_dmg > 0:
				tu.combat_stats.current_hp = maxi(tu.combat_stats.current_hp - bonus_dmg, 0)
				CombatLog.msg("  额外效果: 推不动 → %s 追加 %d 伤害" % [tu.combat_stats.unit_name, bonus_dmg])


## 击退 N 格；若被推到水类地块，对该目标按原伤害的 bonus_ratio 追加伤害。
static func _effect_knockback_with_water_bonus(caster: Unit, hit_results: Array, distance: int, bonus_ratio: float) -> void:
	for entry in hit_results:
		var tu: Unit = entry.get("unit") as Unit
		var hit = entry.get("hit")
		if tu == null or tu.combat_stats == null or hit == null:
			continue
		var dir := _get_direction(caster.cell, tu.cell)
		if dir == Vector2i.ZERO:
			continue
		var move := _apply_displacement(tu, dir, distance, "击退")
		if move.immune:
			continue
		_check_open_fissure(tu, caster)
		if tu.movement_manager and tu.movement_manager.has_method("is_water_cell") and tu.movement_manager.is_water_cell(move.to_cell):
			var bonus_dmg: int = roundi(hit.damage * bonus_ratio)
			if bonus_dmg > 0:
				tu.combat_stats.current_hp = maxi(tu.combat_stats.current_hp - bonus_dmg, 0)
				CombatLog.msg("  额外效果: 推入水格 → %s 追加 %d 伤害" % [tu.combat_stats.unit_name, bonus_dmg])


## 拖拽：将每个目标沿目标→施法者方向拉近 distance 格。
static func _effect_pull(caster: Unit, targets: Array, distance: int) -> void:
	for t in targets:
		var tu := t as Unit
		if tu == null or tu.combat_stats == null:
			continue
		var dir := _get_direction(tu.cell, caster.cell)
		if dir == Vector2i.ZERO:
			continue
		var move := _apply_displacement(tu, dir, distance, "拖拽")
		if move.immune:
			continue
		_check_open_fissure(tu, caster)


## 首目标拖拽：仅对 targets[0] 沿目标→施法者方向拉近 distance 格。
static func _effect_pull_first(caster: Unit, targets: Array, distance: int) -> void:
	if targets.is_empty():
		return
	var first := targets[0] as Unit
	if first == null or first.combat_stats == null:
		return
	var dir := _get_direction(first.cell, caster.cell)
	if dir == Vector2i.ZERO:
		return
	var move := _apply_displacement(first, dir, distance, "首目标拖拽", "拖拽")
	if move.immune:
		return
	_check_open_fissure(first, caster)


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


static func _effect_first_target_status(targets: Array, status_id: String, duration: int, _caster_name: String) -> void:
	if targets.is_empty():
		return
	var first := targets[0] as Unit
	if first == null or first.combat_stats == null:
		return
	var si := CombatResolver.StatusInstance.new()
	si.status_id = status_id
	si.remaining_turns = duration
	first.combat_stats.statuses.append(si)
	CombatLog.msg("  额外效果: %s 获得【%s】%d回合" % [first.combat_stats.unit_name, status_id, duration])


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


static func _has_displacement_immunity(target: Unit) -> bool:
	if target == null or target.combat_stats == null:
		return false
	return target.combat_stats.has_status(STATUS_KNOCKBACK_IMMUNE)


static func _apply_displacement(target: Unit, direction: Vector2i, distance: int, action_name: String, immune_action_name: String = "") -> DisplacementResult:
	var move := _try_move_cell(target, direction, distance)
	var immune_label := immune_action_name if immune_action_name != "" else action_name
	if move.immune:
		CombatLog.msg("  额外效果: %s 拥有【抗击退】，免疫%s%d格" % [target.combat_stats.unit_name, immune_label, distance])
	else:
		CombatLog.msg("  额外效果: %s%d格 (%s 从%s→%s)" % [action_name, distance, target.combat_stats.unit_name, move.from_cell, move.to_cell])
	return move


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
	return _try_move_cell(target, direction, distance).to_cell


static func _try_move_cell(target: Unit, direction: Vector2i, distance: int) -> DisplacementResult:
	var from := target.cell
	var current := from
	if _has_displacement_immunity(target):
		return DisplacementResult.new(from, from, true)
	for i in range(distance):
		var next := current + direction
		# 检查地形通行性
		if target.movement_manager:
			if target.movement_manager.get_movement_cost(next) == TileType.IMPASSABLE:
				break
		# 检查目标格是否被占据（不能移到其他单位身上）
		var blocked := false
		if target.get_parent():
			for sibling in target.get_parent().get_children():
				if sibling != target and sibling is Unit and sibling.cell == next:
					blocked = true
					break
		if blocked:
			break
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
	return DisplacementResult.new(from, current)


# ─────────────────────────────────────────────
# 目标收集
# ─────────────────────────────────────────────

## 穿刺直线中间格：若 caster_cell 与 cast_cell 在同一行/列，返回两者之间
## 的全部格子（不含两端）。非水平/垂直返回空数组。用于 extra_effect_id =
## "line_piercing" 的技能在战斗结算与瞄准预览时共享同一份中间格。
static func get_line_piercing_cells(caster_cell: Vector2i, cast_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var delta := cast_cell - caster_cell
	if delta == Vector2i.ZERO:
		return result
	if delta.x != 0 and delta.y != 0:
		return result
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var cur := caster_cell + step
	while cur != cast_cell:
		result.append(cur)
		cur += step
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
	# 穿刺直线：从 caster_cell 到 cast_cell 中间的格子也计入效果
	# 兼容旧 extra_effect_id == "line_piercing"，新走 SkillData.is_line_piercing 标志位
	if (skill.is_line_piercing or skill.extra_effect_id == "line_piercing") and caster is Unit:
		for line_cell in get_line_piercing_cells((caster as Unit).cell, cast_cell):
			effect_cells[line_cell] = true

	var targets: Array = []
	for unit: Node2D in all_units:
		if not unit is Unit:
			continue
		var u := unit as Unit
		if u.combat_stats == null:
			continue
		if not _unit_in_effect(u, effect_cells):
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


## 单位是否落入技能影响区。先查 .cell，再查 extra_target_cells（巨型单位用）。
static func _unit_in_effect(u: Unit, effect_cells: Dictionary) -> bool:
	if effect_cells.has(u.cell):
		return true
	for offset in u.extra_target_cells:
		if effect_cells.has(u.cell + offset):
			return true
	return false
