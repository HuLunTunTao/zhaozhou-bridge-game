class_name AITurnRunner
extends RefCounted

## AI 回合执行组件（Tactics Stack）。
## 从 BaseLevel 抽出：AI 决策循环 / AI 技能执行 / AI 侧行动预算查询。
## 通过 setup(level) 持有宿主关卡，对 _level 保持鸭子调用，不反向依赖 BaseLevel。
## 不含网格查询（_get_enemy_cells_except 等，3.11 LevelQueryAPI）、战斗反馈 UI（3.4/3.5）、debug AI 对话（3.14）。

const _AIBrain := preload("res://scripts/combat/ai_brain.gd")

## 单个队伍的运行时数据（真源在 TurnSystem，此处保留旧类型名供注解使用）。
const TeamData = TurnSystem.TeamData

## AI 回合中每个单位行动前，镜头锁定并放大的倍率。
const _AI_TURN_CAMERA_LOCK_ZOOM: float = 1.4
## 镜头切到新单位后、该单位开始移动前的等待时间（秒），给玩家视线跟上的间隔。
const _AI_TURN_CAMERA_FOCUS_DELAY: float = 0.3


var _level: Node = null   # BaseLevel 宿主


func setup(level: Node) -> void:
	_level = level


# ─────────────────────────────────────────────
# AI 回合
# ─────────────────────────────────────────────

func run_ai_turn(team: TeamData) -> void:
	var lv_camera := _level.camera as LevelCamera
	# 走宿主的虚方法钩子，保留子类覆写（level1-1 / level1-4 的 _get_ai_context）。
	var context: Dictionary = _level._get_ai_context()
	for unit: Node2D in team.units:
		if _level.is_phase_ended():
			break
		if not is_instance_valid(unit):
			continue
		if not unit is Unit:
			continue
		var u := unit as Unit
		if u.combat_stats == null or not u.combat_stats.is_alive():
			continue

		# 镜头锁定
		if lv_camera:
			lv_camera.lock_on(unit, _AI_TURN_CAMERA_LOCK_ZOOM)
			await _level.get_tree().create_timer(_AI_TURN_CAMERA_FOCUS_DELAY).timeout
			if _level == null or not is_instance_valid(_level):
				return
			if _level.is_phase_ended():
				break

		CombatLog.msg("  AI行动: %s 在%s" % [u.combat_stats.unit_name, u.cell])

		# 决策
		var enemies := get_alive_enemies_of(u.faction)
		var friendly_cells: Array[Vector2i] = _level._get_friendly_cells_except(u)
		var enemy_cells: Array[Vector2i] = _level._get_enemy_cells_except(u)
		var action := _AIBrain.decide_action(u, enemies, _level.tilemap, _level.movement_manager, friendly_cells, enemy_cells, context)

		# 执行移动
		if action["move_path"].size() >= 2:
			var path: Array[Vector2i] = action["move_path"]
			var from_cell := path[0]
			u.move_along_path(path, _level.tilemap)
			await u.move_finished
			if _level == null or not is_instance_valid(_level):
				return
			if _level.is_phase_ended():
				break
			if not u.combat_stats.has_infinite_actions():
				u.combat_stats.ap_current -= action["move_cost"]
			u.combat_stats.moves_used += 1
			u.refresh_overhead_bars()
			CombatLog.msg("    移动: %s → %s (消耗%dAP)" % [from_cell, u.cell, action["move_cost"]])

		if _level.is_phase_ended():
			break

		# 执行攻击
		if action["skill"] != null:
			await execute_ai_skill(u, action["skill"], action["cast_cell"])
			if _level == null or not is_instance_valid(_level):
				return

		u.has_acted = true

	if lv_camera:
		lv_camera.unlock()
	if not _level.is_phase_ended():
		_level._do_end_turn()


