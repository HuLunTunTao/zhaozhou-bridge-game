class_name BridgeTourLevel
extends BaseLevel
## 验桥日 · LLM Agent 关卡。
##
## 9 个 NPC 三种 role：
##   persuade（蓝？）：李春自由打字 → LLM 评 stance_delta，stance>=70 视为说服
##   qa（绿？）：NPC 抛预设问题 → 李春答 → LLM 判 is_correct，对则视为解答
##   mentor（黄！）：李春从主题菜单选一项 → LLM 用对应史实讲解，topic_key 记入"已学"
##
## 已学知识注入 persuade / qa 的 prompt context，让 LLM 倾向给"用上知识的回答"更高分。
## 胜利条件：说服 3/3 + 解答 4/4 全完成。

# ── 资源 ──
const _UD_LI_CHUN := preload("res://data/units/hero_li_chun.tres")
const _UD_NPC_TEMPLATE := preload("res://data/units/craftsman_guard.tres")
const _SK_INTERACT := preload("res://data/skills/bridge_tour_interact.tres")
const _VISUAL_CRAFTSMAN := preload("res://scenes/unit/visual/human/工匠/工匠_visual.tscn")
const _VISUAL_SURVEYOR := preload("res://scenes/unit/visual/human/测量工/测量工_visual.tscn")

const _RoamingAIScript := preload("res://scripts/npc/roaming_ai.gd")
const _NpcPersonasScript := preload("res://scripts/llm/npc_personas.gd")
const _ChatterPromptsScript := preload("res://scripts/llm/chatter_prompts.gd")
const _LLMClientScript := preload("res://scripts/llm/llm_client.gd")
const _ChatterVoiceScript := preload("res://scripts/tts/chatter_voice_adapter.gd")
const _PortraitResolverScript := preload("res://scripts/llm/portrait_resolver.gd")
const _BridgeKnowledgeScript := preload("res://scripts/data/bridge_knowledge.gd")
const _ArgumentInputPanelScene := preload("res://scenes/ui/argument_input_panel.tscn")
const _TopicMenuPanelScene := preload("res://scenes/ui/topic_menu_panel.tscn")
const _KnowledgePanelScene := preload("res://scenes/ui/knowledge_panel.tscn")
const _ThinkingOverlayScene := preload("res://scenes/ui/thinking_overlay.tscn")
const _MissionHudScene := preload("res://scenes/levels/bridge_tour/mission_hud.tscn")

# ── 数值常量 ──
const _HERO_COLOR := Color(1, 0.85, 0, 1)
const _HERO_CELL := Vector2i(0, 0)
const STANCE_PERSUADED := 70
const PERSUADE_TARGET := 3
const QA_TARGET := 4
const NEIGHBOR_INTERJECT_PROB := 0.4
const NEIGHBOR_INTERJECT_RANGE := 5
const HERO_INFINITE_AP := 99999

# ── 头顶图标颜色 ──
const _ICON_PERSUADE := Color(0.45, 0.7, 1.0)         # 蓝
const _ICON_QA := Color(0.45, 0.95, 0.55)             # 绿
const _ICON_MENTOR := Color(1.0, 0.85, 0.32)          # 黄
const _ICON_DONE := Color(1.0, 0.85, 0.32)            # 完成态金（同 mentor）


