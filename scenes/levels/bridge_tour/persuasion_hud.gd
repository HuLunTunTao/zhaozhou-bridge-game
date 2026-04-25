class_name PersuasionHud
extends CanvasLayer
## 验桥日 NPC 说服进度面板。左上角，纯文风（参考 wave_buff_hud）。
##
## 用法：
##   var hud = preload(".../persuasion_hud.tscn").instantiate()
##   level.add_child(hud)
##   hud.set_target(4)
##   hud.add_npc("老匠首", 10, false)
##   ...
##   hud.update_npc("老匠首", 22, false)
##   hud.update_npc("老匠首", 75, true)

@onready var _title: Label = %Title
@onready var _list: VBoxContainer = %List

const TEXT_COLOR := Color(0.96, 0.94, 0.88)
const PERSUADED_COLOR := Color(0.95, 0.85, 0.4)
const OUTLINE_COLOR := Color(0.08, 0.08, 0.08)
const FONT_SIZE := 14

var _target: int = 4
var _persuaded: int = 0
var _entries: Dictionary = {}   # name -> Label


func _ready() -> void:
	layer = 70
	_refresh_title()


func set_target(target: int) -> void:
	_target = max(target, 1)
	_refresh_title()


func add_npc(npc_name: String, stance: int, persuaded: bool) -> void:
	if _entries.has(npc_name):
		update_npc(npc_name, stance, persuaded)
		return
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", FONT_SIZE)
	lbl.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	lbl.add_theme_constant_override("outline_size", 3)
	_list.add_child(lbl)
	_entries[npc_name] = lbl
	_render_entry(npc_name, stance, persuaded)
	if persuaded:
		_persuaded += 1
		_refresh_title()


func update_npc(npc_name: String, stance: int, persuaded: bool) -> void:
	if not _entries.has(npc_name):
		add_npc(npc_name, stance, persuaded)
		return
	var was_marked := bool((_entries[npc_name] as Label).get_meta("persuaded", false))
	_render_entry(npc_name, stance, persuaded)
	if persuaded and not was_marked:
		_persuaded += 1
		_refresh_title()


func _render_entry(npc_name: String, stance: int, persuaded: bool) -> void:
	var lbl: Label = _entries[npc_name]
	if persuaded:
		lbl.text = "✓ %s" % npc_name
		lbl.add_theme_color_override("font_color", PERSUADED_COLOR)
	else:
		lbl.text = "  %s (%d/%d)" % [npc_name, stance, 70]
		lbl.add_theme_color_override("font_color", TEXT_COLOR)
	lbl.set_meta("persuaded", persuaded)


func _refresh_title() -> void:
	if _title:
		_title.text = "说服进度 %d / %d" % [_persuaded, _target]
