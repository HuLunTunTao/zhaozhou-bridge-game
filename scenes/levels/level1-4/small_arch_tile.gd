@tool
class_name SmallArchTile
extends SpecialTile
## 小拱可视化。3 状态：closed / open / blocked。
## 不影响移动/战斗，只给出桥面状态直观反馈。level1-4 的
## _side_arch_states 变化时调用 set_state 同步颜色。

const COLOR_CLOSED := Color(0.95, 0.72, 0.2, 0.6)   # 橙黄：未泄洪
const COLOR_OPEN := Color(0.35, 0.85, 0.45, 0.6)    # 绿：已泄洪
const COLOR_BLOCKED := Color(0.8, 0.25, 0.25, 0.6)  # 红：被漂木 / 淤泥塞住

var state: String = "closed"


func _ready() -> void:
	tile_color = COLOR_CLOSED
	super._ready()


func set_state(new_state: String) -> void:
	if new_state == state:
		return
	state = new_state
	match state:
		"open":
			tile_color = COLOR_OPEN
		"blocked":
			tile_color = COLOR_BLOCKED
		_:
			tile_color = COLOR_CLOSED
