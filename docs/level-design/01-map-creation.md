# 01 -- 地图创建

> 本章介绍如何新建一个关卡场景，并正确设置场景树结构。
>
> **如果你从未使用过 Godot 编辑器**，请先阅读下方 2.0 节的编辑器入门，再进入 2.1 节开始创建关卡。

---

## 2.0 Godot 编辑器入门（第一次使用请先读这一节）

如果你已经熟悉 Godot 编辑器，可直接跳到 2.1 节。

### 2.0.1 首次打开项目

1. 启动 **Godot Engine**（版本必须是 **4.6.1** 或以上）
2. 启动后出现的第一个窗口叫 **项目管理器 (Project Manager)**，列出最近打开的项目
3. 点击右侧的 **导入 (Import)** 按钮
4. 在文件选择对话框中，定位到仓库根目录下的 **`project.godot`** 文件（不是 `.tscn` 也不是 `.gd`）
5. 选中它后点击 **打开**，再点击 **导入并编辑 (Import & Edit)**
6. Godot 会花 10–60 秒扫描并导入项目资源（底部状态栏显示进度条），耐心等待直到进度条消失

> 💡 提示: 导入过程中 Godot 会在项目目录下生成一个 `.godot/` 文件夹存放缓存。这个文件夹已被 `.gitignore` 排除，不会进入版本控制。

> ⚠️ 注意: 不要双击 `.tscn` 文件来"打开项目"——那只会单独打开一个场景却没有项目上下文。**永远通过 `project.godot` 来打开项目**。

### 2.0.2 主界面六大面板

项目打开后，主编辑器窗口从上到下、从左到右分为以下几个区域。**你在下文每一步操作前都应该知道自己要点哪个面板**。

```
┌─────────────────────────────────────────────────────────────┐
│ ① 菜单栏 + ② 主工具栏 (Scene / Project / 2D/3D/Script 切换) │
├──────────────┬─────────────────────────────┬────────────────┤
│              │                             │                │
│   ③ 场景树    │      ④ 视口 (2D/3D/Script)   │  ⑤ 检查器       │
│  (Scene)     │                             │  (Inspector)   │
│              │                             │                │
│              │                             │                │
├──────────────┼─────────────────────────────┼────────────────┤
│ ⑥ 文件系统    │      ⑦ 底部面板               │                │
│ (FileSystem) │      (Output / Debugger / TileMap / ...) │    │
└──────────────┴─────────────────────────────────────────────┘
```

| 面板 | 位置 | 用途 | 什么时候看它 |
|------|------|------|-------------|
| ① **菜单栏** | 最顶部 | 场景、项目、调试、编辑器、帮助 | 新建/打开场景、项目设置 |
| ② **主视图切换条** | 菜单栏下方中间 | 在 `2D` / `3D` / `Script` / `AssetLib` 视图间切换 | 编辑地图时选 `2D`，写脚本时选 `Script` |
| ③ **场景树 (Scene)** | 左上 | 显示当前场景的所有节点 | 添加/选中/重命名节点 |
| ④ **视口 (Viewport)** | 中央 | 2D 编辑器 / 脚本编辑器 | 绘制地图、拖拽单位、写代码 |
| ⑤ **检查器 (Inspector)** | 右侧 | 显示选中节点的所有属性 | 修改节点属性、拖拽资源引用 |
| ⑥ **文件系统 (FileSystem)** | 左下 | 项目内所有文件的树形视图 | 打开场景/脚本、拖拽资源 |
| ⑦ **底部面板** | 视口下方 | Output（输出）、Debugger、TileMap、FileSystem、Animation 等选项卡 | 查看 `print()` 输出、运行时错误、TileMap 绘制工具 |

**关键点**：
- 选中场景树中的节点 → 检查器自动显示该节点的所有属性
- 在文件系统中双击 `.tscn` → 在视口中打开场景
- 在文件系统中双击 `.gd` → 切换到 Script 视图
- 按 `F1` 可在任意位置呼出文档搜索

### 2.0.3 必须认识的几个概念

| 名词 | 解释 | 对应什么 |
|------|------|----------|
| **节点 (Node)** | 场景树中的一个单元，是构成游戏世界的基本块 | 场景树里的每一行 |
| **场景 (Scene)** | 一组节点的组合，保存为 `.tscn` 文件 | 一个关卡就是一个场景 |
| **资源 (Resource)** | 可被多个节点共享的数据，保存为 `.tres` 文件 | 单位数据、技能数据、地形集 |
| **实例化 (Instantiate)** | 把一个场景"插入"到另一个场景里成为子节点 | 把 Unit 场景插到关卡场景里 |
| **继承场景 (Inherited Scene)** | 新场景基于另一个场景创建，自动继承所有节点 | 关卡继承 `base_level.tscn` |
| **脚本 (Script)** | 附加到节点上的 GDScript 文件 | `.gd` 文件 |
| **属性 (Property)** | 节点/资源上的可编辑字段 | 在检查器中看到的条目 |
| **Autoload** | 全局单例脚本，启动时自动加载 | `GameState`、`Notify` |

