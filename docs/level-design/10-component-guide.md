# 10 -- 组件使用指南

> 本章是**关卡组件**的使用手册：关卡脚本该写什么、不该写什么，以及三个核心声明式组件
> （`TutorialStep` / `TaskChain` / `InteractionTile`）的编写规范。
> 前置阅读：[04-关卡参数](04-level-parameters.md)（关卡脚本骨架）与 [09-事件-响应系统](09-event-response.md)（信号与钩子）。

---

## 10.1 这个指南解决什么问题

写一个关卡时，你会发现四件事在四关里长得几乎一样：**回合骨架、教程步进、任务推进、交互点判定**。

关卡组件化之后，这四件事不再是每个关卡复制粘贴的代码，而是：

| 你要做的事 | 用哪个组件 | 你只写什么 |
|---|---|---|
| 教程对话 + 等玩家做一步 | `TutorialStep` | 一步一张"声明表"（文案 / 提示 / 等待条件） |
| 线性任务推进 + 目标面板 | `TaskChain` | 任务条目 + 三个文案函数 |
| 地图交互点（勘测 / 取参 / 合龙…） | `InteractionTile` | 参数表（格子 / 技能 / 谁能交互 / 交互后做什么） |
| `_on_stage_*` 事件接线 | `StageHooks` | 一张 `{信号名: 处理器}` 字典 |
| 敌方波次刷怪 | `WaveSpawns` + `WaveEntry` | 一张 `.tres` 波次表 |
| 我方属性数值 | `UnitRoster` + `RosterEntry` | 一张 `.tres` 属性表 |

**核心原则：关卡脚本只写"这一关独有的机制"，通用骨架全部交给组件。**

> 注意: 组件不是"框架约束"，只是把复制粘贴换成调用。组件里没有的东西（比如 1-3 的双券值、
> 1-4 的桥体稳定值）仍然写在关卡脚本里——那是真正的关卡特色，不要为了"用上组件"而硬抽。

---

## 10.2 组件清单与所在位置

### 战棋栈（Tactics Stack）——`scenes/levels/base_level/`

主线四关、测试关、无尽生存都用这一套。

| 组件 | class_name | 职责 |
|---|---|---|
| `turn_system.gd` | `TurnSystem` | 回合流转、结束回合双击、回合成长问询 |
| `ai_turn_runner.gd` | `AITurnRunner` | 敌方 AI 行动决策与执行 |
| `input_controller.gd` | `InputController` | 选中 / 移动 / 技能瞄准的输入状态机 |
| `skill_cast_controller.gd` | `SkillCastController` | 技能施放、目标收集、伤害反馈 |
| `unit_factory.gd` | `UnitFactory` | 单位生成 / 技能授予 / 战斗数值覆写 / 队伍编成 |
| `scene_bootstrap.gd` | `SceneBootstrap` | walkable / obstacle TileMapLayer 查找、地图边界 |
| `level_query_api.gd` | `LevelQueryAPI` | 占位 / 单位查询 |
| `level_flow.gd` | `LevelFlow` | 胜负判定后的过场 / 结算成长 / 回主菜单 |
| `level_ui_bridge.gd` | `LevelUIBridge` | HUD 按钮、难度联动、状态栏 |
| `objectives_tracker.gd` | `ObjectivesTracker` | 目标面板 |
| `tutorial_runner.gd` | `TutorialRunner` | 教程重玩问询 + **TutorialStep 步进引擎** |
| `llm_chatter_bridge.gd` | `LLMChatterBridge` | LLM 闲聊（debug 开关） |

### 共享内核（Shared Kernel）——`scenes/levels/shared/`

两个栈都用。

| 组件 | class_name | 职责 |
|---|---|---|
| `level_state_machine.gd` | `LevelStateMachine` | 阶段 / overlay / 输入闸门 / 输入锁 |
| `dialogue_bridge.gd` | `DialogueBridge` | `play_dialogue` / 李春单行 / chatter 台词 |
| `status_bar_bridge.gd` | `StatusBarBridge` | 状态栏联动 |
| `special_tile_registry.gd` | `SpecialTileRegistry` | 特殊地块登记与派发 |
| `cell_math.gd` | `CellMath` | 网格静态工具（`nearest_walkable` / `zone2x2_*` …） |
| `level_hud_factory.gd` | `LevelHudFactory` | 运行时造 HUD 标签 / 面板 |

