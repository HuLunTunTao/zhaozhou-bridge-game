class_name ArgumentInputPanel
extends ModalPanel
## 玩家输入"想对 NPC 说什么"的模态文本面板。
##
## 用法：
##   var panel := preload("...argument_input_panel.tscn").instantiate()
##   level.add_child(panel)
##   panel.show_for("老匠首", "主拱")
##   panel.set_learned_topics(learned_keys, used_keys)   # 可选：显示已学知识 hint
##   panel.set_history(dialogue_log)                     # 可选：显示本会话历史
##   var text: String = await panel.argument_submitted   # 取消时返回 ""
##
## 静态布局：所有 UI 在 .tscn 里画好（含 PlayerLineTemplate / NpcLineTemplate）。
## 本脚本只负责绑节点 + duplicate 模板 + 拼 BBCode。

signal argument_submitted(text: String)

const _BridgeKnowledgeScript := preload("res://scripts/data/bridge_knowledge.gd")
## 历史区最多显示几条；超过截最近 N 条。
const HISTORY_MAX := 10

@export_group("Colors — Goal")
## "说服目标：" / NPC 名（暖金）
@export var color_accent_gold: Color = Color(1, 0.85098, 0.478431, 1)
## 目标标题正文（米白）
@export var color_goal_value: Color = Color(0.909804, 0.87451, 0.784314, 1)
## "对方疑虑：" / "累计推进：" / "我："（冷蓝）
@export var color_info_blue: Color = Color(0.619608, 0.764706, 1, 1)
## 疑虑 / 提示 / NPC 正文 / 未用知识标题（柔灰绿）
@export var color_soft_text: Color = Color(0.811765, 0.823529, 0.760784, 1)
## "提示："（草绿）
@export var color_hint_green: Color = Color(0.560784, 0.819608, 0.560784, 1)
## 必提关键词标题（浅金）
@export var color_keyword: Color = Color(1, 0.878431, 0.627451, 1)
## "提到这些更易加分："（土金）
@export var color_bonus_label: Color = Color(0.847059, 0.643137, 0.360784, 1)
## 累计推进值 / 已用知识 ✓（亮金）
@export var color_highlight: Color = Color(1, 0.839216, 0.627451, 1)
## 脚注 / "已学："（橄榄灰）
@export var color_muted: Color = Color(0.478431, 0.501961, 0.384314, 1)

@export_group("Colors — Learned")
## 空状态斜体提示（暗灰）
@export var color_faint: Color = Color(0.603922, 0.564706, 0.470588, 1)
## ★ 标记（明黄）
@export var color_star: Color = Color(1, 0.823529, 0.290196, 1)

@export_group("Colors — History")
## 玩家发言正文（米灰）
@export var color_player_text: Color = Color(0.862745, 0.839216, 0.768627, 1)

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _goal_hint: RichTextLabel = %GoalHint
@onready var _history_scroll: ScrollContainer = %HistoryScroll
@onready var _history_list: VBoxContainer = %HistoryList
@onready var _player_template: RichTextLabel = %PlayerLineTemplate
@onready var _npc_template: RichTextLabel = %NpcLineTemplate
@onready var _learned_hint: RichTextLabel = %LearnedHint
@onready var _input: TextEdit = %Input
@onready var _submit_btn: Button = %SubmitButton
@onready var _cancel_btn: Button = %CancelButton

var _goal: Dictionary = {}
var _base_total: int = 0


func _ready() -> void:
	# TextEdit 默认 Enter=换行，需要拦下来：Enter 提交、Shift+Enter 走默认换行
	_input.gui_input.connect(_on_input_gui_input)
	_submit_btn.pressed.connect(func(): _request_close(_input.text.strip_edges()))
	_cancel_btn.pressed.connect(func(): _request_close(""))
	_input.grab_focus.call_deferred()
	# setter 未被调用时隐藏 hint（GoalHint / HistoryScroll 已在 .tscn 默认 hidden）
	if _learned_hint:
		_learned_hint.visible = false


