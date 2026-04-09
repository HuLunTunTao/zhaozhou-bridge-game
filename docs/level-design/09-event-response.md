# 09. 事件-响应系统

> 本章面向已经会写最简单关卡脚本的设计师。如果你还不知道什么是 GDScript、`func` 是什么、`extends BaseLevel` 是什么意思，请先阅读 [04 § 6.0 代码编辑器入门](04-level-parameters.md#60-代码编辑器入门)。

## 9.1 这个系统是什么

游戏运行时会发生很多"事情"：
- 某个单位死了
- 玩家走到了第 3 大回合
- 主角踩到了一个特殊地块
- 一个敌人的 HP 被打到了 50% 以下
- 主角学会了一个新技能

这些"事情"叫做**事件**（Event）。

针对每个事件，你可能想让游戏做出**反应**：
- 弹一条通知
- 触发一段对话
- 播放一段过场动画
- 在地图上凭空生成一队援军
- 直接判定关卡胜利或失败

这些"反应"叫做**响应**（Response）。

你只需要在关卡脚本里写**几行 GDScript**，就能把任何事件连接到任何响应。这就是事件-响应系统。

---

## 9.2 快速开始：5 分钟做出"踩到桥址触发对话"

打开你的关卡脚本（例如 `scenes/levels/level1-1/level1-1.gd`），在里面写：

```gdscript
extends BaseLevel

# flag 变量：用来记住"是否已经触发过"，避免每次走过都触发
var _bridge_dialogue_played := false


func _on_level_ready() -> void:
	# 关卡刚加载完。在这里"订阅"你想监听的事件。
	movement_manager.tile_entered.connect(_on_tile_entered)


func _on_tile_entered(cell: Vector2i, entity: Node2D) -> void:
	# 任何单位走进任何格子时都会调用这个函数。
	# 我们只关心 (3, 5) 这个格子，且只触发一次。
	if cell == Vector2i(3, 5) and not _bridge_dialogue_played:
		_bridge_dialogue_played = true
		Notify.notify("发现桥址！", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 3.0)
```

按 `F6` 运行关卡，让任意单位走到 (3, 5) — 屏幕顶部应该闪现 "发现桥址！" 通知。

**这就是事件-响应系统的全部精髓**。剩下的章节告诉你**还有哪些事件可以监听、哪些响应可以触发**。

---

## 9.3 事件清单

所有事件都通过 GDScript 的 **signal**（信号）机制工作。关卡脚本在 `_on_level_ready()` 里用 `signal_name.connect(your_function)` 来"订阅"，对应事件发生时你的函数就会被自动调用。

### 9.3.1 关卡内事件（信号挂在 `self` / `BaseLevel` 上）

| 信号名 | 触发时机 | 参数 | 典型用途 |
|---|---|---|---|
| `unit_died` | 任意单位 HP 降到 0 | `unit: Unit` | 主角死亡 → 失败；所有敌人死亡 → 胜利 |
| `unit_hp_changed` | 任意单位 HP 变化（受伤/治疗/DoT/休息恢复） | `unit, old_hp, new_hp` | HP 阈值监控 |
| `round_started` | 新的大回合开始（所有队伍各打完一次） | `round_number` | 第 N 回合触发剧情/援军 |
| `team_turn_started` | 某个队伍的小回合开始 | `team_index` | 敌方回合开始时弹出警告 |
| `unit_gained_skill` | 单位被授予一个新技能（通过 `grant_skill`） | `unit, skill` | 弹出"习得新技能"提示 |
| `unit_lost_skill` | 单位被收回一个技能（通过 `revoke_skill`） | `unit, skill` | — |

**用法**：

```gdscript
func _on_level_ready() -> void:
	unit_died.connect(_on_any_unit_died)
	round_started.connect(_on_round_started)


func _on_any_unit_died(unit: Unit) -> void:
	print(unit.combat_stats.unit_name, " 死了")


func _on_round_started(round_num: int) -> void:
	print("第 ", round_num, " 大回合开始")
```

### 9.3.2 单位移动相关事件

`movement_manager` 是 `BaseLevel` 的子节点，提供了两个移动信号：

| 信号 | 来源 | 参数 | 用途 |
|---|---|---|---|
| `movement_manager.tile_entered` | `MovementManager` | `cell: Vector2i, entity: Node2D` | 单位走进某格 |
| `movement_manager.tile_exited` | `MovementManager` | `cell: Vector2i, entity: Node2D` | 单位走出某格 |

```gdscript
func _on_level_ready() -> void:
	movement_manager.tile_entered.connect(_on_tile_entered)


func _on_tile_entered(cell: Vector2i, entity: Node2D) -> void:
	# entity 是任意 Node2D，要先判断是不是 Unit 才能访问 combat_stats
	if not entity is Unit:
		return
	if cell == Vector2i(0, 0):
		Notify.notify("到达原点！")
```

### 9.3.3 关卡初始化与移动后回调

这两个不是信号，而是**可以 override 的方法**（虚函数）：

| 方法 | 触发时机 | 用途 |
|---|---|---|
| `_on_level_ready()` | 关卡刚加载完，所有节点就绪 | 在这里 connect 你的事件监听 |
| `_on_unit_moved()` | 任意单位完成一次移动后 | 关卡通用的"动一步检查一次"逻辑 |

```gdscript
func _on_level_ready() -> void:
	print("关卡准备好了")
	# 在这里 connect 信号、设置初始状态


func _on_unit_moved() -> void:
	print("有单位刚走完一步")
```

### 9.3.4 特殊地块事件

如果你想为某些 tile 加上**只触发一次**或**只对某种单位生效**的复杂逻辑，最干净的方式是用 `SpecialTile` 子类。

参考 `scenes/levels/test/test_special_tile.gd:1-16`：

```gdscript
extends SpecialTile
## 一个示例：当单位最终停留在此地块时弹出通知。

func _on_unit_arrive(entity: Node2D) -> void:
	if entity is Unit:
		Notify.notify("到达检查点", Notify.Position.TOP_CENTER)


func _on_unit_pass(entity: Node2D) -> void:
	# 单位经过但没有停下时调用
	pass


func _on_unit_depart(entity: Node2D) -> void:
	# 单位从此地块离开时调用
	pass
```

把这个脚本挂到 `SpecialTiles` 节点下的 `Node2D` 实例上即可。

### 9.3.5 单位移动完成事件（细粒度）

每个 `Unit` 节点自身有一个 `move_finished` 信号：

```gdscript
func _on_level_ready() -> void:
	for unit in teams[0].units:
		unit.move_finished.connect(func(): print(unit.combat_stats.unit_name, " 走完了"))
```

通常不需要这么细，用 `_on_unit_moved()` 已经够了。

---

## 9.4 响应清单

响应不是信号，而是**你可以直接调用的方法/函数**。

### 9.4.1 通知（Notify）

`Notify` 是全局 autoload，任何脚本都可以直接调用 `Notify.notify(...)`，详见 [04 § 6.11](04-level-parameters.md#611-调用-notify-发送通知)。

```gdscript
Notify.notify("操作成功", Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 3.0)
```

支持 BBCode 富文本（颜色、加粗等）。

### 9.4.2 对话（Dialogue）

`BaseLevel.play_dialogue(lines)` — 一行播放一段对话，阻塞直到对话结束。

```gdscript
const _LICHUN_FACE := preload("res://assets/face/li_chun.png")

func _on_some_event() -> void:
	await play_dialogue([
		DialogueLine.create("李春", "此处便是桥址。", _LICHUN_FACE, "left"),
		DialogueLine.create("工匠", "李工，地势可还稳妥？", null, "right"),
		DialogueLine.create("李春", "且让我再勘一勘。", _LICHUN_FACE, "left"),
	])
	# 对话结束后继续...
	Notify.notify("对话已结束")
```

`DialogueLine.create(speaker, text, portrait, side)` 参数：
- `speaker: String` — 说话者名字（留空则隐藏名称栏）
- `text: String` — 对话文字（支持 BBCode）
- `portrait: Texture2D` — 头像（留空则不显示头像）
- `side: String` — `"left"` 或 `"right"`，头像位置

> 注意：调用 `play_dialogue` 必须用 `await`，否则对话框会立刻被销毁。

### 9.4.3 关卡胜利

`BaseLevel.complete_level()` — 触发关卡胜利。如果该关卡在 `GameState.CUTSCENE_DATA` 中配置了 `"post"` 过场，会先播放再回主菜单；否则直接回主菜单。

```gdscript
func _on_any_unit_died(unit: Unit) -> void:
	# 所有敌人死了 → 胜利
	var alive := 0
	for u in teams[2].units:
		if u.combat_stats.is_alive():
			alive += 1
	if alive == 0:
		complete_level()
```

### 9.4.4 关卡失败

`BaseLevel.defeat_level()` — 关卡失败，目前直接返回主菜单。

```gdscript
func _on_any_unit_died(unit: Unit) -> void:
	# 主角死了 → 失败
	if unit.combat_stats.is_hero:
		defeat_level()
```

> 注意：`is_hero` 是 `CombatStats` 上的字段，由 `_set_stats(..., is_hero_flag=true)` 设定。参考 `scenes/levels/test/test.gd:72`。

### 9.4.5 中场过场动画（Cutscene）

`BaseLevel.play_mid_cutscene(pages)` — 播放一段静态图片过场，阻塞直到玩家翻完所有页。

```gdscript
func _on_round_started(round_num: int) -> void:
	if round_num == 3:
		await play_mid_cutscene([
			"res://assets/cutscenes/level1-1/mid_reinforcements_01.png",
			"res://assets/cutscenes/level1-1/mid_reinforcements_02.png",
		])
		# 过场结束后继续...
```

**Cutscene 资源约定**：
- 每张图片是一页全屏过场（建议 1920x1080 PNG）
- 玩家点击鼠标 / 按空格 / 按回车翻页
- 资源放在 `res://assets/cutscenes/<关卡名>/mid_*.png`
- 在过场播放期间，玩家输入被屏蔽（`_mid_cutscene_active = true`）

**和开场/结尾过场的区别**：

| 类型 | 触发方式 | 资源位置 | 谁负责调用 |
|---|---|---|---|
| 开场（pre） | 进入关卡时**自动**播放 | `GameState.CUTSCENE_DATA[关卡名]["pre"]` | 引擎自动 |
| 结尾（post） | `complete_level()` 调用时**自动**播放 | `GameState.CUTSCENE_DATA[关卡名]["post"]` | 引擎自动 |
| **中场（mid）** | 关卡脚本**手动** `await play_mid_cutscene([...])` | 关卡脚本里写死路径 | **你**（设计师） |

也就是说：你只需要操心**中场过场**。开场和结尾通过在 `scripts/game_state.gd` 的 `CUTSCENE_DATA` 字典里加条目即可，详见 [08 § 关卡集成](08-integration.md)。

### 9.4.6 运行时生成单位（spawn_unit）

`BaseLevel.spawn_unit(unit_data, cell, team_index) -> Unit` — 在指定格子生成一个单位，加入指定队伍。

```gdscript
const _ENEMY_DATA := preload("res://data/units/ud_enemy_lunge.tres")

func _on_round_started(round_num: int) -> void:
	if round_num == 3:
		# 第 3 回合在 (5, 3) 生成一个敌人到队伍 2（贼人队伍）
		var new_enemy: Unit = spawn_unit(_ENEMY_DATA, Vector2i(5, 3), 2)
		Notify.notify("敌军援军抵达！", Notify.Position.TOP_RIGHT, Notify.Style.WARNING)
```

返回的 `Unit` 节点可以让你进一步配置（例如改 HP、加技能）。

> 注意：`spawn_unit` 出的单位**没有自定义技能**——它继承 `unit_data` 里写死的技能。如果你想动态改技能，下一节看 `grant_skill`。

### 9.4.7 授予/收回技能（grant_skill / revoke_skill）

`BaseLevel.grant_skill(unit, skill)` — 给单位添加一个技能。
`BaseLevel.revoke_skill(unit, skill)` — 移除单位的一个技能。

```gdscript
const _SKILL_NEW := preload("res://data/skills/lc_wedge_bank_probe.tres")

func _on_round_started(round_num: int) -> void:
	if round_num == 5:
		var hero: Unit = teams[0].units[0]
		grant_skill(hero, _SKILL_NEW)


# 用配套的 unit_gained_skill 信号弹通知
func _on_level_ready() -> void:
	unit_gained_skill.connect(_on_unit_gained_skill)


func _on_unit_gained_skill(unit: Unit, skill: SkillData) -> void:
	Notify.notify(
		"%s 习得了【%s】！" % [unit.combat_stats.unit_name, skill.skill_name],
		Notify.Position.TOP_RIGHT,
		Notify.Style.SUCCESS,
		4.0,
	)
```

**注意事项**：
- **幂等**：重复 `grant_skill` 同一个技能不会重复触发 `unit_gained_skill` 信号（已经拥有则不做任何事）
- **状态栏自动刷新**：如果该单位正好是当前选中的单位，状态栏的技能槽位会自动更新
- **不要绕过这两个方法**：如果你直接 `unit.unit_data.skills.append(skill)`，信号**不会**触发，而且可能污染磁盘上的 `.tres` 资源文件

---

## 9.5 常见模式

### 模式 A：只触发一次

用一个 `bool` 类型的 flag 变量：

```gdscript
var _first_blood_shown := false


func _on_any_unit_died(unit: Unit) -> void:
	if not _first_blood_shown:
		_first_blood_shown = true
		Notify.notify("首次击破！", Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS)
```

### 模式 B：第 N 回合后

用 `round_started` 信号 + `if round_num == N`：

```gdscript
func _on_round_started(round_num: int) -> void:
	match round_num:
		3:
			Notify.notify("第 3 回合：敌军援军即将抵达！", Notify.Position.TOP_CENTER, Notify.Style.WARNING)
		5:
			spawn_unit(_REINFORCEMENT_DATA, Vector2i(0, 0), 0)
		10:
			Notify.notify("超时！", Notify.Position.CENTER, Notify.Style.ERROR)
			defeat_level()
```

### 模式 C：HP 阈值监控

用 `unit_hp_changed` 比较 `old_hp` 和 `new_hp`：

```gdscript
func _on_any_unit_hp_changed(unit: Unit, old_hp: int, new_hp: int) -> void:
	if not unit.combat_stats.is_hero:
		return
	var half: int = unit.combat_stats.max_hp / 2
	# old_hp 在阈值之上，new_hp 已降到阈值之下 → 这次刚好穿越阈值
	if old_hp > half and new_hp <= half:
		Notify.notify("[color=#ff5050]血量告急！[/color]", Notify.Position.TOP_CENTER, Notify.Style.WARNING)
```

> 关键技巧：用"`old > 阈值 and new <= 阈值`"这个条件，可以精确捕捉到"刚好跌破阈值的那一瞬间"，避免每次受伤都触发。

### 模式 D：所有敌人死亡 → 胜利

```gdscript
func _on_any_unit_died(unit: Unit) -> void:
	var enemies_alive := 0
	for u in teams[2].units:  # teams[2] 是贼人队伍
		if u.combat_stats.is_alive():
			enemies_alive += 1
	if enemies_alive == 0:
		complete_level()
```

### 模式 E：主角死亡 → 失败

```gdscript
func _on_any_unit_died(unit: Unit) -> void:
	if unit.combat_stats.is_hero:
		defeat_level()
```

### 模式 F：到达指定格子触发剧情

```gdscript
var _visited := {}  # cell → bool


func _on_level_ready() -> void:
	movement_manager.tile_entered.connect(_on_tile_entered)


func _on_tile_entered(cell: Vector2i, entity: Node2D) -> void:
	if not entity is Unit:
		return
	if not entity.combat_stats.is_hero:
		return
	if _visited.has(cell):
		return
	_visited[cell] = true

	if cell == Vector2i(3, 5):
		await play_dialogue([
			DialogueLine.create("李春", "此处地势开阔，可立桥墩。", preload("res://assets/face/li_chun.png"), "left"),
		])
```

---

## 9.6 完整示例：第一关样例

```gdscript
extends BaseLevel
## 第一关：踏勘洨河

# ── 资源预加载 ──
const _ENEMY_DATA := preload("res://data/units/ud_enemy_water.tres")
const _SKILL_WEDGE := preload("res://data/skills/lc_wedge_bank_probe.tres")
const _LICHUN_FACE := preload("res://assets/face/li_chun.png")

# ── 关卡 flag ──
var _first_blood := false
var _bridge_visited := false
var _wedge_taught := false


func get_teams_config() -> Array:
	return [
		{
			"name": "玩家队伍",
			"faction": "好人",
			"controller": "player",
			"units": [$"Entities/Units/Player"],
		},
		{
			"name": "盟友队伍",
			"faction": "好人",
			"controller": "ai",
			"units": [$"Entities/Units/Ally1"],
		},
		{
			"name": "贼人队伍",
			"faction": "坏人",
			"controller": "ai",
			"units": [$"Entities/Units/Enemy1", $"Entities/Units/Enemy2"],
		},
	]


func _on_level_ready() -> void:
	# 订阅事件
	unit_died.connect(_on_any_unit_died)
	unit_hp_changed.connect(_on_any_unit_hp_changed)
	round_started.connect(_on_round_started)
	unit_gained_skill.connect(_on_unit_gained_skill)
	movement_manager.tile_entered.connect(_on_tile_entered)

	# 开场通知
	Notify.notify("第一关：踏勘洨河", Notify.Position.TOP_CENTER, Notify.Style.INFO, 3.0)


# ── 单位死亡 ──
func _on_any_unit_died(unit: Unit) -> void:
	if unit.combat_stats.is_hero:
		defeat_level()
		return

	# 检查是否所有敌人都死了
	var alive := 0
	for u in teams[2].units:
		if u.combat_stats.is_alive():
			alive += 1
	if alive == 0:
		complete_level()
		return

	if not _first_blood:
		_first_blood = true
		Notify.notify("首次击破！", Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS)


# ── HP 阈值 ──
func _on_any_unit_hp_changed(unit: Unit, old_hp: int, new_hp: int) -> void:
	if not unit.combat_stats.is_hero:
		return
	var half: int = unit.combat_stats.max_hp / 2
	if old_hp > half and new_hp <= half:
		Notify.notify("李春血量告急！", Notify.Position.TOP_RIGHT, Notify.Style.WARNING)


# ── 大回合 ──
func _on_round_started(round_num: int) -> void:
	if round_num == 3:
		await play_mid_cutscene(["res://assets/cutscenes/level1-1/mid_01.png"])
		spawn_unit(_ENEMY_DATA, Vector2i(5, 3), 2)
		Notify.notify("敌军援军抵达！", Notify.Position.TOP_RIGHT, Notify.Style.WARNING)

	if round_num == 5 and not _wedge_taught:
		_wedge_taught = true
		var hero: Unit = teams[0].units[0]
		grant_skill(hero, _SKILL_WEDGE)


# ── 技能授予提示 ──
func _on_unit_gained_skill(unit: Unit, skill: SkillData) -> void:
	Notify.notify(
		"%s 习得了【%s】！" % [unit.combat_stats.unit_name, skill.skill_name],
		Notify.Position.TOP_RIGHT,
		Notify.Style.SUCCESS,
		4.0,
	)


# ── 走到桥址触发对话 ──
func _on_tile_entered(cell: Vector2i, entity: Node2D) -> void:
	if not (entity is Unit and entity.combat_stats.is_hero):
		return
	if cell == Vector2i(3, 5) and not _bridge_visited:
		_bridge_visited = true
		await play_dialogue([
			DialogueLine.create("李春", "此处便是桥址。先勘地势。", _LICHUN_FACE, "left"),
		])
```

---

## 9.7 排错

### 信号没有触发

1. **检查 `connect` 是否在 `_on_level_ready()` 里**：必须在这里 connect，因为这是关卡加载完成的时机。
2. **加 `print` 验证**：
   ```gdscript
   func _on_level_ready() -> void:
	   print("[DEBUG] level ready")
	   unit_died.connect(_on_any_unit_died)


   func _on_any_unit_died(unit: Unit) -> void:
	   print("[DEBUG] unit_died emitted: ", unit.combat_stats.unit_name)
   ```
   运行时打开 Godot 编辑器底部的 **Output 面板**，看 print 是否出现。
3. **检查信号名拼写**：信号名严格区分大小写。例如 `unit_died` 不能写成 `unitDied`。

### `grant_skill` 没有触发 `unit_gained_skill` 信号

最常见原因：单位**已经拥有**这个技能。`grant_skill` 是幂等的，重复 grant 同一技能不会再次 emit 信号。

### `play_dialogue` 没有任何效果就消失了

忘记加 `await`。正确写法是：
```gdscript
await play_dialogue([...])
```

### `defeat_level` / `complete_level` 直接黑屏回主菜单

这是预期行为。目前关卡结算就是直接返回主菜单，未来可能会加结算页面。

### 找不到信号定义

所有信号定义在 `scenes/levels/base_level/base_level.gd` 文件开头（约 14-35 行）。在 VSCode 里可以用 `Ctrl+P` 打开这个文件然后搜 `signal `。

---

## 9.8 与其他文档的关系

- 想了解 Notify 的全部位置和样式 → [04 § 6.11](04-level-parameters.md#611-调用-notify-发送通知)
- 想了解 ElementColors 全局类（用元素颜色染富文本）→ [附录 B § B.13](appendix-creature-reference.md#b13-元素颜色全局类-elementcolors)
- 想了解 `is_hero` 字段是怎么设置的 → [03 § 4.4 单位 stats 配置](03-unit-placement.md)
- 想了解状态栏 UI 的渲染层级 → [07 § 7.3 渲染层级速查表](07-testing.md#73-渲染层级速查表)
- 想了解 `GameState.CUTSCENE_DATA` 的开场/结尾过场配置 → [08 关卡集成](08-integration.md)
