class_name BridgeTourLevel
extends BaseLevel
## 验桥日 · LLM Agent 关卡。
##
## 9 个 NPC 三种 role：
##   persuade（蓝？）：李春自由打字 → LLM 评累积分+本轮评分，进度>=70 视为说服
##   qa（绿？）：NPC 抛预设问题 → 李春答 → LLM 判 is_correct，对则视为解答
##   mentor（黄！）：李春从主题菜单选一项 → LLM 用对应史实讲解，topic_key 记入"已学"
##
## 已学知识注入 persuade / qa 的 prompt context，让 LLM 倾向给"用上知识的回答"更高分。
## 胜利条件：说服 3/3 + 解答 4/4 全完成。

# ── 资源 ──
const _UD_LI_CHUN := preload("res://data/units/hero_li_chun.tres")
const _UD_NPC_TEMPLATE := preload("res://data/units/craftsman_guard.tres")
const _SK_INTERACT := preload("res://data/skills/bridge_tour_interact.tres")
const _VISUAL_LI_CHUN := preload("res://scenes/unit/visual/human/li_chun/li_chun_visual.tscn")

const _NpcSpecLibraryScript := preload("res://scenes/levels/bridge_tour/npc_spec_library.gd")
const _NpcPersonasScript := preload("res://scripts/llm/npc_personas.gd")
const _PersonaFallbackScript := preload("res://scripts/llm/persona_fallback.gd")
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
const PERSUADE_ACCUM_SCORE_MIN := 6
const PERSUADE_ACCUM_SCORE_MAX := 15
const PERSUADE_ROUND_SCORE_MIN := -10
const PERSUADE_ROUND_SCORE_MAX := 15
const PERSUADE_TARGET := 3
const QA_TARGET := 4
const NEIGHBOR_INTERJECT_PROB := 0.4
const NEIGHBOR_INTERJECT_RANGE := 5
const HERO_INFINITE_AP := 99999
const HERO_MOVE_PREVIEW_AP_BUDGET := 120 # 验桥日移动范围预览上限，避免无限 AP 把整张图 overlay 算出来
## 演示用作弊暗语：玩家输入只要包含其中任一短语，目标 NPC 任务立即通过。
## LLM 仍会被告知玩家"言中要害"，给出贴角色口吻的惊叹回应——所以观众察觉不到这是作弊。
## 这些都是 4 字短语，不会自然出现在玩家正常论点里。
const CHEAT_WORDS: Array[String] = [
	"鲁班托梦",   # 神匠显梦指点
	"墨线自明",   # 工匠墨线自行显准
	"石龙点头",   # 桥石似有灵应
	"洨水有灵",   # 本关河流神灵
	"天工开物",   # 引经据典（明代典籍名）
]

# ── 状态 ──
var _npcs: Array[Unit] = []
var _spawner: NpcSpawner = null
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
	var hero_unit := _get_static_unit("Player")
	var npc_units: Array[Unit] = []
	for spec in _NpcSpecLibraryScript.get_specs():
		var npc := _get_static_unit(String(spec.get("node_name", "")))
		if npc != null:
			npc_units.append(npc)
	return [
		{"name": "玩家", "faction": "好人", "controller": "player", "units": [hero_unit] if hero_unit != null else []},
		{"name": "桥上众人", "faction": "好人", "controller": "ai", "units": npc_units},
	]


func _get_static_unit(node_name: String) -> Unit:
	if node_name.is_empty() or not has_node("Entities/Units/%s" % node_name):
		return null
	return get_node("Entities/Units/%s" % node_name) as Unit


func get_objectives_text() -> Dictionary:
	# 进入时显示 BRIEFING——和别的关卡一样
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


## 移动占位守卫：自由移动模式下，玩家点击的目标格在"NPC 边漫游边变格"过程中
## 可能从空变占。range overlay 是 show_range_ap 时刻的快照，无法实时刷新。
## 此处在 confirm 路径加最后一道闸：占用就拒绝并提示，不让李春叠到 NPC 头上。
## TARGETING_SKILL（交互 NPC）不在此守卫范围——那条路径就是要点 NPC 的格。
func confirm_cell(cell: Vector2i) -> void:
	if _input_state == InputState.IDLE or _input_state == InputState.UNIT_SELECTED:
		if _is_cell_occupied_by_other(cell, hero):
			Notify.warn("目标格已被占用", 1.5)
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
	# 角色位置在 tscn 中静态摆放；脚本只补运行时数据、技能、AI 与头顶姓名牌。
	var li_chun := _get_team_unit(0, 0)
	if li_chun == null:
		push_error("BridgeTour: missing static hero unit at Entities/Units/Player")
		return
	var hero_visual := li_chun.visual_scene if li_chun.visual_scene != null else _VISUAL_LI_CHUN
	li_chun.apply_runtime_setup(_UD_LI_CHUN, hero_visual, _HERO_COLOR)
	setup_unit_stats(li_chun, "李春", 130, 24, HERO_INFINITE_AP, 6, Enums.Element.NONE, 0, true)
	hero = li_chun
	set_unit_skills(li_chun, [_SK_INTERACT])
	li_chun.set_overhead_name_label("李春", _HERO_COLOR)
	# 初始化 tscn 静态摆放的 NPC。
	_npcs.clear()
	_spawner = NpcSpawner.new()
	_spawner.setup(self, _UD_NPC_TEMPLATE, _refresh_npc_name_label)
	var npc_specs := _NpcSpecLibraryScript.get_specs()
	for spec in npc_specs:
		var npc := _spawner.spawn(spec)
		if npc != null:
			_npcs.append(npc)
	# Mission HUD（左上）
	_mission_hud = _MissionHudScene.instantiate()
	add_child(_mission_hud)
	_mission_hud.set_targets(PERSUADE_TARGET, QA_TARGET)
	for npc in _npcs:
		var st := _npc_state(npc)
		var done: bool = _npc_state(npc).is_done()
		_mission_hud.add_npc(st.role, npc.unit_data.unit_name, done)
		# persuade NPC 显示初始 stance；qa / mentor 静默忽略
		if st.role == "persuade":
			_mission_hud.update_npc_stance(npc.unit_data.unit_name, st.stance, STANCE_PERSUADED)

	# 自由移动模式不走 _init_turn_system，但 _can_accept_command 仍要 _waiting_for_player_input=true
	_waiting_for_player_input = true
	current_team_index = 0
	_select_hero_silently()


