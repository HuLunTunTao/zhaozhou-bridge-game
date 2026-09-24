class_name LearnedKnowledgeView
extends RefCounted

## 验桥日已学知识状态 + 知识面板入口。
## learned_topics / used_topics 与拆分前 bridge_tour 的 _player_learned_topics /
## _player_used_topics 逐字一致（`if not has(key): append(key)` 去重 append）。
##
## LLM prompt 侧的 _learned_title_list / _learned_details_text / _learned_memo /
## _learned_csv 不在此处——它们留在 LLMContextBuilder，通过 _level._player_learned_topics
## 鸭子调用（bridge_tour 属性转发到本 view），保持鸭子接口不变。
##
## _level 是 bridge_tour，对 has_overlay / _open_overlay 保持鸭子调用（同 CheatKeywordGate 模式）。

const _KnowledgePanelScene := preload("res://scenes/ui/knowledge_panel.tscn")
const ActiveOverlay = LevelStateMachine.ActiveOverlay

var _level: Node = null   # bridge_tour

## 玩家通过 mentor 学过的知识 key（来自 BridgeKnowledge.TOPICS）。
var learned_topics: Array[String] = []
## 玩家在 persuade / qa 中实际"用上了"的知识 key（在 prompt eval 时 LLM 标记的）。
var used_topics: Array[String] = []


func setup(level: Node) -> void:
	_level = level


## 记一条已学知识 key（mentor 求教成功时调）。去重 append，返回是否新增。
func add_learned(key: String) -> bool:
	if not learned_topics.has(key):
		learned_topics.append(key)
		return true
	return false


## 记一条已用知识 key（persuade / qa 中 LLM 标记引用过时调）。去重 append，返回是否新增。
func add_used(key: String) -> bool:
	if not used_topics.has(key):
		used_topics.append(key)
		return true
	return false


func is_learned(key: String) -> bool:
	return learned_topics.has(key)


func is_used(key: String) -> bool:
	return used_topics.has(key)


func learned_count() -> int:
	return learned_topics.size()


func used_count() -> int:
	return used_topics.size()


## 顶栏"桥梁知识"按钮：打开知识面板。已有 overlay 时不重复打开。
func open_panel(level: Node) -> void:
	if level.has_overlay():
		return
	var panel: Node = _KnowledgePanelScene.instantiate()
	if not level._open_overlay(ActiveOverlay.KNOWLEDGE, panel, &"closed"):
		panel.queue_free()
		return
	panel.set_state(learned_topics, used_topics)
