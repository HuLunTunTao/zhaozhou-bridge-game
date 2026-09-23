class_name NpcSocialState
extends Resource

## 验桥日 NPC 的社交状态（替代 Unit.set_meta 字符串键）。
## 每个 NPC 实例持有一个 NpcSocialState；bridge_tour 通过 unit.get_meta(META_KEY) 访问。

const META_KEY := "_social_state"

@export var role: String = "persuade"
@export var bridge_part: String = ""
@export var dialogue_log: Array[Dictionary] = []
@export var stance: int = 50
@export var accum_score_total: int = 0
@export var last_accum_score: int = 0
@export var last_round_score: int = 0
@export var last_final_score: int = 0
@export var persuaded: bool = false
@export var persuasion_goal: Dictionary = {}
@export var qa_question: String = ""
@export var qa_key_points: Array[Dictionary] = []
@export var qa_solved: bool = false
@export var mentor_topics: Array[String] = []
@export var qa_attempt: int = 0
@export var persuade_opening_attempt: int = 0
@export var persuade_success_attempt: int = 0
@export var qa_success_attempt: int = 0
@export var discussed_topics: Array[String] = []


func is_done() -> bool:
	match role:
		"persuade":
			return persuaded
		"qa":
			return qa_solved
		_:
			return false
