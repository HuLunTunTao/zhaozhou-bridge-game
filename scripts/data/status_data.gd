class_name StatusData
extends Resource
## 状态效果数据定义。

@export var status_id: String
@export var status_name: String
## 持续回合数。
@export var duration_turns: int = 1
## 是否为一次性触发（如脆裂：下次受击时触发后消失）。
@export var trigger_once: bool = false
@export_multiline var description: String = ""
