class_name BridgeTourLevel
extends BaseLevel
## 验桥日 · LLM Agent 关卡。
##
## 实时自由移动（脱回合制），玩家控李春走到 NPC 旁边，技能栏点"交互"，曼哈顿 ≤2 内
## 选目标 → LLM 生成话题三选一 → NPC 用 persona 语气回答 + 给 stance_delta。
## 累计说服 4 名 NPC（stance ≥ 70）即胜利。
##
## 复用 1-4 关地图（继承场景）；清掉所有预置单位；NPC 与李春全部由 _on_level_ready 运行时 spawn。

# ── 玩家起手单位 ──
const _UD_LI_CHUN := preload("res://data/units/hero_li_chun.tres")
const _UD_NPC_TEMPLATE := preload("res://data/units/craftsman_guard.tres")
const _SK_INTERACT := preload("res://data/skills/bridge_tour_interact.tres")
const _HERO_COLOR := Color(1, 0.85, 0, 1)
## 起手位置（基于 1-4 关地图，桥头入口 — impl 时实测调整）。
const _HERO_CELL := Vector2i(0, 0)

# ── NPC 视觉资源（按 plan 复用工匠 / 测量工 visual） ──
const _VISUAL_CRAFTSMAN := preload("res://scenes/unit/visual/human/工匠/工匠_visual.tscn")
const _VISUAL_SURVEYOR := preload("res://scenes/unit/visual/human/测量工/测量工_visual.tscn")

const _RoamingAIScript := preload("res://scripts/npc/roaming_ai.gd")
const _NpcPersonasScript := preload("res://scripts/llm/npc_personas.gd")
const _ChatterPromptsScript := preload("res://scripts/llm/chatter_prompts.gd")
const _LLMClientScript := preload("res://scripts/llm/llm_client.gd")
const _ChatterVoiceScript := preload("res://scripts/tts/chatter_voice_adapter.gd")
const _PortraitResolverScript := preload("res://scripts/llm/portrait_resolver.gd")
const _ArgumentInputPanelScene := preload("res://scenes/ui/argument_input_panel.tscn")
const _PersuasionHudScene := preload("res://scenes/levels/bridge_tour/persuasion_hud.tscn")

## stance >= 该值 视为已说服。
const STANCE_PERSUADED := 70
## 胜利所需说服人数。
const PERSUADE_TARGET := 4
## 邻接插话概率（每次主对话结束后掷一次）。
const NEIGHBOR_INTERJECT_PROB := 0.4
## 邻接插话距离上限（曼哈顿）。
const NEIGHBOR_INTERJECT_RANGE := 5
## 李春 AP 设这么大相当于"无限"——配合移动后自动回满，玩家可以一直点格子走。
const HERO_INFINITE_AP := 99999

