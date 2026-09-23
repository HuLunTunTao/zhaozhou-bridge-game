class_name SocialInteractionFlow
extends RefCounted

## 验桥日社交交互流程骨架（模板方法）。
## 子类覆写 _is_done / _done_message / _open_panel / _await_submission /
## _thinking_message / _generate / _apply / _log / _reply_text / _is_fallback。
## 共同骨架 run() 走：done 检查 → 面板 → await 提交 → thinking → LLM → apply → log → 邻居插话 → 播台词。
##
## _level 是 bridge_tour（FreeRoamSocialLevel 子类），对它的 _show_thinking /
## _hide_thinking / _start_neighbor_interject / _play_npc_line / _play_pending_neighbor /
## _append_dialogue_log 等私有方法保持鸭子调用（_level._xxx()），不强行抽接口。

var _level: Node = null   # bridge_tour（FreeRoamSocialLevel 子类）


func setup(level: Node) -> void:
	_level = level


func run(npc: Unit) -> void:
	if _is_done(npc):
		Notify.info(_done_message(npc), 1.5)
		return
	var panel := _open_panel(npc)
	if panel == null:
		return
	var submission := await _await_submission(panel)
	if submission.is_empty():
		return
	var thinking: CanvasLayer = _level._show_thinking(_thinking_message(npc))
	var result := await _generate(npc, submission)
	_level._hide_thinking(thinking)
	_apply(npc, result)
	_log(npc, submission, result)
	var reply := _reply_text(result)
	var is_fallback := _is_fallback(result)
	var neighbor_spec: Dictionary = _level._start_neighbor_interject(npc, reply)
	await _level._play_npc_line(npc, reply, not is_fallback)
	await _level._play_pending_neighbor(neighbor_spec)


# ─────────────────────────────────────────────
# 子类覆写
# ─────────────────────────────────────────────


func _is_done(_npc: Unit) -> bool:
	return false


func _done_message(_npc: Unit) -> String:
	return ""


func _open_panel(_npc: Unit) -> Node:
	return null


func _await_submission(_panel: Node) -> String:
	return ""


func _thinking_message(npc: Unit) -> String:
	return "%s 正在思量……" % npc.unit_data.unit_name


func _generate(_npc: Unit, _submission: String) -> Dictionary:
	return {}


func _apply(_npc: Unit, _result: Dictionary) -> void:
	pass


func _log(_npc: Unit, _submission: String, _result: Dictionary) -> void:
	pass


func _reply_text(result: Dictionary) -> String:
	return String(result.get("reply", ""))


func _is_fallback(result: Dictionary) -> bool:
	return bool(result.get("is_fallback", false))
