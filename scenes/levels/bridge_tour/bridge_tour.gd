class_name BridgeTourLevel
extends FreeRoamSocialLevel
## 验桥日 · LLM Agent 关卡（编排层）。
##
## 9 个 NPC 三种 role：persuade（蓝？）自由打字说服 / qa（绿？）答题解惑 / mentor（黄！）选题求教。
## 已学知识注入 persuade / qa 的 prompt context，让 LLM 倾向给"用上知识的回答"更高分。
## 胜利条件：说服 3/3 + 解答 4/4 全完成（SocialLevelEndFlow 目标计数驱动）。
## 领域逻辑在 PersuadeFlow / QaFlow / MentorFlow 与各组件，这里只做装配、交互派发与覆写。

# ── 资源 ──
const _UD_LI_CHUN := preload("res://data/units/hero_li_chun.tres")
const _UD_NPC_TEMPLATE := preload("res://data/units/craftsman_guard.tres")
const _VISUAL_LI_CHUN := preload("res://scenes/unit/visual/human/li_chun/li_chun_visual.tscn")
const _NpcSpecLibraryScript := preload("res://scenes/levels/bridge_tour/npc_spec_library.gd")
const _LLMClientScript := preload("res://scripts/llm/llm_client.gd")
const _ChatterVoiceScript := preload("res://scripts/tts/chatter_voice_adapter.gd")
const _MissionHudScene := preload("res://scenes/levels/bridge_tour/mission_hud.tscn")
const _ObjectivesPanelScene := preload("res://scenes/ui/objectives_panel.tscn")
const _SettingsPanelScene := preload("res://scenes/ui/settings_panel.tscn")
const _ProgressPanelScene := preload("res://scenes/ui/progress_panel.tscn")
const _TutorialPanelScene := preload("res://scenes/ui/tutorial_panel.tscn")

# ── 数值常量 ──
const _HERO_COLOR := Color(1, 0.85, 0, 1)
const STANCE_PERSUADED := 70
const PERSUADE_ACCUM_SCORE_MIN := 6
const PERSUADE_ACCUM_SCORE_MAX := 15
const PERSUADE_ROUND_SCORE_MIN := -10
const PERSUADE_ROUND_SCORE_MAX := 15
const PERSUADE_TARGET := NpcSpecLibrary.PERSUADE_TARGET
const QA_TARGET := NpcSpecLibrary.QA_TARGET
const HERO_INFINITE_AP := 99999
const HERO_MOVE_PREVIEW_AP_BUDGET := 120 # 验桥日移动范围预览上限，避免无限 AP 把整张图 overlay 算出来

# ── 状态 ──
var _npcs: Array[Unit] = []
var _spawner: NpcSpawner = null
var _interaction_target: Unit = null
var _mission_hud: Node = null
var _llm: Node = null
var _voice: Node = null
var _llm_runner: LLMInteractionRunner = null
var _llm_context_builder: LLMContextBuilder = null
var _key_point_matcher: KeyPointMatcher = null
var _cheat_gate: CheatKeywordGate = null
var _neighbor_interjecter: NeighborInterjecter = null
var _learned_view: LearnedKnowledgeView = null
var _persuade_flow: PersuadeFlow = null
var _qa_flow: QaFlow = null
var _mentor_flow: MentorFlow = null
## 玩家学过 / 用过的知识 key。状态在 LearnedKnowledgeView，此处属性转发。
var _player_learned_topics: Array[String]:
	get: return _learned_view.learned_topics
var _player_used_topics: Array[String]:
	get: return _learned_view.used_topics


func _get_llm() -> Node: return _llm
func _get_voice() -> Node: return _voice
func _get_llm_runner() -> LLMInteractionRunner: return _llm_runner
func _get_llm_context_builder() -> LLMContextBuilder: return _llm_context_builder
func _get_key_point_matcher() -> KeyPointMatcher: return _key_point_matcher
func _get_cheat_gate() -> CheatKeywordGate: return _cheat_gate
func _get_neighbor_interjecter() -> NeighborInterjecter: return _neighbor_interjecter
func _get_learned_view() -> LearnedKnowledgeView: return _learned_view


