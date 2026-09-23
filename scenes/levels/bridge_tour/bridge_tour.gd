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
const NPC_ROAM_INTERVAL_MIN := 6.0 # NPC 闲逛时间间隔下限
const NPC_ROAM_INTERVAL_MAX := 10.0 # NPC 闲逛时间间隔上限
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
			"node_name": "NpcOldMaster",
			"bridge_part": "主拱", "cell": Vector2i(5, -3),
			"color": Color(0.55, 0.4, 0.3), "visual": _VISUAL_CRAFTSMAN,
			"stance": 10, "roam_mode": _RoamingAIScript.Mode.STATIONARY, "waypoints": [],
			"persuasion_goal": {
				"goal": "让老匠首承认单孔大跨不是弃祖法冒险，而是能替代旧制多孔桥的稳妥新法。",
				"objection": "他认定一道大拱跨洨河太险，只有祖上传下来的多孔小拱才可靠。",
				"success_claim": "说清扁拱如何缓坡成跨、二十八道并列券如何分力且便于修换，并指出旧制桥墩会堵水冲毁。",
				"hint": "可用「扁拱」「二十八道并列拱券」「旧制多孔小拱」回应他的守旧疑虑。",
				"required_topics": ["flat_arch", "parallel_rings", "old_method"],
				"bad_arguments": ["只说新法好看", "贬低老师傅", "空喊年轻人有胆量"],
				"key_points": [
					{
						"label": "扁拱可一弧跨河且坡度更缓",
						"groups": [["扁拱", "弧形拱"], ["跨河", "单孔", "大跨"], ["坡", "缓", "不陡"]],
						"knowledge_keys": ["flat_arch"],
					},
					{
						"label": "二十八道并列拱券能分力且便于修换",
						"groups": [["二十八", "28"], ["并列", "分券", "拱券"], ["分力", "受力", "修换", "替换"]],
						"knowledge_keys": ["parallel_rings"],
					},
					{
						"label": "旧制多孔桥墩易堵水积淤受冲",
						"groups": [["旧制", "多孔", "桥墩"], ["堵水", "积淤", "冲毁", "洪水"]],
						"knowledge_keys": ["old_method"],
					},
				],
			},
		},
		{
			"unit_id": "bridge_river_chief", "unit_name": "河工总管", "role": "persuade",
			"node_name": "NpcRiverChief",
			"bridge_part": "桥台", "cell": Vector2i(-5, 2),
			"color": Color(0.4, 0.55, 0.7), "visual": _VISUAL_CRAFTSMAN,
			"stance": 40, "roam_mode": _RoamingAIScript.Mode.PATROL,
			"waypoint_offsets": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0)] as Array[Vector2i],
			"persuasion_goal": {
				"goal": "让河工总管相信新桥能经受汛期怒水，不会因单孔大跨而冲台毁桥。",
				"objection": "他担心洪水顶拱、堵水、淘空桥台，要求看到泄洪和基础的硬道理。",
				"success_claim": "说清敞肩小拱可分泄洪势、减轻桥身，本地青砂石桥台能承受扁拱水平推力。",
				"hint": "可用「敞肩拱」「桥台与基础」回应他的防汛疑虑。",
				"required_topics": ["open_spandrel", "abutment"],
				"bad_arguments": ["只保证不会出事", "回避汛期", "只谈桥面好走"],
				"key_points": [
					{
						"label": "敞肩小拱能分泄洪势、减轻水压",
						"groups": [["敞肩", "开肩", "小拱"], ["泄洪", "分水", "水势"], ["减轻", "水压", "冲力", "顶拱"]],
						"knowledge_keys": ["open_spandrel"],
					},
					{
						"label": "桥台与青砂石基础能承受扁拱推力",
						"groups": [["桥台", "基础", "青砂石"], ["推力", "水平推力", "承受", "稳"]],
						"knowledge_keys": ["abutment"],
					},
					{
						"label": "单孔少桥墩让洪水更顺畅通过",
						"groups": [["单孔", "少桥墩", "无桥墩"], ["不堵", "畅水", "泄洪", "积淤"]],
						"knowledge_keys": ["old_method", "open_spandrel"],
					},
				],
			},
		},
		{
			"unit_id": "bridge_court_inspector", "unit_name": "朝廷视察官", "role": "persuade",
			"node_name": "NpcCourtInspector",
			"bridge_part": "桥面中心", "cell": Vector2i(4, -5),
			"color": Color(0.7, 0.55, 0.3), "visual": _VISUAL_CRAFTSMAN,
			"stance": 30, "roam_mode": _RoamingAIScript.Mode.PATROL,
			"waypoint_offsets": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)] as Array[Vector2i],
			"persuasion_goal": {
				"goal": "让朝廷视察官认可新桥不是炫技，而是省工、省料、通商、可成政绩的稳当工程。",
				"objection": "他怕新法不可控，拖工期、耗钱粮，最后让官府背责。",
				"success_claim": "说清敞肩拱可减重省石、单孔大跨少建桥墩且利通行，并结合隋代统一度量衡与赵郡交通要冲说明政绩。",
				"hint": "可用「敞肩拱」「旧制多孔小拱」「时代背景」回应他的工期和政绩疑虑。",
				"required_topics": ["open_spandrel", "old_method", "sui_era"],
				"bad_arguments": ["只讲奇观名声", "不谈工期钱粮", "把风险推给朝廷"],
				"key_points": [
					{
						"label": "敞肩拱减重省石，降低工料压力",
						"groups": [["敞肩", "开肩", "小拱"], ["减重", "省石", "省料", "工料"]],
						"knowledge_keys": ["open_spandrel"],
					},
					{
						"label": "单孔大跨少建桥墩，通行与治水都更合算",
						"groups": [["单孔", "大跨", "少桥墩"], ["通行", "商旅", "省工", "堵水", "治水"]],
						"knowledge_keys": ["old_method"],
					},
					{
						"label": "赵郡交通与隋代统一工程背景能形成政绩",
						"groups": [["隋", "开皇", "大业", "度量衡"], ["赵郡", "交通", "通商", "政绩"]],
						"knowledge_keys": ["sui_era"],
					},
				],
			},
		},
		# ─── 解答类（4）───
		{
			"unit_id": "bridge_apprentice", "unit_name": "学徒工", "role": "qa",
			"node_name": "NpcApprentice",
			"bridge_part": "小拱", "cell": Vector2i(-2, 4),
			"color": Color(0.5, 0.85, 0.6), "visual": _VISUAL_SURVEYOR,
			"roam_mode": _RoamingAIScript.Mode.RANDOM_WALK, "waypoints": [],
			"qa_key_points": [
				{
					"label": "二十八道并列拱券可分散受力",
					"groups": [["二十八", "28"], ["并列", "分券", "各自"], ["拱券", "券"], ["分力", "受力", "分散", "分担"]],
					"knowledge_keys": ["parallel_rings"],
				},
				{
					"label": "单道券损坏可单独修换，不拖垮整桥",
					"groups": [["单独", "独立", "一道", "某一道"], ["修换", "更换", "替换", "不必动整桥", "不拖累"]],
					"knowledge_keys": ["parallel_rings"],
				},
			],
		},
		{
			"unit_id": "bridge_merchant", "unit_name": "商旅过客", "role": "qa",
			"node_name": "NpcMerchant",
			"bridge_part": "桥头", "cell": Vector2i(7, 2),
			"color": Color(0.85, 0.7, 0.4), "visual": _VISUAL_SURVEYOR,
			"roam_mode": _RoamingAIScript.Mode.PATROL,
			"waypoint_offsets": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)] as Array[Vector2i],
			"qa_key_points": [
				{
					"label": "扁拱能让桥面坡度更缓，车马上下省力",
					"groups": [["扁拱", "弧形拱"], ["坡", "坡度", "缓", "不陡"], ["车", "马", "行人", "通行"]],
					"knowledge_keys": ["flat_arch"],
				},
				{
					"label": "半圆拱为保跨度会更高更陡，扁拱更适合通行",
					"groups": [["半圆"], ["高", "陡"], ["扁拱", "低", "缓"]],
					"knowledge_keys": ["flat_arch"],
				},
			],
		},
		{
			"unit_id": "bridge_scholar", "unit_name": "游学书生", "role": "qa",
			"node_name": "NpcScholar",
			"bridge_part": "望柱栏板", "cell": Vector2i(-8, -3),
			"color": Color(0.85, 0.85, 0.95), "visual": _VISUAL_SCHOLAR,
			"roam_mode": _RoamingAIScript.Mode.RANDOM_WALK, "waypoints": [],
			"qa_key_points": [
				{
					"label": "敞肩小拱可减轻桥身重量",
					"groups": [["敞肩", "开肩", "小拱", "四孔"], ["减重", "减轻", "省石", "轻"]],
					"knowledge_keys": ["open_spandrel"],
				},
				{
					"label": "敞肩小拱可泄洪分水，结构与美感并用",
					"groups": [["敞肩", "开肩", "小拱", "四孔"], ["泄洪", "分水", "过水", "水势"], ["美", "势", "好看", "不破"]],
					"knowledge_keys": ["open_spandrel"],
				},
			],
		},
		{
			"unit_id": "bridge_fisherman", "unit_name": "渔夫", "role": "qa",
			"node_name": "NpcFisherman",
			"bridge_part": "桥下河滩", "cell": Vector2i(1, 7),
			"color": Color(0.55, 0.7, 0.85), "visual": _VISUAL_FISHERMAN,
			"roam_mode": _RoamingAIScript.Mode.PATROL,
			"waypoint_offsets": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1)] as Array[Vector2i],
			"qa_key_points": [
				{
					"label": "敞肩小拱能在汛期分泄水势，减轻主拱受压",
					"groups": [["敞肩", "开肩", "小拱", "四孔"], ["泄洪", "分水", "过水", "水势"], ["减轻", "水压", "冲力", "顶拱"]],
					"knowledge_keys": ["open_spandrel"],
				},
				{
					"label": "单孔少桥墩不堵水，桥台基础承受扁拱推力",
					"groups": [["单孔", "少桥墩", "无桥墩", "桥墩少"], ["不堵", "畅水", "积淤", "冲"], ["桥台", "基础", "青砂石"]],
					"knowledge_keys": ["old_method", "abutment"],
				},
			],
		},
		# ─── 求教类（2）───
		{
			"unit_id": "bridge_old_overseer", "unit_name": "老监工", "role": "mentor",
			"node_name": "NpcOldOverseer",
			"bridge_part": "桥头远处", "cell": Vector2i(7, -5),
			"color": Color(0.65, 0.55, 0.5), "visual": _VISUAL_OLD_OVERSEER,
			"roam_mode": _RoamingAIScript.Mode.STATIONARY, "waypoints": [],
			# 老监工偏全局：拱形 / 时代 / 旧制
			"mentor_topics": ["扁拱与半圆拱有何不同？", "为何在隋代建此奇桥？", "和旧制多孔小拱比，胜在哪？"],
		},
		{
			"unit_id": "bridge_old_stonemason", "unit_name": "老石匠", "role": "mentor",
			"node_name": "NpcOldStonemason",
			"bridge_part": "石作工棚", "cell": Vector2i(-6, -5),
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
	var hero_unit := _get_static_unit("Player")
	var npc_units: Array[Unit] = []
	for spec in _get_npc_specs():
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
	var npc_specs := _get_npc_specs()
	for i in range(npc_specs.size()):
		var spec := npc_specs[i]
		var npc := _find_team_unit_by_node_name(1, String(spec.get("node_name", "")))
		if npc == null:
			push_error("BridgeTour: missing static NPC node '%s'" % String(spec.get("node_name", "")))
			continue
		_setup_npc(npc, spec)
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


func _setup_npc(unit: Unit, spec: Dictionary) -> Unit:
	var data: UnitData = _UD_NPC_TEMPLATE.duplicate()
	data.resource_local_to_scene = true
	data.unit_id = spec["unit_id"]
	data.unit_name = spec["unit_name"]
	data.skills = []
	var visual: PackedScene = unit.visual_scene if unit.visual_scene != null else spec.get("visual", null)
	var color: Color = spec.get("color", Color.WHITE)
	unit.apply_runtime_setup(data, visual, color)
	# NPC 元数据
	var role: String = String(spec.get("role", "persuade"))
	unit.set_meta("npc_role", role)
	unit.set_meta("npc_bridge_part", spec.get("bridge_part", ""))
	unit.set_meta("npc_dialogue_log", [] as Array[Dictionary])
	if role == "persuade":
		var stance: int = int(spec.get("stance", 50))
		unit.set_meta("npc_stance", stance)
		unit.set_meta("npc_accum_score_total", 0)
		unit.set_meta("npc_last_accum_score", 0)
		unit.set_meta("npc_last_round_score", 0)
		unit.set_meta("npc_last_final_score", 0)
		unit.set_meta("npc_persuaded", stance >= STANCE_PERSUADED)
		unit.set_meta("npc_persuasion_goal", spec.get("persuasion_goal", {}))
	elif role == "qa":
		var persona: Dictionary = _NpcPersonasScript.get_persona(unit.unit_data.unit_id, unit.unit_data.camp)
		unit.set_meta("npc_qa_question", String(persona.get("qa_question", "我有一事相问，可解么？")))
		unit.set_meta("npc_qa_key_points", spec.get("qa_key_points", []))
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
	ai.move_interval_min = float(spec.get("roam_interval_min", NPC_ROAM_INTERVAL_MIN))
	ai.move_interval_max = float(spec.get("roam_interval_max", NPC_ROAM_INTERVAL_MAX))
	ai.setup(unit, self, spec["roam_mode"], _build_waypoints(unit.cell, spec))
	unit.add_child(ai)
	_npcs.append(unit)
	# 验桥日不显示战斗条，头顶用姓名牌承担识别与角色提示。
	_refresh_npc_name_label(unit)
	return unit


func _build_waypoints(origin: Vector2i, spec: Dictionary) -> Array[Vector2i]:
	var offsets: Array = spec.get("waypoint_offsets", [])
	if not offsets.is_empty():
		var result: Array[Vector2i] = []
		for offset in offsets:
			if offset is Vector2i:
				result.append(origin + offset)
		return result
	var raw_waypoints: Array = spec.get("waypoints", [])
	var waypoints: Array[Vector2i] = []
	for point in raw_waypoints:
		if point is Vector2i:
			waypoints.append(point)
	return waypoints


## 头顶姓名牌：role + 完成态决定颜色，替代 HP/AP 条。
func _refresh_npc_name_label(unit: Unit) -> void:
	var role: String = String(unit.get_meta("npc_role", ""))
	var done: bool = _npc_done(unit)
	if done and role != "mentor":
		unit.set_overhead_name_label(unit.unit_data.unit_name, _ICON_DONE)
		return
	match role:
		"persuade":
			unit.set_overhead_name_label(unit.unit_data.unit_name, _ICON_PERSUADE)
		"qa":
			unit.set_overhead_name_label(unit.unit_data.unit_name, _ICON_QA)
		"mentor":
			unit.set_overhead_name_label(unit.unit_data.unit_name, _ICON_MENTOR)
		_:
			unit.set_overhead_name_label(unit.unit_data.unit_name, Color.WHITE)


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
	var opening: String = _pick_persuade_opening(npc)
	if not opening.is_empty():
		await _play_npc_line(npc, opening, true, "bridge_persuade_opening")
	var panel: Node = _ArgumentInputPanelScene.instantiate()
	add_child(panel)
	var subtitle := bridge_part
	if not opening.is_empty():
		subtitle = "%s · 「%s」" % [bridge_part, opening]
	panel.show_for(npc.unit_data.unit_name, subtitle)
	var goal_raw: Variant = npc.get_meta("npc_persuasion_goal", {})
	var persuasion_goal: Dictionary = goal_raw if goal_raw is Dictionary else {}
	panel.set_persuasion_goal(persuasion_goal)
	panel.set_persuade_base_total(int(npc.get_meta("npc_accum_score_total", 0)))
	panel.set_learned_topics(_player_learned_topics, _player_used_topics)
	panel.set_history(_history_with_npc_prompt(npc, opening))
	var argument: String = await panel.argument_submitted
	if argument.is_empty():
		return
	var thinking := _show_thinking("%s 正在思量……" % npc.unit_data.unit_name)
	var ans: Dictionary = await _generate_persuade_answer(npc, argument)
	_hide_thinking(thinking)
	_apply_persuade_result(npc, ans)
	var reply: String = String(ans.get("reply", ""))
	var is_fallback: bool = bool(ans.get("is_fallback", false))
	# 记入对话历史；fallback 文本仍记（让玩家看到"NPC 没接到话"），但 LLM 失败那条
	# 后续不会被注入 prompt context（chatter_prompts.bridge_topic_answer 不读 dialogue_log）
	if not is_fallback:
		_append_dialogue_log(npc, argument, reply, String(ans.get("tone", "")), opening)
	else:
		_append_dialogue_log(npc, argument, reply, "fallback", opening)
	# 邻居插话与第一句话 dialog 显示并发：先 fire LLM，再开 dialog（TTS 已流式或现在播），最后等邻居完成
	var neighbor_spec := _start_neighbor_interject(npc, reply)
	await _play_npc_line(npc, reply, not is_fallback)
	await _play_pending_neighbor(neighbor_spec)


func _pick_persuade_opening(npc: Unit) -> String:
	var persona: Dictionary = _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var fallback_lines: Variant = persona.get("fallback_lines", {})
	var openings: Array = []
	if fallback_lines is Dictionary:
		var raw: Variant = (fallback_lines as Dictionary).get("persuade_opening", [])
		if raw is Array:
			openings = raw
	if openings.is_empty():
		var goal_raw: Variant = npc.get_meta("npc_persuasion_goal", {})
		if goal_raw is Dictionary:
			return String((goal_raw as Dictionary).get("objection", "")).strip_edges()
		return ""
	var attempt: int = int(npc.get_meta("npc_persuade_opening_attempt", 0))
	npc.set_meta("npc_persuade_opening_attempt", attempt + 1)
	return String(openings[attempt % openings.size()]).strip_edges()


## 检测玩家输入是否包含演示用作弊暗语。命中即整轮强制通过。
func _argument_has_cheat(argument: String) -> bool:
	return _is_cheat_text(argument)


func _generate_persuade_answer(npc: Unit, topic: String) -> Dictionary:
	var cheat_word := _matched_cheat_word(topic)
	var is_cheat := not cheat_word.is_empty()
	var persona: Dictionary = _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
	var bridge_part: String = String(npc.get_meta("npc_bridge_part", ""))
	var stance: int = int(npc.get_meta("npc_stance", 50))
	var goal_raw: Variant = npc.get_meta("npc_persuasion_goal", {})
	var persuasion_goal: Dictionary = goal_raw if goal_raw is Dictionary else {}
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
		"accum_total": int(npc.get_meta("npc_accum_score_total", 0)),
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
	var old_stance: int = int(npc.get_meta("npc_stance", 50))
	var new_stance: int = STANCE_PERSUADED if force_success else clampi(old_stance + final_score, 0, 100)
	npc.set_meta("npc_stance", new_stance)
	var accum_total: int = int(npc.get_meta("npc_accum_score_total", 0)) + accum_score
	npc.set_meta("npc_accum_score_total", accum_total)
	npc.set_meta("npc_last_accum_score", accum_score)
	npc.set_meta("npc_last_round_score", round_score)
	npc.set_meta("npc_last_final_score", final_score)
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
		_refresh_npc_name_label(npc)
		_check_all_done_for_victory()
	elif final_score < 0:
		Notify.notify("%s 摇头：「此说不通」" % npc.unit_data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 2.5)
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
	var history: Array = npc.get_meta("npc_dialogue_log", [] as Array[Dictionary])
	var entry := {
		"player": player,
		"npc": npc_text,
		"npc_name": npc.unit_data.unit_name,
		"tone": tone,
	}
	if not question.strip_edges().is_empty():
		entry["question"] = question.strip_edges()
	history.append(entry)
	npc.set_meta("npc_dialogue_log", history)


## 给输入面板显示"当前 NPC 刚问的话"，但不立即写入持久历史；
## 玩家取消时不会留下半截对话，提交后由 _append_dialogue_log 保存完整问答。
func _history_with_npc_prompt(npc: Unit, prompt_text: String) -> Array:
	var history: Array = npc.get_meta("npc_dialogue_log", [] as Array[Dictionary]).duplicate()
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
	if is_correct and not bool(npc.get_meta("npc_qa_solved", false)):
		npc.set_meta("npc_qa_solved", true)
		Notify.notify("已解答 %s 的疑问" % npc.unit_data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 3.0)
		_refresh_npc_name_label(npc)
		_check_all_done_for_victory()
	elif not is_correct:
		Notify.notify("%s 摇头：尚有疑虑" % npc.unit_data.unit_name, Notify.Position.TOP_RIGHT, Notify.Style.WARNING, 2.5)
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
	var attempt := int(npc.get_meta("npc_persuade_success_attempt", 0))
	npc.set_meta("npc_persuade_success_attempt", attempt + 1)
	return String(lines[attempt % lines.size()]).strip_edges()


func _make_cheat_qa_eval(_npc: Unit) -> Dictionary:
	return {
		"is_correct": true,
		"feedback": "鲁班既托梦，我明白了。",
		"knowledge_used": [],
		"is_cheat": true,
	}


func _make_rule_qa_eval(npc: Unit, answer: String, persona: Dictionary) -> Dictionary:
	var key_points: Array = _get_npc_meta_array(npc, "npc_qa_key_points")
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
	var attempt := int(npc.get_meta("npc_qa_success_attempt", 0))
	npc.set_meta("npc_qa_success_attempt", attempt + 1)
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
	var key_points: Array = _get_npc_meta_array(npc, "npc_qa_key_points")
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


func _get_npc_meta_array(npc: Unit, key: String) -> Array:
	if npc == null or not npc.has_meta(key):
		return []
	var raw: Variant = npc.get_meta(key)
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
	var thinking := _show_thinking("%s 正在斟酌讲法……" % npc.unit_data.unit_name)
	var lesson: Dictionary = await _generate_mentor_lesson(npc, query)
	_hide_thinking(thinking)
	_apply_mentor_lesson(npc, lesson)
	var with_voice: bool = not bool(lesson.get("is_fallback", false))
	await _play_npc_line(npc, String(lesson.get("reply", "")), with_voice)


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

func _maybe_neighbor_interject(speaker: Unit, heard: String) -> void:
	# 旧入口（同步：先 LLM 后播）。新代码请用 _start_neighbor_interject + _play_pending_neighbor，
	# 把 LLM 与第一句话播放并发，省 1~2 秒等待。这里保留以便兼容。
	var spec := _start_neighbor_interject(speaker, heard)
	await _play_pending_neighbor(spec)


## 在第一句话播放前调用。立即决定是否要邻居插话；如果要，立刻 fire-and-forget 跑邻居 LLM。
## 返回 spec dict 给 _play_pending_neighbor 用：{neighbor: Unit?, pending: {done, text}}。
## 这样邻居 LLM 与第一句 TTS 播放并发；轮到邻居说话时再走 TTS 流式播放。
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
	var thinking: CanvasLayer = null
	while not bool(pending.get("done", false)):
		if thinking == null:
			thinking = _show_thinking("%s 正在接话……" % (neighbor as Unit).unit_data.unit_name)
		var tree := get_tree()
		if tree == null:
			break
		await tree.process_frame
	_hide_thinking(thinking)
	var text: String = String(pending.get("text", "")).strip_edges()
	if text.is_empty():
		return
	await _play_npc_line(neighbor as Unit, text, true, "bridge_neighbor_interject")


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
	var role := String(npc.get_meta("npc_role", ""))
	var context := {
		"关卡": "验桥日",
		"触发": trigger_kind,
		"当前NPC": npc.unit_data.unit_name,
		"NPC类型": role,
		"所在桥段": String(npc.get_meta("npc_bridge_part", "")),
		"李春与NPC距离": _hero_distance_label(npc),
		"任务进度": "%d/%d 说服，%d/%d 解答" % [_persuaded_count(), PERSUADE_TARGET, _qa_solved_count(), QA_TARGET],
		"已学知识": _learned_title_list(),
		"已用知识": _player_used_topics.duplicate(),
	}
	if role == "persuade":
		context["当前说服进度"] = "%d/%d" % [int(npc.get_meta("npc_stance", 50)), STANCE_PERSUADED]
		context["累积分合计"] = int(npc.get_meta("npc_accum_score_total", 0))
		var goal_raw: Variant = npc.get_meta("npc_persuasion_goal", {})
		if goal_raw is Dictionary:
			var goal: Dictionary = goal_raw
			context["说服目标"] = goal.get("goal", "")
			context["核心疑虑"] = goal.get("objection", "")
			context["成功条件"] = goal.get("success_claim", "")
	elif role == "qa":
		context["已解答"] = bool(npc.get_meta("npc_qa_solved", false))
	return JSON.stringify(context)


func _dialogue_history_text(npc: Unit, max_entries: int = 4) -> String:
	var history: Array = npc.get_meta("npc_dialogue_log", [] as Array[Dictionary])
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
	var role := String(npc.get_meta("npc_role", ""))
	var parts: Array[String] = [
		"关卡目标：说服 %d/%d，解答 %d/%d。" % [_persuaded_count(), PERSUADE_TARGET, _qa_solved_count(), QA_TARGET],
		"当前 NPC：%s，桥段：%s，距离：%s。" % [
			npc.unit_data.unit_name,
			String(npc.get_meta("npc_bridge_part", "")),
			_hero_distance_label(npc),
		],
	]
	if role == "persuade":
		parts.append("当前说服进度：%d/%d。" % [int(npc.get_meta("npc_stance", 50)), STANCE_PERSUADED])
		parts.append("此前累积分合计：%d。" % int(npc.get_meta("npc_accum_score_total", 0)))
		var goal_raw: Variant = npc.get_meta("npc_persuasion_goal", {})
		if goal_raw is Dictionary:
			var goal: Dictionary = goal_raw
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