func _get_team_unit(team_idx: int, unit_idx: int) -> Unit:
	if team_idx < 0 or team_idx >= teams.size():
		return null
	var team: TeamData = teams[team_idx]
	if unit_idx < 0 or unit_idx >= team.units.size():
		return null
	return team.units[unit_idx] as Unit


func _find_team_unit_by_node_name(team_idx: int, node_name: String) -> Unit:
	if team_idx < 0 or team_idx >= teams.size():
		return null
	var team: TeamData = teams[team_idx]
	for unit in team.units:
		if is_instance_valid(unit) and unit is Unit and unit.name == node_name:
			return unit as Unit
	return null


func _select_hero_silently() -> void:
	if hero == null or not (hero is Unit):
		return
	selected_unit = hero
	unit_selected = true
	_input_state = InputState.IDLE
	_update_status_bar_for_unit(hero, false)
	selection_changed.emit(hero)


func _enter_targeting_move() -> void:
	if selected_unit == null:
		return
	_input_state = InputState.TARGETING_MOVE
	var unit := selected_unit
	if unit is Unit and unit.combat_stats != null:
		var stats: CombatStats = unit.combat_stats
		if not stats.can_move():
			return
		var friendly: Array[Vector2i] = _get_friendly_cells_except(unit)
		var enemy: Array[Vector2i] = _get_enemy_cells_except(unit)
		var effective_cost := stats.move_cost_per_tile + stats.get_move_ap_modifier()
		var preview_budget := stats.ap_current
		if unit == hero:
			preview_budget = mini(preview_budget, HERO_MOVE_PREVIEW_AP_BUDGET)
		move_overlay.show_range_ap(tilemap, movement_manager, unit.cell, preview_budget, effective_cost, friendly, enemy)
	else:
		move_overlay.show_range(tilemap, movement_manager, unit.cell, unit.movement_points)


## 读取 NPC 的类型化社交状态（挂在 unit.set_meta(NpcSocialState.META_KEY) 上）。
func _npc_state(npc: Unit) -> NpcSocialState:
	return npc.get_meta(NpcSocialState.META_KEY, null) as NpcSocialState


## 头顶姓名牌：role + 完成态决定颜色，替代 HP/AP 条。
func _refresh_npc_name_label(unit: Unit) -> void:
	NpcBadgePresenter.refresh(unit, _npc_state(unit))


func get_interaction_target() -> Unit:
	return _interaction_target


# ─────────────────────────────────────────────
# 顶栏"桥梁知识"按钮 + 知识面板
# ─────────────────────────────────────────────


func _open_knowledge_panel() -> void:
	if has_overlay():
		return
	var panel: Node = _KnowledgePanelScene.instantiate()
	if not _open_overlay(ActiveOverlay.KNOWLEDGE, panel, &"closed"):
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
	match _npc_state(npc).role:
		"persuade":
			var flow := PersuadeFlow.new()
			flow.setup(self)
			await flow.run(npc)
		"qa":
			await _flow_qa(npc)
		"mentor":
			var flow := MentorFlow.new()
			flow.setup(self)
			await flow.run(npc)


# ─────────────────────────────────────────────
# Flow 1：说服 — 流程骨架见 PersuadeFlow；LLM 生成与 apply 暂留此（2.16 再抽）
# ─────────────────────────────────────────────

func _pick_persuade_opening(npc: Unit) -> String:
	var persona: Dictionary = _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var fallback_lines: Variant = persona.get("fallback_lines", {})
	var openings: Array = []
	if fallback_lines is Dictionary:
		var raw: Variant = (fallback_lines as Dictionary).get("persuade_opening", [])
		if raw is Array:
			openings = raw
	if openings.is_empty():
		var goal: Dictionary = _npc_state(npc).persuasion_goal
		return String(goal.get("objection", "")).strip_edges()
	var st := _npc_state(npc)
	var attempt: int = st.persuade_opening_attempt
	st.persuade_opening_attempt = attempt + 1
	return String(openings[attempt % openings.size()]).strip_edges()


## 检测玩家输入是否包含演示用作弊暗语。命中即整轮强制通过。
func _argument_has_cheat(argument: String) -> bool:
	return _is_cheat_text(argument)