## NPC 配置表。impl 时按 1-4 关地图实测微调 cell / waypoints。
## 字段：
##   unit_id        : 唯一 id，喂给 voice_mapping / npc_personas
##   unit_name      : 显示名 + 走 dialogue_box speaker
##   bridge_part    : 桥部位（注入 prompt）
##   cell           : 出生格
##   color          : 染色（区分阵营 / 角色辨识）
##   visual         : visual scene 资源
##   stance         : 起手 stance（0–100）
##   roam_mode      : RoamingAI.Mode
##   waypoints      : PATROL 模式用，cell 列表
func _get_npc_specs() -> Array[Dictionary]:
	return [
		{
			"unit_id": "bridge_old_master", "unit_name": "老匠首",
			"bridge_part": "主拱", "cell": Vector2i(3, 0),
			"color": Color(0.55, 0.4, 0.3), "visual": _VISUAL_CRAFTSMAN,
			"stance": 10, "roam_mode": _RoamingAIScript.Mode.STATIONARY, "waypoints": [],
		},
		{
			"unit_id": "bridge_river_chief", "unit_name": "河工总管",
			"bridge_part": "桥台", "cell": Vector2i(-3, 1),
			"color": Color(0.4, 0.55, 0.7), "visual": _VISUAL_CRAFTSMAN,
			"stance": 40, "roam_mode": _RoamingAIScript.Mode.PATROL,
			"waypoints": [Vector2i(-3, 1), Vector2i(-3, 3), Vector2i(-5, 3), Vector2i(-5, 1)] as Array[Vector2i],
		},
		{
			"unit_id": "bridge_court_inspector", "unit_name": "朝廷视察官",
			"bridge_part": "桥面中心", "cell": Vector2i(1, -2),
			"color": Color(0.7, 0.55, 0.3), "visual": _VISUAL_CRAFTSMAN,
			"stance": 40, "roam_mode": _RoamingAIScript.Mode.PATROL,
			"waypoints": [Vector2i(1, -2), Vector2i(2, -2), Vector2i(2, -1), Vector2i(1, -1)] as Array[Vector2i],
		},
		{
			"unit_id": "bridge_apprentice", "unit_name": "学徒工",
			"bridge_part": "小拱", "cell": Vector2i(-1, 2),
			"color": Color(0.5, 0.85, 0.6), "visual": _VISUAL_SURVEYOR,
			"stance": 90, "roam_mode": _RoamingAIScript.Mode.RANDOM_WALK, "waypoints": [],
		},
		{
			"unit_id": "bridge_merchant", "unit_name": "商旅过客",
			"bridge_part": "桥头", "cell": Vector2i(4, 2),
			"color": Color(0.85, 0.7, 0.4), "visual": _VISUAL_SURVEYOR,
			"stance": 60, "roam_mode": _RoamingAIScript.Mode.PATROL,
			"waypoints": [Vector2i(4, 2), Vector2i(5, 2), Vector2i(5, 3), Vector2i(4, 3)] as Array[Vector2i],
		},
		{
			"unit_id": "bridge_scholar", "unit_name": "游学书生",
			"bridge_part": "望柱栏板", "cell": Vector2i(-4, -1),
			"color": Color(0.85, 0.85, 0.95), "visual": _VISUAL_SURVEYOR,
			"stance": 50, "roam_mode": _RoamingAIScript.Mode.RANDOM_WALK, "waypoints": [],
		},
		{
			"unit_id": "bridge_old_overseer", "unit_name": "老监工",
			"bridge_part": "桥头远处", "cell": Vector2i(5, -3),
			"color": Color(0.65, 0.55, 0.5), "visual": _VISUAL_CRAFTSMAN,
			"stance": 50, "roam_mode": _RoamingAIScript.Mode.STATIONARY, "waypoints": [],
		},
	]

## 在场 NPC 列表（与 _get_npc_specs 对应，但持有 spawn 后的实际 Unit 引用）。
var _npcs: Array[Unit] = []
## NPC 当前正与玩家对话的目标（RoamingAI 据此暂停）。
var _interaction_target: Unit = null
## 懒初始化的 LLM 客户端，复用同一份避免每次新建 HTTP 节点。
var _llm: Node = null
## 懒初始化的 chatter voice adapter，给 dialogue_box 当 voice_handle。
var _voice: Node = null
## 左上角说服进度面板。类型用 Node 避免 class_name 注册顺序问题。
var _persuasion_hud: Node = null


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
	# 清掉 1-4 关留下的占位单位（李春 + 工匠 + 测量工）—— 我们自己用 spawn_unit 重起手
	if has_node("Entities/Units"):
		for child in $"Entities/Units".get_children():
			$"Entities/Units".remove_child(child)
			child.queue_free()
	# 玩家队 + NPC 队分开，但同 faction"好人"——这样玩家点 NPC 不会把它们当自己人选中
	# 而 _get_friendly_cells_except / 战斗相关查询仍按 faction 算"友方"，不会误判敌对
	return [
		{
			"name": "玩家",
			"faction": "好人",
			"controller": "player",
			"units": [],
		},
		{
			"name": "桥上众人",
			"faction": "好人",
			"controller": "ai",
			"units": [],
		},
	]


func get_objectives_text() -> Dictionary:
	# 不显示 BRIEFING 面板，直接进 PLAYING（让 base_level._on_initial_briefing_done 立即转 PLAYING）
	return {"victory": [], "defeat": []}


func is_free_roam_level() -> bool:
	return true


func get_wave_config() -> Dictionary:
	return {}


