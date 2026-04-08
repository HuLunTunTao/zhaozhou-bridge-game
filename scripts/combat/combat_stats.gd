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
var statuses: Array = []  # Array[StatusInstance]


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
