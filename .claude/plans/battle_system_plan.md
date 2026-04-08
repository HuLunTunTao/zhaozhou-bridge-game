# 五行流转战斗系统 — 实现方案 v2

## Context

项目"安济桥成"是 Godot 4.6 等距战棋游戏。当前已完成：
- **已完成**: player→unit 统一化重构（`Unit` class_name、`Entities/Units` 合并、`hero`/`unit_selected` 命名）
- **已完成**: 回合制队伍切换、Dijkstra 寻路移动、地形消耗、特殊地块事件、ActionPanel UI

**尚未实现**: 攻击、技能、血量、伤害、属性、状态效果、AI、关卡配置。

设计文档: `artbook/数值.md`

---

## 属性附着核心算法

以下伪代码由策划提供，是属性系统的权威定义：

```python
# ── 技能命中后的属性变换 ──
# A = 技能属性, x = 技能附着量
# B = 目标当前属性, y = 目标当前属性量

if A == B or A == null:       # 同气 或 无属性攻击
    pass                      # 不消耗、不改变
elif B == null:               # 目标无属性
    B = A                     # 直接附着
    y = x
else:                         # 异属性碰撞
    if x > y:                 # 攻击方属性量更大
        y = x - y             # 剩余量覆盖
        B = A
    elif x == y:              # 刚好对消
        y = 0
        B = null
    else:                     # 目标属性更强
        y = y - x             # 部分消耗

# ── 回合开始时的固有属性回补 ──
# B = 当前属性, y = 当前属性量
# C = 固有属性, z = 固有属性量

if B == C:                    # 当前 = 固有
    pass                      # 不变
elif B == null:               # 无属性
    B = C                     # 开始回补
    y = 1
else:                         # 外来属性残留
    y = max(y - 1, 0)         # 每回合消退1层
    if y == 0:
        B = null

# ── setter 规则 ──
# 属性量 y 的 setter: 只要 y == 0, 则 B = null
```

### 与数值.md的关系

数值.md 1.5-1.7 节的规则映射到此算法：
- **同气**: `A == B` → pass（不消耗、不改变）
- **化势/逆势/普通异属性**: 都走 `else` 分支（属性量对消），化势/逆势的**伤害倍率**和**状态施加**在此算法之外由 phase_table 处理
- **无属性攻击**: `A == null` → pass（不消耗目标属性）
- **有属性→无属性目标**: `B == null` → 直接附着
- **敌方固有属性回补**: 回合开始时执行第二段算法

---

## 架构总览

```
scripts/data/              ← 数据定义 (Resource)
  enums.gd                 ← Element, SkillType, AreaShape, TargetRule, Camp
  unit_data.gd             ← UnitData Resource
  skill_data.gd            ← SkillData Resource
  status_data.gd           ← StatusData Resource
  phase_data.gd            ← PhaseData Resource（化势模板）

scripts/combat/            ← 战斗逻辑
  combat_stats.gd          ← 运行时单位状态 (RefCounted)
  element_system.gd        ← 属性附着/消耗/回补（实现上述伪代码）
  phase_table.gd           ← 化势查找表（10条 + 逆势规则）
  combat_resolver.gd       ← 伤害计算（纯函数）
  skill_executor.gd        ← 技能执行流水线
  skill_targeting.gd       ← 技能范围高亮 (Node2D)
  battle_manager.gd        ← 行动循环、波次、胜负判定

scripts/ai/                ← AI 系统
  ai_controller.gd         ← AI 基类
  ai_flank_melee.gd        ← 暗涌
  ai_control_pull.gd       ← 水旋
  ai_zone_breaker.gd       ← 坍岸泥鬼
  ai_hazard_charge.gd      ← 浮木群

data/                      ← .tres 数据文件
  units/                   ← hero_li_chun.tres 等 7 个
  skills/                  ← 全部技能 .tres (~12 个)
  phases/                  ← 化势反应 .tres (10 个)
  statuses/                ← 状态效果 .tres (~12 个)
```

---

## 核心类设计

### Enums (`scripts/data/enums.gd`)

