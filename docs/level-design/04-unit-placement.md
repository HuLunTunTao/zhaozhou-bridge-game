# 04 -- 单位配置

> 本章介绍如何在关卡中放置战斗单位（Unit），配置角色数据和阵营颜色。

---

## 4.1 单位系统概述

本项目中的每个战斗角色都是一个 **Unit 节点**（`scenes/unit/unit.tscn` 的实例）。一个 Unit 节点包含：

```
Unit (Node2D)           ← unit.gd 脚本，class_name Unit
└── Visual (子场景)      ← AnimatedSprite2D，负责角色的视觉动画
```

Unit 节点有以下关键属性（在检查器中可见）：

| 属性 | 类型 | 说明 |
|------|------|------|
| `Movement Points` | int | 旧版移动点数，会被 unit_data 中的 AP 覆盖 |
| `Move Speed` | float | 角色移动动画速度（像素/秒），默认 100 |
| `Unit Data` | UnitData | **核心属性**：指向一个 `.tres` 数据文件 |
| `Unit Color` | Color | 角色叠加颜色，用于区分阵营 |

---

## 4.2 放置单位（详细步骤）

### 第一步：在 Entities/Units 下添加 Unit 节点

1. 在场景树中，展开 **Entities** 节点
2. 右键点击 **Units** 节点
3. 选择 **实例化子场景 (Instantiate Child Scene)**
4. 在文件对话框中导航到 `scenes/unit/`
5. 选择 `unit.tscn`
6. 点击 **打开 (Open)**

此时 Units 下会出现一个新的 Unit 子节点。

### 第二步：重命名单位节点

1. 在场景树中双击新添加的 Unit 节点名
2. 输入有意义的名称，例如：
   - 主角：`LiChun` 或 `Player`
   - 友方工匠：`Guard1`
   - 敌方暗涌：`Enemy1`
3. 按 Enter 确认

> ⚠️ 注意: 节点名称很重要，因为在关卡脚本的 `get_teams_config()` 中需要通过路径引用它们。例如 `$"Entities/Units/LiChun"`。

### 第三步：设置初始位置

单位的初始位置由其在 2D 视图中的放置位置决定。系统在启动时会自动将单位"吸附"到最近的格子中心。

**方法一：在 2D 视图中拖拽**

1. 在场景树中选中 Unit 节点
2. 在中央 2D 视图中，你会看到节点出现在画布上
3. 用鼠标左键拖拽它到你希望的位置
4. 不需要精确放到格子中心 -- 运行时会自动吸附

**方法二：在检查器中手动输入坐标**

1. 选中 Unit 节点
2. 在检查器面板中找到 **Transform** 部分
3. 在 **Position** 属性中输入像素坐标
4. 参考 [03-地形绘制](03-terrain-painting.md) 中的坐标转换公式来计算

> 💡 提示: 方法一更直观，推荐优先使用。只要大致放在正确的格子范围内，运行时会自动修正。

### 第四步：设置 Unit Data（角色数据）

这是最重要的配置。`Unit Data` 属性决定了角色的名字、生命值、攻击力、属性等一切战斗属性。

**方式 A：使用已有的数据文件（推荐）**

项目中已有以下单位数据文件（位于 `data/units/`）：

| 文件名 | 单位名 | 阵营 | 说明 |
|--------|--------|------|------|
| `hero_li_chun.tres` | 李春 | 己方 | 主角，无属性 |
| `craftsman_guard.tres` | 工匠 | 己方 | 辅助单位，每回合限 1 次移动+技能 |
| `survey_worker.tres` | 测量工 | 己方 | 护送目标 |
| `bank_mud_wraith.tres` | 坍岸泥鬼 | 敌方 | 土属性，区域破坏型 AI |
| `dark_current.tres` | 暗涌 | 敌方 | 水属性，侧翼近战型 AI |
| `drift_log_pack.tres` | 浮木群 | 敌方 | 木属性，冲锋型 AI |
| `whirl_pool.tres` | 水旋 | 敌方 | 水属性，控制拉拽型 AI |

使用方法：

1. 选中 Unit 节点
2. 在检查器面板中找到 **Unit Data** 属性
3. 从文件系统面板（左下）导航到 `data/units/`
4. 将对应的 `.tres` 文件拖拽到 Unit Data 属性上
5. 或者，点击 Unit Data 旁边的下拉箭头，选择 **快速加载 (Quick Load)**，搜索文件名

