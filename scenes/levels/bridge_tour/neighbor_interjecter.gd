class_name NeighborInterjecter
extends RefCounted

## 验桥日邻居插话：主角说完一句后，附近 NPC 有概率插话接茬。
## 并发逻辑（NeighborGen 信号 + fire-and-forget LLM 生成）与 spec dict 结构
## {neighbor, gen}、thinking 文案、兜底与后处理均与拆分前逐字一致。
##
## 对话呈现（show_thinking / hide_thinking / play_npc_line）由调用方
## SocialInteractionFlow 作为 presenter 传入（2.24 自 bridge_tour 移入该基类）。
## _level 是 bridge_tour，对 _get_llm_runner / _npcs / is_phase_ended 保持鸭子调用。

const _PersonaFallbackScript := preload("res://scripts/llm/persona_fallback.gd")

const NEIGHBOR_INTERJECT_PROB := 0.4
const NEIGHBOR_INTERJECT_RANGE := 5

var _level: Node = null   # bridge_tour


func setup(level: Node) -> void:
	_level = level


class NeighborGen extends RefCounted:
	signal completed(text: String)
	var done := false
	var text := ""
	func finish(t: String) -> void:
		done = true
		text = t
		completed.emit(t)


## 在第一句话播放前调用。立即决定是否要邻居插话；如果要，立刻 fire-and-forget 跑邻居 LLM。
## 返回 spec dict 给 play_pending 用：{neighbor: Unit?, gen: NeighborGen?}。
## 这样邻居 LLM 与第一句 TTS 播放并发；轮到邻居说话时再走 TTS 流式播放。
func start_interject(speaker: Unit, heard: String) -> Dictionary:
	var spec: Dictionary = {"neighbor": null, "gen": null}
	if heard.is_empty():
		return spec
	if randf() >= NEIGHBOR_INTERJECT_PROB:
		return spec
	var neighbor: Unit = pick_neighbor(speaker)
	if neighbor == null:
		return spec
	var gen := NeighborGen.new()
	spec["neighbor"] = neighbor
	spec["gen"] = gen
	_spawn_gen_async(neighbor, speaker, heard, gen)  # fire-and-forget
	return spec


## 配套 start_interject：第一句话播完后调，等邻居 LLM 收尾再播邻居台词。
## presenter 提供 show_thinking / hide_thinking / play_npc_line（SocialInteractionFlow）。
func play_pending(spec: Dictionary, presenter: SocialInteractionFlow = null) -> void:
	var neighbor: Variant = spec.get("neighbor")
	if neighbor == null:
		return
	var g: NeighborGen = spec.get("gen") as NeighborGen
	if g == null:
		return
	var text: String
	var thinking: CanvasLayer = null
	if g.done:
		text = g.text
	else:
		thinking = presenter.show_thinking("%s 正在接话……" % (neighbor as Unit).unit_data.unit_name) if presenter != null else null
		text = await g.completed
		if presenter != null:
			presenter.hide_thinking(thinking)
	if _level == null or _level.is_phase_ended():
		return
	text = text.strip_edges()
	if text.is_empty() or presenter == null:
		return
	await presenter.play_npc_line(neighbor as Unit, text, true, "bridge_neighbor_interject")


## fire-and-forget 协程：跑邻居 LLM，结束后调 gen.finish(t) 唤醒 play_pending。
func _spawn_gen_async(neighbor: Unit, speaker: Unit, heard: String, gen: NeighborGen) -> void:
	var t: String = await generate_line(neighbor, speaker, heard)
	gen.finish(t)


func pick_neighbor(speaker: Unit) -> Unit:
	var candidates: Array[Unit] = []
	for npc in _level._npcs:
		if not is_instance_valid(npc) or npc == speaker:
			continue
		if npc.combat_stats != null and not npc.combat_stats.is_alive():
			continue
		var d: Vector2i = npc.cell - speaker.cell
		if absi(d.x) + absi(d.y) <= NEIGHBOR_INTERJECT_RANGE:
			candidates.append(npc)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]


func generate_line(neighbor: Unit, speaker: Unit, heard: String) -> String:
	var result: Dictionary = await _level._get_llm_runner().run(neighbor, "bridge_neighbor_interject", "neighbor", {
		"speaker_name": speaker.unit_data.unit_name,
		"heard": heard,
	}, {"max_tokens": 100, "temperature": 0.85})
	var persona: Dictionary = result.get("persona", {})
	if not result.get("ok", false):
		push_warning("[bridge_tour LLM] neighbor 调用失败 unit=%s code=%s err=%s" % [neighbor.unit_data.unit_id, result.get("code", "?"), result.get("error", "?")])
		# LLM 失败 → 用 PersonaFallback 抽 neighbor 变体；空字符串则维持跳过插话
		return _PersonaFallbackScript.pick(persona, "neighbor").strip_edges()
	return DictUtil.strip_quotes(String(result.get("text", ""))).strip_edges()
