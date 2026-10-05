extends Node
## Hides army stacks and military bases on the political map (Main.полит_карта). The simulation is not touched:
## the map's own lists (отряды_карты, базы_карты) are swapped for filtered copies. This runs twice a frame —
## before the game's code (priority -1000) and after it (+1000, the Late child) — so whatever the game puts
## there during the frame is filtered before the map draws. Switching a layer back on returns the game's list.

const Names024 := preload("res://mods/pax_corptimizer/src/shared/names024.gd")
const ARMIES := "отряды_карты"
const BASES := "базы_карты"
const OURS := "наш"
const REDRAW: PackedStringArray = ["холст", "слой_значков", "слой", "слой_линий"]

var hide_foreign := false
var hide_own := false
var hide_bases := false

var _map: Object = null
var _stash := {}       # prop -> the game's latest full list
var _given := {}       # prop -> the filtered list we put into the map
var _given_size := {}  # prop -> its size when we put it (the game may refill it in place)


class Late extends Node:
	var on_frame: Callable

	func _process(_delta: float) -> void:
		on_frame.call()


func _ready() -> void:
	process_priority = -1000
	var late := Late.new()
	late.name = "Late"
	late.on_frame = apply
	late.process_priority = 1000
	add_child(late)


func _process(_delta: float) -> void:
	apply()


func active() -> bool:
	return hide_foreign or hide_own or hide_bases


func set_map(map: Object) -> void:
	if map == _map:
		return
	_map = map
	_stash.clear()
	_given.clear()
	_given_size.clear()


## Call after changing hide_* flags: gives the game's lists back, then filters with the new rules.
func refresh() -> void:
	if _map != null and is_instance_valid(_map):
		for prop: String in _given.keys():
			if is_same(Names024.get_of(_map, prop), _given[prop]) and _stash.has(prop):
				Names024.set_of(_map, prop, _stash[prop])
	_stash.clear()
	_given.clear()
	_given_size.clear()
	apply()
	_invalidate()


func apply() -> void:
	if _map == null or not is_instance_valid(_map) or not active():
		return
	var changed := false
	if hide_foreign or hide_own:
		changed = _filter(ARMIES) or changed
	if hide_bases:
		changed = _filter(BASES) or changed
	if changed:
		_invalidate()


## Units hidden right now (for the report).
func hidden_count() -> int:
	var n := 0
	for prop: String in _given.keys():
		var full: Variant = _stash.get(prop)
		if full is Array:
			n += (full as Array).size() - int(_given_size[prop])
	return n


func _filter(prop: String) -> bool:
	var cur_v: Variant = Names024.get_of(_map, prop)
	if not (cur_v is Array):
		return false
	var cur: Array = cur_v
	var ours_now := _given.has(prop) and is_same(cur, _given[prop])
	if ours_now and cur.size() == int(_given_size[prop]):
		return false
	# A new list from the game, or ours refilled in place: that is the game's full list now.
	var source: Array = cur.duplicate() if ours_now else cur
	_stash[prop] = source
	var out: Array = source.duplicate()
	out.clear()
	for item: Variant in source:
		if _keep(item, prop):
			out.append(item)
	Names024.set_of(_map, prop, out)
	_given[prop] = out
	_given_size[prop] = out.size()
	return true


func _keep(item: Variant, prop: String) -> bool:
	if prop == BASES:
		return false
	if not (item is Dictionary):
		return true
	var ours: bool = bool((item as Dictionary).get(OURS, false))
	return not hide_own if ours else not hide_foreign


func _invalidate() -> void:
	if _map == null or not is_instance_valid(_map):
		return
	# The map caches its stacks per frame (_кэш_стопок / _кадр_стопок): make it rebuild from the new list.
	if Names024.get_of(_map, "_кадр_стопок") is int:
		Names024.set_of(_map, "_кадр_стопок", -1)
	for prop: String in REDRAW:
		var c: Variant = Names024.get_of(_map, prop)
		if is_instance_valid(c) and c is CanvasItem:
			(c as CanvasItem).queue_redraw()
