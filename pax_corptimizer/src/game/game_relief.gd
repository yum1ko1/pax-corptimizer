extends Node
## «Разгрузка игры»: the game's own work in a frame made lighter without touching its scripts (game 0.24 — found in its
## code, src/core/FrameLoop.gd and around). A node before the game's frame (process_priority −10) and one after it (+10):
##   holdings — the political colours and borders of the Earth (ProvinceSystem.refresh_holdings: every province through
##              province_known, two images, the borders' diff, the map's markers) were redone up to 4 times a second,
##              on every change of an owner (in a war — nearly every check). Here the changes are gathered and the
##              repaint comes at most once in «interval» — longer where one repaint costs more on this computer
##              (40× its time, 0.75…3 s). The player's own actions still repaint at once (the game calls it directly).
##   vehicles — the animated machines and stations (Vehicles3D: rovers, rigs, landers; OrbitalBody: station rings and
##              lights) keep their _process on hidden bodies; there it is paused, back when the body is seen.
##   ambience — the planet's sounds and status line (Atmosphere.set_up, 4 times a second) — twice a second;
##   map icons — the units and vehicles on the open map (markers_to_map, once a second) — every 2 s;
##   map layer — the caravans' routes kept the layer canvas redrawing 10 times a second even with the trade layer off
##              (they are drawn only with it on): with it off their list is emptied after the game fills it; the
##              cache of unit chip styles (a new StyleBox for nearly every redraw of a selection, never cleared) is
##              cleared when it grows past 256.
##   during a time skip (rewind_state.rewinding) no repaint at all: the skip repaints once at its end
##              (RewindSystem.advance), the steps between drew borders nobody saw;
##   settings  — every step of the simulation asked the game's setting «historical_course» (HistoryCourse.step); not in
##              the menu's settings, the game opened and parsed user://settings.json from the disk each time. The value
##              the game reads is put into the menu's settings once (the same value — nothing else changes).
## Off (setting «relief»): everything back as the game had it.

const GameApi := preload("res://mods/pax_corptimizer/src/shared/game_api.gd")
const VEHICLES := "res://src/ui/Vehicles3D.gd"
const ORBITAL := "res://src/space/OrbitalBody.gd"
const SCAN_S := 2.0

var app: Node
var game: PaxGame
var enabled := true
var _after: After
var _since_paint := 99.0
var _paint_cost_ms := 0.0
var _pending := false
var _frozen: Array = []            # nodes whose _process we paused
var _movers: Array = []            # the animated machines found on the bodies [node, body index]
var _scan := 0.0
var stats := {"repaints": 0, "skipped": 0, "frozen": 0}


func setup(host: Node) -> void:
	app = host
	name = "PaxCorptimizerRelief"
	process_priority = -10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_after = After.new()
	_after.name = "After"
	_after.process_priority = 10   # after the game's root (0): its clocks were just reset
	_after.process_mode = Node.PROCESS_MODE_ALWAYS
	_after.done = _post_frame
	add_child(_after)


## The second half: runs after the game's frame.
class After extends Node:
	var done: Callable

	func _process(_delta: float) -> void:
		if done.is_valid():
			done.call()


func start(g: PaxGame) -> void:
	game = g
	_frozen.clear()
	_movers.clear()
	_scan = 0.0
	_pending = false
	_settings_done = false


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		restore()


func _root() -> Object:
	if game == null or not is_instance_valid(game.main):
		return null
	return game.main


# ---------- before the game's frame ----------

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var root := _root()
	if root == null or not enabled:
		return
	_holdings(root, delta)
	_vehicles(root, delta)
	_settings_once(root)
	GameApi.perf("corptimizer.relief", t0)


func _holdings(root: Object, delta: float) -> void:
	var model: Variant = root.get("model")
	if model == null:
		return
	var ep: Variant = (model as Object).get("earth_provinces")
	if ep == null:
		return
	_since_paint += delta
	var ver := int((ep as Object).get("version"))
	var seen := int(root.get("_holdings_version"))
	if ver != seen:
		# A change of owners: the game would repaint at its next check (FrameLoop._frame_ambience). Gathered here.
		root.set("_holdings_version", ver)
		_pending = true
		stats["skipped"] = int(stats["skipped"]) + 1
	var interval := clampf(_paint_cost_ms * 0.04, 0.75, 3.0)
	var rs: Variant = root.get("rewind_state")
	if rs is Object and bool((rs as Object).get("rewinding")):
		return   # the skip repaints once when it ends
	if _pending and _since_paint >= interval:
		_pending = false
		_since_paint = 0.0
		var provinces: Variant = root.call("provinces")
		if provinces is Object:
			var t := Time.get_ticks_usec()
			(provinces as Object).call("refresh_holdings")
			_paint_cost_ms = lerpf(_paint_cost_ms, float(Time.get_ticks_usec() - t) / 1000.0, 0.5)
			stats["repaints"] = int(stats["repaints"]) + 1