## AI 使用技能：镜头聚焦 + 执行 + 战斗反馈。
func execute_ai_skill(unit: Unit, skill: SkillData, cast_cell: Vector2i) -> void:
	var lv_camera := _level.camera as LevelCamera
	var focus_marker: Node2D = null

	# 镜头聚焦到施法者与目标中点
	if lv_camera:
		var caster_pos: Vector2 = unit.global_position
		var target_pos: Vector2 = _level.tilemap.map_to_local(cast_cell) if _level.tilemap else caster_pos
		focus_marker = Node2D.new()
		_level.add_child(focus_marker)
		focus_marker.global_position = (caster_pos + target_pos) * 0.5
		lv_camera.lock_on(focus_marker, _level._SKILL_CAMERA_ZOOM)
		await _level.get_tree().create_timer(_level._SKILL_CAMERA_SETTLE_TIME).timeout
		if _level == null or not is_instance_valid(_level):
			return
		if _level.is_phase_ended():
			focus_marker.queue_free()
			lv_camera.unlock()
			return

	# 执行技能
	unit.face_towards_cell(cast_cell)
	var all_units: Array = _level._get_all_units()
	var caster_faction: String = unit.faction if "faction" in unit else ""
	var exec_result := SkillExecutor.execute(unit, skill, cast_cell, all_units, caster_faction, Callable(_level, "_finalize_skill_hit_damage"))

	if exec_result.success:
		SfxManager.play_skill_cast(skill)
		CombatLog.msg("    技能: %s → %s" % [skill.skill_name, cast_cell])
		# 技能释放播报
		var caster_name: String = unit.combat_stats.unit_name if unit.combat_stats else unit.name
		Notify.info("%s 使用了【%s】！" % [caster_name, skill.skill_name], 3.0)
		_level._show_combat_feedback(exec_result, caster_name, skill)
		# 额外效果播报
		if skill.extra_effect_id != "":
			var effect_name: String = _level._EXTRA_EFFECT_NAMES.get(skill.extra_effect_id, "")
			if effect_name != "":
				var target_names: Array[String] = []
				for tu in exec_result.targets:
					if tu is Unit and (tu as Unit).combat_stats:
						target_names.append((tu as Unit).combat_stats.unit_name)
				if not target_names.is_empty():
					Notify.info("%s 触发额外效果：%s" % ["、".join(target_names), effect_name], 3.0)
		unit.refresh_overhead_bars()
		# 技能执行通知
		_level.skill_executed.emit(unit, skill, cast_cell)
		_level._check_win_lose()

	# 镜头恢复（胜负已结算也要走完，不能被 phase 守卫短路）
	if lv_camera and focus_marker:
		await _level.get_tree().create_timer(_level._SKILL_CAMERA_LINGER_TIME).timeout
		if _level == null or not is_instance_valid(_level):
			return
		focus_marker.queue_free()
		lv_camera.unlock()
	elif focus_marker:
		focus_marker.queue_free()


# ─────────────────────────────────────────────
# AI 决策辅助
# ─────────────────────────────────────────────

## 为 AI 提供关卡特有的上下文信息的默认实现（子类覆写宿主 _get_ai_context）。
func get_ai_context() -> Dictionary:
	return {}


## 获取指定阵营的所有存活敌对单位。
func get_alive_enemies_of(faction: String) -> Array:
	var result: Array = []
	for t: TeamData in _level.teams:
		if t.faction == faction:
			continue
		for u: Node2D in t.units:
			if u is Unit and u.combat_stats != null and u.combat_stats.is_alive():
				result.append(u)
	return result


## 当前玩家队伍是否还有可行动单位（未 has_acted、未在移动中、还能移动或有技能能打到敌人）。
func player_team_has_remaining_actions() -> bool:
	if _level.current_team_index < 0 or _level.current_team_index >= _level.teams.size():
		return false
	var team: TeamData = _level.teams[_level.current_team_index]
	if team.controller != "player":
		return false
	var enemy_cells: Dictionary = _level._get_enemy_cell_set(team.faction)
	for unit: Node2D in team.units:
		if not unit is Unit:
			continue
		var u := unit as Unit
		if u.has_acted or u.is_moving:
			continue
		if u.combat_stats == null or not u.combat_stats.is_alive():
			continue
		var stats: CombatStats = u.combat_stats
		if has_action_budget(stats) and (stats.can_move() or has_usable_attack(u, enemy_cells)):
			return true
	return false


func has_action_budget(stats: CombatStats) -> bool:
	return stats != null and (stats.has_infinite_actions() or stats.ap_current > 0)


## 检查单位是否有攻击技能能够打到敌人（AP/次数够 + 范围内有敌人）。
func has_usable_attack(unit: Unit, enemy_cells: Dictionary) -> bool:
	if unit.combat_stats == null or unit.unit_data == null:
		return false
	for skill: SkillData in unit.unit_data.skills:
		if not unit.combat_stats.can_use_skill(skill):
			continue
		# 非攻击技能（辅助/交互）只需 AP 和次数足够即可使用
		if skill.skill_type != Enums.SkillType.ATTACK:
			return true
		# 攻击技能需要敌人在施法+效果范围内
		for cast_offset in skill.cast_offsets:
			var cast_cell := unit.cell + cast_offset
			for effect_offset in skill.effect_offsets:
				if enemy_cells.has(cast_cell + effect_offset):
					return true
	return false
