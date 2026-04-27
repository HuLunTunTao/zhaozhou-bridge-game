# 附录 B -- 单位与技能参考表

> 本附录汇总了项目中所有单位数据、技能数据、状态数据和化势（五行反应）数据，供关卡设计时快速查阅。

---

## B.1 单位数据一览

所有单位数据文件位于 `data/units/`。

### 己方单位（Camp: ALLY）

| 文件名 | unit_id | 名称 | HP | ATK | AP | 移动消耗 | 移动限制 | 技能限制 | 固有属性 | 备注 |
|--------|---------|------|------|------|------|----------|----------|----------|----------|------|
| `hero_li_chun.tres` | hero_li_chun | 李春 | 130 | 24 | 100 | 8 | 无限 | 无限 | 无 | 主角 |
| `craftsman_guard.tres` | craftsman_guard | 工匠 | 110 | 18 | 90 | 9 | 1次/回合 | 1次/回合 | 无 | 辅助单位 |
| `survey_worker.tres` | survey_worker | 测量工 | 80 | 12 | 85 | 10 | 1次/回合 | 1次/回合 | 无 | 护送目标 |

### 敌方单位（Camp: ENEMY）

| 文件名 | unit_id | 名称 | HP | ATK | AP | 移动消耗 | 固有属性 | 属性量 | AI 类型 |
|--------|---------|------|------|------|------|----------|----------|--------|---------|
| `bank_mud_wraith.tres` | bank_mud_wraith | 坍岸泥鬼 | 92 | 15 | 100 | 10 | 土 (EARTH) | 2 | zone_breaker |
| `dark_current.tres` | dark_current | 暗涌 | 68 | 17 | 100 | 10 | 水 (WATER) | 2 | flank_melee |
| `drift_log_pack.tres` | drift_log_pack | 浮木群 | 50 | 18 | 100 | 10 | 木 (WOOD) | 2 | hazard_charge |
| `whirl_pool.tres` | whirl_pool | 水旋 | 75 | 14 | 100 | 10 | 水 (WATER) | 2 | control_pull |

### 字段含义速查

| 字段 | 说明 |
|------|------|
| HP (max_hp) | 最大生命值 |
| ATK (base_atk) | 基础攻击力，技能伤害 = ATK x 技能倍率 |
| AP (ap_max) | 行动力上限，每回合开始时恢复至满 |
| 移动消耗 (move_cost_per_tile) | 每移动一格消耗的 AP |
| 移动限制 (move_limit) | 每回合可移动的次数（-1 = 无限） |
| 技能限制 (skill_limit) | 每回合可使用技能的次数（-1 = 无限） |
| 固有属性 (innate_element) | 单位自带的五行属性 |
| 属性量 (innate_element_amount) | 固有属性的初始层数 |
| 头像 (portrait) | Texture2D，7:9 比例，在状态栏左侧显示 |

---

## B.2 技能数据一览

所有技能数据文件位于 `data/skills/`。

### 李春技能

| 文件名 | skill_id | 名称 | 类型 | AP | 倍率 | 属性 | 附着 | 射程 | 影响范围 | 描述 |
|--------|----------|------|------|------|------|------|------|------|----------|------|
| `lc_rule_strike.tres` | lc_rule_strike | 规尺击 | 攻击 | 20 | 1.0 | 无 | 0 | 四邻(1格) | 单体 | 对无属性目标伤害x1.15 |
| `lc_cast_stone_arrest_flow.tres` | lc_cast_stone_arrest_flow | 投石遏流 | 攻击 | 35 | 0.95 | 土 | 2 | 菱形4格 | 单体 | 高抛远距，命中后击退1格 |
| `lc_pile_bind_wave.tres` | lc_pile_bind_wave | 束桩缓波 | 攻击 | 30 | 0.95 | 木 | 2 | 菱形2格 | 十字(含中心) | 近距，对目标周围十字施加迟滞2回合 |
| `lc_read_water_fix_site.tres` | lc_read_water_fix_site | 相水定址 | 辅助交互 | 30 | 0 | 无 | 0 | 菱形3格 | 十字(含中心) | 显示危险地格2回合，赋予稳步1回合 |
| `lc_wedge_bank_probe.tres` | lc_wedge_bank_probe | 木楔勘岸 | 攻击 | 25 | 1.0 | 木 | 1 | 四方向直线3格 | 单体 | 直射穿刺，用于触发木行化势 |

