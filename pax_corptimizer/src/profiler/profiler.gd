extends Node
## Frame measurements for Pax Corptimizer, built on the main-thread timeline (src/timeline.gd).
## Two numbers matter and are kept apart: the steady frame (median — what FPS feels like) and spikes (frames
## over 33 ms per second — what is felt as lag). An average mixes them and hides both.
## Live: the last half second. Session: spikes with their timeline (where the time went), sim steps.
## Analysis (A/B): each suspect is switched off for MEASURE seconds and measured, then switched back and measured
## again. The report goes to mod_data/pax_corptimizer/report.json (save_data) and to the window.

signal progress(text: String)
signal finished(text: String)

const Names024 := preload("res://mods/pax_corptimizer/src/shared/names024.gd")
const ArmyHider := preload("res://mods/pax_corptimizer/src/map/armies.gd")
const Timeline := preload("res://mods/pax_corptimizer/src/profiler/timeline.gd")
const MapTuner := preload("res://mods/pax_corptimizer/src/map/map_tuner.gd")
const SkipCover := preload("res://mods/pax_corptimizer/src/skip/skip_cover.gd")

const SETTLE := 0.6
const MEASURE := 2.5
const BASE_MEASURE := 1.5
const LIVE_EVERY := 0.5
const SPIKE_MS := 33.0
const SLOWEST := 15
const TEST_LAYER_SLOW := 4
## Map lists whose size says how much the map draws every frame.
const MAP_LISTS: PackedStringArray = ["отряды_карты", "базы_карты", "бои_карты", "фронт_карты", "показатели_карты",
	"связи_карты", "пути_карты", "караваны_карты", "авиарейсы_карты", "промыслы_карты", "подписи", "постройки_карты"]

var mod: PaxMod
var hider: ArmyHider
var timeline: Timeline
var tuner: MapTuner
var cover: SkipCover
var running := false
var last_text := ""
var last_plain := ""

var _game: PaxGame
var _serial := 0
var _rec := false
var _rec_frames: Array = []
var _live_frames: Array = []
var _live_t := 0.0
var _live := {}
var _sess := {}
var _slowest: Array = []
var _step_frame := -1
var _undo := Callable()


func _ready() -> void:
	process_priority = -1000
	Pax.days_passed.connect(_on_days)


func start(game: PaxGame) -> void:
	if running:
		_abort()
	_game = game
	_sess = {"frames": 0, "time": 0.0, "spikes": 0, "s50": 0, "s100": 0, "steps": 0, "days": 0,
		"step_frames": 0, "step_ms": 0.0, "step_max": 0.0, "seg": _zero_segs(), "spike_seg": _zero_segs(), "redraws": {},
		"by_mod": {}, "spike_by_mod": {}, "skip_frames": 0, "skip_ms": 0.0, "skip_max": 0.0, "redraw_frames": 0}
	_slowest = []
	_step_frame = -1
	_serial = timeline.frame_serial
	_trig_setup()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _on_days(_g: PaxGame, _from_day: int, days: int) -> void:
	_step_frame = Engine.get_process_frames()
	if not _sess.is_empty():
		_sess["steps"] = int(_sess["steps"]) + 1
		_sess["days"] = int(_sess["days"]) + days


