@tool
extends EditorPlugin
## 运行时 SDK 占位：Godot 要求 plugin.cfg 指向一个 EditorPlugin。
## 本插件没有编辑器面板/工具栏需求，启用后什么也不做——
## 业务代码直接 preload `res://addons/godot_volcengine_tts/...` 即可。

func _enter_tree() -> void:
	pass

func _exit_tree() -> void:
	pass