func _default_cancel_result() -> Variant:
	return ""


func _emit_result_signal(close_result: Variant) -> void:
	argument_submitted.emit(String(close_result))


func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		if event.shift_pressed:
			return  # Shift+Enter：让 TextEdit 默认行为换行
		# 纯 Enter：提交并阻止默认换行
		_request_close(_input.text.strip_edges())
		_input.accept_event()


func show_for(npc_name: String, subtitle_text: String) -> void:
	_title.text = "对 %s 说点什么" % npc_name
	if subtitle_text.is_empty():
		_subtitle.visible = false
	else:
		_subtitle.text = subtitle_text
		_subtitle.visible = true


## 显示说服目标。仅 persuade 流程调用；qa / mentor 保持隐藏。
func set_persuasion_goal(goal: Dictionary) -> void:
	_goal = goal.duplicate()
	_cache_or_render("goal", _goal, func(v: Variant) -> void:
		_render_goal(v as Dictionary)
	)


## 显示该 NPC 当前累计说服推进值。仅 persuade 流程调用。
func set_persuade_base_total(total: int) -> void:
	_base_total = total
	_cache_or_render("base_total", total, func(_v: Variant) -> void:
		# base_total 是 _render_goal 的输入之一；goal 已有值时重渲 goal。
		if not _goal.is_empty():
			_render_goal(_goal)
	)


## 显示玩家已学的桥梁知识。learned 是 key 数组，used 是已在 persuade/qa 中引用过的 key 数组。
## learned 为空时显示提示文字"先去找 ★ NPC 求教"。
func set_learned_topics(learned: Array, used: Array) -> void:
	_cache_or_render("learned", [learned.duplicate(), used.duplicate()], func(v: Variant) -> void:
		var pair: Array = v as Array
		_render_learned(pair[0] as Array, pair[1] as Array)
	)


## 显示本次 NPC 会话的历史。log 数组每条 {question?: String, player: String, npc: String, ...}；
## 超过 HISTORY_MAX 条只显示最近 N 条；空数组则隐藏整个 history 区。
func set_history(history_log: Array) -> void:
	_cache_or_render("history", history_log.duplicate(), func(v: Variant) -> void:
		_render_history(v as Array)
	)


func _render_goal(goal: Dictionary) -> void:
	if _goal_hint == null:
		return
	if goal.is_empty():
		_goal_hint.visible = false
		return
	var title := String(goal.get("goal", "")).strip_edges()
	var objection := String(goal.get("objection", "")).strip_edges()
	var hint := String(goal.get("hint", "")).strip_edges()
	var lines: Array[String] = []
	if not title.is_empty():
		lines.append("[color=%s]说服目标：[/color][color=%s]%s[/color]" % [_hx(color_accent_gold), _hx(color_goal_value), title])
	if not objection.is_empty():
		lines.append("[color=%s]对方疑虑：[/color][color=%s]%s[/color]" % [_hx(color_info_blue), _hx(color_soft_text), objection])
	if not hint.is_empty():
		lines.append("[color=%s]提示：[/color][color=%s]%s[/color]" % [_hx(color_hint_green), _hx(color_soft_text), hint])
	var required_raw: Variant = goal.get("required_topics", [])
	if required_raw is Array and not (required_raw as Array).is_empty():
		var keyword_titles: Array[String] = []
		for k in required_raw:
			var key := String(k)
			var topic: Dictionary = _BridgeKnowledgeScript.get_topic(key)
			var title_str: String = String(topic.get("title", key)) if not topic.is_empty() else key
			keyword_titles.append("[color=%s]%s[/color]" % [_hx(color_keyword), title_str])
		if not keyword_titles.is_empty():
			lines.append("[color=%s]提到这些更易加分：[/color]" % _hx(color_bonus_label) + " · ".join(keyword_titles))
	if _base_total > 0:
		lines.append("[color=%s]累计推进：[/color][color=%s]%d[/color][color=%s]（每轮再加累积分+本轮评分）[/color]" % [_hx(color_info_blue), _hx(color_highlight), _base_total, _hx(color_muted)])
	_goal_hint.text = "\n".join(lines)
	_goal_hint.visible = not lines.is_empty()


