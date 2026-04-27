# 验桥日 LLM 驱动与提示词机制

本文记录“验桥日”关卡当前的 LLM 驱动方式、提示词拼接链路、说服/答题/求教三类交互的判定流程，以及演示用隐藏暗语机制。

相关代码入口：

- `scenes/levels/bridge_tour/bridge_tour.gd`
- `scripts/llm/chatter_prompts.gd`
- `scripts/llm/llm_client.gd`
- `scripts/llm/npc_personas.gd`
- `scripts/data/bridge_knowledge.gd`
- `scenes/levels/bridge_tour/mission_hud.gd`
- `scenes/ui/argument_input_panel.gd`

## 1. 关卡中的 NPC 交互角色

`bridge_tour.gd` 将 9 个 NPC 分成 3 类：

- `persuade`：说服目标。李春自由输入论述，LLM 给出 NPC 回复与两类评分，分数累加到 NPC 说服进度。
- `qa`：答疑目标。NPC 先抛出问题，李春输入答案，LLM 判断是否切中要点。
- `mentor`：求教目标。玩家从话题菜单选问题，LLM 从桥梁知识库中挑一条知识讲解，成功后把 `topic_key` 记入玩家已学知识。

胜利条件固定为：

- 说服 3/3 个 `persuade` NPC。
- 解答 4/4 个 `qa` NPC。
- `mentor` 不计入完成数，只负责提供知识。

## 2. LLM 客户端调用方式

`BridgeTourLevel` 通过 `_get_llm()` 懒加载 `LLMClient`：

```gdscript
func _get_llm() -> Node:
	if _llm == null:
		_llm = _LLMClientScript.new()
		add_child(_llm)
	return _llm
```

`LLMClient.chat_completion(messages, opts)` 使用 OpenAI Chat Completions 兼容协议，发送非流式请求：

- `messages`：标准 `{role, content}` 数组。
- `opts`：透传 `max_tokens`、`temperature` 等参数。
- 成功返回：`{"ok": true, "text": String, "raw": Dictionary}`。
- 失败返回：`{"ok": false, "code": int, "error": String}`。

验桥日目前使用非流式 LLM。TTS 仍由 `_play_npc_line()` 在拿到文本后播放。

## 3. 人设来源

所有 NPC 人设来自 `scripts/llm/npc_personas.gd`。

查找方式：

```gdscript
var persona := _NpcPersonasScript.get_persona(npc.unit_data.unit_id, npc.unit_data.camp)
```

常用字段：

- `name`：角色名。
- `persona`：角色背景与身份。
- `style`：说话风格。
- `qa_question` / `qa_questions`：答疑 NPC 的预设问题。
- `fallback_lines` / fallback 相关数据：LLM 失败时的兜底台词来源之一。

`bridge_tour.gd` 在初始化静态 NPC 时，会根据配置写入 `unit_id` 和 `unit_name`，因此 persona 查找依赖 `unit_data.unit_id`。

## 4. 提示词拼接总览

提示词拼接集中在 `scripts/llm/chatter_prompts.gd`：

- `build_system_prompt(persona, trigger_kind, memory_text, context_json)`
- `build_user_prompt(persona, trigger_kind, extra)`

实际调用格式均为：

```gdscript
var sys := _ChatterPromptsScript.build_system_prompt(persona, trigger_kind, memory_text, context_json)
var user := _ChatterPromptsScript.build_user_prompt(persona, trigger_kind, extra)
var resp := await _get_llm().chat_completion([
	{"role": "system", "content": sys},
	{"role": "user", "content": user},
], {"max_tokens": ..., "temperature": ...})
```

### 4.1 System Prompt

`build_system_prompt()` 负责提供“角色与场景底盘”：

- 指定模型扮演《安济桥成》中的某个角色。
- 注入 persona 的角色背景与说话风格。
- 加入硬约束：
  - 只说一句话，不超过 30 字。
  - 不写括号动作描述。
  - 不提 HP/AP/技能名。
  - 保持角色口吻。
  - 不能用坐标描述位置。
- 注入 `trigger_kind`。
- 注入“最近你说过 / 听到的话”。
- 注入当前战场/关卡上下文 JSON。

验桥日传入的 `memory_text` 通常来自 `_build_npc_memory_memo(npc)`，包含：

