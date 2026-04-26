class_name SkillData
extends Resource
## 技能数据定义。

@export var skill_id: String
@export var skill_name: String
@export var skill_type: Enums.SkillType
@export var ap_cost: int
@export var damage_ratio: float
## 中心+辐射型 AOE 技能：cast_cell（中心格）使用 damage_ratio，其余 effect_offsets
## 单位使用 surround_ratio。负值表示无中心/周围区分（普通技能）。
@export var surround_ratio: float = -1.0
## 条件触发倍率：满足 extra_effect_id 对应条件时（如 cond_no_attached_bonus），
## 该格目标 base_damage 改用 conditional_ratio。负值表示该技能无条件倍率。
@export var conditional_ratio: float = -1.0
@export var damage_element: Enums.Element = Enums.Element.NONE
@export var attach_amount: int = 0
@export var extra_effect_id: String = ""
## 直线穿刺：true 时 _collect_targets 会自动把 caster→cast_cell 之间的线上格子加入命中范围
## （独立于 extra_effect_id，便于穿刺与 cond_xxx 条件并存）。
@export var is_line_piercing: bool = false
@export var duration_turns: int = 0
@export var cooldown_turns: int = 0
@export_multiline var description: String = ""

## 释放点范围：以施放者所在格为原点的偏移列表。
@export var cast_offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## 应用范围：以释放点为原点的偏移列表。
@export var effect_offsets: Array[Vector2i] = [Vector2i(0, 0)]