func _render_learned(learned: Array, used: Array) -> void:
	if _learned_hint == null:
		return
	_learned_hint.visible = true
	if learned.is_empty():
		_learned_hint.text = "[color=%s][i]先去找头顶 [color=%s]★[/color] 的 NPC 求教，再回来用学到的知识说服 / 答题[/i][/color]" % [_hx(color_faint), _hx(color_star)]
		return
	var parts: Array[String] = []
	for k in learned:
		var key := String(k)
		var topic: Dictionary = _BridgeKnowledgeScript.get_topic(key)
		if topic.is_empty():
			continue  # key 拼错或被删，不显示原始 key
		var title: String = String(topic.get("title", key))
		if used.has(key):
			parts.append("[color=%s]%s ✓[/color]" % [_hx(color_highlight), title])
		else:
			parts.append("[color=%s]%s[/color]" % [_hx(color_soft_text), title])
	if parts.is_empty():
		_learned_hint.text = "[color=%s][i]（已学条目无效）[/i][/color]" % _hx(color_faint)
		return
	_learned_hint.text = "[color=%s]已学：[/color] " % _hx(color_muted) + " · ".join(parts)


func _render_history(history_log: Array) -> void:
	if _history_list == null or _history_scroll == null:
		return
	# 清掉之前 duplicate 出来的子（保留 2 个 template）
	for child in _history_list.get_children():
		if child == _player_template or child == _npc_template:
			continue
		child.queue_free()
	if history_log.is_empty():
		_history_scroll.visible = false
		return
	_history_scroll.visible = true
	# 截最近 HISTORY_MAX 条
	var start: int = maxi(0, history_log.size() - HISTORY_MAX)
	for i in range(start, history_log.size()):
		var entry: Dictionary = history_log[i] if history_log[i] is Dictionary else {}
		var question_text := String(entry.get("question", "")).strip_edges()
		var player_text := String(entry.get("player", "")).strip_edges()
		var npc_text := String(entry.get("npc", "")).strip_edges()
		var npc_speaker := String(entry.get("npc_name", "TA"))
		if not question_text.is_empty():
			_add_npc_history_line(npc_speaker, question_text)
		if not player_text.is_empty():
			var p_lbl: RichTextLabel = _player_template.duplicate() as RichTextLabel
			p_lbl.visible = true
			p_lbl.text = "[color=%s]我：[/color][color=%s]%s[/color]" % [_hx(color_info_blue), _hx(color_player_text), player_text]
			_history_list.add_child(p_lbl)
		if not npc_text.is_empty():
			_add_npc_history_line(npc_speaker, npc_text)
	# 滚到底部（下一帧再做，等子节点 layout 完成）
	_scroll_history_to_bottom.call_deferred()


func _add_npc_history_line(npc_speaker: String, npc_text: String) -> void:
	var n_lbl: RichTextLabel = _npc_template.duplicate() as RichTextLabel
	n_lbl.visible = true
	n_lbl.text = "[color=%s]%s：[/color][color=%s]%s[/color]" % [_hx(color_accent_gold), npc_speaker, _hx(color_soft_text), npc_text]
	_history_list.add_child(n_lbl)


func _scroll_history_to_bottom() -> void:
	if _history_scroll == null:
		return
	var vbar: ScrollBar = _history_scroll.get_v_scroll_bar()
	if vbar:
		_history_scroll.scroll_vertical = int(vbar.max_value)


static func _hx(c: Color) -> String:
	return "#%s" % c.to_html(false)
