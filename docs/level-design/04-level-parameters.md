# 04 -- 关卡参数

> 本章介绍关卡中的核心配置：队伍系统、阵营与回合机制、特殊地块、对话系统、过场动画等。这些是让关卡从"地图+角色"变成"可玩战斗"的关键。
>
> **如果你没写过 GDScript**，请先阅读下方 6.0 节的代码编辑器入门。

---

## 6.0 代码编辑器入门（第一次写 .gd 请先读这一节）

如果你已经会写 GDScript，直接跳到 6.1 节。

### 6.0.1 两种编辑器选择

本项目支持两种代码编辑方式，**任选其一即可**：

| 编辑器 | 优点 | 缺点 | 何时使用 |
|--------|------|------|----------|
| **Godot 内置脚本编辑器** | 无需安装，与场景编辑紧密集成，自动补全 Node 路径 | 界面较简陋 | 快速修改、临时调试 |
| **VSCode + godot-tools 插件** | 更强大的补全、Git 集成、多文件标签 | 需要额外配置，需要先启动 Godot LSP | 大段脚本编写 |

**新手推荐先用 Godot 内置编辑器**，等熟悉了再切换到 VSCode。

### 6.0.2 使用 Godot 内置编辑器

1. 在 Godot 主界面顶部，点击 **Script** 切换到脚本视图（快捷键 `Ctrl+F11` 循环切换视图）
2. 左侧会出现已打开的脚本列表
3. 要打开一个脚本：在 **文件系统 (FileSystem)** 面板中双击 `.gd` 文件
4. 要保存脚本：`Ctrl+S`
5. 要切换回场景编辑：点击顶部的 **2D** 按钮

**脚本编辑器界面：**

```
┌─────────────────────────────────────────────────┐
│ 已打开脚本列表   │                                │
│ ▸ base_level.gd │     代码编辑区                  │
│ ▸ level1-5.gd   │     (这里输入代码)              │
│                 │                                │
├─────────────────┴────────────────────────────────┤
│ ⑦ 输出 (Output) 面板 — print() 的结果会打印在这里 │
│     Debugger 面板 — 运行时错误会显示在这里         │
└──────────────────────────────────────────────────┘
```

### 6.0.3 使用 VSCode + godot-tools（可选）

如果你更习惯 VSCode：

1. **安装 VSCode**：从 https://code.visualstudio.com 下载
2. **安装 godot-tools 扩展**：在 VSCode 扩展市场搜索 `godot-tools`，作者 geequlim，点击 Install
3. **启用 Godot 语言服务器**：
   - 打开 Godot 编辑器 -> 顶部菜单 **编辑器 (Editor) -> 编辑器设置 (Editor Settings)**
   - 搜索 `language server`
   - 确认 **Network > Language Server > Remote Host** = `127.0.0.1`，**Remote Port** = `6005`，**Enable Smart Resolve** 已勾选
4. **在 VSCode 中打开项目**：`文件 -> 打开文件夹`，选择仓库根目录
5. **只要 Godot 编辑器保持打开**，VSCode 就能获得跳转、补全、诊断等能力

> ⚠️ 注意: godot-tools 依赖运行中的 Godot 编辑器作为 LSP 服务器。如果补全失效，检查 Godot 是否还开着。

### 6.0.4 GDScript 最小语法你必须知道的

看懂本项目中的关卡脚本，你只需要理解以下几个概念：

```gdscript
# 1. 注释：# 开头到行尾
## 双井号是"文档注释"，会显示在 Godot 检查器中


# 2. extends：说明这个脚本继承自哪个类
extends BaseLevel


# 3. 常量：全大写，preload() 在脚本加载时读取资源
const DialogueBoxScene := preload("res://scenes/ui/dialogue_box.tscn")


# 4. 成员变量：在整个脚本中都可访问
var _player: Node2D
var _turn_count: int = 0


# 5. @export：让变量出现在检查器中供设计师修改
@export var enemy_hp_bonus: int = 0


# 6. 函数：func 关键字 + 名称 + (参数) -> 返回类型
func _ready() -> void:
    print("场景已加载")


# 7. 覆盖父类方法：通常是 _on_xxx 形式的钩子
func _on_level_ready() -> void:
    # 关卡初始化完成后自动调用
    pass


# 8. 节点引用：$ 语法是 get_node 的缩写
func do_something() -> void:
    var player := $"Entities/Units/LiChun"
    print(player.name)


# 9. if / match / for
func check() -> void:
    if _turn_count > 5:
        print("超时！")
    elif _turn_count >= 3:
        print("时间紧迫")

    for team in teams:
        print(team.team_name)
```