func _setup_ref(c):
	c.setup(self)
	return c


func _init_components() -> void:
	_llm = _LLMClientScript.new()
	add_child(_llm)
	_voice = _ChatterVoiceScript.new()
	add_child(_voice)
	_llm_runner = _setup_ref(LLMInteractionRunner.new())
	_llm_context_builder = _setup_ref(LLMContextBuilder.new())
	_key_point_matcher = _setup_ref(KeyPointMatcher.new())
	_cheat_gate = _setup_ref(CheatKeywordGate.new())
	_neighbor_interjecter = _setup_ref(NeighborInterjecter.new())
	_learned_view = _setup_ref(LearnedKnowledgeView.new())
	_persuade_flow = _setup_ref(PersuadeFlow.new())
	_qa_flow = _setup_ref(QaFlow.new())
	_mentor_flow = _setup_ref(MentorFlow.new())


# ── 关卡虚方法 ──


func get_objectives_text() -> Dictionary:
	return {
		"victory": [
			"说服 3 名持疑者支持新桥 — 头顶 [color=#7ab2ff]蓝色名字[/color] 即可对话",
			"为 4 名疑问者解答桥梁问题 — 头顶 [color=#73f28c]绿色名字[/color] 即可对话",
			"如果不知道答案，向头顶 [color=#ffd24a]黄色名字[/color] 的工地长辈求教",
			"也可以随时打开右上的「桥梁知识」按钮翻阅",
		],
		"defeat": [],
	}


func is_free_roam_level() -> bool:
	return true


func get_wave_config() -> Dictionary:
	return {}


func get_teams_config() -> Array:
	var hero_unit := _get_static_unit("Player")
	var npc_units: Array[Unit] = []
	for spec in _NpcSpecLibraryScript.get_specs():
		var npc := _get_static_unit(String(spec.get("node_name", "")))
		if npc != null: npc_units.append(npc)
	return [
		{"name": "玩家", "faction": "好人", "controller": "player", "units": [hero_unit] if hero_unit != null else []},
		{"name": "桥上众人", "faction": "好人", "controller": "ai", "units": npc_units},
	]


func _get_static_unit(node_name: String) -> Unit:
	if node_name.is_empty() or not has_node("Entities/Units/%s" % node_name):
		return null
	return get_node("Entities/Units/%s" % node_name) as Unit


## 组合根：装配组件、布置主角与 NPC、挂 MissionHud、注册目标计数。
func _on_level_ready() -> void:
	# 隐藏回合制 UI（自由移动模式不需要）
	for path in ["GUI/RoundLabel", "GUI/TurnLabel", "GUI/EndTurnButton"]:
		var n := get_node_or_null(path)
		if n != null: n.visible = false
	# 调试按钮仅 debug 模式显示
	if not Settings.debug_mode:
		for path in ["GUI/WinButton", "GUI/AIButton"]:
			var n := get_node_or_null(path)
			if n != null: n.visible = false
	_init_components()
	# 角色位置在 tscn 中静态摆放；脚本只补运行时数据、AI 与头顶姓名牌。
	var li_chun := _get_static_unit("Player")
	if li_chun == null:
		push_error("BridgeTour: missing static hero unit at Entities/Units/Player")
		return
	var hero_visual := li_chun.visual_scene if li_chun.visual_scene != null else _VISUAL_LI_CHUN
	li_chun.apply_runtime_setup(_UD_LI_CHUN, hero_visual, _HERO_COLOR)
	_setup_hero_stats(li_chun)
	hero = li_chun
	li_chun.set_overhead_name_label("李春", _HERO_COLOR)
	# 初始化 tscn 静态摆放的 NPC。
	_npcs.clear()
	_spawner = NpcSpawner.new()
	_spawner.setup(self, _UD_NPC_TEMPLATE, _refresh_npc_name_label)
	for spec in _NpcSpecLibraryScript.get_specs():
		var npc := _spawner.spawn(spec)
		if npc != null:
			_npcs.append(npc)
	# Mission HUD（左上）+ 目标计数（SocialLevelEndFlow 单一真相源）
	_mission_hud = _MissionHudScene.instantiate()
	add_child(_mission_hud)
	_mission_hud.set_targets(PERSUADE_TARGET, QA_TARGET)
	get_end_flow().add_goal("persuade", PERSUADE_TARGET, "说服")
	get_end_flow().add_goal("qa", QA_TARGET, "解答")
	for npc in _npcs:
		var st := _npc_state(npc)
		_mission_hud.add_npc(st.role, npc.unit_data.unit_name, st.is_done())
		# persuade NPC 显示初始 stance；qa / mentor 静默忽略
		if st.role == "persuade":
			_mission_hud.update_npc_stance(npc.unit_data.unit_name, st.stance, STANCE_PERSUADED)
	_mission_hud.set_counts(get_end_flow().get_progress("persuade"), get_end_flow().get_progress("qa"))
	_select_hero_silently()


