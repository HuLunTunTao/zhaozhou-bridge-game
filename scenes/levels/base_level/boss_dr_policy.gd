class_name BossDRPolicy
extends RefCounted

## Boss 减伤策略对象（Step 4.4）。
## 统一两种 Boss 减伤机制：
##   Mode.FACTOR — 比例免伤：免伤比例 dr → combat_stats.incoming_damage_factor = 1 - dr，
##                 由 CombatResolver.resolve_hit 自动乘算（1-4 怒水三阶段免伤）。
##   Mode.CAP    — 单次伤害上限：由 _finalize_skill_hit_damage 钩子调用 limit_hit，
##                 把单次命中伤害截断到 cap（1-3 偏载傀差值联动 1 / 10 / 9999；
##                 1-2 旧制监工 cap=0 即完全免伤）。
## 当前减伤数值由 provider Callable 现算（取决于关卡进度），策略只负责「算 + 落地」。

enum Mode { FACTOR, CAP }

var mode: int = Mode.FACTOR
## 被减伤的 Boss 单位。
var boss: Unit = null
## 数值来源：FACTOR 模式 `() -> float` 免伤比例；CAP 模式 `() -> int` 单次伤害上限。
var provider: Callable = Callable()


## 比例免伤策略（1-4）。
static func factor(p_boss: Unit, dr_provider: Callable) -> BossDRPolicy:
	var policy := BossDRPolicy.new()
	policy.mode = Mode.FACTOR
	policy.boss = p_boss
	policy.provider = dr_provider
	return policy


## 单次伤害上限策略（1-3 / 1-2）。
static func cap(p_boss: Unit, cap_provider: Callable) -> BossDRPolicy:
	var policy := BossDRPolicy.new()
	policy.mode = Mode.CAP
	policy.boss = p_boss
	policy.provider = cap_provider
	return policy


## 当前免伤比例（>0 减伤 / <0 易伤 / 0 无修正）。CAP 模式恒 0。
func current_dr() -> float:
	if mode != Mode.FACTOR or not provider.is_valid():
		return 0.0
	return float(provider.call())


## 当前入伤系数 = 1 - 免伤比例（CombatResolver 结算用）。
func current_factor() -> float:
	return 1.0 - current_dr()


## 当前单次伤害上限。FACTOR 模式不限（返回 int 上限）。
func current_cap() -> int:
	if mode != Mode.CAP or not provider.is_valid():
		return 9999
	return int(provider.call())


## FACTOR 模式落地：写 boss.combat_stats.incoming_damage_factor（幂等，随时可重算刷新）。
func apply() -> void:
	if boss == null or boss.combat_stats == null:
		return
	boss.combat_stats.incoming_damage_factor = current_factor()


## CAP 模式落地：把单次命中的实际伤害截断到 cap，写回 target HP 并刷新头顶。
## 前置语义与旧 _finalize_skill_hit_damage 逐字一致：只处理「目标是 boss 且有实际伤害」的命中。
## 返回 {changed: bool, raw: int, capped: int, cap: int}；changed=false 时未改动任何状态。
func limit_hit(target: Unit, hit: CombatResolver.HitResult) -> Dictionary:
	if mode != Mode.CAP or boss == null or target != boss:
		return {"changed": false}
	if hit.actual_damage <= 0:
		return {"changed": false}
	var damage_cap := current_cap()
	if hit.actual_damage <= damage_cap:
		return {"changed": false, "cap": damage_cap}
	var raw := hit.actual_damage
	var capped: int = mini(raw, damage_cap)
	target.combat_stats.current_hp = maxi(hit.hp_before - capped, 0)
	target.refresh_overhead_bars()
	return {"changed": true, "raw": raw, "capped": capped, "cap": damage_cap}
