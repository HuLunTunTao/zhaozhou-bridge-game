class_name WaveEntry
extends Resource
## 波次中单个 spawn 条目。
## 关卡脚本负责把 `unit_kind` 和 `cell_hint` 解析为具体的 UnitData/技能/cell。

## 「未指定」哨兵（地图 cell 可为负，不能拿 (-1,-1) 之类当哨兵）。
const NO_CELL := Vector2i(-32768, -32768)

## 出生回合（从 1 开始；表示在该回合「敌方回合开始前」生成）
@export var round_number: int = 1

## 单位类型关键字。关卡的 _resolve_wave_unit 按关卡解析成 UnitData/技能/视觉：
##   1-1："dark_current" / "whirl_pool" / "bank_mud_wraith" / "drift_log_pack"
##   1-3："rope_sever" 断索鬼 / "misalign_soldier" 错券兵 / "stone_split" 裂石兽 /
##        "joint_shade" 脱缝鬼
##   1-4："flood_spear" 洪锋 / "siltmare" 泥沙魇 / "pier_gnawer" 桥台噬者 /
##        "flood_driftwood_pack" 漂木群·洪水版 / "dark_current" / "whirl_pool" / "bank_mud_wraith"
@export var unit_kind: String = ""

## cell 提示（动态锚点刷点用，如 1-3 / 1-4；具体词表见各关 _resolve_cell_hint）。
## 非空时优先于 cell 按 hint 运行时解析。
@export var cell_hint: String = ""

## 绝对出生格（静态地图刷点用，如 1-1）。cell_hint 为空且 cell 未设时由关卡告警回退。
@export var cell: Vector2i = NO_CELL