## NPC 配置表。3 persuade + 4 qa + 2 mentor = 9 人。
func _get_npc_specs() -> Array[Dictionary]:
	return [
		# ─── 说服类（3）───
		{
			"unit_id": "bridge_old_master", "unit_name": "老匠首", "role": "persuade",
			"bridge_part": "主拱", "cell": Vector2i(3, 0),
			"color": Color(0.55, 0.4, 0.3), "visual": _VISUAL_CRAFTSMAN,
			"stance": 10, "roam_mode": _RoamingAIScript.Mode.STATIONARY, "waypoints": [],
		},
		{
			"unit_id": "bridge_river_chief", "unit_name": "河工总管", "role": "persuade",
			"bridge_part": "桥台", "cell": Vector2i(-3, 1),
			"color": Color(0.4, 0.55, 0.7), "visual": _VISUAL_CRAFTSMAN,
			"stance": 40, "roam_mode": _RoamingAIScript.Mode.PATROL,
			"waypoints": [Vector2i(-3, 1), Vector2i(-3, 3), Vector2i(-5, 3), Vector2i(-5, 1)] as Array[Vector2i],
		},
		{
			"unit_id": "bridge_court_inspector", "unit_name": "朝廷视察官", "role": "persuade",
			"bridge_part": "桥面中心", "cell": Vector2i(1, -2),
			"color": Color(0.7, 0.55, 0.3), "visual": _VISUAL_CRAFTSMAN,
			"stance": 30, "roam_mode": _RoamingAIScript.Mode.PATROL,
			"waypoints": [Vector2i(1, -2), Vector2i(2, -2), Vector2i(2, -1), Vector2i(1, -1)] as Array[Vector2i],
		},
		# ─── 解答类（4）───
		{
			"unit_id": "bridge_apprentice", "unit_name": "学徒工", "role": "qa",
			"bridge_part": "小拱", "cell": Vector2i(-1, 2),
			"color": Color(0.5, 0.85, 0.6), "visual": _VISUAL_SURVEYOR,
			"roam_mode": _RoamingAIScript.Mode.RANDOM_WALK, "waypoints": [],
		},
		{
			"unit_id": "bridge_merchant", "unit_name": "商旅过客", "role": "qa",
			"bridge_part": "桥头", "cell": Vector2i(4, 2),
			"color": Color(0.85, 0.7, 0.4), "visual": _VISUAL_SURVEYOR,
			"roam_mode": _RoamingAIScript.Mode.PATROL,
			"waypoints": [Vector2i(4, 2), Vector2i(5, 2), Vector2i(5, 3), Vector2i(4, 3)] as Array[Vector2i],
		},
		{
			"unit_id": "bridge_scholar", "unit_name": "游学书生", "role": "qa",
			"bridge_part": "望柱栏板", "cell": Vector2i(-4, -1),
			"color": Color(0.85, 0.85, 0.95), "visual": _VISUAL_SURVEYOR,
			"roam_mode": _RoamingAIScript.Mode.RANDOM_WALK, "waypoints": [],
		},
		{
			"unit_id": "bridge_fisherman", "unit_name": "渔夫", "role": "qa",
			"bridge_part": "桥下河滩", "cell": Vector2i(0, 4),
			"color": Color(0.55, 0.7, 0.85), "visual": _VISUAL_SURVEYOR,
			"roam_mode": _RoamingAIScript.Mode.PATROL,
			"waypoints": [Vector2i(0, 4), Vector2i(1, 4), Vector2i(1, 5), Vector2i(0, 5)] as Array[Vector2i],
		},
		# ─── 求教类（2）───
		{
			"unit_id": "bridge_old_overseer", "unit_name": "老监工", "role": "mentor",
			"bridge_part": "桥头远处", "cell": Vector2i(5, -3),
			"color": Color(0.65, 0.55, 0.5), "visual": _VISUAL_CRAFTSMAN,
			"roam_mode": _RoamingAIScript.Mode.STATIONARY, "waypoints": [],
			# 老监工偏全局：拱形 / 时代 / 旧制
			"mentor_topics": ["扁拱与半圆拱有何不同？", "为何在隋代建此奇桥？", "和旧制多孔小拱比，胜在哪？"],
		},
		{
			"unit_id": "bridge_old_stonemason", "unit_name": "老石匠", "role": "mentor",
			"bridge_part": "石作工棚", "cell": Vector2i(-2, -3),
			"color": Color(0.7, 0.65, 0.55), "visual": _VISUAL_CRAFTSMAN,
			"roam_mode": _RoamingAIScript.Mode.STATIONARY, "waypoints": [],
			# 老石匠偏材料 / 桥券 / 桥台 / 装饰
			"mentor_topics": ["二十八道券怎么锁住不散？", "本地青石比别处好在哪？", "桥台只埋一丈余怎么扛得住？", "栏板蛟龙也是结构？"],
		},
	]

# ── 状态 ──
var _npcs: Array[Unit] = []
var _interaction_target: Unit = null
var _llm: Node = null
var _voice: Node = null
var _mission_hud: Node = null
## 玩家通过 mentor 学过的知识 key（来自 BridgeKnowledge.TOPICS）。
var _player_learned_topics: Array[String] = []
## 玩家在 persuade / qa 中实际"用上了"的知识 key（在 prompt eval 时 LLM 标记的）。
var _player_used_topics: Array[String] = []


func _get_llm() -> Node:
	if _llm == null:
		_llm = _LLMClientScript.new()
		add_child(_llm)
	return _llm


func _get_voice() -> Node:
	if _voice == null:
		_voice = _ChatterVoiceScript.new()
		add_child(_voice)
	return _voice


func get_teams_config() -> Array:
	if has_node("Entities/Units"):
		for child in $"Entities/Units".get_children():
			$"Entities/Units".remove_child(child)
			child.queue_free()
	return [
		{"name": "玩家", "faction": "好人", "controller": "player", "units": []},
		{"name": "桥上众人", "faction": "好人", "controller": "ai", "units": []},
	]


