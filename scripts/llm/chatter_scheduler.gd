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
## 并发策略：单实例 LLMClient 串行。整个 chatter 会话（LLM 请求 + 对话框 + 流式语音）
## 由顶层 trigger 入口持有 `_busy`；期间到来的新触发直接丢弃，避免与正在播放的语音抢资源。
##
## 普通关卡只让 TTS 流式：_build_line 先用非流式 LLM 拿完整台词，再 fire `_voice.speak`
## 交给火山 bidi WS 流式播放全文。进 dialogue_box 时 audio 还在异步播放，
## 靠 voice_handle=_voice 让对话框等播完。

const NpcPersonasScript := preload("res://scripts/llm/npc_personas.gd")
const PersonaFallbackScript := preload("res://scripts/llm/persona_fallback.gd")
const LLMClientScript := preload("res://scripts/llm/llm_client.gd")
const PortraitResolverScript := preload("res://scripts/llm/portrait_resolver.gd")
const ChatterVoiceScript := preload("res://scripts/tts/chatter_voice_adapter.gd")
const ChatterPromptsScript := preload("res://scripts/llm/chatter_prompts.gd")

## 三类触发的概率（0.0–1.0）。调试时可临时拉到 1.0 做强制触发测试。
const TRIGGER_PROB_ATTACKED := 0.45
const TRIGGER_PROB_ADJACENT := 0.7
const TRIGGER_PROB_HERO_OBS := 0.6

# const TRIGGER_PROB_ATTACKED := 1.0
# const TRIGGER_PROB_ADJACENT := 1.0
# const TRIGGER_PROB_HERO_OBS := 1.0
## 邻接对话中，对方回一句的概率。
const ADJACENT_REPLY_PROB := 0.3
## 邻接对话先后顺序：混杂阵营时友方先开口的概率；同阵营时随机交换的概率。
const ADJACENT_FRIENDLY_FIRST_PROB := 0.7
const ADJACENT_SAME_CAMP_SWAP_PROB := 0.5

## 对话框自动飘过的停留秒数（基线；无音频时按文本长度再拉长）。
const DIALOGUE_DISMISS_DELAY := 3.0
## 无音频时，按中文阅读速度估算时长：字数 / CHARS_PER_SEC + BUFFER。
const DIALOGUE_CHARS_PER_SEC := 3.5
const DIALOGUE_TEXT_BUFFER_SEC := 1.0

## 单条非流式 LLM 请求的超时秒数。
const LLM_TIMEOUT_SEC := 12.0
## 闲聊台词的 LLM 采样参数。
const LLM_MAX_TOKENS := 80
const LLM_TEMPERATURE := 0.85
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
## setup() 时记录的 (signal_name, callable)，供 _exit_tree 配对 disconnect。
var _level_subs: Array[Dictionary] = []
## 当前小回合里发生的攻击事件。条目结构：{ victim: Unit, attacker: Unit, skill: SkillData }。
var _attacked_this_turn: Array[Dictionary] = []
## 本大回合内已经讲过话的单位集合。round_started 时清空，_speak_line 时填充。
## 用于让 chatter_always_each_round 的固定触发不与随机触发在同一单位上重复。
var _spoke_this_round: Array[Node] = []


## 初始化。由 BaseLevel._on_level_ready 调用一次。
## level 必须是 BaseLevel 实例（鸭子类型），llm_client 是 LLMClient 实例（或 null → 本器自建一个）。
func setup(level: Node, llm_client: Node = null) -> void:
	_level = level
	if llm_client != null:
		_llm = llm_client
	else:
		_llm = LLMClientScript.new()
		add_child(_llm)
	if "timeout_sec" in _llm:
		_llm.timeout_sec = LLM_TIMEOUT_SEC
	# 闲聊语音通道（火山流式 TTS + 系统 TTS 兜底，独立于 dialogue_box 的预设音频）
	_voice = ChatterVoiceScript.new()
	_voice.use_system_tts_fallback = use_system_tts_fallback
	add_child(_voice)
	# 订阅 BaseLevel 的领域信号
	_subscribe_level_signal(&"skill_executed", _on_skill_executed)
	_subscribe_level_signal(&"team_turn_started", _on_team_turn_started)
	_subscribe_level_signal(&"team_turn_ended", _on_team_turn_ended)
	_subscribe_level_signal(&"round_started", _on_round_started)
	_subscribe_level_signal(&"round_ended", _on_round_ended)


