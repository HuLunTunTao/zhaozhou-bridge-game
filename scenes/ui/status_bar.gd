extends HBoxContainer
## Bottom status bar showing player state. Add new labels to extend.

var _labels: Dictionary = {}


func _ready() -> void:
	set_status("状态1", "--")
	set_status("状态2", "--")


func set_status(key: String, value: String) -> void:
	if _labels.has(key):
		_labels[key].text = "%s: %s" % [key, value]
	else:
		_add_label(key, value)


func _add_label(key: String, value: String) -> void:
	if _labels.size() > 0:
		var sep := VSeparator.new()
		add_child(sep)
	var label := Label.new()
	label.text = "%s: %s" % [key, value]
	add_child(label)
	_labels[key] = label
