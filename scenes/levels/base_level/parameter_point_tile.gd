@tool
extends SpecialTile
## 参数点。测量工用「测尺取参」或李春用「参数确认」在该格完成。
## 不声明 class_name 以避免与关卡脚本的本地 const 同名冲突；用 preload 引用。

signal parameter_completed(tile)

const COLOR_INCOMPLETE := Color(0.95, 0.72, 0.2, 0.55)
const COLOR_COMPLETE := Color(0.3, 0.85, 0.4, 0.55)

var completed: bool = false
var parameter_key: StringName = &""
var parameter_label: String = ""


func _ready() -> void:
	tile_color = COLOR_INCOMPLETE
	super._ready()


## 标记此参数点为完成。返回 false 表示已完成过。
func complete() -> bool:
	if completed:
		return false
	completed = true
	tile_color = COLOR_COMPLETE
	parameter_completed.emit(self)
	return true
