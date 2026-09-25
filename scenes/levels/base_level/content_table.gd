class_name ContentTable
extends Resource

## 内容表（数据外置）。
## 键值映射的真源在 data/content_tables/*.tres，代码侧 preload 后读 entries，
## 便于在编辑器里改内容而不必动脚本。
## 保持键名 / 值 / 值类型逐字不变（值可为 String、PackedScene 等）。

@export var entries: Dictionary = {}