- `_learned_memo()`：玩家已学知识标题。
- `_dialogue_history_text(npc)`：该 NPC 近几轮历史问答。

验桥日传入的 `context_json` 通常来自 `_build_bridge_context_json(npc, trigger_kind)`，包含：

- 关卡名：`验桥日`。
- 触发类型。
- 当前 NPC 名称与角色类型。
- NPC 所在桥段。
- 李春与 NPC 的距离描述。
- 任务进度。
- 已学知识、已用知识。
- 对 `persuade` NPC 额外注入：
  - 当前说服进度。
  - 累积分合计。
  - 说服目标。
  - 核心疑虑。
  - 成功条件。
- 对 `qa` NPC 额外注入：
  - 是否已解答。

### 4.2 User Prompt

`build_user_prompt()` 根据 `trigger_kind` 分支生成任务提示。

验桥日主要使用：

- `bridge_topic_answer`：说服。
- `bridge_qa_eval`：答疑判定。
- `bridge_knowledge_explain`：导师讲解。
- `bridge_neighbor_interject`：邻近 NPC 插话。

## 5. 说服机制：`bridge_topic_answer`

### 5.1 输入流程

玩家与 `persuade` NPC 交互时：

1. 打开 `ArgumentInputPanel`。
2. 面板显示：
   - NPC 的说服目标。
   - NPC 的疑虑。
   - 推荐知识关键词。
   - 当前累计推进。
   - 已学知识。
   - 与该 NPC 的历史对话。
3. 玩家输入论述。
4. `_generate_persuade_answer(npc, argument)` 非流式请求 LLM，要求返回完整 JSON。
5. `_apply_persuade_result(npc, ans)` 结算分数。
6. `_append_dialogue_log()` 写入历史。
7. `_play_npc_line()` 播放 NPC 回复。
8. `_start_neighbor_interject()` / `_play_pending_neighbor()` 概率触发邻近 NPC 插话。

### 5.2 传给 prompt 的 extra 字段

`bridge_topic_answer` 的 `extra` 主要包含：

- `topic`：李春本轮输入。
- `bridge_part`：NPC 所在桥段。
- `stance`：当前说服进度。
- `persuasion_goal`：NPC 的说服目标配置。
- `learned_csv`：玩家已学知识 key 列表。
- `learned_details`：玩家已学知识正文摘要。
- `dialogue_history`：该 NPC 近几轮历史问答。
- `mission_context`：当前任务与 NPC 关键信息。
- `cheat_context`：隐藏暗语命中时的特殊判定说明；未命中时为“（无）”。
- `accum_total`：此前累积分合计。

### 5.3 LLM 输出格式

说服 prompt 要求 LLM 严格输出 JSON：

```json
{
  "reply": "<一句话回答，30字内>",
  "accum_score": 1,
  "round_score": 0,
  "tone": "<两到四字情绪标签>",
  "knowledge_used": [],
  "matched_points": [],
  "missed_points": []
}
```

字段含义：

- `reply`：NPC 本轮实际说给玩家的话；LLM 完整返回后，由 TTS 流式播放。
- `accum_score`：累积分，范围 `1..5`。
- `round_score`：本轮评分，范围 `-10..15`。
- `tone`：情绪标签。
- `knowledge_used`：李春本轮论述中实际用到的知识 key。
- `matched_points`：命中的说服点。
- `missed_points`：仍缺少的要点。

### 5.4 分数归一化与结算

`_normalize_persuade_scores(ans)` 负责容错：

- 如果有 `accum_score`：使用它。
- 如果没有但有旧字段 `cumulative_score`：兼容读取。
- 否则 `accum_score = 1`。
- `accum_score` clamp 到 `1..5`。
- 如果有 `round_score`：使用它。
- 如果没有但有旧字段 `stance_delta`：兼容读取。
- 否则 `round_score = 0`。
- `round_score` clamp 到 `-10..15`。
- 写入 `final_score = accum_score + round_score`。

`_apply_persuade_result()` 的结算规则：

```gdscript
final_score = accum_score + round_score
npc_stance += final_score
npc_accum_score_total += accum_score
```

如果 `npc_stance >= STANCE_PERSUADED`，即当前阈值 `70`，则：

