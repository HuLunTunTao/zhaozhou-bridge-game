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
godot --path /Users/hltt/projects/wxy_game/Godot-game

# Open in editor
godot --editor --path /Users/hltt/projects/wxy_game/Godot-game
```

The main scene is `scenes/menu/main_menu.tscn`.

## Architecture

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
- Terrain types: Earth, Grass, Stone Road, Water (light/dark), Water Stone
- Tileset: `assets/battle_tile_set.tres` (battle) + inline tilesets in level scenes

### Assets

- Spritesheet: `assets/thepixeltiles/isometric tileset/spritesheet.png`
- Creatures in `assets/thepixeltiles/critters/`: badger, boar, stag, wolf
  - Naming convention: `{creature}_{direction}_{action}_{frame}.png`
  - Directions: NE, NW, SE, SW (some have center)
  - Actions vary per creature (idle, walk, run, attack variants)

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
