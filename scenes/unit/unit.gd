@tool
class_name Unit
extends Node2D

const OUTLINE_COLOR_HERO := Color(1.0, 1.0, 0.0, 0.5)   # 黄色
const OUTLINE_COLOR_ALLY := Color(0.0, 1.0, 0.0, 0.5)   # 绿色
const OUTLINE_COLOR_ENEMY := Color(1.0, 0.0, 0.0, 0.36)  # 红色

signal move_finished
## 单位倒下时发出（HP 降为 0，退场动画播完后触发）。
signal died
## 单位被右键点击时发出。
signal clicked

@export var movement_points: int = 10
@export var move_speed: float = 100.0  # pixels per second
## 单位数据（在编辑器中指定 .tres 文件）。
@export var unit_data: UnitData
## 单位外观场景。修改后立即替换 Visual 节点（编辑器中可预览）。
@export var visual_scene: PackedScene:
	set(value):
		visual_scene = value
		_replace_visual()
## 单位叠加颜色，用于区分阵营。修改后在编辑器中实时预览。
@export var unit_color: Color = Color(1, 1, 1, 1):
	set(value):
		unit_color = value
		_apply_color()

var cell: Vector2i
var is_moving := false
## 由 BaseLevel 在场景就绪后赋值，用于触发地块进入/退出钩子。
var movement_manager = null

## 运行时战斗状态（从 unit_data 初始化）。
var combat_stats: CombatStats

## 所属队伍编号（由 BaseLevel 赋值）。
var team_index: int = -1
## 所属阵营名称（由 BaseLevel 赋值）。
var faction: String = ""
## 本回合是否已行动。设为 true 时单位自动变暗，false 时恢复。
var has_acted: bool = false:
	set(value):
		has_acted = value
		_update_acted_visual()

## 当前朝向。
var _facing: UnitVisual.Facing = UnitVisual.Facing.RIGHT_FRONT
## 动画视觉组件。
var _visual: UnitVisual = null
## 头顶血条。
var _hp_bar: UnitHpBar = null

## 局内对话记忆（由 ChatterScheduler 写入）。
## 每项结构：{ "round": int, "trigger": String, "text": String }。
## 限长 MEMORY_LIMIT 条，关卡退出时随单位节点一起释放。
const MEMORY_LIMIT := 6
var dialogue_memory: Array[Dictionary] = []


func _ready() -> void:
	if visual_scene:
		_replace_visual()
	else:
		_visual = get_node_or_null("Visual") as UnitVisual
	_apply_color()
	_align_visual()
	if _visual:
		_visual.set_facing(_facing)
		_visual.play_state(&"idle")
	_init_combat_stats()
	_init_hp_bar()
	_init_click_button()


## 将 visual_scene 的属性复制到当前 Visual 节点（不替换节点）。
func _replace_visual() -> void:
	if not is_inside_tree():
		return
	var visual := get_node_or_null("Visual")
	if visual == null or visual_scene == null:
		return
	var source := visual_scene.instantiate()
	visual.sprite_frames = source.sprite_frames
	if source.material:
		visual.material = source.material.duplicate()
	visual.scale = source.scale
	visual.flip_h = source.flip_h
	visual.flip_v = source.flip_v
	visual.set_script(source.get_script())
	for prop in ["move_is_idle", "flip_h_for_turning", "default_facing_left", "hp_bar_height"]:
		if prop in source:
			visual.set(prop, source.get(prop))
	# 复制 FootMarker 位置
	var src_marker := source.get_node_or_null("FootMarker") as Marker2D
	var dst_marker := visual.get_node_or_null("FootMarker") as Marker2D
	if src_marker and dst_marker:
		dst_marker.position = src_marker.position
	source.free()
	# 重新播放动画以刷新显示
	if visual.sprite_frames and visual.sprite_frames.get_animation_names().size() > 0:
		visual.play(visual.sprite_frames.get_animation_names()[0])
	_visual = visual as UnitVisual
	_apply_color()
	_align_visual()


## 从 unit_data 初始化 combat_stats。
func _init_combat_stats() -> void:
	if Engine.is_editor_hint():
		return
	if unit_data:
		combat_stats = CombatStats.new()
		combat_stats.init_from(unit_data)
		movement_points = combat_stats.ap_current


## 运行时为占位单位补齐真实角色数据、外观和颜色。
## 用于关卡场景里先放一个通用 Unit，再在 _on_level_ready() 中指定具体角色。
func apply_runtime_setup(data: UnitData, visual: PackedScene = null, color: Color = Color(1, 1, 1, 1)) -> void:
	if data == null:
		return
	unit_data = data.duplicate(true)
	unit_data.resource_local_to_scene = true
	if visual != null:
		visual_scene = visual
	unit_color = color
	_init_combat_stats()
	_init_hp_bar()
	refresh_overhead_bars()


