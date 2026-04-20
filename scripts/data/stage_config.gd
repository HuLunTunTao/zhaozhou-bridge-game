class_name StageConfig
extends Resource
## 关卡级常量。当前仅用于 level1-4；未来其他关卡可共用此 schema。

@export var turn_limit: int = 15  ## 超过此回合数（不含）即判负
