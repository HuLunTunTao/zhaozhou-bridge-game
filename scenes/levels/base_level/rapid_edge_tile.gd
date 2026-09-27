@tool
class_name RapidEdgeTile
extends TransientTile
## 激流桥缘（通用临时地块）。Boss「翻潮压桥」效果 3 在桥面上下边缘生成 1 回合。
## 设计稿语义：**被击退进入**时 12 伤 + 继续位移 1；主动走过去不触发伤害
## （约束"不可结束行动"由走位决策层自觉回避，当前不强制阻止）。
##
## 因此 SpecialTile 基类派发的 _on_unit_arrive / _on_unit_pass（对应玩家/AI
## 主动移动路径）不调用扣血，只有关卡层 `_apply_rapid_edge_if_present` 在
## 技能结算后扫到单位落格才触发——这样击退/拖拽进入才算"被击退"。
## 过期回收走 TransientTile.is_expired（round_now >= round + 1）。

const COLOR_ACTIVE := Color(0.25, 0.6, 0.95, 0.6)
const ENTER_DAMAGE := 12

var _damaged_this_frame: Dictionary = {}


func _ready() -> void:
	tile_color = COLOR_ACTIVE
	super._ready()


# 存活 1 回合：沿用 TransientTile.duration_rounds() 默认值。


# 主动路径不扣血：保持基类 noop 行为，不重写 _on_unit_arrive / _on_unit_pass。


## 关卡层调用入口：统一给"当前正好停在我这格"的单位结算 12 伤。
## 同一帧同一单位只扣一次；下一帧自动清标，允许下次再被推进来。
func apply_knockback_damage(entity: Node2D) -> void:
	if not (entity is Unit):
		return
	var u := entity as Unit
	if u.combat_stats == null or not u.combat_stats.is_alive():
		return
	var eid := u.get_instance_id()
	if _damaged_this_frame.has(eid):
		return
	_damaged_this_frame[eid] = true
	var before: int = u.combat_stats.current_hp
	u.combat_stats.current_hp = maxi(before - ENTER_DAMAGE, 0)
	u.refresh_overhead_bars()
	CombatLog.msg("  激流桥缘: %s 被冲入受 %d 伤害 (HP %d → %d)" % [u.combat_stats.unit_name, ENTER_DAMAGE, before, u.combat_stats.current_hp])
	call_deferred("_clear_damage_flag", eid)


func _clear_damage_flag(eid: int) -> void:
	_damaged_this_frame.erase(eid)
