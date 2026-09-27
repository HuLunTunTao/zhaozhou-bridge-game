class_name WaveBuffDef
extends Resource
## 无尽生存波间「三选一」buff 卡定义（Step 5.1）。
## 一条 = 一张成长卡。SurvivalWaveController._build_buff_options 逐条转成
## GrowthChoicePanel 的 option dict（id / name / description / _kind / _amount / _label / _element）。
##
## 「学技」卡不在本表：由 SurvivalWaveConfig.learnable_skills 运行时生成，
## 名称 / 描述取自 SkillData 本身，避免同一份文案两处维护。

## option id，GrowthChoicePanel 选中后原样回传。
@export var id: String = ""

## 卡面标题。
@export var display_name: String = ""

## 卡面描述。
@export var description: String = ""

## 应用类型，_apply_buff 按此分支：
##   "hp_cap"         — 李春 max_hp += amount 并回满
##   "ap_cap"         — 李春 ap_max += amount
##   "element_attach" — 李春附着 element 元素，持续 amount 次出招
@export var kind: String = ""

## 数值：hp_cap / ap_cap 的加量；element_attach 的附着次数。
@export var amount: int = 0

## 解锁波次，0 = 一直可抽。wave_index < unlock_wave 时该卡不入候选池。
@export var unlock_wave: int = 0

## element_attach 专用：附着的元素（Enums.Element）。
@export var element: int = 0

## WaveBuffHud 增益栏小标签。
@export var label: String = ""
