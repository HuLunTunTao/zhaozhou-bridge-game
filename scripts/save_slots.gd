extends Node
## Manages the active save slot and slot-scoped user:// data paths.

const MIN_SLOT := 1
const MAX_SLOT := 9
const ACTIVE_SLOT_PATH := "user://active_slot.json"
const LEGACY_SETTINGS_PATH := "user://settings.json"
const LEGACY_PROGRESS_PATH := "user://progress.json"
const SETTINGS_FILE := "settings.json"
const PROGRESS_FILE := "progress.json"

signal active_slot_changed(new_slot: int)

var active_slot: int = MIN_SLOT


func _ready() -> void:
	_migrate_legacy_root_files()
	active_slot = _load_active_slot()
	_save_active_slot()


func is_valid_slot(slot: int) -> bool:
	return slot >= MIN_SLOT and slot <= MAX_SLOT


func get_slot_dir(slot: int = active_slot) -> String:
	return "user://%d" % clampi(slot, MIN_SLOT, MAX_SLOT)


func get_settings_path(slot: int = active_slot) -> String:
	return get_slot_dir(slot).path_join(SETTINGS_FILE)


func get_progress_path(slot: int = active_slot) -> String:
	return get_slot_dir(slot).path_join(PROGRESS_FILE)


func slot_exists(slot: int) -> bool:
	return is_valid_slot(slot) and DirAccess.dir_exists_absolute(get_slot_dir(slot))


func ensure_slot_dir(slot: int = active_slot) -> bool:
	if not is_valid_slot(slot):
		return false
	var root := DirAccess.open("user://")
	if root == null:
		return false
	if not root.dir_exists(str(slot)):
		return root.make_dir(str(slot)) == OK
	return true


func set_active_slot(slot: int, reload_data: bool = true) -> bool:
	if not is_valid_slot(slot):
		return false
	var changed := active_slot != slot
	active_slot = slot
	_save_active_slot()
	if reload_data:
		_reload_active_data()
	if changed:
		active_slot_changed.emit(active_slot)
	return true


func save_current_to_slot(slot: int) -> bool:
	if not is_valid_slot(slot):
		return false
	if not ensure_slot_dir(slot):
		return false
	var changed := active_slot != slot
	active_slot = slot
	_save_active_slot()
	Settings.save_settings()
	Progress.save_progress()
	if changed:
		active_slot_changed.emit(active_slot)
	return true


func load_slot(slot: int) -> bool:
	if not slot_exists(slot):
		return false
	return set_active_slot(slot, true)


func delete_slot(slot: int) -> bool:
	if not is_valid_slot(slot):
		return false
	var ok := true
	if slot_exists(slot):
		ok = _remove_slot_dir(slot)
	if slot == active_slot:
		set_active_slot(MIN_SLOT, true)
	return ok


func clear_all_slot_data() -> void:
	for slot in range(MIN_SLOT, MAX_SLOT + 1):
		if slot_exists(slot):
			_remove_slot_dir(slot)
	_remove_user_file("active_slot.json")
	_remove_user_file(SETTINGS_FILE)
	_remove_user_file(PROGRESS_FILE)
	active_slot = MIN_SLOT
	_save_active_slot()
	active_slot_changed.emit(active_slot)


func _load_active_slot() -> int:
	if not FileAccess.file_exists(ACTIVE_SLOT_PATH):
		return MIN_SLOT
	var file := FileAccess.open(ACTIVE_SLOT_PATH, FileAccess.READ)
	if file == null:
		return MIN_SLOT
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var slot := MIN_SLOT
	if parsed is Dictionary:
		slot = int((parsed as Dictionary).get("active_slot", MIN_SLOT))
	elif parsed is float or parsed is int:
		slot = int(parsed)
	return slot if is_valid_slot(slot) else MIN_SLOT


func _save_active_slot() -> void:
	var file := FileAccess.open(ACTIVE_SLOT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveSlots: 无法保存当前存档位")
		return
	file.store_string(JSON.stringify({"active_slot": active_slot}))
	file.close()


func _reload_active_data() -> void:
	if has_node("/root/Settings"):
		Settings.load_settings()
		Settings.apply_settings()
	if has_node("/root/Progress"):
		Progress.load_progress()
		Progress.normalize_and_save()


func _migrate_legacy_root_files() -> void:
	_migrate_legacy_file(LEGACY_SETTINGS_PATH, get_settings_path(MIN_SLOT), SETTINGS_FILE)
	_migrate_legacy_file(LEGACY_PROGRESS_PATH, get_progress_path(MIN_SLOT), PROGRESS_FILE)


func _migrate_legacy_file(source_path: String, target_path: String, source_name: String) -> void:
	if not FileAccess.file_exists(source_path):
		return
	var migrated := true
	if not FileAccess.file_exists(target_path):
		migrated = ensure_slot_dir(MIN_SLOT) and _copy_file(source_path, target_path)
	if migrated:
		_remove_user_file(source_name)


func _copy_file(source_path: String, target_path: String) -> bool:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return false
	var data := source.get_buffer(source.get_length())
	source.close()
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		return false
	target.store_buffer(data)
	target.close()
	return true


func _remove_slot_dir(slot: int) -> bool:
	var dir_name := str(slot)
	var path := get_slot_dir(slot)
	_remove_dir_contents(path)
	var root := DirAccess.open("user://")
	if root == null:
		return false
	if not root.dir_exists(dir_name):
		return true
	return root.remove(dir_name) == OK


func _remove_dir_contents(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var child_path := path.path_join(file_name)
			if dir.current_is_dir():
				_remove_dir_contents(child_path)
			dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func _remove_user_file(file_name: String) -> void:
	var root := DirAccess.open("user://")
	if root != null and root.file_exists(file_name):
		root.remove(file_name)