## 把 _level 的指定信号连到 callable 上，并记录到 _level_subs，供 _exit_tree 配对断开。
func _subscribe_level_signal(signal_name: StringName, callable: Callable) -> void:
	if _level == null or not _level.has_signal(signal_name):
		return
	_level.connect(signal_name, callable)
	_level_subs.append({"signal": signal_name, "callable": callable})


func _exit_tree() -> void:
	if _level == null or not is_instance_valid(_level):
		_level_subs.clear()
		return
	for sub in _level_subs:
		var sig: StringName = sub.get("signal", &"")
		var cb: Callable = sub.get("callable", Callable())
		if sig == &"" or not cb.is_valid():
			continue
		if _level.is_connected(sig, cb):
			_level.disconnect(sig, cb)
	_level_subs.clear()


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
	# 过滤掉本回合已发声的受害者（避免与固定 chatter 重复触发同一单位）
	var available: Array[Dictionary] = []
	for entry in _attacked_this_turn:
		var victim = entry.get("victim")
		if not is_instance_valid(victim) or _spoke_this_round.has(victim):
			continue
		available.append(entry)
	if available.is_empty():
		return
	var entry: Dictionary = available[randi() % available.size()]
	_busy = true
	await _do_attacked_reaction(entry)
	_busy = false


func _on_round_started(_round_number: int) -> void:
	# 大回合开始：清掉上一回合的 spoken 集合
	_spoke_this_round.clear()


func _on_round_ended(round_number: int) -> void:
	if _busy or _level == null or _level.is_phase_ended():
		return
	_busy = true
	# 阶段 1：场景内带 chatter_always_each_round 的单位强制说话（多个则依次）
	var any_fixed_spoke: bool = false
	for fixed_unit: Node in _collect_fixed_chatter_units():
		if not _is_alive(fixed_unit) or _spoke_this_round.has(fixed_unit):
			continue
		if _level.is_phase_ended():
			_busy = false
			return
		var full_map: bool = _is_full_map_range(fixed_unit)
		await _do_fixed_chatter(fixed_unit, round_number, full_map)
		any_fixed_spoke = true
	# 阶段 2：随机邻接 / 主角观察。若阶段 1 已发声，本回合不再追加（避免一回合三段闲聊）
	if not any_fixed_spoke:
		var choices: Array[String] = []
		if randf() < TRIGGER_PROB_ADJACENT:
			choices.append("adjacent")
		if randf() < TRIGGER_PROB_HERO_OBS:
			choices.append("hero_obs")
		if not choices.is_empty():
			var choice: String = choices[randi() % choices.size()]
			match choice:
				"adjacent":
					await _do_adjacent_chat(round_number)
				"hero_obs":
					await _do_hero_observation(round_number)
	_busy = false


# ─────────────────────────────────────────────────────────
# 具体触发实现
# ─────────────────────────────────────────────────────────

func _do_attacked_reaction(entry: Dictionary) -> void:
	# 受击单位可能在小回合内被打死并 queue_free，dict 里残留着 freed 引用。
	# 必须先 untyped 取 + is_instance_valid 验，再做 typed 赋值。
	var victim_raw = entry.get("victim")
	if not is_instance_valid(victim_raw) or not _is_alive(victim_raw):
		return
	var victim: Node = victim_raw
	var attacker_raw = entry.get("attacker")
	var attacker: Node = attacker_raw if is_instance_valid(attacker_raw) else null
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
	# 混杂阵营让友方先开口；纯同阵营随机先后
	var swap: bool = false
	if _are_different_camps(a, b):
		var a_is_friendly := _is_friendly(a)
		if not a_is_friendly and randf() < ADJACENT_FRIENDLY_FIRST_PROB:
			swap = true
	elif randf() < ADJACENT_SAME_CAMP_SWAP_PROB:
		swap = true
	if swap:
		var tmp := a
		a = b
		b = tmp

	# 第一行：A 先开口，单独对话 + 流式 TTS
	var line_a: DialogueLine = await _build_line(a, "adjacent_chat", {
		"other_name": _unit_display_name(b),
		"round": round_number,
	})
	if line_a == null:
		return
	var was_skipped_a: bool = await _speak_line(a, line_a, "adjacent_chat")

	# 决定是否有第二行；同时决定 A 的语音是切是等
	var has_reply: bool = randf() < ADJACENT_REPLY_PROB and _is_alive(b)
	if has_reply and was_skipped_a:
		# 玩家手动跳过 + 还有下一句 → 立即切音，让 B 无缝接上
		_voice.cancel()
	else:
		# 没下一句 / 自动飘过 → 让 A 自然播完
		await _wait_for_voice_end()

	if not has_reply:
		return

	# 第二行：B 接话
	var line_b: DialogueLine = await _build_line(b, "adjacent_reply", {
		"other_name": _unit_display_name(a),
		"heard": line_a.text,
		"round": round_number,
	})
	if line_b == null:
		return
	# 互相把对话纳入记忆
	_append_memory(a, {"round": round_number, "trigger": "adjacent_heard", "text": line_b.text})
	_append_memory(b, {"round": round_number, "trigger": "adjacent_heard", "text": line_a.text})
	@warning_ignore("unused_variable")
	var _was_skipped_b: bool = await _speak_line(b, line_b, "adjacent_reply")
	# B 是闲聊段最后一句，无论是否被跳过都让它播完
	await _wait_for_voice_end()


