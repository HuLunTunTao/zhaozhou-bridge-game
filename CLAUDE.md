# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**安济桥成** — a 2D isometric turn-based tactics game (战棋) built in Godot 4.6. The player follows Li Chun (李春) building the Zhaozhou Bridge. This is NOT a tower defense game.

- Engine: Godot 4.6.1, Forward Plus renderer
- Language: GDScript
- Resolution: 960x540 viewport, 1920x1080 window, stretch mode viewport
- Texture filter: nearest (pixel art)
- Physics: Jolt (3D enabled despite 2D gameplay)
- Font: Unifont 15.1.04 (Chinese character support), Fusion Pixel (pixel UI font)

## Running the Project

```bash
# Run the project
godot --path /path/to/Godot-game

# Open in editor
godot --editor --path /path/to/Godot-game
```

The main scene is `scenes/menu/main_menu.tscn`.

## Architecture

### Autoloads (`project.godot`)

- `GameState` (`scripts/game_state.gd`) — level registry (`LEVEL_SCENES`), cutscene page table (`CUTSCENE_DATA`), and transient inter-scene state (`pending_cutscene_pages`, `pending_next_scene`)
- `Notify` (`scripts/notification_manager.gd`) — global notification manager for in-game toasts
- `TestBridge` — editor plugin bridge (`addons/godot_test_bridge/`)

### Scene Structure

- `scenes/menu/main_menu.tscn` — Main menu, entry point
- `scenes/levels/base_level/` — Base level class (all battle levels inherit from this)
  - `base_level.gd` — Turn system, team management, input state machine, combat feedback
  - `movement_manager.gd` — Tile type queries, movement cost, enter/exit hooks
  - `move_overlay.gd` — Movement range preview
- `scenes/levels/` — Campaign levels (level1-1 through level1-4, test)
- `scenes/unit/unit.tscn` — Unit scene (AnimatedSprite2D + HP bar)
- `scenes/ui/` — UI components (status_bar, dialogue_box, settings_panel, notification_popup)
- `scenes/cutscene/` — Cutscene system
- `scenes/test/` — Test scenes (dialogue, notification, phase notification)

### Level State Machine (`base_level.gd`)

Every level runs on **two orthogonal state axes**. Subclasses and gameplay code must go through this machine rather than adding ad-hoc bool flags.

**Axis A — `LevelPhase` (coarse lifecycle, unidirectional)**:
- `BRIEFING` — 进入关卡时的初始目标面板阶段。`_init_turn_system()` 未启动，AI 不跑，`_can_accept_command()` 返回 false。
- `PLAYING` — 正常战斗。
- `ENDED` — 胜负已判定（`complete_level` / `defeat_level` 首行置位）。AI 循环读到 `is_phase_ended()` 退出。

状态切换仅通过 `_set_phase(p)` 并 emit `phase_changed(p)`。订阅示例见 `level1-1.gd::_on_phase_changed_for_onboarding`（教程只在 PLAYING 启动，不与 BRIEFING 抢输入）。

**轴 B — `ActiveOverlay` (瞬态独占前景 UI，互斥)**:
`NONE` / `BRIEFING_OBJECTIVES` / `DIALOGUE` / `CUTSCENE` / `OBJECTIVES_REVIEW` / `SETTINGS` / `PROGRESS` / `TUTORIAL_PANEL` / `GROWTH_CHOICE` / `DEFEAT_PANEL`。

统一通过 `_open_overlay(kind, node, closed_signal=&"closed")` 打开、`_close_overlay(kind)` 关闭（通常由 panel 的 `closed` 信号 CONNECT_ONE_SHOT 触发）。互斥由 `_open_overlay` 自动守护——若已有 overlay，新请求返回 false。

**联合闸门**：`_can_accept_command()` 要求 `phase == PLAYING` **且** `overlay == NONE` **且** `tilemap != null` **且** `_waiting_for_player_input` **且** `_input_state != ANIMATING`。所有按钮/输入都走这条闸门。

**领域信号**（教程、任务系统、LLM 触发器可订阅）:
- `phase_changed(new_phase: int)` — BRIEFING → PLAYING → ENDED
- `overlay_opened(kind: int)` / `overlay_closed(kind: int)`
- `selection_changed(unit: Node2D)` — `selected_unit` 赋值/清空
- `unit_move_completed(unit: Unit)` — 玩家单位移动完成（AP 扣除后）
- 已有：`unit_died` / `unit_hp_changed` / `round_started` / `team_turn_started` / `skill_executed` / `unit_gained_skill` / `unit_lost_skill`