func get_objectives_text() -> Dictionary:
	# 进入时显示 BRIEFING——和别的关卡一样
	return {
		"victory": [
			"说服 3 名持疑者支持新桥 — 头顶 [color=#7ab2ff]?[/color] 即可对话",
			"为 4 名疑问者解答桥梁问题 — 头顶 [color=#73f28c]?[/color] 即可对话",
			"如果不知道答案，向头顶 [color=#ffd24a]![/color] 的工地长辈求教",
			"也可以随时打开右上的「桥梁知识」按钮翻阅",
		],
		"defeat": [],
	}


func is_free_roam_level() -> bool:
	return true


## 移动占位守卫：自由移动模式下，玩家点击的目标格在"NPC 边漫游边变格"过程中
## 可能从空变占。range overlay 是 show_range_ap 时刻的快照，无法实时刷新。
## 此处在 confirm 路径加最后一道闸：占用就拒绝并提示，不让李春叠到 NPC 头上。
## TARGETING_SKILL（交互 NPC）不在此守卫范围——那条路径就是要点 NPC 的格。
func confirm_cell(cell: Vector2i) -> void:
	if _input_state == InputState.IDLE or _input_state == InputState.UNIT_SELECTED:
		if _is_cell_occupied_by_other(cell, hero):
			Notify.notify("目标格已被占用", Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 1.5)
			return
	super.confirm_cell(cell)


func _is_cell_occupied_by_other(cell: Vector2i, exclude: Node) -> bool:
	for unit in _get_all_units():
		if unit == exclude:
			continue
		if is_instance_valid(unit) and unit is Unit and (unit as Unit).cell == cell:
			return true
	return false


func get_wave_config() -> Dictionary:
	return {}


func _on_level_ready() -> void:
	# 隐藏回合制 UI（自由移动模式不需要）
	if _turn_label: _turn_label.visible = false
	if _round_label: _round_label.visible = false
	if _end_turn_button: _end_turn_button.visible = false
	# 起手 spawn 李春
	var li_chun := spawn_unit(_UD_LI_CHUN, _HERO_CELL, 0)
	li_chun.unit_color = _HERO_COLOR
	setup_unit_stats(li_chun, "李春", 130, 24, HERO_INFINITE_AP, 6, Enums.Element.NONE, 0, true)
	hero = li_chun
	set_unit_skills(li_chun, [_SK_INTERACT])
	# Spawn NPCs
	for spec in _get_npc_specs():
		_spawn_npc(spec)
	# Mission HUD（左上）
	_mission_hud = _MissionHudScene.instantiate()
	add_child(_mission_hud)
	_mission_hud.set_targets(PERSUADE_TARGET, QA_TARGET)
	for npc in _npcs:
		var role: String = String(npc.get_meta("npc_role", "persuade"))
		var done: bool = _npc_done(npc)
		_mission_hud.add_npc(role, npc.unit_data.unit_name, done)
		# persuade NPC 显示初始 stance；qa / mentor 静默忽略
		if role == "persuade":
			var stance0: int = int(npc.get_meta("npc_stance", 50))
			_mission_hud.update_npc_stance(npc.unit_data.unit_name, stance0, STANCE_PERSUADED)

	# 自由移动模式不走 _init_turn_system，但 _can_accept_command 仍要 _waiting_for_player_input=true
	_waiting_for_player_input = true
	current_team_index = 0
	_select_hero_silently()


func _select_hero_silently() -> void:
	if hero == null or not (hero is Unit):
		return
	selected_unit = hero
	unit_selected = true
	_input_state = InputState.IDLE
	_update_status_bar_for_unit(hero, false)
	selection_changed.emit(hero)


