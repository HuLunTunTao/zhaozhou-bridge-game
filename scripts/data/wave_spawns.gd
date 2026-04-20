class_name WaveSpawns
extends Resource
## 第四关整场波次表。关卡脚本按回合号聚合后插入 base_level 的 wave 系统。
## 注意：entries 底层用 Array[Resource] 避免 class_name 前向引用问题；
## 每项运行时期望是 WaveEntry 实例。

@export var entries: Array[Resource] = []
