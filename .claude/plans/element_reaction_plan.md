# 五行流转 — 元素反应系统设计

## Context

本文档专门设计"五行流转"元素反应机制的实现方案。这是 `battle_system_plan.md` Phase 3.5 的展开。

设计依据: `artbook/数值.md` 第 1.5-1.8 节（属性附着规则）、第 3 节（化势）、第 3.4 节（状态池）。

---

## 1. 原神元素反应机制参考

在设计之前，先梳理原神（Genshin Impact）的元素系统作为参考，提取适用于回合制战棋的设计模式。

### 1.1 原神核心机制

| 概念 | 说明 |
|-----|------|
| **元素量 (Gauge Unit)** | 每次元素攻击附着一定"量"（1U/2U/4U），量会随时间衰减 |
| **底色 (Aura)** | 目标身上已附着的元素 |
| **触发 (Trigger)** | 新施加的元素，碰到底色触发反应 |
| **增幅反应** | 蒸发/融化：直接乘算当次伤害（1.5x/2.0x），不产生独立伤害 |
| **剧变反应** | 超载/感电/扩散等：产生固定伤害，不吃攻击力/暴击 |
| **反应系数** | 不对称——正向蒸发消耗2U底色，逆向只消耗0.5U，同一对元素方向不同效果不同 |
| **内置冷却 (ICD)** | 限制同一技能多次触发反应的频率（回合制不需要） |
| **双底色** | 感电状态下水+雷共存，火攻击可同时触发蒸发+超载 |

### 1.2 可借鉴的设计模式

**1. 不对称反应** — 原神最核心的设计。五行流转已有类似设计：制势（克制方攻击）和承势（生方攻击）对同一对元素产生不同效果。这比原神更清晰，因为五行的相生相克是固定方向的。

**2. 元素量对消** — 原神用连续量(float)，五行流转用离散层数(int)。回合制用整数层更直观，每次反应消耗固定层数，设计师容易理解和平衡。

**3. 反应不二次触发** — 原神和五行流转都有这条规则：化势附加伤害不再触发二次化势。防止链式爆炸。

**4. 底色恢复** — 原神的元素自然衰减 vs 五行流转的"固有属性回补"。回合制中敌方每回合开始自动回补1层固有属性，比实时衰减更可控。

### 1.3 五行流转的独特优势（相对原神）

- **五行相生相克是对称环**：金克木克土克水克火克金 / 金生水生木生火生土生金，每个元素恰好有一个克制目标和一个生目标，不存在原神中"风/岩没有反应"的问题
- **制势 vs 承势双层反应**：同一对元素（如金+土）既有制势（金克木）也有承势（金承土），比原神的单一反应更有深度
- **回合制天然解决 ICD 问题**：每次行动就是一次独立的元素施加，不需要冷却机制
- **整数层数而非浮点量**：2层固有属性、1层附着、消耗1层...设计师和玩家都容易理解

---

## 2. 五行关系总表

### 2.1 五行克制环（统一设计名：化势）

攻击方克制目标方，触发制势化势：

```
金 → 木 → 土 → 水 → 火 → 金
metal → wood → earth → water → fire → metal
```

| 攻击属性 | 目标附着 | 化势名 | 倍率 | 附加效果 |
|---------|---------|--------|------|---------|
| 金 metal | 木 wood | 斫枝 | 1.20x | 裂伤 rend (2回合DoT) |
| 木 wood | 土 earth | 穿垠 | 1.20x | 陷裂 fracture_step (移动+4AP) |
| 土 earth | 水 water | 遏流 | 1.20x | 15%最大HP附加伤害 + 壅水 silt_lock |
| 水 water | 火 fire | 熄燎 | 1.20x | 攻衰 weakened (-20%伤害) |
| 火 fire | 金 metal | 熔铸 | 1.20x | 脆裂 brittle (+20%受伤一次性) |

### 

### 2.3 其他关系

| 关系 | 条件 | 效果 |
|-----|------|------|
| **逆势** adverse | 目标附着克制攻击属性 | 伤害 x0.80，无额外效果 |
| **同气** same | 攻击属性 = 目标附着 | 不触发反应，不消耗属性量，不改变附着 |
| **普通异属性** plain | 不属于以上任何 | 仅属性量对消 + 剩余附着，无额外效果 |
| **无属性→无属性** | 双方都无 | 伤害 x1.15 |
| **无属性→有属性** | 攻击无，目标有 | 正常伤害，不消耗目标属性量 |
| **有属性→无属性** | 攻击有，目标无 | 正常伤害，按技能附着属性 |

