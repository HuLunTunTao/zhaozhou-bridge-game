class_name TutorialStep
extends Resource

## 单步教程声明（Step 4.1）。
## 把「对话 → 提示 → 等玩家做一步」的教程原子步声明成资源，
## 由 TutorialRunner.run_steps 按序驱动；教程文案 / 等待条件可脱离步进代码维护。
## 对话行 schema：{"speaker": String（缺省「李春」）, "text": String, "can_skip": bool}。

## 本步放完对话后的等待方式。
enum WaitMode {
	## 对话放完即进下一步（不额外等待）。
	DIALOGUE_DONE,
	## 等 wait_signal 触发一次（等价 `await <signal>`）。
	SIGNAL,
	## 等 wait_signal 触发直到 wait_predicate 成立（等价 `while not cond: await <signal>`）。
	PREDICATE,
}

## hint_target_cell 的「未指定」哨兵（地图 cell 可为负，不能拿 (-1,-1) 之类当哨兵）。
const NO_CELL := Vector2i(-32768, -32768)

## 步骤 id（调试 / 日志用）。
@export var step_id: String = ""
## 对话行（{"speaker", "text", "can_skip"}；speaker 缺省「李春」，走 _lc_line 保留预生成 TTS）。
@export var dialogue: Array[Dictionary] = []
## 提示文本（空串 = 不弹 Notify.hint）。
@export var hint: String = ""
## 提示停留秒数（Notify.hint 的 duration）。
@export var hint_duration: float = 2.5
## 对话放完后的等待方式。
@export var wait_mode: WaitMode = WaitMode.DIALOGUE_DONE
## 等待的信号名（wait_mode == SIGNAL / PREDICATE 时必填）。
@export var wait_signal: StringName = &""
## 提示目标格（可选；步进引擎不额外绘制，留给任务标记 / 高亮等后续组件）。
@export var hint_target_cell: Vector2i = NO_CELL

## wait_mode == PREDICATE 的完成条件。Callable 不能导出，只能在代码里装配。
## 签名 `func(args: Array) -> bool`：args 为 wait_signal 的实参列表（入口预检时为空 []），
## 循环等价 `while not wait_predicate.call(args): await wait_signal`。
var wait_predicate: Callable = Callable()


## 快捷构造（对话行直接传字典字面量数组即可）。
static func create(
	p_step_id: String,
	p_dialogue: Array[Dictionary],
	p_hint: String = "",
	p_hint_duration: float = 2.5,
	p_wait_mode: WaitMode = WaitMode.DIALOGUE_DONE,
	p_wait_signal: StringName = &"",
	p_wait_predicate: Callable = Callable(),
) -> TutorialStep:
	var step := TutorialStep.new()
	step.step_id = p_step_id
	step.dialogue = p_dialogue
	step.hint = p_hint
	step.hint_duration = p_hint_duration
	step.wait_mode = p_wait_mode
	step.wait_signal = p_wait_signal
	step.wait_predicate = p_wait_predicate
	return step
