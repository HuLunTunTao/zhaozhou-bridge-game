@tool
class_name SiltTile
extends TransientTile
## 淤泥格（通用临时地块）。泥沙魇「淤行」在其行动结束非小拱格生成，持续 2 回合。
## 单位进入：立即额外 -4 AP。（"停留本格下回合首次移动 -2 AP" 尚未接入；
## 需要新增 status 表达"下次移动额外消耗"，暂缓。）
## 过期回收走 TransientTile.is_expired（round_now >= round + 2）。

const COLOR_ACTIVE := Color(0.45, 0.3, 0.15, 0.55)   # 褐色
const ENTER_AP_PENALTY := 4

var _source_name: String = "淤泥"


func _ready() -> void:
	tile_color = COLOR_ACTIVE
	super._ready()


func duration_rounds() -> int:
	return 2


func configure(round_now: int, source_name: String = "淤泥") -> void:
	super.configure(round_now)
	_source_name = source_name


func _on_unit_arrive(entity: Node2D) -> void:
	if not (entity is Unit):
		return
	var u := entity as Unit
	if u.combat_stats == null:
		return
	var before: int = u.combat_stats.ap_current
	u.combat_stats.ap_current = maxi(before - ENTER_AP_PENALTY, 0)
	u.refresh_overhead_bars()
	CombatLog.msg("  淤泥格: %s 进入 -%dAP (剩 %d)" % [u.combat_stats.unit_name, ENTER_AP_PENALTY, u.combat_stats.ap_current])


func _on_unit_pass(entity: Node2D) -> void:
	_on_unit_arrive(entity)
