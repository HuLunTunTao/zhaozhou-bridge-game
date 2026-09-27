class_name RosterEntry
extends Resource
## 我方队伍一行属性（Step 4.8）。
## 李春 / 测量工 / 工匠 / 运石工 等的运行时战斗数值五件套：
## unit_name + max_hp / base_atk / ap_max / move_cost，
## 对应 UnitFactory.setup_unit_stats 的覆写参数（element 恒 NONE/0，保持旧装配语义）。
## 各关数值可能不同（设计师按关配平），所以按关各存一张 roster_*.tres，数值只在 .tres 维护。

@export var unit_name: String = ""
@export var max_hp: int = 100
@export var base_atk: int = 10
@export var ap_max: int = 100
@export var move_cost: int = 8