```gdscript
class_name Enums

enum Element { NONE, METAL, WOOD, WATER, FIRE, EARTH }
enum SkillType { ATTACK, ASSIST, INTERACT, ASSIST_INTERACT }
enum Camp { ALLY, ENEMY }
enum PhaseCategory { DOMINANT, FOLLOW, ADVERSE, SAME, PLAIN }
```

### UnitData (`scripts/data/unit_data.gd`)

```gdscript
class_name UnitData extends Resource

@export var unit_id: String
@export var unit_name: String
@export var camp: Enums.Camp
@export var max_hp: int
@export var base_atk: int
@export var ap_max: int
@export var move_cost_per_tile: int = 10
@export var attack_limit: int = -1        # -1 = unlimited
@export var assist_limit: int = -1
@export var interact_limit: int = -1
@export var innate_element: Enums.Element = Enums.Element.NONE
@export var innate_element_amount: int = 0
@export var ai_type: String = ""
@export var is_escort_target: bool = false
## 技能列表，上限 5 个。超出时编辑器报错。
@export var skills: Array[SkillData] = []:
    set(v):
        assert(v.size() <= 5, "单位技能数不能超过5个，当前: %d" % v.size())
        skills = v
```

### SkillData (`scripts/data/skill_data.gd`)

技能有两个独立的范围定义，均为相对坐标偏移列表：
- **cast_offsets**: 以施放单位为原点，可选择的释放点范围
- **effect_offsets**: 以释放点为原点，技能实际影响的区域

```gdscript
class_name SkillData extends Resource

@export var skill_id: String
@export var skill_name: String
@export var skill_type: Enums.SkillType   # ATTACK/ASSIST/INTERACT/ASSIST_INTERACT
@export var ap_cost: int
@export var damage_ratio: float
@export var damage_element: Enums.Element
@export var attach_amount: int = 0
@export var extra_effect_id: String = ""
@export var duration_turns: int = 0
@export var cooldown_turns: int = 0
@export_multiline var description: String = ""

## 释放点范围：以施放者所在格为原点的偏移列表。
## 玩家选择其中一个格子作为技能释放点。
@export var cast_offsets: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

## 应用范围：以释放点为原点的偏移列表。
## 释放点自身用 Vector2i(0,0) 表示。该范围内的合法单位会被技能影响。
@export var effect_offsets: Array[Vector2i] = [Vector2i(0,0)]
```

**目标筛选规则（简化）**:
- `ATTACK` 类技能：只对敌方阵营单位生效
- `ASSIST` 类技能：只对友方阵营单位生效
- `INTERACT` / `ASSIST_INTERACT`：对地块生效（不筛选阵营）

**示例 — 数值.md 技能映射**:

```gdscript
# 规尺击 (近战单体)
cast_offsets = OffsetPresets.diamond(1, 1)    # 上下左右 4 邻格
effect_offsets = OffsetPresets.SINGLE          # 单体

# 投石遏流 (远程单体, range=3)
cast_offsets = OffsetPresets.diamond(1, 3)     # 曼哈顿距离 1~3
effect_offsets = OffsetPresets.SINGLE

# 相水定址 (十字范围, range=3, radius=1)
cast_offsets = OffsetPresets.diamond(1, 3)
effect_offsets = OffsetPresets.cross(1)        # 十字, 臂长1

# 漂槎冲岸 (直线4格)
cast_offsets = OffsetPresets.line(Vector2i(1,0), 4)  # 一个方向的直线
effect_offsets = OffsetPresets.SINGLE

# 束桩缓波 (远程, 对目标周围十字施加迟滞)
cast_offsets = OffsetPresets.diamond(1, 3)
effect_offsets = OffsetPresets.cross(1)
```

### OffsetPresets (`scripts/data/offset_presets.gd`)

提供典型范围模板的静态工具函数，避免手动填写大量 Vector2i：

