extends BaseLevel
## Base script for campaign levels that load map data from scenes/levels/maps/.

@export var map_scene: PackedScene


func _ready() -> void:
	if map_scene:
		var map_instance: Node = map_scene.instantiate()
		map_instance.name = "MapData"
		tilemap_container.add_child(map_instance)
	super._ready()
