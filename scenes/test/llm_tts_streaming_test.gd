extends Control
## 流式 LLM + 双向 TTS 联动测试场景。
##
## 选 NPC + 切分策略 + 输入提示 → 按"开始"：LLMClient.stream_chat_completion 逐 token emit，
## 按选定策略累积成 chunk 后 feed 给 ChatterVoiceAdapter.feed_stream（→ 火山 bidi WS）。
##
## 三种切分策略：
##   - 标点切分：尾字 ∈ ，。？！；：\n 立即 flush；累积 ≥ 50 字仍无标点强制 flush（避免退化非流式）
##   - 定长 30 字：buf.length() >= 30 才 flush
##   - 混合：长度 30 或遇标点 whichever first
##
## 关键时间戳显示在 StatusLabel：首 token / 首 feed 延迟，便于对比策略。
## FeedLog 实时显示每次 feed 的 chunk 内容和长度，方便观察策略实际产物。
##
## "开始"按钮的禁用 / 启用：
##   - 按下 → 立即 disabled
##   - LLM 失败 / TTS 未启用 → 立即 enabled
##   - LLM 完成且 TTS 启用 → 等 streaming_done（audio playback 真正播完）才 enabled
##   - cancel → cancel 内部 emit streaming_done，自动 enabled
## 这样防止上一段 audio 还在异步播放时新会话开始，导致跨会话残留串台。
##
## 关键节点（unique_name_in_owner）：
##   %NpcOption %ChunkOption %TtsToggle %PromptEdit %StartBtn %CancelBtn %BackBtn
##   %LlmOutput（RichTextLabel）%FeedLog（RichTextLabel）%StatusLabel

const VoiceMappingScript := preload("res://scripts/tts/voice_mapping.gd")
const NpcPersonasScript := preload("res://scripts/llm/npc_personas.gd")
const LLMClientScript := preload("res://scripts/llm/llm_client.gd")
const ChatterVoiceAdapterScript := preload("res://scripts/tts/chatter_voice_adapter.gd")
const StreamChunkerScript := preload("res://scripts/llm/stream_chunker.gd")

const PUNCT_CHARS := "，。？！；：、,.?!;:\n"
const FIXED_LEN := 30


var _llm: LLMClient = null
var _voice: Node = null
var _chunker = null     # StreamChunker 实例（避免类型标注，class_name 注册时序问题）
var _running: bool = false
var _t0_msec: int = 0
var _first_chunk_msec: int = 0
var _first_feed_msec: int = 0
var _feed_count: int = 0
var _total_chars: int = 0

var _npc_keys: Array[String] = []