func _process(delta: float) -> void:
	if _game == null or Pax.game != _game:
		if running:
			_abort()
		return
	if timeline.frame_serial == _serial:
		return
	_serial = timeline.frame_serial
	# timeline.last is the frame that has just ended (the previous process frame).
	var f: Dictionary = timeline.last.duplicate()
	var now_frame := Engine.get_process_frames()
	var step := _step_frame >= 0 and _step_frame < now_frame
	if step:
		_step_frame = -1
	var rid := get_viewport().get_viewport_rid()
	f["step"] = step
	f["gpu"] = RenderingServer.viewport_get_measured_render_time_gpu(rid)
	f["draws"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	f["map_on"] = _map_visible()
	if _rec:
		_rec_frames.append(f)
	_live_frames.append(f)
	_live_t += delta
	if _live_t >= LIVE_EVERY:
		_live = _summary(_live_frames, _live_t)
		_live_frames = []
		_live_t = 0.0
	if running or now_frame < 60:
		return
	_session_add(f, delta)


func _session_add(f: Dictionary, delta: float) -> void:
	var ms: float = f["frame"]
	_sess["frames"] = int(_sess["frames"]) + 1
	_sess["time"] = float(_sess["time"]) + delta
	_add_segs(_sess["seg"], f)
	var redraws: Dictionary = _sess["redraws"]
	var redrawn: PackedStringArray = f["redrawn"]
	for item: String in redrawn:
		redraws[item] = int(redraws.get(item, 0)) + 1
	var by_mod: Dictionary = f.get("by_mod", {})
	_add_by_mod(_sess["by_mod"], by_mod)
	if ms > SPIKE_MS:
		_add_by_mod(_sess["spike_by_mod"], by_mod)
	if not cover.skipping_flag().is_empty():
		_sess["skip_frames"] = int(_sess["skip_frames"]) + 1
		_sess["skip_ms"] = float(_sess["skip_ms"]) + ms
		_sess["skip_max"] = maxf(float(_sess["skip_max"]), ms)
	if bool(f["map_on"]):
		var heavy := redrawn.has("слой") or redrawn.has("холст")
		if heavy:
			_sess["redraw_frames"] = int(_sess["redraw_frames"]) + 1
		_trig_step(heavy)
	if bool(f["step"]):
		_sess["step_frames"] = int(_sess["step_frames"]) + 1
		_sess["step_ms"] = float(_sess["step_ms"]) + ms
		_sess["step_max"] = maxf(float(_sess["step_max"]), ms)
	if ms > SPIKE_MS:
		_sess["spikes"] = int(_sess["spikes"]) + 1
		_add_segs(_sess["spike_seg"], f)
		if ms > 50.0:
			_sess["s50"] = int(_sess["s50"]) + 1
		if ms > 100.0:
			_sess["s100"] = int(_sess["s100"]) + 1
	if _slowest.size() < SLOWEST or ms > float((_slowest[_slowest.size() - 1] as Dictionary)["frame"]):
		var rec := {}
		for k: String in Timeline.SEGMENTS:
			rec[k] = snappedf(float(f[k]), 0.01)
		rec["frame"] = snappedf(ms, 0.01)
		rec["step"] = f["step"]
		rec["map_on"] = f["map_on"]
		rec["redrawn"] = Array(f["redrawn"] as PackedStringArray)
		_slowest.append(rec)
		_slowest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["frame"]) > float(b["frame"]))
		if _slowest.size() > SLOWEST:
			_slowest.resize(SLOWEST)


static func _add_by_mod(acc: Dictionary, by_mod: Dictionary) -> void:
	for id: Variant in by_mod.keys():
		var k := str(id)
		var cur: Array = acc.get(k, [0.0, 0.0, 0])   # [sum ms, max ms, frames]
		var v: float = float(by_mod[id])
		acc[k] = [float(cur[0]) + v, maxf(float(cur[1]), v), int(cur[2]) + 1]