### 6.0.5 几个关键"魔法"函数（生命周期钩子）

BaseLevel 会在不同时机自动调用以下方法。如果你想在这些时机插入逻辑，在你的关卡脚本中**覆盖（override）**它们即可：

| 函数 | 调用时机 | 用途 |
|------|----------|------|
| `_ready()` | 场景节点全部就绪后（底层 Godot 生命周期） | **一般不要覆盖**，用 `_on_level_ready` 代替 |
| `get_teams_config() -> Array` | BaseLevel 初始化队伍前 | **必须覆盖**，返回队伍配置（见 6.1 节） |
| `_on_level_ready() -> void` | 队伍初始化完成、相机就位、可以开始战斗前 | 插入开场对话、标记主角、运行时装配技能 |
| `_on_unit_moved() -> void` | 任何单位完成一次移动后 | 检查胜利条件、触发位置相关对话 |

> ⚠️ 注意: 不要直接覆盖 `_ready()`。BaseLevel 的 `_ready()` 会做大量初始化工作（查找 TileMapLayer、挂载实体、创建 UI），如果你覆盖了它而没有调用 `super._ready()`，关卡会无法运行。请使用 `_on_level_ready()` 这种语义清晰的钩子。

### 6.0.6 如何查看报错

1. **运行时错误**：按 F6 运行后，看 Godot 底部的 **Debugger（调试器）** 面板。红色行就是错误，双击能跳到出错的代码行
2. **解析错误**：脚本有语法错误时，底部的 **Output（输出）** 面板会立即显示，格式为：
   ```
   res://scenes/levels/level1-5/level1-5.gd:12 - Parse Error: Unexpected "Identifier" ...
   ```
   文件名后跟行号和错误描述
3. **自己打印日志**：在代码中加 `print("xxx: ", some_var)`，运行时会在 Output 面板看到

### 6.0.7 常见坑

| 坑 | 症状 | 解决 |
|----|------|------|
| 缩进用 Tab 和空格混合 | Parse Error: Used space character for indentation | 统一使用 Tab 或统一使用空格 |
| 函数参数缺少类型 | 函数能运行但补全不给力 | 写 `func foo(x: int) -> void:`，不要 `func foo(x):` |
| 忘记 `$` 引号 | `Node not found` | 带空格/中文的路径必须用 `$"Entities/Units/Li Chun"`，纯英文可写 `$Entities/Units/LiChun` |
| 改了场景树节点名忘记改脚本 | 运行时报 Node not found | 场景树改名后，**立即**去脚本里同步改引用 |
| 覆盖了 `_ready` 没调 `super._ready` | 关卡界面全空白 | 改用 `_on_level_ready()` |

---

## 6.1 队伍配置（get_teams_config）

### 为什么需要队伍配置

在回合制战棋中，角色分属不同队伍，轮流行动。BaseLevel 通过 `get_teams_config()` 方法获取队伍信息。如果你不覆盖这个方法（即不写队伍配置），系统会退回到"旧版单玩家模式"，只有一个角色可以操作。

**绝大多数战斗关卡都需要队伍配置。**

### 配置格式

在你的关卡脚本中覆盖 `get_teams_config()` 方法，返回一个数组。数组中每个元素是一个 Dictionary，描述一支队伍：

```gdscript
extends BaseLevel

func get_teams_config() -> Array:
    return [
        {
            "name": "玩家队伍",       # 显示名，会出现在回合标签上
            "faction": "好人",       # 阵营名，同阵营队伍之间不可互相攻击
            "controller": "player",  # "player" = 玩家操控, "ai" = 电脑操控
            "units": [               # 该队伍包含的单位节点
                $"Entities/Units/LiChun",
                $"Entities/Units/Guard1",
            ],
        },
        {
            "name": "敌方队伍",
            "faction": "坏人",
            "controller": "ai",
            "units": [
                $"Entities/Units/Enemy1",
                $"Entities/Units/Enemy2",
            ],
        },
    ]
```

### 字段说明