```gdscript
class_name OffsetPresets

## 单体（释放点自身）
const SINGLE: Array[Vector2i] = [Vector2i(0, 0)]

## 菱形（曼哈顿距离 min_r ~ max_r 的所有格子）
## diamond(1,1) = 4邻格, diamond(1,3) = 远程3格范围, diamond(0,2) = 含自身的2格范围
static func diamond(min_r: int, max_r: int) -> Array[Vector2i]: ...

## 十字（上下左右各 arm_length 格 + 中心）
## cross(1) = 5格十字, cross(2) = 9格长十字
static func cross(arm_length: int) -> Array[Vector2i]: ...

## 直线（沿 direction 方向, 长度 length 格, 不含原点）
## line(V(1,0), 4) = 右方4格直线
static func line(direction: Vector2i, length: int) -> Array[Vector2i]: ...

## 四方向直线（上下左右各 length 格, 不含原点, 用于无方向限制的直线技能）
static func lines_4dir(length: int) -> Array[Vector2i]: ...
```

### CombatStats (`scripts/combat/combat_stats.gd`)

```gdscript
class_name CombatStats extends RefCounted

# 从 UnitData 初始化
var max_hp: int
var current_hp: int
var base_atk: int
var ap_max: int
var ap_current: int
var move_cost_per_tile: int
var attack_limit: int
var assist_limit: int
var interact_limit: int

# 属性系统 — setter 保证: amount==0 时清除 element, amount<0 时报错
var innate_element: Enums.Element
var innate_element_amount: int
var current_element: Enums.Element = Enums.Element.NONE
var current_element_amount: int = 0:
    set(v):
        assert(v >= 0, "current_element_amount cannot be negative: %d" % v)
        current_element_amount = v
        if current_element_amount == 0:
            current_element = Enums.Element.NONE

# 回合内计数器
var attacks_used: int = 0
var assists_used: int = 0
var interacts_used: int = 0

# 状态列表
var statuses: Array = []  # Array[StatusInstance]

# AI
var ai_type: String
var camp: Enums.Camp
var is_hero: bool = false

func init_from(data: UnitData) -> void: ...
func reset_turn_counters() -> void: ...
```

### ElementSystem (`scripts/combat/element_system.gd`)

```gdscript
class_name ElementSystem

## 技能命中后的属性变换（实现策划伪代码）
static func apply_skill_element(
    stats: CombatStats,
    skill_element: Enums.Element,
    attach_amount: int
) -> void:
    var A := skill_element
    var x := attach_amount
    var B := stats.current_element
    var y := stats.current_element_amount

    if A == B or A == Enums.Element.NONE:
        return
    elif B == Enums.Element.NONE:
        stats.current_element = A
        stats.current_element_amount = x
    else:
        if x > y:
            stats.current_element = A
            stats.current_element_amount = x - y
        elif x == y:
            stats.current_element_amount = 0  # setter 会自动清 element
        else:
            stats.current_element_amount = y - x


## 回合开始时的固有属性回补
static func refresh_innate_element(stats: CombatStats) -> void:
    var B := stats.current_element
    var y := stats.current_element_amount
    var C := stats.innate_element

    if C == Enums.Element.NONE:
        return
    if B == C:
        return
    elif B == Enums.Element.NONE:
        stats.current_element = C
        stats.current_element_amount = 1
    else:
        stats.current_element_amount = max(y - 1, 0)
```

### PhaseTable (`scripts/combat/phase_table.gd`)

```gdscript
class_name PhaseTable

# 五行相克: 金→木→土→水→火→金
# 五行相生: 金→土, 木→水, 土→火, 水→金, 火→木
static var _dominant: Dictionary  # {Vector2i(atk, tgt): PhaseData}
static var _follow: Dictionary
static var _adverse: Dictionary   # 逆势: 目标克攻击

static func lookup(atk_elem: Enums.Element, tgt_elem: Enums.Element) -> Dictionary:
    # 返回 {category: PhaseCategory, multiplier: float, phase_data: PhaseData or null}
```

### CombatResolver (`scripts/combat/combat_resolver.gd`)

纯函数，无状态，返回结果结构体。

