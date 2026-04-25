extends Control
## 高级对话测试场景：用预设的多角色对话演示 dialogue_box + 头像底板 + TTS 全链路效果。
## 不调 LLM（避免 token 消耗），台词全是写死的，专注验证视觉 + 配音。
##
## 用法：F6 跑 scenes/test/advanced_dialogue_test.tscn，或主菜单"测试"面板 →「高级对话」
## 每个场景按一下按钮播一遍。TTS 优先走火山（需 ApiConfig.TTS_API_KEY），失败回落到
## 系统 TTS 或纯静默；视觉无论如何都有效。

const VoiceMappingScript := preload("res://scripts/tts/voice_mapping.gd")
const VolcengineTTSClientScript := preload("res://scripts/tts/volcengine_tts_client.gd")
const NpcPersonasScript := preload("res://scripts/llm/npc_personas.gd")
# ApiConfig 是 class_name，全局可访问，无需 preload
const DialogueBoxScene := preload("res://scenes/ui/dialogue_box.tscn")

const BG_YELLOW := preload("res://assets/face_background/yellow.png")
const BG_GREEN := preload("res://assets/face_background/green.png")
const BG_RED := preload("res://assets/face_background/red.png")

## unit_id → visual 场景路径。test 场景里没有 Unit 节点，需要手工实例化视觉来取 idle 第 0 帧。
const UNIT_VISUALS: Dictionary = {
	"hero_li_chun":          "res://scenes/unit/visual/human/li_chun/li_chun_visual.tscn",
	"craftsman_guard":       "res://scenes/unit/visual/human/工匠/工匠_visual.tscn",
	"survey_worker":         "res://scenes/unit/visual/human/测量工/测量工_visual.tscn",
	"bank_mud_wraith":       "res://scenes/unit/visual/monster/坍岸泥鬼/坍岸泥鬼_visual.tscn",
	"dark_current":          "res://scenes/unit/visual/monster/暗涌/暗涌_visual.tscn",
	"drift_log_pack":        "res://scenes/unit/visual/monster/浮木群/浮木群_visual.tscn",
	"flood_driftwood_pack":  "res://scenes/unit/visual/monster/漂木群洪水版/漂木群洪水版_visual.tscn",
	"flood_spear":           "res://scenes/unit/visual/monster/洪峰/洪峰_visual.tscn",
	"heavy_pier_statue":     "res://scenes/unit/visual/monster/重墩石像/重墩石像_visual.tscn",
	"high_arch_phantom":     "res://scenes/unit/visual/monster/高拱幻影/高拱幻影_visual.tscn",
	"old_method_supervisor": "res://scenes/unit/visual/monster/旧制监工/旧制监工_visual.tscn",
	"pier_gnawer":           "res://scenes/unit/visual/monster/桥台噬者/桥台噬者_visual.tscn",
	"rule_guard_head":       "res://scenes/unit/visual/monster/守法匠首/守法匠首_visual.tscn",
	"siltmare":              "res://scenes/unit/visual/monster/泥沙魇/泥沙魇_visual.tscn",
	"whirl_pool":            "res://scenes/unit/visual/monster/水旋/水旋_visual.tscn",
	"wrathful_flood":        "res://scenes/unit/visual/monster/怒水/怒水_visual.tscn",
}

