# 安济桥成 -- 关卡设计文档

> 本文档面向关卡设计师（Level Designer），帮助你在 Godot 4.6 编辑器中创建、配置和测试战棋关卡。

---

## 如果你是第一次接触这个项目

按以下顺序阅读即可上手：

1. **[01-地图创建 § 2.0 Godot 编辑器入门](01-map-creation.md#20-godot-编辑器入门第一次使用请先读这一节)** — 打开项目、熟悉主界面面板
2. **[01-地图创建 § 2.1 起](01-map-creation.md#21-关卡场景结构总览)** — 新建继承场景
3. **[02-地形绘制](02-terrain-painting.md)** — 用 TileMap 面板画地形
4. **[03-单位配置](03-unit-placement.md)** — 放置单位、注意 Unit 原点约定
5. **[04-关卡参数 § 6.1](04-level-parameters.md#61-队伍配置get_teams_config)** — 编写最简关卡脚本
6. **[07-测试与调试 § 7.1](07-testing.md#71-运行关卡)** — 按 F6 测试你的关卡
7. **[09-事件-响应系统](09-event-response.md)** — 进阶：让关卡对死亡/回合/位置等事件做出反应（剧情/胜负判定）

最重要的两个按键：**`Ctrl+S` 保存**、**`F6` 运行当前场景**。

---

## 目录

| 编号 | 文档 | 内容概述 |
|------|------|----------|
| 01 | [地图创建](01-map-creation.md) | Godot 编辑器入门 · 新建关卡场景 · 场景树结构 · 继承 BaseLevel |
| 02 | [地形绘制](02-terrain-painting.md) | 使用 TileMapLayer 绘制等距地形、地形类型与移动消耗 |
| 03 | [单位配置](03-unit-placement.md) | 放置和配置单位（Unit）、Unit 原点约定、设置 UnitData、技能装配 |
| 04 | [关卡参数](04-level-parameters.md) | 队伍配置 · 胜负条件 · 对话系统 · Notify 通知 · 代码编辑器入门 |
| 05 | [资源唯一化](05-resource-uniqueness.md) | Make Unique 操作、避免意外修改共享资源 |
| 06 | [Git 工作流](06-git-workflow.md) | 版本控制、提交规范、分支策略、冲突处理 |
| 07 | [测试与调试](07-testing.md) | 运行关卡 · 渲染层级 · 化势反馈 · 常见问题排查 |
| 08 | [关卡集成](08-integration.md) | 将关卡接入主菜单和战役流程 |
| 09 | [事件-响应系统](09-event-response.md) | 用 GDScript 钩子让关卡对死亡/回合/位置/HP/技能等事件做出反应 |
| A | [地形参考表](appendix-tileset-reference.md) | 全部地形类型、移动消耗、Terrain 名称速查 |
| B | [单位与技能参考表](appendix-creature-reference.md) | 全部单位数据、技能数据、状态数据、ElementColors 用法 |

---

## 项目快速概览

- **游戏类型**: 2D 等距回合制战棋（非塔防）
- **引擎版本**: Godot 4.6.1
- **脚本语言**: GDScript
- **视口分辨率**: 960x540（窗口 1920x1080）
- **纹理过滤**: Nearest（像素风）
- **主字体**: Unifont（中文支持）
- **主入口场景**: `scenes/menu/main_menu.tscn`
- **关卡基类**: `scenes/levels/base_level/base_level.tscn`（class_name: BaseLevel）
- **单位场景**: `scenes/unit/unit.tscn`（class_name: Unit）
- **关卡目录**: `scenes/levels/`
- **数据目录**: `data/units/`、`data/skills/`、`data/statuses/`、`data/phases/`
- **头像资源**: `assets/face/`（如 `li_chun.png`，7:9 比例）
- **全局 Autoload**: `GameState`（关卡注册）、`Notify`（通知管理器）、`TestBridge`（测试桥接）

---

## 文档约定

- **文件路径**: 以 `res://` 开头的路径表示项目根目录下的相对路径（Godot 约定）
- **代码引用**: 用 `file_path:line_number` 格式（如 `scripts/notification_manager.gd:80`），可在 VSCode 中点击跳转
- **操作步骤**: 用数字编号的步骤是必须按顺序执行的；用要点符号的是可选或说明性内容
- **代码块**: 灰色背景的文字是需要在编辑器属性面板或脚本中输入的值
- **快捷键**: 格式为 `Ctrl+S`，macOS 用户请将 `Ctrl` 替换为 `Cmd`

> 提示: 标有此图标的段落提供有用但非必需的额外信息。

> 注意: 标有此图标的段落包含容易出错的操作要点。

> 常见错误: 标有此图标的段落描述了常见的错误操作及其解决方法。

---

## 更新日志

| 日期 | 版本 | 变更内容 |
|------|------|----------|
| 2026-04-08 | v1.0 | 初始版本，覆盖完整关卡设计工作流（01-04、README） |
| 2026-04-08 | v1.1 | 补全全部文档（05-08、附录A/B），更新04技能数据 |
| 2026-04-08 | v2.0 | 移除 Godot 基础入门和相机设置文档；新增资源唯一化（05）和 Git 工作流（06）；重新编号全部文档 |
| 2026-04-08 | v3.0 | 战斗系统实现（Phase 0~5 + UI反馈）；视口放大至 960x540；状态栏重构；新增战斗日志；字体更新 |
| 2026-04-09 | v4.0 | 补充对话系统文档；新增头像（portrait）字段说明；更新状态栏 UI 细节（头像、属性显示、技能槽位）；补充战斗日志使用说明；修正场景树描述与代码一致；新增敌方技能 dlp_drifting_timber_crash；新增 Autoload: Notify（通知管理器） |
| 2026-04-09 | v4.1 | 新增 Godot 编辑器首次使用入门（01 § 2.0）；新增代码编辑器与 GDScript 基础（04 § 6.0）；扩展 Unit 原点约定与脚下对齐示例（03 § 4.2）；新增化势反馈三层 UI 与渲染层级速查（07 § 7.3 / § 7.3b）；新增 Notify.notify 调用示例（04 § 6.11）；新增 ElementColors 全局颜色类使用指南（附录 B § B.13）；修正 HP 条 Y 偏移（-40）、TestBridge autoload |
| 2026-04-09 | v4.2 | 新增 09 事件-响应系统专题文档：6 个关卡事件信号（unit_died / unit_hp_changed / round_started / team_turn_started / unit_gained_skill / unit_lost_skill）+ 5 个新增响应方法（defeat_level / spawn_unit / play_dialogue / grant_skill / revoke_skill）；中场过场动画用法说明；常见模式速查；完整关卡示例 |
| 2026-04-10 | v4.3 | 附录 B 新增 B.11a「新增化势的完整流程」：创建 PhaseData .tres 文件 + 在 phase_table.gd 中注册路径的两步必做流程；说明 DirAccess 在导出版中无法扫描目录的技术背景；B.6 节头部新增注册提醒 |