```gdscript
class_name CombatResolver

static func resolve_hit(attacker: CombatStats, target: CombatStats, skill: SkillData) -> HitResult:
    # 1. base_damage = base_atk * damage_ratio
    # 2. phase_info = PhaseTable.lookup(skill.damage_element, target.current_element)
    # 3. phase_multiplier (化势1.0~1.1, 逆势0.8, 同气1.0, 普通1.0)
    # 4. 无属性→无属性: multiplier = 1.15
    # 5. 遍历攻击方 statuses 修正 (weakened → *0.8)
    # 6. 遍历目标 statuses 修正 (brittle → *1.2, trigger_once)
    # 7. phase_bonus_damage (如土克水的 max_hp*0.15)
    # 8. 属性对消: ElementSystem.apply_skill_element()
    # 9. 化势状态施加
    # 10. 返回 HitResult
```

---

## 信号与通信

```
信号向上: Unit → BattleManager → BaseLevel
调用向下: BaseLevel → BattleManager → CombatResolver

BattleManager 信号:
  damage_dealt(source: Unit, target: Unit, result: HitResult)
  status_applied(target: Unit, status_id: String)
  unit_died(unit: Unit)
  unit_action_completed(unit: Unit)
  unit_clicked(unit: Unit)          ← 状态栏更新

CombatResolver: 纯逻辑, 无信号, 返回 HitResult
ElementSystem: 纯逻辑, 无信号, 直接修改 CombatStats
```

---

## 输入状态机

所有输入操作通过 **命令函数** 间接执行，不直接耦合鼠标事件。
鼠标/键盘只是调用这些函数的入口，方便日后支持键盘操作和调试。

### 命令函数（BaseLevel 公开方法）

```gdscript
# 预选：模拟鼠标悬停到某个格子，更新 overlay 预览
func preview_cell(cell: Vector2i) -> void

# 确认：模拟点击当前预选的格子（移动/释放技能/选中单位）
func confirm_cell(cell: Vector2i) -> void

# 取消：回退到上一个输入状态
func cancel_action() -> void

# 选择技能：从 ActionPanel 选择一个技能进入 TARGETING_SKILL
func select_skill(skill: SkillData) -> void

# 结束等待：当前单位跳过剩余行动
func end_unit_turn() -> void
```

鼠标输入映射（`_unhandled_input` 内部）:
- `MouseMotion` → `preview_cell(hovered_cell)`
- `RightClick` → `confirm_cell(clicked_cell)`
- `ESC / 右键空地` → `cancel_action()`

### 状态流转

```
IDLE
  → confirm_cell(己方可行动单位) → UNIT_SELECTED (更新状态栏+技能按钮)
  → confirm_cell(任意单位) → 更新状态栏（不进入选中）
  → confirm_cell(空地) → 状态栏回退显示主角

UNIT_SELECTED
  → select_skill("移动") → TARGETING_MOVE (显示移动范围)
  → select_skill(技能) → TARGETING_SKILL (显示释放范围)
  → end_unit_turn() → 结束该单位回合 → IDLE
  → cancel_action() → IDLE

TARGETING_MOVE
  → preview_cell(格子) → 更新路径预览 + 显示预计消耗/剩余 AP
  → confirm_cell(可达格) → ANIMATING → AP 剩余? UNIT_SELECTED : IDLE
  → cancel_action() → UNIT_SELECTED

TARGETING_SKILL
  → preview_cell(释放点) → 叠加显示 effect_offsets 影响区域
  → confirm_cell(合法释放点) → ANIMATING → AP 剩余? UNIT_SELECTED : IDLE
  → cancel_action() → UNIT_SELECTED

ANIMATING
  → 动画完成 → 返回上一状态
```

---

## 状态栏 UI

StatusPanel 背景色按阵营切换：

| 对象 | 颜色 |
|------|------|
| 主角特别地（李春） | 蓝色 `(0.2, 0.3, 0.7, 0.8)` |
| 友方 | 浅绿 `(0.3, 0.7, 0.3, 0.8)` |
| 敌方 | 浅红 `(0.7, 0.3, 0.3, 0.8)` |
| 空地 | 回退主角 |

### 状态栏布局

```
┌──────────────────────────────────────────────────────────────┐
│ 左侧                              │ 右侧（仅己方可操作单位）   │
│                                    │                          │
│ 角色名                             │ [规尺击] [木楔勘岸] ...   │
│ HP: 120/130                        │  (技能按钮，AP不足灰显)   │
│ AP: 75/100                         │                          │
│ 属性: 水×2                         │                          │
│ (非主角额外显示:)                   │                          │
│ 攻击: 1/1  辅助: 0/1              │                          │
├──────────────────────────────────────────────────────────────┘
```