## 运行时覆写李春战斗数值（等价原 setup_unit_stats(..., is_hero=true)——含 set_base_stats 烤难度系数）。
func _setup_hero_stats(unit: Unit) -> void:
	var s: CombatStats = unit.combat_stats
	s.unit_name = "李春"
	s.set_base_stats(130, 24, HERO_INFINITE_AP)
	s.move_cost_per_tile = 6
	s.is_hero = true
	unit.refresh_overhead_bars()
	unit.apply_faction_outline()


# ── 交互编排 ──


## 读取 NPC 的类型化社交状态（挂在 unit.set_meta(NpcSocialState.META_KEY) 上）。
func _npc_state(npc: Unit) -> NpcSocialState: return npc.get_meta(NpcSocialState.META_KEY, null) as NpcSocialState


## 头顶姓名牌：role + 完成态决定颜色，替代 HP/AP 条。
func _refresh_npc_name_label(unit: Unit) -> void: NpcBadgePresenter.refresh(unit, _npc_state(unit))


func get_interaction_target() -> Unit: return _interaction_target


func _open_knowledge_panel() -> void: _get_learned_view().open_panel(self)


func _find_npc_at_cell(cell: Vector2i) -> Unit:
	for npc in _npcs:
		if is_instance_valid(npc) and npc is Unit and (npc as Unit).cell == cell: return npc
	return null


## 主交互入口——按 NPC role 派发到三种流。
func _dispatch_interaction(npc: Unit) -> void:
	match _npc_state(npc).role:
		"persuade":
			await _persuade_flow.run(npc)
		"qa":
			await _qa_flow.run(npc)
		"mentor":
			await _mentor_flow.run(npc)


# ── FreeRoamSocialLevel 覆写（输入 / 移动 / 收尾）──


## 让 tscn 静态摆放的 NPC 参与点选（ActorRegistry 只登记过 spawn_unit 的单位）。
func _get_actors_at_cell(cell: Vector2i) -> Array:
	var out: Array = super._get_actors_at_cell(cell)
	for npc in _npcs:
		if is_instance_valid(npc) and npc is Unit and (npc as Unit).cell == cell and not out.has(npc):
			out.append(npc)
	return out


## 移动占位守卫：目标格在"NPC 边漫游边变格"过程中可能从空变占，而 range overlay 是
## show_range_ap 时刻的快照。此处在移动路径加最后一道闸：占用就拒绝并提示。点 NPC 走交互路径。
func _on_move_requested(from_cell: Vector2i, to_cell: Vector2i) -> void:
	if not _is_cell_occupied_by_other(to_cell, hero):
		super._on_move_requested(from_cell, to_cell)
		return
	Notify.warn("目标格已被占用", 1.5)
	# 控制器已把状态切到 TARGETING_MOVE/ANIMATING，这里调回可重试状态，避免软锁
	_input.set_state(FreeRoamInputController.S.UNIT_SELECTED)


