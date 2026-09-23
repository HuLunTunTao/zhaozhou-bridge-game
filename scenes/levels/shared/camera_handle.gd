class_name CameraHandle
extends RefCounted

## LevelCamera.input_enabled 快照/恢复。
## 嵌套计数由 LevelStateMachine 维护，本类只管"当前这一层"的 set/restore。
## 不假设原值为 true：原值 false 时 lock 后仍是 false，unlock 后仍是 false。

var _get_camera: Callable = Callable()
var _saved_input_enabled: bool = true


## 绑定"如何取到 LevelCamera"的 Callable。之后 lock_input/unlock_input 无参调用。
func setup(get_camera: Callable) -> void:
	_get_camera = get_camera


## 记录当前 input_enabled 并置 false。重复调用会覆盖快照（由上层嵌套计数防重入）。
func lock_input() -> void:
	var cam: Variant = _resolve_camera()
	if cam == null:
		return
	_saved_input_enabled = cam.input_enabled
	cam.input_enabled = false


## 恢复 lock_input 时保存的 input_enabled 值。
func unlock_input() -> void:
	var cam: Variant = _resolve_camera()
	if cam == null:
		return
	cam.input_enabled = _saved_input_enabled


func _resolve_camera() -> Variant:
	if not _get_camera.is_valid():
		return null
	var cam: Variant = _get_camera.call()
	if cam != null and "input_enabled" in cam:
		return cam
	return null