### 工匠技能

| 文件名 | skill_id | 名称 | 类型 | AP | 倍率 | 属性 | 描述 |
|--------|----------|------|------|------|------|------|------|
| `cg_mallet_strike.tres` | cg_mallet_strike | 杵槌击 | 攻击 | 25 | 1.0 | 金 | 铁杵近战，对木触发斫枝(×1.10+裂伤)，对土触发开砺(×1.05+剖隙) |
| `cg_guard_the_works.tres` | cg_guard_the_works | 捍作护行 | 辅助 | 30 | 0 | 无 | 赋予目标护持2回合 |

### 测量工技能

| 文件名 | skill_id | 名称 | 类型 | AP | 倍率 | 描述 |
|--------|----------|------|------|------|------|------|
| `sw_field_measure_site.tres` | sw_field_measure_site | 踏勘量址 | 交互 | 40 | 0 | 对未完成勘测点使用，完成勘测 |
| `sw_staff_end_strike.tres` | sw_staff_end_strike | 尺梢击 | 攻击 | 25 | 0.9 | 近战攻击 |

### 敌方技能

| 文件名 | skill_id | 名称 | 所属 | AP | 倍率 | 属性 | 附着 | 描述 |
|--------|----------|------|------|------|------|------|------|------|
| `bmw_crumbling_bank_crush.tres` | bmw_crumbling_bank_crush | 坍岸扑压 | 坍岸泥鬼 | 20 | 1.0 | 土 | 1 | 近战土属性攻击 |
| `dc_hidden_current_lunge.tres` | dc_hidden_current_lunge | 伏流扑袭 | 暗涌 | 20 | 0.95 | 水 | 1 | 近战水属性攻击 |
| `dlp_drifting_timber_crash.tres` | dlp_drifting_timber_crash | 漂槎冲岸 | 浮木群 | 20 | 1.0 | 木 | 1 | 直线冲锋攻击，击退1格 |
| `wp_spiral_pull.tres` | wp_spiral_pull | 回漩牵汲 | 水旋 | 25 | 0.9 | 水 | 2 | 远程水属性，拖拽1格 |

---

## B.3 技能类型说明

| 枚举值 | SkillType | 中文名 | 说明 | 目标选择规则 |
|--------|-----------|--------|------|-------------|
| 0 | ATTACK | 攻击 | 造成伤害的主动技能 | 只对**不同阵营**的单位生效 |
| 1 | ASSIST | 辅助 | 不造成伤害，为友方单位提供增益 | 只对**同阵营**的单位生效（排除自身） |
| 2 | INTERACT | 交互 | 与地图元素交互（如勘测点） | 对所有单位/地块生效 |
| 3 | ASSIST_INTERACT | 辅助交互 | 同时具有辅助和交互功能 | 对所有单位/地块生效 |

---

## B.4 技能范围说明

每个技能有两个范围参数：

### cast_offsets（释放点范围）

以施放者所在格为原点 `(0,0)` 的偏移列表。定义了技能可以选择哪些格子作为释放点。

常见模式：

| 模式 | 格子数 | 说明 | 示例 |
|------|--------|------|------|
| 四邻格 | 4 | 上下左右各1格 | `[(1,0),(-1,0),(0,1),(0,-1)]` |
| 菱形3格 | 24 | 曼哈顿距离1-3的所有格 | `OffsetPresets.diamond(1,3)` |
| 菱形2格 | 12 | 曼哈顿距离1-2的所有格 | `OffsetPresets.diamond(1,2)` |
| 菱形4格 | 40 | 曼哈顿距离1-4的所有格 | `OffsetPresets.diamond(1,4)` |
| 含自身菱形3格 | 25 | 曼哈顿距离0-3的所有格 | `OffsetPresets.diamond(0,3)` |
| 四方向直线 | 4xN | 上下左右各N格 | `OffsetPresets.lines_4dir(5)` |

### effect_offsets（影响区域）

以释放点为原点 `(0,0)` 的偏移列表。定义了技能实际影响哪些格子。

常见模式：