## 5 个预设场景。每条 line 是 [unit_id, text]；最后那条 dismiss 用文本估算。
const SCENARIOS: Array = [
	{
		"label": "① 李春独白",
		"desc":  "主角单人发言。李春画像 + 黄底，左侧。",
		"lines": [
			["hero_li_chun", "依老朽看，这桥要成，须得脚下踩稳。"],
		],
	},
	{
		"label": "② 工匠应答",
		"desc":  "李春布置 + 工匠应答。两人都左侧（友方），交替显示。",
		"lines": [
			["hero_li_chun", "石料按图分三层，从底券起。"],
			["craftsman_guard", "成不成，老规矩——手上见。"],
		],
	},
	{
		"label": "③ 敌方挑衅",
		"desc":  "高拱幻影质疑，李春回怼。一右一左。",
		"lines": [
			["high_arch_phantom", "一道拱跨三十丈？当真？你撑得住么。"],
			["hero_li_chun", "由不得你来质疑。"],
		],
	},
	{
		"label": "④ 邻接闲聊（敌我）",
		"desc":  "暗涌阴语，测量工虚张声势。展示左右切换 + 颜色对比。",
		"lines": [
			["dark_current", "……脚下凉么。"],
			["survey_worker", "三尺七寸，按尺绳看，再涨我就撤。"],
		],
	},
	{
		"label": "⑤ 群魔乱舞",
		"desc":  "四个怪物连续发声，验证多音色 + 长对话节奏。",
		"lines": [
			["flood_spear", "来！让道！"],
			["whirl_pool", "下来下来下来。"],
			["siltmare", "……埋了吧……埋多好……"],
			["wrathful_flood", "吞没。归水。"],
		],
	},
]

var _tts: Node = null
var _busy: bool = false

@onready var scenario_list: VBoxContainer = %ScenarioList
@onready var status_label: Label = %StatusLabel
@onready var tts_toggle: CheckBox = %TtsToggle
@onready var back_btn: Button = %BackBtn


func _ready() -> void:
	_tts = VolcengineTTSClientScript.new()
	add_child(_tts)
	tts_toggle.button_pressed = not ApiConfig.TTS_API_KEY.is_empty()
	tts_toggle.disabled = ApiConfig.TTS_API_KEY.is_empty()
	if ApiConfig.TTS_API_KEY.is_empty():
		tts_toggle.text = "启用火山 TTS（ApiConfig 未填 Key，已禁用，将回落到系统 TTS / 静默）"
	back_btn.pressed.connect(_on_back_pressed)
	_build_scenario_buttons()
	_set_status("准备就绪。挑一个场景按一下。", Color(0.7, 0.85, 0.7))


func _build_scenario_buttons() -> void:
	for child in scenario_list.get_children():
		child.queue_free()
	for scenario_dict: Dictionary in SCENARIOS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var btn := Button.new()
		btn.text = scenario_dict.label
		btn.custom_minimum_size = Vector2(180, 36)
		btn.pressed.connect(_on_scenario_pressed.bind(scenario_dict))
		row.add_child(btn)
		var desc_label := Label.new()
		desc_label.text = scenario_dict.desc
		desc_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
		desc_label.add_theme_font_size_override("font_size", 12)
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(desc_label)
		scenario_list.add_child(row)


