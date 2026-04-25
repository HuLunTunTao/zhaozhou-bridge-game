class_name ChatterScheduler
extends Node
## 单位闲聊调度器。监听 BaseLevel 信号，在合适的时机按概率抽取单位，向 LLM 请求一句
## "进入角色的台词"，然后通过 dialogue_box (auto_dismiss 模式) 飘过。
##
## 三类触发：
##   1. 受击反应 —— 小回合结束时，从本队这回合攻击到的敌方里随机挑一个
##   2. 邻接闲聊 —— 大回合结束时，扫出相邻的两单位，优先敌我混杂对
##   3. 李春观察 —— 大回合结束时，主角对全局战况发一句
##
## 并发策略：单实例 LLMClient 串行。_busy 期间到来的触发直接丢弃（不排队，避免滞后）。

const NpcPersonasScript := preload("res://scripts/llm/npc_personas.gd")
const LLMClientScript := preload("res://scripts/llm/llm_client.gd")
const PortraitResolverScript := preload("res://scripts/llm/portrait_resolver.gd")
const ChatterVoiceScript := preload("res://scripts/tts/chatter_voice.gd")
const ChatterPromptsScript := preload("res://scripts/llm/chatter_prompts.gd")

## 三类触发的概率（0.0–1.0）。调试时可临时拉到 1.0 做强制触发测试。
const TRIGGER_PROB_ATTACKED := 0.45
const TRIGGER_PROB_ADJACENT := 0.35
const TRIGGER_PROB_HERO_OBS := 0.30
## 对话框自动飘过的停留秒数。
const DIALOGUE_DISMISS_DELAY := 3.0
## 邻接对话中，对方回一句的概率。
const ADJACENT_REPLY_PROB := 0.3
## 单条 LLM 请求的超时秒数（比全局 30s 短，避免阻塞过久）。
const LLM_TIMEOUT_SEC := 12.0
## 火山 TTS 不可用时的兜底策略：true → 调用 DisplayServer.tts_speak（系统 TTS）；
## false → 完全不发声。两者都不会让对话失败，只影响是否能听到声。
@export var use_system_tts_fallback: bool = true

## 曼哈顿相邻偏移（4 向）。
const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

var _level: Node = null
var _llm: Node = null
var _voice: Node = null
var _busy: bool = false
## 当前小回合里发生的攻击事件。条目结构：{ victim: Unit, attacker: Unit, skill: SkillData }。
var _attacked_this_turn: Array[Dictionary] = []


## 初始化。由 BaseLevel._on_level_ready 调用一次。
## level 必须是 BaseLevel 实例（鸭子类型），llm_client 是 LLMClient 实例（或 null → 本器自建一个）。
func setup(level: Node, llm_client: Node = null) -> void:
	_level = level
	if llm_client != null:
		_llm = llm_client
	else:
		_llm = LLMClientScript.new()
		add_child(_llm)
	# 闲聊语音通道（火山流式 TTS + 系统 TTS 兜底，独立于 dialogue_box 的预设音频）
	_voice = ChatterVoiceScript.new()
	_voice.use_system_tts_fallback = use_system_tts_fallback
	add_child(_voice)
	# 订阅 BaseLevel 的领域信号
	if _level.has_signal("skill_executed"):
		_level.skill_executed.connect(_on_skill_executed)
	if _level.has_signal("team_turn_started"):
		_level.team_turn_started.connect(_on_team_turn_started)
	if _level.has_signal("team_turn_ended"):
		_level.team_turn_ended.connect(_on_team_turn_ended)
	if _level.has_signal("round_ended"):
		_level.round_ended.connect(_on_round_ended)


# ─────────────────────────────────────────────────────────
# 信号回调
# ─────────────────────────────────────────────────────────

