extends Node
## Main-thread timeline of every frame, split into segments by marker nodes placed in the process order:
##   start (this node, priority -1001) → autoloads and mods (a marker after each mod → time per mod) → A (right
##   before Main) → Main._process → B (Main's first internal child) → the rest of Main's children → C (right
##   before the map) → map._process → D (map's first internal child) → everything else → end (+1001) → _draw of
##   canvas items, deferred calls, timers, resumed awaits → frame_pre_draw → rendering → frame_post_draw →
##   input, physics, OS → next start.
## Markers are internal children: the game's get_child() indices do not move. A missing marker merges its
## segment into the next one. A marker whose host keeps disappearing is given up after a few tries.

## Stamp key → the segment that ends at it.
const Names024 := preload("res://mods/pax_corptimizer/src/shared/names024.gd")
const ORDER: Array = [["a", "mods"], ["b", "main"], ["c", "ui"], ["d", "map"], ["end", "rest"], ["pre", "draw"], ["post", "render"]]
const SEGMENTS: PackedStringArray = ["mods", "main", "ui", "map", "rest", "draw", "render", "gap"]
## Canvas items of the map whose redraws are counted.
const DRAW_ITEMS: PackedStringArray = ["холст", "слой", "слой_линий", "фон", "показ_фигурок"]
const MOD_PREFIX := "m:"
const REPLACE_EVERY_MSEC := 2000

var last := {}          # the last finished frame: {"frame": ms, <segment>: ms, "redrawn": [...], "by_mod": {id: ms}}
var frame_serial := 0   # grows every time `last` is replaced

var _s := {}
var _redrawn := PackedStringArray()
var _markers := {}       # key -> Marker
var _placers := {}       # key -> Callable that places that marker again
var _replaced := {}      # key -> how many times it had to be placed again
var _replaced_at := {}   # key -> msec of the last time
var _draw_links: Array = []   # [CanvasItem, Callable]
var _map: Object = null
var _main: Object = null
var _main_thread := 0


class Marker extends Node:
	var key := ""
	var sink: Callable

	func _process(_delta: float) -> void:
		sink.call(key)


func _ready() -> void:
	process_priority = -1001
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main_thread = OS.get_main_thread_id()
	var end := _marker("end")
	end.process_priority = 1001
	add_child(end)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _s.has("start"):
		_close(now)
	_s = {"start": now}
	_redrawn = PackedStringArray()


func stamp(key: String) -> void:
	_s[key] = Time.get_ticks_usec()


# With a separate render thread these may come from it: only the main thread's view is measured here.
func _on_pre_draw() -> void:
	if OS.get_thread_caller_id() == _main_thread:
		_s["pre"] = Time.get_ticks_usec()


func _on_post_draw() -> void:
	if OS.get_thread_caller_id() == _main_thread:
		_s["post"] = Time.get_ticks_usec()


func _close(now: int) -> void:
	var f := {}
	var start: int = _s["start"]
	var prev := start
	for pair: Array in ORDER:
		var key: String = pair[0]
		var seg: String = pair[1]
		f[seg] = 0.0
		if _s.has(key) and int(_s[key]) >= prev:
			var t: int = _s[key]
			f[seg] = (t - prev) / 1000.0
			prev = t
	f["gap"] = (now - prev) / 1000.0
	f["frame"] = (now - start) / 1000.0
	f["redrawn"] = _redrawn
	# Time per mod: from the previous mod's marker (or the frame start) to this mod's marker.
	var limit: int = _s.get("a", _s.get("end", now))
	var marks: Array = []
	for k: Variant in _s.keys():
		var key := str(k)
		if key.begins_with(MOD_PREFIX) and int(_s[key]) >= start and int(_s[key]) <= limit:
			marks.append([int(_s[key]), key.substr(MOD_PREFIX.length())])
	marks.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) < int(y[0]))
	var by_mod := {}
	var p := start
	for m: Array in marks:
		by_mod[m[1]] = (int(m[0]) - p) / 1000.0
		p = int(m[0])
	f["by_mod"] = by_mod
	last = f
	frame_serial += 1