- `npc_persuaded = true`
- 刷新头顶姓名颜色。
- 刷新左上角任务 HUD。
- 检查胜利条件。

如果 LLM 失败并走普通 fallback：

- `accum_score = 0`
- `round_score = 0`
- `final_score = 0`

也就是说，普通 LLM 失败不会推进说服进度。

### 5.5 HUD 显示

`MissionHud.update_npc_stance()` 会显示说服进度与上轮计分：

```text
老匠首  12+8/70
```

含义：

- `12`：该 NPC 已累计的基础分合计。
- `+8`：本次玩家回答的本轮评分；负分会显示为 `-3` 这类形式。
- `70`：说服通过所需总进度阈值。

HUD 底部提示：

```text
说服显示：累计基础分+本次评分/总进度
```

## 6. 答疑机制：`bridge_qa_eval`

### 6.1 输入流程

玩家与 `qa` NPC 交互时：

1. `_pick_qa_question(npc)` 选出问题。
2. `_play_npc_line(npc, question, true)` 让 NPC 先把问题说出来。
3. 打开 `ArgumentInputPanel`。
4. 输入面板显示当前问题和历史对话。
5. 玩家输入答案。
6. `_generate_qa_eval(npc, question, answer)` 请求 LLM。
7. `_apply_qa_result(npc, eval)` 结算。
8. 将“问题 + 玩家答案 + NPC 反馈”写入历史。
9. 播放 NPC 反馈。

### 6.2 QA 问题选择

`_pick_qa_question()` 的优先级：

1. persona 中的 `qa_questions` 数组，按尝试次数轮换。
2. persona 中的 `qa_question` 单字段。
3. NPC meta 中的 `npc_qa_question`。
4. 固定兜底句。

每次选择后，`npc_qa_attempt += 1`。

### 6.3 传给 prompt 的 extra 字段

`bridge_qa_eval` 的 `extra` 主要包含：

- `question`：NPC 当前问题。
- `answer`：李春当前答案。
- `learned_csv`：玩家已学知识 key 列表。
- `learned_details`：已学知识正文摘要。
- `dialogue_history`：该 NPC 历史问答。
- `mission_context`：当前任务上下文。
- `cheat_context`：隐藏暗语命中时的特殊判定说明。

### 6.4 LLM 输出格式

QA prompt 要求 LLM 严格输出 JSON：

```json
{
  "is_correct": true,
  "feedback": "<一句口吻 reaction，<= 30 字>",
  "knowledge_used": []
}
```

字段含义：

- `is_correct`：是否答对。
- `feedback`：NPC 反馈；LLM 完整返回后，由 TTS 流式播放。
- `knowledge_used`：李春答案中实际用到的知识 key。

如果 `is_correct == true`：

- `npc_qa_solved = true`
- 刷新头顶姓名颜色。
- 刷新左上 HUD。
- 检查胜利条件。

## 7. 求教机制：`bridge_knowledge_explain`

玩家与 `mentor` NPC 交互时：

1. 打开 `TopicMenuPanel`。
2. 玩家选择预设话题或自由输入。
3. `_generate_mentor_lesson(npc, query)` 请求 LLM。
4. LLM 从 `BridgeKnowledge.TOPICS` 中挑一条最贴切知识讲解。
5. `_apply_mentor_lesson()` 校验 `topic_key` 是否存在。
6. 若存在且未学过，则加入 `_player_learned_topics`。

导师 prompt 要求 LLM 严格输出 JSON：

```json
{
  "reply": "<以你的口吻把这条知识讲给李春听，70 字以内>",
  "topic_key": "<knowledge.gd 里那条的 key>"
}
```

玩家学到的知识会进入后续说服/答疑 prompt：

- 以 key 列表形式进入 `learned_csv`。
- 以正文摘要形式进入 `learned_details`。
- 标题列表也会进入 system prompt 的上下文 JSON。

## 8. 邻近 NPC 插话：`bridge_neighbor_interject`

说服或答疑结束后，`_maybe_neighbor_interject(speaker, heard)` 有概率触发附近 NPC 插话。

条件：

- NPC 与发言者曼哈顿距离不超过 `NEIGHBOR_INTERJECT_RANGE`。
- 随机概率小于 `NEIGHBOR_INTERJECT_PROB`。
- 不能选择发言者自己。
- NPC 必须存活。