func _is_cell_occupied_by_other(cell: Vector2i, exclude: Node) -> bool:
	if is_instance_valid(hero) and hero is Unit and hero != exclude and (hero as Unit).cell == cell: return true
	for npc in _npcs:
		if npc != exclude and is_instance_valid(npc) and npc is Unit and (npc as Unit).cell == cell: return true
	return false


func _select_hero_silently() -> void:
	if hero is Unit: _update_status_bar_for_unit(hero, false)


## 点英雄 → 显示移动范围预览（AP 预算上限防止无限 AP 把整张图 overlay 算出来）。
func _on_actor_selected(actor) -> void:
	var unit := actor as Unit
	if unit == null or move_overlay == null or tilemap == null:
		return
	if unit.combat_stats == null:
		move_overlay.show_range(tilemap, movement_manager, unit.cell, unit.movement_points)
		return
	var stats: CombatStats = unit.combat_stats
	if not stats.can_move(): return
	var occupied: Array[Vector2i] = []
	for other in _npcs:
		if is_instance_valid(other) and other is Unit and other != unit:
			occupied.append((other as Unit).cell)
	var effective_cost := stats.move_cost_per_tile + stats.get_move_ap_modifier()
	var budget: int = stats.ap_current
	if unit == hero:
		budget = mini(budget, HERO_MOVE_PREVIEW_AP_BUDGET)
	move_overlay.show_range_ap(tilemap, movement_manager, unit.cell, budget, effective_cost, occupied, [])


## 点 NPC → 交互（输入锁 + 按 role 派发）。
func _on_actor_interact_requested(_actor, target) -> void:
	if not (target is Unit): return
	var npc := _find_npc_at_cell((target as Unit).cell)
	if npc == null: return
	_interaction_target = npc
	_begin_input_lock()
	await _dispatch_interaction(npc)
	_end_input_lock()
	_interaction_target = null
	_select_hero_silently()


## 移动完成：AP 回满（等同无限移动）。
func _on_actor_move_completed(_actor) -> void:
	if hero != null and hero is Unit and (hero as Unit).combat_stats != null:
		var stats: CombatStats = (hero as Unit).combat_stats
		stats.ap_current = stats.ap_max
		(hero as Unit).refresh_overhead_bars()


## 目标全达标：胜利横幅 + 通关（原 _check_all_done_for_victory）。
func _on_all_goals_met() -> void:
	Notify.success("桥成在望！群众心服口服。", 5.0)
	complete_level.call_deferred()


# ── 顶栏按钮（FreeRoamSocialLevel 不接 BaseLevel 的按钮线，这里就地实现）──


func _on_objectives_button_pressed() -> void:
	if has_overlay(): return
	var obj := get_objectives_text()
	if obj["victory"].is_empty() and obj["defeat"].is_empty() and obj.get("details", []).is_empty(): return
	var panel: ObjectivesPanel = _ObjectivesPanelScene.instantiate()
	panel.victory_lines = obj["victory"]
	panel.defeat_lines = obj["defeat"]
	panel.detail_lines = obj.get("details", [])
	_open_overlay(ActiveOverlay.OBJECTIVES_REVIEW, panel)


func _on_settings_button_pressed() -> void:
	if has_overlay(): return
	var panel: SettingsPanel = _SettingsPanelScene.instantiate()
	panel.show_back_to_menu = true
	_open_overlay(ActiveOverlay.SETTINGS, panel)


func _on_progress_button_pressed() -> void:
	if has_overlay(): return
	var panel: Node = _ProgressPanelScene.instantiate()
	panel.set("show_debug_controls", Settings.debug_mode)
	_open_overlay(ActiveOverlay.PROGRESS, panel)
	UiSounds.play_popup()


func _on_tutorial_button_pressed() -> void:
	if has_overlay(): return
	_open_overlay(ActiveOverlay.TUTORIAL_PANEL, _TutorialPanelScene.instantiate())


func _on_win_button_pressed() -> void: complete_level()
func _on_end_turn_button_pressed() -> void: pass
func _on_ai_button_pressed() -> void: pass
