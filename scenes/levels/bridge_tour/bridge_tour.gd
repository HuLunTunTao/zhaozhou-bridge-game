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
const _VISUAL_OLD_OVERSEER := preload("res://scenes/unit/visual/human/老监工/老监工_visual.tscn")
const _VISUAL_SCHOLAR := preload("res://scenes/unit/visual/human/游学书生/游学书生_visual.tscn")
const _VISUAL_STONEMASON := preload("res://scenes/unit/visual/human/石匠/石匠_visual.tscn")
const _VISUAL_FISHERMAN := preload("res://scenes/unit/visual/human/渔夫/渔夫_visual.tscn")

const _RoamingAIScript := preload("res://scripts/npc/roaming_ai.gd")
const _NpcPersonasScript := preload("res://scripts/llm/npc_personas.gd")
const _PersonaFallbackScript := preload("res://scripts/llm/persona_fallback.gd")
const _ChatterPromptsScript := preload("res://scripts/llm/chatter_prompts.gd")
const _LLMClientScript := preload("res://scripts/llm/llm_client.gd")
const _ChatterVoiceScript := preload("res://scripts/tts/chatter_voice_adapter.gd")
const _StreamChunkerScript := preload("res://scripts/llm/stream_chunker.gd")
const _META_SENTINEL := "###META###"
const _PortraitResolverScript := preload("res://scripts/llm/portrait_resolver.gd")
const _BridgeKnowledgeScript := preload("res://scripts/data/bridge_knowledge.gd")
const _ArgumentInputPanelScene := preload("res://scenes/ui/argument_input_panel.tscn")
const _TopicMenuPanelScene := preload("res://scenes/ui/topic_menu_panel.tscn")
const _KnowledgePanelScene := preload("res://scenes/ui/knowledge_panel.tscn")
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

