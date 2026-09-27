@tool
class_name TransientTile
extends SpecialTile

## 临时地块基类（Step 4.5）：带过期回合的特殊地格。
## 契约：configure(round) 声明「从 round 起生效」；is_expired(round) 判定何时该回收。
## 通用子类：silt_tile（淤泥格）/ rapid_edge_tile（激流桥缘）；子类覆写 duration_rounds()
## 定义存活回合数，其余效果钩子仍走 SpecialTile 的 _on_unit_arrive / _on_unit_pass。
## 关卡层每回合用 is_expired(round) 扫一遍，过期的 unregister + queue_free。

## 过期回合（configure 时写入：round_now + duration_rounds()）。
@export var expires_at_round: int = 0


## 存活回合数（子类覆写）。
func duration_rounds() -> int:
	return 1


## 声明「从 round_now 起生效」，重算过期回合（同格重复生成时刷新）。
func configure(round_now: int) -> void:
	expires_at_round = round_now + duration_rounds()


## 是否已到回收回合。
func is_expired(round_now: int) -> bool:
	return round_now >= expires_at_round
