extends Node
## Map tuning found by the measurements:
## - Layer redraws: the map redraws its layer canvas (20–80 ms of _draw each time) when its timer
##   map._часы_слоёв runs up to a period and resets — about half of the heavy redraws come from it. Each frame,
##   right after the map's own code, the timer's growth since the last frame is divided by the slow factor, so
##   the resets (and the redraws) come that many times less often. Only growth is touched: a reset or a timer
##   that counts down is left alone.
##   layer_slow = AUTO: adaptive quality — the factor follows the measured cost of a heavy redraw (timeline.gd)
##   so that heavy redraws take about BUDGET of the time: cheap redraws stay frequent, costly ones get rarer.
## - 3D under the map: while the political map is open the 3D scene (planet, space) behind it is not seen, but
##   costs ~2.5 ms a frame. With `no_3d_under_map` the root viewport stops rendering 3D until the map closes.
## - FPS cap: Engine.max_fps while the game runs (0 — the game's own setting). Steady frame pacing, and the
##   freed time goes to the OS, the drivers and the worker threads.

const Names024 := preload("res://mods/pax_corptimizer/src/shared/names024.gd")
const Timeline := preload("res://mods/pax_corptimizer/src/profiler/timeline.gd")
const TIMER := "_часы_слоёв"
const AUTO := 0
const BUDGET := 0.04          # share of time the heavy layer redraws may take in AUTO
const AUTO_MIN := 1.0
const AUTO_MAX := 8.0
const HEAVY: PackedStringArray = ["слой", "холст"]

var layer_slow := 1           # AUTO or a fixed factor 1, 2, 4
var no_3d_under_map := false
var fps_cap := 0
var cover: Node               # skip_cover.gd: while it is active it owns disable_3d
var timeline: Timeline

var auto_factor := 1.0        # the factor AUTO uses now (shown in the report)
var redraw_cost_ms := 0.0     # running average cost of a heavy redraw

var _map: CanvasLayer = null
var _prev := -1.0
var _3d_off := false
var _serial := 0
var _last_heavy_msec := 0
var _game_fps := -1           # Engine.max_fps before our cap


func _ready() -> void:
	process_priority = 1000   # after the game's code, before drawing


func set_map(map: CanvasLayer) -> void:
	if map == _map:
		return
	_map = map
	_prev = -1.0


func set_fps_cap(cap: int) -> void:
	fps_cap = maxi(0, cap)
	if fps_cap > 0:
		if _game_fps < 0:
			_game_fps = Engine.max_fps
		Engine.max_fps = fps_cap
	elif _game_fps >= 0:
		Engine.max_fps = _game_fps
		_game_fps = -1


func release() -> void:
	if _3d_off:
		get_tree().root.disable_3d = false
	_3d_off = false
	_prev = -1.0
	set_fps_cap(0)


func slow_factor() -> float:
	return auto_factor if layer_slow == AUTO else float(maxi(1, layer_slow))


func _process(_delta: float) -> void:
	var map_open := is_instance_valid(_map) and _map.visible
	var cover_on := cover != null and bool(cover.get("active"))
	if not cover_on:
		var root := get_tree().root
		var want_off := no_3d_under_map and map_open
		if want_off and not _3d_off and not root.disable_3d:
			root.disable_3d = true
			_3d_off = true
		elif not want_off and _3d_off:
			root.disable_3d = false
			_3d_off = false
	if map_open and layer_slow == AUTO:
		_adapt()
	var k := slow_factor()
	if not map_open or k <= 1.0:
		_prev = -1.0
		return
	var v_v: Variant = Names024.get_of(_map, TIMER)
	if not (v_v is float):
		return
	var v: float = v_v
	if _prev >= 0.0 and v > _prev:
		v = _prev + (v - _prev) / k
		Names024.set_of(_map, TIMER, v)
	_prev = v


## AUTO: after every heavy redraw compare the time since the previous one with what its cost allows.
func _adapt() -> void:
	if timeline == null or timeline.frame_serial == _serial:
		return
	_serial = timeline.frame_serial
	var f: Dictionary = timeline.last
	var redrawn: PackedStringArray = f.get("redrawn", PackedStringArray())
	if not (redrawn.has(HEAVY[0]) or redrawn.has(HEAVY[1])):
		return
	var cost: float = float(f.get("draw", 0.0))
	redraw_cost_ms = cost if redraw_cost_ms <= 0.0 else lerpf(redraw_cost_ms, cost, 0.2)
	var now := Time.get_ticks_msec()
	if _last_heavy_msec > 0:
		var interval := (now - _last_heavy_msec) / 1000.0
		var wanted := clampf(redraw_cost_ms / 1000.0 / BUDGET, 0.1, 3.0)
		if interval < wanted:
			auto_factor = minf(AUTO_MAX, auto_factor * 1.25)
		elif interval > wanted * 1.5:
			auto_factor = maxf(AUTO_MIN, auto_factor / 1.25)
	_last_heavy_msec = now
