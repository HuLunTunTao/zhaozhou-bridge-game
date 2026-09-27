@tool
class_name InteractionTile
extends SpecialTile

## 参数化交互地块（Step 4.3）。
## 把四关「交互点」的判定骨架收成一张参数表：{cells, allowed_skill_id, unit_filter, on_complete}。
## 吸收自 1-1 勘测点 / 1-2 参数点 / 1-3 石料场·券台 / 1-4 小拱 的 `_on_skill_executed` 交互分支。
##
## 两个触发入口（均为静态派发，遍历关卡登记的交互点列表）：
##   dispatch_skill — 技能施放触发（1-1 / 1-2 / 1-4）；
##   dispatch_touch — 单位落格触发（1-3 取石 / 交石）。
## 派发保持旧手写分支的判定顺序：先「谁此刻能交互」闸门，后「落在哪一格」判定，
## 再一次性闸门 → on_complete；因此失败提示的先后与旧版逐字一致。
##
## 参数：
##   cells             本交互点覆盖格集合（单格点一格；2×2 区传整区 4 格）。
##   allowed_skill_id  触发技能标识，与 SkillData.skill_id 或 extra_effect_id 任一相等即命中；
##                     空 = 本点只响应落格触发。
##   unit_filter       (caster: Unit) -> bool ——「谁此刻能交互」谓词。拒绝提示由谓词自己发
##                     （保留旧文案与 Notify 样式），返回 false 即拒绝。
##   on_complete       (tile, caster, target_cell) -> void —— 放行后的效果实现
##                     （本关专属的后续闸门 / 计数 / 文案也写在这里）。
##
## 扩展字段（可选）：
##   completable_once  true 时首次成功交互后 completed 置位，重复交互只走 on_already；
##                     false = 可重复交互（1-2 取参 / 1-4 小拱），计数闸门写在 on_complete 里。
##   on_cell_miss      () -> void —— 技能认领后未落在 cells 内的提示（旧「此处不是…」分支）。
##   on_already        () -> void —— 一次性点重复交互的提示（旧「已经完成过了」分支）。
##
## 同一 allowed_skill_id 的多个点（如 3 个勘测点）共享 unit_filter / on_cell_miss / on_already。

signal interaction_completed(tile: InteractionTile, caster: Node2D)

var cells: Array[Vector2i] = []
var allowed_skill_id: StringName = &""
var unit_filter: Callable = Callable()
var on_complete: Callable = Callable()
var completable_once: bool = true
var on_cell_miss: Callable = Callable()
var on_already: Callable = Callable()
var completed: bool = false


## 快捷构造（返回可继续挂 on_cell_miss / on_already 的实例）。
static func create(p_cells: Array[Vector2i], p_allowed_skill_id: StringName,
		p_unit_filter: Callable = Callable(), p_on_complete: Callable = Callable(),
		p_completable_once: bool = true) -> InteractionTile:
	var tile := InteractionTile.new()
	return tile.configure(p_cells, p_allowed_skill_id, p_unit_filter, p_on_complete, p_completable_once)


## 链式装配交互参数（可替换 new + 散字段赋值）。
func configure(p_cells: Array[Vector2i], p_allowed_skill_id: StringName,
		p_unit_filter: Callable = Callable(), p_on_complete: Callable = Callable(),
		p_completable_once: bool = true) -> InteractionTile:
	cells = p_cells.duplicate()
	allowed_skill_id = p_allowed_skill_id
	unit_filter = p_unit_filter
	on_complete = p_on_complete
	completable_once = p_completable_once
	return self


## 技能是否归本点管：skill_id / extra_effect_id 任一与 allowed_skill_id 相等。
func matches_skill(skill: SkillData) -> bool:
	if allowed_skill_id == &"" or skill == null:
		return false
	return StringName(skill.skill_id) == allowed_skill_id \
			or StringName(skill.extra_effect_id) == allowed_skill_id


## target_cell 是否落在本点覆盖格内。
func holds_cell(target_cell: Vector2i) -> bool:
	return cells.is_empty() or target_cell in cells


## 技能触发派发：在 tiles 里认领一次施放。
## 返回 true = 本次施放已被某交互点认领（含被闸门拒绝 / 落错格）；
## false = 与所有交互点无关，调用方继续自己的技能分支。
static func dispatch_skill(tiles: Array, caster: Unit, skill: SkillData, cast_cell: Vector2i) -> bool:
	var probe: InteractionTile = null
	for t in tiles:
		if not is_instance_valid(t):
			continue
		var tile := t as InteractionTile
		if tile != null and tile.matches_skill(skill):
			probe = tile
			break
	if probe == null:
		return false
	# 先「人 / 状态」闸门（同技能共享谓词与文案），保持旧分支「先人后格」的提示顺序
	if probe.unit_filter.is_valid() and not probe.unit_filter.call(caster):
		return true
	for t in tiles:
		if not is_instance_valid(t):
			continue
		var tile := t as InteractionTile
		if tile != null and tile.matches_skill(skill) and tile.holds_cell(cast_cell):
			tile._finish(caster, cast_cell)
			return true
	if probe.on_cell_miss.is_valid():
		probe.on_cell_miss.call()
	return true


## 落格触发派发：单位停在 target_cell 时认领一次交互。
## 返回 true = 已被某交互点认领；false = 该格没有落格交互点。
static func dispatch_touch(tiles: Array, caster: Unit, target_cell: Vector2i) -> bool:
	for t in tiles:
		if not is_instance_valid(t):
			continue
		var tile := t as InteractionTile
		if tile == null or not tile.holds_cell(target_cell):
			continue
		if tile.allowed_skill_id != &"":
			continue
		if tile.unit_filter.is_valid() and not tile.unit_filter.call(caster):
			return true
		tile._finish(caster, target_cell)
		return true
	return false


## 一次性完成态置位（幂等）。返回 false 表示此前已完成过。
func complete() -> bool:
	if completed:
		return false
	completed = true
	return true


func _finish(caster: Unit, target_cell: Vector2i) -> void:
	if completable_once and completed:
		if on_already.is_valid():
			on_already.call()
		return
	if completable_once:
		completed = true
	if on_complete.is_valid():
		on_complete.call(self, caster, target_cell)
	interaction_completed.emit(self, caster)
