# 敌方 AI 系统设计

## 概述

静态工具类 `AIBrain`（遵循 `SkillExecutor` 模式），无状态，纯函数。关卡通过虚方法 `_get_ai_context()` 提供特殊上下文。

## 架构

```
scripts/combat/ai_brain.gd  (NEW)  ~180行
  ├── decide_action(unit, enemies, ...) -> Dictionary
  ├── _pick_target(unit, enemies, level_context) -> Unit
  ├── _compute_reachable(origin, budget, ...) -> Dictionary
  ├── _find_attack_cell(from, target, skill, reachable) -> Vector2i
  ├── _can_hit(from_cell, skill, target_cell) -> bool
  ├── _reconstruct_path(parents, origin, target) -> Array[Vector2i]
  └── _decide_hazard_charge(unit, enemies, ...) -> Dictionary

base_level.gd  (MODIFY)
  ├── _get_ai_context() -> Dictionary        (新增虚方法)
  ├── _get_alive_enemies(faction) -> Array    (新增辅助)
  ├── _execute_ai_skill(unit, skill, cell)    (新增，含镜头+反馈)
  ├── _run_ai_turn()                          (重构)
  └── _ai_move_unit()                         (删除)
```

## 决策流程

### 标准流程（flank_melee / control_pull / zone_breaker）

```
1. 选目标: _pick_target() 根据 ai_type 评分
2. 检查原地能否攻击
   → 能: 直接攻击，结束
3. 为每个技能计算:
   a. movement_budget = ap_current - skill.ap_cost
   b. reachable = Dijkstra(unit.cell, movement_budget)
   c. attack_cell = 可达范围内能打到目标的最近格
4. 有 attack_cell: 移动 → 攻击
5. 无 attack_cell: 用全部 AP 尽可能接近目标
```

### hazard_charge 流程（浮木群）

```
1. 沿固定方向直线前进（方向由关卡 level_context 配置）
2. 每步检查: 前方有敌人 → 攻击并停止
3. 前方不可通行 → 停止
4. AP 耗尽 → 停止
```

## 目标评分规则

| ai_type | 评分规则 |
|---------|---------|
| flank_melee | is_escort_target: +100, HP<50%: +50, 距离: -1/格 |
| control_pull | 可拖入危险地块: +200, is_escort_target: +100, 距离: -1/格 |
| zone_breaker | is_escort_target: +100, 距离: -1/格 |
| 默认 | 距离: -1/格（最近优先）|

## AP 管理

- 技能 AP 优先预留：`move_budget = ap_current - skill.ap_cost`
- 移动消耗与玩家相同：`base_move_cost + (tile_cost - 1)` 每步

## 技能范围检查

```gdscript
# 从 from_cell 用 skill 能否打到 target_cell？
static func _can_hit(from_cell, skill, target_cell) -> bool:
    for cast_offset in skill.cast_offsets:
        var cast_cell := from_cell + cast_offset
        for effect_offset in skill.effect_offsets:
            if cast_cell + effect_offset == target_cell:
                return true
    return false
```

## 关卡自定义

关卡覆写 `_get_ai_context()` 提供特殊数据：

```gdscript
# level1-1.gd
func _get_ai_context() -> Dictionary:
    return {
        "escort_units": [_survey_a, _survey_b],       # 护送目标
        "drift_directions": {},                         # 浮木移动方向
    }
```

## 镜头整合

AI 攻击复用玩家技能的镜头模式：
- 计算施法者与目标中点
- lock_on(中点, zoom)
- 执行技能 + 反馈
- 短暂停留后恢复

## decide_action 返回值

```gdscript
{
    "move_path": Array[Vector2i],  # 移动路径（空 = 不移动）
    "move_cost": int,              # 移动 AP 消耗
    "skill": SkillData,            # 使用的技能（null = 不攻击）
    "cast_cell": Vector2i,         # 技能施放点
}
```