static func _by_mod_report(acc: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in acc.keys():
		var cur: Array = acc[k]
		out[k] = {"avg": snappedf(float(cur[0]) / maxf(1.0, float(cur[2])), 0.01), "max": snappedf(float(cur[1]), 0.01)}
	return out


# ---------- what makes the map redraw ----------
# Every frame the numeric fields of the map and of Main are sampled. A field «fires» when an int changes or a
# float timer drops (is reset). Fields that fire in the same frames as the heavy redraws of the map (слой/холст)
# are what triggers them.

var _trig_props: Array = []   # [label, Object, property, is_float]
var _trig_prev := {}
var _trig := {}               # label -> [fired with a redraw, fired without one]


func _trig_setup() -> void:
	_trig_props = []
	_trig_prev = {}
	_trig = {}
	var targets := {"main": _game.main}
	var map := _map()
	if map != null:
		targets["map"] = map
	for label: String in targets.keys():
		var obj: Object = targets[label]
		for p: Dictionary in obj.get_property_list():
			var usage: int = p.get("usage", 0)
			var type: int = p.get("type", 0)
			if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and (type == TYPE_INT or type == TYPE_FLOAT):
				_trig_props.append([label + "." + str(p["name"]), obj, str(p["name"]), type == TYPE_FLOAT])


func _trig_step(heavy: bool) -> void:
	for entry: Variant in _trig_props:
		var e: Array = entry
		var obj: Variant = e[1]
		if not is_instance_valid(obj):
			continue
		var label: String = e[0]
		var v: float = float((obj as Object).get(str(e[2])))
		if _trig_prev.has(label):
			var prev: float = _trig_prev[label]
			var fired := v < prev if bool(e[3]) else v != prev
			if fired:
				var cur: Array = _trig.get(label, [0, 0])
				_trig[label] = [int(cur[0]) + (1 if heavy else 0), int(cur[1]) + (0 if heavy else 1)]
		_trig_prev[label] = v


## The fields that fire most often together with the heavy redraws: [{field, with, without, coverage %}].
func _trig_top() -> Array:
	var redraw_frames := maxf(1.0, float(_sess.get("redraw_frames", 0)))
	var rows: Array = []
	for label: Variant in _trig.keys():
		var cur: Array = _trig[label]
		if int(cur[0]) < 3:
			continue
		rows.append({"field": label, "with": cur[0], "without": cur[1],
			"coverage": snappedf(100.0 * float(cur[0]) / redraw_frames, 0.1),
			"precision": snappedf(100.0 * float(cur[0]) / maxf(1.0, float(cur[0]) + float(cur[1])), 0.1)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["coverage"]) + float(a["precision"]) > float(b["coverage"]) + float(b["precision"]))
	if rows.size() > 8:
		rows.resize(8)
	return rows


static func _zero_segs() -> Dictionary:
	var d := {}
	for k: String in Timeline.SEGMENTS:
		d[k] = 0.0
	d["n"] = 0
	return d


static func _add_segs(acc: Dictionary, f: Dictionary) -> void:
	for k: String in Timeline.SEGMENTS:
		acc[k] = float(acc[k]) + float(f.get(k, 0.0))
	acc["n"] = int(acc["n"]) + 1


static func _avg_segs(acc: Dictionary) -> Dictionary:
	var out := {}
	var n := maxf(1.0, float(acc.get("n", 0)))
	for k: String in Timeline.SEGMENTS:
		out[k] = snappedf(float(acc.get(k, 0.0)) / n, 0.01)
	return out


# ---------- summaries ----------

## Frames → {n, med, avg, p95, max, fps, spikes_s, seg (avg ms per segment), spike_seg, gpu, draws}.
func _summary(frames: Array, seconds: float) -> Dictionary:
	var n := frames.size()
	if n == 0:
		return {}
	var ms := PackedFloat32Array()
	var seg := _zero_segs()
	var spike_seg := _zero_segs()
	var spikes := 0
	var gpu := 0.0
	var draws := 0.0
	for fv: Variant in frames:
		var f: Dictionary = fv
		var m: float = f["frame"]
		ms.append(m)
		_add_segs(seg, f)
		if m > SPIKE_MS:
			spikes += 1
			_add_segs(spike_seg, f)
		gpu += float(f["gpu"])
		draws += float(f["draws"])
	ms.sort()
	var total := 0.0
	for m: float in ms:
		total += m
	var avg := total / n
	return {"n": n, "med": snappedf(ms[int(n * 0.5)], 0.01), "avg": snappedf(avg, 0.01), "p95": snappedf(ms[mini(n - 1, int(n * 0.95))], 0.01),
		"max": snappedf(ms[n - 1], 0.01), "fps": snappedf(1000.0 / maxf(avg, 0.001), 0.1),
		"spikes_s": snappedf(spikes / maxf(seconds, 0.001), 0.01), "seg": _avg_segs(seg),
		"spike_seg": _avg_segs(spike_seg) if spikes > 0 else {}, "gpu": snappedf(gpu / n, 0.01), "draws": snappedf(draws / n, 1.0)}


func live_text() -> String:
	if _live.is_empty():
		return mod.tr_key("pax_corptimizer_wait")
	var s: Dictionary = _live["seg"]
	return mod.tr_key("pax_corptimizer_live", [_f(_live["fps"], 0), _f(_live["med"], 1), _f(_live["max"], 1),
		_f(_live["spikes_s"], 1), _segs_text(s), _f(_live["gpu"], 1), _f(_live["draws"], 0),
		str(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))])


func _segs_text(s: Dictionary) -> String:
	var parts := PackedStringArray()
	for k: String in Timeline.SEGMENTS:
		parts.append(mod.tr_key("pax_corptimizer_seg_" + k) + " " + _f(s.get(k, 0.0), 1))
	return " · ".join(parts)


# ---------- analysis ----------

