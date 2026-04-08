# player → unit 统一化重构计划

## Context

当前项目中所有单位（玩家、友方、敌方）都使用同一个 `player.gd` / `player.tscn`，但场景树中分为 `Entities/Players` 和 `Entities/Enemies` 两个容器，`base_level.gd` 中变量名也混用 `player`（既指"玩家操控方"又指"单位"）。这在后续战斗系统开发中会造成混淆。需要统一命名和场景结构。

---

## 变更清单

### 1. 创建 `scenes/unit/unit.gd`（从 player.gd）

- 复制 `scenes/player/player.gd` → `scenes/unit/unit.gd`
- 添加 `class_name Unit`（第 2 行后插入）
- 其余内容不变（变量名 `unit_color`, `movement_points` 等已经是通用的）

### 2. 创建 `scenes/unit/unit.tscn`（从 player.tscn）

- 修改脚本路径：`res://scenes/player/player.gd` → `res://scenes/unit/unit.gd`
- 根节点名：`Player` → `Unit`

### 3. 修改 `base_level.tscn` — 合并 Players/Enemies 为 Units

```
# 删除:
[node name="Enemies" type="Node2D" parent="Entities" unique_id=1178648495]

# 修改（保留原 unique_id 436779837，确保继承场景的 parent_id_path 不断）：
[node name="Players" ...] → [node name="Units" type="Node2D" parent="Entities" unique_id=436779837]
```

### 4. 修改 `base_level.gd` — 变量/方法重命名

| 旧 | 新 | 说明 |
|---|---|---|
| `players_container` + `enemies_container` | `units_container` | 合并为单一容器引用 |
| `var player: Node2D` | `var hero: Node2D` | 专指第一个玩家控制单位（李春） |
| `player_selected` | `unit_selected` | 是否有单位被选中 |
| `_find_player()` | `_find_hero()` | 从容器中找到第一个单位 |
| `_on_player_moved()` | `_on_unit_moved()` | 单位移动完毕回调 |
| `get_player_start_cell()` | `get_hero_start_cell()` | 旧版单角色起始位置 |

**不改动的**：`_waiting_for_player_input`（语义正确，指"等待人类玩家输入"）、`team.controller == "player"`（指人类操控方）、cutscene 相关。

### 5. 修改 8 个继承场景 .tscn

所有文件执行：
- `ext_resource` 路径 `scenes/player/player.tscn` → `scenes/unit/unit.tscn`
- `parent="Entities/Players"` → `parent="Entities/Units"`

文件列表：
- `scenes/levels/level1-1/level1-1.tscn`
- `scenes/levels/level1-2/level1-2.tscn`
- `scenes/levels/level1-3/level1-3.tscn`
- `scenes/levels/level1-4/level1-4.tscn`
- `scenes/levels/level1-3-2/level1-3-2.tscn`
- `scenes/levels/maps/level1-3-2桥面测试画法.tscn`
- `scenes/debug/debug_battle.tscn`
- `scenes/levels/test/test.tscn`（额外：Enemy 节点的 `parent_id_path` 从 1178648495 改为 436779837，index 改为 4/5）

### 6. 修改 `test.gd` — 节点路径

```
$"Entities/Players/..."  → $"Entities/Units/..."
$"Entities/Enemies/..." → $"Entities/Units/..."
```

### 7. 修改 `debug_battle.gd` — 引用旧名

- `get_player_start_cell` → `get_hero_start_cell`
- `_on_player_moved` → `_on_unit_moved`
- `player.cell` → `hero.cell`
- `player_selected` → `unit_selected`

### 8. 删除 `scenes/player/` 目录

---

## 执行顺序

1. 创建 `scenes/unit/` 目录和 unit.gd, unit.tscn（步骤 1-2）
2. 同时修改 base_level.tscn + 所有继承场景 tscn（步骤 3+5，必须一起做）
3. 修改 base_level.gd（步骤 4）
4. 修改 test.gd, debug_battle.gd（步骤 6-7）
5. 删除旧文件（步骤 8）

## 关键风险：parent_id_path

Godot 继承场景通过 `unique_id` 关联父子节点。`Entities/Players` 的 unique_id 是 436779837。我们将此 ID 保留给新的 `Units` 节点，所有子场景的 `parent_id_path=PackedInt32Array(436779837)` 无需修改即可正常工作。只有 test.tscn 中原属 Enemies（unique_id=1178648495）的节点需要改为指向 436779837。

---

## 验证

1. **grep 检查**：`scenes/player`、`Entities/Players`、`Entities/Enemies`、`player_selected`、`_find_player`、`_on_player_moved`、`get_player_start_cell` 在 .gd/.tscn 中不再出现
2. **Godot 编辑器**：打开各场景无报错
3. **运行测试**：debug_battle 场景和 test 场景正常运行，回合切换、移动、多队伍正常
