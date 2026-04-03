# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**安济桥成** — a 2D isometric turn-based tactics game (战棋) built in Godot 4.6. The player follows Li Chun (李春) building the Zhaozhou Bridge. This is NOT a tower defense game.

- Engine: Godot 4.6.1, Forward Plus renderer
- Language: GDScript
- Resolution: 640x360 viewport, 1280x720 window, stretch mode viewport
- Texture filter: nearest (pixel art)
- Physics: Jolt (3D enabled despite 2D gameplay)
- Font: Unifont 15.1.04 (Chinese character support)

## Running the Project

```bash
# Run the project
godot --path /home/ffcrazy/proj/game

# Open in editor
godot --editor --path /home/ffcrazy/proj/game
```

The main scene is `scenes/battle/battle.tscn`.

## Architecture

### Scene Structure

- `scenes/battle/battle.tscn` — Main battle scene (Format 4), the game's entry point
- `scenes/levels/` — Campaign levels (Format 3), all share isometric tilemap structure:
  - Each level: Root Node2D → TileMapLayer + Camera2D + "DO NOT CHANGE THIS" Node2D
  - Levels: `initscence`, `base`, `test`, `level1-1` through `level1-4`, `level1-3-2`
- `scenes/highlight/` — Tile selection UI system
  - `highlight_selecter.gd` — The only custom script; a Line2D that draws a diamond-shaped highlight on tiles

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

### Web Demo

- `demo/index.html` — JavaScript-based prototype of the first level (separate from Godot project)

## MCP Integration

Godot MCP server is configured (`@coding-solo/godot-mcp`) for scene creation, node manipulation, and project inspection.