func _generate_persuade_answer(npc: Unit, topic: String) -> Dictionary:
	var cheat_word := _matched_cheat_word(topic)
	var is_cheat := not cheat_word.is_empty()
	var persona: Dictionary = _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var st := _npc_state(npc)
	var bridge_part: String = st.bridge_part
	var stance: int = st.stance
	var persuasion_goal: Dictionary = st.persuasion_goal
	var sys: String = _ChatterPromptsScript.build_system_prompt(
		persona,
		"bridge_topic_answer",
		_build_npc_memory_memo(npc),
		_build_bridge_context_json(npc, "persuade")
	)
	var user: String = _ChatterPromptsScript.build_user_prompt(persona, "bridge_topic_answer", {
		"topic": topic,
		"bridge_part": bridge_part,
		"stance": stance,
		"persuasion_goal": persuasion_goal,
		"learned_csv": _learned_csv(),
		"learned_details": _learned_details_text(),
		"dialogue_history": _dialogue_history_text(npc),
		"mission_context": _mission_context_text(npc),
		"cheat_context": _cheat_context_text(is_cheat, cheat_word),
		"accum_total": st.accum_score_total,
		"persuade_key_points": _persuade_key_points_text(persuasion_goal),
	})
	var resp: Dictionary = await _get_llm().chat_completion([
		{"role": "system", "content": sys},
		{"role": "user", "content": user},
	], {"max_tokens": 260, "temperature": 0.85})
	if resp.get("ok", false):
		var parsed := _parse_object_json(String(resp.get("text", "")))
		if not parsed.is_empty() and parsed.has("reply"):
			if is_cheat:
				parsed["accum_score"] = PERSUADE_ACCUM_SCORE_MAX
				parsed["round_score"] = PERSUADE_ROUND_SCORE_MAX
				parsed["final_score"] = PERSUADE_ACCUM_SCORE_MAX + PERSUADE_ROUND_SCORE_MAX
				parsed["force_success"] = true
				parsed["is_cheat"] = true
			else:
				_normalize_persuade_scores(parsed)
			if not parsed.has("tone"): parsed["tone"] = ""
			if not parsed.has("knowledge_used"): parsed["knowledge_used"] = []
			if not parsed.has("matched_points"): parsed["matched_points"] = []
			if not parsed.has("missed_points"): parsed["missed_points"] = []
			return parsed
	if is_cheat:
		return _make_cheat_persuade_answer(npc)
	return _make_rule_persuade_answer(npc, topic, persona, persuasion_goal)


func _apply_persuade_result(npc: Unit, ans: Dictionary) -> void:
	var force_success: bool = bool(ans.get("force_success", false))
	if not ans.has("final_score"):
		_normalize_persuade_scores(ans)
	var accum_score: int = clampi(int(ans.get("accum_score", PERSUADE_ACCUM_SCORE_MIN)), PERSUADE_ACCUM_SCORE_MIN, PERSUADE_ACCUM_SCORE_MAX)
	var round_score: int = clampi(int(ans.get("round_score", 0)), PERSUADE_ROUND_SCORE_MIN, PERSUADE_ROUND_SCORE_MAX)
	var final_score: int = int(ans.get("final_score", accum_score + round_score))
	if bool(ans.get("is_fallback", false)) and not force_success and not bool(ans.get("allow_fallback_score", false)):
		accum_score = 0
		round_score = 0
		final_score = 0
	var st := _npc_state(npc)
	var old_stance: int = st.stance
	var new_stance: int = STANCE_PERSUADED if force_success else clampi(old_stance + final_score, 0, 100)
	st.stance = new_stance
	var accum_total: int = st.accum_score_total + accum_score
	st.accum_score_total = accum_total
	st.last_accum_score = accum_score
	st.last_round_score = round_score
	st.last_final_score = final_score
	# LLM 引用过的知识 → 加入 used 集合，知识面板高亮
	for k in ans.get("knowledge_used", []):
		var key := String(k)
		if not key.is_empty() and not _player_used_topics.has(key):
			_player_used_topics.append(key)
	var was_persuaded: bool = st.persuaded
	var now_persuaded: bool = new_stance >= STANCE_PERSUADED
	if not was_persuaded and now_persuaded:
		st.persuaded = true
		Notify.notify("已说服 %s" % npc.unit_data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 3.0)
		_refresh_npc_name_label(npc)
		_check_all_done_for_victory()
	elif final_score < 0:
		Notify.warn("%s 摇头：「此说不通」" % npc.unit_data.unit_name)
	if _mission_hud:
		_mission_hud.update_npc("persuade", npc.unit_data.unit_name, now_persuaded)
		_mission_hud.update_npc_stance(npc.unit_data.unit_name, new_stance, STANCE_PERSUADED, accum_total, accum_score, round_score, final_score)


func _normalize_persuade_scores(ans: Dictionary) -> void:
	var accum_score: int
	if ans.has("accum_score"):
		accum_score = int(ans.get("accum_score", PERSUADE_ACCUM_SCORE_MIN))
	elif ans.has("cumulative_score"):
		accum_score = int(ans.get("cumulative_score", PERSUADE_ACCUM_SCORE_MIN))
	else:
		accum_score = PERSUADE_ACCUM_SCORE_MIN
	accum_score = clampi(accum_score, PERSUADE_ACCUM_SCORE_MIN, PERSUADE_ACCUM_SCORE_MAX)
	var round_score: int
	if ans.has("round_score"):
		round_score = int(ans.get("round_score", 0))
	elif ans.has("stance_delta"):
		round_score = int(ans.get("stance_delta", 0))
	else:
		round_score = 0
	round_score = clampi(round_score, PERSUADE_ROUND_SCORE_MIN, PERSUADE_ROUND_SCORE_MAX)
	ans["accum_score"] = accum_score
	ans["round_score"] = round_score
	ans["final_score"] = accum_score + round_score


