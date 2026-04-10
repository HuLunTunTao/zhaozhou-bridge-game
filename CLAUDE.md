# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**安济桥成** — a 2D isometric turn-based tactics game (战棋) built in Godot 4.6. The player follows Li Chun (李春) building the Zhaozhou Bridge. This is NOT a tower defense game.

- Engine: Godot 4.6.1, Forward Plus renderer
- Language: GDScript
- Resolution: 960x540 viewport, 1920x1080 window, stretch mode viewport
- Texture filter: nearest (pixel art)
- Physics: Jolt (3D enabled despite 2D gameplay)
- Font: Unifont (Chinese character support)

## Running the Project

```bash
# Run the project
godot --path /home/ffcrazy/proj/game

# Open in editor
godot --editor --path /home/ffcrazy/proj/game
```

The main entry scene is `scenes/menu/main_menu.tscn` (see `project.godot`). From there the player picks a level registered in `GameState.LEVEL_SCENES`.

## Architecture

### Autoloads (`project.godot`)

- `GameState` (`scripts/game_state.gd`) — level registry (`LEVEL_SCENES`), cutscene page table (`CUTSCENE_DATA`), and transient inter-scene state (`pending_cutscene_pages`, `pending_next_scene`)
- `Notify` (`scripts/notification_manager.gd`) — global notification manager for in-game toasts
- `TestBridge` — editor plugin bridge (`addons/godot_test_bridge/`)

### Scene Structure

- `scenes/menu/main_menu.tscn` — Entry scene; builds level buttons from `GameState.LEVEL_SCENES`
- `scenes/levels/` — All campaign levels. Every level inherits from `BaseLevel`:
  - `base_level/base_level.tscn` + `base_level.gd` (`class_name BaseLevel`) — shared root with `TileMaps`, `Entities/Units`, `SpecialTiles`, `MoveOverlay`, `MovementManager`, `Camera2D`, `GUI`, `StatusBarScene`
  - Level folders: `level1-1/`, `level1-2/`, `level1-3/`, `level1-3-2/`, `level1-4/`, `test/`
  - `maps/` — raw map layouts (`*v2.tscn`) used as starting points for level scenes
  - `base_level/tile_types/` — terrain tile-type resources; `movement_manager.gd` + `move_overlay.gd` handle pathfinding and range display
- `scenes/unit/unit.tscn` (`class_name Unit`) — shared unit scene; animations under `scenes/unit/anamation/`
- `scenes/ui/` — `action_panel`, `status_bar`, `dialogue_box`, `settings_panel`, `save_manager`, plus `combat/` (damage popups, HP bar, phase/element popups, phase notification)
- `scenes/cutscene/cutscene_player.tscn` — fullscreen cutscene page viewer used before/after levels and mid-level
- `scenes/highlight/` — tile selection highlight (`highlight_selecter.gd`, a Line2D diamond)
- `scenes/debug/`, `scenes/test/` — dev-only scenes

### Combat System (`scripts/combat/`)

Turn-based combat organized around the five elements (五行) and a "化势" (phase transform) mechanic:

- `combat_resolver.gd` — resolves skill hits, damage, and knock-on effects
- `combat_stats.gd` — per-unit stat math
- `element_system.gd` + `phase_table.gd` — 五行 relationships and phase transitions
- `skill_executor.gd` — drives skill animation/resolution pipeline
- `skill_targeting.gd` — range/target overlay selection
- `combat_log.gd` — structured log feeding the combat log UI

`BaseLevel` owns the input state machine (`IDLE` → `UNIT_SELECTED` → `TARGETING_MOVE`/`TARGETING_SKILL` → `ANIMATING`) and emits level-level signals: `unit_died`, `unit_hp_changed`, `round_started`, `team_turn_started`, `unit_gained_skill`, `unit_lost_skill`. Level scripts override `get_teams_config()` and connect to these signals to wire up win/lose conditions, dialogue, and scripted spawns.

### Data Resources (`data/`)

All tunable content lives as `.tres` resources driven by script classes under `scripts/data/`:

- `data/units/*.tres` — `UnitData` (`unit_data.gd`): `hero_li_chun`, `craftsman_guard`, `survey_worker`, `bank_mud_wraith`, `dark_current`, `drift_log_pack`, `whirl_pool`
- `data/skills/*.tres` — `SkillData` (`skill_data.gd`): Li Chun's `lc_*`, craftsman `cg_*`, survey worker `sw_*`, enemy skills (`bmw_*`, `dc_*`, `dlp_*`, `wp_*`)
- `data/phases/*.tres` — `PhaseData` (`phase_data.gd`): 五行相生相克关系（`wood_over_earth_pierce_bank`, `water_over_fire_quench_blaze`, …）
- `data/statuses/*.tres` — `StatusData` (`status_data.gd`): buffs / debuffs / DoT
- `scripts/data/enums.gd`, `element_colors.gd`, `offset_presets.gd` — shared constants

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

## MCP Integration

Godot MCP server is configured (`@coding-solo/godot-mcp`) for scene creation, node manipulation, and project inspection.
