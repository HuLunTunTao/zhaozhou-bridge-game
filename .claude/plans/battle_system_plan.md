# 五行流转战斗系统 — 实现方案

## Context

项目"安济桥成"是 Godot 4.6 等距战棋游戏。当前已有：回合制队伍切换、Dijkstra 寻路移动、地形消耗、特殊地块事件、ActionPanel UI。**但完全没有战斗系统**——无攻击、无技能、无血量、无伤害。

设计文档 `artbook/数值.md` 定义了"五行流转"战斗机制：AP系统、五行属性附着与化势反应、技能系统、状态效果、敌方AI、第一关完整配置。

**元素反应机制**（化势/逆势/同气等）较复杂，已拆分至独立文档：`artbook/element_reaction_plan.md`。

---

## 重构前提：player → unit 统一化

### 当前问题

- 单位脚本叫 `player.gd`，场景节点分为 `Entities/Players` 和 `Entities/Enemies` 两个容器
- base_level.gd 中多处变量名为 `player`、`player_selected`，混淆了"主角"和"单位"概念
- 不同阵营的单位本质上是同一个东西，不应分开管理

### 重构方案

1. **`player.gd` → `unit.gd`**，`class_name` 改为 `Unit`
2. **场景结构**：`Entities/Players` + `Entities/Enemies` 合并为 **`Entities/Units`**，所有单位放在同一个节点下
3. **base_level.gd 变量重命名**：
   - `player` → `hero`（专指李春，用于快捷访问）
   - `player_selected` → `unit_selected`
   - `players_container` / `enemies_container` → `units_container`
4. **base_level.tscn 场景树调整**：
   ```
   Entities/
     Units/        <- 所有单位统一放这里
       LiChun      <- 设计师在编辑器中放置
       Worker1
       Worker2
       Craftsman1
       Enemy1
       Enemy2
   ```
5. 单位的阵营由 `unit_data.camp` 或 `get_teams_config()` 决定，不由场景树位置决定

---

## 核心设计理念：状态列表 + 遍历结算

**每个单位持有一个 `statuses: Array[StatusInstance]` 列表**，所有 buff/debuff 统一存储。每次行动时遍历该列表计算最终结果。

- 时间复杂度 O(n)，n 为单位身上状态数（战棋场景通常 < 10）
- buff 和 debuff 是同一个 StatusInstance 对象，仅效果不同
- 按触发时机过滤（turn_start / turn_end / on_move / on_hit / on_hit_received）
- 无需事件系统或观察者模式，简单直接，易于调试

```gdscript
class StatusInstance:
    var status_id: String        # "rend", "brittle", ...
    var remaining_turns: int
    var source_base_atk: float   # 施术者攻击力（DoT 需要）
    var trigger_once: bool       # 脆裂等一次性触发
    var triggered: bool = false
```

结算时遍历：

```gdscript
# 移动消耗修正
func get_effective_move_cost(base_cost: int) -> int:
    var cost = base_cost
    for s in statuses:
        match s.status_id:
            "fracture_step": cost += 4
            "slowed_step", "hindered_step": cost += 2
    return cost

# 伤害修正
func apply_damage_modifiers(damage: float, is_attacker: bool) -> float:
    for s in statuses:
        match s.status_id:
            "weakened" when is_attacker: damage *= 0.8
            "brittle" when not is_attacker and not s.triggered:
                damage *= 1.2
                s.triggered = true
    return damage
```

---

## 状态栏：动态显示单位信息

### 需求

下方状态栏显示最近点击的单位的状态信息。背景颜色区分阵营：

| 显示对象 | 背景颜色 |
|---------|---------|
| 主角（李春） | 蓝色 |
| 其他友方单位 | 浅绿色 |
| 敌方单位 | 浅红色 |
| 未选中/点击空地 | 回退显示主角（蓝色） |

### 实现

- `status_bar.gd` 重构：新增 `show_unit(unit: Unit)` 方法，根据 unit 的 camp/faction 切换背景色
- 显示内容：名称、HP/MaxHP、AP/MaxAP、当前附着属性、状态效果列表
- 点击任意单位（无论敌我）都更新状态栏；点击空地回退到主角
- StatusBar 的父节点 `StatusPanel` 是 PanelContainer，改其 `StyleBoxFlat.bg_color` 即可