func _on_level_ready() -> void:
	# 隐藏回合制 UI（自由移动模式不需要）
	if _turn_label:
		_turn_label.visible = false
	if _round_label:
		_round_label.visible = false
	if _end_turn_button:
		_end_turn_button.visible = false
	# 起手 spawn 李春
	var li_chun := spawn_unit(_UD_LI_CHUN, _HERO_CELL, 0)
	li_chun.unit_color = _HERO_COLOR
	# AP 设得极大 + _on_unit_moved 里每次回满 = 无限移动
	setup_unit_stats(li_chun, "李春", 130, 24, HERO_INFINITE_AP, 6, Enums.Element.NONE, 0, true)
	hero = li_chun
	# 李春身上只挂"交互"技能（此关无战斗）
	set_unit_skills(li_chun, [_SK_INTERACT])
	# Spawn NPCs
	for spec in _get_npc_specs():
		_spawn_npc(spec)
	# 说服进度 HUD
	_persuasion_hud = _PersuasionHudScene.instantiate()
	add_child(_persuasion_hud)
	_persuasion_hud.set_target(PERSUADE_TARGET)
	for npc in _npcs:
		var stance: int = int(npc.get_meta("npc_stance", 50))
		var persuaded: bool = bool(npc.get_meta("npc_persuaded", false))
		_persuasion_hud.add_npc(npc.unit_data.unit_name, stance, persuaded)
	# 自由移动模式不走 _init_turn_system，但 _can_accept_command 仍要 _waiting_for_player_input=true。
	# 同时 confirm_cell 守卫要求 current_team_index >= 0（line 1427），手动设回 0。
	_waiting_for_player_input = true
	current_team_index = 0
	# 自动选中李春，让 status_bar 显示"交互"技能按钮
	_select_hero_silently()


## 把 selected_unit 设为 hero，但跳过 _enter_targeting_move（自由移动模式下不需要移动 overlay）。
func _select_hero_silently() -> void:
	if hero == null or not (hero is Unit):
		return
	selected_unit = hero
	unit_selected = true
	_input_state = InputState.IDLE
	_update_status_bar_for_unit(hero, false)
	selection_changed.emit(hero)


## 工厂：用 craftsman_guard 模板克隆 UnitData 并改 id / name，spawn 后挂 RoamingAI。
## NPC 自定义状态（stance / bridge_part / discussed_topics）通过 Unit.set_meta 存。
## 注意 spawn 到 team 1（"桥上众人"），让玩家点击不会把它们当自己人选中。
func _spawn_npc(spec: Dictionary) -> Unit:
	var data: UnitData = _UD_NPC_TEMPLATE.duplicate()
	data.resource_local_to_scene = true
	data.unit_id = spec["unit_id"]
	data.unit_name = spec["unit_name"]
	data.skills = []   # NPC 不参战，清掉模板的技能
	var unit := spawn_unit(data, spec["cell"], 1, spec["visual"])
	unit.unit_color = spec["color"]
	# 自定义 NPC 元数据
	unit.set_meta("npc_bridge_part", spec["bridge_part"])
	unit.set_meta("npc_stance", int(spec["stance"]))
	unit.set_meta("npc_discussed_topics", [] as Array[String])
	unit.set_meta("npc_persuaded", int(spec["stance"]) >= STANCE_PERSUADED)
	# RoamingAI 节点
	var ai := _RoamingAIScript.new()
	ai.name = "RoamingAI"
	unit.add_child(ai)
	ai.setup(unit, self, spec["roam_mode"], spec.get("waypoints", []))
	_npcs.append(unit)
	return unit


## 给 RoamingAI 暂停判定用：返回当前与玩家对话的 NPC（无则 null）。
func get_interaction_target() -> Unit:
	return _interaction_target


# ─────────────────────────────────────────────
# 交互技能：拦截 _confirm_targeting_skill，根据 skill_id 走对话流而非 SkillExecutor
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
	# 关掉相机 + 状态机进入 ANIMATING，拦下方向键 / 点击 / 技能等所有"操作世界"的输入
	_set_world_input_locked(true)
	await _open_topic_choice(npc)
	_set_world_input_locked(false)
	_interaction_target = null
	# 对话完后保持 hero 选中，方便连续交互
	_input_state = InputState.IDLE
	_select_hero_silently()


## 对话期间锁住"操作世界"的输入：相机方向键、地块点击、技能等。
## 通过 LevelCamera.input_enabled 关掉相机平移；
## _input_state 设 ANIMATING 让 _can_accept_command 返回 false 拦截 tile click。
func _set_world_input_locked(locked: bool) -> void:
	if camera != null and "input_enabled" in camera:
		camera.input_enabled = not locked
	if locked:
		_input_state = InputState.ANIMATING
	# 解锁时由调用方自己把 _input_state 调回 IDLE（不在此处覆盖，避免覆盖中间状态）


