class_name BridgeStabilityConfig
extends Resource
## 第四关桥体稳定值系统配置。整桥单一稳定值；归零即失败。
## 早期版本曾有左/右桥台分离稳定值，已简化合并为单一 overall。

@export var initial_overall: int = 100  ## 整桥稳定值初值（也是上限）