```gdscript
# status_bar.gd 新增
const COLOR_HERO := Color(0.2, 0.3, 0.7, 0.8)     # 蓝色
const COLOR_ALLY := Color(0.3, 0.7, 0.3, 0.8)     # 浅绿
const COLOR_ENEMY := Color(0.7, 0.3, 0.3, 0.8)    # 浅红

func show_unit(unit: Unit) -> void:
    var color := COLOR_HERO
    if unit.combat_stats:
        match unit.combat_stats.camp:
            "ally": color = COLOR_ALLY if not unit.combat_stats.is_hero else COLOR_HERO
            "enemy": color = COLOR_ENEMY
    _set_panel_color(color)
    _update_fields(unit)
```

---

## 关卡设计友好化：让非程序员也能拼关卡

### 设计目标

关卡设计师（Godot 水平不高）只需做两件事：
1. **在 Godot 编辑器中拖放单位到地图上**（位置会自动吸附到最近 tile）
2. **在一个集中的配置文件/Resource 中编辑关卡数据**

### 关卡设计师的工作流

#### 第一步：放置单位（编辑器内）

设计师在关卡场景的 `Entities/Units/` 下添加 Unit 节点。每个 Unit 节点只需在 Inspector 中设置：

```
@export var unit_data: UnitData    <- 从下拉菜单选一个 .tres（如 hero_li_chun.tres）
@export var unit_color: Color      <- 可选，调颜色区分
```

运行时 BaseLevel 自动：吸附到最近 tile → 从 unit_data 初始化 combat_stats → 注册到队伍

#### 第二步：编辑关卡配置（单个 Resource 文件）

每个关卡一个 `LevelConfig` Resource（.tres），设计师在 Inspector 中编辑：

```gdscript
# scripts/data/level_config.gd
class_name LevelConfig
extends Resource

## 队伍配置 — 设计师填单位节点名 + 阵营 + 控制方式
@export var teams: Array[TeamConfig] = []

## 波次配置 — 哪个回合刷什么敌人、在哪个位置
@export var waves: Array[WaveConfig] = []

## 胜利条件
@export var victory_conditions: Array[String] = []  # 如 ["survey_3_points", "confirm_bridge", "evacuate_worker"]

## 失败条件
@export var fail_conditions: Array[String] = []  # 如 ["hero_dead", "all_workers_dead", "turn_limit_10"]

## 关卡特殊地块（勘测点位置等）
@export var special_tile_configs: Array[SpecialTileConfig] = []

## 结算成长选项
@export var growth_options: Array[GrowthOptionData] = []
```

```gdscript
# TeamConfig Resource
class_name TeamConfig
extends Resource

@export var team_name: String
@export var faction: String             # "ally" / "enemy"
@export var controller: String          # "player" / "ai"
@export var unit_node_names: Array[String] = []  # 场景中的节点名，如 ["LiChun", "Worker1"]
```

```gdscript
# WaveConfig Resource
class_name WaveConfig
extends Resource

@export var trigger_turn: int           # 第几回合触发
@export var spawn_entries: Array[SpawnEntry] = []

# SpawnEntry
class_name SpawnEntry
extends Resource

@export var unit_data: UnitData         # 要刷的单位数据
@export var spawn_cell: Vector2i        # 刷出位置
@export var team_name: String           # 加入哪个队伍
```

#### 第三步（可选）：关卡脚本

大部分关卡只需继承 BaseLevel + 挂一个 LevelConfig，不写代码。
只有需要特殊逻辑（如过场剧情触发）的关卡才写脚本。

```gdscript
# 典型的关卡脚本（无特殊逻辑时甚至可以为空）
extends BaseLevel

@export var level_config: LevelConfig

func _on_level_ready() -> void:
    _apply_level_config(level_config)  # BaseLevel 提供此方法
```

### 设计师不需要接触的部分

