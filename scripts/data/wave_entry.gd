class_name WaveEntry
extends Resource
## 波次中单个 spawn 条目。
## 关卡脚本负责把 `unit_kind` 和 `cell_hint` 解析为具体的 UnitData/技能/cell。

## 出生回合（从 1 开始；表示在该回合「敌方回合开始前」生成）
@export var round_number: int = 1

## 单位类型关键字。当前支持：
##   "flood_spear"           洪锋
##   "siltmare"              泥沙魇
##   "pier_gnawer"           桥台噬者
##   "flood_driftwood_pack"  漂木群·洪水版
@export var unit_kind: String = ""

## cell 提示。当前支持：
##   "near_left_pier_west"      左桥台西侧 2 格
##   "near_right_pier_east"     右桥台东侧 2 格
##   "watch_north_2"            桥心观察位上 2 格
##   "arch_left_front_north_2"  左前小拱上 2 格
##   "arch_right_front_north_2" 右前小拱上 2 格
@export var cell_hint: String = ""