func _spawn_npc(spec: Dictionary) -> Unit:
	var data: UnitData = _UD_NPC_TEMPLATE.duplicate()
	data.resource_local_to_scene = true
	data.unit_id = spec["unit_id"]
	data.unit_name = spec["unit_name"]
	data.skills = []
	var unit := spawn_unit(data, spec["cell"], 1, spec["visual"])
	unit.unit_color = spec["color"]
	# NPC 元数据
	var role: String = String(spec.get("role", "persuade"))
	unit.set_meta("npc_role", role)
	unit.set_meta("npc_bridge_part", spec.get("bridge_part", ""))
	unit.set_meta("npc_dialogue_log", [] as Array[Dictionary])
	if role == "persuade":
		var stance: int = int(spec.get("stance", 50))
		unit.set_meta("npc_stance", stance)
		unit.set_meta("npc_persuaded", stance >= STANCE_PERSUADED)
	elif role == "qa":
		var persona: Dictionary = _NpcPersonasScript.get_persona(unit.unit_data.unit_id, unit.unit_data.camp)
		unit.set_meta("npc_qa_question", String(persona.get("qa_question", "我有一事相问，可解么？")))
		unit.set_meta("npc_qa_solved", false)
	elif role == "mentor":
		var topics_raw: Array = spec.get("mentor_topics", [])
		var topics: Array[String] = []
		for t in topics_raw:
			topics.append(String(t))
		unit.set_meta("npc_mentor_topics", topics)
	# RoamingAI
	var ai := _RoamingAIScript.new()
	ai.name = "RoamingAI"
	unit.add_child(ai)
	ai.setup(unit, self, spec["roam_mode"], spec.get("waypoints", []))
	_npcs.append(unit)
	# 头顶图标
	_refresh_npc_icon(unit)
	return unit


## 头顶图标：role + 完成态决定文字 + 颜色。直接借用 UnitHpBar 的 ElemLabel 位。
func _refresh_npc_icon(unit: Unit) -> void:
	var role: String = String(unit.get_meta("npc_role", ""))
	var done: bool = _npc_done(unit)
	if done and role != "mentor":
		unit.set_overhead_status_label("✓", _ICON_DONE)
		return
	match role:
		"persuade":
			unit.set_overhead_status_label("?", _ICON_PERSUADE)
		"qa":
			unit.set_overhead_status_label("?", _ICON_QA)
		"mentor":
			unit.set_overhead_status_label("!", _ICON_MENTOR)
		_:
			unit.set_overhead_status_label("", Color.WHITE)


## 该 NPC 是否完成了交互目标（persuade=已说服，qa=已解答；mentor 永不"完成"）。
func _npc_done(unit: Unit) -> bool:
	var role: String = String(unit.get_meta("npc_role", ""))
	match role:
		"persuade":
			return bool(unit.get_meta("npc_persuaded", false))
		"qa":
			return bool(unit.get_meta("npc_qa_solved", false))
		_:
			return false


func get_interaction_target() -> Unit:
	return _interaction_target


# ─────────────────────────────────────────────
# 顶栏"桥梁知识"按钮 + 知识面板
# ─────────────────────────────────────────────


func _open_knowledge_panel() -> void:
	if has_overlay():
		return
	var panel: Node = _KnowledgePanelScene.instantiate()
	if not _open_overlay(ActiveOverlay.TUTORIAL_PANEL, panel, &"closed"):
		panel.queue_free()
		return
	panel.set_state(_player_learned_topics, _player_used_topics)


# ─────────────────────────────────────────────
# 交互入口：按 role 分支
# ─────────────────────────────────────────────

func _confirm_targeting_skill(cell: Vector2i) -> void:
	if _current_skill != null and _current_skill.skill_id == "bridge_tour_interact":
		await _confirm_interact_target(cell)
		return
	super._confirm_targeting_skill(cell)


func _confirm_interact_target(cell: Vector2i) -> void:
	if _skill_targeting == null or not _skill_targeting.has_cast_cell(cell):
		_go_idle()
		_select_hero_silently()
		return
	var npc := _find_npc_at_cell(cell)
	_clear_skill_targeting()
	if npc == null:
		_go_idle()
		_select_hero_silently()
		return
	_interaction_target = npc
	_begin_input_lock()
	await _dispatch_interaction(npc)
	_end_input_lock()
	_interaction_target = null
	_select_hero_silently()


func _find_npc_at_cell(cell: Vector2i) -> Unit:
	for npc in _npcs:
		if is_instance_valid(npc) and npc is Unit and (npc as Unit).cell == cell:
			return npc
	return null


## 主交互入口——按 NPC role 派发到三种流。
func _dispatch_interaction(npc: Unit) -> void:
	var role: String = String(npc.get_meta("npc_role", "persuade"))
	match role:
		"persuade":
			await _flow_persuade(npc)
		"qa":
			await _flow_qa(npc)
		"mentor":
			await _flow_mentor(npc)


# ─────────────────────────────────────────────
# Flow 1：说服（同旧版，加 learned_csv 注入 + 头顶图标更新）
# ─────────────────────────────────────────────

