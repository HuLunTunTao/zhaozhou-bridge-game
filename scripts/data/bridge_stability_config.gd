class_name BridgeStabilityConfig
extends Resource
## 第四关桥体稳定值系统配置。

@export var initial_overall: int = 12  ## 整桥总稳定值初值
@export var initial_left_pier: int = 6  ## 左桥台稳定值初值
@export var initial_right_pier: int = 6  ## 右桥台稳定值初值
@export var pier_max: int = 6  ## 单侧桥台抢修上限
