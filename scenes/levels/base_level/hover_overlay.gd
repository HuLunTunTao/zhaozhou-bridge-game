extends Node2D
## 鼠标 hover 格子的白色脉冲菱形描边。
##
## 与 move_overlay (z=5) / skill_targeting (z=5) 共存：
##   - 仅画描边（draw_polyline），不填充——避免压在下方蓝/黄填充上
##   - z_index=7 始终在范围与技能高亮之上、HP 条 (z=100) 之下
##
## 状态：base_level 在 preview_cell / 模态面板 / 状态变化处统一调用
##   set_hover(cell, tilemap)    → 切换格子并刷新
##   set_visible_state(active)   → 显示 / 隐藏（隐藏时 _draw 直接 return）

const PULSE_PERIOD := 0.9  # 一次完整脉动秒数
const ALPHA_MIN := 0.45
const ALPHA_MAX := 1.0
const STROKE_WIDTH := 1.0

var tilemap: TileMapLayer = null
var hover_cell: Vector2i = Vector2i(-9999, -9999)
var visible_now: bool = false
var half_tile := Vector2(16, 8)  # 与 move_overlay 一致

var _pulse_t: float = 0.0


func _ready() -> void:
	z_index = 7
	z_as_relative = false


func _process(delta: float) -> void:
	if not visible_now:
		return
	_pulse_t += delta
	queue_redraw()


func set_hover(cell: Vector2i, p_tilemap: TileMapLayer) -> void:
	tilemap = p_tilemap
	if cell != hover_cell:
		hover_cell = cell
		queue_redraw()


func set_visible_state(active: bool) -> void:
	if active == visible_now:
		return
	visible_now = active
	queue_redraw()


func clear() -> void:
	hover_cell = Vector2i(-9999, -9999)
	visible_now = false
	queue_redraw()


func _draw() -> void:
	if not visible_now or tilemap == null:
		return
	var center: Vector2 = tilemap.map_to_local(hover_cell)
	var pts: PackedVector2Array = _diamond_points(center)
	# 闭合多边形
	pts.append(pts[0])
	var phase: float = sin(_pulse_t * TAU / PULSE_PERIOD) * 0.5 + 0.5
	var alpha: float = lerpf(ALPHA_MIN, ALPHA_MAX, phase)
	draw_polyline(pts, Color(1.0, 1.0, 1.0, alpha), STROKE_WIDTH)


func _diamond_points(center: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -half_tile.y),
		center + Vector2(half_tile.x, 0),
		center + Vector2(0, half_tile.y),
		center + Vector2(-half_tile.x, 0),
	])
