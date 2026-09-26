class_name UnitRoster
extends Resource
## 我方队伍属性表（Step 4.8）：一关一张 data/units/roster_*.tres。
## 各关 _setup_li_chun / _setup_allies_from_scene 从这里取行交给 UnitFactory，
## 李春 / 测量工 / 工匠 / 运石工 的数值只在 .tres 一处维护（1-1 与 survival、
## 1-2 与 test 数值相同，共用同名表）。
## 注意：entries 底层用 Array[Resource] 避免 class_name 前向引用问题；
## 每项运行时期望是 RosterEntry 实例。

@export var entries: Array[Resource] = []


## 按 unit_name 取一行（找不到返回 null，由调用方/工厂告警）。
func find(unit_name: String) -> RosterEntry:
	for e in entries:
		var entry := e as RosterEntry
		if entry != null and entry.unit_name == unit_name:
			return entry
	return null