| 字段 | 类型 | 必须 | 说明 |
|------|------|------|------|
| `name` | String | 是 | 队伍显示名称。会出现在顶部的回合提示标签中，如 `[ 玩家队伍 的回合 ]` |
| `faction` | String | 是 | 阵营名称。**同 faction 的队伍之间不可互相攻击**。名称可自定义 |
| `controller` | String | 是 | 控制方式。`"player"` 为玩家手动操作，`"ai"` 为电脑自动操作 |
| `units` | Array[Node] | 是 | 该队伍中的单位节点引用。使用 `$"路径"` 语法引用场景树中的节点 |

### 回合顺序

队伍按照它们在数组中的**顺序**依次行动。例如上面的配置：

```
第1回合：玩家队伍（玩家操控）→ 敌方队伍（AI操控）
第2回合：玩家队伍 → 敌方队伍
...
```

如果需要三支队伍（如 test 关卡），排列顺序即为回合顺序：

```gdscript
return [
    { "name": "玩家队伍", "faction": "好人", "controller": "player", ... },
    { "name": "盟友队伍", "faction": "好人", "controller": "ai", ... },
    { "name": "贼人队伍", "faction": "坏人", "controller": "ai", ... },
]
# 回合顺序：玩家 → 盟友（AI自动） → 贼人（AI自动） → 玩家 → ...
```

> 提示: 标准的回合顺序为：主角回合 -> 敌方回合 -> 友方辅助回合。你可以通过调整数组顺序来实现不同的回合安排。

### 阵营（faction）机制

- 阵营名称是**任意字符串**，如 `"好人"`、`"坏人"`
- **相同 faction** 的队伍：属于同一方，技能不会对同阵营单位造成伤害
- **不同 faction** 的队伍：属于对立方，攻击技能可以作用于对方
- 一个 faction 可以有多支队伍（例如"好人"阵营下可以有玩家队伍和盟友队伍）

### 多支玩家队伍 vs AI 盟友

可以有多支 `controller = "player"` 的队伍，它们会分别轮到各自的回合，由玩家分别操控。也可以将盟友设为 `controller = "ai"`，让 AI 自动操控盟友。

这在策划设计中用于区分：
- **"主角队伍"**（`controller = "player"`）：李春，行动力自由分配
- **"盟友队伍"**（`controller = "ai"` 或 `"player"`）：工匠等，可由 AI 或玩家操控

> 注意: 当前 AI 行为为占位实现（随机移动一步），因此如果你希望盟友有更复杂的行为，暂时建议设为 `"player"` 由玩家手动控制。

---

## 6.2 单位节点引用

### $"路径" 语法

在 `get_teams_config()` 中，`$"Entities/Units/LiChun"` 是 GDScript 的节点路径缩写，等价于 `get_node("Entities/Units/LiChun")`。

路径规则：
- 从**当前脚本所在的节点**（即关卡根节点）开始
- 用 `/` 分隔层级
- 名称必须与场景树中的节点名称**完全一致**（区分大小写）

### 保存节点引用的最佳实践

在 `get_teams_config()` 中通过 `$"..."` 获取的节点引用，建议同时保存为成员变量，以便在 `_on_level_ready()` 中使用：

```gdscript
extends BaseLevel

var _player: Node2D
var _enemy1: Node2D

func get_teams_config() -> Array:
    _player = $"Entities/Units/Player"
    _enemy1 = $"Entities/Units/Enemy1"
    return [
        { "name": "玩家", "faction": "好人", "controller": "player", "units": [_player] },
        { "name": "敌方", "faction": "坏人", "controller": "ai", "units": [_enemy1] },
    ]

func _on_level_ready() -> void:
    # 此时可以直接使用 _player 和 _enemy1
    if _player is Unit and _player.combat_stats:
        _player.combat_stats.is_hero = true
```

### 常见路径问题

> 常见错误: 节点名称与脚本中的引用不匹配。

例如，你在场景树中将单位命名为 `li_chun`，但脚本中写了 `$"Entities/Units/LiChun"`。运行时会报错：

```
Node not found: "Entities/Units/LiChun" (relative to "/root/Level1-1")
```

解决方法：确保场景树中的节点名和脚本中的引用**完全一致**。

> 常见错误: 在 `get_teams_config()` 中引用了不存在的节点。

如果你删除了一个单位节点但忘记更新脚本，运行时会崩溃。每次增删单位时，都要同步更新 `get_teams_config()`。

---

## 6.3 特殊地块

