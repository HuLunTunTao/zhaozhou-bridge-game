# 08 -- 关卡集成

> 本章介绍如何将完成的关卡接入游戏的选关菜单和战役流程中，使玩家可以从主菜单进入你的关卡。

---

## 8.1 关卡注册系统概述

游戏使用 `scripts/game_state.gd` 作为全局关卡注册表。这是一个 **Autoload**（自动加载脚本），在游戏启动时自动加载，全局可访问。

注册表中有两个关键常量：

| 常量 | 作用 |
|------|------|
| `LEVEL_SCENES` | 关卡名称 -> 场景文件路径的映射。选关界面会自动根据此字典生成按钮 |
| `CUTSCENE_DATA` | 关卡名称 -> 过场动画图片路径的映射 |

---

## 8.2 注册新关卡（详细步骤）

### 第一步：打开 game_state.gd

1. 在 Godot 编辑器的文件系统面板中，导航到 `scripts/`
2. 双击 `game_state.gd` 打开脚本编辑器

### 第二步：在 LEVEL_SCENES 中添加条目

找到 `LEVEL_SCENES` 字典，在末尾添加你的关卡：

```gdscript
const LEVEL_SCENES: Dictionary = {
    "关卡1-1": "res://scenes/levels/level1-1/level1-1.tscn",
    "关卡1-2": "res://scenes/levels/level1-2/level1-2.tscn",
    "关卡1-3": "res://scenes/levels/level1-3/level1-3.tscn",
    "关卡1-3-2": "res://scenes/levels/level1-3-2/level1-3-2.tscn",
    "关卡1-4": "res://scenes/levels/level1-4/level1-4.tscn",
    "关卡测试": "res://scenes/levels/test/test.tscn",
    "关卡1-5": "res://scenes/levels/level1-5/level1-5.tscn",  # <- 新增
}
```

注意事项：
- **键**（如 `"关卡1-5"`）是显示在选关按钮上的文字
- **值**（如 `"res://scenes/levels/level1-5/level1-5.tscn"`）必须是正确的场景文件路径
- 字典的**插入顺序**决定按钮的显示顺序
- 路径以 `res://` 开头（Godot 项目根目录）

### 第三步：（可选）添加过场动画

如果你的关卡有开场或结束过场动画，在 `CUTSCENE_DATA` 中添加：

```gdscript
const CUTSCENE_DATA: Dictionary = {
    "关卡1-1": {
        "pre": [
            "res://assets/cutscenes/level1-1/pre_01.png",
            "res://assets/cutscenes/level1-1/pre_02.png",
        ],
        "post": [
            "res://assets/cutscenes/level1-1/post_01.png",
        ],
    },
    "关卡1-5": {                                              # <- 新增
        "pre": [
            "res://assets/cutscenes/level1-5/pre_01.png",
        ],
    },
}
```

- `"pre"` 列表中的图片在**进入关卡前**播放
- `"post"` 列表中的图片在**通关后**播放
- 图片按数组顺序逐页显示，玩家点击翻页
- 如果不需要过场，不添加条目即可

### 第四步：保存并验证

1. 按 `Ctrl+S` 保存 `game_state.gd`
2. 按 `F5` 运行项目
3. 在主菜单点击 **开始**
4. 确认选关界面中出现了你的关卡按钮
5. 点击按钮确认能正常进入关卡

---

## 8.3 关卡加载流程

理解完整的加载流程有助于排查问题：

```
玩家点击关卡按钮
    ↓
MainMenu._on_level_selected("关卡1-5")
    ↓
GameState.selected_level = "关卡1-5"
    ↓
检查是否有 pre 过场？
    ├── 有 → 加载 cutscene_scene.tscn → 播放过场 → 加载关卡场景
    └── 无 → 直接加载关卡场景
    ↓
关卡场景加载
    ↓
BaseLevel._ready() 执行：
    1. 查找可行走的 TileMapLayer
    2. 读取 get_teams_config() 初始化队伍
    3. 将实体重新挂载到障碍物层
    4. 设置特殊地块
    5. 初始化相机
    6. 调用 _on_level_ready()
    7. 启动回合系统
    ↓
关卡进行中...
    ↓
调用 complete_level()
    ↓
检查是否有 post 过场？
    ├── 有 → 播放过场 → 返回主菜单
    └── 无 → 直接返回主菜单
```

