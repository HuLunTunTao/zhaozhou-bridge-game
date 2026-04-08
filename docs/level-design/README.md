# 安济桥成 -- 关卡设计文档

> 本文档面向关卡设计师（Level Designer），帮助你在 Godot 4.6 编辑器中创建、配置和测试战棋关卡。
> 即使你从未使用过 Godot，也可以按照文档一步步完成操作。

---

## 目录

| 编号 | 文档 | 内容概述 |
|------|------|----------|
| 01 | [Godot 基础入门](01-getting-started.md) | 编辑器界面介绍、核心概念（节点/场景/资源）、项目打开方式 |
| 02 | [地图创建](02-map-creation.md) | 如何新建关卡场景、场景树结构、继承 BaseLevel |
| 03 | [地形绘制](03-terrain-painting.md) | 使用 TileMapLayer 绘制等距地形、地形类型与移动消耗 |
| 04 | [单位配置](04-unit-placement.md) | 放置和配置单位（Unit）、设置 UnitData、技能装配 |
| 05 | [相机设置](05-camera-setup.md) | LevelCamera 参数调整、镜头范围与缩放 |
| 06 | [关卡参数](06-level-parameters.md) | 队伍配置、胜负条件、过场动画、特殊地块 |
| 07 | [测试与调试](07-testing.md) | 运行关卡、常见问题排查、调试工具 |
| 08 | [关卡集成](08-integration.md) | 将关卡接入主菜单和战役流程 |
| A | [地形参考表](appendix-tileset-reference.md) | 全部地形类型、移动消耗、Terrain 名称速查 |
| B | [单位与技能参考表](appendix-creature-reference.md) | 全部单位数据、技能数据、状态数据速查 |

---

## 项目快速概览

- **游戏类型**: 2D 等距回合制战棋（非塔防）
- **引擎版本**: Godot 4.6.1
- **脚本语言**: GDScript
- **视口分辨率**: 640x360（窗口 1280x720）
- **纹理过滤**: Nearest（像素风）
- **主入口场景**: `scenes/menu/main_menu.tscn`
- **关卡基类**: `scenes/levels/base_level/base_level.tscn`（class_name: BaseLevel）
- **关卡目录**: `scenes/levels/`
- **数据目录**: `data/units/`、`data/skills/`、`data/statuses/`、`data/phases/`

---

## 文档约定

- **文件路径**: 以 `res://` 开头的路径表示项目根目录下的相对路径（Godot 约定）
- **操作步骤**: 用数字编号的步骤是必须按顺序执行的；用要点符号的是可选或说明性内容
- **代码块**: 灰色背景的文字是需要在编辑器属性面板或脚本中输入的值
- **快捷键**: 格式为 `Ctrl+S`，macOS 用户请将 `Ctrl` 替换为 `Cmd`

> 💡 提示: 标有此图标的段落提供有用但非必需的额外信息。

> ⚠️ 注意: 标有此图标的段落包含容易出错的操作要点。

> ❌ 常见错误: 标有此图标的段落描述了常见的错误操作及其解决方法。

---

## 更新日志

| 日期 | 版本 | 变更内容 |
|------|------|----------|
| 2026-04-08 | v1.0 | 初始版本，覆盖完整关卡设计工作流 |