**方式 B：在场景中创建内联数据**

如果你需要一个现有数据文件的变体（例如一个更强的坍岸泥鬼），可以创建内联资源：

1. 选中 Unit 节点
2. 在检查器中点击 **Unit Data** 旁边的下拉箭头
3. 选择 **新建 UnitData (New UnitData)**
4. 展开新创建的 UnitData 资源，手动填写各个字段（参见下方字段说明）

> ⚠️ 注意: 内联资源只存在于当前场景文件中，其他场景无法复用。如果你创建的是通用单位数据，建议另存为 `.tres` 文件放在 `data/units/` 中。

### 第五步：设置 Unit Color（阵营颜色）

`Unit Color` 用于给角色精灵叠加颜色，帮助玩家区分不同阵营。

1. 选中 Unit 节点
2. 在检查器中找到 **Unit Color** 属性
3. 点击颜色方块，打开颜色选择器
4. 选择颜色

推荐的阵营颜色方案（参照 test 关卡）：

| 阵营 | 颜色 | RGBA 值 |
|------|------|---------|
| 主角/玩家 | 金黄色 | `(1.0, 0.85, 0.0, 1.0)` |
| 友方 | 绿色 | `(0.2, 0.85, 0.35, 1.0)` |
| 敌方 | 红色 | `(0.9, 0.2, 0.2, 1.0)` |

> 💡 提示: Unit Color 设置后会在编辑器中立即预览（因为 unit.gd 使用了 `@tool` 注解）。你可以直接在 2D 视图中看到颜色效果。

---

## 4.3 UnitData 字段详解

当你需要创建新的单位数据或理解现有数据时，参考以下字段说明：

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `unit_id` | String | "" | 单位唯一标识符，如 `"hero_li_chun"` |
| `unit_name` | String | "" | 显示名称，如 `"李春"` |
| `camp` | Camp 枚举 | ALLY | 阵营：`ALLY`(己方) 或 `ENEMY`(敌方) |
| `max_hp` | int | 100 | 最大生命值 |
| `base_atk` | int | 10 | 基础攻击力 |
| `ap_max` | int | 100 | 行动力上限 |
| `move_cost_per_tile` | int | 10 | 每格移动消耗的行动力 |
| `move_limit` | int | -1 | 每回合移动次数上限（-1 = 无限制） |
| `skill_limit` | int | -1 | 每回合技能使用次数上限（-1 = 无限制） |
| `innate_element` | Element 枚举 | NONE | 固有属性 |
| `innate_element_amount` | int | 0 | 固有属性层数 |
| `ai_type` | String | "" | AI 行为类型（敌方单位使用） |
| `is_escort_target` | bool | false | 是否为护送目标（被击败则关卡失败） |
| `skills` | Array[SkillData] | [] | 技能列表（最多 5 个） |

### Element 枚举值

| 值 | 名称 | 中文 |
|----|------|------|
| 0 | NONE | 无属性 |
| 1 | METAL | 金 |
| 2 | WOOD | 木 |
| 3 | WATER | 水 |
| 4 | FIRE | 火 |
| 5 | EARTH | 土 |

### Camp 枚举值

| 值 | 名称 | 中文 |
|----|------|------|
| 0 | ALLY | 己方 |
| 1 | ENEMY | 敌方 |

### AI 类型（ai_type）

现有的 AI 行为模板：

| ai_type 值 | 中文名 | 行为描述 |
|------------|--------|----------|
| `""` | 无 | 不使用 AI（玩家控制单位） |
| `"zone_breaker"` | 区域破坏 | 优先攻击区域内目标 |
| `"flank_melee"` | 侧翼近战 | 绕路攻击侧翼 |
| `"hazard_charge"` | 冲锋 | 直线冲向目标 |
| `"control_pull"` | 控制拉拽 | 将目标拉入不利位置 |

> 💡 提示: AI 系统当前为初步实现（随机移动一步），ai_type 字段用于未来完善。但数据应提前填写正确。

---

## 4.4 技能装配

每个单位最多可以装配 **5 个技能**。技能数据以 `.tres` 文件形式存放在 `data/skills/` 中。

### 在 UnitData 中添加技能