func _do_hero_observation(round_number: int) -> void:
	var hero: Node = _level.hero if "hero" in _level else null
	if hero == null or not _is_alive(hero):
		return
	# 主角本回合已发声 → 不再追加观察
	if _spoke_this_round.has(hero):
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
# 固定 chatter（场景中带 chatter_always_each_round 的单位）
# ─────────────────────────────────────────────────────────

## 扫场上所有 chatter_round_prob > 0 的存活单位，按各自概率独立 roll，返回本回合命中的。
func _collect_fixed_chatter_units() -> Array[Node]:
	var out: Array[Node] = []
	if _level == null or not _level.has_method("_get_all_units"):
		return out
	for u in _level._get_all_units():
		if not (u is Unit) or not _is_alive(u):
			continue
		var prob: float = (u as Unit).chatter_round_prob
		if prob <= 0.0:
			continue
		if prob >= 1.0 or randf() < prob:
			out.append(u)
	return out


func _is_full_map_range(unit: Node) -> bool:
	if not (unit is Unit):
		return false
	return (unit as Unit).chatter_full_map_range


## Boss-style 强制闲聊：unit 一定开口；若能找到对话伙伴则按 ADJACENT_REPLY_PROB 概率给一句回应。
## full_map=true → 伙伴池忽略 5 格邻接限制，可选全地图任意单位。
## 复用 adjacent_chat / adjacent_reply 的 prompt（无需新增模板，boss 语气交给 NpcPersonas 处理）。
func _do_fixed_chatter(unit: Node, round_number: int, full_map: bool) -> void:
	var partner: Node = _pick_partner_for_fixed(unit, full_map)
	# 没找到伙伴：当独白处理（hero_observation 模板足够通用）
	if partner == null:
		await _say(unit, "hero_observation", {
			"objectives": "",
			"round": round_number,
		})
		return
	var line_a: DialogueLine = await _build_line(unit, "adjacent_chat", {
		"other_name": _unit_display_name(partner),
		"round": round_number,
	})
	if line_a == null:
		return
	var was_skipped_a: bool = await _speak_line(unit, line_a, "adjacent_chat")
	var has_reply: bool = randf() < ADJACENT_REPLY_PROB and _is_alive(partner)
	if has_reply and was_skipped_a:
		_voice.cancel()
	else:
		await _wait_for_voice_end()
	if not has_reply:
		return
	var line_b: DialogueLine = await _build_line(partner, "adjacent_reply", {
		"other_name": _unit_display_name(unit),
		"heard": line_a.text,
		"round": round_number,
	})
	if line_b == null:
		return
	_append_memory(unit, {"round": round_number, "trigger": "adjacent_heard", "text": line_b.text})
	_append_memory(partner, {"round": round_number, "trigger": "adjacent_heard", "text": line_a.text})
	@warning_ignore("unused_variable")
	var _was_skipped_b: bool = await _speak_line(partner, line_b, "adjacent_reply")
	await _wait_for_voice_end()