# ─────────────────────────────────────────────
# Flow 2：解答（NPC 抛预设问题 → 玩家答 → LLM 判对错）
# ─────────────────────────────────────────────

func _flow_qa(npc: Unit) -> void:
	if _npc_state(npc).is_done():
		Notify.info("%s 的疑问已解" % npc.unit_data.unit_name, 1.5)
		return
	var st := _npc_state(npc)
	var bridge_part: String = st.bridge_part
	var question: String = _pick_qa_question(npc)
	# 先让 NPC 把问题抛给玩家——dialogue_box 显示 + TTS
	await _play_npc_line(npc, question, true)
	# 玩家输入答案；副标题用 NPC 名 + 桥部位
	var panel: Node = _ArgumentInputPanelScene.instantiate()
	add_child(panel)
	panel.show_for(npc.unit_data.unit_name, "%s · 「%s」" % [bridge_part, question])
	panel.set_learned_topics(_player_learned_topics, _player_used_topics)
	panel.set_history(_history_with_npc_prompt(npc, question))
	var answer: String = await panel.argument_submitted
	if answer.is_empty():
		return
	var thinking := _show_thinking("%s 正在判断……" % npc.unit_data.unit_name)
	var eval: Dictionary = await _generate_qa_eval(npc, question, answer)
	_hide_thinking(thinking)
	_apply_qa_result(npc, eval)
	var feedback: String = String(eval.get("feedback", ""))
	var is_fallback: bool = bool(eval.get("is_fallback", false))
	# 记入对话历史。问题用本轮抛出的 question + 玩家答案 + NPC feedback 三段拼接：
	# 历史每条同时保存 question，避免下次打开面板时丢掉 NPC 上轮问句。
	_append_dialogue_log(npc, answer, feedback, "fallback" if is_fallback else "qa", question)
	var neighbor_spec := _start_neighbor_interject(npc, feedback)
	await _play_npc_line(npc, feedback, not is_fallback)
	await _play_pending_neighbor(neighbor_spec)


## 把一轮交互写入 NPC 的 dialogue_log meta。供 set_history 显示给玩家看。
## question 只在 QA 流程传入，用于在玩家答案前恢复 NPC 的提问。
## tone 字段可记 "fallback" / "qa" / LLM 给的 tone 标签，便于将来分类（当前未做特殊渲染）。
func _append_dialogue_log(npc: Unit, player: String, npc_text: String, tone: String, question: String = "") -> void:
	var st := _npc_state(npc)
	var history: Array = st.dialogue_log
	var entry := {
		"player": player,
		"npc": npc_text,
		"npc_name": npc.unit_data.unit_name,
		"tone": tone,
	}
	if not question.strip_edges().is_empty():
		entry["question"] = question.strip_edges()
	history.append(entry)
	st.dialogue_log = history


## 给输入面板显示"当前 NPC 刚问的话"，但不立即写入持久历史；
## 玩家取消时不会留下半截对话，提交后由 _append_dialogue_log 保存完整问答。
func _history_with_npc_prompt(npc: Unit, prompt_text: String) -> Array:
	var history: Array = _npc_state(npc).dialogue_log.duplicate()
	var clean_prompt := prompt_text.strip_edges()
	if clean_prompt.is_empty():
		return history
	history.append({
		"npc": clean_prompt,
		"npc_name": npc.unit_data.unit_name,
		"tone": "question_preview",
	})
	return history


## 取一句 QA 问题。优先用 persona.qa_questions 数组按尝试次数轮换；空时 fallback 到旧
## qa_question 单字段；再空 fallback 到 spawn 时存的 state.qa_question；最终兜底固定句。
## 选完后 state.qa_attempt += 1 写回，供下次轮换。
func _pick_qa_question(npc: Unit) -> String:
	var persona: Dictionary = _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var st := _npc_state(npc)
	var attempt: int = st.qa_attempt
	var qs_raw: Variant = persona.get("qa_questions", [])
	var qs: Array = qs_raw if qs_raw is Array else []
	var picked: String = ""
	if not qs.is_empty():
		picked = String(qs[attempt % qs.size()])
	else:
		picked = String(persona.get("qa_question", ""))
	if picked.is_empty():
		picked = st.qa_question if not st.qa_question.is_empty() else "我有一事相问，可解么？"
	st.qa_attempt = attempt + 1
	return picked


func _generate_qa_eval(npc: Unit, question: String, answer: String) -> Dictionary:
	var cheat_word := _matched_cheat_word(answer)
	var is_cheat := not cheat_word.is_empty()
	var persona: Dictionary = _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var sys: String = _ChatterPromptsScript.build_system_prompt(
		persona,
		"bridge_qa_eval",
		_build_npc_memory_memo(npc),
		_build_bridge_context_json(npc, "qa")
	)
	var user: String = _ChatterPromptsScript.build_user_prompt(persona, "bridge_qa_eval", {
		"question": question,
		"answer": answer,
		"learned_csv": _learned_csv(),
		"learned_details": _learned_details_text(),
		"dialogue_history": _dialogue_history_text(npc),
		"mission_context": _mission_context_text(npc),
		"cheat_context": _cheat_context_text(is_cheat, cheat_word),
		"qa_key_points": _qa_key_points_text(npc),
	})
	var resp: Dictionary = await _get_llm().chat_completion([
		{"role": "system", "content": sys},
		{"role": "user", "content": user},
	], {"max_tokens": 240, "temperature": 0.7})
	if resp.get("ok", false):
		var parsed := _parse_object_json(String(resp.get("text", "")))
		if not parsed.is_empty() and parsed.has("feedback"):
			if is_cheat:
				parsed["is_correct"] = true
				parsed["is_cheat"] = true
			elif not parsed.has("is_correct"):
				parsed["is_correct"] = false
			if not parsed.has("knowledge_used"): parsed["knowledge_used"] = []
			return parsed
	if is_cheat:
		return _make_cheat_qa_eval(npc)
	return _make_rule_qa_eval(npc, answer, persona)