LLM 输入：

- 插话 NPC persona。
- 听到谁说了什么。
- 插话 NPC 的上下文 JSON 和历史记忆。

LLM 输出是一句短文本，不要求 JSON。失败时使用 persona fallback 的 `neighbor` 台词。

## 9. 对话历史机制

每个 NPC 用 meta 保存独立历史：

```gdscript
npc.set_meta("npc_dialogue_log", [] as Array[Dictionary])
```

写入函数：

```gdscript
_append_dialogue_log(npc, player, npc_text, tone, question = "")
```

每条历史可包含：

- `question`：QA 流程中的 NPC 问题。
- `player`：玩家输入。
- `npc`：NPC 回复。
- `npc_name`：NPC 名。
- `tone`：情绪或流程标签。

`_dialogue_history_text(npc)` 会取最近 4 条，整理成：

```text
某某问：……
李春答：……
某某回：……
```

这段文本同时用于：

- system prompt 中的“最近说过 / 听到的话”。
- user prompt 中的“此前近几轮问答”。
- 输入面板历史显示。

QA 的当前问题会通过 `_history_with_npc_prompt()` 临时拼进输入面板历史，但玩家取消时不写入持久历史。

## 10. 隐藏暗语机制（演示用）

当前演示暗语定义在 `bridge_tour.gd`：

```gdscript
const CHEAT_WORDS: Array[String] = [
	"鲁班托梦",
	"墨线自明",
	"石龙点头",
	"洨水有灵",
	"天工开物",
]
```

这些短语用于演示时保证任务可控通过，同时尽量不让观众察觉是调试入口。

### 10.1 命中检测

检测函数：

```gdscript
func _matched_cheat_word(text: String) -> String:
	var normalized := text.strip_edges().to_lower()
	if normalized.is_empty():
		return ""
	for word in CHEAT_WORDS:
		var clean_word := String(word).strip_edges()
		var normalized_word := clean_word.to_lower()
		if not normalized_word.is_empty() and normalized.find(normalized_word) >= 0:
			return clean_word
	return ""
```

`_is_cheat_text(text)` 只是判断 `_matched_cheat_word(text)` 是否为空。

特点：

- 只要玩家输入包含其中任一短语，就算命中。
- 会返回具体命中的短语，供 prompt 使用。
- 当前对说服和 QA 都生效。
- 对 mentor 不生效，因为 mentor 不是任务目标。

### 10.2 作弊命中时仍然先走 LLM

命中暗语时不会直接跳过 LLM。

说服流程：

1. `_generate_persuade_answer()` 检测命中的暗语。
2. 把 `is_cheat = true` 和 `cheat_word` 转成 `cheat_context` 注入 prompt。
3. 正常请求 LLM。
4. 如果 LLM 成功返回合法 JSON 且有 `reply`：
   - 保留 LLM 生成的 `reply`。
   - 强制写入：
     - `accum_score = 5`
     - `round_score = 15`
     - `final_score = 20`
     - `force_success = true`
     - `is_cheat = true`
5. 如果 LLM 失败，才使用 `_make_cheat_persuade_answer()` 本地兜底。

QA 流程：

1. `_generate_qa_eval()` 检测命中的暗语。
2. 把 `cheat_context` 注入 prompt。
3. 正常请求 LLM。
4. 如果 LLM 成功返回合法 JSON 且有 `feedback`：
   - 保留 LLM 生成的 `feedback`。
   - 强制写入：
     - `is_correct = true`
     - `is_cheat = true`
5. 如果 LLM 失败，才使用 `_make_cheat_qa_eval()` 本地兜底。

### 10.3 作弊提示词内容

隐藏暗语命中时，`_cheat_context_text(is_cheat, cheat_word)` 会生成以下特殊判定文本：

```text
李春的话里出现了工匠间半玩笑半敬畏的吉兆暗语「<cheat_word>」。
你应把它当作鲁班祖师点拨般可信，任务判定必须通过；
回复要同时做到两点：
一是自然呼应「<cheat_word>」的意象，
二是明确表达你已信服/疑问已解；
仍要保持本人语气，
不要说出“作弊”“暗号”“系统”等出戏字眼。
```