特殊地块是一种可交互的地图元素，角色在其上停留、经过或离开时可以触发特殊效果。例如：勘测点、治疗泉、陷阱等。

### 特殊地块的工作原理

`SpecialTile`（`scenes/levels/base_level/special_tile.gd`）是所有特殊地块的基类。它有三个可覆盖的方法：

| 方法 | 触发时机 | 用途示例 |
|------|----------|----------|
| `_on_unit_arrive(entity)` | 角色移动结束后，最终停留在此地块上 | 勘测点完成、治疗泉恢复 |
| `_on_unit_pass(entity)` | 角色路过此地块但没有停留 | 经过陷阱触发 |
| `_on_unit_depart(entity)` | 角色从此地块出发去往其他地方 | 离开安全区域 |

### 放置特殊地块

1. 在场景树中，找到 **SpecialTiles** 节点
2. 右键点击 -> **实例化子场景 (Instantiate Child Scene)**
3. 选择 `scenes/levels/base_level/special_tile.tscn`
4. 在 2D 视图中将其拖拽到目标格子位置
5. 运行时系统会自动吸附到最近的格子

### 创建自定义特殊地块

如果你需要自定义交互逻辑（非程序员可跳过此节）：

1. 在你的关卡文件夹中创建一个新脚本，例如 `my_special_tile.gd`
2. 内容模板：

```gdscript
extends SpecialTile
## 自定义特殊地块说明。

func _on_unit_arrive(entity: Node2D) -> void:
    print("%s 到达了特殊地块！" % entity.name)
    # 在此添加你的逻辑

func _on_unit_pass(entity: Node2D) -> void:
    print("%s 路过了特殊地块" % entity.name)

func _on_unit_depart(entity: Node2D) -> void:
    print("%s 离开了特殊地块" % entity.name)
```

3. 将此脚本附加到场景中的 SpecialTile 实例上

### 特殊地块颜色

每个 SpecialTile 有一个 `Tile Color` 属性，可以在检查器中设置。这个颜色决定了地块的视觉标记颜色（通过内部的 Polygon2D 显示）。

推荐颜色约定：

| 地块类型 | 颜色 | RGBA 建议值 |
|----------|------|-------------|
| 勘测点 | 紫色 | `(0.5, 0.0, 1.0, 0.6)` |
| 治疗点 | 绿色 | `(0.0, 0.8, 0.3, 0.6)` |
| 陷阱 | 红色 | `(0.9, 0.1, 0.1, 0.6)` |

> 提示: 参考 test 关卡中的 `test_special_tile.gd` 了解完整示例。它会在三种交互时打印日志消息，方便调试。

---

## 6.4 对话系统

关卡中可以在任意时机触发 RPG 风格的对话框，支持左/右头像、打字机效果和 BBCode 富文本。

### 对话数据结构

每条对话由 `DialogueLine` 资源表示：

| 字段 | 类型 | 说明 |
|------|------|------|
| `speaker` | String | 说话者名称（留空则隐藏名称栏） |
| `text` | String | 对话文本（支持 BBCode，如 `[color=red]重点[/color]`） |
| `portrait` | Texture2D | 说话者头像（留空则不显示头像） |
| `portrait_side` | String | 头像位于哪侧：`"left"`（左侧）或 `"right"`（右侧） |

### 在关卡中触发对话

1. 首先在脚本中预加载对话框场景：

```gdscript
const DialogueBoxScene := preload("res://scenes/ui/dialogue_box.tscn")
```

2. 在需要触发对话的地方构建对话行并启动：

```gdscript
func _some_trigger() -> void:
    var portrait_lc := preload("res://assets/face/li_chun.png")
    var lines: Array[DialogueLine] = [
        DialogueLine.create("李春", "这条河流看起来很危险。", portrait_lc, "left"),
        DialogueLine.create("工匠", "我们需要先勘测地形才能动工。"),
        DialogueLine.create("李春", "好的，我来探路。", portrait_lc, "left"),
    ]
    var box: DialogueBox = DialogueBoxScene.instantiate()
    add_child(box)
    box.start(lines)
    await box.dialogue_finished
    # 对话结束后继续执行后续逻辑
```

### 对话框操作

对话框显示时，玩家通过以下方式推进：