### 声明式与数据组件——`scenes/levels/base_level/` + `scripts/data/`

| 组件 | class_name | 职责 | 详见 |
|---|---|---|---|
| `tutorial_step.gd` | `TutorialStep` | 教程原子步声明（Resource） | [§ 10.4](#104-tutorialstep-编写规范) |
| `task_chain.gd` | `TaskChain` | 线性任务链 | [§ 10.5](#105-taskchain-编写规范) |
| `interaction_tile.gd` | `InteractionTile` | 参数化交互地块 | [§ 10.6](#106-interactiontile-编写规范) |
| `stage_hooks.gd` | `StageHooks` | `_on_stage_*` 声明式接线 | [§ 10.7](#107-其它声明式组件) |
| `boss_dr_policy.gd` | `BossDRPolicy` | Boss 减伤策略 | [§ 10.7](#107-其它声明式组件) |
| `transient_tile.gd` | `TransientTile` | 限时地块基类（淤泥 / 急流沿） | [§ 10.7](#107-其它声明式组件) |
| `scripts/data/wave_spawns.gd` | `WaveSpawns` | 波次刷怪表 | [§ 10.7](#107-其它声明式组件) |
| `scripts/data/unit_roster.gd` | `UnitRoster` | 我方属性表 | [§ 10.7](#107-其它声明式组件) |

---

## 10.3 关卡脚本的最小骨架

一个只做"摆单位 + 走任务链"的关卡，脚本长这样：

```gdscript
extends BaseLevel

var _task_chain: TaskChain = TaskChain.new()
var _interactions: Array[InteractionTile] = []
var _stage_hooks: StageHooks = StageHooks.new()

func get_teams_config() -> Array:
	# 见 04-关卡参数 § 6.1
	return [...]

func get_objectives_text() -> Dictionary:
	return {"victory": _task_chain.get_objective_lines(), "defeat": [...]}

func _on_level_ready() -> void:
	_task_chain.setup(self)
	_task_chain.configure(_build_task_chain_tasks())

	_stage_hooks.setup(self)
	_stage_hooks.connect_all({
		"unit_died": _on_stage_unit_died,
		"team_turn_started": _on_stage_team_turn_started,
	})

	_setup_interactions()          # InteractionTile 登记
	phase_changed.connect(_on_phase_changed_for_onboarding)   # 教程等 PLAYING 再跑
```

**这段骨架里没有任何回合 / 输入 / 战斗逻辑**——那部分在 BaseLevel 与组件里。
你的关卡脚本只填四样：队伍、任务、交互点、阶段处理器。

> 注意: 教程 / 任务提示**不要**在 `_on_level_ready` 里直接 fire-and-forget。
> 那时还处于 `BRIEFING` 阶段，会与初始目标面板抢输入。
> 统一订阅 `phase_changed`，等 `PLAYING` 再启动（见 [§ 10.4.5](#1045-时序与异步纪律必读)）。

---

## 10.4 TutorialStep 编写规范

### 10.4.1 它是什么

`TutorialStep`（`scenes/levels/base_level/tutorial_step.gd`）是**一步教程的声明表**：
播哪几句 → 弹什么提示 → 等玩家做什么。

步进引擎在 `TutorialRunner.run_steps(steps)`，它负责按序播放、等待、以及关卡结束时中止。
**你不需要自己写 `await` 循环。**

### 10.4.2 字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `step_id` | `String` | 调试 / 日志用，如 `"cast_skill"` |
| `dialogue` | `Array[Dictionary]` | 对话行：`{"speaker": String, "text": String, "can_skip": bool}`。`speaker` 缺省 / 空 / `"李春"` → 走预生成 TTS |
| `hint` | `String` | 对话放完后的 `Notify.hint` 文案；空串 = 不弹 |
| `hint_duration` | `float` | 提示停留秒数 |
| `wait_mode` | `WaitMode` | `DIALOGUE_DONE` / `SIGNAL` / `PREDICATE` |
| `wait_signal` | `StringName` | 等待的关卡信号名（`SIGNAL` / `PREDICATE` 时必填） |
| `wait_predicate` | `Callable` | **只能在代码里装配**（Callable 不能导出到 `.tres`） |

### 10.4.3 三种等待方式

| `wait_mode` | 等价写法 | 什么时候用 |
|---|---|---|
| `DIALOGUE_DONE` | 不等 | 纯讲解步 |
| `SIGNAL` | `await <wait_signal>` | 等玩家做**一次**动作（选中、走一步、放一次技能） |
| `PREDICATE` | `while not cond: await <wait_signal>` | 等到**某个条件**成立（"回到我方回合"、"选中了李春"） |

`PREDICATE` 的谓词签名是 `func(args: Array) -> bool`：
`args` 是 `wait_signal` 的实参列表（入口预检时为空 `[]`）。

### 10.4.4 标准写法（摘自 `scenes/levels/level1-1/level1-1.gd`）

```gdscript
func _build_onboarding_steps() -> Array[TutorialStep]:
	var steps: Array[TutorialStep] = []

	# 等一次动作：SIGNAL
	steps.append(TutorialStep.create("move_unit", [
		{"text": "地图上高亮的格子，就是这回合能走到的范围。左键点其中一格试试。"},
	], "左键点击一个高亮格让单位走过去。", 8.0,
		TutorialStep.WaitMode.SIGNAL, &"unit_move_completed"))

	# 等到条件成立：PREDICATE
	steps.append(TutorialStep.create("select_hero", [
		{"text": "左键点一下我，就能选中我——左键用来确认，右键或 Esc 用来取消。"},
	], "左键点击李春（或任意己方单位）。", 8.0,
		TutorialStep.WaitMode.PREDICATE, &"selection_changed",
		func(_args: Array) -> bool: return selected_unit != null))

	# 等回我方回合：PREDICATE（读信号实参）
	steps.append(TutorialStep.create("end_turn", [
		{"text": "等全队都动完了，点右下角的「结束回合」。"},
	], "按右下角「结束回合」结束本回合。", 12.0,
		TutorialStep.WaitMode.PREDICATE, &"team_turn_started",
		func(args: Array) -> bool: return not args.is_empty() and args[0] == 0))

	# 纯讲解：不等待
	steps.append(TutorialStep.create("difficulty_hint", [
		{"text": "屏幕右上角的 ⚙ 是设置，里面可以随时调『难度』。"},
	]))
	return steps
```

启动与收尾：

```gdscript
func _run_onboarding() -> void:
	set_tutorial_onboarding_active(true)      # 暂停战场闲聊触发
	await _get_tutorial_runner().run_steps(_build_onboarding_steps())
	if not is_phase_ended():
		Progress.mark_tutorial_seen(TUTORIAL_ID)
	_finish_onboarding()
```

### 10.4.5 时序与异步纪律（必读）

1. **只在 `phase_changed(PLAYING)` 之后启动教程**。`BRIEFING` 阶段启动会与初始目标面板抢输入。
   ```gdscript
   func _on_phase_changed_for_onboarding(p: int) -> void:
       if p != LevelPhase.PLAYING:
           return
       if Progress.has_seen_tutorial(TUTORIAL_ID):
           ...
       _run_onboarding()
   ```
2. **NEVER 用 `await get_tree().process_frame` 轮询状态**。关卡节点被 `queue_free` 时
   `get_tree()` 为 null 会崩。要等状态就用 `wait_mode = PREDICATE` 等**关卡自己的信号**，
   节点销毁时协程静默死亡。
3. `run_steps` 内部每个 `await` 后都检查 `is_phase_ended()`，你不用重复写；
   但**自己额外写的 `await`** 之后要补 `if is_phase_ended(): return`。
4. 打开自定义模态 UI 必须走 `_open_overlay`，否则会逃过 `_can_accept_command()` 闸门。
5. 教程文案改动后若要重新配音，走 `tools/dump_tutorial_tts_manifest.py` 重生成 TTS 清单
   （见 `CLAUDE.md` 的 Tutorial TTS Workflow）；**只改提示文案不用重生成**。

> 常见错误: 在 `_on_level_ready` 里 `run_steps(...)` 不 await，结果目标面板和教程对话同时弹。
> 正确做法是订阅 `phase_changed`，见上文第 1 条。

---

## 10.5 TaskChain 编写规范

### 10.5.1 它是什么

`TaskChain`（`scenes/levels/base_level/task_chain.gd`）把关卡的**线性任务列表**（旧的
`TaskState` 枚举 + `_current_task` + `_advance_to_taskN()`）收成一张声明表，
并统一产出目标面板需要的三种展示形态。

### 10.5.2 任务条目 schema

用 `TaskChain.task(...)` 造：

```gdscript
static func task(id: StringName, objective_text: Variant, hint_text: Variant,
		on_enter: Callable = Callable(), marker_cell: Vector2i = Vector2i.ZERO) -> Dictionary
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `StringName` | 任务标识。`is_at_id(&"survey")` 判定"当前是不是这一步" |
| `objective_text` | `String` \| `Callable(mode: int) -> String` | 目标行文案。Callable 时按 `DisplayMode` 返回三种形态 |
| `hint_text` | `String` \| `Callable() -> String` | 顶部提示条文案（可带进度插值的动态文案） |
| `on_enter` | `Callable` | 进入该任务时的进场副作用（镜头、通知、召唤…） |
| `marker_cell` | `Vector2i` | 任务指引标记所在格（多点任务取代表格） |

`DisplayMode` 三种形态：

| 值 | 含义 | 典型文案 |
|---|---|---|
| `TaskChain.DisplayMode.PENDING` | 还没轮到这一步 | `"- 完成 3 个勘测点"` |
| `TaskChain.DisplayMode.ACTIVE` | 当前任务 | `"- 完成 3 个勘测点 (1/3)"` |
| `TaskChain.DisplayMode.DONE` | 已完成 | `"- 完成 3 个勘测点 (3/3)"` |

### 10.5.3 标准写法（摘自 `scenes/levels/level1-1/level1-1.gd`）

```gdscript
func _build_task_chain_tasks() -> Array[Dictionary]:
	return [
		TaskChain.task(&"survey", _obj_survey, _hint_survey, Callable(), SURVEY_CELLS[0]),
		TaskChain.task(&"bridge", _obj_bridge, _hint_bridge, _on_enter_bridge, BRIDGE_CELL),
		TaskChain.task(&"evac", _obj_evac, _hint_evac, _on_enter_evac, EVAC_CENTER_CELL),
	]

# objective_text 用 Callable：三种展示形态各给一条文案
func _obj_survey(mode: int) -> String:
	match mode:
		TaskChain.DisplayMode.DONE:
			return "- 完成 3 个勘测点 (3/3)"
		TaskChain.DisplayMode.ACTIVE:
			var status := " (%d/%d)" % [_survey_completed_count, SURVEY_CELLS.size()]
			return "- 完成 3 个勘测点%s" % status
		_:
			return "- 完成 3 个勘测点"

# hint_text 用 Callable：带进度插值
func _hint_survey() -> String:
	return "任务目标一，完成3个勘测点【%d/%d】" % [_survey_completed_count, SURVEY_CELLS.size()]
```

装配与推进：

```gdscript
_task_chain.setup(self)
_task_chain.configure(_build_task_chain_tasks())
# ...
_task_chain.advance_next()          # 前进一格（末任务时不动）
# 或 _task_chain.advance_to(2)     # 跳到指定任务
```

### 10.5.4 常用查询

| 方法 | 用途 |
|---|---|
| `is_at_id(&"survey")` | 交互闸门里判"当前任务是不是这一步" |
| `current_id()` / `is_at(index)` | 当前任务标识 / 索引判定 |
| `get_current_objective()` | 目标面板的当前行 |
| `get_objective_lines()` | **全链**目标行（`get_objectives_text()` 直接用它） |
| `get_current_hint()` | 顶部提示条 |
| `get_current_marker_cell()` | 任务指引标记格 |

接入目标面板：

```gdscript
func get_objectives_text() -> Dictionary:
	return {"victory": _task_chain.get_objective_lines(), "defeat": ["- 玩家队全灭"]}
```

### 10.5.5 注意点

- `configure()` **不触发** `on_enter`（开局任务的进场动作由关卡自行安排）；
  `advance_to()` / `advance_next()` 会触发。
- `on_enter` 是**裸调**（不 await），语义等价旧 `_advance_to_taskN()`；
  里面有 `await` 的协程靠它自己 await 的信号 / 计时器续命。
- 文案函数要**幂等**：目标面板每次刷新都会重新调用，别在里面改状态。

---

## 10.6 InteractionTile 编写规范

### 10.6.1 它是什么

`InteractionTile`（`scenes/levels/base_level/interaction_tile.gd`）把关卡"交互点"的判定骨架
收成一张参数表，吸收了旧 `_on_skill_executed` 里的手写交互分支。

四关的用例：1-1 勘测点、1-2 参数点、1-3 石料场 / 券台、1-4 小拱。

### 10.6.2 参数表

| 参数 | 类型 | 说明 |
|---|---|---|
| `cells` | `Array[Vector2i]` | 本交互点覆盖格（单格点一格；2×2 区传整区 4 格） |
| `allowed_skill_id` | `StringName` | 触发技能标识，与 `SkillData.skill_id` **或** `extra_effect_id` 任一相等即命中；**空 = 只响应落格触发** |
| `unit_filter` | `(caster: Unit) -> bool` | "谁此刻能交互"谓词。**拒绝提示由谓词自己发**（保留旧文案），返回 `false` 即拒绝 |
| `on_complete` | `(tile, caster, target_cell) -> void` | 放行后的效果实现（本关专属的后续闸门 / 计数 / 文案） |
| `completable_once` | `bool` | `true` = 一次性点；`false` = 可重复交互（1-2 取参 / 1-4 小拱），计数闸门写在 `on_complete` 里 |
| `on_cell_miss` | `() -> void` | 技能认领后未落在 `cells` 内的提示（旧"此处不是…"分支） |
| `on_already` | `() -> void` | 一次性点重复交互的提示（旧"已经完成过了"分支） |

### 10.6.3 标准写法（摘自 `scenes/levels/level1-1/level1-1.gd`）

```gdscript
func _setup_survey_points() -> void:
	for i in SURVEY_CELLS.size():
		var cell := SURVEY_CELLS[i]
		var tile := InteractionTile.create(
			[cell], &"complete_survey", _survey_unit_filter, _on_survey_completed_effect)
		tile.name = "SurveyPoint_%d_%d" % [cell.x, cell.y]
		tile.tile_color = COLOR_SURVEY_INCOMPLETE
		tile.on_cell_miss = _survey_cell_miss
		tile.on_already = _survey_already_done
		_special_tile_registry.register(tile, cell)   # 登记到特殊地块系统
		_interactions.append(tile)                    # 加入派发列表

# 闸门：拒绝提示自己发，返回 false 即拒绝
func _survey_unit_filter(caster: Unit) -> bool:
	if not _task_chain.is_at_id(&"survey"):
		return false
	if caster.combat_stats.unit_name != "测量工":
		Notify.notify("只有测量工可以完成勘测点。",
			Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
		return false
	return true

# 放行后的效果
func _on_survey_completed_effect(tile: InteractionTile, caster: Unit, _cell: Vector2i) -> void:
	_survey_completed_count += 1
	# ...计数、通知、推进任务链
```

### 10.6.4 两个触发入口

| 入口 | 触发时机 | 谁用 |
|---|---|---|
| `InteractionTile.dispatch_skill(_interactions, caster, skill, cast_cell)` | 技能施放 | 1-1 / 1-2 / 1-4 |
| `InteractionTile.dispatch_touch(_interactions, caster, target_cell)` | 单位落格 | 1-3 取石 / 交石 |

接线位置：

```gdscript
func _on_skill_executed(caster: Unit, skill: SkillData, cast_cell: Vector2i, _r) -> void:
	if InteractionTile.dispatch_skill(_interactions, caster, skill, cast_cell):
		return          # 已被某个交互点认领（含被拒绝 / 落错格）
	# ...本关自己的技能分支
```

两个入口都返回 `bool`：`true` = 本次已被某个交互点认领，调用方**不要再走自己的技能分支**。

### 10.6.5 派发顺序（不要改）

派发保持旧手写分支的判定顺序：**先"人 / 状态"闸门 → 后"落在哪一格" → 再一次性闸门 → `on_complete`**。

因此失败提示的先后与旧版逐字一致：先说"只有测量工可以"，再说"此处不是勘测点"。

> 注意: 同一 `allowed_skill_id` 的多个点（如 3 个勘测点）**共享**
> `unit_filter` / `on_cell_miss` / `on_already`——派发只在第一个匹配点上取谓词与文案。
> 所以这三个回调里不要写"这一个点专属"的判断。

> 注意: `unit_filter` 返回 `false` 时派发**立即结束**（`return true`），后面的点不会再被尝试。
> 这是刻意的：旧版就是"先人后格"，人不过闸就不该继续找格。

### 10.6.6 与 SpecialTile 的关系

`InteractionTile` 继承自 `SpecialTile`，所以它**同时是**一个特殊地块：
可以设 `tile_color`、挂 `Visual` 子节点、被 `SpecialTileRegistry` 管理进出场景。

`SpecialTile` 的子类标杆：`SiltTile`（淤泥）、`RapidEdgeTile`（急流沿）、`SmallArchTile`（小拱视觉）。
需要"随回合过期"的地块继承 `TransientTile`（`configure(round)` / `is_expired(round)`）。

---

## 10.7 其它声明式组件

### StageHooks —— 事件接线声明化

把 `_on_level_ready` 里的手写 `connect` 块收成一张字典：

```gdscript
_stage_hooks.setup(self)
_stage_hooks.connect_all({
	"unit_died": _on_stage_unit_died,
	"unit_hp_changed": _on_stage_hp_changed,
	"team_turn_started": _on_stage_team_turn_started,
	"unit_move_completed": _on_stage_unit_move_completed,
})
```

键是 BaseLevel 领域名信号（`StringName`），值是处理器 `Callable`。
无对应信号 / 无效 Callable 的条目**跳过并告警**，不阻断其余接线。
`disconnect_all()` 一键断开本对象接过的全部信号（幂等）。

**处理器本体留在关卡脚本**（各关机制不同），接线本身声明化。

### WaveSpawns + WaveEntry —— 波次刷怪表

把关卡的内联波次 dict 外置成 `.tres`（`data/stages/chapter1_stage*/wave_spawns.tres`）：

```
[sub_resource type="Resource" id="W_R1a"]
script = ExtResource("2")
round_number = 1
unit_kind = "dark_current"
cell = Vector2i(13, -24)
```

`unit_kind` 是关键字，由关卡的 `_resolve_wave_unit` 解析成具体 `UnitData` / 技能 / 视觉；
`cell_hint` 用于动态锚点刷点（1-3 / 1-4），`cell` 用于静态刷点（1-1）。
关卡按 `round_number` 聚合后喂给 BaseLevel 的 wave 系统。

> 提示: 无尽生存的刷点不用 `.tres`，而是**地图锚点节点**（`survival.tscn` 的
> `WaveSpawnAnchors/North|South/*`）——锚点所在格即刷点，设计师在编辑器里拖锚点即可改刷点；
> 节奏公式与 buff 池在 `data/stages/survival/wave_config.tres`。

### UnitRoster + RosterEntry —— 我方属性表

一关一张 `data/units/roster_*.tres`，李春 / 测量工 / 工匠 / 运石工 的
`max_hp / base_atk / ap_max / move_cost` 只在 `.tres` 一处维护：

```gdscript
_get_unit_factory().setup_unit_stats_from_roster(_li_chun, _roster.find("李春"),
	Enums.Element.NONE, 0, true)
```

数值不再写进关卡脚本，配平只改 `.tres`。

### BossDRPolicy —— Boss 减伤策略

统一 1-3 `_finalize_skill_hit_damage` 与 1-4 `_compute_boss_dr` 两种减伤机制，
挂 `combat_stats.incoming_damage_factor`。

### TransientTile —— 限时地块基类

`configure(round)` / `is_expired(round)` 两个 hook；`silt_tile` / `rapid_edge_tile` 是通用子类标杆。

---

## 10.8 新增组件的自查清单

写一个新组件 / 新交互点之前先问：

1. **是关卡特色还是四关共有？** 只有四关共有的才值得抽成组件。
2. **能参数化吗？** 能就写成 `Resource`（`@export` 字段）或参数表，把文案 / 数值挪进 `.tres`。
3. **异步了吗？** 只 `await` 关卡自己的信号，**绝不** `await get_tree().process_frame` 轮询。
4. **打开模态 UI 了吗？** 走 `_open_overlay`，不要直接 `add_child` 一个面板。
5. **导出构建会崩吗？** 不要用 `DirAccess.open("res://...")` 扫目录；
   `@export TileMapLayer` 一律配 `_find_*_tilemap` 运行时回退（见 `CLAUDE.md` Export Build Pitfalls）。
6. **行为变了吗？** 提示文案、Notify 样式、判定顺序都要与旧版逐字一致，除非这次就是要改文案。

---

## 10.9 相关文档

- [04-关卡参数](04-level-parameters.md) — 关卡脚本骨架、`get_teams_config`、胜负条件
- [09-事件-响应系统](09-event-response.md) — 可接的领域信号与响应方法清单
- [07-测试与调试](07-testing.md) — F6 跑关卡、常见问题排查
- `CLAUDE.md` — 给 AI 助手的架构说明与硬性约束（异步纪律、导出陷阱、TTS 流程）