**左侧信息**（所有单位都显示）:
- 角色名
- HP / MaxHP
- AP / MaxAP（己方显示当前值，敌方显示上限）
- 当前属性 + 层数（无属性不显示）
- 状态效果列表

**左侧额外信息**（仅非主角的己方单位）:
- 剩余攻击次数 / 上限
- 剩余辅助次数 / 上限（如有）
- 剩余交互次数 / 上限（如有）

**右侧技能按钮**（仅当前可操作的己方单位）:
- 固定 5 个按钮槽位（对应技能上限 5）
- 有技能的槽位显示技能名，无技能的槽位隐藏
- AP 不足时灰显（disabled）
- 次数用尽时灰显
- 点击按钮 → 调用 `select_skill(skill)` 进入 TARGETING_SKILL
- 敌方单位或非选中状态时：右侧隐藏所有按钮


---

## 分阶段实施

### Phase 0: 数据层 ← 第一步

**目标**: 建立所有 Resource 脚本和第一关 .tres 数据文件。

**创建文件**:
- `scripts/data/enums.gd` — 枚举
- `scripts/data/unit_data.gd` — UnitData（技能上限 5，setter 校验）
- `scripts/data/skill_data.gd` — SkillData（cast_offsets + effect_offsets）
- `scripts/data/offset_presets.gd` — 范围模板工具函数（diamond, cross, line, lines_4dir）
- `scripts/data/status_data.gd` — StatusData
- `scripts/data/phase_data.gd` — PhaseData
- `data/units/*.tres` — 7 个单位 (hero_li_chun, survey_worker, craftsman_guard, dark_current, whirl_pool, bank_mud_wraith, drift_log_pack)
- `data/skills/*.tres` — ~12 个技能
- `data/statuses/*.tres` — ~12 个状态
- `data/phases/*.tres` — 10 个化势

**修改文件**:
- `scenes/unit/unit.gd` — 新增 `@export var unit_data: UnitData`

**验证**: Godot 编辑器打开 .tres 检查字段正确

---

### Phase 1: CombatStats + 属性系统 + 状态栏

**目标**: 单位有血量和属性，状态栏显示单位信息+技能按钮。

**创建文件**:
- `scripts/combat/combat_stats.gd` — 运行时状态（HP、AP、属性、statuses）
- `scripts/combat/element_system.gd` — 属性附着/消耗/回补算法

**修改文件**:
- `scenes/unit/unit.gd` — `var combat_stats: CombatStats`，`_ready()` 中从 unit_data 初始化
- `scenes/ui/status_bar.gd` — 重构为左右布局:
  - 左侧: 角色名、HP、AP、属性、状态；非主角额外显示攻击/辅助/交互次数
  - 右侧: 技能按钮列表（仅当前可操作的己方单位），AP 不足或次数用尽时灰显
  - `show_unit(unit: Unit, is_active: bool)` — is_active 控制是否显示技能按钮
  - `signal skill_button_pressed(skill: SkillData)` — 技能按钮点击信号
- `scenes/levels/base_level/base_level.gd` — 点击单位更新状态栏，点击空地回退主角

**关键文件**: `unit.gd`, `combat_stats.gd`, `element_system.gd`, `status_bar.gd`
**验证**: 点击不同单位状态栏变色+显示正确信息，己方单位显示技能按钮
**依赖**: Phase 0

---

### Phase 2: AP 制移动 + 输入状态机 + 命令函数

**目标**: 移动消耗 AP 而非固定 movement_points，输入改为显式状态机，通过命令函数解耦输入。

在玩家使用鼠标预选移动落脚位置的时候，需要显示其若移动到该点所消耗和剩余的AP

**修改文件**:
- `scenes/levels/base_level/move_overlay.gd` — 新增 `show_range_ap()`，AP 预算 Dijkstra
- `scenes/levels/base_level/base_level.gd`:
  - `_unhandled_input` 重构为 InputState enum 状态机
  - 新增命令函数: `preview_cell()`, `confirm_cell()`, `cancel_action()`, `select_skill()`, `end_unit_turn()`
  - 鼠标事件只调用命令函数，不直接处理逻辑