func _find_npc_at_cell(cell: Vector2i) -> Unit:
	for npc in _npcs:
		if is_instance_valid(npc) and npc is Unit and (npc as Unit).cell == cell:
			return npc
	return null


## 玩家选中 NPC 后的对话主流程：弹文本输入框 → 玩家自由输入论点 → LLM 评分 + 回话。
func _open_topic_choice(npc: Unit) -> void:
	var bridge_part: String = String(npc.get_meta("npc_bridge_part", ""))
	var panel: Node = _ArgumentInputPanelScene.instantiate()
	add_child(panel)
	panel.show_for(npc.unit_data.unit_name, bridge_part)
	var argument: String = await panel.argument_submitted
	if argument.is_empty():
		# 取消（ESC / 空文本）—— 直接退出，不计入 stance / discussed
		return
	# 把玩家说过的论点写入 NPC memory（同一论点重复说服，LLM 看得到）
	var discussed: Array = npc.get_meta("npc_discussed_topics", [] as Array[String])
	discussed.append(argument)
	npc.set_meta("npc_discussed_topics", discussed)
	# LLM 评分玩家原话——期间用一个全屏 thinking overlay 拦住所有输入，
	# 等待 LLM 时不让玩家走来走去。
	var thinking := _make_thinking_overlay()
	add_child(thinking)
	var ans: Dictionary = await _generate_answer(npc, argument)
	thinking.queue_free()
	_apply_npc_answer(npc, ans)
	# 兜底回话（如"沉吟不语"）不走 TTS——念出来太出戏
	var with_voice: bool = not bool(ans.get("is_fallback", false))
	await _play_npc_line(npc, String(ans.get("reply", "")), with_voice)
	# 邻接 NPC 偶尔插话
	await _maybe_neighbor_interject(npc, String(ans.get("reply", "")))


## 一个轻量的全屏阻塞层：等 LLM 期间盖在世界上方，吃掉所有点击和键盘事件。
func _make_thinking_overlay() -> CanvasLayer:
	var c := CanvasLayer.new()
	c.layer = 95
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	# 半透明压暗
	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0.45)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_child(blocker)
	c.add_child(center)
	var label := Label.new()
	label.text = "……（思忖中）……"
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.06))
	label.add_theme_constant_override("outline_size", 4)
	center.add_child(label)
	return c


## 主对话结束后，按概率挑一个 5 格内的其他 NPC 起一句插嘴。
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


## 让邻居 NPC 用 bridge_neighbor_interject prompt 起一句话。LLM 失败 → 返回空跳过。
func _generate_neighbor_line(neighbor: Unit, speaker: Unit, heard: String) -> String:
	var persona: Dictionary = _NpcPersonasScript.get_persona(
		neighbor.unit_data.unit_id, neighbor.unit_data.camp
	)
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


## LLM 偶尔会在台词外面加一对引号 / 中文引号 / 顶格"——"，去掉。
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


## 调 LLM 让 NPC 回答某话题；返回 {reply, stance_delta, tone}。失败返回兜底回话。
func _generate_answer(npc: Unit, topic: String) -> Dictionary:
	var persona: Dictionary = _NpcPersonasScript.get_persona(
		npc.unit_data.unit_id, npc.unit_data.camp
	)
	var bridge_part: String = String(npc.get_meta("npc_bridge_part", ""))
	var stance: int = int(npc.get_meta("npc_stance", 50))
	var sys: String = _ChatterPromptsScript.build_system_prompt(persona, "bridge_topic_answer", "（无）", "{}")
	var user: String = _ChatterPromptsScript.build_user_prompt(persona, "bridge_topic_answer", {
		"topic": topic,
		"bridge_part": bridge_part,
		"stance": stance,
	})
	var resp: Dictionary = await _get_llm().chat_completion([
		{"role": "system", "content": sys},
		{"role": "user", "content": user},
	], {"max_tokens": 200, "temperature": 0.85})
	if resp.get("ok", false):
		var parsed := _parse_answer_json(String(resp.get("text", "")))
		if not parsed.is_empty():
			return parsed
	# Fallback：沉默不语，stance 不变。标记 is_fallback 让上层跳过 TTS（念"沉吟不语"很出戏）
	return {
		"reply": "（%s 沉吟不语）" % persona.get("name", npc.unit_data.unit_name),
		"stance_delta": 0,
		"tone": "沉默",
		"is_fallback": true,
	}


