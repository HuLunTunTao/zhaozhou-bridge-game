class_name SurveyPointTile
extends SpecialTile
## 勘测点。测量工在相邻格使用「踏勘量址」后标记为完成。

signal survey_completed(tile: SurveyPointTile)

const COLOR_INCOMPLETE := Color(0.9, 0.8, 0.2, 0.6)
const COLOR_COMPLETE := Color(0.2, 0.85, 0.3, 0.6)

var completed: bool = false


func _ready() -> void:
	tile_color = COLOR_INCOMPLETE
	super._ready()


## 标记此勘测点为完成。返回 false 表示已完成过。
func complete() -> bool:
	if completed:
		return false
	completed = true
	tile_color = COLOR_COMPLETE
	survey_completed.emit(self)
	return true