@onready var npc_option: OptionButton = %NpcOption
@onready var chunk_option: OptionButton = %ChunkOption
@onready var tts_toggle: CheckBox = %TtsToggle
@onready var prompt_edit: TextEdit = %PromptEdit
@onready var start_btn: Button = %StartBtn
@onready var cancel_btn: Button = %CancelBtn
@onready var back_btn: Button = %BackBtn
@onready var llm_output: RichTextLabel = %LlmOutput
@onready var feed_log: RichTextLabel = %FeedLog
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	_llm = LLMClientScript.new()
	add_child(_llm)
	_voice = ChatterVoiceAdapterScript.new()
	add_child(_voice)
	_llm.stream_chunk_received.connect(_on_llm_chunk)
	_llm.stream_finished.connect(_on_llm_finished)
	_voice.stream_failed.connect(_on_tts_failed)
	# audio 真正播完时 emit streaming_done（finish_streaming 后等 SDK drain，cancel 后立即）
	_voice.streaming_done.connect(_on_voice_streaming_done)
	_populate_npc_options()
	_populate_chunk_options()
	start_btn.pressed.connect(_on_start_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	if ApiConfig.TTS_API_KEY.is_empty():
		tts_toggle.button_pressed = false
		tts_toggle.disabled = true
		tts_toggle.text = "启用 TTS（ApiConfig 未填 TTS_API_KEY，已禁用）"
	if ApiConfig.LLM_API_KEY.is_empty():
		_set_status("ApiConfig.LLM_API_KEY 未填，无法测试", Color(1, 0.5, 0.5))
		start_btn.disabled = true
	else:
		_set_status("准备就绪。选 NPC 和策略，按▶ 开始流式。", Color(0.7, 0.85, 0.7))


func _populate_npc_options() -> void:
	npc_option.clear()
	_npc_keys.clear()
	var keys: Array = (NpcPersonasScript.PERSONAS as Dictionary).keys()
	keys.sort()
	for unit_id_v: Variant in keys:
		var unit_id := str(unit_id_v)
		# 只列同时在 personas + voice_mapping 都登记的 NPC
		if not (VoiceMappingScript.VOICES as Dictionary).has(unit_id):
			continue
		var persona: Dictionary = (NpcPersonasScript.PERSONAS as Dictionary)[unit_id]
		var voice_cfg: Dictionary = (VoiceMappingScript.VOICES as Dictionary)[unit_id]
		npc_option.add_item("%s（%s）" % [persona.get("name", unit_id), voice_cfg.get("label", "?")])
		_npc_keys.append(unit_id)
	# 默认选李春
	for i in _npc_keys.size():
		if _npc_keys[i] == "hero_li_chun":
			npc_option.select(i)
			break


func _populate_chunk_options() -> void:
	chunk_option.clear()
	chunk_option.add_item("0: 按标点切分")
	chunk_option.add_item("1: 定长 30 字")
	chunk_option.add_item("2: 混合（30 字或标点）")
	chunk_option.select(2)


func _on_start_pressed() -> void:
	if _running:
		return
	var prompt := prompt_edit.text.strip_edges()
	if prompt.is_empty():
		_set_status("提示词为空", Color(1, 0.5, 0.5))
		return
	if npc_option.selected < 0 or npc_option.selected >= _npc_keys.size():
		_set_status("未选 NPC", Color(1, 0.5, 0.5))
		return
	var unit_id := _npc_keys[npc_option.selected]

	# B: 立刻 disable start_btn，等 streaming_done / 失败路径再 enable
	start_btn.disabled = true
	llm_output.clear()
	feed_log.clear()
	_feed_count = 0
	_total_chars = 0
	_t0_msec = Time.get_ticks_msec()
	_first_chunk_msec = 0
	_first_feed_msec = 0
	_chunker = StreamChunkerScript.new(chunk_option.selected)
	_running = true

	# 1) 先开 TTS 流（如果启用），再发 LLM 请求——首 token 来了立刻能 feed
	if tts_toggle.button_pressed and not ApiConfig.TTS_API_KEY.is_empty():
		var voice_cfg: Dictionary = VoiceMappingScript.get_voice(unit_id)
		var voice: String = voice_cfg.get("voice", "")
		if not voice.is_empty():
			var ok: bool = await _voice.start_stream_with_voice(voice, {})
			if not _running:           # 启动期间被取消
				return
			if not ok:
				_set_status("TTS 启动失败，仅显示文字流", Color(1, 0.7, 0.4))
		else:
			_set_status("voice 为空，仅显示文字流", Color(1, 0.7, 0.4))

	# 2) 发 LLM 流式请求
	var persona: Dictionary = (NpcPersonasScript.PERSONAS as Dictionary)[unit_id]
	var system_prompt := "你扮演 %s。%s\n说话风格：%s\n请直接说话，不要旁白动作描写，不要使用括号。回答控制在 200 字以内。" % [
		persona.get("name", unit_id),
		persona.get("persona", ""),
		persona.get("style", ""),
	]
	var messages: Array = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": prompt},
	]
	var ok2: bool = _llm.stream_chat_completion(messages, {"temperature": 0.85, "max_tokens": 250})
	if not ok2:
		_set_status("LLM 启动失败", Color(1, 0.5, 0.5))
		_running = false
		if _voice.is_stream_active():
			_voice.cancel()       # 会 emit streaming_done → _on_voice_streaming_done 启用按钮
		else:
			start_btn.disabled = false


func _on_llm_chunk(text: String) -> void:
	if not _running:
		return
	if _first_chunk_msec == 0:
		_first_chunk_msec = Time.get_ticks_msec()
	llm_output.append_text(text)
	_total_chars += text.length()
	if _chunker == null:
		return
	var chunks: Array = _chunker.push(text)
	for c in chunks:
		_log_feed(c)               # C: 记录每次 feed 的内容
		if _voice.is_stream_active():
			if _first_feed_msec == 0:
				_first_feed_msec = Time.get_ticks_msec()
			_voice.feed_stream(c)
			_feed_count += 1
	_refresh_status()


