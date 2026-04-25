class_name KnowledgePanel
extends CanvasLayer
## 验桥日的桥梁知识面板。复用 tutorial_panel 的 backdrop + 居中 PanelContainer 风格。
##
## 8 个话题，每条三态：
##   - 未学（灰、显示 summary 占位）
##   - 已学（亮、显示 body 全文）
##   - 已用（金边，曾在解答类 NPC 那里被引用）
##
## 用法：
##   var panel = preload(".../knowledge_panel.tscn").instantiate()
##   level.add_child(panel)
##   panel.set_state(learned_keys, used_keys)
##
## 关闭：玩家点 ✕ 或按 ESC。emit closed。

signal closed

const _BridgeKnowledgeScript := preload("res://scripts/data/bridge_knowledge.gd")

@onready var _backdrop: ColorRect = %Backdrop
@onready var _close_btn: Button = %CloseButton
@onready var _body: RichTextLabel = %Body

var _learned: Array[String] = []
var _used: Array[String] = []


func _ready() -> void:
	if _close_btn:
		_close_btn.pressed.connect(_on_close)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_on_close()
		get_viewport().set_input_as_handled()


func set_state(learned_keys: Array, used_keys: Array) -> void:
	_learned.clear()
	for k in learned_keys:
		_learned.append(String(k))
	_used.clear()
	for k in used_keys:
		_used.append(String(k))
	if _body:
		_body.text = _build_body()


func _build_body() -> String:
	var lines: Array[String] = []
	for topic: Dictionary in _BridgeKnowledgeScript.TOPICS:
		var key: String = String(topic.get("key", ""))
		var title: String = String(topic.get("title", ""))
		var summary: String = String(topic.get("summary", ""))
		var body: String = String(topic.get("body", ""))
		var is_learned: bool = key in _learned
		var is_used: bool = key in _used
		# 标题
		if is_used:
			lines.append("[b][color=#e8c067]◆ %s（已用于说服 / 解答）[/color][/b]" % title)
		elif is_learned:
			lines.append("[b][color=#f5edd5]● %s[/color][/b]" % title)
		else:
			lines.append("[b][color=#7d7a72]○ %s（未学）[/color][/b]" % title)
		# 正文
		if is_learned:
			lines.append("[color=#d6cdb6]%s[/color]" % body)
		else:
			lines.append("[color=#7a766b][i]%s[/i][/color]" % summary)
		lines.append("")  # blank
	lines.append("[color=#7a766b][i]提示：向头顶有 [color=#ffd24a]![/color] 标记的 NPC 求教，可解锁更多详情。[/i][/color]")
	return "\n".join(lines)


func _on_close() -> void:
	closed.emit()
	queue_free()