## 给固定闲聊单位挑伙伴：先排除自己 / 已发声 / 已死亡，再按 full_map 决定是否压缩到邻接 5 格。
## 优先敌阵营，没有则同阵营。
func _pick_partner_for_fixed(unit: Node, full_map: bool) -> Node:
	if not (unit is Unit) or _level == null or not _level.has_method("_get_all_units"):
		return null
	var u := unit as Unit
	var enemies: Array[Node] = []
	var friendlies: Array[Node] = []
	for v in _level._get_all_units():
		if not (v is Unit) or v == u or not _is_alive(v):
			continue
		if _spoke_this_round.has(v):
			continue
		if not full_map:
			var delta: Vector2i = (v as Unit).cell - u.cell
			if absi(delta.x) + absi(delta.y) > 5:
				continue
		if _are_different_camps(u, v):
			enemies.append(v)
		else:
			friendlies.append(v)
	if not enemies.is_empty():
		return enemies[randi() % enemies.size()]
	if not friendlies.is_empty():
		return friendlies[randi() % friendlies.size()]
	return null


# ─────────────────────────────────────────────────────────
# 通用 _say / _build_line：拼 prompt、调 LLM、写 memory、呈现
# ─────────────────────────────────────────────────────────

func _say(unit: Node, trigger_kind: String, extra: Dictionary) -> void:
	var line: DialogueLine = await _build_line(unit, trigger_kind, extra)
	if line == null:
		return
	# 单条触发（受击 / 主角观察）没有"下一条"，无论是否手动跳过都让语音收尾
	@warning_ignore("unused_variable")
	var _was_skipped: bool = await _speak_line(unit, line, trigger_kind)
	await _wait_for_voice_end()


## 流式 TTS + 对话框并行播放一行。返回 was_skipped（玩家是否手动跳过对话框）。
## **不**在内部等语音收尾——caller 自己决定下一步是 _voice.cancel() 还是 _wait_for_voice_end()。
## 注意：TTS 已在 _build_line 中通过 speak() 启动；本函数只负责打开 dialogue_box，
## audio 由 voice_handle=_voice 让 dialogue_box 等播完。
## trigger_kind 参数保留以兼容旧调用方（实际由 _build_line 传给 speak）。
func _speak_line(unit: Node, line: DialogueLine, _trigger_kind: String = "") -> bool:
	# 记录"本回合已发声"——避免随机触发与固定触发在同一单位上重复
	if unit != null and not _spoke_this_round.has(unit):
		_spoke_this_round.append(unit)
	if _level == null or not _level.has_method("play_chatter_lines"):
		return false
	var lines: Array[DialogueLine] = [line]
	# voice_handle=_voice 让 dialogue_box 在 auto_dismiss 模式下等 TTS 播完 + 0.5s 才关
	var result: Dictionary = await _level.play_chatter_lines(lines, _delay_for_lines(lines), _voice)
	return bool(result.get("was_skipped", false))


## 等当前 chatter 语音自然收尾。无在播则立返回。
func _wait_for_voice_end() -> void:
	if _voice.is_streaming():
		await _voice.streaming_done