| 不用管的 | 由系统处理 |
|---------|----------|
| 单位吸附到 tile | BaseLevel._ready() 自动完成 |
| 队伍初始化 | BaseLevel 从 LevelConfig 读取 |
| 波次刷怪 | BattleManager 按 WaveConfig 自动执行 |
| 胜负判定 | BattleManager 按条件字符串自动检查 |
| 伤害/状态/化势 | combat 系统全自动 |
| AI 行为 | UnitData.ai_type 指定，AI 系统自动执行 |

---

## 技能集中存储

所有技能以 SkillData Resource (.tres) 形式存储在 `data/skills/` 目录下：

```
data/skills/
  # 李春技能
  lc_rule_strike.tres          # 规尺击
  lc_wedge_bank_probe.tres     # 木楔勘岸
  lc_cast_stone_arrest_flow.tres  # 投石遏流
  lc_read_water_fix_site.tres  # 相水定址
  lc_pile_bind_wave.tres       # 束桩缓波（成长获得）

  # 测量工技能
  sw_staff_end_strike.tres     # 尺梢击
  sw_field_measure_site.tres   # 踏勘量址

  # 工匠技能
  cg_mallet_strike.tres        # 杵槌击
  cg_guard_the_works.tres      # 捍作护行

  # 敌方技能
  dc_hidden_current_lunge.tres # 伏流扑袭
  wp_spiral_pull.tres          # 回漩牵汲
  bmw_crumbling_bank_crush.tres # 坍岸扑压
  dlp_drifting_timber_crash.tres # 漂槎冲岸
```

### SkillData Resource 定义

```gdscript
class_name SkillData
extends Resource

@export var skill_id: String
@export var skill_name: String
@export var skill_type: Enums.SkillType  # ATTACK / ASSIST / INTERACT / ASSIST_INTERACT
@export var cast_range: int
@export var area_shape: Enums.AreaShape  # SINGLE / CROSS / LINE
@export var area_radius: int = 0
@export var ap_cost: int
@export var damage_ratio: float
@export var damage_element: Enums.Element
@export var attach_amount: int = 0
@export var target_rule: Enums.TargetRule  # ENEMY / ALLY / SELF / TILE
@export var extra_effect_id: String = ""   # 击退/拖拽/完成勘测等
@export var duration_turns: int = 0
@export var cooldown_turns: int = 0
@export_multiline var description: String = ""
```

UnitData 通过 `skills: Array[SkillData]` 引用技能，设计师在 Inspector 中从下拉列表选择。

---

## 架构总览

```
scripts/data/          <- 数据定义 (Resource 脚本)
  enums.gd             <- Element, SkillType, AreaShape 等枚举
  unit_data.gd         <- UnitData Resource
  skill_data.gd        <- SkillData Resource
  status_data.gd       <- StatusData Resource (状态模板)
  level_config.gd      <- LevelConfig Resource (关卡配置)
  team_config.gd       <- TeamConfig Resource
  wave_config.gd       <- WaveConfig / SpawnEntry Resource
  growth_option_data.gd <- GrowthOptionData Resource

scripts/combat/        <- 战斗逻辑
  combat_stats.gd      <- 运行时单位状态 (RefCounted), 持有 statuses 列表
  combat_resolver.gd   <- 纯函数: 伤害计算, 遍历状态修正
  skill_executor.gd    <- 技能执行: 验证->扣AP->计算->遍历状态->应用结果
  skill_targeting.gd   <- 技能范围高亮 (Node2D, 类似 move_overlay)
  battle_manager.gd    <- 行动循环, 波次刷怪, 胜负判定

scripts/elements/      <- 元素反应系统（详见 element_reaction_plan.md）
  element_system.gd    <- 属性附着/消耗/回补
  phase_table.gd       <- 化势查找表
  phase_data.gd        <- PhaseData Resource

scripts/ai/            <- AI 系统
  ai_controller.gd     <- AI 基类
  ai_flank_melee.gd    <- 暗涌
  ai_control_pull.gd   <- 水旋
  ai_zone_breaker.gd   <- 坍岸泥鬼
  ai_hazard_charge.gd  <- 浮木群

scenes/unit/           <- 单位场景（原 scenes/player/）
  unit.tscn
  unit.gd

data/                  <- .tres 数据文件
  units/               <- hero_li_chun.tres, survey_worker.tres ...
  skills/              <- 全部技能 .tres (集中存储)
  phases/              <- 化势反应 .tres
  statuses/            <- 状态效果 .tres
  levels/              <- 关卡配置 .tres (level1_config.tres ...)
```

