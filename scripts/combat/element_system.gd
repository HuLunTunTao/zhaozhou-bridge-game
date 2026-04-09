class_name ElementSystem
## 属性附着/消耗/回补系统。实现策划提供的伪代码。


## 技能命中后的属性变换。
## A = 技能属性, x = 附着量; B = 目标当前属性, y = 目标当前属性量。
static func apply_skill_element(
	stats: CombatStats,
	skill_element: Enums.Element,
	attach_amount: int
) -> void:
	var A := skill_element
	var x := attach_amount
	var B := stats.current_element
	var y := stats.current_element_amount

	if A == B or A == Enums.Element.NONE:
		# 同气 或 无属性攻击 → 不消耗、不改变
		return
	elif B == Enums.Element.NONE:
		# 目标无属性 → 直接附着
		stats.current_element = A
		stats.current_element_amount = x
	else:
		# 异属性碰撞
		if x > y:
			stats.current_element = A
			stats.current_element_amount = x - y
		elif x == y:
			stats.current_element_amount = 0  # setter 自动清除 element
		else:
			stats.current_element_amount = y - x


## 回合开始时的固有属性回补（敌方单位在行动前执行）。
## B = 当前属性, y = 当前属性量; C = 固有属性。
static func refresh_innate_element(stats: CombatStats) -> void:
	var C := stats.innate_element

	if C == Enums.Element.NONE:
		return

	var B := stats.current_element
	var y := stats.current_element_amount

	if B == C:
		# 当前 = 固有 → 不变
		return
	elif B == Enums.Element.NONE:
		# 无属性 → 开始回补
		stats.current_element = C
		stats.current_element_amount = 1
	else:
		# 外来属性残留 → 每回合消退1层
		stats.current_element_amount = maxi(y - 1, 0)
