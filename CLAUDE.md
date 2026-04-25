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

### LLM Agent System

LLM 驱动的对话由两部分组成：调度 + prompt 装配，外加每单位的 persona / 记忆。

**入口**：
- `scripts/llm/llm_client.gd` — HTTP 客户端（OpenAI 兼容协议）。`chat_completion(messages, opts)` 返回 `{ok, text, code, error}`。配置走 `scripts/llm/api_config.gd`（用户私有，gitignored）。
- `scripts/llm/chatter_scheduler.gd` — `base_level._ready()` 自动挂载。订阅 `skill_executed / team_turn_started / team_turn_ended / round_started / round_ended`，驱动主线关卡的闲聊（受击反应 / 邻接对话 / 主角观察 / boss 固定吐槽）。**自由移动关卡里这些信号都不会触发，scheduler 默默闲置。**
- `scripts/llm/chatter_prompts.gd` — 纯静态函数：`build_system_prompt(persona, trigger_kind, memory, context_json)` + `build_user_prompt(persona, trigger_kind, extra)`。新增 trigger_kind 在 `build_user_prompt` 的 match 块里加一条。
- `scripts/llm/npc_personas.gd` — `PERSONAS: Dictionary[unit_id]`，字段 `{name, persona, style, tags, fallback_topics?, qa_question?}`。新增 NPC 必须同时在这里 + `voice_mapping.gd` + `data/units/*.tres` 三处登记。

**Cancel / wait 纪律（绝不破坏）**：
ChatterScheduler 任何新一段 speak 之前必须满足两条之一——**先 cancel 旧的**或**先 await 旧的播完**。看 `_do_adjacent_chat` 是参考实现：玩家跳过 A 且有 B → `_voice.cancel()`；其它路径 → `await _wait_for_voice_end()`。`_busy` 锁覆盖整段会话以串行化所有 trigger。**新代码路径调用 `chatter_voice_adapter.speak()` 之前必须保持这个纪律**，否则会出现"上一段尾音串到下一段"的串台 bug（详见下方 TTS 章节的 race window 说明）。

**LLM 失败兜底**：
- chatter_scheduler 直接跳过本次（不用 fallback_lines；那是"老监工"口吻，套到别角色出戏）
- bridge_tour 用 persona 自带 `fallback_topics`，回答兜底标记 `{is_fallback: true, ...}`，上层据此**跳过 TTS**（避免 OS TTS 念出"沉吟不语"很出戏）

**dialogue 显示协同**：
- `play_chatter_lines(lines, dismiss_delay, voice_handle)` —— `voice_handle` 必须传 `chatter_voice_adapter` 实例，否则 dialogue_box 在 TTS 还在播时就关掉
- auto_dismiss 等三者最大值：文字打完 / voice + 0.5s / open + dismiss_delay
- 玩家手动跳过时 dialogue_box 立刻关，但语音不会自动断——caller 必须显式 `cancel()` 或 await 收尾

### TTS System (Volcengine 火山 + OS Fallback)

- `addons/godot_volcengine_tts/streaming_voice_player.gd` — 高层 SDK：`speak(text, voice, opts)` / `start_streaming + feed_text + finish_streaming` / `fetch_audio` / `stop()` / `cancel()`。内部三个 client（bidi WS / uni WS / HTTP）+ AudioStreamPlayer。
- `scripts/tts/chatter_voice_adapter.gd` — 游戏侧适配：`speak(unit, text, trigger_kind)` 按 `unit.unit_data.unit_id` 查 voice_mapping，按 trigger_kind 查 emotion/speech_rate。火山失败 → `_maybe_speak_via_system_tts(text)` 走 OS DisplayServer TTS（**听起来机械、不带情绪**——是火山失败的信号）。
- `scripts/tts/voice_mapping.gd` — NPC → 火山 voice ID 映射。**所有 voice ID 必须在 `docs/tts/火山语音合成大模型音色表.md` 里能 grep 到**，否则 SDK 直接报错 → 走 OS TTS。
  - 自检脚本：
    ```bash
    grep -E '"voice":' scripts/tts/voice_mapping.gd | awk -F'"' '{print $4}' | sort -u > /tmp/used.txt
    grep -oE 'zh_[a-z_]+_uranus_bigtts' docs/tts/*.md | sort -u > /tmp/legal.txt
    comm -23 /tmp/used.txt /tmp/legal.txt   # 应无输出
    ```

