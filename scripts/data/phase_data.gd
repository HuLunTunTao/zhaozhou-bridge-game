class_name PhaseData
extends Resource
## 化势（五行反应）数据定义。

@export var phase_id: String
@export var phase_name: String
@export var attack_element: Enums.Element
@export var target_element: Enums.Element
@export var category: Enums.PhaseCategory = Enums.PhaseCategory.DOMINANT
@export var damage_multiplier: float = 1.0
## 附加伤害类型：""=无, "target_max_hp_ratio"=目标最大生命百分比。
@export var bonus_damage_type: String = ""
@export var bonus_damage_value: float = 0.0
## 附加伤害上限表达式，如 "attacker_base_atk * 2.0"。
@export var bonus_damage_cap: String = ""
## 额外属性消耗量（覆烬等）。
@export var extra_element_consume: int = 0
## 触发时施加的状态ID。
@export var apply_status_id: String = ""
## 施加状态的持续回合。
@export var status_duration: int = 0
@export_multiline var flavor_text: String = ""