## Places the markers around Main, the map and every mod; call again when Main or the map change (check()).
func attach(game: PaxGame) -> void:
	detach()
	if game == null or not is_instance_valid(game.main):
		return
	var main: Node = game.main
	_main = main
	_placers["a"] = func() -> void: _place_before(main, "a")
	_placers["b"] = func() -> void: _add_internal(main, "b", Node.INTERNAL_MODE_FRONT)
	var map_v: Variant = main.get("полит_карта")
	if is_instance_valid(map_v) and map_v is Node:
		var map: Node = map_v
		_map = map
		_placers["c"] = func() -> void: _place_before(map, "c")
		_placers["d"] = func() -> void: _add_internal(map, "d", Node.INTERNAL_MODE_FRONT)
		for prop: String in DRAW_ITEMS:
			var ci: Variant = Names024.get_of(map, prop)
			if is_instance_valid(ci) and ci is CanvasItem:
				var item_key := prop
				var cb := func() -> void: _on_item_draw(item_key)
				(ci as CanvasItem).draw.connect(cb)
				_draw_links.append([ci, cb])
	var insts: Variant = Pax.instances
	if insts is Dictionary:
		for id_v: Variant in (insts as Dictionary).keys():
			var n: Variant = (insts as Dictionary)[id_v]
			if is_instance_valid(n) and n is Node:
				var host: Node = n
				var key := MOD_PREFIX + str(id_v)
				_placers[key] = func() -> void: _add_internal(host, key, Node.INTERNAL_MODE_BACK)
	for key: Variant in _placers.keys():
		(_placers[key] as Callable).call()


## False when Main or the map were replaced (attach again). Lost markers are put back here, a few times at most.
func check(game: PaxGame) -> bool:
	if game == null or not is_instance_valid(game.main) or game.main != _main:
		return false
	var map_v: Variant = game.main.get("полит_карта")
	var map: Object = map_v as Object if is_instance_valid(map_v) and map_v is Object else null
	if map != _map:
		return false
	var now := Time.get_ticks_msec()
	for key: Variant in _placers.keys():
		if _alive(key):
			continue
		if now - int(_replaced_at.get(key, -REPLACE_EVERY_MSEC)) < REPLACE_EVERY_MSEC:
			continue
		_replaced_at[key] = now
		_replaced[key] = int(_replaced.get(key, 0)) + 1
		(_placers[key] as Callable).call()
	return true


## For the report: {marker key: {"alive": bool, "replaced": times it had to be put back}}.
func status() -> Dictionary:
	var out := {}
	for key: Variant in _placers.keys():
		out[key] = {"alive": _alive(key), "replaced": int(_replaced.get(key, 0))}
	return out


## A marker is alive when it exists and is inside the tree (a host taken out of the tree stops processing).
func _alive(key: Variant) -> bool:
	var m: Variant = _markers.get(key)
	return is_instance_valid(m) and m is Node and (m as Node).is_inside_tree()


func detach() -> void:
	for m: Variant in _markers.values():
		if is_instance_valid(m) and m is Node:
			(m as Node).queue_free()
	_markers.clear()
	_placers.clear()
	_replaced.clear()
	_replaced_at.clear()
	for link: Variant in _draw_links:
		var l: Array = link
		var ci: Variant = l[0]
		var cb: Callable = l[1]
		if is_instance_valid(ci) and ci is CanvasItem and (ci as CanvasItem).draw.is_connected(cb):
			(ci as CanvasItem).draw.disconnect(cb)
	_draw_links.clear()
	_map = null
	_main = null


func _on_item_draw(name_key: String) -> void:
	if not _redrawn.has(name_key):
		_redrawn.append(name_key)


func _marker(key: String) -> Marker:
	var m := Marker.new()
	m.name = "PaxCorptimizerMark_" + key.replace(":", "_")
	m.key = key
	m.sink = stamp
	m.process_mode = Node.PROCESS_MODE_ALWAYS
	return m


func _add_internal(parent: Node, key: String, mode: Node.InternalMode) -> void:
	if not is_instance_valid(parent):
		return
	var old: Variant = _markers.get(key)
	if is_instance_valid(old) and old is Node:
		(old as Node).queue_free()
	var m := _marker(key)
	parent.add_child(m, false, mode)
	_markers[key] = m


## A marker that runs right before `node`: the last internal child of its previous sibling (after that
## sibling's whole subtree), or the first internal child of the parent when `node` is the first child.
func _place_before(node: Node, key: String) -> void:
	if not is_instance_valid(node):
		return
	var parent := node.get_parent()
	if parent == null:
		return
	var idx := node.get_index()
	if idx > 0:
		_add_internal(parent.get_child(idx - 1), key, Node.INTERNAL_MODE_BACK)
	else:
		_add_internal(parent, key, Node.INTERNAL_MODE_FRONT)
