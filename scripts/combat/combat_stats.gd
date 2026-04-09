class_name CombatStats
extends RefCounted
## 单位运行时战斗状态。从 UnitData 初始化，在战斗中动态修改。


# ── 基础属性 ──

var max_hp: int
var current_hp: int
var base_atk: int
var ap_max: int
var ap_current: int
var move_cost_per_tile: int

## 每回合次数上限（-1 = 无限制）。
var move_limit: int
var skill_limit: int


# ── 属性系统 ──

var innate_element: Enums.Element
var innate_element_amount: int

var current_element: Enums.Element = Enums.Element.NONE
## setter: amount==0 时自动清除 element，<0 时断言报错。
var current_element_amount: int = 0:
	set(v):
		assert(v >= 0, "current_element_amount cannot be negative: %d" % v)
		current_element_amount = v
		if current_element_amount == 0:
			current_element = Enums.Element.NONE


# ── 回合内计数器 ──

var moves_used: int = 0
var skills_used: int = 0


# ── 状态列表 ──

## 运行时状态实例。
var statuses: Array = []  # Array[CombatResolver.StatusInstance]


# ── 身份 ──

var camp: Enums.Camp
var ai_type: String
var is_hero: bool = false
var is_escort_target: bool = false
var unit_name: String


# ── 初始化 ──

func init_from(data: UnitData) -> void:
	unit_name = data.unit_name
	max_hp = data.max_hp
	current_hp = data.max_hp
	base_atk = data.base_atk
	ap_max = data.ap_max
	ap_current = data.ap_max
	move_cost_per_tile = data.move_cost_per_tile
	move_limit = data.move_limit
	skill_limit = data.skill_limit
	innate_element = data.innate_element
	innate_element_amount = data.innate_element_amount
	current_element = data.innate_element
	current_element_amount = data.innate_element_amount
	camp = data.camp
	ai_type = data.ai_type
	is_escort_target = data.is_escort_target
	statuses = []
	moves_used = 0
	skills_used = 0


## 回合开始时重置计数器并恢复 AP。
func reset_turn_counters() -> void:
	moves_used = 0
	skills_used = 0
	ap_current = ap_max


## 检查是否还能移动。
func can_move() -> bool:
	return move_limit < 0 or moves_used < move_limit


## 检查是否还能使用技能（AP + 次数）。
func can_use_skill(skill: SkillData) -> bool:
	if ap_current < skill.ap_cost:
		return false
	return skill_limit < 0 or skills_used < skill_limit


## 是否存活。
func is_alive() -> bool:
	return current_hp > 0


# ─────────────────────────────────────────────
# 状态生命周期
# ─────────────────────────────────────────────

## 回合开始时触发状态效果（AP恢复修正、属性回补跳过等）。
## 在 reset_turn_counters() 之后调用。
func process_turn_start() -> void:
	var skip_element_refresh := false
	for s in statuses:
		match s.status_id:
			"cold_damp":
				var reduction := roundi(ap_max * 0.15)
				ap_current = maxi(ap_current - reduction, 0)
				CombatLog.msg("  状态【湿寒】: %s AP减少%d → %d" % [unit_name, reduction, ap_current])
			"silt_lock":
				skip_element_refresh = true
				CombatLog.msg("  状态【壅水】: %s 跳过属性回补" % unit_name)
			"smothered":
				skip_element_refresh = true
				CombatLog.msg("  状态【闷熄】: %s 跳过属性回补" % unit_name)

	if not skip_element_refresh:
		var before_elem: int = current_element
		var before_amt: int = current_element_amount
		ElementSystem.refresh_innate_element(self)
		if before_elem != current_element or before_amt != current_element_amount:
			CombatLog.log_element_change(unit_name, before_elem, before_amt, current_element, current_element_amount)


## 回合结束时触发状态效果（DoT 等）。返回本回合 DoT 总伤害。
func process_turn_end() -> int:
	var total_dot := 0
	for s in statuses:
		match s.status_id:
			"rend":
				var dot := roundi(s.source_base_atk * 0.30)
				current_hp = maxi(current_hp - dot, 0)
				total_dot += dot
				CombatLog.log_dot(unit_name, "裂伤", dot)
			"scorch_mark":
				var dot := roundi(s.source_base_atk * 0.25)
				current_hp = maxi(current_hp - dot, 0)
				total_dot += dot
				CombatLog.log_dot(unit_name, "灼痕", dot)

	_tick_statuses()
	return total_dot


## 获取移动时的额外 AP 消耗（由状态修正）。
func get_move_ap_modifier() -> int:
	var extra := 0
	for s in statuses:
		match s.status_id:
			"steady_step":
				extra -= 4  # 稳步：浅水额外消耗-4
			"fracture_step":
				extra += 4  # 陷裂：前2格每格+4（简化为全程+4）
			"slowed_step", "hindered_step":
				extra += 2  # 迟步/迟滞：每格+2
	return extra


## 获取移动范围减少量（蔓缚等）。
func get_move_range_penalty() -> int:
	var penalty := 0
	for s in statuses:
		match s.status_id:
			"overgrow_bind":
				penalty += 1
	return penalty


## 休息回复（回合结束时，剩余 AP 转化为生命恢复）。
func rest_recovery() -> int:
	if ap_current <= 0 or ap_max <= 0:
		return 0
	var recover := ceili(float(ap_current) / float(ap_max) * float(max_hp) * 0.10)
	var cap := ceili(float(max_hp) * 0.12)
	recover = mini(recover, cap)
	current_hp = mini(current_hp + recover, max_hp)
	return recover


## 状态倒计时，移除过期状态。
func _tick_statuses() -> void:
	var i := statuses.size() - 1
	while i >= 0:
		var s = statuses[i]
		s.remaining_turns -= 1
		if s.remaining_turns <= 0 or (s.trigger_once and s.triggered):
			statuses.remove_at(i)
		i -= 1