## 调 LLM 非流式生成完整台词，然后启动 TTS 流式播放，组装 DialogueLine。
## 返回时 LLM 已完成、TTS 已开始异步播放，dialogue_box 会等播完。
## LLM 失败 → 跳过本次 chatter（不用 fallback_lines，那是"老监工"语气，套到别的角色严重出戏）。
## 被 _say / _do_adjacent_chat 共用。**调用方负责 _busy 锁**（外层 trigger 入口已设）。
func _build_line(unit: Node, trigger_kind: String, extra: Dictionary) -> DialogueLine:
	if unit == null or not (unit is Unit) or not _is_alive(unit):
		return null
	var u := unit as Unit
	if u.unit_data == null:
		return null
	var persona: Dictionary = NpcPersonasScript.get_persona(u.unit_data.unit_id, u.unit_data.camp)
	var memory_text := ChatterPromptsScript.format_memory(u)
	var context_json := ChatterPromptsScript.build_context_summary(_level)
	var system_msg := ChatterPromptsScript.build_system_prompt(persona, trigger_kind, memory_text, context_json)
	var user_msg := ChatterPromptsScript.build_user_prompt(persona, trigger_kind, extra)

	var resp: Dictionary = await _llm.chat_completion([
		{"role": "system", "content": system_msg},
		{"role": "user", "content": user_msg},
	], {"max_tokens": LLM_MAX_TOKENS, "temperature": LLM_TEMPERATURE})

	if not resp.get("ok", false):
		push_warning("[ChatterFallback][LLM_ONLY] unit=%s trigger=%s error=%s fallback=persona_text+tts" % [
			_unit_display_name(u),
			trigger_kind,
			resp.get("error", ""),
		])
		return _build_fallback_line(u, persona, trigger_kind, extra, {
			"code": resp.get("code", ""),
			"error": resp.get("error", ""),
		})
	var text: String = String(resp.get("text", "")).strip_edges()
	if text.is_empty():
		push_warning("[ChatterFallback][LLM_ONLY] unit=%s trigger=%s error=empty_text fallback=persona_text+tts" % [
			_unit_display_name(u),
			trigger_kind,
		])
		return _build_fallback_line(u, persona, trigger_kind, extra, {
			"code": "empty_text",
			"error": "LLM returned empty text",
		})

	print("[Chatter][LLM_OK] unit=%s trigger=%s text=%s" % [
		_unit_display_name(u),
		trigger_kind,
		text.left(80),
	])
	_voice.speak(u, text, trigger_kind, {"llm_ok": true, "source": "llm"})

	# 追加到说话者自己的记忆
	_append_memory(u, {
		"round": extra.get("round", -1),
		"trigger": trigger_kind,
		"text": text,
	})

	return DialogueLine.create(
		u.combat_stats.unit_name if u.combat_stats != null else u.unit_data.unit_name,
		text,
		_get_portrait(u),
		_side_for_unit(u),
		PortraitResolverScript.get_portrait_bg(u)
	)


## LLM 失败时的兜底文本路径：拿 PersonaFallback 多变体 + 用 _voice.speak() 流式 TTS 播放
## （走 chatter_voice_adapter 的 火山 → pre-baked MP3 → OS TTS 三级降级）。
## 返回 null 表示"连兜底文本都没有，本轮静默跳过"（neighbor trigger 默认空）。
func _build_fallback_line(
		u: Unit,
		persona: Dictionary,
		trigger_kind: String,
		extra: Dictionary,
		llm_error: Dictionary = {},
	) -> DialogueLine:
	var text: String = PersonaFallbackScript.pick(persona, trigger_kind).strip_edges()
	if text.is_empty():
		return null
	# 触发流式 TTS（火山失败时转 speak() 内部兜底链）
	_voice.speak(u, text, trigger_kind, {
		"llm_ok": false,
		"source": "persona_fallback",
		"llm_code": llm_error.get("code", ""),
		"llm_error": llm_error.get("error", ""),
	})
	# 记忆里也记一笔，避免下次 prompt 看不到这次发声
	_append_memory(u, {
		"round": extra.get("round", -1),
		"trigger": trigger_kind,
		"text": text,
		"is_fallback": true,
	})
	return DialogueLine.create(
		u.combat_stats.unit_name if u.combat_stats != null else u.unit_data.unit_name,
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
		var est := float(line.text.length()) / DIALOGUE_CHARS_PER_SEC + DIALOGUE_TEXT_BUFFER_SEC
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

## 扫出所有曼哈顿距离 <= 5 的单位对。返回 [a, b]，优先敌我混杂对。
## 已在本大回合发声的单位会被过滤掉，避免 Boss 等固定 chatter 与随机抽签同回合撞车。
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
			if _spoke_this_round.has(a) or _spoke_this_round.has(b):
				continue
			var delta: Vector2i = (a as Unit).cell - (b as Unit).cell
			var manhattan := absi(delta.x) + absi(delta.y)
			if manhattan > 5:
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
	return u.combat_stats.unit_name if u.combat_stats != null else persona.get("name", u.unit_data.unit_name)


# 把 portrait / side 的查询委托到 PortraitResolver（通过 preload，避免 class_name 冷启动问题）。
func _get_portrait(unit: Node) -> Texture2D:
	return PortraitResolverScript.get_portrait(unit)


func _side_for_unit(unit: Node) -> String:
	return PortraitResolverScript.side_for_unit(unit)


func _append_memory(unit: Node, entry: Dictionary) -> void:
	if not (unit is Unit):
		return
	(unit as Unit).append_dialogue_memory(entry)
