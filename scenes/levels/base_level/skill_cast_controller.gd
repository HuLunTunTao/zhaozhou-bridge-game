class_name SkillCastController
extends RefCounted

## 技能施放与战斗反馈组件（Tactics Stack）。
## 从 BaseLevel 抽出：技能目标确认与执行 / 战斗反馈 UI / 化势详情 / 直接伤害上报。
## 通过 setup(level) 持有宿主关卡，对 _level 保持鸭子调用，不反向依赖 BaseLevel。
## 不含技能授予（grant_skill / revoke_skill 等，3.9 UnitFactory）、
## 网格查询（_get_occupied_cells_except 等，3.11 LevelQueryAPI，本文件走 _level._xxx 鸭子调用）。

## 输入状态机（真源在 InputController，此处保留旧名供注解使用）。
const InputState = InputController.InputState

## 技能攻击镜头参数
const _SKILL_CAMERA_ZOOM: float = 1.8
const _SKILL_CAMERA_SETTLE_TIME: float = 0.35
const _SKILL_CAMERA_PAUSE_TIME: float = 0.25
const _SKILL_CAMERA_LINGER_TIME: float = 0.45

## 状态 ID → 显示名。（真源外置 data/content_tables/status_names.tres，此处 preload 读取。）
const _STATUS_NAMES: Dictionary = preload("res://data/content_tables/status_names.tres").entries

## 额外效果 ID → 显示名。（真源外置 data/content_tables/extra_effect_names.tres，此处 preload 读取。）
const _EXTRA_EFFECT_NAMES: Dictionary = preload("res://data/content_tables/extra_effect_names.tres").entries

var _level: Node = null   # BaseLevel 宿主


func setup(level: Node) -> void:
	_level = level


# ─────────────────────────────────────────────
# 技能释放
# ─────────────────────────────────────────────

## 技能目标确认 + SkillExecutor.execute + 伤害结算 + 相机 lock_on + 动画等待 + 战斗反馈。
func confirm_targeting_skill(cell: Vector2i) -> void:
	_level._clear_end_turn_pending()
	if _level.selected_unit == null or _level._current_skill == null or _level._skill_targeting == null:
		_level._go_idle()
		return

	if not _level._skill_targeting.has_cast_cell(cell):
		_level._go_idle()
		return

	_level._input_state = InputState.ANIMATING

	# ── 镜头拉近 ──
	var lv_camera := _level.camera as LevelCamera
	var focus_marker: Node2D = null
	if lv_camera:
		var caster_pos: Vector2 = _level.selected_unit.global_position
		var target_pos: Vector2 = _level.tilemap.map_to_local(cell) if _level.tilemap else caster_pos
		focus_marker = Node2D.new()
		_level.add_child(focus_marker)
		focus_marker.global_position = (caster_pos + target_pos) * 0.5
		lv_camera.lock_on(focus_marker, _SKILL_CAMERA_ZOOM)
		await _level.get_tree().create_timer(_SKILL_CAMERA_SETTLE_TIME).timeout
		if _level == null or not is_instance_valid(_level):
			return
		if _level.is_phase_ended():
			focus_marker.queue_free()
			lv_camera.unlock()
			return
		await _level.get_tree().create_timer(_SKILL_CAMERA_PAUSE_TIME).timeout
		if _level == null or not is_instance_valid(_level):
			return
		if _level.is_phase_ended():
			focus_marker.queue_free()
			lv_camera.unlock()
			return

	# ── 执行技能 ──
	var all_units: Array = _level._get_all_units()
	var caster_faction: String = _level.selected_unit.faction if "faction" in _level.selected_unit else ""

	_level.selected_unit.face_towards_cell(cell)
	var exec_result := SkillExecutor.execute(_level.selected_unit, _level._current_skill, cell, all_units, caster_faction, Callable(_level, "_finalize_skill_hit_damage"))
	var used_skill: SkillData = _level._current_skill
	_level._clear_skill_targeting()

	if not exec_result.success:
		push_warning("技能执行失败: %s" % exec_result.error)
		if focus_marker:
			focus_marker.queue_free()
		if lv_camera:
			lv_camera.unlock()
		_level._go_idle()
		return

	SfxManager.play_skill_cast(used_skill)

	# ── 技能释放播报 ──
	var caster_name := ""
	if _level.selected_unit is Unit and (_level.selected_unit as Unit).combat_stats:
		caster_name = (_level.selected_unit as Unit).combat_stats.unit_name
	Notify.info("%s 使用了【%s】！" % [caster_name, used_skill.skill_name], 3.0)

	# ── UI 反馈 ──
	show_combat_feedback(exec_result, caster_name, used_skill)
	if _level.selected_unit is Unit:
		_level._on_skill_executed(_level.selected_unit as Unit, used_skill, cell, exec_result)

	# ── 额外效果播报 ──
	if used_skill.extra_effect_id != "":
		var effect_name: String = _EXTRA_EFFECT_NAMES.get(used_skill.extra_effect_id, "")
		if effect_name != "":
			var target_names: Array[String] = []
			for tu in exec_result.targets:
				if tu is Unit and (tu as Unit).combat_stats:
					target_names.append((tu as Unit).combat_stats.unit_name)
			if not target_names.is_empty():
				Notify.info("%s 触发额外效果：%s" % ["、".join(target_names), effect_name], 3.0)

	# ── 技能执行通知（关卡可响应副作用）──
	_level.skill_executed.emit(_level.selected_unit as Unit, used_skill, cell)
	_level._check_win_lose()

	# 镜头停留片刻后恢复（胜负已结算也要走完，不能被 phase 守卫短路）
	if lv_camera and focus_marker:
		await _level.get_tree().create_timer(_SKILL_CAMERA_LINGER_TIME).timeout
		if _level == null or not is_instance_valid(_level):
			return
		focus_marker.queue_free()
		lv_camera.unlock()

	# 更新状态栏
	_level._update_status_bar_for_unit(_level.selected_unit, true)
	# 刷新攻击者头顶状态条（AP 消耗后）
	if _level.selected_unit is Unit:
		(_level.selected_unit as Unit).refresh_overhead_bars()

	# AP 剩余且还能行动？
	var unit := _level.selected_unit as Unit
	if unit and unit.combat_stats:
		var stats := unit.combat_stats
		var ec: Dictionary = _level._get_enemy_cell_set(unit.faction)
		if _level._has_action_budget(stats) and (stats.can_move() or _level._has_usable_attack(unit, ec)):
			_level._input_state = InputState.UNIT_SELECTED
			if stats.can_move():
				_level._enter_targeting_move()
			return

	if _level.selected_unit:
		_level.selected_unit.has_acted = true
	_level._go_idle()


