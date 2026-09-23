class_name ModalPanel
extends CanvasLayer
## 模态面板基类（CanvasLayer）。统一四份面板里的三套样板：
##
##   1. ESC 关闭 handler —— 基类 `_unhandled_input` 拦 KEY_ESCAPE → `_request_close()`。
##   2. emit-and-free 收尾 —— `_request_close`：设 `result` → emit `closed` →
##      `_emit_result_signal`（子类带参结果信号）→ `queue_free`。`closed`（0 参）
##      与 `_open_overlay` 的默认 `closed_signal = &"closed"` 天然对接。
##   3. setter-before-ready 的 pending 缓存 —— `_cache_or_render`：ready 前把
##      value + renderer 存进 `_pending`，节点 `ready` 后自动 `_flush_pending`。
##
## 子类约定：
##   - 有带参结果信号（向后兼容旧调用点）→ override `_emit_result_signal(result)`，
##     在里面 emit 自己的信号；同时保留基类 `result` 字段供新调用点读取。
##   - 取消 / ESC 的默认 result 不是 null → override `_default_cancel_result()`。
##   - 可以自由 override `_ready()`，不必调 super（pending 由 `ready` 信号自动 flush）。
##   - 需要吃掉全部输入（thinking_overlay）→ override `_unhandled_input` 并自行
##     set_input_as_handled，不要调 super。
##   - `_request_close(close_result)` 的实参优先；为 null 时回落 `_default_cancel_result()`。
##
## 用法：
##   class_name MyPanel
##   extends ModalPanel
##
##   signal picked(text: String)
##
##   func _default_cancel_result() -> Variant: return ""
##   func _emit_result_signal(r: Variant) -> void: picked.emit(String(r))
##   func set_message(m: String) -> void:
##       _cache_or_render("message", m, func(v): _label.text = String(v))

signal closed

## 本次关闭的结果。0 参面板可忽略；带参面板也可以只用自己 emit 的带参信号（向后兼容）。
var result: Variant = null

var _pending: Dictionary = {}
var _ready_done := false
var _closing := false


func _init() -> void:
	ready.connect(_on_node_ready, CONNECT_ONE_SHOT)


func _on_node_ready() -> void:
	_ready_done = true
	_flush_pending()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_request_close()
		get_viewport().set_input_as_handled()


## 子类收尾统一出口。幂等：重复调用只生效一次。
func _request_close(close_result: Variant = null) -> void:
	if _closing:
		return
	_closing = true
	result = _default_cancel_result() if close_result == null else close_result
	closed.emit()
	_emit_result_signal(result)
	queue_free()


## ESC / 无参关闭时写入 `result` 的默认值。子类按需 override（如 topic_menu 的 ""）。
func _default_cancel_result() -> Variant:
	return null


## 子类 override：用 close_result emit 自己的带参结果信号（向后兼容旧调用点）。
func _emit_result_signal(_close_result: Variant) -> void:
	pass


## setter-before-ready 通用缓存。节点 ready 后直接 `renderer.call(value)`；
## ready 前存进 `_pending`，节点 ready 后自动 flush。
## 返回 true 表示本次只是缓存、尚未渲染。
func _cache_or_render(key: String, value: Variant, renderer: Callable) -> bool:
	if _ready_done:
		renderer.call(value)
		return false
	_pending[key] = [value, renderer]
	return true


## 清掉 `_pending` 并按存下的 renderer 逐个渲染。节点 ready 后自动调；一般无需手动调。
func _flush_pending() -> void:
	for key in _pending.keys():
		var entry: Array = _pending[key]
		(entry[1] as Callable).call(entry[0])
	_pending.clear()
