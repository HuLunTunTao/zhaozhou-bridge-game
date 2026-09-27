class_name NpcBadgePresenter
extends RefCounted

## 验桥日 NPC 头顶姓名牌（role + 完成态 → 颜色）。
## 几何符号 ○/●/★ 在 MissionHud 显示，头顶只用颜色。**不用 emoji**。

const COLOR_PERSUADE := Color(0.45, 0.7, 1.0)   # 蓝
const COLOR_QA := Color(0.45, 0.95, 0.55)       # 绿
const COLOR_MENTOR := Color(1.0, 0.85, 0.32)    # 黄
const COLOR_DONE := Color(1.0, 0.85, 0.32)      # 完成态金（同 mentor）
const COLOR_DEFAULT := Color.WHITE


## role + 完成态 → 头顶姓名牌颜色。persuade/qa 完成后变金色；mentor 永不"完成"。
static func color_for(state: NpcSocialState) -> Color:
	if state.is_done() and state.role != "mentor":
		return COLOR_DONE
	match state.role:
		"persuade":
			return COLOR_PERSUADE
		"qa":
			return COLOR_QA
		"mentor":
			return COLOR_MENTOR
		_:
			return COLOR_DEFAULT


## 刷新 NPC 头顶姓名牌文字 + 颜色。
static func refresh(unit: Unit, state: NpcSocialState) -> void:
	unit.set_overhead_name_label(unit.unit_data.unit_name, color_for(state))


## 该 NPC 是否完成了交互目标（persuade=已说服，qa=已解答；mentor 永不"完成"）。
static func is_done(state: NpcSocialState) -> bool:
	return state.is_done()