## 显示战斗 UI 反馈：伤害弹字 + 血条刷新 + 化势提示。
func show_combat_feedback(exec_result: SkillExecutor.ExecuteResult, _caster_name: String = "", skill: SkillData = null) -> void:
	if exec_result.hit_results.is_empty():
		# 辅助技能没有伤害结算，但效果已通过额外效果系统生效，不显示警告
		if skill != null and skill.skill_type == Enums.SkillType.ASSIST:
			# 刷新目标头顶状态条以反映新状态
			for tu in exec_result.targets:
				if tu is Unit:
					(tu as Unit).refresh_overhead_bars()
			return
		Notify.warn("没有单位受到技能效果！", 3.0)
		return
	var showed_phase := false
	for entry in exec_result.hit_results:
		var target_unit: Node2D = entry["unit"]
		var hit: CombatResolver.HitResult = entry["hit"]

		var target_name := ""
		if target_unit is Unit and (target_unit as Unit).combat_stats:
			target_name = (target_unit as Unit).combat_stats.unit_name

		var actual_damage: int = hit.actual_damage if hit.actual_damage >= 0 else hit.damage

		# 伤害弹字
		if actual_damage > 0:
			var phase_name := ""
			if hit.phase_result and hit.phase_result.phase_data:
				phase_name = hit.phase_result.phase_data.phase_name
			var popup := DamagePopup.new()
			_level.add_child(popup)
			popup.show_at(target_unit.global_position, actual_damage, phase_name)

			if hit.is_kill:
				Notify.error("%s 受到 %d 点伤害，被击败了！" % [target_name, actual_damage], 3.0)
			else:
				Notify.info("%s 受到 %d 点伤害！" % [target_name, actual_damage], 3.0)

		if hit.damage_limit_message != "":
			Notify.warn(hit.damage_limit_message, 3.5)

		# 刷新头顶状态条
		if target_unit is Unit:
			(target_unit as Unit).refresh_overhead_bars()

		# 关卡事件信号：HP 变化 + 倒下
		if target_unit is Unit and actual_damage > 0:
			var stats := (target_unit as Unit).combat_stats
			var new_hp: int = stats.current_hp
			var old_hp: int = hit.hp_before if hit.hp_before >= 0 else new_hp + actual_damage
			_level.unit_hp_changed.emit(target_unit, old_hp, new_hp)
			if hit.is_kill:
				_level.unit_died.emit(target_unit)

		for s_info: Dictionary in hit.statuses_to_apply:
			var sname: String = _STATUS_NAMES.get(s_info["id"], s_info["id"])
			Notify.warn("%s 被施加了【%s】！" % [target_name, sname], 3.0)

		# 化势触发时的元素对比 popup（每个命中都显示）
		if hit.phase_result and hit.phase_result.phase_data:
			var elem_popup := PhaseElementPopup.new()
			_level.add_child(elem_popup)
			elem_popup.show_at(
				target_unit.global_position,
				hit.skill_attach_element, hit.skill_attach_amount,
				hit.pre_target_element, hit.pre_target_amount
			)

		# 化势提示（整次施法只一次）
		if not showed_phase and hit.phase_result and hit.phase_result.phase_data:
			showed_phase = true
			var pd: PhaseData = hit.phase_result.phase_data
			var cat_name := "制势" if pd.category == Enums.PhaseCategory.DOMINANT else "承势"
			if _level._phase_notification:
				_level._phase_notification.show_phase(pd.phase_name, cat_name)
			Notify.info(format_phase_details(pd, hit, cat_name), 4.0)