## 技能结算后调用。只有攻击类技能才算"被攻击"。
func _on_skill_executed(caster: Node, skill: Resource, cast_cell: Vector2i) -> void:
	if caster == null or skill == null:
		return
	if not ("skill_type" in skill):
		return
	if skill.skill_type != Enums.SkillType.ATTACK:
		return
	for offset: Vector2i in (skill.effect_offsets if "effect_offsets" in skill else []):
		var hit_cell := cast_cell + offset
		var victim := _find_unit_at_cell(hit_cell)
		if victim == null or victim == caster:
			continue
		if not _is_alive(victim):
			continue
		_attacked_this_turn.append({
			"victim": victim,
			"attacker": caster,
			"skill": skill,
		})


func _on_team_turn_started(_team_index: int) -> void:
	_attacked_this_turn.clear()


func _on_team_turn_ended(_team_index: int) -> void:
	if _busy or _level == null or _level.is_phase_ended():
		return
	if _attacked_this_turn.is_empty():
		return
	if randf() > TRIGGER_PROB_ATTACKED:
		return
	var entry: Dictionary = _attacked_this_turn[randi() % _attacked_this_turn.size()]
	await _do_attacked_reaction(entry)


func _on_round_ended(round_number: int) -> void:
	if _busy or _level == null or _level.is_phase_ended():
		return
	var choices: Array[String] = []
	if randf() < TRIGGER_PROB_ADJACENT:
		choices.append("adjacent")
	if randf() < TRIGGER_PROB_HERO_OBS:
		choices.append("hero_obs")
	if choices.is_empty():
		return
	var choice: String = choices[randi() % choices.size()]
	match choice:
		"adjacent":
			await _do_adjacent_chat(round_number)
		"hero_obs":
			await _do_hero_observation(round_number)


# ─────────────────────────────────────────────────────────
# 具体触发实现
# ─────────────────────────────────────────────────────────

func _do_attacked_reaction(entry: Dictionary) -> void:
	var victim: Node = entry.get("victim")
	if victim == null or not _is_alive(victim):
		return
	var attacker: Node = entry.get("attacker")
	var skill: Resource = entry.get("skill")
	var extra: Dictionary = {
		"attacker_name": _unit_display_name(attacker),
		"skill_name": skill.skill_name if skill and "skill_name" in skill else "未知攻势",
		"hp_percent": _hp_percent(victim),
	}
	await _say(victim, "reaction_to_attack", extra)


func _do_adjacent_chat(round_number: int) -> void:
	var pair: Array = _pick_adjacent_pair()
	if pair.is_empty():
		return
	var a: Node = pair[0]
	var b: Node = pair[1]
	# 70% 概率由阵营混杂对中的友方先开口；纯同阵营对随机先后
	var swap: bool = false
	if _are_different_camps(a, b):
		var a_is_friendly := _is_friendly(a)
		if not a_is_friendly and randf() < 0.7:
			swap = true
	elif randf() < 0.5:
		swap = true
	if swap:
		var tmp := a
		a = b
		b = tmp

	# 第一行：A 先开口，单独对话 + 流式语音
	var line_a: DialogueLine = await _build_line(a, "adjacent_chat", {
		"other_name": _unit_display_name(b),
		"round": round_number,
	})
	if line_a == null:
		return
	await _speak_line(a, line_a)

	# 第二行（30% 概率）：B 接话，独立的对话 + 流式语音
	if randf() < ADJACENT_REPLY_PROB and _is_alive(b):
		var line_b: DialogueLine = await _build_line(b, "adjacent_reply", {
			"other_name": _unit_display_name(a),
			"heard": line_a.text,
			"round": round_number,
		})
		if line_b != null:
			# 互相把对话纳入记忆
			_append_memory(a, {"round": round_number, "trigger": "adjacent_heard", "text": line_b.text})
			_append_memory(b, {"round": round_number, "trigger": "adjacent_heard", "text": line_a.text})
			await _speak_line(b, line_b)


