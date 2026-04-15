extends Node2D
## 技能范围双层预览 Overlay。
## 蓝色 = 释放点范围 (cast_offsets)
## 红色/绿色/黄色 = 应用范围 (effect_offsets)，颜色按技能类型区分。

var tilemap: TileMapLayer
var half_tile := Vector2(16, 8)
var _coord_font: Font = null

var _cast_cells: Array[Vector2i] = []      # 可选释放点（绝对坐标）
var _effect_cells: Array[Vector2i] = []    # 当前悬停的影响区域（绝对坐标）
var _skill: SkillData = null
var _caster_cell: Vector2i
var _hovered_cast_cell: Vector2i = Vector2i(-9999, -9999)
var _target_set: Dictionary = {}        # 有效目标（敌方）所在格子
var _hover_has_target: bool = false      # 当前悬停效果区域是否覆盖敌人

const COLOR_CAST := Color(0.3, 0.5, 1.0, 0.3)         # 蓝色 — 释放点
const COLOR_ATTACK := Color(1.0, 0.2, 0.2, 0.35)       # 红色 — 伤害（有目标）
const COLOR_ATTACK_NO_TARGET := Color(0.5, 0.5, 0.5, 0.25) # 灰色 — 伤害（无目标）
const COLOR_ASSIST := Color(0.2, 0.8, 0.2, 0.35)       # 绿色 — 增益
const COLOR_INTERACT := Color(1.0, 0.9, 0.2, 0.35)     # 黄色 — 交互
const COLOR_COORD_TEXT := Color(1.0, 0.98, 0.88, 0.95)
const COLOR_COORD_OUTLINE := Color(0.08, 0.08, 0.08, 0.95)
const COORD_FONT_SIZE := 10


func _ready() -> void:
	# 必须高于所有 TileMapLayer 的 z_index（Obstacle z=2），否则会被地形图层遮挡。
	z_index = 5
	_coord_font = Fonts.PIXEL_10


## 显示技能释放范围。caster_cell = 施法者格子坐标。
## target_cells: 有效目标（敌方单位）所在格子，用于高亮能命中的释放点。
func show_skill_range(p_tilemap: TileMapLayer, skill: SkillData, caster_cell: Vector2i, target_cells: Array[Vector2i] = []) -> void:
	tilemap = p_tilemap
	_skill = skill
	_caster_cell = caster_cell
	_hovered_cast_cell = Vector2i(-9999, -9999)
	_effect_cells.clear()

	_target_set.clear()
	for c in target_cells:
		_target_set[c] = true

	# 计算绝对坐标的释放点
	_cast_cells.clear()
	for offset in skill.cast_offsets:
		_cast_cells.append(caster_cell + offset)

	queue_redraw()


## 悬停到某格时更新影响区域预览。
func update_hover(cell: Vector2i) -> void:
	if cell == _hovered_cast_cell:
		return
	_hovered_cast_cell = cell
	_effect_cells.clear()
	_hover_has_target = false

	if _skill and cell in _cast_cells:
		for offset in _skill.effect_offsets:
			var ec := cell + offset
			_effect_cells.append(ec)
			if _target_set.has(ec):
				_hover_has_target = true

	queue_redraw()


## 检查某格是否是合法释放点。
func has_cast_cell(cell: Vector2i) -> bool:
	return cell in _cast_cells


## 获取释放点对应的影响区域（绝对坐标）。
func get_effect_cells(cast_cell: Vector2i) -> Array[Vector2i]:
	if _skill == null:
		return []
	var result: Array[Vector2i] = []
	for offset in _skill.effect_offsets:
		result.append(cast_cell + offset)
	return result


func clear() -> void:
	_cast_cells.clear()
	_effect_cells.clear()
	_target_set.clear()
	_hover_has_target = false
	_skill = null
	_hovered_cast_cell = Vector2i(-9999, -9999)
	queue_redraw()


func _draw() -> void:
	if tilemap == null:
		return

	var effect_set: Dictionary = {}
	for c in _effect_cells:
		effect_set[c] = true

	# 释放点范围（蓝色）
	for cell in _cast_cells:
		if not effect_set.has(cell):
			var center := tilemap.map_to_local(cell)
			draw_colored_polygon(_diamond(center), COLOR_CAST)

	# 影响区域（按技能类型着色）
	if _effect_cells.size() > 0:
		var color := _get_effect_color()
		for cell in _effect_cells:
			var center := tilemap.map_to_local(cell)
			draw_colored_polygon(_diamond(center), color)

	if _hovered_cast_cell in _cast_cells:
		_draw_cell_coordinate(_hovered_cast_cell, tilemap.map_to_local(_hovered_cast_cell))


func _get_effect_color() -> Color:
	if _skill == null:
		return COLOR_INTERACT
	match _skill.skill_type:
		Enums.SkillType.ATTACK:
			return COLOR_ATTACK if _hover_has_target else COLOR_ATTACK_NO_TARGET
		Enums.SkillType.ASSIST:
			return COLOR_ASSIST
		_:
			return COLOR_INTERACT


func _diamond(center: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -half_tile.y),
		center + Vector2(half_tile.x, 0),
		center + Vector2(0, half_tile.y),
		center + Vector2(-half_tile.x, 0),
	])


func _draw_cell_coordinate(cell: Vector2i, center: Vector2) -> void:
	if _coord_font == null:
		return
	var text := "%d,%d" % [cell.x, cell.y]
	var text_width := _coord_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, COORD_FONT_SIZE).x
	var pos := center + Vector2(-text_width * 0.5, -11)
	for offset in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_string(_coord_font, pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, COORD_FONT_SIZE, COLOR_COORD_OUTLINE)
	draw_string(_coord_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, COORD_FONT_SIZE, COLOR_COORD_TEXT)