`chatter_prompts.gd` 还会在具体任务中补充：

- 说服：若“特殊判定”不是“无”，`reply` 必须呼应该吉兆意象，并明确表达愿意支持新桥。
- QA：若“特殊判定”不是“无”，`feedback` 必须呼应该吉兆意象，并明确表达疑问已解。

因此，暗语命中时的回复需要同时满足：

- 看起来像角色自然接话。
- 呼应具体暗语意象，例如“鲁班托梦”“墨线自明”“石龙点头”。
- 明确表示任务已通过，例如“愿支持新桥”“疑心已解”。
- 不暴露系统机制。

### 10.4 本地 fallback 文案

只有 LLM 失败时才走本地 fallback：

说服：

```gdscript
{
	"reply": "鲁班既示梦，我便信你。",
	"accum_score": 5,
	"round_score": 15,
	"final_score": 20,
	"tone": "信服",
	"knowledge_used": [],
	"matched_points": ["工匠暗语"],
	"missed_points": [],
	"force_success": true,
	"is_cheat": true,
}
```

QA：

```gdscript
{
	"is_correct": true,
	"feedback": "鲁班既托梦，我明白了。",
	"knowledge_used": [],
	"is_cheat": true,
}
```

注意：fallback 文案目前固定使用“鲁班”意象，即使命中的是“墨线自明”或“石龙点头”。这是 LLM 失败时的兜底，不是常规路径。

## 11. 知识系统与评分联动

知识库在 `scripts/data/bridge_knowledge.gd`，每条包含：

- `key`
- `title`
- `summary`
- `body`
- `tags`

导师讲解成功后，`topic_key` 写入 `_player_learned_topics`。

后续说服和答疑时：

- `_learned_csv()` 提供 key 列表。
- `_learned_details_text()` 提供已学知识正文摘要。
- LLM 通过 `knowledge_used` 声明李春本轮实际用到的 key。
- `_player_used_topics` 记录实际用过的知识 key。
- 输入面板会高亮已用过的知识。

说服评分 prompt 中明确：

- 只有李春话里确实用到知识时才加分。
- 推荐知识 key 或已学知识命中可提高 `round_score`。
- 空泛表态、未回应 NPC 核心疑虑，不应高分。

## 12. 失败与兜底

LLM 失败包括：

- HTTP 请求失败。
- API key 未配置。
- 响应不是合法 JSON。
- JSON 缺少必要字段。

各流程兜底：

- 说服：`_PersonaFallbackScript.pick(persona, "persuade")`，且普通失败不推进说服进度。
- QA：`_PersonaFallbackScript.pick(persona, "qa")`，且默认 `is_correct = false`。
- Mentor：`_PersonaFallbackScript.pick(persona, "mentor")`，`topic_key = ""`，不会学到知识。
- Neighbor：`_PersonaFallbackScript.pick(persona, "neighbor")`，为空则跳过插话。
- 暗语命中：使用专门的 `_make_cheat_persuade_answer()` / `_make_cheat_qa_eval()`，确保演示可通过。

TTS 失败不影响 LLM 逻辑。`chatter_voice_adapter.gd` 会尝试：

1. 火山 TTS。
2. 预制 fallback MP3。
3. OS TTS。
4. 静默。

## 13. 维护注意事项

- 新增 NPC 时，要同步维护：
  - `bridge_tour.gd` 的 NPC 配置。
  - `npc_personas.gd` 的 persona。
  - `voice_mapping.gd` 的 TTS 映射。
  - 对应 `UnitData` 或运行时 unit_id。
- 修改说服评分字段时，要同步改：
  - `chatter_prompts.gd` 的 JSON schema。
  - `_normalize_persuade_scores()`。
  - `_apply_persuade_result()`。
  - `MissionHud.update_npc_stance()`。
- 修改暗语时，要同步确认：
  - `CHEAT_WORDS` 是否自然、隐蔽。
  - `_cheat_context_text()` 是否能让 LLM 呼应新意象。
  - fallback 文案是否仍合适。
- 不要在 prompt 中暴露“作弊”“系统”“调试”等会破坏演示沉浸感的字眼，除非只出现在对 LLM 的禁止性约束中。