---

## 3. 元素反应结算流程

这是每次攻击命中后的完整结算流程：

```
on_hit(attacker, target, skill):

    ┌─ 1. 计算基础伤害
    │      base_damage = base_atk * damage_ratio
    │      (此处遍历攻击方状态修正，如 weakened)
    │
    ├─ 2. 判定元素关系
    │      输入: skill.damage_element, target.current_element
    │      输出: relation_type (dominant/follow/adverse/same/plain/non_element)
    │
    ├─ 3. 根据关系类型计算
    │      ├ dominant: damage *= phase.damage_multiplier
    │      │           + phase.bonus_damage (如遏流的15%最大HP)
    │      │           准备施加 phase.apply_status
    │      ├ follow:   damage *= phase.damage_multiplier
    │      │           准备施加 phase.apply_status
    │      │           处理 extra_element_consume / extra_effect
    │      ├ adverse:  damage *= 0.80
    │      ├ same:     无修正（跳过步骤4-6的属性操作）
    │      ├ plain:    无伤害修正
    │      └ non_element_vs_non: damage *= 1.15
    │
    │      (此处遍历目标方状态修正，如 brittle)
    │
    ├─ 4. 消耗目标属性量
    │      if relation != same and relation != non_to_element:
    │          消耗量 = skill.attach_amount + phase.extra_consume (如有)
    │          target.current_element_amount -= 消耗量
    │          if target.current_element_amount <= 0:
    │              target.current_element = NONE
    │              target.current_element_amount = 0
    │
    ├─ 5. 附着剩余属性
    │      if target.current_element == NONE and skill.attach_amount > 0:
    │          remaining = skill.attach_amount - 已消耗量
    │          if remaining > 0:
    │              target.current_element = skill.damage_element
    │              target.current_element_amount = remaining
    │
    └─ 6. 施加状态 (化势附加伤害不再触发二次化势)
           if phase.apply_status:
               target.statuses.append(StatusInstance.new(phase.apply_status, ...))
           if phase.extra_effect: (如焚延溅射)
               apply_extra_effect(...)
```

---

## 4. 敌方固有属性回补

每个敌方单位在自己行动开始前执行：

```gdscript
func refresh_innate_element(unit: Unit) -> void:
    var stats = unit.combat_stats
    # 被壅水 silt_lock 时跳过回补
    if stats.has_status("silt_lock"):
        return

    if stats.current_element != stats.innate_element:
        # 当前附着的不是固有属性 → 清除1层
        stats.current_element_amount -= 1
        if stats.current_element_amount <= 0:
            stats.current_element = Enums.Element.NONE
            stats.current_element_amount = 0
    elif stats.current_element == Enums.Element.NONE:
        # 无附着 → 回补1层固有属性
        stats.current_element = stats.innate_element
        stats.current_element_amount = 1
    # 当前附着 = 固有属性 → 不变
```

---

## 5. 数据结构设计

### 5.1 PhaseData Resource

```gdscript
# scripts/elements/phase_data.gd
class_name PhaseData
extends Resource

@export var phase_id: String                          # "metal_over_wood_fell_branch"
@export var attack_element: Enums.Element             # 攻击属性
@export var target_element: Enums.Element             # 目标附着属性
@export var phase_name: String                        # "斫枝"
@export var phase_category: Enums.PhaseCategory       # DOMINANT / FOLLOW
@export var damage_multiplier: float = 1.0            # 伤害倍率
@export var bonus_damage_type: String = ""            # "target_max_hp_ratio" / ""
@export var bonus_damage_value: float = 0.0           # 0.15 (15%)
@export var bonus_damage_cap_multiplier: float = 0.0  # attacker_base_atk * N
@export var extra_element_consume: int = 0            # 额外属性消耗
@export var apply_status_id: String = ""              # 施加的状态ID
@export var status_duration: int = 0                  # 状态持续回合
@export var carry_over_enabled: bool = false           # 剩余附着结转
@export_multiline var flavor_text: String = ""        # 游戏文案
```

### 5.2 PhaseTable — 化势查找表