func _on_scenario_pressed(scenario_dict: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	_disable_buttons(true)
	var preset_lines: Array = scenario_dict.lines
	var use_tts: bool = tts_toggle.button_pressed and not ApiConfig.TTS_API_KEY.is_empty()
	_set_status("[准备] %s — 共 %d 条。%s" % [
		scenario_dict.label, preset_lines.size(),
		"合成 TTS 中…" if use_tts else "无 TTS 模式（仅视觉 + 估算时长）",
	], Color(0.7, 0.85, 1))

	# 一次性构建所有 DialogueLine（含 portrait + bg + 可选 audio_stream）
	var lines: Array[DialogueLine] = []
	for entry: Array in preset_lines:
		var unit_id: String = entry[0]
		var text: String = entry[1]
		var line := await _make_line(unit_id, text, use_tts)
		if line != null:
			lines.append(line)

	if lines.is_empty():
		_set_status("[失败] 没有可播的对话。", Color(1, 0.5, 0.5))
		_busy = false
		_disable_buttons(false)
		return

	# 算 dismiss_delay：有音频走默认 2.5s（dialogue_box 会按音频长度拉长）；
	# 无音频按文本长度估时（中文 3.5 字/秒 + 1s 缓冲）
	var dismiss_delay := 2.5
	for line in lines:
		if line.audio_stream != null:
			continue
		dismiss_delay = maxf(dismiss_delay, float(line.text.length()) / 3.5 + 1.0)

	_set_status("[播放中] %s" % scenario_dict.label, Color(0.7, 1, 0.85))
	await _play_dialogue(lines, dismiss_delay, use_tts)
	_set_status("[完成] %s 播放结束。" % scenario_dict.label, Color(0.7, 0.85, 0.7))
	_busy = false
	_disable_buttons(false)


## 把 (unit_id, text) 变成完整 DialogueLine：portrait 来自 sprite_frames 第 0 帧，
## bg 按 hero/友/敌三色，name 走 NpcPersonas 的角色名，audio_stream 看 use_tts。
func _make_line(unit_id: String, text: String, use_tts: bool) -> DialogueLine:
	var portrait: Texture2D = _make_portrait(unit_id)
	var data: UnitData = _load_unit_data(unit_id)
	var camp: int = data.camp if data else Enums.Camp.ALLY
	var is_hero: bool = unit_id == "hero_li_chun"
	var bg: Texture2D
	var side: String
	if is_hero:
		bg = BG_YELLOW
		side = "left"
	elif camp == Enums.Camp.ENEMY:
		bg = BG_RED
		side = "right"
	else:
		bg = BG_GREEN
		side = "left"
	var persona: Dictionary = NpcPersonasScript.get_persona(unit_id, camp)
	var speaker_name: String = persona.get("name", unit_id)

	var audio_stream: AudioStream = null
	if use_tts:
		var voice_cfg: Dictionary = VoiceMappingScript.get_voice(unit_id, camp)
		var voice: String = voice_cfg.get("voice", "")
		if not voice.is_empty():
			var mp3: PackedByteArray = await _tts.synthesize(text, voice)
			if not mp3.is_empty():
				var stream := AudioStreamMP3.new()
				stream.data = mp3
				audio_stream = stream

	return DialogueLine.create(speaker_name, text, portrait, side, bg, audio_stream)


## 把 unit visual 实例化、取 idle 朝右动画第 0 帧、再 free 掉。
func _make_portrait(unit_id: String) -> Texture2D:
	var path: String = UNIT_VISUALS.get(unit_id, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var inst := ps.instantiate() as UnitVisual
	if inst == null:
		return null
	add_child(inst)
	inst.visible = false
	var sf: SpriteFrames = inst.sprite_frames
	var anim: StringName = inst.get_idle_right_anim_name() if sf else StringName("")
	var tex: Texture2D = null
	if sf != null and anim != StringName(""):
		tex = sf.get_frame_texture(anim, 0)
	inst.queue_free()
	return tex


func _load_unit_data(unit_id: String) -> UnitData:
	var path := "res://data/units/%s.tres" % unit_id
	if not ResourceLoader.exists(path):
		return null
	return load(path) as UnitData


## 弹一个 dialogue_box 把 lines 走完。auto_dismiss=true，无需点击。
## TTS：lines 里的 audio_stream 已在 _make_line 里塞好（火山合成）；
## 没填 key / 火山失败 → audio_stream=null → 静默播放，dismiss_delay 已按文本估算拉长。
func _play_dialogue(lines: Array[DialogueLine], dismiss_delay: float, _used_volcengine: bool) -> void:
	var box = DialogueBoxScene.instantiate()
	add_child(box)
	box.start(lines, true, dismiss_delay)
	await box.dialogue_finished


func _disable_buttons(disabled: bool) -> void:
	for row in scenario_list.get_children():
		for child in row.get_children():
			if child is Button:
				child.disabled = disabled
	tts_toggle.disabled = disabled or ApiConfig.TTS_API_KEY.is_empty()


func _set_status(msg: String, color: Color = Color.WHITE) -> void:
	status_label.text = msg
	status_label.add_theme_color_override("font_color", color)


func _on_back_pressed() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_stop()
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