---

## 信号与通信

```
信号向上: Unit -> BattleManager -> BaseLevel
调用向下: BaseLevel -> BattleManager -> CombatResolver

BattleManager 信号:
  - damage_dealt(source, target, amount, phase_info)
  - status_applied(target, status_id)
  - unit_died(unit)
  - unit_action_completed(unit, action)
  - unit_clicked(unit)          <- 用于状态栏更新

CombatResolver: 纯逻辑, 无信号, 返回结果结构体
BaseLevel: 监听 BattleManager 信号用于胜负判定/波次刷怪/剧情触发/状态栏更新
```

## 输入状态机 (Phase 2 重构)

```
IDLE -> (点击任意单位) -> 更新状态栏
IDLE -> (点击己方单位) -> UNIT_SELECTED
IDLE -> (点击空地) -> 状态栏回退显示主角
UNIT_SELECTED -> ActionPanel 显示
  -> "移动" -> TARGETING_MOVE (显示移动范围)
  -> 技能   -> TARGETING_SKILL (显示技能范围)
  -> "等待" -> 结束单位回合 -> IDLE
TARGETING_MOVE  -> (点击目标格) -> ANIMATING -> UNIT_SELECTED(AP剩余) / IDLE
TARGETING_SKILL -> (点击目标)   -> ANIMATING -> UNIT_SELECTED(AP剩余) / IDLE

注: 点击敌方单位只更新状态栏，不触发选中
```

---

## 分阶段实施

### Phase 0: 重构基础 + 数据层

**0a: player → unit 重构**
- `scenes/player/` → `scenes/unit/`，`player.gd` → `unit.gd`，class_name → `Unit`
- `base_level.tscn`: `Entities/Players` + `Entities/Enemies` → `Entities/Units`
- `base_level.gd`: 变量/方法重命名 (player→hero, players_container→units_container)
- 更新所有关卡场景引用

**0b: 数据 Resource 定义**
- 创建 `scripts/data/` 下所有 Resource 脚本: enums, unit_data, skill_data, status_data, level_config, team_config, wave_config
- 编写第一关全部 .tres 文件: `data/units/`(7), `data/skills/`(~12), `data/statuses/`(~12)

**验证**: 编辑器打开 .tres 检查字段，关卡场景能正常打开
**依赖**: 无

### Phase 1: CombatStats + 状态栏

**1a: CombatStats 与单位集成**
- `combat_stats.gd` (RefCounted): max_hp, current_hp, base_atk, ap_max, ap_current, move_cost_per_tile, 属性状态, statuses 列表
- `unit.gd` 新增 `@export var unit_data: UnitData` 和 `var combat_stats: CombatStats`
- `movement_points` getter 兼容旧版

**1b: 状态栏重构**
- `status_bar.gd`: 新增 `show_unit(unit)` 方法，按阵营切换 StatusPanel 背景色
- 点击任意单位 → 更新状态栏；点击空地 → 显示主角

**关键文件**: `scenes/unit/unit.gd`, `base_level.gd`, `scenes/ui/status_bar.gd`
**验证**: 点击不同单位状态栏变色，显示正确信息
**依赖**: Phase 0

### Phase 2: AP 制移动 + 输入状态机
移动改为扣 AP，移动消耗遍历状态列表修正。

- `move_overlay.gd` 新增 `show_range_ap()` 用 `ap_current` 做预算
- 每格消耗 = `combat_stats.get_effective_move_cost(tile_extra_cost)` (遍历 statuses)
- 移动完成扣 AP，AP 未尽重新显示 ActionPanel
- `_unhandled_input` 重构为显式状态机 (InputState enum)
- 旧 `show_range()` 保留兼容