## 应用 stance_delta、记录已说服。HUD 更新由 step 8 的 _update_persuasion_hud 接管（暂占位）。
func _apply_npc_answer(npc: Unit, ans: Dictionary) -> void:
	var delta: int = int(ans.get("stance_delta", 0))
	var old_stance: int = int(npc.get_meta("npc_stance", 50))
	var new_stance: int = clampi(old_stance + delta, 0, 100)
	npc.set_meta("npc_stance", new_stance)
	var was_persuaded: bool = bool(npc.get_meta("npc_persuaded", false))
	var now_persuaded: bool = new_stance >= STANCE_PERSUADED
	if not was_persuaded and now_persuaded:
		npc.set_meta("npc_persuaded", true)
		Notify.notify("已说服 %s" % npc.unit_data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 3.0)
		# 命中胜利目标：弹横幅 + 走标准结算（complete_level 会切场景回主菜单）
		if _persuaded_count() >= PERSUADE_TARGET:
			Notify.notify("桥成在望！你已说服 %d 位" % _persuaded_count(), Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 5.0)
			# free-roam 模式不会自动触发 _check_win_lose（无 unit_died / round_started），手动调
			_check_win_lose.call_deferred()
	if _persuasion_hud:
		_persuasion_hud.update_npc(npc.unit_data.unit_name, new_stance, now_persuaded)


## 用 dialogue_box + chatter_voice 播一条 NPC 台词。
## with_voice=false 时不走 TTS（兜底文本如"沉吟不语"用），dialogue_box 仍按文本长度自然 dismiss。
func _play_npc_line(npc: Unit, text: String, with_voice: bool = true) -> void:
	if text.is_empty():
		return
	var line := DialogueLine.create(
		npc.unit_data.unit_name,
		text,
		_PortraitResolverScript.get_portrait(npc),
		_PortraitResolverScript.side_for_unit(npc),
		_PortraitResolverScript.get_portrait_bg(npc),
	)
	if with_voice:
		# 并行启动 TTS（不 await，让 dialogue_box 的 voice_handle 负责等收尾）
		_get_voice().speak(npc, text, "bridge_topic_answer")
		await play_chatter_lines([line], 2.0, _get_voice())
	else:
		await play_chatter_lines([line], 2.0)


## 从 LLM 回复中提取 JSON 对象 {reply, stance_delta, tone}。失败返回 {}。
func _parse_answer_json(text: String) -> Dictionary:
	var s := text.strip_edges()
	var l := s.find("{")
	var r := s.rfind("}")
	if l < 0 or r <= l:
		return {}
	var json_text := s.substr(l, r - l + 1)
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed
	if not d.has("reply"):
		return {}
	# 容错：缺字段补默认
	if not d.has("stance_delta"):
		d["stance_delta"] = 0
	if not d.has("tone"):
		d["tone"] = ""
	return d


func check_victory() -> bool:
	return _persuaded_count() >= PERSUADE_TARGET


func check_defeat() -> String:
	return ""   # 永不失败


func _persuaded_count() -> int:
	var n := 0
	for npc in _npcs:
		if is_instance_valid(npc) and bool(npc.get_meta("npc_persuaded", false)):
			n += 1
	return n


## 移动结束钩子：把李春 AP 回满，等同"无限步数"。
## 同时把 selected_unit 重选回 hero，让玩家走完一格后还能继续点格子或开技能。
func _on_unit_moved() -> void:
	if hero != null and hero is Unit and (hero as Unit).combat_stats != null:
		var stats: CombatStats = (hero as Unit).combat_stats
		stats.ap_current = stats.ap_max
		(hero as Unit).refresh_overhead_bars()


# ─────────────────────────────────────────────
# 自由移动：点击地块 — 复用 base_level 的 click-to-move（无回合制 + AP 无限）。
# 玩家点李春 → _confirm_idle 选中并进入 TARGETING_MOVE → 点目的地 → 移动。
# 由 _on_unit_moved 在每次移动后把 AP 顶满，等同无步数限制。
# ─────────────────────────────────────────────
