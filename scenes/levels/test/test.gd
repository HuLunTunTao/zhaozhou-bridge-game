extends BaseLevel
## 测试关卡：包含三支队伍用于验证回合机制。
##   - 玩家队伍（好人阵营）：玩家操控
##   - 队友队伍（好人阵营）：AI 操控
##   - 贼人队伍（坏人阵营）：AI 操控
##
## 各角色节点挂载在场景中，颜色和初始位置通过 unit_color / initial_cell 属性在编辑器中设置。


func get_teams_config() -> Array:
	return [
		{
			"name": "玩家队伍",
			"faction": "好人",
			"controller": "player",
			"units": [
				$"Entities/Players/Player",
				$"Entities/Players/PlayerB",
			],
		},
		{
			"name": "队友队伍",
			"faction": "好人",
			"controller": "ai",
			"units": [
				$"Entities/Players/Ally1",
				$"Entities/Players/Ally2",
			],
		},
		{
			"name": "贼人队伍",
			"faction": "坏人",
			"controller": "ai",
			"units": [
				$"Entities/Enemies/Enemy1",
				$"Entities/Enemies/Enemy2",
			],
		},
	]