func _apply_qa_result(npc: Unit, eval: Dictionary) -> void:
	for k in eval.get("knowledge_used", []):
		var key := String(k)
		if not key.is_empty() and not _player_used_topics.has(key):
			_player_used_topics.append(key)
	var is_correct: bool = bool(eval.get("is_correct", false))
	if is_correct and not _npc_state(npc).qa_solved:
		_npc_state(npc).qa_solved = true
		Notify.notify("已解答 %s 的疑问" % npc.unit_data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 3.0)
		_refresh_npc_name_label(npc)
		_check_all_done_for_victory()
	elif not is_correct:
		Notify.warn("%s 摇头：尚有疑虑" % npc.unit_data.unit_name)
	if _mission_hud:
		_mission_hud.update_npc("qa", npc.unit_data.unit_name, is_correct)


func _is_cheat_text(text: String) -> bool:
	return not _matched_cheat_word(text).is_empty()


func _matched_cheat_word(text: String) -> String:
	var normalized := text.strip_edges().to_lower()
	if normalized.is_empty():
		return ""
	for word in CHEAT_WORDS:
		var clean_word := String(word).strip_edges()
		var normalized_word := clean_word.to_lower()
		if not normalized_word.is_empty() and normalized.find(normalized_word) >= 0:
			return clean_word
	return ""


func _make_cheat_persuade_answer(_npc: Unit) -> Dictionary:
	return {
		"reply": "鲁班既示梦，我便信你。",
		"accum_score": PERSUADE_ACCUM_SCORE_MAX,
		"round_score": PERSUADE_ROUND_SCORE_MAX,
		"final_score": PERSUADE_ACCUM_SCORE_MAX + PERSUADE_ROUND_SCORE_MAX,
		"tone": "信服",
		"knowledge_used": [],
		"matched_points": ["工匠暗语"],
		"missed_points": [],
		"force_success": true,
		"is_cheat": true,
	}


func _make_rule_persuade_answer(npc: Unit, argument: String, persona: Dictionary, persuasion_goal: Dictionary) -> Dictionary:
	var key_points: Array = _get_dict_array(persuasion_goal, "key_points")
	var matched: Array[String] = []
	var missed: Array[String] = []
	var knowledge_used: Array[String] = []
	for point_v in key_points:
		if not (point_v is Dictionary):
			continue
		var point: Dictionary = point_v
		var label := String(point.get("label", "")).strip_edges()
		if label.is_empty():
			continue
		if _key_point_matches(argument, point):
			matched.append(label)
			var keys: Array = _get_dict_array(point, "knowledge_keys")
			for key_v in keys:
				var key := String(key_v).strip_edges()
				if not key.is_empty() and not knowledge_used.has(key):
					knowledge_used.append(key)
		else:
			missed.append(label)
	var matched_count := matched.size()
	var has_progress := matched_count > 0
	var accum_score := 0
	var round_score := 0
	if has_progress:
		accum_score = clampi(10 + matched_count * 2, PERSUADE_ACCUM_SCORE_MIN, PERSUADE_ACCUM_SCORE_MAX)
		round_score = clampi(5 + matched_count * 4, PERSUADE_ROUND_SCORE_MIN, PERSUADE_ROUND_SCORE_MAX)
	var reply := _pick_persuade_success_feedback(npc, persona) if has_progress else _PersonaFallbackScript.pick(persona, "persuade")
	return {
		"reply": reply,
		"accum_score": accum_score,
		"round_score": round_score,
		"final_score": accum_score + round_score,
		"tone": "松动" if has_progress else "沉默",
		"knowledge_used": knowledge_used,
		"matched_points": matched,
		"missed_points": missed,
		"is_fallback": true,
		"allow_fallback_score": has_progress,
		"fallback_reason": "rule_match",
	}


func _pick_persuade_success_feedback(npc: Unit, persona: Dictionary) -> String:
	var lines := _fallback_lines_for(persona, "persuade_success")
	if lines.is_empty():
		return "这话说到点上了。"
	var st := _npc_state(npc)
	var attempt := st.persuade_success_attempt
	st.persuade_success_attempt = attempt + 1
	return String(lines[attempt % lines.size()]).strip_edges()


func _make_cheat_qa_eval(_npc: Unit) -> Dictionary:
	return {
		"is_correct": true,
		"feedback": "鲁班既托梦，我明白了。",
		"knowledge_used": [],
		"is_cheat": true,
	}