| 模式 | 格子数 | 说明 | 示例 |
|------|--------|------|------|
| 单体 | 1 | 仅影响释放点 | `[(0,0)]` |
| 十字(含中心) | 5 | 释放点及其上下左右 | `OffsetPresets.cross(1)` |
| 大十字(含中心) | 13 | 臂长3的十字 | `OffsetPresets.cross(3)` |
| 菱形2格(含中心) | 13 | 曼哈顿距离0-2 | `OffsetPresets.diamond(0,2)` |

### OffsetPresets 工具函数

`scripts/data/offset_presets.gd` 提供了便捷的范围生成函数：

| 函数 | 参数 | 说明 | 示例 |
|------|------|------|------|
| `SINGLE` | -- | 单体 `[(0,0)]` | `OffsetPresets.SINGLE` |
| `diamond(min_r, max_r)` | 最小/最大曼哈顿距离 | 菱形范围 | `OffsetPresets.diamond(1, 3)` = 1-3格菱形 |
| `cross(arm_length)` | 臂长 | 十字+中心 | `OffsetPresets.cross(1)` = 5格十字 |
| `line(direction, length)` | 方向, 长度 | 直线（不含原点） | `OffsetPresets.line(Vector2i(1,0), 4)` |
| `lines_4dir(length)` | 长度 | 四方向直线（不含原点） | `OffsetPresets.lines_4dir(3)` = 12格 |

---

## B.5 状态数据一览

所有状态数据文件位于 `data/statuses/`。

| 文件名 | status_id | 名称 | 持续回合 | 一次触发 | 描述 | 代码效果 |
|--------|-----------|------|----------|----------|------|----------|
| `brittle.tres` | brittle | 脆裂 | 2 | 是 | 下一次受到的伤害额外提高20% | 受击时倍率x1.2，触发后消失 |
| `cold_damp.tres` | cold_damp | 湿寒 | 2 | 否 | 下回合行动力恢复值降低15% | 回合开始时 AP -= ap_max*15% |
| `fracture_step.tres` | fracture_step | 陷裂 | 2 | 否 | 移动时前2格每格额外消耗4点行动力 | 移动每格额外+4 AP消耗 |
| `guarded_cover.tres` | guarded_cover | 护持 | 2 | 否 | 首次受到的伤害-16，不能被拖拽或击退超过1格 | （描述性，待完善） |
| `hindered_step.tres` | hindered_step | 迟滞 | 2 | 否 | 每移动1格额外消耗2点行动力 | 移动每格额外+2 AP消耗 |
| `open_fissure.tres` | open_fissure | 剖隙 | 2 | 否 | 受到击退/冲撞/地形撞击时额外承受施术者ATKx0.50的伤害 | （描述性，待完善） |
| `overgrow_bind.tres` | overgrow_bind | 蔓缚 | 2 | 否 | 最大可移动格数-1 | 移动范围减少1格 |
| `rend.tres` | rend | 裂伤 | 2 | 否 | 回合结束时失去施术者ATKx0.30的生命 | DoT：回合末 HP -= source_atk*30% |
| `scorch_mark.tres` | scorch_mark | 灼痕 | 2 | 否 | 回合结束时失去施术者ATKx0.25的生命 | DoT：回合末 HP -= source_atk*25% |
| `silt_lock.tres` | silt_lock | 壅水 | 3 | 否 | 行动开始时不执行固有属性回补 | 回合开始跳过属性回补 |
| `slowed_step.tres` | slowed_step | 迟步 | 1 | 否 | 每移动1格额外消耗2点行动力 | 移动每格额外+2 AP消耗 |
| `smothered.tres` | smothered | 闷熄 | 1 | 否 | 下回合开始时不能额外获得火属性量 | 回合开始跳过属性回补 |
| `steady_step.tres` | steady_step | 稳步 | 1 | 否 | 进入浅水额外消耗-4，本回合第一次被击退时距离-1 | （描述性，待完善） |
| `weakened.tres` | weakened | 攻衰 | 2 | 否 | 造成的伤害降低20% | 攻击时倍率x0.8 |

### 状态字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `status_id` | String | 状态唯一标识符 |
| `status_name` | String | 显示名称 |
| `duration_turns` | int | 持续回合数 |
| `trigger_once` | bool | 是否为一次性触发（触发后立即消失） |
| `description` | String | 效果描述 |

