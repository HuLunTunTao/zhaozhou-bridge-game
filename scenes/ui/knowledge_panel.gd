class_name KnowledgePanel
extends ModalPanel
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
## 关闭：玩家点 ✕ 或按 ESC。基类 emit closed。

const _BridgeKnowledgeScript := preload("res://scripts/data/bridge_knowledge.gd")

@export_group("Colors")
## 深朱红：已用标题
@export var color_used_title: Color = Color(0.478431, 0.14902, 0.0784314, 1)
## 深墨：已学标题
@export var color_learned_title: Color = Color(0.101961, 0.0666667, 0.0313725, 1)
## 褪墨褐：未学标题
@export var color_unlearned_title: Color = Color(0.243137, 0.196078, 0.12549, 1)
## 深炭墨：已学正文
@export var color_learned_body: Color = Color(0.168627, 0.113725, 0.0470588, 1)
## 深石青：未学 summary
@export var color_unlearned_summary: Color = Color(0.172549, 0.290196, 0.321569, 1)
## 深栗紫：底部提示
@export var color_footer_hint: Color = Color(0.290196, 0.172549, 0.227451, 1)
## 提示内 ! 标记色
@export var color_mentor_mark: Color = Color(0.541176, 0.282353, 0.0784314, 1)

@onready var _close_btn: Button = %CloseButton
@onready var _body: RichTextLabel = %Body

var _learned: Array[String] = []
var _used: Array[String] = []


func _ready() -> void:
	if _close_btn:
		_close_btn.pressed.connect(func(): _request_close())


func set_state(learned_keys: Array, used_keys: Array) -> void:
	_learned.clear()
	for k in learned_keys:
		_learned.append(String(k))
	_used.clear()
	for k in used_keys:
		_used.append(String(k))
	_cache_or_render("body", true, func(_v: Variant) -> void:
		if _body:
			_body.text = _build_body()
	)


func _build_body() -> String:
	var lines: Array[String] = []
	for topic: Dictionary in _BridgeKnowledgeScript.TOPICS:
		var key: String = String(topic.get("key", ""))
		var title: String = String(topic.get("title", ""))
		var summary: String = String(topic.get("summary", ""))
		var body: String = String(topic.get("body", ""))
		var is_learned: bool = key in _learned
		var is_used: bool = key in _used
		# 标题（不加粗，三种状态用三种深色区分）
		if is_used:
			lines.append("[color=%s]◆ %s（已用于说服 / 解答）[/color]" % [_hx(color_used_title), title])
		elif is_learned:
			lines.append("[color=%s]● %s[/color]" % [_hx(color_learned_title), title])
		else:
			lines.append("[color=%s]○ %s（未学）[/color]" % [_hx(color_unlearned_title), title])
		# 正文：已学=深炭墨，未学 summary=深石青斜体（冷色与标题褐色区分）
		if is_learned:
			lines.append("[color=%s]%s[/color]" % [_hx(color_learned_body), body])
		else:
			lines.append("[color=%s][i]%s[/i][/color]" % [_hx(color_unlearned_summary), summary])
		lines.append("")  # blank
	# 底部提示用深栗紫，与上面四种色都不撞
	lines.append("[color=%s][i]提示：向头顶有 [color=%s]![/color] 标记的 NPC 求教，可解锁更多详情。[/i][/color]" % [_hx(color_footer_hint), _hx(color_mentor_mark)])
	return "\n".join(lines)


static func _hx(c: Color) -> String:
	return "#%s" % c.to_html(false)