func analyze() -> void:
	if running or _game == null:
		return
	running = true
	var game := _game
	var tests := _tests()
	var rows: Array = []
	progress.emit(mod.tr_key("pax_corptimizer_warmup"))
	await _wait(SETTLE)
	var base: Dictionary = await _measure(MEASURE)
	var prev: Dictionary = base
	for i: int in tests.size():
		if not running or Pax.game != game:
			break
		var t: Dictionary = tests[i]
		var key: String = t["key"]
		progress.emit(mod.tr_key("pax_corptimizer_running", [mod.tr_key("pax_corptimizer_t_" + key), str(i + 1), str(tests.size())]))
		var on_c: Callable = t["on"]
		var off_c: Callable = t["off"]
		on_c.call()
		_undo = off_c
		await _wait(SETTLE)
		var with_off: Dictionary = await _measure(MEASURE)
		if _undo.is_valid():
			off_c.call()
		_undo = Callable()
		await _wait(SETTLE)
		var after: Dictionary = await _measure(BASE_MEASURE)
		if with_off.is_empty() or after.is_empty() or prev.is_empty():
			continue
		# The baseline is the mean of the measurements right before and right after: slow drift cancels out.
		var base_med := (float(prev["med"]) + float(after["med"])) * 0.5
		var base_sp := (float(prev["spikes_s"]) + float(after["spikes_s"])) * 0.5
		rows.append({"key": key, "base_med": snappedf(base_med, 0.01), "off_med": with_off["med"],
			"saved_ms": snappedf(base_med - float(with_off["med"]), 0.01),
			"base_spikes_s": snappedf(base_sp, 0.01), "off_spikes_s": with_off["spikes_s"],
			"spikes_cut": snappedf(base_sp - float(with_off["spikes_s"]), 0.01), "off": with_off})
		prev = after
	if not running or Pax.game != game:
		return
	running = false
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["spikes_cut"]) * 10.0 + float(a["saved_ms"]) > float(b["spikes_cut"]) * 10.0 + float(b["saved_ms"]))
	var report := _report(base, rows)
	mod.save_data("report", report)
	last_text = report_text(report, true)
	last_plain = report_text(report, false)
	mod.log_info(last_plain)
	finished.emit(last_text)


func _abort() -> void:
	if _undo.is_valid():
		_undo.call()
	_undo = Callable()
	_rec = false
	running = false
	progress.emit(mod.tr_key("pax_corptimizer_aborted"))


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _measure(sec: float) -> Dictionary:
	_rec_frames = []
	_rec = true
	var t0 := Time.get_ticks_usec()
	await get_tree().create_timer(sec, true, false, true).timeout
	_rec = false
	return _summary(_rec_frames, (Time.get_ticks_usec() - t0) / 1000000.0)


# ---------- suspects ----------

func _tests() -> Array:
	var out: Array = []
	var main: Object = _game.main
	var map := _map()
	var speed_v: Variant = main.get("скорость_наблюдения")
	var speed: int = int(speed_v) if (speed_v is int or speed_v is float) else 0
	if speed > 0:
		out.append(_speed_test(speed))
	if map != null and map.visible:
		out.append(_tuner_test())
		out.append(_hider_test("armies", true, true, false))
		out.append(_hider_test("bases", false, false, true))
		out.append(_layers_test(map))
		out.append(_props_test("icons", [[Names024.get_of(map, "холст"), "visible", false]]))
		out.append(_props_test("lines", [[Names024.get_of(map, "слой_линий"), "visible", false]]))
		out.append(_props_test("surface", [[map.get("слой"), "visible", false]]))
		out.append(_props_test("mapvp", [[map.get("вп"), "render_target_update_mode", SubViewport.UPDATE_DISABLED]]))
		# Never the whole map (map.visible): hiding it makes the game rebuild things for seconds.
	var root := get_tree().root
	out.append(_props_test("world3d", [[root, "disable_3d", true]]))
	out.append(_mods_test())
	return out.filter(func(t: Dictionary) -> bool: return not t.is_empty())


