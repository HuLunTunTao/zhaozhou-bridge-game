extends Control
## 对话系统测试场景。按空格/左键启动示例对话。

const DialogueBoxScene := preload("res://scenes/ui/dialogue_box.tscn")

var _stag_tex: Texture2D
var _wolf_tex: Texture2D
var _running := false


func _ready() -> void:
	_stag_tex = load("res://assets/thepixeltiles/critters/stag/critter_stag_NE_idle.png")
	_wolf_tex = load("res://assets/thepixeltiles/critters/wolf/wolf-all.png")


func _unhandled_input(event: InputEvent) -> void:
	if _running:
		return
	var accept := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER]:
			accept = true
	if accept:
		get_viewport().set_input_as_handled()
		_start_demo()


func _start_demo() -> void:
	_running = true

	var lines: Array[DialogueLine] = [
		DialogueLine.create("李春", "赵郡有河，名曰洨水，春秋涨溢，每逢雨季便阻断南北交通。", _stag_tex, "left"),
		DialogueLine.create("李春", "我决意在此修建一座石桥，使百姓不再受困于洪水。", _stag_tex, "left"),
		DialogueLine.create("工匠", "李工，此河宽逾三十丈，若用多孔桥恐怕根基不稳……", _wolf_tex, "right"),
		DialogueLine.create("李春", "所以我要造一座单孔大弧拱桥，以巨石为券，跨河而过！", _stag_tex, "left"),
		DialogueLine.create("", "（众人面面相觑，不知此法是否可行……）"),
		DialogueLine.create("李春", "诸位放心，我已经反复推算。这座桥，[b]一定能建成[/b]。", _stag_tex, "left"),
	]

	var box: DialogueBox = DialogueBoxScene.instantiate()
	add_child(box)
	box.start(lines)
	await box.dialogue_finished

	_running = false