### 状态生命周期

1. **施加时**: 将 StatusInstance 加入目标的 `combat_stats.statuses` 列表
2. **回合开始时**: `process_turn_start()` 处理状态效果（如湿寒减AP、壅水跳过回补）
3. **回合结束时**: `process_turn_end()` 处理 DoT 伤害（裂伤、灼痕），然后 `_tick_statuses()` 将所有状态剩余回合-1，清除过期状态
4. **一次性状态**: 如脆裂，在触发后标记 `triggered = true`，下次 tick 时移除

---

## B.6 化势（五行反应）数据一览

所有化势数据文件位于 `data/phases/`。

> ⚠️ 注意: 如果你新增了化势 `.tres` 文件，**必须**同时在 `scripts/combat/phase_table.gd` 中注册路径，否则导出版中该化势不会被加载。详见 [B.11a 新增化势的完整流程](#b11a-新增化势的完整流程)。

### 相克化势（Dominant, category = 0）

五行相克产生的强力反应。

| 文件名 | phase_id | 名称 | 攻击属性 | 目标属性 | 伤害倍率 | 附加伤害 | 施加状态 | 描述 |
|--------|----------|------|----------|----------|----------|----------|----------|------|
| `metal_over_wood_fell_branch.tres` | metal_over_wood_fell_branch | 斫枝 | 金 | 木 | 1.1 | -- | 裂伤(2回合) | 金克木 |
| `wood_over_earth_pierce_bank.tres` | wood_over_earth_pierce_bank | 穿垠 | 木 | 土 | 1.05 | -- | 陷裂(2回合) | 木克土 |
| `earth_over_water_arrest_flow.tres` | earth_over_water_arrest_flow | 遏流 | 土 | 水 | 1.0 | 目标最大HPx15%(上限ATKx2.0) | 壅水(3回合) | 土克水 |
| `water_over_fire_quench_blaze.tres` | water_over_fire_quench_blaze | 熄燎 | 水 | 火 | 1.1 | -- | 攻衰(2回合) | 水克火 |
| `fire_over_metal_molten_temper.tres` | fire_over_metal_molten_temper | 熔铸 | 火 | 金 | 1.0 | -- | 脆裂(2回合) | 火克金 |

### 相生化势（Follow, category = 1）

五行相生产生的辅助反应。

| 文件名 | phase_id | 名称 | 攻击属性 | 目标属性 | 伤害倍率 | 施加状态 | 描述 |
|--------|----------|------|----------|----------|----------|----------|------|
| `water_follow_metal_quench_edge.tres` | water_follow_metal_quench_edge | 淬锋 | 水 | 金 | 1.05 | 湿寒(2回合) | 金生水 |
| `wood_follow_water_creeping_growth.tres` | wood_follow_water_creeping_growth | 滋蔓 | 木 | 水 | 1.0 | 蔓缚(2回合) | 水生木 |
| `fire_follow_wood_spread_scorch.tres` | fire_follow_wood_spread_scorch | 焚延 | 火 | 木 | 1.05 | 灼痕(2回合) | 木生火 |
| `earth_follow_fire_smother_ash.tres` | earth_follow_fire_smother_ash | 覆烬 | 土 | 火 | 1.0 | 闷熄(1回合) | 火生土 |
| `metal_follow_earth_open_grit.tres` | metal_follow_earth_open_grit | 开砺 | 金 | 土 | 1.05 | 剖隙(2回合) | 土生金 |

### 化势分类

| 枚举值 | PhaseCategory | 中文名 | 伤害倍率 | 说明 |
|--------|---------------|--------|----------|------|
| 0 | DOMINANT | 制势（相克） | 见上表 | 五行相克反应（金克木、木克土等） |
| 1 | FOLLOW | 承势（相生） | 见上表 | 五行相生反应（金生水、水生木等） |
| 2 | ADVERSE | 逆势 | x0.8 | 攻击方处于不利克制关系 |
| 3 | SAME | 同气 | x1.0 | 攻击属性 = 目标当前属性，不触发化势 |
| 4 | PLAIN | 普通 | x1.0 | 无特殊反应的异属性接触 |

### 特殊倍率：无属性加成

当攻击属性和目标属性都为 NONE（无属性）时，伤害倍率为 **x1.15**。这使得无属性攻击对无属性目标有额外加成。

### 五行相克关系图

```
     金 --克--> 木
     ^           |
     |           v
     火         土
     ^           |
     |           v
     木 <--克-- 水

  相克: 金->木->土->水->火->金
  相生: 金->水->木->火->土->金
```

---

## B.7 Element 枚举速查

| 枚举值 | 名称 | 中文 | .tres 文件中的数字 |
|--------|------|------|-------------------|
| 0 | NONE | 无属性 | 0 |
| 1 | METAL | 金 | 1 |
| 2 | WOOD | 木 | 2 |
| 3 | WATER | 水 | 3 |
| 4 | FIRE | 火 | 4 |
| 5 | EARTH | 土 | 5 |

> 提示: 在 `.tres` 文件中，属性以数字存储。例如 `innate_element = 5` 表示 `EARTH`（土）。在 Godot 编辑器的检查器中，你可以直接从下拉菜单中选择属性名称。

---

## B.8 属性系统机制

### 属性附着

技能命中后，如果 `attach_amount > 0` 且 `damage_element != NONE`，会在目标上附着属性：

| 情况 | 结果 |
|------|------|
| 目标无属性 | 直接附着技能属性 |
| 目标属性 = 技能属性（同气） | 不消耗、不改变 |
| 目标属性 != 技能属性（异属性碰撞） | 附着量 > 目标量：覆盖为技能属性（差值为新层数） |
| | 附着量 = 目标量：清除所有属性 |
| | 附着量 < 目标量：削减目标属性层数 |

### 固有属性回补

每回合开始时（除非被壅水/闷熄跳过）：

| 情况 | 结果 |
|------|------|
| 当前属性 = 固有属性 | 不变 |
| 当前无属性 | 开始回补（固有属性量+1） |
| 当前有外来属性残留 | 每回合消退1层 |

### 休息回复（回合结束时）

玩家队伍的单位在回合结束时，剩余 AP 可转化为生命恢复：

```
恢复量 = ceil(剩余AP / AP上限 * 最大HP * 10%)
上限 = ceil(最大HP * 12%)
```

> 提示: 这意味着保留一些 AP 不用完可以在回合末恢复少量 HP。这是鼓励玩家合理分配行动力的机制。

---

## B.9 AI 类型说明

| ai_type | 中文名 | 预期行为（待完善） |
|---------|--------|--------------------|
| `""` | 无 | 不使用 AI，玩家控制或无行动 |
| `"zone_breaker"` | 区域破坏 | 优先攻击区域内的目标，破坏防线 |
| `"flank_melee"` | 侧翼近战 | 绕过前排，从侧翼攻击 |
| `"hazard_charge"` | 冲锋 | 直线冲向最近的目标 |
| `"control_pull"` | 控制拉拽 | 将目标拉向不利位置（水中等） |

> 注意: 当前 AI 实现为占位逻辑（随机移动一步）。ai_type 字段为将来完善 AI 行为树预留。数据应提前按设计文档填写正确。

---

## B.10 SkillData 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| `skill_id` | String | 技能唯一标识符 |
| `skill_name` | String | 技能显示名称 |
| `skill_type` | SkillType | 技能类型（攻击/辅助/交互/辅助交互） |
| `ap_cost` | int | AP 消耗 |
| `damage_ratio` | float | 伤害倍率，最终伤害 = base_atk x damage_ratio |
| `damage_element` | Element | 技能的属性（用于触发化势） |
| `attach_amount` | int | 技能命中后附着到目标的属性层数 |
| `extra_effect_id` | String | 额外效果标识（如 `"knockback_1"` = 击退1格） |
| `duration_turns` | int | 效果持续回合数 |
| `cooldown_turns` | int | 技能冷却回合数 |
| `description` | String | 技能描述文本（显示在状态栏按钮的提示中） |
| `cast_offsets` | Array[Vector2i] | 释放点范围 |
| `effect_offsets` | Array[Vector2i] | 影响区域 |

### 常见 extra_effect_id

| ID | 效果 |
|----|------|
| `""` | 无额外效果 |
| `"non_element_bonus"` | 对无属性目标额外伤害x1.15 |
| `"knockback_1"` | 击退目标1格 |
| `"pull_1"` | 将目标拉向自身1格 |
| `"hindered_cross"` | 对十字范围施加迟滞 |
| `"guarded_cover"` | 赋予护持状态 |
| `"read_water"` | 显示危险地格 + 赋予稳步 |
| `"complete_survey"` | 完成勘测点 |

---

## B.11 PhaseData 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| `phase_id` | String | 化势唯一标识符 |
| `phase_name` | String | 化势显示名称 |
| `attack_element` | Element | 攻击方属性 |
| `target_element` | Element | 目标方当前属性 |
| `category` | PhaseCategory | 化势类型（相克/相生/逆势/同气/普通） |
| `damage_multiplier` | float | 伤害倍率修正 |
| `bonus_damage_type` | String | 附加伤害类型（`""` = 无, `"target_max_hp_ratio"` = 目标最大HP百分比） |
| `bonus_damage_value` | float | 附加伤害值（百分比时为 0.15 = 15%） |
| `bonus_damage_cap` | String | 附加伤害上限表达式（如 `"attacker_base_atk * 2.0"`） |
| `extra_element_consume` | int | 额外属性消耗量（覆烬消耗额外1层火属性） |
| `apply_status_id` | String | 触发时施加的状态 ID |
| `status_duration` | int | 施加状态的持续回合 |
| `flavor_text` | String | 化势的意境描述（五行哲学文案） |

---

## B.11a 新增化势的完整流程

当你需要添加一个新的化势（五行反应）时，必须完成**两个步骤**：创建 `.tres` 数据文件，然后在代码中注册路径。缺少任何一步都会导致化势无法生效。

### 为什么需要手动注册？

早期版本中，系统在启动时会自动扫描 `data/phases/` 目录下的所有 `.tres` 文件并加载。这在 Godot 编辑器中运行正常，但 **导出版（export build）中会失败**。

原因：Godot 导出时会将所有资源打包进 `.pck` 文件。打包后，`DirAccess.open("res://data/phases")` **无法列举目录内容**——这是 Godot 引擎的限制，不是 Bug。因此，我们改用了在代码中显式列出所有路径的方式，确保编辑器和导出版行为一致。

> ⚠️ 注意: 如果你只创建了 `.tres` 文件但忘记注册路径，化势在编辑器中 **也不会生效**（因为当前代码已不再扫描目录）。

### 第一步：创建化势数据文件（.tres）

1. 在 Godot 编辑器的 **文件系统 (FileSystem)** 面板中，导航到 `data/phases/`
2. 右键点击 `phases` 文件夹 → **新建资源 (New Resource)**
3. 在弹出的对话框中搜索 `PhaseData`，选中后点击 **创建 (Create)**
4. 给文件起一个有意义的名字，命名规则为：
   - 相克化势：`{攻击属性}_over_{目标属性}_{英文描述}.tres`
   - 相生化势：`{攻击属性}_follow_{目标属性}_{英文描述}.tres`
   - 例如：`fire_over_metal_molten_temper.tres`
5. 点击 **保存 (Save)**

接下来在检查器中填写各字段：

| 字段 | 说明 | 示例值 |
|------|------|--------|
| `phase_id` | 唯一标识符，与文件名一致（不含 `.tres`） | `"fire_over_metal_molten_temper"` |
| `phase_name` | 化势显示名称（中文，两字为佳） | `"熔铸"` |
| `attack_element` | 攻击方属性（下拉选择） | `FIRE` |
| `target_element` | 目标方属性（下拉选择） | `METAL` |
| `category` | 化势类型 | 相克选 `DOMINANT`，相生选 `FOLLOW` |
| `damage_multiplier` | 伤害倍率 | `1.0` ~ `1.1` |
| `bonus_damage_type` | 附加伤害类型，无则留空 | `""` 或 `"target_max_hp_ratio"` |
| `bonus_damage_value` | 附加伤害数值 | `0.0` 或 `0.15`（= 15%） |
| `bonus_damage_cap` | 附加伤害上限表达式，无则留空 | `""` 或 `"attacker_base_atk * 2.0"` |
| `extra_element_consume` | 额外属性消耗量 | `0` |
| `apply_status_id` | 触发时施加的状态 ID | `"silt_lock"` |
| `status_duration` | 状态持续回合数 | `2` |
| `flavor_text` | 五行意境描述文案 | `"土行加水，不争一时之急"` |

> 💡 提示: 各字段的详细定义见上方 [B.11 PhaseData 字段详解](#b11-phasedata-字段详解)。`attack_element` 和 `target_element` 的枚举值见 [B.7 Element 枚举速查](#b7-element-枚举速查)。

### 第二步：在 phase_table.gd 中注册路径（关键！）

这一步**必须做**，否则化势不会被加载。

1. 打开文件 `scripts/combat/phase_table.gd`
   - 在 Godot 编辑器中：双击文件系统面板中的 `scripts/combat/phase_table.gd`
   - 或在 VSCode 中：打开该文件
2. 找到 `_ensure_init()` 函数中的 `var paths` 数组（大约在第 36 行）
3. 在数组中添加你的新文件路径

修改前的代码大致如下：

```gdscript
static func _ensure_init() -> void:
    if _initialized:
        return
    _initialized = true
    var paths := [
        "res://data/phases/earth_over_water_arrest_flow.tres",
        "res://data/phases/earth_follow_fire_smother_ash.tres",
        "res://data/phases/fire_follow_wood_spread_scorch.tres",
        "res://data/phases/fire_over_metal_molten_temper.tres",
        "res://data/phases/metal_follow_earth_open_grit.tres",
        "res://data/phases/metal_over_wood_fell_branch.tres",
        "res://data/phases/water_follow_metal_quench_edge.tres",
        "res://data/phases/water_over_fire_quench_blaze.tres",
        "res://data/phases/wood_follow_water_creeping_growth.tres",
        "res://data/phases/wood_over_earth_pierce_bank.tres",
    ]
```

假设你新增了一个化势文件 `metal_over_fire_example.tres`，你需要在数组末尾加一行：

```gdscript
    var paths := [
        "res://data/phases/earth_over_water_arrest_flow.tres",
        "res://data/phases/earth_follow_fire_smother_ash.tres",
        # ...（省略已有条目）...
        "res://data/phases/wood_over_earth_pierce_bank.tres",
        "res://data/phases/metal_over_fire_example.tres",   # ← 新增
    ]
```

4. 保存文件（`Ctrl+S`）

> ❌ 常见错误: 忘记在路径字符串前加 `"res://"`。正确格式是 `"res://data/phases/你的文件名.tres"`，**不是** `"data/phases/你的文件名.tres"`。

> ❌ 常见错误: 路径中的文件名拼写与实际文件不一致。请仔细核对大小写和下划线。如果路径错误，游戏启动时不会报错，但该化势静默缺失。

### 验证清单

完成上述两步后，请逐一确认：

- [ ] `.tres` 文件已保存在 `data/phases/` 目录中
- [ ] `phase_id` 与文件名一致
- [ ] `attack_element` 和 `target_element` 已正确设置（不是默认的 NONE）
- [ ] `category` 已设置为 `DOMINANT`（相克）或 `FOLLOW`（相生）
- [ ] `scripts/combat/phase_table.gd` 的 `paths` 数组中已添加 `"res://data/phases/你的文件名.tres"`
- [ ] 按 `F5` 或 `F6` 运行游戏，触发对应属性组合的攻击，确认化势名称出现在右上角通知中

---

## B.12 伤害计算公式

战斗中技能伤害的完整计算流程：

```
1. 基础伤害 = base_atk x damage_ratio

2. 化势判定:
   - 查找 PhaseTable.lookup(技能属性, 目标当前属性)
   - 获得化势倍率 multiplier

3. 特殊倍率:
   - 无属性 -> 无属性: multiplier = 1.15
   - 攻击方有"攻衰"状态: multiplier *= 0.8
   - 目标有"脆裂"状态（未触发）: multiplier *= 1.2

4. 中间伤害 = round(基础伤害 x multiplier)

5. 化势附加伤害:
   - 若化势数据有 bonus_damage_type:
     - "target_max_hp_ratio": 附加 = target.max_hp x bonus_value
     - 附加伤害不超过 cap 表达式的值
   - 中间伤害 += 附加伤害

6. 最终伤害 = max(中间伤害, 0)

7. 目标 HP -= 最终伤害
```

---

## B.13 元素颜色全局类（ElementColors）

项目中所有涉及五行元素的颜色显示都由 **`ElementColors`** 全局类统一管理，实现位于 `scripts/data/element_colors.gd`。

这是一个 `class_name ElementColors extends RefCounted` 类型的工具类，所有方法都是 `static`，可以直接通过类名调用，**无需 preload，无需实例化**。

### 颜色表

| Enums.Element 值 | 中文 | Color8 (R, G, B) | 十六进制 |
|------------------|------|------------------|----------|
| `NONE` (0) | 无 | `(140, 147, 161)` | `#8c93a1` |
| `METAL` (1) | 金 | `(255, 215, 70)` | `#ffd746` |
| `WOOD` (2) | 木 | `(110, 220, 110)` | `#6edc6e` |
| `WATER` (3) | 水 | `(90, 180, 255)` | `#5ab4ff` |
| `FIRE` (4) | 火 | `(230, 70, 60)` | `#e6463c` |
| `EARTH` (5) | 土 | `(200, 150, 80)` | `#c89650` |

> 💡 提示: 想修改全局元素配色？只需编辑 `scripts/data/element_colors.gd` 的 `COLORS` 字典，底部状态栏、头顶 popup、右上角 Notify 等所有 UI 都会自动同步。

### 静态方法 API

| 方法 | 参数 | 返回值 | 用途 |
|------|------|--------|------|
| `ElementColors.get_color(e)` | `Enums.Element` | `Color` | 取得某元素对应的 Color 对象 |
| `ElementColors.element_name(e)` | `Enums.Element` | `String` | 取得某元素的中文名（金/木/水/火/土/无） |
| `ElementColors.bbcode(e, text)` | `Enums.Element`, `String` | `String` | 生成带颜色的 BBCode 片段 `[color=#xxx]text[/color]` |

### 使用场景与示例

#### 场景一：在 Label 上用元素色

```gdscript
var lbl := Label.new()
lbl.text = "水属性"
lbl.add_theme_color_override("font_color", ElementColors.get_color(Enums.Element.WATER))
add_child(lbl)
```

#### 场景二：在 RichTextLabel / Notify 里嵌入彩色片段

```gdscript
# 生成 BBCode
var atk_bb := ElementColors.bbcode(Enums.Element.EARTH, "土×2")
var tgt_bb := ElementColors.bbcode(Enums.Element.WATER, "水×2")

# 拼接富文本
var text := "%s → %s" % [atk_bb, tgt_bb]

# 发送到右上角 Notify
Notify.notify(text, Notify.Position.TOP_RIGHT, Notify.Style.INFO, 3.0)

# 或者填到 RichTextLabel
var rtl := RichTextLabel.new()
rtl.bbcode_enabled = true
rtl.text = text
add_child(rtl)
```

#### 场景三：根据单位的固有属性动态取名字

```gdscript
func describe_unit(unit: Unit) -> String:
    var e: Enums.Element = unit.unit_data.innate_element
    var name: String = ElementColors.element_name(e)  # "土"、"水"...
    return "%s (%s属性)" % [unit.unit_data.unit_name, name]
```

### 铁律：不要硬编码元素颜色

> ❌ **错误做法**：
> ```gdscript
> lbl.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))  # 直接写水色数值
> ```
>
> ✔ **正确做法**：
> ```gdscript
> lbl.add_theme_color_override("font_color", ElementColors.get_color(Enums.Element.WATER))
> ```
>
> **理由**：全局统一的配色可被美术一键调整；硬编码的数值会变成"漏网之鱼"。

### 已在项目中使用 ElementColors 的地方

| 位置 | 用途 |
|------|------|
| `scenes/levels/base_level/base_level.gd:775-776` | 拼接化势详情 Notify 的彩色元素片段 |
| `scenes/ui/combat/phase_element_popup.gd:17-19` | 头顶元素对比 popup 的左右两段颜色 |
| 底部状态栏的"当前属性 / 固有属性"显示 | 按单位当前元素着色 |

---

返回: [目录](README.md)