var _settings_done := false


func _settings_once(root: Object) -> void:
	if _settings_done:
		return
	var ui: Variant = root.get("ui")
	var menu: Variant = (ui as Object).get("menu_node") if ui is Object else null
	if not (menu is Object) or not is_instance_valid(menu):
		return
	var st: Variant = (menu as Object).get("settings")
	if not (st is Dictionary):
		return
	_settings_done = true
	if not (st as Dictionary).has("historical_course") and root.has_method("_setting"):
		(st as Dictionary)["historical_course"] = root.call("_setting", "historical_course", true)


## The animated machines of the bodies not seen now: their _process paused (they only turn and blink).
func _vehicles(root: Object, delta: float) -> void:
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_S
		_find_movers(root)
	for i in range(_movers.size() - 1, -1, -1):
		var n: Variant = _movers[i]
		if not is_instance_valid(n):
			_movers.remove_at(i)
			continue
		var node := n as Node3D
		var seen := node.is_visible_in_tree()
		if not seen and node.process_mode != Node.PROCESS_MODE_DISABLED:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			_frozen.append(node)
		elif seen and node.process_mode == Node.PROCESS_MODE_DISABLED and _frozen.has(node):
			node.process_mode = Node.PROCESS_MODE_INHERIT
			_frozen.erase(node)
	stats["frozen"] = _frozen.size()


func _find_movers(root: Object) -> void:
	var model: Variant = root.get("model")
	if model == null:
		return
	var bodies: Variant = (model as Object).get("bodies")
	if not (bodies is Array):
		return
	var found: Array = []
	for b in bodies:
		if not (b is Dictionary):
			continue
		var node: Variant = (b as Dictionary).get("node")
		if not (node is Node) or not is_instance_valid(node):
			continue
		_collect(node as Node, found, 0)
	_movers = found


func _collect(n: Node, into: Array, depth: int) -> void:
	for ch in n.get_children():
		var s: Variant = ch.get_script()
		if s is Script and ((s as Script).resource_path == VEHICLES or (s as Script).resource_path == ORBITAL):
			into.append(ch)
		elif depth < 2 and ch.get_child_count() > 0 and ch.get_child_count() < 400:
			_collect(ch, into, depth + 1)


# ---------- after the game's frame ----------

## After the game's frame: the clocks it just reset are stretched, the map's layer lightened.
func _post_frame() -> void:
	var root := _root()
	if root == null or not enabled:
		return
	var fl: Variant = root.call("frame_loop") if root.has_method("frame_loop") else null
	if not (fl is Object):
		return
	var flo := fl as Object
	# The game sets them to exactly 0.25 s and 1 s when they run out (counting down otherwise): the next run later.
	if float(flo.get("_ambience_clock")) == 0.25:
		flo.set("_ambience_clock", 0.5)
	if float(flo.get("_map_vehicles_clock")) == 1.0:
		flo.set("_map_vehicles_clock", 2.0)
	_map_layer(root)


func _map_layer(root: Object) -> void:
	var map: Variant = root.get("political_map")
	if not (map is CanvasLayer) or not is_instance_valid(map) or not (map as CanvasLayer).visible:
		return
	var m := map as Object
	var layers: Variant = m.get("layers_m")
	if layers is Dictionary and not bool((layers as Dictionary).get("trade", true)):
		var caravans: Variant = m.get("map_caravans")
		if caravans is Array and not (caravans as Array).is_empty():
			m.set("map_caravans", [])
	var styles: Variant = m.get("_chip_styles")
	if styles is Dictionary and (styles as Dictionary).size() > 256:
		(styles as Dictionary).clear()


func restore() -> void:
	for n in _frozen:
		if is_instance_valid(n):
			(n as Node).process_mode = Node.PROCESS_MODE_INHERIT
	_frozen.clear()
	if _pending:
		_pending = false
		var root := _root()
		if root != null:
			root.set("_holdings_version", -1)   # the game repaints at its next check


func _exit_tree() -> void:
	restore()