func _on_llm_finished(_full: String, ok: bool, err: String) -> void:
	# 把残余 buffer flush 出去再 finish 流式
	var had_tail := false
	if _chunker != null:
		var tail: String = _chunker.flush_remaining()
		if not tail.is_empty():
			_log_feed(tail, true)
			if _voice.is_stream_active():
				if _first_feed_msec == 0:
					_first_feed_msec = Time.get_ticks_msec()
				_voice.feed_stream(tail)
				_feed_count += 1
				had_tail = true
	# B: 决定是否需要等 audio 播完再启用 start_btn
	var need_wait_audio: bool = _voice.is_stream_active()
	if need_wait_audio:
		_voice.finish_stream()    # streaming_done 由 SDK drain 完后自然触发
	_running = false
	if not ok:
		_set_status("LLM 失败: %s" % err, Color(1, 0.5, 0.5))
		if not need_wait_audio:
			start_btn.disabled = false
		return
	var t := (Time.get_ticks_msec() - _t0_msec) / 1000.0
	var first_chunk_lat := -1.0
	if _first_chunk_msec > 0:
		first_chunk_lat = (_first_chunk_msec - _t0_msec) / 1000.0
	var first_feed_lat := -1.0
	if _first_feed_msec > 0:
		first_feed_lat = (_first_feed_msec - _t0_msec) / 1000.0
	var tail_note := "（含尾段）" if had_tail else ""
	_set_status(
		"[完成 LLM] %.1fs / %d 字 / 首 token %.2fs / 首 feed %.2fs / feed×%d / 模式: %s%s%s" %
		[t, _total_chars, first_chunk_lat, first_feed_lat, _feed_count,
		 chunk_option.get_item_text(chunk_option.selected), tail_note,
		 "（等 audio 播完）" if need_wait_audio else ""],
		Color(0.7, 1, 0.7))
	if not need_wait_audio:
		start_btn.disabled = false


## audio playback 完全结束（finish_stream 后 SDK drain 完成 / cancel 后立即 emit）。
## B: 这是 start_btn 重新启用的最终时机，避免上次 audio 还在播时新会话开始导致串台。
func _on_voice_streaming_done() -> void:
	# 仅在 LLM 已结束的"等待 audio 播完"阶段才启用按钮；
	# 若 _running == true 说明是中途 cancel 触发的 streaming_done，cancel 自己已处理 enable
	if not _running and start_btn.disabled:
		start_btn.disabled = false
		# 状态栏追加一行 audio 完成时间
		var t := (Time.get_ticks_msec() - _t0_msec) / 1000.0
		_set_status(status_label.text + "  ✓ audio 播完 %.1fs" % t, Color(0.7, 1, 0.7))


func _on_tts_failed(reason: String) -> void:
	_set_status("[TTS 失败] %s（继续显示 LLM 文字）" % reason, Color(1, 0.7, 0.4))


func _on_cancel_pressed() -> void:
	# 三种活跃状态都要能取消：LLM 流式中、TTS 流式 session 进行中、audio 还在异步播放
	var has_active: bool = _running or _voice.is_stream_active() or _voice.is_streaming()
	if not has_active:
		return
	# 顺序：先停 TTS（cancel 会同步 emit streaming_done → 启用 start_btn），再 abort LLM
	if _voice != null:
		_voice.cancel()
	if _llm != null:
		_llm.abort_stream()
	_chunker = null
	_running = false
	# 兜底：上面的 cancel 通常已经通过 streaming_done 启用按钮，这里保险再开一次
	start_btn.disabled = false
	_set_status("已取消", Color(0.85, 0.85, 0.85))


func _on_back_pressed() -> void:
	if _voice != null:
		_voice.cancel()
	if _llm != null:
		_llm.abort_stream()
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


func _exit_tree() -> void:
	if _voice != null:
		_voice.cancel()
	if _llm != null:
		_llm.abort_stream()


func _refresh_status() -> void:
	if not _running:
		return
	var t := (Time.get_ticks_msec() - _t0_msec) / 1000.0
	var first_lat := "未到"
	if _first_chunk_msec > 0:
		first_lat = "%.2fs" % ((_first_chunk_msec - _t0_msec) / 1000.0)
	_set_status("[流式中] %.1fs / %d 字 / 首 token %s / feed×%d" % [t, _total_chars, first_lat, _feed_count],
		Color(0.7, 0.85, 1))


## C: 把每次 feed 的 chunk 内容追加到 FeedLog。is_tail=true 时标黄表示尾段（LLM finish 后的残余 flush）。
func _log_feed(chunk: String, is_tail: bool = false) -> void:
	if feed_log == null:
		return
	var color := "#ffd24a" if is_tail else "#a8e0ff"
	var label := "尾" if is_tail else str(_feed_count + 1)
	var t := (Time.get_ticks_msec() - _t0_msec) / 1000.0
	# BBCode 转义：把方括号转成圆括号显示，避免误解析为标签
	var safe := chunk.replace("[", "(").replace("]", ")").replace("\n", "\\n")
	feed_log.append_text(
		"[color=%s][%s] %.2fs (%d字)[/color] %s\n" % [color, label, t, chunk.length(), safe]
	)


func _set_status(msg: String, color: Color = Color.WHITE) -> void:
	status_label.text = msg
	status_label.add_theme_color_override("font_color", color)