- `scenes/unit/unit.gd` — movement_points getter 兼容旧版（读 combat_stats.ap_current）

**关键改动**:
- 每格消耗 = `combat_stats.move_cost_per_tile + movement_manager.get_extra_ap_cost(cell)` + 状态修正
- 移动后扣 AP，AP 未尽时重新显示 ActionPanel
- `preview_cell()` 在 TARGETING_MOVE 时更新路径预览 + 显示预计消耗/剩余 AP
- `preview_cell()` 在 TARGETING_SKILL 时叠加显示 effect_offsets
- 旧 `show_range()` 保留兼容

**验证**: 移动扣 AP，多次移动，等待结束回合；通过代码调用 `confirm_cell()` 验证命令函数可用
**依赖**: Phase 1

---

### Phase 3: 伤害核心 + 属性交互

**目标**: 基础伤害计算、属性对消、化势/逆势/同气判定。

**创建文件**:
- `scripts/combat/phase_table.gd` — 化势查找表（10 条化势 + 逆势规则）
- `scripts/combat/combat_resolver.gd` — `resolve_hit()` 纯函数

**伤害流水线**:
```
1. base_damage = base_atk * damage_ratio
2. phase_info = PhaseTable.lookup(skill_element, target_element)
3. final_damage = round(base_damage * phase_multiplier) + phase_bonus
4. 遍历攻击方 statuses 修正 (weakened)
5. 遍历目标 statuses 修正 (brittle)
6. ElementSystem.apply_skill_element() — 属性对消/附着
7. 化势触发的状态施加
```

**属性交互（已在 ElementSystem 中实现）**:
- 同气: 不消耗、不改变
- 化势/逆势/普通异属性: 走属性量对消
- 无属性攻击: 不消耗目标属性
- 有属性→无属性: 直接附着

**验证**: debug 场景中验证各种属性碰撞组合、伤害修正
**依赖**: Phase 1

---

### Phase 4: 技能执行与选择 UI

**目标**: 玩家可以选择并使用技能攻击敌人。

**创建文件**:
- `scripts/combat/skill_targeting.gd` — Node2D，技能范围双层预览
- `scripts/combat/skill_executor.gd` — 技能执行流水线

**skill_targeting 双层 Overlay**:

复用 move_overlay 的菱形绘制方式，用不同颜色区分两层：

| 层 | 含义 | 颜色 |
|----|------|------|
| 释放点范围 (cast_offsets) | 玩家可选择的释放点 | 蓝色半透明 |
| 应用范围 (effect_offsets) | 鼠标悬停释放点时显示的实际影响区域 | 红色/绿色半透明 |

应用范围颜色根据技能类型区分：
- `ATTACK` → 红色（伤害区域）
- `ASSIST` → 绿色（增益区域）
- `INTERACT` / `ASSIST_INTERACT` → 黄色（交互区域）

**交互流程**:
1. 玩家选择技能 → 显示蓝色 cast_offsets 范围
2. 鼠标悬停在某个释放点上 → 以该点为原点叠加显示 effect_offsets（红/绿/黄）
3. 点击确认释放点 → 收集 effect_offsets 范围内的合法目标 → 执行技能

**目标筛选**:
- `ATTACK`: effect_offsets 范围内所有**敌方**单位
- `ASSIST`: effect_offsets 范围内所有**友方**单位
- `INTERACT`: effect_offsets 范围内的**地块**（勘测点等）

**修改文件**:
- `scenes/ui/action_panel.gd` — 显示技能按钮（AP 不足灰显），传递 SkillData

**skill_executor 流程**:
```
1. 验证 AP 足够
2. 收集 effect_offsets 范围内的合法目标
3. 扣 AP + 更新回合计数器
4. 对每个目标: combat_resolver.resolve_hit()
5. 应用伤害
6. 应用属性变换
7. 施加状态
8. 处理 extra_effect (击退/拖拽/勘测等)
9. 发射信号
```

**验证**: 使用各种技能，验证伤害/属性/状态/击退
**依赖**: Phase 2, Phase 3