**关键文件**: `move_overlay.gd`, `base_level.gd`
**验证**: 移动扣AP, 多次移动, 等待结束回合
**依赖**: Phase 1

### Phase 3: 伤害核心
纯战斗数学，遍历双方状态列表修正伤害。**不含元素反应**。

- `combat_resolver.gd`:
  1. base_atk * damage_ratio
  2. 遍历攻击方状态修正 (weakened)
  3. 预留化势接口 (phase_multiplier 默认 1.0)
  4. 遍历目标状态修正 (brittle)
  5. 返回 DamageResult 结构体

**验证**: debug 场景验证基础伤害 + 状态修正
**依赖**: Phase 0

### Phase 3.5: 元素反应系统
**详见 `artbook/element_reaction_plan.md`**

- 接入 combat_resolver 的化势接口
- element_system.gd, phase_table.gd, phase_data.gd

**依赖**: Phase 3

### Phase 4: 技能执行与选择
- `skill_targeting.gd`: 根据 cast_range/area_shape 高亮有效目标
- `skill_executor.gd`: 验证AP → 扣AP → combat_resolver → 元素反应 → 状态施加
- ActionPanel 显示技能按钮（AP 不足灰显）

**关键文件**: `action_panel.gd`, 新建 `skill_targeting.gd`, `skill_executor.gd`
**验证**: 使用技能, 验证伤害/属性/状态施加
**依赖**: Phase 2, Phase 3

### Phase 5: 状态效果生命周期
- 回合开始: 遍历 statuses tick turn_start
- 回合结束: 遍历 statuses tick turn_end (DoT)
- remaining_turns -= 1, 移除过期, trigger_once 处理

**依赖**: Phase 1, Phase 4

### Phase 6: 回合生命周期完善
- 回合开始: AP 恢复 + 状态修正 + 敌方属性回补
- 回合结束: 休息回复 `ceil(remaining_ap / ap_max * max_hp * 10%)`
- 固定顺序: hero → enemy → ally_support

**依赖**: Phase 1, Phase 5

### Phase 7: 地形效果
- ShallowWaterTile, RapidWaterTile, CollapsedBankTile
- `resolve_forced_movement()` 击退工具函数

**依赖**: Phase 1, Phase 3 (可并行)

### Phase 8: AI 系统
- ai_controller 基类 + 4 个 AI 模板
- 替换当前随机移动

**依赖**: Phase 4, Phase 7

### Phase 9: 第一关组装
- 使用 LevelConfig Resource 配置关卡
- 波次/胜负/特殊地块全部数据驱动

**依赖**: 全部前置

### Phase 10: UI 与关卡结算
- 单位 HUD, 伤害弹字, 化势名称
- 4选1 成长界面

**依赖**: Phase 9

---

## 移动系统重构细节

### TileType 改动

```gdscript
# tile_type.gd — 新增方法（旧接口保留）
func get_extra_ap_cost() -> int:       # 额外 AP 消耗，默认 0
func can_stop() -> bool:              # 能否主动停留，默认 true
func is_surveyable() -> bool:         # 能否勘测，默认 true
func on_end_turn(_entity: Node2D):    # 回合结束时触发
```

### MovementManager 新增接口

```gdscript
func get_extra_ap_cost(cell) -> int    # 额外 AP 消耗
func can_stop_on(cell) -> bool         # 能否停留
func on_end_turn(cell, entity)         # 回合结束地形效果
func is_surveyable(cell) -> bool       # 能否勘测
```

### move_overlay.gd 新增方法

```gdscript
func show_range_ap(tilemap, movement_manager, origin,
    ap_budget, move_cost_per_tile, occupied_cells) -> void
    # Dijkstra: cost = move_cost_per_tile + get_extra_ap_cost(nb)
    # 排除被占据格和不可停留格
```

---

## 验证方式

1. **单元测试**: debug 场景验证伤害公式、状态遍历修正
2. **集成测试**: 测试关卡手动操作移动+攻击+技能
3. **关卡设计测试**: 纯通过 Inspector 编辑 LevelConfig 配出一个测试关卡
4. **AI 测试**: 观察敌方行为
5. **完整流程**: 第一关从开局到通关
