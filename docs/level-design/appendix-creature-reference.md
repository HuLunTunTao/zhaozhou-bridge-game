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

---

## B.2 技能数据一览

所有技能数据文件位于 `data/skills/`。

### 李春技能

| 文件名 | skill_id | 名称 | 类型 | AP | 倍率 | 属性 | 附着 | 射程 | 影响范围 | 描述 |
|--------|----------|------|------|------|------|------|------|------|----------|------|
| `lc_rule_strike.tres` | lc_rule_strike | 规尺击 | 攻击 | 20 | 1.0 | 无 | 0 | 四邻(1格) | 单体 | 对无属性目标伤害x1.15 |
| `lc_cast_stone_arrest_flow.tres` | lc_cast_stone_arrest_flow | 投石遏流 | 攻击 | 35 | 0.95 | 土 | 2 | 菱形3格 | 单体 | 命中后击退1格 |
| `lc_pile_bind_wave.tres` | lc_pile_bind_wave | 束桩缓波 | 攻击 | 30 | 0.95 | 木 | 2 | 菱形3格 | 十字(含中心) | 对目标周围十字施加迟滞2回合 |
| `lc_read_water_fix_site.tres` | lc_read_water_fix_site | 相水定址 | 辅助交互 | 30 | 0 | 无 | 0 | 菱形3格 | 十字(含中心) | 显示危险地格2回合，赋予稳步1回合 |
| `lc_wedge_bank_probe.tres` | lc_wedge_bank_probe | 木楔勘岸 | 攻击 | 25 | 1.0 | 木 | 1 | 菱形3格 | 单体 | 用于触发木行化势 |

### 工匠技能

| 文件名 | skill_id | 名称 | 类型 | AP | 倍率 | 描述 |
|--------|----------|------|------|------|------|------|
| `cg_mallet_strike.tres` | cg_mallet_strike | 杵槌击 | 攻击 | 25 | 1.0 | 近战攻击 |
| `cg_guard_the_works.tres` | cg_guard_the_works | 捍作护行 | 辅助 | 30 | 0 | 赋予目标护持2回合 |

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

| 枚举值 | SkillType | 中文名 | 说明 |
|--------|-----------|--------|------|
| 0 | ATTACK | 攻击 | 造成伤害的主动技能 |
| 1 | ASSIST | 辅助 | 不造成伤害，为友方单位提供增益 |
| 2 | INTERACT | 交互 | 与地图元素交互（如勘测点） |
| 3 | ASSIST_INTERACT | 辅助交互 | 同时具有辅助和交互功能 |

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
| 直线4格 | 4 | 单方向连续4格 | `[(1,0),(2,0),(3,0),(4,0)]` |

### effect_offsets（影响区域）

以释放点为原点 `(0,0)` 的偏移列表。定义了技能实际影响哪些格子。

常见模式：

| 模式 | 格子数 | 说明 | 示例 |
|------|--------|------|------|
| 单体 | 1 | 仅影响释放点 | `[(0,0)]` |
| 十字(含中心) | 5 | 释放点及其上下左右 | `[(0,0),(1,0),(-1,0),(0,1),(0,-1)]` |

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

| 文件名 | status_id | 名称 | 持续回合 | 一次触发 | 描述 |
|--------|-----------|------|----------|----------|------|
| `brittle.tres` | brittle | 脆裂 | 2 | 是 | 下一次受到的伤害额外提高20% |
| `cold_damp.tres` | cold_damp | 湿寒 | 2 | 否 | 下回合行动力恢复值降低15% |
| `fracture_step.tres` | fracture_step | 陷裂 | 2 | 否 | 移动时前2格每格额外消耗4点行动力 |
| `guarded_cover.tres` | guarded_cover | 护持 | 2 | 否 | 首次受到的伤害-12，不能被拖拽或击退超过1格 |
| `hindered_step.tres` | hindered_step | 迟滞 | 2 | 否 | 每移动1格额外消耗2点行动力 |
| `open_fissure.tres` | open_fissure | 剖隙 | 2 | 否 | 受到击退/冲撞/地形撞击时额外承受施术者ATKx0.50的伤害 |
| `overgrow_bind.tres` | overgrow_bind | 蔓缚 | 2 | 否 | 最大可移动格数-1 |
| `rend.tres` | rend | 裂伤 | 2 | 否 | 回合结束时失去施术者ATKx0.30的生命 |
| `scorch_mark.tres` | scorch_mark | 灼痕 | 2 | 否 | 回合结束时失去施术者ATKx0.25的生命 |
| `silt_lock.tres` | silt_lock | 壅水 | 3 | 否 | 行动开始时不执行固有属性回补 |
| `slowed_step.tres` | slowed_step | 迟步 | 1 | 否 | 每移动1格额外消耗2点行动力 |
| `smothered.tres` | smothered | 闷熄 | 1 | 否 | 下回合开始时不能额外获得火属性量 |
| `steady_step.tres` | steady_step | 稳步 | 1 | 否 | 进入浅水额外消耗-4，本回合第一次被击退时距离-1 |
| `weakened.tres` | weakened | 攻衰 | 2 | 否 | 造成的伤害降低20% |

### 状态字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `status_id` | String | 状态唯一标识符 |
| `status_name` | String | 显示名称 |
| `duration_turns` | int | 持续回合数 |
| `trigger_once` | bool | 是否为一次性触发（触发后立即消失） |
| `description` | String | 效果描述 |

---

## B.6 化势（五行反应）数据一览

所有化势数据文件位于 `data/phases/`。

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

| 枚举值 | PhaseCategory | 中文名 | 说明 |
|--------|---------------|--------|------|
| 0 | DOMINANT | 相克 | 五行相克反应（金克木、木克土等） |
| 1 | FOLLOW | 相生 | 五行相生反应（金生水、水生木等） |
| 2 | ADVERSE | 逆势 | 攻击方处于不利克制关系 |
| 3 | SAME | 同气 | 攻击属性 = 目标当前属性，不触发化势 |
| 4 | PLAIN | 普通 | 无特殊反应的异属性接触 |

### 五行相克关系图

```
     金 ─克→ 木
     ↑         ↓
     火        土
     ↑         ↓
     木 ←克─ 水

  相克: 金→木→土→水→火→金
  相生: 金→水→木→火→土→金
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

> 💡 提示: 在 `.tres` 文件中，属性以数字存储。例如 `innate_element = 5` 表示 `EARTH`（土）。在 Godot 编辑器的检查器中，你可以直接从下拉菜单中选择属性名称。

---

## B.8 AI 类型说明

| ai_type | 中文名 | 预期行为（待完善） |
|---------|--------|--------------------|
| `""` | 无 | 不使用 AI，玩家控制或无行动 |
| `"zone_breaker"` | 区域破坏 | 优先攻击区域内的目标，破坏防线 |
| `"flank_melee"` | 侧翼近战 | 绕过前排，从侧翼攻击 |
| `"hazard_charge"` | 冲锋 | 直线冲向最近的目标 |
| `"control_pull"` | 控制拉拽 | 将目标拉向不利位置（水中等） |

> ⚠️ 注意: 当前 AI 实现为占位逻辑（随机移动一步）。ai_type 字段为将来完善 AI 行为树预留。数据应提前按设计文档填写正确。

---

## B.9 SkillData 字段详解

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
| `description` | String | 技能描述文本 |
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

## B.10 PhaseData 字段详解

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

返回: [目录](README.md)
