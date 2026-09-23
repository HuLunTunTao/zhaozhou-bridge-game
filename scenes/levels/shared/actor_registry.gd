class_name ActorRegistry
extends RefCounted

## 单位注册表（Shared Kernel / Social Stack）：按 id / node_name / role / cell 注册与查询。
## 不依赖 TeamData / teams —— 自由移动社交关卡用（验桥日等），为 bridge_tour 迁移铺路。
## 约定：格子探测走鸭子类型 `cell: Vector2i` 属性（Unit 与伪 actor 皆然）；
## role 读 meta "npc_role"（验桥日 convention）。

signal actor_registered(actor: Node2D)
signal actor_unregistered(actor: Node2D)

# ─── 内部状态 ───
## id: String -> Node2D（约定 id = UnitData.unit_id）
var _by_id: Dictionary = {}
## node_name: String -> Node2D（约定 node_name = Node.name）
var _by_node_name: Dictionary = {}
var _hero: Node2D = null
var _actors: Array[Node2D] = []


## 注册一个 actor。id / node_name 非空时建索引；is_hero=true 时同时设为主角。
## 重复注册同一 actor 只更新索引，不重复入列表。
func register(actor: Node2D, id: String = "", node_name: String = "", is_hero: bool = false) -> void:
	if actor == null:
		return
	if not _actors.has(actor):
		_actors.append(actor)
	if not id.is_empty():
		_by_id[id] = actor
	if not node_name.is_empty():
		_by_node_name[node_name] = actor
	if is_hero:
		_hero = actor
	actor_registered.emit(actor)


## 注销一个 actor，并清掉它在 id / node_name / hero 侧的痕迹。幂等。
func unregister(actor: Node2D) -> void:
	if actor == null or not _actors.has(actor):
		return
	_actors.erase(actor)
	_erase_refs(_by_id, actor)
	_erase_refs(_by_node_name, actor)
	if _hero == actor:
		_hero = null
	actor_unregistered.emit(actor)


## 清空全部注册（不发信号）。
func clear() -> void:
	_by_id.clear()
	_by_node_name.clear()
	_hero = null
	_actors.clear()


func get_hero() -> Node2D:
	return _hero


func set_hero(actor: Node2D) -> void:
	_hero = actor


func get_by_id(id: String) -> Node2D:
	return _by_id.get(id, null)


func get_by_node_name(node_name: String) -> Node2D:
	return _by_node_name.get(node_name, null)


func get_all() -> Array[Node2D]:
	return _actors.duplicate()


## 全部 actor 中排除 hero。
func get_npcs() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for actor in _actors:
		if actor != _hero:
			out.append(actor)
	return out


## 指定格子上的所有 actor（遍历查 `cell` 属性）。
func get_at_cell(cell: Vector2i) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for actor in _actors:
		if is_instance_valid(actor) and "cell" in actor and actor.cell == cell:
			out.append(actor)
	return out


## 按 meta "npc_role" 匹配 role 的 actor（验桥日 convention）。
func get_by_role(role: String) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for actor in _actors:
		if is_instance_valid(actor) and String(actor.get_meta("npc_role", "")) == role:
			out.append(actor)
	return out


func has_actor(actor: Node2D) -> bool:
	return _actors.has(actor)


## 从索引字典里清掉指向 actor 的全部条目。
func _erase_refs(map: Dictionary, actor: Node2D) -> void:
	for key in map.keys():
		if map[key] == actor:
			map.erase(key)