### 2.0.4 必须记住的快捷键

macOS 用户把 `Ctrl` 替换为 `Cmd`：

| 快捷键 | 作用 |
|--------|------|
| `Ctrl+S` | 保存当前场景/脚本（**每改一点就按一次**） |
| `Ctrl+Shift+S` | 另存为 |
| `Ctrl+Z` / `Ctrl+Shift+Z` | 撤销 / 重做 |
| `F5` | 从主场景运行整个项目（从主菜单开始） |
| `F6` | 运行当前打开的场景（跳过主菜单，最快的测试方式） |
| `F8` | 停止运行 |
| `Ctrl+A`（在场景树面板中） | 添加子节点 |
| `Ctrl+点击场景树节点` | 多选 |
| `鼠标中键拖拽`（在 2D 视口中） | 平移视口 |
| `鼠标滚轮` | 缩放视口 |

### 2.0.5 第一次操作：打开一个现有关卡看看

在开始创建新关卡前，先打开一个现有关卡熟悉界面：

1. 在 **文件系统 (⑥)** 面板中展开 `scenes/levels/test/`
2. 双击 `test.tscn`
3. 此时 **场景树 (③)** 显示该关卡的节点层级，**视口 (④)** 显示等距地图
4. 试着点击场景树中的 `TileMaps/surface z=0`，注意底部自动弹出 **TileMap 面板** —— 这是绘制地形的工具
5. 点击某个 `Entities/Units/XXX` 单位节点，**检查器 (⑤)** 显示 `Unit Data`、`Unit Color` 等属性
6. **不要修改任何东西**，只是看看，然后按 `Ctrl+Z` 撤销任何误操作，或者直接关闭场景但**不保存**（弹窗中选 "Discard"）

> 💡 提示: 熟悉界面是零成本的。建议打开 2–3 个现有关卡对比看看，了解场景树长什么样，检查器里会出现哪些属性。

---

## 2.1 关卡场景结构总览

每个关卡场景都继承自 `base_level.tscn`，继承后自动获得以下节点树：

```
关卡根节点 (Node2D, 继承 BaseLevel)
├── TileMaps (Node2D)          -- 放置所有 TileMapLayer 地图层
│   ├── init tile map          -- 初始化地图层（可选，某些关卡有）
│   ├── surface z=0            -- 地表层（可行走区域）★ 最重要
│   ├── Obstacle z=2           -- 障碍物层
│   ├── decoration z=1         -- 装饰层
│   ├── thebase z=-1           -- 底层（地面以下）
│   └── thebase z=-2           -- 更低的底层
├── Entities (Node2D)          -- 实体容器
│   └── Units (Node2D)         -- 放置所有战斗单位
├── MoveOverlay (Node2D)       -- 移动范围高亮（自动管理，不要修改）
├── Camera2D (LevelCamera)     -- 关卡相机
├── GUI (CanvasLayer)          -- 界面层（自动管理）
│   ├── HudPanel               -- 顶部面板
│   ├── EndTurnButton          -- 结束回合按钮
│   ├── SettingsButton         -- 设置按钮（齿轮图标）
│   └── TurnLabel              -- 回合标签（显示当前回合队伍）
├── StatusBarScene             -- 底部状态栏（左侧头像+信息，右侧技能槽位）
├── MovementManager (Node)     -- 移动管理器 ★ 需要配置
└── SpecialTiles (Node2D)      -- 特殊地块容器
```

> 注意: `StatusBarScene` 是底部状态栏，包含角色头像、HP/AP 进度条、属性显示和技能按钮。它与 `GUI` 节点是**并列**的（都挂在根节点下），不是 GUI 的子节点。

> ⚠️ 注意: 标有"不要修改"的节点是由基类脚本自动管理的。修改它们可能导致关卡无法正常运行。

---

## 2.2 创建新关卡（详细步骤）

### 第一步：创建关卡文件夹

1. 在 Godot 编辑器左下方的 **文件系统 (FileSystem)** 面板中，导航到 `scenes/levels/`
2. 右键点击 `levels` 文件夹
3. 选择 **新建文件夹 (New Folder)**
4. 输入你的关卡名称，建议格式：`level{章}-{节}`，例如 `level1-5`
5. 按 Enter 确认

### 第二步：创建继承场景

"继承场景"意味着你的关卡自动获得 `base_level.tscn` 中定义的所有节点和功能，不需要从零搭建。