1. 选中 Unit 节点，在检查器中展开 **Unit Data** 资源
2. 找到 **Skills** 数组属性
3. 点击 Skills 旁边的数字输入框，设置数组大小（例如输入 `3` 表示 3 个技能）
4. 展开数组，每个元素都是一个技能槽
5. 将 `data/skills/` 中的 `.tres` 文件拖拽到对应的技能槽上

### 现有技能一览

**李春专属技能：**

| 文件 | 技能名 | 类型 | AP消耗 | 说明 |
|------|--------|------|--------|------|
| `lc_rule_strike.tres` | 规尺击 | 攻击 | 20 | 近战，对无属性目标伤害x1.15 |
| `lc_cast_stone_arrest_flow.tres` | 投石遏流 | 攻击 | 35 | 远程土属性，击退1格 |
| `lc_pile_bind_wave.tres` | 桩束波 | 攻击 | -- | -- |
| `lc_read_water_fix_site.tres` | 观水定址 | -- | -- | -- |
| `lc_wedge_bank_probe.tres` | 楔岸探 | -- | -- | -- |

**工匠技能：**

| 文件 | 技能名 | 类型 | AP消耗 | 说明 |
|------|--------|------|--------|------|
| `cg_mallet_strike.tres` | 槌击 | 攻击 | -- | -- |
| `cg_guard_the_works.tres` | 捍作护行 | 辅助 | 30 | 赋予目标护持2回合 |

**测量工技能：**

| 文件 | 技能名 | 类型 | AP消耗 | 说明 |
|------|--------|------|--------|------|
| `sw_field_measure_site.tres` | 踏勘量址 | 交互 | 40 | 对未完成勘测点使用 |
| `sw_staff_end_strike.tres` | 杖尾击 | 攻击 | -- | -- |

**敌方技能：**

| 文件 | 技能名 | 所属 | 说明 |
|------|--------|------|------|
| `bmw_crumbling_bank_crush.tres` | 坍岸碎压 | 坍岸泥鬼 | -- |
| `dc_hidden_current_lunge.tres` | 暗涌突刺 | 暗涌 | -- |
| `dlp_drifting_timber_crash.tres` | 浮木冲撞 | 浮木群 | -- |
| `wp_spiral_pull.tres` | 旋涡拉拽 | 水旋 | -- |

> 💡 提示: 关于技能数据各字段的详细说明，请参见 [附录B-单位与技能参考表](appendix-creature-reference.md)。

---

## 4.5 多单位放置示例

以 test 关卡为例，一个包含三支队伍的配置：

### 场景树结构

```
Entities
└── Units
    ├── Player    ← 玩家队伍，金黄色，unit_data = hero_li_chun.tres
    ├── PlayerB   ← 玩家队伍，金黄色
    ├── Ally1     ← 队友队伍，绿色
    ├── Ally2     ← 队友队伍，绿色
    ├── Enemy1    ← 敌方队伍，红色
    └── Enemy2    ← 敌方队伍，红色
```

### 对应的关卡脚本

```gdscript
extends BaseLevel

func get_teams_config() -> Array:
    return [
        {
            "name": "玩家队伍",
            "faction": "好人",
            "controller": "player",
            "units": [
                $"Entities/Units/Player",
                $"Entities/Units/PlayerB",
            ],
        },
        {
            "name": "队友队伍",
            "faction": "好人",
            "controller": "player",
            "units": [
                $"Entities/Units/Ally1",
                $"Entities/Units/Ally2",
            ],
        },
        {
            "name": "贼人队伍",
            "faction": "坏人",
            "controller": "ai",
            "units": [
                $"Entities/Units/Enemy1",
                $"Entities/Units/Enemy2",
            ],
        },
    ]
```

> ⚠️ 注意: `$"Entities/Units/Player"` 中的路径必须与场景树中的节点名称完全一致。如果你重命名了单位节点，脚本中的引用也必须同步修改。

---

## 4.6 单位配置清单

每次放置新单位时，确认以下事项：

- [ ] 节点放在 `Entities/Units/` 下
- [ ] 节点名称有意义且与脚本中的引用一致
- [ ] `Unit Data` 属性已设置（拖拽了 `.tres` 文件或创建了内联资源）
- [ ] `Unit Color` 已设置为对应阵营的颜色
- [ ] 位置大致在正确的格子上（可以不精确）
- [ ] 在关卡脚本的 `get_teams_config()` 中添加了对该节点的引用

---

下一章: [05-相机设置](05-camera-setup.md) | 上一章: [03-地形绘制](03-terrain-painting.md)