## 根据 FootMarker 定位 Visual（脚底对齐 Unit 原点）和 HpBar。
func _align_visual() -> void:
	if _visual:
		_visual.position = -_visual.get_foot_offset()


## 初始化头顶血条。
func _init_hp_bar() -> void:
	if Engine.is_editor_hint():
		return
	_hp_bar = get_node_or_null("HpBar") as UnitHpBar
	if _hp_bar:
		# HpBar 位于脚底上方 hp_bar_height 像素处
		var h := _visual.hp_bar_height if _visual else 40.0
		_hp_bar.position = Vector2(0, -h)
	if _hp_bar and combat_stats:
		_hp_bar.update_element(combat_stats.current_element, combat_stats.current_element_amount)


## 初始化透明点击按钮（不再拦截左键，选择改由地块点击处理）。
func _init_click_button() -> void:
	if Engine.is_editor_hint():
		return
	var btn := get_node_or_null("Button") as Button
	if btn:
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _update_acted_visual() -> void:
	if not is_inside_tree():
		return
	if _visual:
		_visual.set_acted(has_acted)


func _apply_color() -> void:
	if _visual:
		_visual.set_unit_color(unit_color)


## 根据阵营设置描边颜色。主角黄色，友方绿色，敌方红色。
func apply_faction_outline() -> void:
	if _visual == null:
		return
	var color: Color
	if combat_stats and combat_stats.is_hero:
		color = OUTLINE_COLOR_HERO
	elif faction == "好人":
		color = OUTLINE_COLOR_ALLY
	else:
		color = OUTLINE_COLOR_ENEMY
	_visual.set_outline_color(color)


## 单位倒下：播放淡出动画后从场景树移除，并发出 died 信号。
func die() -> void:
	# 防止重复调用
	if not is_inside_tree():
		return
	set_process_input(false)
	is_moving = false
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	await tween.finished
	died.emit()
	queue_free()


## 刷新血条显示。外部在伤害/治疗后调用。
func refresh_hp_bar() -> void:
	if _hp_bar and combat_stats:
		_hp_bar.update_hp(float(combat_stats.current_hp) / float(combat_stats.max_hp))


## 刷新 AP 条显示。
func refresh_ap_bar() -> void:
	if _hp_bar and combat_stats:
		_hp_bar.update_ap(float(combat_stats.ap_current) / float(combat_stats.ap_max))


## 一次性刷新头顶 HP + AP + 属性条。
func refresh_overhead_bars() -> void:
	refresh_hp_bar()
	refresh_ap_bar()
	if _hp_bar and combat_stats:
		_hp_bar.update_element(combat_stats.current_element, combat_stats.current_element_amount)


## 根据等距坐标步进方向确定朝向。
## +x = 右前(SE), -x = 左后(NW), +y = 左前(SW), -y = 右后(NE)
func _facing_from_step(step: Vector2i) -> UnitVisual.Facing:
	if step.x > 0:
		return UnitVisual.Facing.RIGHT_FRONT
	elif step.x < 0:
		return UnitVisual.Facing.LEFT_BACK
	elif step.y > 0:
		return UnitVisual.Facing.LEFT_FRONT
	else:
		return UnitVisual.Facing.RIGHT_BACK


func set_cell(new_cell: Vector2i, tilemap: TileMapLayer) -> void:
	cell = new_cell
	position = tilemap.map_to_local(cell)


func move_along_path(path: Array[Vector2i], tilemap: TileMapLayer) -> void:
	if path.size() < 2 or is_moving:
		return
	is_moving = true
	for i in range(1, path.size()):
		var step := path[i] - path[i - 1]
		_facing = _facing_from_step(step)
		if _visual:
			_visual.set_facing(_facing)
			_visual.play_state(&"move")

		if movement_manager:
			movement_manager.on_tile_exit(path[i - 1], self)
		var target_pos := tilemap.map_to_local(path[i])
		var dist := position.distance_to(target_pos)
		var duration := dist / move_speed
		var tween := create_tween()
		tween.tween_property(self, "position", target_pos, duration)
		await tween.finished

		if movement_manager:
			movement_manager.on_tile_enter(path[i], self)
	if _visual:
		_visual.play_state(&"idle")
	cell = path[path.size() - 1]
	is_moving = false
	move_finished.emit()


func face_towards_cell(target_cell: Vector2i) -> void:
	var step := target_cell - cell
	if step == Vector2i.ZERO:
		return
	_facing = _facing_from_step(step)
	if _visual:
		_visual.set_facing(_facing)
		_visual.play_state(&"idle")


## 追加一条对话记忆。超出 MEMORY_LIMIT 自动丢弃最老的一条。
## entry 建议包含 round / trigger / text 三键。
func append_dialogue_memory(entry: Dictionary) -> void:
	dialogue_memory.append(entry)
	if dialogue_memory.size() > MEMORY_LIMIT:
		dialogue_memory = dialogue_memory.slice(dialogue_memory.size() - MEMORY_LIMIT)