1. 顶部菜单 -> **场景 (Scene)** -> **新建继承场景 (New Inherited Scene)**
2. 在弹出的文件选择对话框中，导航到 `scenes/levels/base_level/`
3. 选择 `base_level.tscn`
4. 点击 **打开 (Open)**

此时编辑器中会出现一个新场景，场景树中会显示灰色的继承节点。

5. 立刻保存：按 `Ctrl+S`
6. 在保存对话框中，导航到刚才创建的文件夹（例如 `scenes/levels/level1-5/`）
7. 文件名输入关卡名（例如 `level1-5.tscn`）
8. 点击 **保存 (Save)**

> 💡 提示: 场景树中灰色图标的节点是从基类继承的。你可以修改它们的属性，但不能删除或重命名它们。

### 第三步：创建关卡脚本

每个关卡需要一个 GDScript 脚本来定义关卡特有的逻辑（如队伍配置）。

1. 在场景树中，点击选中**根节点**（最顶部的节点，名称类似 `BaseLevel`）
2. 点击场景树面板上方的 **附加脚本 (Attach Script)** 按钮（卷轴图标）
3. 在弹出的对话框中：
   - **语言 (Language)**: GDScript
   - **继承 (Inherits)**: `BaseLevel`（应该已自动填写）
   - **路径 (Path)**: 改为你的关卡文件夹路径，例如 `res://scenes/levels/level1-5/level1-5.gd`
   - **模板 (Template)**: 选择 **空模板 (Empty)**
4. 点击 **创建 (Create)**
5. 在打开的脚本编辑器中，输入以下内容：

```gdscript
extends BaseLevel
```

如果你的关卡需要多队伍（绝大多数战斗关卡都需要），请加上队伍配置方法。完整的队伍配置将在 [04-关卡参数](04-level-parameters.md) 中详细说明。最简模板如下：

```gdscript
extends BaseLevel


func get_teams_config() -> Array:
    return [
        {
            "name": "玩家队伍",
            "faction": "好人",
            "controller": "player",
            "units": [
                # 稍后添加单位引用
            ],
        },
        {
            "name": "敌方队伍",
            "faction": "坏人",
            "controller": "ai",
            "units": [
                # 稍后添加单位引用
            ],
        },
    ]
```

6. 按 `Ctrl+S` 保存脚本

> 💡 提示: 如果你的关卡暂时不需要队伍系统（比如只是测试地图），只写 `extends BaseLevel` 一行即可。系统会使用旧版单玩家模式。

### 第四步：重命名根节点

为了便于识别，将根节点重命名为你的关卡名。

1. 在场景树中双击根节点名称
2. 输入新名称，例如 `Level1-5`
3. 按 Enter 确认
4. 按 `Ctrl+S` 保存场景

---

## 2.3 添加地图层

关卡继承后，`TileMaps` 节点下是空的。你需要添加 TileMapLayer 来绘制地图。

### 必须的地图层

至少需要一个 **地表层**，它是可行走区域的定义。系统会按以下名称顺序自动查找：

```
"surface z=0" → "Main tile map z=0" → "WalkableMap"
```

如果都找不到，会使用 `TileMaps` 下的第一个 TileMapLayer。

### 推荐的地图层结构

参照现有关卡（如 test 关卡），建议使用以下分层：

| 层名 | 用途 | 是否必须 |
|------|------|----------|
| `surface z=0` | 地表可行走区域 | **必须** |
| `Obstacle z=2` | 障碍物（树、石头等不可通行物体） | 建议 |
| `decoration z=1` | 装饰物（花草等不影响通行的物体） | 可选 |
| `thebase z=-1` | 地面底层（水面、悬崖等） | 可选 |
| `thebase z=-2` | 更低的底层 | 可选 |

### 添加地图层的步骤

1. 在场景树中，右键点击 **TileMaps** 节点
2. 选择 **添加子节点 (Add Child Node)**
3. 在弹出的节点类型搜索框中输入 `TileMapLayer`
4. 选中 **TileMapLayer** 并点击 **创建 (Create)**
5. 双击新建的节点，重命名为 `surface z=0`

### 为地图层设置 TileSet

每个 TileMapLayer 需要一个 TileSet 资源来定义它可以使用哪些地块图案。

**方法一：使用现有关卡的地图层（推荐）**

如果你想使用与现有关卡相同的地形，最简单的方法是：

1. 打开一个已有的关卡场景（例如 `scenes/levels/test/test.tscn`）
2. 在场景树中找到对应的 TileMapLayer（例如 `surface z=0`）
3. 在检查器面板中找到 **Tile Set** 属性
4. 点击 Tile Set 属性值旁的小箭头，选择 **复制 (Copy)**
5. 切换回你的新关卡场景
6. 选中你新建的 TileMapLayer
7. 在检查器中点击 **Tile Set** 属性，选择 **粘贴 (Paste)**

