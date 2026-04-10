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

3. **Prefer `autowrap_mode = 3` (WORD_SMART) over `2` (WORD) for Chinese text.**
   `AUTOWRAP_WORD` has inconsistent CJK line-breaking behavior between editor and export.

4. **Prefer PackedScene `.instantiate()` over `.new()` for complex UI node trees.**
   Programmatically built Control trees (PanelContainer > HBoxContainer > RichTextLabel) may have minimum_size propagation timing issues in export. Use a `.tscn` template instead. See `scenes/ui/notification_popup.tscn`.

## MCP Integration

Godot MCP server is configured (`@coding-solo/godot-mcp`) for scene creation, node manipulation, and project inspection.
