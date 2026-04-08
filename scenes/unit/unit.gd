@tool
class_name Unit
extends Node2D

signal move_finished

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
## 本回合是否已行动。
var has_acted: bool = false

## 当前朝向前缀，用于拼接动画名。
var _facing: StringName = &"right_front"
## 头顶血条。
var _hp_bar: UnitHpBar = null


func _ready() -> void:
	_make_sprite_frames_unique()
	_apply_color()
	_play_anim(&"idle")
	_init_combat_stats()
	_init_hp_bar()


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
	_hp_bar = UnitHpBar.new()
	_hp_bar.z_index = 10
	_hp_bar.y_sort_enabled = false
	add_child(_hp_bar)


## 刷新血条显示。外部在伤害/治疗后调用。
func refresh_hp_bar() -> void:
	if _hp_bar and combat_stats:
		_hp_bar.update_hp(float(combat_stats.current_hp) / float(combat_stats.max_hp))


## 让 SpriteFrames 资源唯一化，避免修改颜色时影响其他单位实例。
func _make_sprite_frames_unique() -> void:
	var visual := get_node_or_null("Visual")
	if visual is AnimatedSprite2D:
		var sprite := visual as AnimatedSprite2D
		if sprite.sprite_frames:
			sprite.sprite_frames = sprite.sprite_frames.duplicate()


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