**方法二：使用项目 TileSet 资源**

项目中有一个公共的 TileSet 资源文件：

```
assets/battle_tile_set.tres
```

1. 选中你的 TileMapLayer
2. 在检查器面板中找到 **Tile Set** 属性
3. 将文件系统面板中的 `assets/battle_tile_set.tres` 拖拽到 Tile Set 属性上

> ⚠️ 注意: 不同关卡的 TileSet 可能包含不同的地形和图块。如果使用方法一从其他关卡复制，请确认该 TileSet 包含你需要的所有地形类型。

---

## 2.4 配置 MovementManager

`MovementManager` 节点负责管理哪些格子可以行走、哪些是障碍物。**你必须正确配置它，否则角色无法移动。**

1. 在场景树中选中 **MovementManager** 节点
2. 在检查器面板中，你会看到两个数组属性：

| 属性 | 说明 | 该填什么 |
|------|------|----------|
| `Movement Tilemaps` | 可行走的 TileMapLayer 列表 | 填入地表层（如 `surface z=0`） |
| `Obstacle Tilemaps` | 障碍物 TileMapLayer 列表 | 填入障碍物层（如 `Obstacle z=2`） |

### 配置 Movement Tilemaps

1. 在检查器中找到 `Movement Tilemaps` 属性
2. 点击属性旁的 **数组大小** 输入框，输入 `1`（表示有 1 个可行走层）
3. 展开数组，在第 `0` 项的下拉框中，点击 **指定 (Assign)**
4. 从弹出的节点选择器中，选择 `TileMaps/surface z=0`

### 配置 Obstacle Tilemaps

1. 找到 `Obstacle Tilemaps` 属性
2. 同样设置数组大小为 `1`
3. 指定为 `TileMaps/Obstacle z=2`

> 💡 提示: 如果你的关卡暂时没有障碍物层，Obstacle Tilemaps 可以留空。但 Movement Tilemaps **不能为空**，否则系统会自动用 `surface z=0` 作为回退，但可能不符合预期。

---

## 2.5 配置 obstacles_tilemap_layer

根节点（BaseLevel）有一个 `@export` 属性 `obstacles_tilemap_layer`，用于在运行时将实体节点重新挂载到障碍物层实现 Y-Sort（前后遮挡排序）。

1. 在场景树中选中**根节点**
2. 在检查器面板中找到 `Obstacles Tilemap Layer` 属性
3. 点击属性右侧的 **指定 (Assign)** 按钮
4. 选择你的障碍物层（例如 `TileMaps/Obstacle z=2`）

> ❌ 常见错误: 如果忘记设置此属性，运行时控制台会报错 `obstacles_tilemap_layer is not set; cannot reparent entities`，并且角色节点不会正确显示前后遮挡关系。

---

## 2.6 完成后的场景树

以下是一个正确配置的新关卡场景树示例：

```
Level1-5 (Node2D)                     ← 根节点，附带 level1-5.gd 脚本
├── TileMaps (Node2D)                 ← 继承自 base_level
│   ├── surface z=0 (TileMapLayer)    ← 新建的地表层
│   ├── Obstacle z=2 (TileMapLayer)   ← 新建的障碍物层
│   └── decoration z=1 (TileMapLayer) ← 新建的装饰层（可选）
├── Entities (Node2D)                 ← 继承自 base_level
│   └── Units (Node2D)               ← 稍后在此添加单位
├── MoveOverlay (Node2D)              ← 继承自 base_level（不要修改）
├── Camera2D (LevelCamera)            ← 继承自 base_level
├── GUI (CanvasLayer)                 ← 继承自 base_level（不要修改）
├── StatusBarScene                    ← 继承自 base_level（底部状态栏）
├── MovementManager (Node)            ← 已配置 movement/obstacle tilemaps
└── SpecialTiles (Node2D)             ← 继承自 base_level
```

---

## 2.7 使用纯地图场景

项目中的 `scenes/levels/maps/` 文件夹包含一些纯地图场景（没有关卡逻辑，只有地形绘制）。这些可以作为地图美术的参考。

现有的纯地图文件：
- `1.tscn`
- `default map.tscn`
- `level1-1v2.tscn`、`level1-2v2.tscn` 等

如果美术同学先在独立场景中绘制好了地图，你可以：

1. 打开纯地图场景
2. 复制其中的 TileMapLayer 节点
3. 粘贴到你的关卡场景的 TileMaps 节点下

---

下一章: [02-地形绘制](02-terrain-painting.md) | 返回: [目录](README.md)
