class_name SkillData
extends Resource
## 技能数据定义。

@export var skill_id: String
@export var skill_name: String
@export var skill_type: Enums.SkillType
@export var ap_cost: int
@export var damage_ratio: float
@export var damage_element: Enums.Element = Enums.Element.NONE
@export var attach_amount: int = 0
@export var extra_effect_id: String = ""
@export var duration_turns: int = 0
@export var cooldown_turns: int = 0
@export_multiline var description: String = ""

## 释放点范围：以施放者所在格为原点的偏移列表。
@export var cast_offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## 应用范围：以释放点为原点的偏移列表。
@export var effect_offsets: Array[Vector2i] = [Vector2i(0, 0)]