## [[object, property, value while switched off], …] — objects that do not exist are skipped.
func _props_test(key: String, triples: Array) -> Dictionary:
	var live: Array = []
	for entry: Variant in triples:
		var t: Array = entry
		var obj: Variant = t[0]
		var prop: String = t[1]
		if is_instance_valid(obj) and obj is Object and (obj as Object).get(prop) != null:
			live.append(t)
	if live.is_empty():
		return {}
	var old := {}
	var on := func() -> void:
		for i: int in live.size():
			var t: Array = live[i]
			var obj: Variant = t[0]
			var prop: String = t[1]
			if is_instance_valid(obj) and obj is Object:
				old[i] = (obj as Object).get(prop)
				(obj as Object).set(prop, t[2])
	var off := func() -> void:
		for i: int in live.size():
			var t: Array = live[i]
			var obj: Variant = t[0]
			var prop: String = t[1]
			if old.has(i) and is_instance_valid(obj) and obj is Object:
				(obj as Object).set(prop, old[i])
	return {"key": key, "on": on, "off": off}


## All the game's map layers (Tab window) off — through the map's own задать_слои, then the old set back.
func _layers_test(map: CanvasLayer) -> Dictionary:
	var cur: Variant = map.get("слои")
	if not (cur is Dictionary) or not map.has_method("задать_слои"):
		return {}
	var old: Dictionary = (cur as Dictionary).duplicate()
	var off_all := {}
	for k: Variant in old.keys():
		off_all[k] = false
	var on := func() -> void:
		if is_instance_valid(map):
			map.call("задать_слои", off_all.duplicate())
	var off := func() -> void:
		if is_instance_valid(map):
			map.call("задать_слои", old.duplicate())
	return {"key": "layers", "on": on, "off": off}


func _speed_test(speed: int) -> Dictionary:
	var game := _game
	var on := func() -> void: game.set_speed(0)
	var off := func() -> void:
		if Pax.game == game:
			game.set_speed(speed)
	return {"key": "sim", "on": on, "off": off}


## The map tuner's layer timer at x4 (if it is set lower now): how much rarer layer redraws save.
func _tuner_test() -> Dictionary:
	if tuner.layer_slow >= TEST_LAYER_SLOW:
		return {}
	var tu := tuner
	var old := {}
	var on := func() -> void:
		old["v"] = tu.layer_slow
		tu.layer_slow = TEST_LAYER_SLOW
	var off := func() -> void:
		if old.has("v"):
			tu.layer_slow = int(old["v"])
	return {"key": "layerslow", "on": on, "off": off}


func _hider_test(key: String, foreign: bool, own: bool, bases: bool) -> Dictionary:
	var h := hider
	var old := {}
	var on := func() -> void:
		old["f"] = h.hide_foreign
		old["o"] = h.hide_own
		old["b"] = h.hide_bases
		h.hide_foreign = h.hide_foreign or foreign
		h.hide_own = h.hide_own or own
		h.hide_bases = h.hide_bases or bases
		h.refresh()
	var off := func() -> void:
		if old.is_empty():
			return
		h.hide_foreign = bool(old["f"])
		h.hide_own = bool(old["o"])
		h.hide_bases = bool(old["b"])
		h.refresh()
	return {"key": key, "on": on, "off": off}


## Other mods' code: their mod nodes stop processing (their UI on the map keeps drawing).
func _mods_test() -> Dictionary:
	var nodes: Array = []
	var insts: Variant = Pax.instances
	if insts is Dictionary:
		for v: Variant in (insts as Dictionary).values():
			if is_instance_valid(v) and v is Node and v != mod:
				nodes.append(v)
	if nodes.is_empty():
		return {}
	var old := {}
	var on := func() -> void:
		for i: int in nodes.size():
			var n: Node = nodes[i]
			if is_instance_valid(n):
				old[i] = n.process_mode
				n.process_mode = Node.PROCESS_MODE_DISABLED
	var off := func() -> void:
		for i: int in nodes.size():
			var n: Variant = nodes[i]
			if old.has(i) and is_instance_valid(n) and n is Node:
				(n as Node).set("process_mode", old[i])
	return {"key": "mods", "on": on, "off": off}


# ---------- report ----------

func _map() -> CanvasLayer:
	if _game == null:
		return null
	var v: Variant = _game.main.get("полит_карта")
	return v as CanvasLayer if is_instance_valid(v) and v is CanvasLayer else null


func _map_visible() -> bool:
	var map := _map()
	return map != null and map.visible