**关键陷阱**：
1. **voice ID 后缀**：豆包 2.0 系列必须是 `_uranus_bigtts`，易错写成 `_uranus_big`（无效）。改 voice_mapping 后跑一次自检脚本。
2. **Session race（已修，勿破坏）**：streaming_voice_player 在 `start_session` 成功后回填 `_active_bidi_session_id`；`stop()` 第一行清空它。三个 bidi 信号 handler（`_on_bidi_audio_chunk` / `_on_bidi_session_finished` / `_on_bidi_session_failed`）都按 sid 守卫，挡掉旧 session 的延迟事件。**修 SDK 时不要绕过这套守卫**。
3. **跳过即取消纪律**：`bridge_tour._play_npc_line` 在玩家跳过对话框且语音还在流时立刻 `_voice.cancel()`，避免尾音串到下一段。任何使用 chatter_voice_adapter 的关卡都得遵守。
4. **`use_system_tts_fallback` 默认 true**：火山失败时偷偷走 OS TTS。如果不希望出现"机械音"，可以在调用方关掉 `_voice.use_system_tts_fallback = false`，让失败就是失败（无声）。

**注意 voice_mapping 里的 `note` 字段不会传给火山**——只是给开发者看的注释。要让"性格描述"影响 TTS 效果，得拼到 LLM 的 prompt 里改文本风格，而不是改音色配置。

### Free-Roam Levels (额外关卡 / 验桥日)

不同于主线回合制，"无尽生存 / 验桥日"等额外关卡走自由移动 + 实时模式。基类提供单一 hook：

- `BaseLevel.is_free_roam_level() -> bool`（默认 false）。子类返回 true → `_init_turn_system()` 直接 return，回合系统跳过。
- 子类**必须手动**：`_waiting_for_player_input = true; current_team_index = 0` 让 `_can_accept_command()` / `confirm_cell()` 守卫通过；隐藏 `_turn_label / _round_label / _end_turn_button`；运行时 spawn 玩家单位并 `_select_hero_silently()`。
- 玩家点李春 → 走基类的 click-to-move（AP 由 `_on_unit_moved` 每次回满，等同无限移动）。

**验桥日（bridge_tour）特殊架构**：

`scenes/levels/bridge_tour/bridge_tour.gd` — 9 个 NPC × 3 种 role 分支：
- `persuade`（蓝 `?`）：玩家自由打字论点 → LLM 评 `stance_delta` → ≥70 视为说服
- `qa`（绿 `?`）：NPC 抛预设 `qa_question`（写在 npc_personas）→ 玩家答 → LLM 判 `is_correct`
- `mentor`（黄 `!`）：玩家从话题菜单选一项 → LLM 选一条 `BridgeKnowledge.TOPICS` 讲解 → `topic_key` 记入 `_player_learned_topics`，注入后续 persuade / qa 的 prompt context 让"用上知识的回答"得分更高

NPC 自定义状态用 `Unit.set_meta("npc_role" / "npc_stance" / "npc_qa_solved" / "npc_persuaded" / "npc_discussed_topics" / ...)`，**不污染 Unit 类**。

**头顶图标**：`Unit.set_overhead_status_label(text, color)` 借用 `UnitHpBar.ElemLabel` 显示像素字。验桥日用几何符号 `○ / ● / ★`（**不用 emoji**——Fusion Pixel 字体不支持彩色 emoji，会渲染成豆腐块或失败）。

**模态面板规范（重要）**：
`scenes/ui/{argument_input_panel,topic_menu_panel,thinking_overlay,knowledge_panel}.tscn` **全部静态布局** + `unique_name_in_owner`，配套 .gd 只负责 `@onready` 绑节点 + 信号连接 + 数据填充。需要变长列表的（如 topic_menu）用"隐藏 Button 模板 + `duplicate()` 复制"方式（看 `topic_menu_panel.tscn` 的 `TopicButtonTemplate` 节点）。

**新增模态面板必须按这个规范**——禁止在 .gd 里 `add_child` 拼 UI 树，设计师无法调。

**BRIEFING / `objectives_panel` 支持 BBCode**：`bbcode_enabled = true` 已在 panel tscn 设好。`get_objectives_text()` 返回的字符串可以用 `[color=#xxx]…[/color]` / `[b]…[/b]` 等。验桥日用此表达"头顶蓝/绿/黄符号"图例。

**对话期间锁世界输入**（必须配对调用）：
```gdscript
_set_world_input_locked(true)    # 关相机方向键 + 状态机进 ANIMATING 拦点击
await _open_topic_choice(npc)    # 整段对话流（输入框 + LLM 等待 + dialogue_box + 邻居插话）
_set_world_input_locked(false)   # 解锁
_input_state = InputState.IDLE   # 调回 IDLE，配合 _select_hero_silently()
```

**主菜单跳过技能装备页**：验桥日只有"交互"技能，prebattle_setup 无意义。`GameState.LEVELS_SKIP_PREBATTLE: Array[String]` 注册的关卡在主菜单选关后直接进战斗，不走 `prebattle_setup.tscn`。

**额外关卡入口**：`GameState.EXTRA_LEVEL_SCENES`（与 `LEVEL_SCENES` 并列，但不查 `Progress.is_level_unlocked`，也不参与主线解锁链）。

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