```gdscript
# scripts/elements/phase_table.gd
class_name PhaseTable
extends RefCounted

# (attack_element, target_element) → PhaseData
var _table: Dictionary = {}

func _init() -> void:
    _load_all_phases()

func _load_all_phases() -> void:
    var dir := DirAccess.open("res://data/phases/")
    if dir == null:
        return
    for file in dir.get_files():
        if file.ends_with(".tres"):
            var phase: PhaseData = load("res://data/phases/" + file)
            var key := Vector2i(phase.attack_element, phase.target_element)
            _table[key] = phase

func get_phase(atk: Enums.Element, tgt: Enums.Element) -> PhaseData:
    return _table.get(Vector2i(atk, tgt), null)
```

### 5.3 ElementSystem — 元素判定核心

```gdscript
# scripts/elements/element_system.gd
class_name ElementSystem
extends RefCounted

## 克制关系: element → 被它克制的 element
const DOMINANT_MAP := {
    Enums.Element.METAL: Enums.Element.WOOD,
    Enums.Element.WOOD:  Enums.Element.EARTH,
    Enums.Element.EARTH: Enums.Element.WATER,
    Enums.Element.WATER: Enums.Element.FIRE,
    Enums.Element.FIRE:  Enums.Element.METAL,
}

enum Relation { DOMINANT, FOLLOW, ADVERSE, SAME, PLAIN, NON_VS_NON, NON_VS_ELEM, ELEM_VS_NON }

static func resolve_relation(atk_elem: Enums.Element, tgt_elem: Enums.Element) -> Relation:
    # 无属性规则
    if atk_elem == Enums.Element.NONE and tgt_elem == Enums.Element.NONE:
        return Relation.NON_VS_NON
    if atk_elem == Enums.Element.NONE:
        return Relation.NON_VS_ELEM
    if tgt_elem == Enums.Element.NONE:
        return Relation.ELEM_VS_NON

    # 同气
    if atk_elem == tgt_elem:
        return Relation.SAME

    # 制势: 攻击方克制目标方
    if DOMINANT_MAP.get(atk_elem) == tgt_elem:
        return Relation.DOMINANT

    # 逆势: 目标方克制攻击方 (即目标是攻击方的克星)
    if DOMINANT_MAP.get(tgt_elem) == atk_elem:
        return Relation.ADVERSE

    # 承势: 目标方是攻击方的"母" (生攻击方的元素)
    if FOLLOW_MAP.get(atk_elem) == tgt_elem:
        return Relation.FOLLOW

    # 以上都不是 → 普通异属性
    return Relation.PLAIN
```

### 5.4 Relation 判定速查

以金(Metal)为攻击方为例：

| 目标附着 | 关系 | 原因 |
|---------|------|------|
| 木 Wood | **制势** DOMINANT | 金克木 |
| 土 Earth | **承势** FOLLOW | 土生金 |
| 火 Fire | **逆势** ADVERSE | 火克金 |
| 金 Metal | **同气** SAME | 同属性 |
| 水 Water | **普通异属性** PLAIN | 无直接关系 |

完整 5x5 矩阵：

```
攻\目   金    木    水    火    土
金     同气  制势  普通  逆势  承势
木     普通  同气  承势  普通  制势
水     承势  普通  同气  制势  逆势
火     制势  承势  逆势  同气  普通
土     逆势  制势  制势  承势  同气
          ↑ 这里应仔细核对
```

精确核对（基于克制环 金→木→土→水→火→金 和相生环 金→水→木→火→土→金）：

```
攻\目    金      木      水      火      土
金      同气    制势    普通    逆势    承势
木      普通    同气    承势    普通    制势
水      承势    普通    同气    制势    逆势
火      制势    承势    逆势    同气    普通
土      逆势    普通    制势    承势    同气
```

---

## 6. 属性量对消与附着详细逻辑

```gdscript
## 执行属性量对消和附着
## 返回 Dictionary: { consumed: int, attached: int, new_element: Element, new_amount: int }
static func resolve_element_interaction(
    target_stats: CombatStats,
    atk_element: Enums.Element,
    atk_attach_amount: int,
    relation: Relation,
    extra_consume: int = 0
) -> Dictionary:
    var result := {
        "consumed": 0,
        "attached": 0,
        "new_element": target_stats.current_element,
        "new_amount": target_stats.current_element_amount,
    }

    # 同气: 不消耗、不改变
    if relation == Relation.SAME:
        return result

    # 无属性→有属性: 不消耗目标
    if relation == Relation.NON_VS_ELEM:
        return result

    # 有属性→无属性: 直接附着
    if relation == Relation.ELEM_VS_NON:
        if atk_attach_amount > 0:
            result.new_element = atk_element
            result.new_amount = atk_attach_amount
            result.attached = atk_attach_amount
        return result

    # 有属性→有属性: 对消
    var total_consume := atk_attach_amount + extra_consume
    var consumed := mini(total_consume, result.new_amount)
    result.consumed = consumed
    result.new_amount -= consumed

    if result.new_amount <= 0:
        # 目标属性被完全消耗
        var remaining := atk_attach_amount - consumed  # 注意这里不含 extra_consume
        if remaining > 0:
            result.new_element = atk_element
            result.new_amount = remaining
            result.attached = remaining
        else:
            result.new_element = Enums.Element.NONE
            result.new_amount = 0

    return result
```

