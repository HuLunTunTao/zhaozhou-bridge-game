@tool
class_name SmallArchTile
extends SpecialTile
## 小拱可视化。3 状态：closed / open / blocked。
## 不影响移动/战斗，只给出桥面状态直观反馈。level1-4 的
## _side_arch_states 变化时调用 set_state 同步颜色 + 文字。

const COLOR_CLOSED := Color(1.0, 0.6, 0.1, 0.85)    # 鲜橙：未泄洪
const COLOR_OPEN := Color(0.25, 0.95, 0.4, 0.85)    # 鲜绿：已泄洪
const COLOR_BLOCKED := Color(1.0, 0.2, 0.2, 0.85)   # 鲜红：被漂木 / 淤泥塞住

var state: String = "closed"


func _ready() -> void:
	tile_color = COLOR_CLOSED
	super._ready()
	_refresh_label()


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
	_refresh_label()


func _refresh_label() -> void:
	var label := get_node_or_null("Label") as Label
	if label == null:
		return
	match state:
		"open":
			label.text = "通"
		"blocked":
			label.text = "塞"
		_:
			label.text = "肩"
