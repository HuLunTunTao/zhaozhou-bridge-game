class_name SurvivalWaveConfig
extends Resource
## 无尽生存波次配置（Step 5.1）：节奏公式 + buff 池 + 李春可学技能池。
##
## 刷点不放本资源：它们是地图锚点节点（survival.tscn 的 WaveSpawnAnchors/North|South/*），
## 锚点所在格即刷点，设计师在编辑器里拖锚点即可改刷点。
## 数值真源 data/stages/survival/wave_config.tres，设计师只改 .tres 不改代码。

# ── 波间回血 / 支援 ──

## 波间友方回血比例下限 / 上限（按 max_hp 计）。
@export var heal_min_ratio: float = 0.30
@export var heal_max_ratio: float = 0.60
## 波间召唤友方支援的概率。
@export var support_prob: float = 0.40

# ── 波次节奏公式 ──

## 每 N 波出一次 Boss。
@export var boss_every: int = 5
## Boss 额外 HP 倍率。
@export var boss_hp_mult: float = 1.3
## Boss 波随从数 = wave / boss_minion_divisor。
@export var boss_minion_divisor: int = 10
## Boss 波 pack 数 = 1 + wave / boss_pack_bonus_divisor。
@export var boss_pack_bonus_divisor: int = 10
## 难度缩放：wave >= scaling_start_wave 起，HP / ATK 每波 ×(1 + (wave - start) * scaling_per_wave)。
@export var scaling_start_wave: int = 10
@export var scaling_per_wave: float = 0.1
## 非 Boss 波 pack 数 = min(pack_base + wave / pack_grow_divisor, pack_max)。
@export var pack_base: int = 2
@export var pack_grow_divisor: int = 3
@export var pack_max: int = 6

# ── buff 池 ──

## 注意：底层用 Array[Resource] 避免 class_name 前向引用问题；
## 每项运行时期望是 WaveBuffDef 实例。
@export var buffs: Array[Resource] = []

## 李春可学技能池（「学技」卡候选）。李春已学的会被运行时过滤。
@export var learnable_skills: Array[SkillData] = []