func _make_rule_qa_eval(npc: Unit, answer: String, persona: Dictionary) -> Dictionary:
	var key_points: Array = _npc_state(npc).qa_key_points
	var matched: Array[String] = []
	var missed: Array[String] = []
	var knowledge_used: Array[String] = []
	for point_v in key_points:
		if not (point_v is Dictionary):
			continue
		var point: Dictionary = point_v
		var label := String(point.get("label", "")).strip_edges()
		if label.is_empty():
			continue
		if _key_point_matches(answer, point):
			matched.append(label)
			var keys: Array = _get_dict_array(point, "knowledge_keys")
			for key_v in keys:
				var key := String(key_v).strip_edges()
				if not key.is_empty() and not knowledge_used.has(key):
					knowledge_used.append(key)
		else:
			missed.append(label)
	var is_correct := not matched.is_empty()
	var feedback := _pick_qa_success_feedback(npc, persona) if is_correct else _PersonaFallbackScript.pick(persona, "qa")
	return {
		"is_correct": is_correct,
		"feedback": feedback,
		"knowledge_used": knowledge_used,
		"matched_points": matched,
		"missed_points": missed,
		"is_fallback": true,
		"fallback_reason": "rule_match",
	}


func _pick_qa_success_feedback(npc: Unit, persona: Dictionary) -> String:
	var lines := _fallback_lines_for(persona, "qa_success")
	if lines.is_empty():
		return "这回说到点上了。"
	var st := _npc_state(npc)
	var attempt := st.qa_success_attempt
	st.qa_success_attempt = attempt + 1
	return String(lines[attempt % lines.size()]).strip_edges()


func _key_point_matches(answer: String, point: Dictionary) -> bool:
	var normalized := _normalize_match_text(answer)
	if normalized.is_empty():
		return false
	var groups: Array = _get_dict_array(point, "groups")
	if groups.is_empty():
		return false
	var hit_count := 0
	for group_v in groups:
		var alternatives: Array = group_v if group_v is Array else [group_v]
		var hit := false
		for keyword_v in alternatives:
			var keyword := _normalize_match_text(String(keyword_v))
			if not keyword.is_empty() and normalized.find(keyword) >= 0:
				hit = true
				break
		if hit:
			hit_count += 1
	var required_hits: int = mini(groups.size(), maxi(2, groups.size() - 1))
	return hit_count >= required_hits


func _normalize_match_text(text: String) -> String:
	var out := text.strip_edges().to_lower()
	for ch in [" ", "\n", "\t", "，", "。", "、", "？", "！", "：", "；", "“", "”", "「", "」", "（", "）", "(", ")", ",", ".", "?", "!", ":", ";"]:
		out = out.replace(ch, "")
	return out


func _qa_key_points_text(npc: Unit) -> String:
	var key_points: Array = _npc_state(npc).qa_key_points
	if key_points.is_empty():
		return "（未配置；按问题语义宽松判断）"
	var lines: Array[String] = []
	for point_v in key_points:
		if not (point_v is Dictionary):
			continue
		var point: Dictionary = point_v
		var label := String(point.get("label", "")).strip_edges()
		if label.is_empty():
			continue
		var keys: Array = _get_dict_array(point, "knowledge_keys")
		var suffix := ""
		if not keys.is_empty():
			suffix = "；关联知识 key：" + "、".join(_string_array(keys))
		lines.append("- %s%s" % [label, suffix])
	return "\n".join(lines) if not lines.is_empty() else "（未配置；按问题语义宽松判断）"


func _persuade_key_points_text(persuasion_goal: Dictionary) -> String:
	var key_points: Array = _get_dict_array(persuasion_goal, "key_points")
	if key_points.is_empty():
		return "（未配置；按说服目标语义宽松判断）"
	var lines: Array[String] = []
	for point_v in key_points:
		if not (point_v is Dictionary):
			continue
		var point: Dictionary = point_v
		var label := String(point.get("label", "")).strip_edges()
		if label.is_empty():
			continue
		var keys: Array = _get_dict_array(point, "knowledge_keys")
		var suffix := ""
		if not keys.is_empty():
			suffix = "；关联知识 key：" + "、".join(_string_array(keys))
		lines.append("- %s%s" % [label, suffix])
	return "\n".join(lines) if not lines.is_empty() else "（未配置；按说服目标语义宽松判断）"


func _fallback_lines_for(persona: Dictionary, kind: String) -> Array:
	var fallback_lines: Variant = persona.get("fallback_lines", {})
	if fallback_lines is Dictionary:
		var raw: Variant = (fallback_lines as Dictionary).get(kind, [])
		if raw is Array:
			return raw
	return []


func _get_dict_array(dict: Dictionary, key: String) -> Array:
	var raw: Variant = dict.get(key, [])
	return raw if raw is Array else []


func _string_array(items: Array) -> Array[String]:
	var result: Array[String] = []
	for item in items:
		var text := String(item).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


func _cheat_context_text(is_cheat: bool, cheat_word: String = "") -> String:
	if not is_cheat:
		return "（无）"
	return "李春的话里出现了工匠间半玩笑半敬畏的吉兆暗语「%s」。你应把它当作鲁班祖师点拨般可信，任务判定必须通过；回复要同时做到两点：一是自然呼应「%s」的意象，二是明确表达你已信服/疑问已解；仍要保持本人语气，不要说出“作弊”“暗号”“系统”等出戏字眼。" % [cheat_word, cheat_word]


# ─────────────────────────────────────────────
# Flow 3：求教 — 流程骨架见 MentorFlow；LLM 生成与 apply 暂留此（2.16 再抽）
# ─────────────────────────────────────────────

