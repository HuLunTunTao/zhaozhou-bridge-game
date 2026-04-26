class_name UnitData
extends Resource
## 单位数据定义。

@export var unit_id: String
@export var unit_name: String
## 头像纹理（7:9 比例），在状态栏左侧显示。
@export var portrait: Texture2D
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
## 仅限水域移动。为 true 时 AI 只在 is_water() 地块上移动。
@export var water_only: bool = false
@export var is_escort_target: bool = false
## 是否为人形单位。非人形（怪物 / 水流 / 石块等）使用更弱的描边和选中高光，
## 避免大量怪物挤在一起时高光过度刺眼。
@export var is_humanoid: bool = true
## 技能列表，上限 5 个。
@export var skills: Array[SkillData] = []:
	set(v):
		assert(v.size() <= 5, "单位技能数不能超过5个，当前: %d" % v.size())
		skills = v