func _flow_persuade(npc: Unit) -> void:
	if _npc_done(npc):
		# 已说服的不再交互——给个轻提示就走
		Notify.notify("已说服 %s" % npc.unit_data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.INFO, 1.5)
		return
	var bridge_part: String = String(npc.get_meta("npc_bridge_part", ""))
	var panel: Node = _ArgumentInputPanelScene.instantiate()
	add_child(panel)
	panel.show_for(npc.unit_data.unit_name, bridge_part)
	panel.set_learned_topics(_player_learned_topics, _player_used_topics)
	panel.set_history(npc.get_meta("npc_dialogue_log", [] as Array[Dictionary]))
	var argument: String = await panel.argument_submitted
	if argument.is_empty():
		return
	var thinking := _make_thinking_overlay()
	add_child(thinking)
	var ans: Dictionary = await _generate_persuade_answer(npc, argument)
	thinking.queue_free()
	_apply_persuade_result(npc, ans)
	var reply: String = String(ans.get("reply", ""))
	var is_fallback: bool = bool(ans.get("is_fallback", false))
	# 记入对话历史；fallback 文本仍记（让玩家看到"NPC 没接到话"），但 LLM 失败那条
	# 后续不会被注入 prompt context（chatter_prompts.bridge_topic_answer 不读 dialogue_log）
	if not is_fallback:
		_append_dialogue_log(npc, argument, reply, String(ans.get("tone", "")))
	else:
		_append_dialogue_log(npc, argument, reply, "fallback")
	await _play_npc_line(npc, reply, not is_fallback)
	await _maybe_neighbor_interject(npc, reply)


func _generate_persuade_answer(npc: Unit, topic: String) -> Dictionary:
	var persona: Dictionary = _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var bridge_part: String = String(npc.get_meta("npc_bridge_part", ""))
	var stance: int = int(npc.get_meta("npc_stance", 50))
	var sys: String = _ChatterPromptsScript.build_system_prompt(persona, "bridge_topic_answer", _learned_memo(), "{}")
	var user: String = _ChatterPromptsScript.build_user_prompt(persona, "bridge_topic_answer", {
		"topic": topic,
		"bridge_part": bridge_part,
		"stance": stance,
	})
	var resp: Dictionary = await _get_llm().chat_completion([
		{"role": "system", "content": sys},
		{"role": "user", "content": user},
	], {"max_tokens": 220, "temperature": 0.85})
	if resp.get("ok", false):
		var parsed := _parse_object_json(String(resp.get("text", "")))
		if not parsed.is_empty() and parsed.has("reply"):
			if not parsed.has("stance_delta"): parsed["stance_delta"] = 0
			if not parsed.has("tone"): parsed["tone"] = ""
			return parsed
	return {
		"reply": "（%s 沉吟不语）" % persona.get("name", npc.unit_data.unit_name),
		"stance_delta": 0,
		"tone": "沉默",
		"is_fallback": true,
	}


func _apply_persuade_result(npc: Unit, ans: Dictionary) -> void:
	var delta: int = int(ans.get("stance_delta", 0))
	var old_stance: int = int(npc.get_meta("npc_stance", 50))
	var new_stance: int = clampi(old_stance + delta, 0, 100)
	npc.set_meta("npc_stance", new_stance)
	# LLM 引用过的知识 → 加入 used 集合，知识面板高亮
	for k in ans.get("knowledge_used", []):
		var key := String(k)
		if not key.is_empty() and not _player_used_topics.has(key):
			_player_used_topics.append(key)
	var was_persuaded: bool = bool(npc.get_meta("npc_persuaded", false))
	var now_persuaded: bool = new_stance >= STANCE_PERSUADED
	if not was_persuaded and now_persuaded:
		npc.set_meta("npc_persuaded", true)
		Notify.notify("已说服 %s" % npc.unit_data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 3.0)
		_refresh_npc_icon(npc)
		_check_all_done_for_victory()
	elif delta < 0:
		Notify.notify("%s 摇头：「此说不通」" % npc.unit_data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 2.5)
	if _mission_hud:
		_mission_hud.update_npc("persuade", npc.unit_data.unit_name, now_persuaded)
		_mission_hud.update_npc_stance(npc.unit_data.unit_name, new_stance, STANCE_PERSUADED)


# ─────────────────────────────────────────────
# Flow 2：解答（NPC 抛预设问题 → 玩家答 → LLM 判对错）
# ─────────────────────────────────────────────