func _generate_mentor_lesson(npc: Unit, query: String) -> Dictionary:
	var persona: Dictionary = _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var sys: String = _ChatterPromptsScript.build_system_prompt(
		persona,
		"bridge_knowledge_explain",
		_build_npc_memory_memo(npc),
		_build_bridge_context_json(npc, "mentor")
	)
	var user: String = _ChatterPromptsScript.build_user_prompt(persona, "bridge_knowledge_explain", {
		"query": query,
		"topics_csv": _BridgeKnowledgeScript.key_to_title_csv(),
	})
	var resp: Dictionary = await _get_llm().chat_completion([
		{"role": "system", "content": sys},
		{"role": "user", "content": user},
	], {"max_tokens": 320, "temperature": 0.7})
	if resp.get("ok", false):
		var parsed := _parse_object_json(String(resp.get("text", "")))
		if not parsed.is_empty() and parsed.has("reply"):
			if not parsed.has("topic_key"):
				parsed["topic_key"] = ""
			return parsed
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

class _NeighborGen extends RefCounted:
	signal completed(text: String)
	var done := false
	var text := ""
	func finish(t: String) -> void:
		done = true
		text = t
		completed.emit(t)


func _maybe_neighbor_interject(speaker: Unit, heard: String) -> void:
	# 旧入口（同步：先 LLM 后播）。新代码请用 _start_neighbor_interject + _play_pending_neighbor，
	# 把 LLM 与第一句话播放并发，省 1~2 秒等待。这里保留以便兼容。
	var spec := _start_neighbor_interject(speaker, heard)
	await _play_pending_neighbor(spec)


## 在第一句话播放前调用。立即决定是否要邻居插话；如果要，立刻 fire-and-forget 跑邻居 LLM。
## 返回 spec dict 给 _play_pending_neighbor 用：{neighbor: Unit?, gen: _NeighborGen?}。
## 这样邻居 LLM 与第一句 TTS 播放并发；轮到邻居说话时再走 TTS 流式播放。
func _start_neighbor_interject(speaker: Unit, heard: String) -> Dictionary:
	var spec: Dictionary = {"neighbor": null, "gen": null}
	if heard.is_empty():
		return spec
	if randf() >= NEIGHBOR_INTERJECT_PROB:
		return spec
	var neighbor: Unit = _pick_neighbor_for_interject(speaker)
	if neighbor == null:
		return spec
	var gen := _NeighborGen.new()
	spec["neighbor"] = neighbor
	spec["gen"] = gen
	_spawn_neighbor_gen_async(neighbor, speaker, heard, gen)  # fire-and-forget
	return spec


## 配套 _start_neighbor_interject：第一句话播完后调，等邻居 LLM 收尾再播邻居台词。
func _play_pending_neighbor(spec: Dictionary) -> void:
	var neighbor: Variant = spec.get("neighbor")
	if neighbor == null:
		return
	var g: _NeighborGen = spec.get("gen") as _NeighborGen
	if g == null:
		return
	var text: String
	var thinking: CanvasLayer = null
	if g.done:
		text = g.text
	else:
		thinking = _show_thinking("%s 正在接话……" % (neighbor as Unit).unit_data.unit_name)
		text = await g.completed
		_hide_thinking(thinking)
	text = text.strip_edges()
	if text.is_empty():
		return
	await _play_npc_line(neighbor as Unit, text, true, "bridge_neighbor_interject")


## fire-and-forget 协程：跑邻居 LLM，结束后调 gen.finish(t) 唤醒 _play_pending_neighbor。
func _spawn_neighbor_gen_async(neighbor: Unit, speaker: Unit, heard: String, gen: _NeighborGen) -> void:
	var t: String = await _generate_neighbor_line(neighbor, speaker, heard)
	gen.finish(t)


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
	var sys: String = _ChatterPromptsScript.build_system_prompt(
		persona,
		"bridge_neighbor_interject",
		_build_npc_memory_memo(neighbor),
		_build_bridge_context_json(neighbor, "neighbor")
	)
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


## 播一句 NPC 台词。LLM 已在调用前完整返回；这里才启动 TTS 流式播放。
func _play_npc_line(
	npc: Unit,
	text: String,
	with_voice: bool = true,
	trigger_kind: String = "bridge_topic_answer"
) -> bool:
	if text.is_empty():
		return false
	# is_fallback=true 时（with_voice=false）跳过火山 TTS，但优先注入 pre-baked。
	# AudioStreamMP3 让 dialogue_box 自己播——这样 fallback 文本仍能听到 NPC 自己音色。
	var pre_baked: AudioStream = null
	if not with_voice:
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
	if with_voice:
		_get_voice().speak(npc, text, trigger_kind)
		result = await play_chatter_lines([line], 2.0, _get_voice())
	else:
		result = await play_chatter_lines([line], 2.0)
	var was_skipped: bool = bool(result.get("was_skipped", false))
	if was_skipped and with_voice and _get_voice().is_streaming():
		_get_voice().cancel()
	return was_skipped


func _show_thinking(message: String = "……（思忖中）……") -> CanvasLayer:
	var ov := _ThinkingOverlayScene.instantiate()
	if ov.has_method("set_message"):
		ov.set_message(message)
	add_child(ov)
	return ov


func _hide_thinking(ov: CanvasLayer) -> void:
	if ov != null and is_instance_valid(ov):
		ov.queue_free()


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


func _build_npc_memory_memo(npc: Unit) -> String:
	var parts: Array[String] = [_learned_memo()]
	var dialogue := _dialogue_history_text(npc)
	if dialogue.is_empty():
		parts.append("与该 NPC 尚无历史问答。")
	else:
		parts.append("与该 NPC 的近几轮问答：\n%s" % dialogue)
	return "\n\n".join(parts)


