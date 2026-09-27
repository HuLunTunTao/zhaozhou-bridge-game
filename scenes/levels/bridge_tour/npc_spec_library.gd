class_name NpcSpecLibrary
extends RefCounted

## 验桥日 9 个 NPC 的静态规格表（原 bridge_tour._get_npc_specs，213 行）。
## 决策：本次用 .gd 静态数据（深层嵌套 dict + PackedScene 引用，手写 .tres 易错）；
## .tres Resource 化留作后续（设计师可在 Inspector 编辑）。
##
## 字段约定（与原 _get_npc_specs 一致）：
##   unit_id / unit_name / role / node_name / bridge_part / cell / color / visual
##   stance / roam_mode / waypoints 或 waypoint_offsets
##   persuasion_goal | qa_key_points | mentor_topics

const _VISUAL_CRAFTSMAN := preload("res://scenes/unit/visual/human/工匠/工匠_visual.tscn")
const _VISUAL_SURVEYOR := preload("res://scenes/unit/visual/human/测量工/测量工_visual.tscn")
const _VISUAL_OLD_OVERSEER := preload("res://scenes/unit/visual/human/老监工/老监工_visual.tscn")
const _VISUAL_SCHOLAR := preload("res://scenes/unit/visual/human/游学书生/游学书生_visual.tscn")
const _VISUAL_STONEMASON := preload("res://scenes/unit/visual/human/石匠/石匠_visual.tscn")
const _VISUAL_FISHERMAN := preload("res://scenes/unit/visual/human/渔夫/渔夫_visual.tscn")

const _RoamingAIScript := preload("res://scripts/npc/roaming_ai.gd")

## 通关目标数（单一真相源）。
const PERSUADE_TARGET := 3
const QA_TARGET := 4


## NPC 配置表。3 persuade + 4 qa + 2 mentor = 9 人。
static func get_specs() -> Array[Dictionary]:
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
			"mentor_topic_keys": ["flat_arch", "sui_era", "old_method"],
		},
		{
			"unit_id": "bridge_old_stonemason", "unit_name": "老石匠", "role": "mentor",
			"node_name": "NpcOldStonemason",
			"bridge_part": "石作工棚", "cell": Vector2i(-6, -5),
			"color": Color(0.7, 0.65, 0.55), "visual": _VISUAL_STONEMASON,
			"roam_mode": _RoamingAIScript.Mode.STATIONARY, "waypoints": [],
			# 老石匠偏材料 / 桥券 / 桥台 / 装饰
			"mentor_topics": ["二十八道券怎么锁住不散？", "本地青石比别处好在哪？", "桥台只埋一丈余怎么扛得住？", "栏板蛟龙也是结构？"],
			"mentor_topic_keys": ["parallel_rings", "stone_choice", "abutment", "ornament"],
		},
	]