func _flow_qa(npc: Unit) -> void:
	if _npc_done(npc):
		Notify.notify("%s 的疑问已解" % npc.unit_data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.INFO, 1.5)
		return
	var bridge_part: String = String(npc.get_meta("npc_bridge_part", ""))
	var question: String = _pick_qa_question(npc)
	# 先让 NPC 把问题抛给玩家——dialogue_box 显示 + TTS
	await _play_npc_line(npc, question, true)
	# 玩家输入答案；副标题用 NPC 名 + 桥部位
	var panel: Node = _ArgumentInputPanelScene.instantiate()
	add_child(panel)
	panel.show_for(npc.unit_data.unit_name, "%s · 「%s」" % [bridge_part, question])
	panel.set_learned_topics(_player_learned_topics, _player_used_topics)
	panel.set_history(npc.get_meta("npc_dialogue_log", [] as Array[Dictionary]))
	var answer: String = await panel.argument_submitted
	if answer.is_empty():
		return
	var thinking := _make_thinking_overlay()
	add_child(thinking)
	var eval: Dictionary = await _generate_qa_eval(npc, question, answer)
	thinking.queue_free()
	_apply_qa_result(npc, eval)
	var feedback: String = String(eval.get("feedback", ""))
	var is_fallback: bool = bool(eval.get("is_fallback", false))
	# 记入对话历史。问题用本轮抛出的 question + 玩家答案 + NPC feedback 三段拼接：
	# 历史每条记 player（玩家答案）/ npc（feedback），question 在显示时上下文已隐含。
	_append_dialogue_log(npc, answer, feedback, "fallback" if is_fallback else "qa")
	await _play_npc_line(npc, feedback, not is_fallback)
	await _maybe_neighbor_interject(npc, feedback)


## 把一轮交互写入 NPC 的 dialogue_log meta。供 set_history 显示给玩家看。
## tone 字段可记 "fallback" / "qa" / LLM 给的 tone 标签，便于将来分类（当前未做特殊渲染）。
func _append_dialogue_log(npc: Unit, player: String, npc_text: String, tone: String) -> void:
	var log: Array = npc.get_meta("npc_dialogue_log", [] as Array[Dictionary])
	log.append({
		"player": player,
		"npc": npc_text,
		"npc_name": npc.unit_data.unit_name,
		"tone": tone,
	})
	npc.set_meta("npc_dialogue_log", log)


## 取一句 QA 问题。优先用 persona.qa_questions 数组按尝试次数轮换；空时 fallback 到旧
## qa_question 单字段；再空 fallback 到 spawn 时存的 npc_qa_question meta；最终兜底固定句。
## 选完后 npc_qa_attempt += 1 写回 meta，供下次轮换。
func _pick_qa_question(npc: Unit) -> String:
	var persona: Dictionary = _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var attempt: int = int(npc.get_meta("npc_qa_attempt", 0))
	var qs_raw: Variant = persona.get("qa_questions", [])
	var qs: Array = qs_raw if qs_raw is Array else []
	var picked: String = ""
	if not qs.is_empty():
		picked = String(qs[attempt % qs.size()])
	else:
		picked = String(persona.get("qa_question", ""))
	if picked.is_empty():
		picked = String(npc.get_meta("npc_qa_question", "我有一事相问，可解么？"))
	npc.set_meta("npc_qa_attempt", attempt + 1)
	return picked


func _generate_qa_eval(npc: Unit, question: String, answer: String) -> Dictionary:
	var persona: Dictionary = _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var sys: String = _ChatterPromptsScript.build_system_prompt(persona, "bridge_qa_eval", _learned_memo(), "{}")
	var user: String = _ChatterPromptsScript.build_user_prompt(persona, "bridge_qa_eval", {
		"question": question,
		"answer": answer,
		"learned_csv": _learned_csv(),
	})
	var resp: Dictionary = await _get_llm().chat_completion([
		{"role": "system", "content": sys},
		{"role": "user", "content": user},
	], {"max_tokens": 220, "temperature": 0.7})
	if resp.get("ok", false):
		var parsed := _parse_object_json(String(resp.get("text", "")))
		if not parsed.is_empty() and parsed.has("feedback"):
			if not parsed.has("is_correct"): parsed["is_correct"] = false
			return parsed
	return {
		"is_correct": false,
		"feedback": "（%s 摇头不语）" % persona.get("name", npc.unit_data.unit_name),
		"knowledge_used": [],
		"is_fallback": true,
	}


