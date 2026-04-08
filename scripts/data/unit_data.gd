class_name UnitData
extends Resource
## 单位数据定义。

@export var unit_id: String
@export var unit_name: String
@export var camp: Enums.Camp = Enums.Camp.ALLY
@export var max_hp: int = 100
@export var base_atk: int = 10
@export var ap_max: int = 100
@export var move_cost_per_tile: int = 10
## 每回合移动次数上限，-1 = 无限制。
@export var move_limit: int = -1
## 每回合技能使用次数上限，-1 = 无限制。
@export var skill_limit: int = -1
@export var innate_element: Enums.Element = Enums.Element.NONE
@export var innate_element_amount: int = 0
@export var ai_type: String = ""
@export var is_escort_target: bool = false
## 技能列表，上限 5 个。
@export var skills: Array[SkillData] = []:
	set(v):
		assert(v.size() <= 5, "单位技能数不能超过5个，当前: %d" % v.size())
		skills = v
