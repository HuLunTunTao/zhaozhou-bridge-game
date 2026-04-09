class_name OffsetPresets
## 技能范围模板工具函数，生成常用的 Array[Vector2i] 偏移列表。


## 单体（释放点自身）。
const SINGLE: Array[Vector2i] = [Vector2i(0, 0)]


## 菱形：曼哈顿距离 min_r ~ max_r 的所有格子。
## diamond(1,1) = 4邻格, diamond(1,3) = 远程3格, diamond(0,2) = 含自身的2格范围。
static func diamond(min_r: int, max_r: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(-max_r, max_r + 1):
		for y in range(-max_r, max_r + 1):
			var d := absi(x) + absi(y)
			if d >= min_r and d <= max_r:
				result.append(Vector2i(x, y))
	return result


## 十字：上下左右各 arm_length 格 + 中心。
## cross(1) = 5格, cross(2) = 9格。
static func cross(arm_length: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = [Vector2i(0, 0)]
	for i in range(1, arm_length + 1):
		result.append(Vector2i(i, 0))
		result.append(Vector2i(-i, 0))
		result.append(Vector2i(0, i))
		result.append(Vector2i(0, -i))
	return result


## 直线：沿 direction 方向 length 格，不含原点。
## line(Vector2i(1,0), 4) = 右方4格。
static func line(direction: Vector2i, length: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in range(1, length + 1):
		result.append(direction * i)
	return result


## 四方向直线：上下左右各 length 格，不含原点。
static func lines_4dir(length: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for i in range(1, length + 1):
			result.append(dir * i)
	return result