## 拼接化势详情 BBCode 富文本，供 Notify 右上角显示。
func format_phase_details(pd: PhaseData, hit: CombatResolver.HitResult, cat_name: String) -> String:
	var lines: Array[String] = []
	lines.append("【%s·%s】" % [cat_name, pd.phase_name])

	var atk_str := "%s×%d" % [ElementDefs.element_name(hit.skill_attach_element), hit.skill_attach_amount]
	var tgt_str := "%s×%d" % [ElementDefs.element_name(hit.pre_target_element), hit.pre_target_amount]
	lines.append("%s → %s" % [
		ElementDefs.bbcode(hit.skill_attach_element, atk_str),
		ElementDefs.bbcode(hit.pre_target_element, tgt_str),
	])

	if not is_equal_approx(pd.damage_multiplier, 1.0):
		lines.append("伤害倍率 ×%.2f" % pd.damage_multiplier)
	if hit.phase_bonus_damage > 0:
		lines.append("附加伤害 %d" % hit.phase_bonus_damage)
	if pd.apply_status_id != "":
		var sname: String = _STATUS_NAMES.get(pd.apply_status_id, pd.apply_status_id)
		lines.append("施加【%s】%d回合" % [sname, pd.status_duration])

	return "\n".join(lines)


## 子类覆写钩子的默认实现（空）：技能成功执行后的关卡机制响应。
## 子类覆写宿主 BaseLevel._on_skill_executed，由 confirm_targeting_skill 鸭子调用。
func on_skill_executed(_caster: Unit, _skill: SkillData, _cast_cell: Vector2i, _exec_result: SkillExecutor.ExecuteResult) -> void:
	pass


## 子类覆写钩子的默认实现（空）：在战斗反馈显示前修正单次命中的最终 HP / 实际伤害。
## 子类覆写宿主 BaseLevel._finalize_skill_hit_damage，SkillExecutor 经 Callable(_level, ...) 回调。
func finalize_skill_hit_damage(_caster: Unit, _skill: SkillData, _target: Unit, _hit: CombatResolver.HitResult) -> void:
	pass


# ─────────────────────────────────────────────
# 直接伤害 / 上报结算
# ─────────────────────────────────────────────

## 直接伤害/回复统一出口（不经 SkillExecutor 的 HP 变化必须走这里）。
## 前置条件：伤害/回复已应用到 combat_stats。负责 emit unit_hp_changed / unit_died，
## 并无条件调用 _check_win_lose（幂等：phase ENDED 后重复调用为 no-op）。
func report_unit_damaged(unit: Unit, old_hp: int, new_hp: int) -> void:
	if unit == null:
		return
	_level.unit_hp_changed.emit(unit, old_hp, new_hp)
	if new_hp <= 0:
		_level.unit_died.emit(unit)
	_level._check_win_lose()


## 直接伤害便捷入口：先扣减 combat_stats.current_hp，再走 report_unit_damaged 上报结算。
## source 可选，非空时写入 CombatLog。仅用于关卡机制类固定伤害，不走 SkillExecutor。
func apply_direct_damage(unit: Unit, damage: int, source: String = "") -> void:
	if unit == null or unit.combat_stats == null or not unit.combat_stats.is_alive():
		return
	if damage <= 0:
		return
	var old_hp: int = unit.combat_stats.current_hp
	unit.combat_stats.current_hp = maxi(old_hp - damage, 0)
	unit.refresh_overhead_bars()
	if source != "":
		CombatLog.msg("    直接伤害: %s -%d（%s）" % [
			unit.combat_stats.unit_name, old_hp - unit.combat_stats.current_hp, source,
		])
	report_unit_damaged(unit, old_hp, unit.combat_stats.current_hp)
