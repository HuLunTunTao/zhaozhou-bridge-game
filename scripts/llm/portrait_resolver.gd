class_name PortraitResolver
## 统一单位头像（Texture2D）获取工具。对话框、未来的其它 UI 都可复用，
## 保证头像风格与 status_bar 一致——均取 idle 朝右动画的第 0 帧作为静态头像，
## 底板按阵营上色（主角=黄、友方=绿、敌方=红），图片同 status_bar 使用的 face_background 资源。
##
## 用法：
##   var tex := PortraitResolver.get_portrait(unit)
##   var bg  := PortraitResolver.get_portrait_bg(unit)
##   DialogueLine.create(name, text, tex, side, bg)
##
## 策略（按优先级）：
##   1. 从 Unit 的 Visual (UnitVisual.sprite_frames) 取 idle 朝右第 0 帧
##   2. 失败返回 null
##
## 不再回落到 assets/face/*.png——按用户决策，全部单位统一用采样帧风格。

const BG_YELLOW := preload("res://assets/face_background/yellow.png")
const BG_GREEN := preload("res://assets/face_background/green.png")
const BG_RED := preload("res://assets/face_background/red.png")


## 返回单位的静态头像。失败返回 null（调用方负责处理）。
static func get_portrait(unit: Node) -> Texture2D:
	if unit == null or not (unit is Unit):
		return null
	var visual := unit.get_node_or_null("Visual") as UnitVisual
	if visual == null or visual.sprite_frames == null:
		return null
	var anim: StringName = visual.get_idle_right_anim_name()
	if anim == StringName(""):
		return null
	return visual.sprite_frames.get_frame_texture(anim, 0)


## 返回头像底板（face_background 系列）。
## 主角 → yellow，友方 → green，敌方 → red。无 combat_stats 时返回 null（不显示底板）。
static func get_portrait_bg(unit: Node) -> Texture2D:
	if unit == null or not (unit is Unit):
		return null
	var stats: CombatStats = unit.combat_stats
	if stats == null:
		return null
	if stats.is_hero:
		return BG_YELLOW
	if stats.camp == Enums.Camp.ENEMY:
		return BG_RED
	return BG_GREEN


## 根据阵营返回对话框中头像应放的一侧。
## 主角和友方 → "left"；敌方 → "right"。
static func side_for_unit(unit: Node) -> String:
	if unit == null or not (unit is Unit):
		return "left"
	var stats: CombatStats = unit.combat_stats
	if stats == null:
		return "left"
	if stats.is_hero:
		return "left"
	if stats.camp == Enums.Camp.ENEMY:
		return "right"
	return "left"
