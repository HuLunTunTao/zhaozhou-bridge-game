class_name PhaseTable
## 五行化势查找表。根据攻击属性和目标属性判定化势/逆势/同气/普通。
## 启动时从 data/phases/ 加载所有 PhaseData .tres。

## 查找结果。
class PhaseResult:
	var category: Enums.PhaseCategory
	var multiplier: float
	var phase_data: PhaseData  # 化势/承势时非 null

	func _init(c: Enums.PhaseCategory, m: float, d: PhaseData = null) -> void:
		category = c
		multiplier = m
		phase_data = d

# ── 五行相克（制势）：金→木→土→水→火→金 ──
static var _dominant_map: Dictionary = {
	Enums.Element.METAL: Enums.Element.WOOD,
	Enums.Element.WOOD: Enums.Element.EARTH,
	Enums.Element.EARTH: Enums.Element.WATER,
	Enums.Element.WATER: Enums.Element.FIRE,
	Enums.Element.FIRE: Enums.Element.METAL,
}

# ── 查找表：Vector2i(atk_element, tgt_element) → PhaseData ──
static var _phase_map: Dictionary = {}
static var _initialized: bool = false


static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true
	# 显式列出所有化势资源路径（不使用 DirAccess 扫描目录，
	# 因为导出版中 res:// 目录被打包进 .pck，DirAccess 无法列举）。
	var paths := [
		"res://data/phases/earth_over_water_arrest_flow.tres",
		"res://data/phases/earth_follow_fire_smother_ash.tres",
		"res://data/phases/fire_follow_wood_spread_scorch.tres",
		"res://data/phases/fire_over_metal_molten_temper.tres",
		"res://data/phases/metal_follow_earth_open_grit.tres",
		"res://data/phases/metal_over_wood_fell_branch.tres",
		"res://data/phases/water_follow_metal_quench_edge.tres",
		"res://data/phases/water_over_fire_quench_blaze.tres",
		"res://data/phases/wood_follow_water_creeping_growth.tres",
		"res://data/phases/wood_over_earth_pierce_bank.tres",
	]
	for path in paths:
		var res := load(path)
		if res is PhaseData:
			var pd: PhaseData = res
			var key := Vector2i(pd.attack_element, pd.target_element)
			_phase_map[key] = pd


## 查找两个属性之间的关系。
static func lookup(atk_elem: Enums.Element, tgt_elem: Enums.Element) -> PhaseResult:
	_ensure_init()

	# 无属性不触发化势
	if atk_elem == Enums.Element.NONE or tgt_elem == Enums.Element.NONE:
		return PhaseResult.new(Enums.PhaseCategory.PLAIN, 1.0)

	# 同气
	if atk_elem == tgt_elem:
		return PhaseResult.new(Enums.PhaseCategory.SAME, 1.0)

	# 查找化势/承势数据
	var key := Vector2i(atk_elem, tgt_elem)
	if _phase_map.has(key):
		var pd: PhaseData = _phase_map[key]
		return PhaseResult.new(pd.category, pd.damage_multiplier, pd)

	# 逆势：目标属性克制攻击属性
	if _dominant_map.get(tgt_elem) == atk_elem:
		return PhaseResult.new(Enums.PhaseCategory.ADVERSE, 0.8)

	# 普通异属性
	return PhaseResult.new(Enums.PhaseCategory.PLAIN, 1.0)