## 演示用作弊暗语：玩家输入只要包含其中任一短语，立即说服成功。
## LLM 仍会被告知玩家"言中要害"，给出贴角色口吻的惊叹回应——所以观众察觉不到这是作弊。
## 这些都是 4 字短语，不会自然出现在玩家正常论点里。
const _PERSUADE_CHEAT_PHRASES: Array[String] = [
	"鲁班托梦",   # 神匠显梦指点
	"洨水有灵",   # 本关河流神灵
	"天工开物",   # 引经据典（明代典籍名）
]

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
			"persuasion_goal": {
				"goal": "让老匠首承认单孔大跨不是弃祖法冒险，而是能替代旧制多孔桥的稳妥新法。",
				"objection": "他认定一道大拱跨洨河太险，只有祖上传下来的多孔小拱才可靠。",
				"success_claim": "说清扁拱如何缓坡成跨、二十八道并列券如何分力且便于修换，并指出旧制桥墩会堵水冲毁。",
				"hint": "可用「扁拱」「二十八道并列拱券」「旧制多孔小拱」回应他的守旧疑虑。",
				"required_topics": ["flat_arch", "parallel_rings", "old_method"],
				"bad_arguments": ["只说新法好看", "贬低老师傅", "空喊年轻人有胆量"],
			},
		},
		{
			"unit_id": "bridge_river_chief", "unit_name": "河工总管", "role": "persuade",
			"bridge_part": "桥台", "cell": Vector2i(-3, 1),
			"color": Color(0.4, 0.55, 0.7), "visual": _VISUAL_CRAFTSMAN,
			"stance": 40, "roam_mode": _RoamingAIScript.Mode.PATROL,
			"waypoints": [Vector2i(-3, 1), Vector2i(-3, 3), Vector2i(-5, 3), Vector2i(-5, 1)] as Array[Vector2i],
			"persuasion_goal": {
				"goal": "让河工总管相信新桥能经受汛期怒水，不会因单孔大跨而冲台毁桥。",
				"objection": "他担心洪水顶拱、堵水、淘空桥台，要求看到泄洪和基础的硬道理。",
				"success_claim": "说清敞肩小拱可分泄洪势、减轻桥身，本地青砂石桥台能承受扁拱水平推力。",
				"hint": "可用「敞肩拱」「桥台与基础」回应他的防汛疑虑。",
				"required_topics": ["open_spandrel", "abutment"],
				"bad_arguments": ["只保证不会出事", "回避汛期", "只谈桥面好走"],
			},
		},
		{
			"unit_id": "bridge_court_inspector", "unit_name": "朝廷视察官", "role": "persuade",
			"bridge_part": "桥面中心", "cell": Vector2i(1, -2),
			"color": Color(0.7, 0.55, 0.3), "visual": _VISUAL_CRAFTSMAN,
			"stance": 30, "roam_mode": _RoamingAIScript.Mode.PATROL,
			"waypoints": [Vector2i(1, -2), Vector2i(2, -2), Vector2i(2, -1), Vector2i(1, -1)] as Array[Vector2i],
			"persuasion_goal": {
				"goal": "让朝廷视察官认可新桥不是炫技，而是省工、省料、通商、可成政绩的稳当工程。",
				"objection": "他怕新法不可控，拖工期、耗钱粮，最后让官府背责。",
				"success_claim": "说清敞肩拱可减重省石、单孔大跨少建桥墩且利通行，并结合隋代统一度量衡与赵郡交通要冲说明政绩。",
				"hint": "可用「敞肩拱」「旧制多孔小拱」「时代背景」回应他的工期和政绩疑虑。",
				"required_topics": ["open_spandrel", "old_method", "sui_era"],
				"bad_arguments": ["只讲奇观名声", "不谈工期钱粮", "把风险推给朝廷"],
			},
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
			"color": Color(0.85, 0.85, 0.95), "visual": _VISUAL_SCHOLAR,
			"roam_mode": _RoamingAIScript.Mode.STATIONARY, "waypoints": [],
		},
		{
			"unit_id": "bridge_fisherman", "unit_name": "渔夫", "role": "qa",
			"bridge_part": "桥下河滩", "cell": Vector2i(0, 4),
			"color": Color(0.55, 0.7, 0.85), "visual": _VISUAL_FISHERMAN,
			"roam_mode": _RoamingAIScript.Mode.STATIONARY, "waypoints": [],
		},
		# ─── 求教类（2）───
		{
			"unit_id": "bridge_old_overseer", "unit_name": "老监工", "role": "mentor",
			"bridge_part": "桥头远处", "cell": Vector2i(5, -3),
			"color": Color(0.65, 0.55, 0.5), "visual": _VISUAL_OLD_OVERSEER,
			"roam_mode": _RoamingAIScript.Mode.STATIONARY, "waypoints": [],
			# 老监工偏全局：拱形 / 时代 / 旧制
			"mentor_topics": ["扁拱与半圆拱有何不同？", "为何在隋代建此奇桥？", "和旧制多孔小拱比，胜在哪？"],
		},
		{
			"unit_id": "bridge_old_stonemason", "unit_name": "老石匠", "role": "mentor",
			"bridge_part": "石作工棚", "cell": Vector2i(-2, -3),
			"color": Color(0.7, 0.65, 0.55), "visual": _VISUAL_STONEMASON,
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
		unit.set_meta("npc_persuasion_goal", spec.get("persuasion_goal", {}))
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
	var goal_raw: Variant = npc.get_meta("npc_persuasion_goal", {})
	var persuasion_goal: Dictionary = goal_raw if goal_raw is Dictionary else {}
	panel.set_persuasion_goal(persuasion_goal)
	panel.set_persuade_base_total(int(npc.get_meta("npc_persuade_base_total", 0)))
	panel.set_learned_topics(_player_learned_topics, _player_used_topics)
	panel.set_history(npc.get_meta("npc_dialogue_log", [] as Array[Dictionary]))
	var argument: String = await panel.argument_submitted
	if argument.is_empty():
		return
	var is_cheat: bool = _argument_has_cheat(argument)
	# 流式：LLM 一边吐 token、TTS bidi 一边播——首字音延迟 ≈ 0.5s。
	# 比之前的 thinking overlay + 等全文 + 一次性 TTS 体验快 1-2 秒。
	var ans: Dictionary = await _generate_persuade_answer(npc, argument, is_cheat)
	_apply_persuade_result(npc, ans)
	var reply: String = String(ans.get("reply", ""))
	var is_fallback: bool = bool(ans.get("is_fallback", false))
	var is_streaming: bool = bool(ans.get("is_streaming", false))
	# 记入对话历史；fallback 文本仍记（让玩家看到"NPC 没接到话"），但 LLM 失败那条
	# 后续不会被注入 prompt context（chatter_prompts.bridge_topic_answer 不读 dialogue_log）
	if not is_fallback:
		_append_dialogue_log(npc, argument, reply, String(ans.get("tone", "")))
	else:
		_append_dialogue_log(npc, argument, reply, "fallback")
	# 邻居插话与第一句话 dialog 显示并发：先 fire LLM，再开 dialog（TTS 已流式或现在播），最后等邻居完成
	var neighbor_spec := _start_neighbor_interject(npc, reply)
	await _play_npc_line(npc, reply, not is_fallback, is_streaming)
	await _play_pending_neighbor(neighbor_spec)


## 检测玩家输入是否包含演示用作弊暗语。命中即整轮强制通过。
func _argument_has_cheat(argument: String) -> bool:
	for phrase in _PERSUADE_CHEAT_PHRASES:
		if phrase in argument:
			return true
	return false


## LLM+TTS 一体化流式：LLM SSE token 一边到一边按 ###META### 分流——前半（reply 纯文本）
## 实时喂 TTS bidi 播放，后半 JSON 元数据收集到末尾解析。
##
## 期望 LLM 输出格式：
##     <reply 纯文本>
##     ###META###
##     {"key":val,...}
##
## 返回：{"ok": bool, "reply": String, "meta": Dictionary, "error": String}
##   - ok=false：LLM 启动失败 / 中途断流。reply / meta 仍可能有部分内容
##   - 没出现 sentinel：整段当 reply，meta 给 {}
##
## 流式失败兜底：调用方判断 ok/reply.is_empty() 再决定要不要回落到 _PersonaFallbackScript。
func _stream_llm_with_meta_split(unit: Unit, messages: Array, llm_opts: Dictionary, trigger_kind: String) -> Dictionary:
	var sentinel := _META_SENTINEL
	var chunker = _StreamChunkerScript.new(_StreamChunkerScript.Mode.MIXED)
	var has_tts: bool = await _get_voice().start_stream(unit, trigger_kind)
	if not has_tts:
		push_warning("[bridge_tour TTS] start_stream 失败 unit=%s trigger=%s" % [unit.unit_data.unit_id, trigger_kind])

	var done := [false]
	var ok_state := [true]
	var err_state := [""]
	var reply_collected := [""]   # 已 feed 给 TTS 的 reply 内容
	var meta_buffer := [""]       # sentinel 之后累积的 JSON 文本
	var pre_buf := [""]           # 还没决定 feed/丢弃的滑动窗口
	var sentinel_seen := [false]

	var feed_to_tts := func(piece: String) -> void:
		if piece.is_empty():
			return
		reply_collected[0] += piece
		if has_tts and _get_voice().is_stream_active():
			for c in chunker.push(piece):
				_get_voice().feed_stream(c)

	var on_chunk := func(text: String) -> void:
		if sentinel_seen[0]:
			meta_buffer[0] += text
			return
		pre_buf[0] += text
		var idx: int = pre_buf[0].find(sentinel)
		if idx >= 0:
			sentinel_seen[0] = true
			var pre: String = pre_buf[0].substr(0, idx)
			meta_buffer[0] = pre_buf[0].substr(idx + sentinel.length())
			pre_buf[0] = ""
			feed_to_tts.call(pre)
		else:
			# 还没看到 sentinel：feed 除最后 (sentinel.length()-1) 字符外的安全段
			# （万一末尾正在拼 sentinel 的前几个字符，留住别 feed）
			var safe_len: int = pre_buf[0].length() - sentinel.length() + 1
			if safe_len > 0:
				var safe_text: String = pre_buf[0].substr(0, safe_len)
				pre_buf[0] = pre_buf[0].substr(safe_len)
				feed_to_tts.call(safe_text)

	var on_finished := func(_full: String, ok: bool, err: String) -> void:
		ok_state[0] = ok
		err_state[0] = err
		# 收尾：如果整段都没出现 sentinel，pre_buf 里的内容都是 reply 尾巴
		if not sentinel_seen[0] and not pre_buf[0].is_empty():
			feed_to_tts.call(pre_buf[0])
			pre_buf[0] = ""
		if has_tts and _get_voice().is_stream_active():
			var tail: String = chunker.flush_remaining()
			if not tail.is_empty():
				_get_voice().feed_stream(tail)
			_get_voice().finish_stream()
		done[0] = true

	_get_llm().stream_chunk_received.connect(on_chunk)
	_get_llm().stream_finished.connect(on_finished, CONNECT_ONE_SHOT)
	var started: bool = _get_llm().stream_chat_completion(messages, llm_opts)
	if not started:
		push_warning("[bridge_tour LLM] stream_chat_completion 启动失败 unit=%s trigger=%s" % [unit.unit_data.unit_id, trigger_kind])
		if _get_llm().stream_chunk_received.is_connected(on_chunk):
			_get_llm().stream_chunk_received.disconnect(on_chunk)
		if _get_llm().stream_finished.is_connected(on_finished):
			_get_llm().stream_finished.disconnect(on_finished)
		if has_tts:
			_get_voice().cancel()
		return {"ok": false, "reply": "", "meta": {}, "error": "stream start failed"}

	while not done[0]:
		var tree := get_tree()
		if tree == null:
			break
		await tree.process_frame
	if _get_llm().stream_chunk_received.is_connected(on_chunk):
		_get_llm().stream_chunk_received.disconnect(on_chunk)

	if not ok_state[0]:
		push_warning("[bridge_tour LLM] stream 中断 unit=%s trigger=%s err=%s" % [unit.unit_data.unit_id, trigger_kind, err_state[0]])

	var meta_final: Dictionary = _parse_object_json(meta_buffer[0]) if sentinel_seen[0] else {}
	var reply_final: String = reply_collected[0].strip_edges()
	return {
		"ok": ok_state[0],
		"reply": reply_final,
		"meta": meta_final,
		"error": err_state[0],
	}


func _generate_persuade_answer(npc: Unit, topic: String, is_cheat: bool = false) -> Dictionary:
	var persona: Dictionary = _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var bridge_part: String = String(npc.get_meta("npc_bridge_part", ""))
	var stance: int = int(npc.get_meta("npc_stance", 50))
	var goal_raw: Variant = npc.get_meta("npc_persuasion_goal", {})
	var persuasion_goal: Dictionary = goal_raw if goal_raw is Dictionary else {}
	var sys: String = _ChatterPromptsScript.build_system_prompt(persona, "bridge_topic_answer", _dialogue_history_memo(npc), "{}")
	var user: String = _ChatterPromptsScript.build_user_prompt(persona, "bridge_topic_answer", {
		"topic": topic,
		"bridge_part": bridge_part,
		"stance": stance,
		"persuasion_goal": persuasion_goal,
		"learned_csv": _learned_csv(),
		"is_cheat": is_cheat,
	})
	var resp: Dictionary = await _stream_llm_with_meta_split(npc, [
		{"role": "system", "content": sys},
		{"role": "user", "content": user},
	], {"max_tokens": 280, "temperature": 0.85}, "bridge_topic_answer")
	var reply_text: String = String(resp.get("reply", "")).strip_edges()
	var meta: Dictionary = resp.get("meta", {})
	if resp.get("ok", false) and not reply_text.is_empty():
		# 只在 meta 真的解析成功时按字段填；否则给保底
		var parsed: Dictionary = {
			"reply": reply_text,
			"stance_delta": clampi(int(meta.get("stance_delta", 0)), -6, 18),
			"base_bonus": clampi(int(meta.get("base_bonus", 0)), 0, 5),
			"tone": String(meta.get("tone", "")),
			"knowledge_used": meta.get("knowledge_used", []),
			"matched_points": meta.get("matched_points", []),
			"missed_points": meta.get("missed_points", []),
			"is_cheat": is_cheat,
			"is_streaming": true,   # 让 _flow_persuade 知道 TTS 已经流式播了，dialog_box 不要重播
		}
		return parsed
	# LLM 失败也保留 cheat 通过：fallback 文本配合 + is_cheat 让 _apply_persuade_result 强制通过
	return {
		"reply": "（一时怔住，连连点头）" if is_cheat else _PersonaFallbackScript.pick(persona, "persuade"),
		"stance_delta": 0,
		"base_bonus": 0,
		"tone": "感动" if is_cheat else "沉默",
		"is_fallback": not is_cheat,
		"is_cheat": is_cheat,
	}


func _apply_persuade_result(npc: Unit, ans: Dictionary) -> void:
	var is_cheat: bool = bool(ans.get("is_cheat", false))
	var delta: int = clampi(int(ans.get("stance_delta", 0)), -6, 18)
	var bonus: int = clampi(int(ans.get("base_bonus", 0)), 0, 5)
	var old_stance: int = int(npc.get_meta("npc_stance", 50))
	# 实际加成 = LLM stance_delta + base_bonus（基础参与分）
	var combined_delta: int = delta + bonus
	var new_stance: int = clampi(old_stance + combined_delta, 0, 100)
	# Cheat 暗语命中：强制把 stance 推到通过线之上（即使 LLM 给了 0 或负分）
	if is_cheat:
		new_stance = maxi(new_stance, STANCE_PERSUADED)
	npc.set_meta("npc_stance", new_stance)
	# 累积基础分（每个 NPC 独立）
	var base_total: int = int(npc.get_meta("npc_persuade_base_total", 0)) + bonus
	npc.set_meta("npc_persuade_base_total", base_total)
	# LLM 引用过的知识 → 加入 used 集合，知识面板高亮
	for k in ans.get("knowledge_used", []):
		var key := String(k)
		if not key.is_empty() and not _player_used_topics.has(key):
			_player_used_topics.append(key)
	var was_persuaded: bool = bool(npc.get_meta("npc_persuaded", false))
	var now_persuaded: bool = new_stance >= STANCE_PERSUADED
	if not was_persuaded and now_persuaded:
		npc.set_meta("npc_persuaded", true)
		Notify.notify("已说服 %s（态度 +%d，含基础分 +%d）" % [npc.unit_data.unit_name, combined_delta, bonus], Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 3.0)
		_refresh_npc_icon(npc)
		_check_all_done_for_victory()
	elif combined_delta > 0:
		Notify.notify("%s：态度 +%d（含基础分 +%d，累计 %d）" % [npc.unit_data.unit_name, combined_delta, bonus, base_total], Notify.Position.TOP_RIGHT, Notify.Style.INFO, 2.5)
	elif combined_delta < 0:
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
	# 流式：LLM + TTS 一起推进
	var eval: Dictionary = await _generate_qa_eval(npc, question, answer)
	_apply_qa_result(npc, eval)
	var feedback: String = String(eval.get("feedback", ""))
	var is_fallback: bool = bool(eval.get("is_fallback", false))
	var is_streaming: bool = bool(eval.get("is_streaming", false))
	# 记入对话历史。问题用本轮抛出的 question + 玩家答案 + NPC feedback 三段拼接：
	# 历史每条记 player（玩家答案）/ npc（feedback），question 在显示时上下文已隐含。
	_append_dialogue_log(npc, answer, feedback, "fallback" if is_fallback else "qa")
	# 邻居插话与 feedback 显示并发：先 fire LLM，再开 dialog，最后等邻居完成
	var neighbor_spec := _start_neighbor_interject(npc, feedback)
	await _play_npc_line(npc, feedback, not is_fallback, is_streaming)
	await _play_pending_neighbor(neighbor_spec)


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
	var sys: String = _ChatterPromptsScript.build_system_prompt(persona, "bridge_qa_eval", _dialogue_history_memo(npc), "{}")
	var user: String = _ChatterPromptsScript.build_user_prompt(persona, "bridge_qa_eval", {
		"question": question,
		"answer": answer,
		"learned_csv": _learned_csv(),
	})
	var resp: Dictionary = await _stream_llm_with_meta_split(npc, [
		{"role": "system", "content": sys},
		{"role": "user", "content": user},
	], {"max_tokens": 280, "temperature": 0.7}, "bridge_qa_eval")
	var feedback_text: String = String(resp.get("reply", "")).strip_edges()
	var meta: Dictionary = resp.get("meta", {})
	if resp.get("ok", false) and not feedback_text.is_empty():
		return {
			"feedback": feedback_text,
			"is_correct": bool(meta.get("is_correct", false)),
			"knowledge_used": meta.get("knowledge_used", []),
			"is_streaming": true,
		}
	return {
		"is_correct": false,
		"feedback": _PersonaFallbackScript.pick(persona, "qa"),
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
	# 流式：LLM + TTS 一起推进
	var lesson: Dictionary = await _generate_mentor_lesson(npc, query)
	_apply_mentor_lesson(npc, lesson)
	var with_voice: bool = not bool(lesson.get("is_fallback", false))
	var is_streaming: bool = bool(lesson.get("is_streaming", false))
	await _play_npc_line(npc, String(lesson.get("reply", "")), with_voice, is_streaming)


func _generate_mentor_lesson(npc: Unit, query: String) -> Dictionary:
	var persona: Dictionary = _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var sys: String = _ChatterPromptsScript.build_system_prompt(persona, "bridge_knowledge_explain", _dialogue_history_memo(npc), "{}")
	var user: String = _ChatterPromptsScript.build_user_prompt(persona, "bridge_knowledge_explain", {
		"query": query,
		"topics_csv": _BridgeKnowledgeScript.key_to_title_csv(),
	})
	var resp: Dictionary = await _stream_llm_with_meta_split(npc, [
		{"role": "system", "content": sys},
		{"role": "user", "content": user},
	], {"max_tokens": 320, "temperature": 0.7}, "bridge_knowledge_explain")
	var reply_text: String = String(resp.get("reply", "")).strip_edges()
	var meta: Dictionary = resp.get("meta", {})
	if resp.get("ok", false) and not reply_text.is_empty():
		return {
			"reply": reply_text,
			"topic_key": String(meta.get("topic_key", "")),
			"is_streaming": true,
		}
	return {
		"reply": _PersonaFallbackScript.pick(persona, "mentor"),
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

func _maybe_neighbor_interject(speaker: Unit, heard: String) -> void:
	# 旧入口（同步：先 LLM 后播）。新代码请用 _start_neighbor_interject + _play_pending_neighbor，
	# 把 LLM 与第一句话播放并发，省 1~2 秒等待。这里保留以便兼容。
	var spec := _start_neighbor_interject(speaker, heard)
	await _play_pending_neighbor(spec)


## 在第一句话播放前调用。立即决定是否要邻居插话；如果要，立刻 fire-and-forget 跑邻居 LLM。
## 返回 spec dict 给 _play_pending_neighbor 用：{neighbor: Unit?, pending: {done, text}}。
## 这样 LLM 调用与第一句 TTS 播放并发，第一句结束时邻居台词通常已生成完。
func _start_neighbor_interject(speaker: Unit, heard: String) -> Dictionary:
	var spec: Dictionary = {"neighbor": null, "pending": {"done": false, "text": ""}}
	if heard.is_empty():
		return spec
	if randf() >= NEIGHBOR_INTERJECT_PROB:
		return spec
	var neighbor: Unit = _pick_neighbor_for_interject(speaker)
	if neighbor == null:
		return spec
	spec["neighbor"] = neighbor
	_spawn_neighbor_gen_async(neighbor, speaker, heard, spec["pending"])  # fire-and-forget
	return spec


## 配套 _start_neighbor_interject：第一句话播完后调，等邻居 LLM 收尾再播邻居台词。
func _play_pending_neighbor(spec: Dictionary) -> void:
	var neighbor: Variant = spec.get("neighbor")
	if neighbor == null:
		return
	var pending: Dictionary = spec.get("pending", {})
	while not bool(pending.get("done", false)):
		var tree := get_tree()
		if tree == null:
			break
		await tree.process_frame
	var text: String = String(pending.get("text", "")).strip_edges()
	if text.is_empty():
		return
	await _play_npc_line(neighbor as Unit, text)


## fire-and-forget 协程：跑邻居 LLM，把结果写到 out["text"]，设 out["done"] = true。
func _spawn_neighbor_gen_async(neighbor: Unit, speaker: Unit, heard: String, out: Dictionary) -> void:
	var t: String = await _generate_neighbor_line(neighbor, speaker, heard)
	out["text"] = t
	out["done"] = true


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
		push_warning("[bridge_tour LLM] neighbor 调用失败 unit=%s code=%s err=%s" % [neighbor.unit_data.unit_id, resp.get("code", "?"), resp.get("error", "?")])
		# LLM 失败 → 用 PersonaFallback 抽 neighbor 变体；空字符串则维持跳过插话
		return _PersonaFallbackScript.pick(persona, "neighbor").strip_edges()
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


## 三种播放模式：
##   - 默认 (with_voice=true)：调 _voice.speak 一次性 TTS，dialog_box 等 voice 收尾
##   - with_voice=false：fallback 路径，优先 pre-baked MP3，否则降级 OS TTS
##   - tts_already_streamed=true：TTS 已通过 _stream_llm_with_meta_split 流式播过/正在播，
##     dialog_box 只显示文字 + 用 _voice 句柄等流式收尾，**不再调 speak**
func _play_npc_line(npc: Unit, text: String, with_voice: bool = true, tts_already_streamed: bool = false) -> bool:
	if text.is_empty():
		return false
	# is_fallback=true 时（with_voice=false）跳过火山 TTS，但优先注入 pre-baked
	# AudioStreamMP3 让 dialogue_box 自己播——这样 fallback 文本仍能听到 NPC 自己音色。
	var pre_baked: AudioStream = null
	if not with_voice and not tts_already_streamed:
		pre_baked = TtsFallbackIndex.get_fallback_audio(npc.unit_data.unit_id, text)
	var line := DialogueLine.create(
		npc.unit_data.unit_name,
		text,
		_PortraitResolverScript.get_portrait(npc),
		_PortraitResolverScript.side_for_unit(npc),
		_PortraitResolverScript.get_portrait_bg(npc),
		pre_baked,
	)
	var result: Dictionary
	if tts_already_streamed:
		# TTS 已在流式播放；dialog_box 通过 voice handle 等 streaming_done 自然收尾
		result = await play_chatter_lines([line], 2.0, _get_voice())
	elif with_voice:
		_get_voice().speak(npc, text, "bridge_topic_answer")
		result = await play_chatter_lines([line], 2.0, _get_voice())
	else:
		result = await play_chatter_lines([line], 2.0)
	var was_skipped: bool = bool(result.get("was_skipped", false))
	if was_skipped and (with_voice or tts_already_streamed) and _get_voice().is_streaming():
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


## 把该 NPC 与玩家的完整对话历史拼成 LLM 可读文本，用于 system prompt 的"最近你说过/听到的话"槽位。
## 让 LLM 记得之前几轮聊过什么，回答更连贯。空 log 返回"（首次见面）"。
func _dialogue_history_memo(npc: Unit) -> String:
	var entries: Array = npc.get_meta("npc_dialogue_log", [] as Array[Dictionary])
	if entries.is_empty():
		return "（首次见面，没有过往对话）"
	var lines: Array[String] = []
	for entry_v in entries:
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v
		var player_text: String = String(entry.get("player", "")).strip_edges()
		var npc_text: String = String(entry.get("npc", "")).strip_edges()
		if not player_text.is_empty():
			lines.append("李春：" + player_text)
		if not npc_text.is_empty():
			lines.append("你：" + npc_text)
	if lines.is_empty():
		return "（首次见面，没有过往对话）"
	return "你和李春之前的全部对话（最早→最近，共 %d 轮）：\n%s" % [entries.size(), "\n".join(lines)]


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
