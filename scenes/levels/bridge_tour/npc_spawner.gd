class_name NpcSpawner
extends RefCounted

## 验桥日 NPC 装配器（spawn + RoamingAI + waypoints + NpcSocialState 初始化）。
## 从 bridge_tour._setup_npc / _build_waypoints 抽出（原 67 行）。

signal npc_spawned(unit: Unit, state: NpcSocialState)

const STANCE_PERSUADED := 70
const NPC_ROAM_INTERVAL_MIN := 6.0 # NPC 闲逛时间间隔下限
const NPC_ROAM_INTERVAL_MAX := 10.0 # NPC 闲逛时间间隔上限

const _NpcPersonasScript := preload("res://scripts/llm/npc_personas.gd")

var _level: Node = null
var _npc_template: UnitData = null
var _on_npc_ready: Callable = Callable()   # 回调 _refresh_npc_name_label


func setup(level: Node, npc_template: UnitData, on_npc_ready: Callable = Callable()) -> void:
	_level = level
	_npc_template = npc_template
	_on_npc_ready = on_npc_ready


func spawn(spec: Dictionary) -> Unit:
	var node_name := String(spec.get("node_name", ""))
	var unit: Unit = null
	if _level != null and not node_name.is_empty() and _level.has_node("Entities/Units/%s" % node_name):
		unit = _level.get_node("Entities/Units/%s" % node_name) as Unit
	if unit == null:
		push_error("BridgeTour: missing static NPC node '%s'" % node_name)
		return null
	var data: UnitData = _npc_template.duplicate()
	data.resource_local_to_scene = true
	data.unit_id = spec["unit_id"]
	data.unit_name = spec["unit_name"]
	data.skills = []
	var visual: PackedScene = unit.visual_scene if unit.visual_scene != null else spec.get("visual", null)
	var color: Color = spec.get("color", Color.WHITE)
	unit.apply_runtime_setup(data, visual, color)
	# NPC 社交状态（类型化 Resource，替代 16+ set_meta 字符串键）
	var st := NpcSocialState.new()
	st.role = String(spec.get("role", "persuade"))
	st.bridge_part = String(spec.get("bridge_part", ""))
	st.dialogue_log = [] as Array[Dictionary]
	if st.role == "persuade":
		var stance: int = int(spec.get("stance", 50))
		st.stance = stance
		st.accum_score_total = 0
		st.last_accum_score = 0
		st.last_round_score = 0
		st.last_final_score = 0
		st.persuaded = stance >= STANCE_PERSUADED
		var goal: Variant = spec.get("persuasion_goal", {})
		st.persuasion_goal = goal if goal is Dictionary else {}
	elif st.role == "qa":
		var persona: Dictionary = _NpcPersonasScript.get_persona(unit.unit_data.unit_id, unit.unit_data.camp)
		st.qa_question = String(persona.get("qa_question", "我有一事相问，可解么？"))
		var qa_kp: Array[Dictionary] = []
		for p in spec.get("qa_key_points", []):
			if p is Dictionary:
				qa_kp.append(p)
		st.qa_key_points = qa_kp
		st.qa_solved = false
	elif st.role == "mentor":
		var topics_raw: Array = spec.get("mentor_topics", [])
		var topics: Array[String] = []
		for t in topics_raw:
			topics.append(String(t))
		st.mentor_topics = topics
	unit.set_meta(NpcSocialState.META_KEY, st)
	# RoamingAI
	var ai := RoamingAI.new()
	ai.name = "RoamingAI"
	ai.move_interval_min = float(spec.get("roam_interval_min", NPC_ROAM_INTERVAL_MIN))
	ai.move_interval_max = float(spec.get("roam_interval_max", NPC_ROAM_INTERVAL_MAX))
	ai.setup(unit, _level, spec["roam_mode"], build_waypoints(unit.cell, spec))
	unit.add_child(ai)
	npc_spawned.emit(unit, st)
	# 验桥日不显示战斗条，头顶用姓名牌承担识别与角色提示。
	if _on_npc_ready.is_valid():
		_on_npc_ready.call(unit)
	return unit


func build_waypoints(origin: Vector2i, spec: Dictionary) -> Array[Vector2i]:
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