func _apply_qa_result(npc: Unit, eval: Dictionary) -> void:
	for k in eval.get("knowledge_used", []):
		var key := String(k)
		if not key.is_empty() and not _player_used_topics.has(key):
			_player_used_topics.append(key)
	var is_correct: bool = bool(eval.get("is_correct", false))
	if is_correct and not bool(npc.get_meta("npc_qa_solved", false)):
		npc.set_meta("npc_qa_solved", true)
		Notify.notify("已解答 %s 的疑问" % npc.unit_data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 3.0)
		_refresh_npc_icon(npc)
		_check_all_done_for_victory()
	elif not is_correct:
		Notify.notify("%s 摇头：尚有疑虑" % npc.unit_data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 2.5)
	if _mission_hud:
		_mission_hud.update_npc("qa", npc.unit_data.unit_name, is_correct)


# ─────────────────────────────────────────────
# Flow 3：求教（mentor 给主题菜单 → 玩家选 → LLM 用一条知识讲解）
# ─────────────────────────────────────────────

func _flow_mentor(npc: Unit) -> void:
	var topics_raw: Array = npc.get_meta("npc_mentor_topics", [])
	var topics: Array[String] = []
	for t in topics_raw:
		topics.append(String(t))
	var menu: Node = _TopicMenuPanelScene.instantiate()
	add_child(menu)
	menu.show_for(npc.unit_data.unit_name, topics)
	var pick: String = await menu.topic_picked
	if pick.is_empty():
		return
	var query: String = pick
	if pick == "__free__":
		var inp: Node = _ArgumentInputPanelScene.instantiate()
		add_child(inp)
		inp.show_for(npc.unit_data.unit_name, "向 %s 自由请教" % npc.unit_data.unit_name)
		inp.set_learned_topics(_player_learned_topics, _player_used_topics)
		query = await inp.argument_submitted
		if query.is_empty():
			return
	var thinking := _make_thinking_overlay()
	add_child(thinking)
	var lesson: Dictionary = await _generate_mentor_lesson(npc, query)
	thinking.queue_free()
	_apply_mentor_lesson(npc, lesson)
	var with_voice: bool = not bool(lesson.get("is_fallback", false))
	await _play_npc_line(npc, String(lesson.get("reply", "")), with_voice)


func _generate_mentor_lesson(npc: Unit, query: String) -> Dictionary:
	var persona: Dictionary = _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var sys: String = _ChatterPromptsScript.build_system_prompt(persona, "bridge_knowledge_explain", _learned_memo(), "{}")
	var user: String = _ChatterPromptsScript.build_user_prompt(persona, "bridge_knowledge_explain", {
		"query": query,
		"topics_csv": _BridgeKnowledgeScript.key_to_title_csv(),
	})
	var resp: Dictionary = await _get_llm().chat_completion([
		{"role": "system", "content": sys},
		{"role": "user", "content": user},
	], {"max_tokens": 280, "temperature": 0.7})
	if resp.get("ok", false):
		var parsed := _parse_object_json(String(resp.get("text", "")))
		if not parsed.is_empty() and parsed.has("reply"):
			return parsed
	return {
		"reply": "（%s 摸了摸下巴，没说出口）" % persona.get("name", npc.unit_data.unit_name),
		"topic_key": "",
		"is_fallback": true,
	}


func _apply_mentor_lesson(npc: Unit, lesson: Dictionary) -> void:
	var key: String = String(lesson.get("topic_key", "")).strip_edges()
	if key.is_empty():
		return
	# 要在 BridgeKnowledge 里能找到这个 key 才算"学到"
	var topic: Dictionary = _BridgeKnowledgeScript.get_topic(key)
	if topic.is_empty():
		return
	if not _player_learned_topics.has(key):
		_player_learned_topics.append(key)
		Notify.notify(
			"向 %s 学到了「%s」" % [npc.unit_data.unit_name, topic.get("title", key)],
			Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 3.5
		)


# ─────────────────────────────────────────────
# 邻居插话 + 通用工具
# ─────────────────────────────────────────────

func _make_thinking_overlay() -> CanvasLayer:
	return _ThinkingOverlayScene.instantiate()


func _maybe_neighbor_interject(speaker: Unit, heard: String) -> void:
	if heard.is_empty():
		return
	if randf() >= NEIGHBOR_INTERJECT_PROB:
		return
	var neighbor: Unit = _pick_neighbor_for_interject(speaker)
	if neighbor == null:
		return
	var line_text: String = await _generate_neighbor_line(neighbor, speaker, heard)
	if line_text.is_empty():
		return
	await _play_npc_line(neighbor, line_text)


func _pick_neighbor_for_interject(speaker: Unit) -> Unit:
	var candidates: Array[Unit] = []
	for npc in _npcs:
		if not is_instance_valid(npc) or npc == speaker:
			continue
		if npc.combat_stats != null and not npc.combat_stats.is_alive():
			continue
		var d: Vector2i = npc.cell - speaker.cell
		if absi(d.x) + absi(d.y) <= NEIGHBOR_INTERJECT_RANGE:
			candidates.append(npc)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]


