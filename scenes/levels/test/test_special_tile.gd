extends SpecialTile
## 测试用特殊地块，三种交互都打印消息。

@export var tile_name: String = "测试地块"


func _on_unit_arrive(entity: Node2D) -> void:
	print("[特殊地块] %s：%s 抵达了此地块 (cell=%s)" % [tile_name, entity.name, cell])


func _on_unit_pass(entity: Node2D) -> void:
	print("[特殊地块] %s：%s 经过了此地块 (cell=%s)" % [tile_name, entity.name, cell])


func _on_unit_depart(entity: Node2D) -> void:
	print("[特殊地块] %s：%s 从此地块出发 (cell=%s)" % [tile_name, entity.name, cell])
