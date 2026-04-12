@tool
class_name Unit
extends Node2D

const OUTLINE_COLOR_HERO := Color(1.0, 1.0, 0.0, 0.5)   # 黄色
const OUTLINE_COLOR_ALLY := Color(0.0, 1.0, 0.0, 0.5)   # 绿色
const OUTLINE_COLOR_ENEMY := Color(1.0, 0.0, 0.0, 0.5)  # 红色

signal move_finished
## 单位死亡时发出（HP 降为 0，退场动画播完后触发）。
signal died
## 单位被右键点击时发出。
signal clicked

@export var movement_points: int = 10
@export var move_speed: float = 100.0  # pixels per second
## 单位数据（在编辑器中指定 .tres 文件）。
@export var unit_data: UnitData
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


func _update_acted_visual() -> void:
	if not is_inside_tree():
		return
	var visual := get_node_or_null("Visual")
	if visual:
		if has_acted:
			visual.modulate = Color(0.5, 0.5, 0.55, 0.75)
		else:
			visual.modulate = Color.WHITE

## 当前朝向前缀，用于拼接动画名。
var _facing: StringName = &"right_front"
## 头顶血条。
var _hp_bar: UnitHpBar = null


func _ready() -> void:
	_make_sprite_frames_unique()
	_make_outline_material_unique()
	_apply_color()
	_play_anim(&"idle")
	_init_combat_stats()
	_init_hp_bar()
	_init_click_button()


## 从 unit_data 初始化 combat_stats。
func _init_combat_stats() -> void:
	if Engine.is_editor_hint():
		return
	if unit_data:
		combat_stats = CombatStats.new()
		combat_stats.init_from(unit_data)
		movement_points = combat_stats.ap_current


## 初始化头顶血条。
func _init_hp_bar() -> void:
	if Engine.is_editor_hint():
		return
	_hp_bar = get_node_or_null("HpBar") as UnitHpBar
	if _hp_bar and combat_stats:
		_hp_bar.update_element(combat_stats.current_element, combat_stats.current_element_amount)


## 初始化透明点击按钮（不再拦截左键，选择改由地块点击处理）。
func _init_click_button() -> void:
	if Engine.is_editor_hint():
		return
	var btn := get_node_or_null("Button") as Button
	if btn:
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE


## 根据阵营设置描边颜色。主角黄色，友方绿色，敌方红色，均 50% alpha。
func apply_faction_outline() -> void:
	var visual := get_node_or_null("Visual")
	if visual == null:
		return
	var mat := visual.material as ShaderMaterial
	if mat == null:
		return
	var color: Color
	if combat_stats and combat_stats.is_hero:
		color = OUTLINE_COLOR_HERO
	elif faction == "好人":
		color = OUTLINE_COLOR_ALLY
	else:
		color = OUTLINE_COLOR_ENEMY
	mat.set_shader_parameter("outline_color", color)


## 单位死亡：播放淡出动画后从场景树移除，并发出 died 信号。
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


## 让 SpriteFrames 资源唯一化，避免修改颜色时影响其他单位实例。
func _make_sprite_frames_unique() -> void:
	var visual := get_node_or_null("Visual")
	if visual is AnimatedSprite2D:
		var sprite := visual as AnimatedSprite2D
		if sprite.sprite_frames:
			sprite.sprite_frames = sprite.sprite_frames.duplicate()


## 让描边材质唯一化，避免修改颜色时影响其他单位实例。
func _make_outline_material_unique() -> void:
	var visual := get_node_or_null("Visual")
	if visual and visual.material is ShaderMaterial:
		visual.material = visual.material.duplicate()


func _apply_color() -> void:
	var visual := get_node_or_null("Visual")
	if visual is AnimatedSprite2D:
		(visual as AnimatedSprite2D).self_modulate = unit_color
	elif visual is Polygon2D:
		(visual as Polygon2D).color = unit_color


## 根据等距坐标步进方向确定朝向。
## +x = 右前(SE), -x = 左后(NW), +y = 左前(SW), -y = 右后(NE)
func _facing_from_step(step: Vector2i) -> StringName:
	if step.x > 0:
		return &"right_front"
	elif step.x < 0:
		return &"left_back"
	elif step.y > 0:
		return &"left_front"
	else:
		return &"right_back"


## 播放当前朝向下的指定状态动画（"idle" 或 "move"）。
func _play_anim(state: StringName) -> void:
	var visual := get_node_or_null("Visual")
	if not visual is AnimatedSprite2D:
		return
	var sprite := visual as AnimatedSprite2D
	var anim_name := StringName(String(_facing) + "_" + String(state))
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim_name):
		sprite.play(anim_name)


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
		_play_anim(&"move")

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
	_play_anim(&"idle")
	cell = path[path.size() - 1]
	is_moving = false
	move_finished.emit()