---

## 7. 与 CombatResolver 的集成接口

CombatResolver 在伤害计算中调用元素系统：

```gdscript
# combat_resolver.gd 中的调用方式

func calculate_damage(attacker, target, skill) -> DamageResult:
    var base = attacker.combat_stats.base_atk * skill.damage_ratio

    # 遍历攻击方状态修正
    base = attacker.combat_stats.apply_damage_modifiers(base, true)

    var phase_mult := 1.0
    var bonus_damage := 0.0
    var status_to_apply := ""
    var status_duration := 0

    # 元素判定
    var relation := ElementSystem.resolve_relation(
        skill.damage_element, target.combat_stats.current_element)

    match relation:
        ElementSystem.Relation.DOMINANT, ElementSystem.Relation.FOLLOW:
            var phase := phase_table.get_phase(
                skill.damage_element, target.combat_stats.current_element)
            if phase:
                phase_mult = phase.damage_multiplier
                bonus_damage = _calc_bonus_damage(phase, attacker, target)
                status_to_apply = phase.apply_status_id
                status_duration = phase.status_duration
        ElementSystem.Relation.ADVERSE:
            phase_mult = 0.80
        ElementSystem.Relation.NON_VS_NON:
            phase_mult = 1.15
        _:
            pass  # SAME, PLAIN, NON_VS_ELEM, ELEM_VS_NON: 倍率 1.0

    var final_damage = roundi(base * phase_mult) + roundi(bonus_damage)

    # 遍历目标方状态修正
    final_damage = target.combat_stats.apply_damage_modifiers(final_damage, false)

    # 属性对消
    var elem_result := ElementSystem.resolve_element_interaction(
        target.combat_stats, skill.damage_element, skill.attach_amount,
        relation, phase.extra_element_consume if phase else 0)

    return DamageResult.new(final_damage, relation, phase, elem_result,
        status_to_apply, status_duration)
```

---

## 8. .tres 文件清单

```
data/phases/
  # 制势 (5个)
  metal_over_wood_fell_branch.tres
  wood_over_earth_pierce_bank.tres
  earth_over_water_arrest_flow.tres
  water_over_fire_quench_blaze.tres
  fire_over_metal_molten_temper.tres

  # 承势 (5个)
  metal_follow_earth_open_grit.tres
  wood_follow_water_creeping_growth.tres
  earth_follow_fire_smother_ash.tres
  water_follow_metal_quench_edge.tres
  fire_follow_wood_spread_scorch.tres
```

---

## 9. 实施步骤

### Step 1: 枚举与数据
- `Enums` 中添加 Element 和 PhaseCategory 枚举
- 创建 `PhaseData` Resource 脚本
- 编写 10 个 .tres 文件

### Step 2: ElementSystem 核心逻辑
- 实现 `resolve_relation()` — 纯静态函数
- 实现 `resolve_element_interaction()` — 属性量对消
- 实现 `refresh_innate_element()` — 敌方回补

### Step 3: PhaseTable
- 加载所有 PhaseData，提供查找接口

### Step 4: 集成到 CombatResolver
- 在伤害计算流程中插入化势判定
- 返回 DamageResult 包含化势信息

### Step 5: 验证
- debug 场景中覆盖测试：
  - 全部 5 种制势反应（伤害倍率 + 状态施加）
  - 全部 5 种承势反应
  - 逆势 (0.80x)
  - 同气 (无反应)
  - 普通异属性 (仅对消)
  - 无属性三种情况
  - 属性量对消正确性 (2层固有 vs 1层附着 → 剩1层)
  - 壅水 silt_lock 阻止回补
  - 化势附加伤害不触发二次化势

## 