---

### Phase 5: 状态效果生命周期

**目标**: 状态按触发时机正确生效和消退。

**触发时机**:
- `turn_start`: AP 恢复修正 (cold_damp)、属性回补跳过 (silt_lock, smothered)
- `turn_end`: DoT 结算 (rend, scorch_mark)
- `on_move`: 移动消耗修正 (fracture_step, slowed_step, hindered_step, overgrow_bind)
- `on_hit`: 攻击方修正 (weakened)
- `on_hit_received`: 受击方修正 (brittle, open_fissure)

**每触发点遍历**:
```gdscript
for s in statuses:
    match s.status_id:
        "rend": ...
remaining_turns -= 1, 移除过期, trigger_once 处理
```

**验证**: 状态正确施加、生效、消退
**依赖**: Phase 4

---

### Phase 6: 回合生命周期完善

**目标**: 完整的回合开始/结束流程。

**回合开始（按队伍顺序: hero → enemy → ally_support）**:
1. AP 恢复至上限
2. 状态 turn_start 遍历
3. **敌方固有属性回补** `ElementSystem.refresh_innate_element()`（如有 silt_lock 则跳过）
4. 重置回合计数器

**回合结束**:
1. 状态 turn_end 遍历（DoT）
2. 休息回复: `ceil(remaining_ap / ap_max * max_hp * 10%)`，上限 `ceil(max_hp * 12%)`
3. 地形结束效果

**验证**: AP 恢复、DoT、休息回复、属性回补
**依赖**: Phase 5

---

### Phase 7: 地形效果

**目标**: 浅水、激流、坍岸等特殊地格效果。

**新增 TileType 子类**:
- `ShallowWaterTile` — 额外消耗 4 AP，结束行动时获得 1 层水属性
- `RapidWaterTile` — 不可主动停留，被击退进入时受 12 无属性伤害 + 沿流向位移 1 格
- `CollapsedBankTile` — 额外消耗 6 AP，不可勘测，被击退时额外后退 1 格

**TileType 新增方法**:
- `get_extra_ap_cost() -> int`
- `can_stop() -> bool`
- `is_surveyable() -> bool`
- `on_end_turn(entity: Node2D)`

**工具函数**: `resolve_forced_movement()` — 击退/拖拽通用

**验证**: 浅水附着水属性、激流伤害+位移、坍岸击退加成
**依赖**: Phase 4（击退需要技能系统）

---

### Phase 8: AI 系统

继续随机移动

---

### Phase 9: 关卡配置系统 + 第一关组装

**目标**: 数据驱动的关卡配置，无代码拼关卡。

**创建文件**:
- `scripts/data/level_config.gd` — LevelConfig Resource
- `scripts/data/team_config.gd` — TeamConfig Resource
- `scripts/data/wave_config.gd` — WaveConfig + SpawnEntry Resource
- `scripts/combat/battle_manager.gd` — 行动循环、波次刷怪、胜负判定
- `data/levels/chapter1_stage1.tres` — 第一关配置

**BattleManager 职责**:
- 从 LevelConfig 读取配置
- 波次刷怪（按回合触发）
- 胜利/失败条件检查
- 发射信号给 BaseLevel

**第一关配置**:
- 5 个波次，共 8 个敌人
- 胜利: 3 勘测点 + 相水定址 + 1 测量工撤离
- 失败: 李春死亡 / 测量工全死 / 超 10 回合

**验证**: 完整第一关流程
**依赖**: 全部前置

---

### Phase 10: UI 反馈 + 关卡结算

**目标**: 战斗体验打磨。

- 伤害弹字（含化势名称）
- 单位头顶 HP 条
- 化势触发提示
- 4 选 1 成长界面
- `data/growth/stage1_options.tres`

**验证**: 完整流程 + 视觉反馈
**依赖**: Phase 9

---

## 验证方式

1. **debug 场景**: 手动放置不同属性单位，测试属性对消、伤害、状态
2. **集成测试**: test 关卡手动操作移动+攻击+技能
3. **关卡配置测试**: 纯 Inspector 编辑 LevelConfig 配出测试关卡