| 操作 | 输入 |
|------|------|
| 显示全文（打字机播放中） | 鼠标左键 / 空格 / 回车 |
| 翻到下一句（当前句已完整显示） | 鼠标左键 / 空格 / 回车 |
| 最后一句翻完后 | 对话框自动淡出消失 |

### 常见对话触发时机

- **关卡开场**: 在 `_on_level_ready()` 中触发
- **特定位置到达**: 在 `_on_unit_moved()` 中检查角色位置
- **特殊地块**: 在 SpecialTile 的 `_on_unit_arrive()` 中触发
- **回合条件**: 在自定义的回合计数逻辑中触发

> 提示: 对话框显示期间，关卡的操作输入会被对话框拦截（因为对话框在 CanvasLayer 80 层，高于游戏画面）。`await box.dialogue_finished` 会等到玩家读完所有对话后才继续。

---

## 6.5 过场动画

### 关卡前后过场

游戏支持在关卡开始前和结束后播放过场动画（漫画式图片序列）。过场数据在 `scripts/game_state.gd` 中注册：

```gdscript
const CUTSCENE_DATA: Dictionary = {
    "关卡1-1": {
        "pre": [                                      # 关卡前过场
            "res://assets/cutscenes/level1-1/pre_01.png",
            "res://assets/cutscenes/level1-1/pre_02.png",
        ],
        "post": [                                     # 关卡后过场
            "res://assets/cutscenes/level1-1/post_01.png",
        ],
    },
}
```

添加新关卡的过场：

1. 准备过场图片（PNG 格式），放在 `assets/cutscenes/你的关卡名/` 下
2. 打开 `scripts/game_state.gd`
3. 在 `CUTSCENE_DATA` 中添加新条目
4. `"pre"` 数组中的图片在关卡开始前播放
5. `"post"` 数组中的图片在关卡通关后播放

### 关卡中途过场

BaseLevel 提供 `play_mid_cutscene()` 方法，可以在关卡进行中插入过场：

```gdscript
# 在关卡脚本中调用
await play_mid_cutscene([
    "res://assets/cutscenes/level1-1/mid_01.png",
    "res://assets/cutscenes/level1-1/mid_02.png",
])
# 过场结束后继续执行
```

这个方法会：
1. 暂停关卡输入处理
2. 以覆盖层形式播放图片序列
3. 玩家点击或按空格/回车翻页
4. 全部翻完后返回，恢复关卡输入

> 提示: 中途过场通常在特定条件触发时调用（如角色到达某个位置、击败 Boss 等）。触发逻辑需要在关卡脚本中编写。

---

## 6.6 关卡完成

当关卡达成胜利条件时，调用 `complete_level()` 方法：

```gdscript
# 在关卡脚本中，当胜利条件满足时
complete_level()
```

此方法会：
1. 检查是否有关卡后过场动画
2. 如有，播放过场后返回主菜单
3. 如无，直接返回主菜单

> 注意: 当前版本没有内置的胜负条件检测系统。你需要在关卡脚本中自行编写条件判断逻辑。常见的触发点包括：
> - 覆盖 `_on_unit_moved()` 检查角色位置
> - 在特殊地块的 `_on_unit_arrive()` 中触发
> - 在每回合结束时检查存活单位数

---

## 6.7 护送目标

UnitData 中有一个 `is_escort_target` 属性。标记为护送目标的单位（如测量工）如果被击败，应导致关卡失败。

设置方法：

1. 在单位的 UnitData 中，将 **Is Escort Target** 设为 `true`
2. 在关卡脚本中编写检测逻辑（当前需手动实现）

> 提示: `survey_worker.tres`（测量工）已预设 `is_escort_target = true`，可作为参考。

---

## 6.8 obstacles_tilemap_layer 属性

这个属性在 [01-地图创建](01-map-creation.md) 中提到过，但这里详细解释其作用：

BaseLevel 在运行时会将 `Entities/Units` 下的所有单位节点**重新挂载**到 `obstacles_tilemap_layer` 指定的 TileMapLayer 下。这是为了实现 **Y-Sort（前后遮挡排序）**。

在等距视角中，"靠近屏幕下方"的物体应该遮挡"靠近屏幕上方"的物体。Godot 的 Y-Sort 机制要求所有需要排序的节点在同一个父节点下。

配置步骤（如果还没有设置）：

1. 选中关卡根节点
2. 在检查器中找到 **Obstacles Tilemap Layer** 属性
3. 指定为障碍物层（例如 `TileMaps/Obstacle z=2`）