func _do_hero_observation(round_number: int) -> void:
	var hero: Node = _level.hero if "hero" in _level else null
	if hero == null or not _is_alive(hero):
		return
	var objectives: String = ""
	if _level.has_method("get_objectives_text"):
		var obj: Dictionary = _level.get_objectives_text()
		objectives = ChatterPromptsScript.format_objectives(obj)
	await _say(hero, "hero_observation", {
		"objectives": objectives,
		"round": round_number,
	})


# ─────────────────────────────────────────────────────────
# 通用 _say / _build_line：拼 prompt、调 LLM、写 memory、呈现
# ─────────────────────────────────────────────────────────

func _say(unit: Node, trigger_kind: String, extra: Dictionary) -> void:
	var line: DialogueLine = await _build_line(unit, trigger_kind, extra)
	if line == null:
		return
	await _speak_line(unit, line)


## 流式语音 + 对话框并行播放一行的统一入口。被 _say 和 _do_adjacent_chat 共用。
func _speak_line(unit: Node, line: DialogueLine) -> void:
	# 并行启动流式语音（不 await — 协程在第一个 await 后让出）
	_voice.speak(unit, line.text)
	# 与此同时打开对话框
	if _level != null and _level.has_method("play_chatter_lines"):
		var lines: Array[DialogueLine] = [line]
		await _level.play_chatter_lines(lines, _delay_for_lines(lines))
	# 对话先关，但语音还没说完 → 等语音收尾，避免下一次 chatter 冲掉
	if _voice.is_streaming():
		await _voice.streaming_done


## 调 LLM 生成一条台词并组装成 DialogueLine（不带 audio_stream，配音由 ChatterVoice 单独走）。
## LLM 失败 → 跳过本次 chatter（不用 fallback_lines，那是"老监工"语气，套到别的角色会严重出戏）。
## 被 _say / _do_adjacent_chat 共用。
func _build_line(unit: Node, trigger_kind: String, extra: Dictionary) -> DialogueLine:
	if _busy:
		return null
	if unit == null or not (unit is Unit) or not _is_alive(unit):
		return null
	var u := unit as Unit
	if u.unit_data == null:
		return null
	_busy = true
	var persona: Dictionary = NpcPersonasScript.get_persona(u.unit_data.unit_id, u.unit_data.camp)
	var memory_text := ChatterPromptsScript.format_memory(u)
	var context_json := ChatterPromptsScript.build_context_summary(_level)
	var system_msg := ChatterPromptsScript.build_system_prompt(persona, trigger_kind, memory_text, context_json)
	var user_msg := ChatterPromptsScript.build_user_prompt(persona, trigger_kind, extra)

	# 临时把 LLMClient 超时调短
	var prev_timeout: float = _llm.timeout_sec if "timeout_sec" in _llm else 30.0
	if "timeout_sec" in _llm:
		_llm.timeout_sec = LLM_TIMEOUT_SEC

	var resp: Dictionary = await _llm.chat_completion(
		[
			{"role": "system", "content": system_msg},
			{"role": "user", "content": user_msg},
		],
		{"max_tokens": 80, "temperature": 0.85}
	)
	if "timeout_sec" in _llm:
		_llm.timeout_sec = prev_timeout

	if not resp.ok:
		push_warning("[Chatter] LLM 失败 code=%s error=%s，跳过本次闲聊" % [resp.get("code", 0), resp.get("error", "")])
		_busy = false
		return null
	var text: String = String(resp.text).strip_edges()
	if text.is_empty():
		_busy = false
		return null

	# 追加到说话者自己的记忆
	_append_memory(u, {
		"round": extra.get("round", -1),
		"trigger": trigger_kind,
		"text": text,
	})
	_busy = false

	return DialogueLine.create(
		persona.get("name", u.unit_data.unit_name),
		text,
		_get_portrait(u),
		_side_for_unit(u),
		PortraitResolverScript.get_portrait_bg(u)
	)