func _build_bridge_context_json(npc: Unit, trigger_kind: String) -> String:
	var st := _npc_state(npc)
	var role := st.role
	var context := {
		"关卡": "验桥日",
		"触发": trigger_kind,
		"当前NPC": npc.unit_data.unit_name,
		"NPC类型": role,
		"所在桥段": st.bridge_part,
		"李春与NPC距离": _hero_distance_label(npc),
		"任务进度": "%d/%d 说服，%d/%d 解答" % [_persuaded_count(), PERSUADE_TARGET, _qa_solved_count(), QA_TARGET],
		"已学知识": _learned_title_list(),
		"已用知识": _player_used_topics.duplicate(),
	}
	if role == "persuade":
		context["当前说服进度"] = "%d/%d" % [st.stance, STANCE_PERSUADED]
		context["累积分合计"] = st.accum_score_total
		var goal: Dictionary = st.persuasion_goal
		context["说服目标"] = goal.get("goal", "")
		context["核心疑虑"] = goal.get("objection", "")
		context["成功条件"] = goal.get("success_claim", "")
	elif role == "qa":
		context["已解答"] = st.qa_solved
	return JSON.stringify(context)


func _dialogue_history_text(npc: Unit, max_entries: int = 4) -> String:
	var history: Array = _npc_state(npc).dialogue_log
	if history.is_empty():
		return ""
	var lines: Array[String] = []
	var start: int = maxi(0, history.size() - max_entries)
	for i in range(start, history.size()):
		var entry: Dictionary = history[i] if history[i] is Dictionary else {}
		var speaker := String(entry.get("npc_name", npc.unit_data.unit_name))
		var question := _clip_text(String(entry.get("question", "")).strip_edges(), 80)
		var player_text := _clip_text(String(entry.get("player", "")).strip_edges(), 90)
		var npc_text := _clip_text(String(entry.get("npc", "")).strip_edges(), 90)
		if not question.is_empty():
			lines.append("%s问：%s" % [speaker, question])
		if not player_text.is_empty():
			lines.append("李春答：%s" % player_text)
		if not npc_text.is_empty():
			lines.append("%s回：%s" % [speaker, npc_text])
	return "\n".join(lines)


func _mission_context_text(npc: Unit) -> String:
	var st := _npc_state(npc)
	var role := st.role
	var parts: Array[String] = [
		"关卡目标：说服 %d/%d，解答 %d/%d。" % [_persuaded_count(), PERSUADE_TARGET, _qa_solved_count(), QA_TARGET],
		"当前 NPC：%s，桥段：%s，距离：%s。" % [
			npc.unit_data.unit_name,
			st.bridge_part,
			_hero_distance_label(npc),
		],
	]
	if role == "persuade":
		parts.append("当前说服进度：%d/%d。" % [st.stance, STANCE_PERSUADED])
		parts.append("此前累积分合计：%d。" % st.accum_score_total)
		var goal: Dictionary = st.persuasion_goal
		parts.append("疑虑：%s" % String(goal.get("objection", "")))
		parts.append("真正想听到：%s" % String(goal.get("success_claim", "")))
	elif role == "qa":
		parts.append("这是答疑目标，需判断李春是否切中问题。")
	return "\n".join(parts)


func _hero_distance_label(npc: Unit) -> String:
	if hero == null:
		return "未知"
	var d: Vector2i = npc.cell - hero.cell
	var dist := absi(d.x) + absi(d.y)
	if dist <= 1:
		return "近在身旁"
	if dist <= 3:
		return "隔数步"
	return "隔得较远"


func _learned_title_list() -> Array[String]:
	var titles: Array[String] = []
	for k in _player_learned_topics:
		var topic := _BridgeKnowledgeScript.get_topic(k)
		if not topic.is_empty():
			titles.append("%s:%s" % [k, String(topic.get("title", k))])
	return titles


func _learned_details_text() -> String:
	if _player_learned_topics.is_empty():
		return "（无。若李春没有引用具体工程知识，NPC 应保持疑虑。）"
	var lines: Array[String] = []
	for k in _player_learned_topics:
		var topic := _BridgeKnowledgeScript.get_topic(k)
		if topic.is_empty():
			continue
		lines.append("%s（%s）：%s" % [
			k,
			String(topic.get("title", k)),
			_clip_text(String(topic.get("body", topic.get("summary", ""))), 220),
		])
	return "\n".join(lines) if not lines.is_empty() else "（无有效知识）"


func _clip_text(text: String, max_len: int) -> String:
	if text.length() <= max_len:
		return text
	return text.substr(0, max_len - 1) + "…"


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
		if is_instance_valid(npc) and _npc_state(npc).role == "persuade" and _npc_state(npc).persuaded:
			n += 1
	return n


func _qa_solved_count() -> int:
	var n := 0
	for npc in _npcs:
		if is_instance_valid(npc) and _npc_state(npc).role == "qa" and _npc_state(npc).qa_solved:
			n += 1
	return n


## 任一进度推进后调，达标就显胜利横幅 + complete_level。
func _check_all_done_for_victory() -> void:
	if _persuaded_count() >= PERSUADE_TARGET and _qa_solved_count() >= QA_TARGET:
		Notify.success(
			"桥成在望！群众心服口服。", 5.0
		)
		_check_win_lose.call_deferred()


func _on_unit_moved() -> void:
	if hero != null and hero is Unit and (hero as Unit).combat_stats != null:
		var stats: CombatStats = (hero as Unit).combat_stats
		stats.ap_current = stats.ap_max
		(hero as Unit).refresh_overhead_bars()