---

## 8.4 选关界面工作原理

选关界面由 `scenes/menu/main_menu.gd` 自动生成。它会遍历 `GameState.LEVEL_SCENES` 字典，为每个条目创建一个按钮。

因此你**不需要手动编辑主菜单场景**，只需在 `LEVEL_SCENES` 字典中添加条目即可。

当前的选关界面特性：
- 按钮按字典插入顺序排列
- 所有关卡默认可进入（没有锁定机制）
- 没有通关标记（评价/星级系统待实现）

> 💡 提示: 如果你希望调整关卡的显示顺序，调整 `LEVEL_SCENES` 字典中条目的顺序即可。

---

## 8.5 Autoload（自动加载）说明

游戏中有以下 Autoload 节点：

| 名称 | 脚本路径 | 作用 |
|------|----------|------|
| `GameState` | `scripts/game_state.gd` | 关卡注册表、过场数据、场景间状态传递 |
| `Notify` | `scripts/notification_manager.gd` | 全局通知管理器（游戏内消息提示） |

这意味着：

- 它们在游戏启动时自动创建，全局唯一
- 在任何脚本中都可以通过名称直接访问（如 `GameState.selected_level`）
- 场景切换时不会被销毁，可以在场景之间传递数据
- 配置在 `project.godot` 的 `[autoload]` 段中

关卡设计师通常不需要修改 Autoload 配置，只需编辑 `game_state.gd` 文件中的字典数据。

---

## 8.6 设置面板

关卡中右上角的齿轮按钮会打开设置面板（`scenes/ui/settings_panel.tscn`）。在关卡中打开时，设置面板会显示一个"返回主菜单"选项。

这部分由 BaseLevel 自动处理，关卡设计师无需额外配置。

---

## 8.7 测试场景菜单

主菜单中还有一个"测试"入口，用于运行非关卡的功能测试场景（如对话系统测试、通知系统测试）。这些测试场景在 `main_menu.gd` 的 `TEST_SCENES` 常量中定义，与关卡注册系统是独立的。

关卡设计师通常不需要修改测试场景列表。

---

## 8.8 集成检查清单

完成一个关卡后，按以下清单确认集成：

- [ ] 关卡场景文件存在于 `scenes/levels/你的关卡名/` 目录中
- [ ] 关卡脚本文件（`.gd`）位于同一目录中
- [ ] `game_state.gd` 的 `LEVEL_SCENES` 中已添加关卡条目
- [ ] 场景路径正确（以 `res://` 开头，文件名与实际一致）
- [ ] （可选）`CUTSCENE_DATA` 中已添加过场动画数据
- [ ] （可选）过场动画图片已放置在 `assets/cutscenes/` 对应目录
- [ ] F5 运行后，选关界面能看到新关卡按钮
- [ ] 点击按钮后能正常进入关卡
- [ ] 关卡中"结束回合"和"设置"按钮正常工作

---

## 8.9 从完成到上线的完整流程

总结一个关卡从创建到可玩的完整步骤：

1. **创建场景** -- 继承 `base_level.tscn`，添加脚本（[01-地图创建](01-map-creation.md)）
2. **绘制地图** -- 添加 TileMapLayer，用 Terrain 模式绘制地形（[02-地形绘制](02-terrain-painting.md)）
3. **放置单位** -- 添加 Unit 实例，配置 UnitData 和颜色（[03-单位配置](03-unit-placement.md)）
4. **配置参数** -- 编写队伍配置、设置特殊地块（[04-关卡参数](04-level-parameters.md)）
5. **测试调试** -- F6 测试、排查问题（[07-测试与调试](07-testing.md)）
6. **注册关卡** -- 在 `game_state.gd` 中添加条目（本章）
7. **最终验证** -- F5 从主菜单完整走一遍

---

上一章: [07-测试与调试](07-testing.md) | 返回: [目录](README.md)
