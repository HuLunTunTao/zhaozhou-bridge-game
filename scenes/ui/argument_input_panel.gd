class_name ArgumentInputPanel
extends CanvasLayer
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

## set_learned_topics / set_history 在 _ready 之前被调时缓存，_ready 末尾再 render。
var _pending_learned: Array = []
var _pending_used: Array = []
var _has_pending_learned: bool = false
var _pending_goal: Dictionary = {}
var _has_pending_goal: bool = false
var _pending_history: Array = []
var _has_pending_history: bool = false
var _pending_base_total: int = 0
var _has_pending_base_total: bool = false


func _ready() -> void:
	# TextEdit 默认 Enter=换行，需要拦下来：Enter 提交、Shift+Enter 走默认换行
	_input.gui_input.connect(_on_input_gui_input)
	_submit_btn.pressed.connect(func(): _emit_and_close(_input.text.strip_edges()))
	_cancel_btn.pressed.connect(func(): _emit_and_close(""))
	_input.grab_focus.call_deferred()
	if _has_pending_learned:
		_render_learned(_pending_learned, _pending_used)
	else:
		if _learned_hint:
			_learned_hint.visible = false
	if _has_pending_goal:
		_render_goal(_pending_goal)
	else:
		if _goal_hint:
			_goal_hint.visible = false
	if _has_pending_history:
		_render_history(_pending_history)


func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		if event.shift_pressed:
			return  # Shift+Enter：让 TextEdit 默认行为换行
		# 纯 Enter：提交并阻止默认换行
		_emit_and_close(_input.text.strip_edges())
		_input.accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_emit_and_close("")
		get_viewport().set_input_as_handled()


func show_for(npc_name: String, subtitle_text: String) -> void:
	_title.text = "对 %s 说点什么" % npc_name
	if subtitle_text.is_empty():
		_subtitle.visible = false
	else:
		_subtitle.text = subtitle_text
		_subtitle.visible = true


## 显示说服目标。仅 persuade 流程调用；qa / mentor 保持隐藏。
func set_persuasion_goal(goal: Dictionary) -> void:
	if not is_inside_tree() or _goal_hint == null:
		_pending_goal = goal.duplicate()
		_has_pending_goal = true
		return
	_render_goal(goal)


## 显示该 NPC 当前累计说服推进值。仅 persuade 流程调用。
func set_persuade_base_total(total: int) -> void:
	_pending_base_total = total
	_has_pending_base_total = true
	if is_inside_tree() and _goal_hint != null and _has_pending_goal:
		_render_goal(_pending_goal)


## 显示玩家已学的桥梁知识。learned 是 key 数组，used 是已在 persuade/qa 中引用过的 key 数组。
## learned 为空时显示提示文字"先去找 ★ NPC 求教"。
func set_learned_topics(learned: Array, used: Array) -> void:
	if not is_inside_tree() or _learned_hint == null:
		_pending_learned = learned.duplicate()
		_pending_used = used.duplicate()
		_has_pending_learned = true
		return
	_render_learned(learned, used)


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
		lines.append("[color=#ffd97a]说服目标：[/color][color=#e8dfc8]%s[/color]" % title)
	if not objection.is_empty():
		lines.append("[color=#9ec3ff]对方疑虑：[/color][color=#cfd2c2]%s[/color]" % objection)
	if not hint.is_empty():
		lines.append("[color=#8fd18f]提示：[/color][color=#cfd2c2]%s[/color]" % hint)
	var required_raw: Variant = goal.get("required_topics", [])
	if required_raw is Array and not (required_raw as Array).is_empty():
		var keyword_titles: Array[String] = []
		for k in required_raw:
			var key := String(k)
			var topic: Dictionary = _BridgeKnowledgeScript.get_topic(key)
			var title_str: String = String(topic.get("title", key)) if not topic.is_empty() else key
			keyword_titles.append("[color=#ffe0a0]%s[/color]" % title_str)
		if not keyword_titles.is_empty():
			lines.append("[color=#d8a45c]提到这些更易加分：[/color]" + " · ".join(keyword_titles))
	if _has_pending_base_total and _pending_base_total > 0:
		lines.append("[color=#9ec3ff]累计推进：[/color][color=#ffd6a0]%d[/color][color=#7a8062]（每轮再加累积分+本轮评分）[/color]" % _pending_base_total)
	_goal_hint.text = "\n".join(lines)
	_goal_hint.visible = not lines.is_empty()


## 显示本次 NPC 会话的历史。log 数组每条 {question?: String, player: String, npc: String, ...}；
## 超过 HISTORY_MAX 条只显示最近 N 条；空数组则隐藏整个 history 区。
func set_history(history_log: Array) -> void:
	if not is_inside_tree() or _history_list == null:
		_pending_history = history_log.duplicate()
		_has_pending_history = true
		return
	_render_history(history_log)


func _render_learned(learned: Array, used: Array) -> void:
	if _learned_hint == null:
		return
	_learned_hint.visible = true
	if learned.is_empty():
		_learned_hint.text = "[color=#9a9078][i]先去找头顶 [color=#ffd24a]★[/color] 的 NPC 求教，再回来用学到的知识说服 / 答题[/i][/color]"
		return
	var parts: Array[String] = []
	for k in learned:
		var key := String(k)
		var topic: Dictionary = _BridgeKnowledgeScript.get_topic(key)
		if topic.is_empty():
			continue  # key 拼错或被删，不显示原始 key
		var title: String = String(topic.get("title", key))
		if used.has(key):
			parts.append("[color=#ffd6a0]%s ✓[/color]" % title)  # 已用过：高亮金黄
		else:
			parts.append("[color=#cfd2c2]%s[/color]" % title)
	if parts.is_empty():
		_learned_hint.text = "[color=#9a9078][i]（已学条目无效）[/i][/color]"
		return
	_learned_hint.text = "[color=#7a8062]已学：[/color] " + " · ".join(parts)


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
			p_lbl.text = "[color=#9ec3ff]我：[/color][color=#dcd6c4]%s[/color]" % player_text
			_history_list.add_child(p_lbl)
		if not npc_text.is_empty():
			_add_npc_history_line(npc_speaker, npc_text)
	# 滚到底部（下一帧再做，等子节点 layout 完成）
	_scroll_history_to_bottom.call_deferred()


func _add_npc_history_line(npc_speaker: String, npc_text: String) -> void:
	var n_lbl: RichTextLabel = _npc_template.duplicate() as RichTextLabel
	n_lbl.visible = true
	n_lbl.text = "[color=#ffd97a]%s：[/color][color=#cfd2c2]%s[/color]" % [npc_speaker, npc_text]
	_history_list.add_child(n_lbl)


func _scroll_history_to_bottom() -> void:
	if _history_scroll == null:
		return
	var vbar: ScrollBar = _history_scroll.get_v_scroll_bar()
	if vbar:
		_history_scroll.scroll_vertical = int(vbar.max_value)


func _emit_and_close(text: String) -> void:
	argument_submitted.emit(text)
	queue_free()