系统会自动：
- 将障碍物层的 `y_sort_enabled` 设为 `true`
- 将所有实体的 `y_sort_enabled` 设为 `true`

---

## 6.9 技能运行时装配

如果你需要在关卡初始化时为单位运行时装配技能（而不是在 UnitData 的 `.tres` 文件中预设），可以在 `_on_level_ready()` 中进行。test 关卡展示了这种模式：

```gdscript
func _on_level_ready() -> void:
    # 预加载技能 .tres 文件
    var sk_strike: SkillData = preload("res://data/skills/lc_rule_strike.tres")

    # 运行时创建技能
    var sk_custom := SkillData.new()
    sk_custom.skill_id = "custom_skill"
    sk_custom.skill_name = "自定义技能"
    sk_custom.skill_type = Enums.SkillType.ATTACK
    sk_custom.ap_cost = 20
    sk_custom.damage_ratio = 1.0
    sk_custom.cast_offsets = OffsetPresets.diamond(1, 3)
    sk_custom.effect_offsets = OffsetPresets.SINGLE

    # 装配到单位（需先对 unit_data 做 duplicate 避免污染原始资源）
    if _player is Unit and _player.unit_data:
        _player.unit_data = _player.unit_data.duplicate()
        var typed: Array[SkillData] = [sk_strike, sk_custom]
        _player.unit_data.skills = typed
```

> 注意: 运行时装配技能时，务必先 `duplicate()` unit_data，否则会修改共享的 `.tres` 文件（参见 [05-资源唯一化](05-resource-uniqueness.md)）。

---

## 6.10 完整关卡脚本示例

以下是一个中等复杂度的关卡脚本示例：

```gdscript
extends BaseLevel
## 关卡 1-5：李春带领队伍渡河。

const DialogueBoxScene := preload("res://scenes/ui/dialogue_box.tscn")
var _sk_strike: SkillData = preload("res://data/skills/lc_rule_strike.tres")
var _sk_stone: SkillData = preload("res://data/skills/lc_cast_stone_arrest_flow.tres")

var _player: Node2D
var _guard1: Node2D
var _survey: Node2D
var _enemy1: Node2D
var _enemy2: Node2D


func get_teams_config() -> Array:
    _player = $"Entities/Units/LiChun"
    _guard1 = $"Entities/Units/Guard1"
    _survey = $"Entities/Units/SurveyWorker"
    _enemy1 = $"Entities/Units/DarkCurrent1"
    _enemy2 = $"Entities/Units/WhirlPool1"
    return [
        {
            "name": "李春队伍",
            "faction": "好人",
            "controller": "player",
            "units": [_player],
        },
        {
            "name": "工匠队伍",
            "faction": "好人",
            "controller": "player",
            "units": [_guard1, _survey],
        },
        {
            "name": "水患",
            "faction": "坏人",
            "controller": "ai",
            "units": [_enemy1, _enemy2],
        },
    ]


func _on_level_ready() -> void:
    # 标记主角
    if _player is Unit and _player.combat_stats:
        _player.combat_stats.is_hero = true

    # 开场对话
    var portrait := preload("res://assets/face/li_chun.png")
    var lines: Array[DialogueLine] = [
        DialogueLine.create("李春", "前方就是渡口，注意水势。", portrait),
    ]
    var box: DialogueBox = DialogueBoxScene.instantiate()
    add_child(box)
    box.start(lines)
    await box.dialogue_finished


func _on_unit_moved() -> void:
    # 每次有单位移动后检查胜利条件
    # 例如：检查测量工是否到达目标位置
    pass
```

---

## 6.11 调用 Notify 发送通知

`Notify` 是全局 **autoload 单例**（`scripts/notification_manager.gd`），可以在任意脚本中直接调用，让屏幕上弹出一条滑入式通知。无需 preload、无需 `get_node`。

### 函数签名

```gdscript
Notify.notify(
    text: String,                                # 通知文本，支持 BBCode 富文本
    pos: Notify.Position = Notify.Position.TOP_RIGHT,  # 弹出位置
    style: Notify.Style = Notify.Style.INFO,           # 样式
    duration: float = 3.0                              # 显示时长（秒）
) -> void
```

### 位置枚举

