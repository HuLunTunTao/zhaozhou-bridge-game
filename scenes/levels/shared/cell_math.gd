class_name CellMath
extends RefCounted

## 网格坐标纯工具。所有函数 static。
## 从 level1-1 ~ level1-4 的重复实现中收编。


## 曼哈顿距离。
static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## 4-邻接或同格。
static func is_adjacent_or_same(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) <= 1


## 2×2 区（SE 展开，level1-3 语义）：anchor / +(1,0) / +(0,1) / +(1,1)。
static func zone2x2_se(anchor: Vector2i) -> Array[Vector2i]:
	return [
		anchor,
		anchor + Vector2i(1, 0),
		anchor + Vector2i(0, 1),
		anchor + Vector2i(1, 1),
	]


## 2×2 区（NW 展开，level1-4 语义）：anchor / +(-1,0) / +(0,-1) / +(-1,-1)。
static func zone2x2_nw(anchor: Vector2i) -> Array[Vector2i]:
	return [
		anchor,
		anchor + Vector2i(-1, 0),
		anchor + Vector2i(0, -1),
		anchor + Vector2i(-1, -1),
	]


## cell 是否落在 anchor 起的 2×2 区。se_expand=true 为 SE 展开（1-3），false 为 NW 展开（1-4）。
static func is_in_zone2x2(cell: Vector2i, anchor: Vector2i, se_expand: bool = true) -> bool:
	if se_expand:
		return cell.x >= anchor.x and cell.x <= anchor.x + 1 \
			and cell.y >= anchor.y and cell.y <= anchor.y + 1
	return cell.x >= anchor.x - 1 and cell.x <= anchor.x \
		and cell.y >= anchor.y - 1 and cell.y <= anchor.y


## 是否命中 anchors 中任一 2×2 区。
static func is_in_any_zone2x2(cell: Vector2i, anchors: Array[Vector2i], se_expand: bool = true) -> bool:
	for a in anchors:
		if is_in_zone2x2(cell, a, se_expand):
			return true
	return false


## 螺旋搜索最近可走格（全方扫描，非仅方环）。
## max_radius 为 range(1, max_radius) 上界（不含），默认 4 对应原 1-3/1-4 的 range(1, 4)。
## 找不到则返回 target 本身。
static func nearest_walkable(mm: MovementManager, target: Vector2i, max_radius: int = 4) -> Vector2i:
	if mm.get_movement_cost(target) != TileType.IMPASSABLE:
		return target
	for radius in range(1, max_radius):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var candidate := target + Vector2i(dx, dy)
				if mm.get_movement_cost(candidate) != TileType.IMPASSABLE:
					return candidate
	return target