func _report(base: Dictionary, rows: Array) -> Dictionary:
	var counts := {"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))}
	var armies: Variant = _game.main.get("армии")
	if is_instance_valid(armies) and armies is Object:
		var units: Variant = (armies as Object).get("отряды")
		if units is Array:
			counts["units_total"] = (units as Array).size()
	var map := _map()
	if map != null:
		for prop: String in MAP_LISTS:
			var v: Variant = Names024.get_of(map, prop)
			if v is Array:
				counts["map." + prop] = (v as Array).size()
		var layers: Variant = map.get("слои")
		if layers is Dictionary:
			counts["map.слои"] = (layers as Dictionary).duplicate()
	var root := get_tree().root
	var sess := _sess.duplicate(true)
	sess["seg"] = _avg_segs(_sess["seg"])
	sess["spike_seg"] = _avg_segs(_sess["spike_seg"])
	var frames := maxf(1.0, float(_sess["frames"]))
	var rates := {}
	var redraws: Dictionary = _sess["redraws"]
	for item: String in redraws.keys():
		rates[item] = snappedf(100.0 * float(redraws[item]) / frames, 0.1)
	sess["redraw_pct"] = rates
	sess.erase("redraws")
	sess["by_mod"] = _by_mod_report(_sess["by_mod"])
	sess["spike_by_mod"] = _by_mod_report(_sess["spike_by_mod"])
	sess["redraw_triggers"] = _trig_top()
	var corp: Variant = Pax.get_mod("pax_corporations") if Pax.has_mod("pax_corporations") else null
	if is_instance_valid(corp) and corp is Object:
		var week: Variant = (corp as Object).get("last_week_usec")
		if week is Dictionary:
			var ms := {}
			var total := 0.0
			for k: Variant in (week as Dictionary).keys():
				ms[k] = snappedf(float((week as Dictionary)[k]) / 1000.0, 0.01)
				if not str(k).contains("."):
					total += float(ms[k])
			sess["corp_week_ms"] = ms
			sess["corp_week_total_ms"] = snappedf(total, 0.01)
		var refresh: Variant = (corp as Object).get("last_refresh_usec")
		if refresh is int:
			sess["corp_window_refresh_ms"] = snappedf(int(refresh) / 1000.0, 0.01)
	return {"version": 2, "mod_version": str(mod.manifest.get("version", "")), "time": Time.get_datetime_string_from_system(),
		"gpu": RenderingServer.get_video_adapter_name(), "window": str(DisplayServer.window_get_size()),
		"vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps, "msaa_3d": root.msaa_3d,
		"render_thread_model": ProjectSettings.get_setting("rendering/driver/threads/thread_model", -1),
		"map_visible": _map_visible(), "layer_slow": tuner.layer_slow, "layer_factor": snappedf(tuner.slow_factor(), 0.01), "layer_redraw_ms": snappedf(tuner.redraw_cost_ms, 0.1),
		"no_3d_under_map": tuner.no_3d_under_map, "fps_cap": tuner.fps_cap,
		"skip_screen": {"enabled": cover.enabled, "shown": cover.shown, "frames": cover.frames, "last_flag": cover.last_flag, "where": cover.where},
		"timeline": timeline.status(), "speed": _game.main.get("скорость_наблюдения"),
		"hidden_by_layers": hider.hidden_count(), "counts": counts, "base": base, "tests": rows,
		"session": sess, "slowest": _slowest.duplicate(true)}


func report_text(r: Dictionary, bb: bool) -> String:
	var lines := PackedStringArray()
	var base: Dictionary = r["base"]
	var head := mod.tr_key("pax_corptimizer_r_base", [_f(base["med"], 1), _f(base["fps"], 0), _f(base["p95"], 1),
		_f(base["max"], 1), _f(base["spikes_s"], 1)])
	lines.append(("[b]%s[/b]" % head) if bb else head)
	lines.append(mod.tr_key("pax_corptimizer_r_where", [_segs_text(base["seg"])]))
	var s: Dictionary = r["session"]
	if int(s.get("spikes", 0)) > 0:
		lines.append(mod.tr_key("pax_corptimizer_r_where_spikes", [_segs_text(s["spike_seg"])]))
		var worst := _worst_segment(s["spike_seg"])
		if not worst.is_empty():
			var verdict := mod.tr_key("pax_corptimizer_why_" + worst)
			lines.append(("[color=#ffcc66]%s[/color]" % verdict) if bb else verdict)
	lines.append("")
	lines.append(mod.tr_key("pax_corptimizer_r_tests"))
	for row_v: Variant in r["tests"]:
		var row: Dictionary = row_v
		var line := mod.tr_key("pax_corptimizer_r_row", [mod.tr_key("pax_corptimizer_t_" + str(row["key"])),
			_f(row["base_med"], 1), _f(row["off_med"], 1), _f(row["base_spikes_s"], 1), _f(row["off_spikes_s"], 1)])
		if bb and (float(row["spikes_cut"]) >= 0.5 or float(row["saved_ms"]) >= 1.0):
			line = "[color=#ffcc66]%s[/color]" % line
		lines.append(line)
	if int(s.get("frames", 0)) > 0:
		lines.append("")
		lines.append(mod.tr_key("pax_corptimizer_r_session", [_f(s["time"], 0), str(s["spikes"]), str(s["s50"]), str(s["s100"])]))
		var step_frames := int(s["step_frames"])
		if step_frames > 0:
			lines.append(mod.tr_key("pax_corptimizer_r_steps", [str(s["steps"]), str(s["days"]),
				_f(float(s["step_ms"]) / step_frames, 1), _f(s["step_max"], 1)]))
		var rates: Dictionary = s.get("redraw_pct", {})
		if not rates.is_empty():
			var parts := PackedStringArray()
			for item: String in rates.keys():
				parts.append("%s %s%%" % [item, _f(rates[item], 0)])
			lines.append(mod.tr_key("pax_corptimizer_r_redraws", [", ".join(parts)]))
		var mods_line := _by_mod_text(s.get("by_mod", {}))
		if not mods_line.is_empty():
			lines.append(mod.tr_key("pax_corptimizer_r_mods", [mods_line]))
		var trig: Array = s.get("redraw_triggers", [])
		if not trig.is_empty():
			var parts := PackedStringArray()
			for t_v: Variant in trig.slice(0, 4):
				var t: Dictionary = t_v
				parts.append("%s (%s%% / %s%%)" % [str(t["field"]), _f(t["coverage"], 0), _f(t["precision"], 0)])
			lines.append(mod.tr_key("pax_corptimizer_r_triggers", [", ".join(parts)]))
		if s.has("corp_week_total_ms"):
			lines.append(mod.tr_key("pax_corptimizer_r_corp", [_f(s["corp_week_total_ms"], 1)]))
		var scr: Dictionary = r.get("skip_screen", {})
		if int(scr.get("shown", 0)) > 0:
			lines.append(mod.tr_key("pax_corptimizer_r_screen", [str(scr["shown"]), str(scr["frames"]), str(scr["last_flag"]), str(scr["where"])]))
		if int(s.get("skip_frames", 0)) > 0:
			lines.append(mod.tr_key("pax_corptimizer_r_skip", [str(s["skip_frames"]),
				_f(float(s["skip_ms"]) / int(s["skip_frames"]), 1), _f(s["skip_max"], 1)]))
	var c: Dictionary = r["counts"]
	lines.append("")
	lines.append(mod.tr_key("pax_corptimizer_r_counts", [str(c.get("nodes", 0)), str(c.get("orphan_nodes", 0)),
		str(c.get("units_total", 0)), str(c.get("map.отряды_карты", 0)), str(c.get("map.базы_карты", 0)),
		str(c.get("map.показатели_карты", 0))]))
	lines.append(mod.tr_key("pax_corptimizer_r_saved"))
	return "\n".join(lines)


## «mod 1.2 мс (до 40 мс), …» — mods by average cost, the heaviest first.
func _by_mod_text(by_mod: Dictionary) -> String:
	var ids: Array = by_mod.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return float((by_mod[a] as Dictionary)["avg"]) > float((by_mod[b] as Dictionary)["avg"]))
	var parts := PackedStringArray()
	for id: Variant in ids:
		var d: Dictionary = by_mod[id]
		parts.append(mod.tr_key("pax_corptimizer_r_mod", [str(id), _f(d["avg"], 2), _f(d["max"], 0)]))
	return ", ".join(parts)


## The segment that takes most of a spike frame ("" if none stands out).
func _worst_segment(seg: Dictionary) -> String:
	var best := ""
	var best_ms := 0.0
	var total := 0.0
	for k: String in Timeline.SEGMENTS:
		var v: float = float(seg.get(k, 0.0))
		total += v
		if v > best_ms:
			best_ms = v
			best = k
	return best if best_ms >= total * 0.4 else ""


func _f(v: Variant, digits: int) -> String:
	var x: float = float(v)
	return str(int(round(x))) if digits == 0 else ("%." + str(digits) + "f") % x