| 枚举值 | 说明 | 典型用途 |
|--------|------|----------|
| `Notify.Position.TOP_LEFT` | 左上角 | 次要信息 |
| `Notify.Position.TOP_RIGHT` | 右上角（默认） | 战斗详情、化势反馈 |
| `Notify.Position.BOTTOM_LEFT` | 左下角 | 调试信息 |
| `Notify.Position.BOTTOM_RIGHT` | 右下角 | 成就、奖励 |
| `Notify.Position.TOP_CENTER` | 顶部横幅 | 重要公告 |
| `Notify.Position.BOTTOM_CENTER` | 底部横幅 | 任务提示 |
| `Notify.Position.CENTER` | 屏幕正中（大字+阴影） | 关卡胜利/失败 |

> 💡 提示: 所有 `TOP_*` 位置会自动避开顶部 HudPanel（`TOP_BAR_HEIGHT = 26`，见 `scripts/notification_manager.gd:58`），不会与回合标签重叠。

### 样式枚举

| 枚举值 | 图标 | 配色 | 典型用途 |
|--------|------|------|----------|
| `Notify.Style.INFO` | ℹ | 深蓝 | 一般信息 |
| `Notify.Style.SUCCESS` | ✔ | 深绿 | 任务完成、胜利 |
| `Notify.Style.WARNING` | ⚠ | 深黄 | 资源不足、危险警告 |
| `Notify.Style.ERROR` | ✖ | 深红 | 关卡失败、操作非法 |

### 示例

```gdscript
extends BaseLevel

func _on_level_ready() -> void:
    # 最简调用：右上角，INFO 样式，3 秒
    Notify.notify("欢迎来到安济桥工地")

    # 指定位置和样式：左上角，警告样式，5 秒
    Notify.notify(
        "洪水将至，注意避让",
        Notify.Position.TOP_LEFT,
        Notify.Style.WARNING,
        5.0
    )


func _on_unit_moved() -> void:
    # 使用 BBCode 富文本：颜色、粗体
    Notify.notify(
        "[color=#ffcc33]李春[/color]到达了 [b]工地东岸[/b]",
        Notify.Position.BOTTOM_CENTER,
        Notify.Style.SUCCESS
    )


func _show_victory() -> void:
    # 屏幕正中大字提示
    Notify.notify(
        "关卡胜利",
        Notify.Position.CENTER,
        Notify.Style.SUCCESS,
        2.5
    )
```

### 配合 ElementColors 使用

项目内置了 `ElementColors` 全局类（见 [附录 B § B.13](appendix-creature-reference.md#b13-元素颜色全局类-elementcolors)），可以快速生成带五行元素颜色的 BBCode 片段：

```gdscript
var text := "击中目标：%s" % ElementColors.bbcode(Enums.Element.WATER, "水×2")
Notify.notify(text, Notify.Position.TOP_RIGHT, Notify.Style.INFO)
# 显示效果：击中目标：水×2（"水×2"部分为天蓝色）
```

### 注意事项

- 通知是**非阻塞**的：调用后立即返回，不会暂停游戏。如果需要等玩家确认再继续，用对话框（6.4 节）而不是 Notify
- 多条通知会**自动堆叠**：同一位置连续发的通知会纵向排列
- **战斗系统已经在内部使用 Notify**：化势触发时会自动在右上角发送富文本详情（见 [07-测试与调试 § 7.3b](07-testing.md#73b-化势反馈三层-ui)），设计师**不需要**手动为化势发通知

---

## 6.12 关卡参数配置检查清单

- [ ] `get_teams_config()` 已正确覆盖，包含所有队伍
- [ ] 所有 `$"..."` 路径与场景树中的节点名一致
- [ ] 阵营名称（faction）正确分组（友方同阵营，敌方不同阵营）
- [ ] 回合顺序合理（通常：玩家 -> 敌方 -> 友方辅助）
- [ ] `obstacles_tilemap_layer` 已设置
- [ ] 如需过场动画，已在 `game_state.gd` 的 `CUTSCENE_DATA` 中注册
- [ ] 如有护送目标，对应 UnitData 的 `is_escort_target = true`
- [ ] 如有特殊地块，已放在 `SpecialTiles` 节点下
- [ ] 如有对话，已准备好 DialogueLine 数据和头像图片
- [ ] 主角单位在 `_on_level_ready()` 中标记了 `is_hero = true`

---

下一章: [05-资源唯一化](05-resource-uniqueness.md) | 上一章: [03-单位配置](03-unit-placement.md)