## 给 play_chatter_lines 估算合理的 dismiss_delay。
## - 有 audio_stream：返回 base，dialogue_box 内会再用音频时长进一步拉长
## - 无 audio_stream（含系统 TTS 兜底）：按文本长度估时（中文约 3.5 字/秒 + 1s 缓冲）
func _delay_for_lines(lines: Array[DialogueLine]) -> float:
	var d := DIALOGUE_DISMISS_DELAY
	for line in lines:
		if line.audio_stream != null:
			continue
		var est := float(line.text.length()) / 3.5 + 1.0
		d = maxf(d, est)
	return d


# ─────────────────────────────────────────────────────────
# 战场查询小工具
# ─────────────────────────────────────────────────────────

func _find_unit_at_cell(cell: Vector2i) -> Node:
	if _level == null or not _level.has_method("_get_all_units"):
		return null
	for u in _level._get_all_units():
		if u is Unit and _is_alive(u) and u.cell == cell:
			return u
	return null


## 扫出所有曼哈顿距离=1 的单位对。返回 [a, b]，优先敌我混杂对。
func _pick_adjacent_pair() -> Array:
	if _level == null or not _level.has_method("_get_all_units"):
		return []
	var units: Array = _level._get_all_units()
	var mixed: Array[Array] = []
	var same_camp: Array[Array] = []
	for i in range(units.size()):
		for j in range(i + 1, units.size()):
			var a = units[i]
			var b = units[j]
			if not (a is Unit) or not (b is Unit):
				continue
			if not _is_alive(a) or not _is_alive(b):
				continue
			if not _are_adjacent(a, b):
				continue
			if _are_different_camps(a, b):
				mixed.append([a, b])
			else:
				same_camp.append([a, b])
	if not mixed.is_empty():
		return mixed[randi() % mixed.size()]
	if not same_camp.is_empty():
		return same_camp[randi() % same_camp.size()]
	return []


func _are_adjacent(a: Node, b: Node) -> bool:
	if not (a is Unit) or not (b is Unit):
		return false
	var delta: Vector2i = (a as Unit).cell - (b as Unit).cell
	return absi(delta.x) + absi(delta.y) == 1


func _are_different_camps(a: Node, b: Node) -> bool:
	if not (a is Unit) or not (b is Unit):
		return false
	var ca: int = (a as Unit).unit_data.camp if (a as Unit).unit_data else Enums.Camp.ALLY
	var cb: int = (b as Unit).unit_data.camp if (b as Unit).unit_data else Enums.Camp.ALLY
	return ca != cb


func _is_friendly(unit: Node) -> bool:
	if not (unit is Unit) or (unit as Unit).unit_data == null:
		return false
	return (unit as Unit).unit_data.camp == Enums.Camp.ALLY


func _is_alive(unit: Node) -> bool:
	if unit == null or not is_instance_valid(unit) or not (unit is Unit):
		return false
	var u := unit as Unit
	return u.combat_stats != null and u.combat_stats.is_alive()


func _hp_percent(unit: Node) -> int:
	if not (unit is Unit):
		return 100
	var stats: CombatStats = (unit as Unit).combat_stats
	if stats == null or stats.max_hp <= 0:
		return 100
	return int(round(100.0 * float(stats.current_hp) / float(stats.max_hp)))


func _unit_display_name(unit: Node) -> String:
	if not (unit is Unit):
		return "某处"
	var u := unit as Unit
	if u.unit_data == null:
		return "某人"
	var persona := NpcPersonasScript.get_persona(u.unit_data.unit_id, u.unit_data.camp)
	return persona.get("name", u.unit_data.unit_name)


# 把 portrait / side 的查询委托到 PortraitResolver（通过 preload，避免 class_name 冷启动问题）。
func _get_portrait(unit: Node) -> Texture2D:
	return PortraitResolverScript.get_portrait(unit)


func _side_for_unit(unit: Node) -> String:
	return PortraitResolverScript.side_for_unit(unit)


func _append_memory(unit: Node, entry: Dictionary) -> void:
	if not (unit is Unit):
		return
	(unit as Unit).append_dialogue_memory(entry)
