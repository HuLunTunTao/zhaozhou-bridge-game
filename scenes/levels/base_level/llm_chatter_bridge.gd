class_name LLMChatterBridge
extends RefCounted

## debug AI 闲聊桥接组件（Tactics Stack）。
## 从 BaseLevel 抽出：AI 按钮 / 大回合开始的 debug 闲聊请求（老监工口吻）+ LLM 客户端与忙锁状态。
## 通过 setup(level) 持有宿主关卡，对 _level 保持鸭子调用，不反向依赖 BaseLevel。

const LLMClientScript := preload("res://scripts/llm/llm_client.gd")
const BattleContextScript := preload("res://scripts/llm/battle_context.gd")
const LLMFallbackLinesScript := preload("res://scripts/llm/fallback_lines.gd")

var _level: Node = null   # BaseLevel 宿主

## 请求忙锁：同一时刻只跑一次 LLM 闲聊。
var ai_busy := false
var _llm_client: Node = null


func setup(level: Node) -> void:
	_level = level


## AI 支持按钮：临时调用 LLM 做一次测试请求。后续会替换为具体业务（旁白/调侃等）。
func on_ai_button_pressed() -> void:
	await call_ai_with_prompt("老把式，你瞧这局怎么样？")


## 大回合开始信号回调：自动触发一次 AI（占位，后续替换为剧情/战况点评）。
func on_round_started_ai_call(rn: int) -> void:
	await call_ai_with_prompt("第 %d 回合刚开锣，瞧瞧这阵势。" % rn)


## 内部：拼请求 + 显示 toast。被按钮和回合开始两处复用。
func call_ai_with_prompt(prompt: String) -> void:
	if ai_busy:
		return
	ai_busy = true
	if _llm_client == null:
		_llm_client = LLMClientScript.new()
		_level.add_child(_llm_client)
	var snapshot: Dictionary = BattleContextScript.build_snapshot(_level)
	var system_msg := """你不是教练，是《安济桥成》工坊里的"老监工"。隋代营造场，匠师李春带着工匠在筑赵州桥，半道撞上洪水、旧制等阻碍。你懂点五行（金木水火土相生相克），更懂"该干就干、该躲就躲"那点门道。

请基于下方战场快照，用老把式的口气说**一句话**（30 字以内）。看势头：
- 顺手时 → 催他们抓紧把本关任务办了，别磨蹭
- 吃紧时 → 劝撤、劝守、劝先缓口气，别硬刚
- 平淡时 → 发句牢骚、聊聊桥的旧事、或随口调侃几句也行

**忌讳**：
- 别指着说"用 X 技能打 Y 单位"，那是新手教程，老监工不干这种事
- 别报数字（HP/AP/坐标这些都别说出口）
- 别用"建议"、"综上"、"以下"这种教学体
- 宁愿俏皮、带点人味儿，也别端着架子

趣味第一，别把人当小学生教。

当前战场（自己心里有数，别复述给玩家）：
%s""" % JSON.stringify(snapshot)
	Notify.info("AI 思考中...", 1.5)
	var resp: Dictionary = await _llm_client.chat_completion([
		{"role": "system", "content": system_msg},
		{"role": "user", "content": prompt}
	], {"max_tokens": 200, "temperature": 0.7})
	ai_busy = false
	if resp.ok:
		Notify.notify(resp.text, Notify.Position.TOP_RIGHT, Notify.Style.SUCCESS, 8.0)
	else:
		# LLM 调用失败时不暴露报错给玩家，用老监工口吻的兜底台词糊过去
		push_warning("[LLM] 调用失败 code=%d error=%s" % [resp.code, resp.error])
		Notify.info(LLMFallbackLinesScript.random(), 6.0)