func _generate_neighbor_line(neighbor: Unit, speaker: Unit, heard: String) -> String:
	var persona: Dictionary = _NpcPersonasScript.get_persona(neighbor.unit_data.unit_id, neighbor.unit_data.camp)
	var sys: String = _ChatterPromptsScript.build_system_prompt(persona, "bridge_neighbor_interject", "（无）", "{}")
	var user: String = _ChatterPromptsScript.build_user_prompt(persona, "bridge_neighbor_interject", {
		"speaker_name": speaker.unit_data.unit_name,
		"heard": heard,
	})
	var resp: Dictionary = await _get_llm().chat_completion([
		{"role": "system", "content": sys},
		{"role": "user", "content": user},
	], {"max_tokens": 100, "temperature": 0.85})
	if not resp.get("ok", false):
		return ""
	return _strip_quotes(String(resp.get("text", ""))).strip_edges()


func _strip_quotes(s: String) -> String:
	var out := s.strip_edges()
	while out.length() > 1:
		var first := out[0]
		var last := out[out.length() - 1]
		if (first == "\"" and last == "\"") or (first == "「" and last == "」") or (first == "“" and last == "”"):
			out = out.substr(1, out.length() - 2).strip_edges()
		else:
			break
	return out


func _play_npc_line(npc: Unit, text: String, with_voice: bool = true) -> bool:
	if text.is_empty():
		return false
	var line := DialogueLine.create(
		npc.unit_data.unit_name,
		text,
		_PortraitResolverScript.get_portrait(npc),
		_PortraitResolverScript.side_for_unit(npc),
		_PortraitResolverScript.get_portrait_bg(npc),
	)
	var result: Dictionary
	if with_voice:
		_get_voice().speak(npc, text, "bridge_topic_answer")
		result = await play_chatter_lines([line], 2.0, _get_voice())
	else:
		result = await play_chatter_lines([line], 2.0)
	var was_skipped: bool = bool(result.get("was_skipped", false))
	if was_skipped and with_voice and _get_voice().is_streaming():
		_get_voice().cancel()
	return was_skipped


func _parse_object_json(text: String) -> Dictionary:
	var s := text.strip_edges()
	var l := s.find("{")
	var r := s.rfind("}")
	if l < 0 or r <= l:
		return {}
	var json_text := s.substr(l, r - l + 1)
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return {}
	return parsed


## 拼"已学知识"渲染给 LLM。空时给"（无）"。
func _learned_memo() -> String:
	if _player_learned_topics.is_empty():
		return "（玩家尚未学过任何桥梁知识）"
	var titles: Array[String] = []
	for k in _player_learned_topics:
		var topic := _BridgeKnowledgeScript.get_topic(k)
		if not topic.is_empty():
			titles.append(String(topic.get("title", k)))
	return "玩家已学知识：" + "、".join(titles)


func _learned_csv() -> String:
	if _player_learned_topics.is_empty():
		return "（无）"
	return ", ".join(_player_learned_topics)


# ─────────────────────────────────────────────
# 胜利 / 失败 / 移动
# ─────────────────────────────────────────────

func check_victory() -> bool:
	return _persuaded_count() >= PERSUADE_TARGET and _qa_solved_count() >= QA_TARGET


func check_defeat() -> String:
	return ""


func _persuaded_count() -> int:
	var n := 0
	for npc in _npcs:
		if is_instance_valid(npc) and String(npc.get_meta("npc_role", "")) == "persuade" \
				and bool(npc.get_meta("npc_persuaded", false)):
			n += 1
	return n


func _qa_solved_count() -> int:
	var n := 0
	for npc in _npcs:
		if is_instance_valid(npc) and String(npc.get_meta("npc_role", "")) == "qa" \
				and bool(npc.get_meta("npc_qa_solved", false)):
			n += 1
	return n


## 任一进度推进后调，达标就显胜利横幅 + complete_level。
func _check_all_done_for_victory() -> void:
	if _persuaded_count() >= PERSUADE_TARGET and _qa_solved_count() >= QA_TARGET:
		Notify.notify(
			"桥成在望！群众心服口服。",
			Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 5.0
		)
		_check_win_lose.call_deferred()


func _on_unit_moved() -> void:
	if hero != null and hero is Unit and (hero as Unit).combat_stats != null:
		var stats: CombatStats = (hero as Unit).combat_stats
		stats.ap_current = stats.ap_max
		(hero as Unit).refresh_overhead_bars()
