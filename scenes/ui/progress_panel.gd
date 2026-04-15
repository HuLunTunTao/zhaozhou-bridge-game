class_name ProgressPanel
extends CanvasLayer

signal closed

@export var show_debug_controls := false

@onready var level_list: VBoxContainer = %LevelList
@onready var equipped_count_label: Label = %EquippedCountLabel
@onready var skill_list: VBoxContainer = %SkillList
@onready var debug_row: HBoxContainer = %DebugRow
@onready var unlock_all_button: Button = %UnlockAllButton
@onready var reset_button: Button = %ResetButton
@onready var preset_box: OptionButton = %PresetBox


func _ready() -> void:
	layer = 96
	Progress.progress_changed.connect(_rebuild, CONNECT_REFERENCE_COUNTED)
	_rebuild()
	for button in find_children("*", "BaseButton", true, false):
		UiSounds.bind_button(button as BaseButton)
	debug_row.visible = show_debug_controls


func _unhandled_input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		_close()


func _rebuild() -> void:
	_rebuild_levels()
	_rebuild_skills()
	_rebuild_debug_presets()


func _rebuild_levels() -> void:
	for child in level_list.get_children():
		child.queue_free()
	for row in Progress.get_level_summary():
		var label := Label.new()
		var state := "未解锁"
		if row["completed"]:
			state = "已完成"
		elif row["unlocked"]:
			state = "已解锁"
		label.text = "%s  %s" % [row["level_name"], state]
		level_list.add_child(label)


func _rebuild_skills() -> void:
	for child in skill_list.get_children():
		child.queue_free()
	var equipped_ids := Progress.get_equipped_skill_ids()
	equipped_count_label.text = "已装备 %d / %d" % [equipped_ids.size(), Progress.MAX_EQUIPPED_SKILLS]

	for skill_id in Progress.get_unlocked_skill_ids():
		var skill := Progress.get_skill_resource(skill_id)
		if skill == null:
			continue
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if Progress.is_stage_limited_skill(skill_id):
			var badge := Label.new()
			badge.text = "%s  [关卡限定]" % skill.skill_name
			badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(badge)
		else:
			var toggle := CheckButton.new()
			toggle.text = skill.skill_name
			toggle.button_pressed = skill_id in equipped_ids
			toggle.toggled.connect(_on_skill_toggled.bind(skill_id, toggle))
			row.add_child(toggle)

		var meta := Label.new()
		meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meta.text = "AP%d  %s" % [skill.ap_cost, skill.description]
		meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(meta)
		skill_list.add_child(row)


func _rebuild_debug_presets() -> void:
	if preset_box.item_count > 0:
		return
	preset_box.add_item("测试预设")
	preset_box.add_item("第一关后")
	preset_box.add_item("第二关后")
	preset_box.add_item("第三关后")


func _on_skill_toggled(pressed: bool, skill_id: String, toggle: CheckButton) -> void:
	var ok := Progress.set_skill_equipped(skill_id, pressed)
	if not ok:
		toggle.button_pressed = not pressed
		Notify.notify("李春最多只能装备 4 个自选技能", Notify.Position.TOP_CENTER, Notify.Style.WARNING, 2.0)
	_rebuild()


func _on_unlock_all_pressed() -> void:
	Progress.unlock_all_progress()
	Notify.notify("已解锁全部章节与技能", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.0)


func _on_reset_pressed() -> void:
	Progress.reset_progress()
	Notify.notify("进度已重置", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.0)


func _on_apply_preset_pressed() -> void:
	match preset_box.selected:
		1:
			Progress.apply_debug_stage_preset("关卡1-2")
		2:
			Progress.apply_debug_stage_preset("关卡1-3")
		3:
			Progress.apply_debug_stage_preset("关卡1-4")
		_:
			return
	Notify.notify("测试预设已应用", Notify.Position.TOP_CENTER, Notify.Style.SUCCESS, 2.0)


func _on_close_pressed() -> void:
	_close()


func _close() -> void:
	closed.emit()
	queue_free()
