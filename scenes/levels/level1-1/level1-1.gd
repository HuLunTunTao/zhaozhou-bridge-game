extends BaseLevel
## 第一关《踏勘洨河》

# ── 预加载李春技能 ──
var _sk_rule_strike: SkillData = preload("res://data/skills/lc_rule_strike.tres")
var _sk_wedge: SkillData = preload("res://data/skills/lc_wedge_bank_probe.tres")
var _sk_stone: SkillData = preload("res://data/skills/lc_cast_stone_arrest_flow.tres")
var _sk_read_water: SkillData = preload("res://data/skills/lc_read_water_fix_site.tres")

var _li_chun: Node2D


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/LiChun"
	return [
		{
			"name": "玩家队伍",
			"faction": "好人",
			"controller": "player",
			"units": [_li_chun],
		},
	]


func get_objectives_text() -> Dictionary:
	return {
		"victory": [
			"- 完成 3 个勘测点",
			"- 李春在候选桥位执行「相水定址」",
			"- 至少 1 名测量工进入撤离区并结束回合",
		],
		"defeat": [
			"- 李春死亡",
			"- 两名测量工全部死亡",
			"- 超过第 10 回合仍未完成撤离",
		],
	}


func _on_level_ready() -> void:
	assign_skills(_li_chun as Unit, [_sk_rule_strike, _sk_wedge, _sk_stone, _sk_read_water] as Array[SkillData])
	setup_unit_stats(_li_chun as Unit, "李春", 130, 24, 100, 8, Enums.Element.NONE, 0, true)