**写异步脚本（教程、开场剧情）的准则**：
- **NEVER** `await get_tree().process_frame` 来轮询状态——关卡节点被 queue_free 时 `get_tree()` 为 null 会崩。改为 `await self_signal`（如 `selection_changed` / `unit_move_completed` / `skill_executed` / `team_turn_started` / `play_dialogue`），节点销毁时协程静默死亡。
- 每个 await 点后加 `if is_phase_ended(): return`，防止胜负结算后继续推进。
- 长期协程订阅 `phase_changed`，在 `PLAYING` 才启动，不要在 `_on_level_ready` 里 fire-and-forget。
- 打开自定义模态 UI 必须走 `_open_overlay`，否则会逃过 `_can_accept_command()` 闸门。

### Combat System

- `scripts/combat/combat_resolver.gd` — Damage calculation, hit resolution
- `scripts/combat/skill_executor.gd` — Skill validation, target collection, effect application
- `scripts/combat/combat_stats.gd` — Unit runtime state (HP, AP, statuses, element)
- `scripts/combat/phase_table.gd` — Five-element phase (化势) lookup table
- `scripts/combat/element_system.gd` — Element attachment/collision/refresh
- `scripts/data/phase_data.gd` — PhaseData resource definition

### Data Resources

- `data/units/*.tres` — Unit data (UnitData resources)
- `data/skills/*.tres` — Skill data (SkillData resources)
- `data/phases/*.tres` — Phase data (PhaseData resources, 10 files for five-element interactions)

### Tile System

- Isometric tiles: 32x32 texture regions displayed as 32x16 in-game
- Terrain types: Earth, Grass, Stone Road, Water (light/dark), Water Stone — each with movement cost
- Tileset: `assets/battle_tile_set.tres` + inline tilesets in map scenes

### Assets

- `assets/thepixeltiles/isometric tileset/spritesheet.png` — main tileset
- `assets/thepixeltiles/critters/` — badger, boar, stag, wolf
  - Naming: `{creature}_{direction}_{action}_{frame}.png` (directions: NE/NW/SE/SW, some with center)
- `assets/character/` — character art; `assets/face/` — portraits (7:9, e.g. `li_chun.png`) shown in status bar and dialogue
- `assets/cutscenes/` — per-level cutscene pages (e.g. `level1-1/pre_01.png`)
- `assets/font/` — Unifont

### Level Design Documentation (`docs/level-design/`)

Comprehensive authoring guide for level designers working in the Godot editor. Start with `README.md`. Numbered chapters cover map creation, terrain painting, unit placement, level parameters, resource uniqueness, git workflow, testing, main-menu integration, and the event-response system. Appendices A/B are the terrain and unit/skill reference tables. **When adding features that affect level authoring, update these docs.**

### Design Documents

- `artbook/第一章：安济桥成.docx` — Chapter 1 story and level design
- `artbook/补充详细设定与剧情.docx` — Supplementary settings and plot details
- `docs/level-design/` — Level design guides for designers

## Export Build Pitfalls

These patterns cause "works in editor, fails in export" bugs. **Always avoid them:**

1. **NEVER use `DirAccess.open("res://...")` to scan directories at runtime.**
   Exported builds pack resources into `.pck` files where `DirAccess` cannot enumerate `res://` directories. Use explicit path lists + `load()` instead. See `scripts/combat/phase_table.gd` for the correct pattern.

2. **`@export var node: TileMapLayer` in inherited scenes may be null in exports.**
   This is a known Godot 4.x bug cluster. Always add a runtime fallback lookup in `_ready()`. See `base_level.gd::_find_obstacle_tilemap()`.

3. **CJK text wrapping: enable `Include Text Server Data` or use `AUTOWRAP_WORD_SMART`.**
   Exported builds do NOT include ICU break iterator data by default ([godotengine/godot#117102](https://github.com/godotengine/godot/issues/117102)). Without it, `AUTOWRAP_WORD` treats Chinese text as a single unbreakable word. Fix: go to `Project > Project Settings > General > Internationalization > Locale`, enable `Include Text Server Data` (~4 MB), then re-export. Alternatively, use `autowrap_mode = 3` (WORD_SMART) which falls back to per-character breaking.

4. **Prefer PackedScene `.instantiate()` over `.new()` for complex UI node trees.**
   Programmatically built Control trees (PanelContainer > HBoxContainer > RichTextLabel) may have minimum_size propagation timing issues in export. Use a `.tscn` template instead. See `scenes/ui/notification_popup.tscn`.

## MCP Integration

Godot MCP server is configured (`@coding-solo/godot-mcp`) for scene creation, node manipulation, and project inspection.
