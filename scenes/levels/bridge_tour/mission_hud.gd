class_name MissionHud
extends CanvasLayer
## 验桥日左上角任务面板。三分区显示说服 / 解答 / 求教 + 进度 + 操作提示。
## 用法：
##   var hud = preload(".../mission_hud.tscn").instantiate()
##   level.add_child(hud)
##   hud.set_targets(persuade_target=3, qa_target=4)
##   hud.add_npc("persuade", "老匠首", false)
##   hud.add_npc("qa", "渔夫", false)
##   hud.add_npc("mentor", "老监工", false)
##   hud.update_npc("persuade", "老匠首", true)
##
## state 维度按 npc_name 索引，role 区分三段。

@onready var _title: Label = %Title
@onready var _persuade_count: Label = %PersuadeCount
@onready var _persuade_list: VBoxContainer = %PersuadeList
@onready var _qa_count: Label = %QaCount
@onready var _qa_list: VBoxContainer = %QaList
@onready var _mentor_list: VBoxContainer = %MentorList
@onready var _tip: Label = %Tip

const TEXT_COLOR := Color(0.96, 0.94, 0.88)
const DIM_COLOR := Color(0.65, 0.6, 0.5)
const PERSUADE_COLOR := Color(0.55, 0.78, 1.0)
const QA_COLOR := Color(0.55, 0.95, 0.6)
const MENTOR_COLOR := Color(1.0, 0.85, 0.32)
const DONE_COLOR := Color(1.0, 0.85, 0.32)
## 几何 Unicode 标记（非 emoji），像素字体下可正常渲染。
const DOT_UNDONE := "○"
const DOT_DONE := "●"
const DOT_MENTOR := "★"
const OUTLINE_COLOR := Color(0.08, 0.08, 0.08)
const FONT_SIZE := 12

var _persuade_target: int = 3
var _qa_target: int = 4
var _persuade_done: int = 0
var _qa_done: int = 0
## name -> {role, label, done, stance, threshold, base_total, accum_score, round_score, final_score}
## persuade 显示格式：x+y/总进度，其中 x=累计基础分，y=本次回答评分。
var _entries: Dictionary = {}


func _ready() -> void:
	layer = 70
	_refresh_title()
	_refresh_counts()
	_refresh_tip()


func set_targets(persuade_target: int, qa_target: int) -> void:
	_persuade_target = persuade_target
	_qa_target = qa_target
	_refresh_title()
	_refresh_counts()


func add_npc(role: String, npc_name: String, done: bool) -> void:
	if _entries.has(npc_name):
		update_npc(role, npc_name, done)
		return
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", FONT_SIZE)
	lbl.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	lbl.add_theme_constant_override("outline_size", 3)
	var parent: VBoxContainer = _list_for(role)
	if parent:
		parent.add_child(lbl)
	_entries[npc_name] = {
		"role": role,
		"label": lbl,
		"done": false,
		"stance": -1,
		"threshold": 0,
		"base_total": 0,
		"accum_score": 0,
		"round_score": 0,
		"final_score": 0,
	}
	_render(npc_name, role, done)
	if done:
		_inc_count(role)


func update_npc(role: String, npc_name: String, done: bool) -> void:
	if not _entries.has(npc_name):
		add_npc(role, npc_name, done)
		return
	var entry: Dictionary = _entries[npc_name]
	var was_done: bool = bool(entry.get("done", false))
	_render(npc_name, role, done)
	if done and not was_done:
		_inc_count(role)


## 更新 persuade NPC 的说服进度与上轮计分。仅 persuade 起效；qa / mentor 调用静默忽略。
## 该 NPC 还未 add_npc 时自动注册（fallback）；threshold<=0 时 fallback 到 70。
func update_npc_stance(
	npc_name: String,
	stance: int,
	threshold: int,
	base_total: int = 0,
	accum_score: int = 0,
	round_score: int = 0,
	final_score: int = 0
) -> void:
	if not _entries.has(npc_name):
		add_npc("persuade", npc_name, false)
	var entry: Dictionary = _entries[npc_name]
	if String(entry.get("role", "")) != "persuade":
		return
	entry["stance"] = stance
	entry["threshold"] = threshold if threshold > 0 else 70
	entry["base_total"] = base_total
	entry["accum_score"] = accum_score
	entry["round_score"] = round_score
	entry["final_score"] = final_score
	_render(npc_name, "persuade", bool(entry.get("done", false)))


func _render(npc_name: String, role: String, done: bool) -> void:
	var entry: Dictionary = _entries[npc_name]
	var lbl: Label = entry["label"]
	var dot: String
	var color: Color
	if role == "mentor":
		dot = DOT_MENTOR
		color = MENTOR_COLOR
	elif done:
		dot = DOT_DONE
		color = DONE_COLOR
	else:
		dot = DOT_UNDONE
		match role:
			"persuade": color = PERSUADE_COLOR
			"qa": color = QA_COLOR
			_: color = TEXT_COLOR
	# persuade 显示 x+y/总进度：x=累计基础分，y=本次回答评分。
	var suffix := ""
	if role == "persuade":
		if done:
			suffix = "  ✓"
		else:
			var threshold: int = int(entry.get("threshold", 0))
			var base_total: int = int(entry.get("base_total", 0))
			var round_score: int = int(entry.get("round_score", 0))
			if threshold > 0:
				suffix = "  %d%+d/%d" % [base_total, round_score, threshold]
	lbl.text = "  %s %s%s" % [dot, npc_name, suffix]
	lbl.add_theme_color_override("font_color", color)
	entry["done"] = done


func _list_for(role: String) -> VBoxContainer:
	match role:
		"persuade":
			return _persuade_list
		"qa":
			return _qa_list
		"mentor":
			return _mentor_list
		_:
			return null


func _inc_count(role: String) -> void:
	match role:
		"persuade":
			_persuade_done += 1
		"qa":
			_qa_done += 1
	_refresh_counts()
	_refresh_title()


func _refresh_counts() -> void:
	if _persuade_count:
		_persuade_count.text = "%d / %d" % [_persuade_done, _persuade_target]
	if _qa_count:
		_qa_count.text = "%d / %d" % [_qa_done, _qa_target]


func _refresh_title() -> void:
	if _title:
		var total_done: int = _persuade_done + _qa_done
		var total_target: int = _persuade_target + _qa_target
		_title.text = "桥成在望  %d / %d" % [total_done, total_target]


func _refresh_tip() -> void:
	if _tip:
		_tip.text = "说服显示：累计基础分+本次评分/总进度"
