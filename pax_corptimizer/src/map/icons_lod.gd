extends Node
## «Значки корпораций по дальности» (setting «icons_lod», on by default): Pax Corporations draws a mark for every
## company on the map (and over the 3D Earth) — some 4 000; each redraw puts every one through the screen, groups the
## close ones, pushes them apart: the CPU's frame. From afar only the largest companies are marks anyway — the rest
## are one crowded dot under them. So:
##   by the map's zoom (its «зум»: the world's width in screens) only the largest companies are given to the layer —
##   PER_ZOOM × zoom^1.3, at least MIN_N (the layer keeps its list largest first: the cut is its head); close in,
##   all of them; the chosen company always stays;
##   while the map moves the layer redraws at most moving_fps times a second (its own «redraw_fps», 30).
## Nothing of Pax Corporations is changed on disk: its layer's list and its map config are set while this is on and
## given back when it is off or the mod goes.

const MIN_N := 150
const PER_ZOOM := 70.0

var enabled := true
var moving_fps := 12.0
var shown := 0                     # companies given to the layer now (for the panel)
var total := 0
var _full: Array = []              # the layer's own list (all, largest first)
var _cut: Array = []               # what we gave it instead
var _cut_n := -1
var _layer_ref: WeakRef
var _fps_was: Variant = null
var _t := 0.0


func _ready() -> void:
	name = "IconsLod"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -10          # before the layer's own _process: it draws with our list


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		restore()


func _layer() -> Object:
	var corp: Variant = Pax.get_mod("pax_corporations") if Pax.has_method("get_mod") else null
	if not (corp is Object) or not is_instance_valid(corp):
		return null
	var l: Variant = (corp as Object).get("_layer")
	return l as Object if l is Object and is_instance_valid(l) and (l as Object).get("_order") is Array else null


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or not enabled:
		return
	_t = 0.2
	var layer := _layer()
	if layer == null:
		return
	if _layer_ref == null or _layer_ref.get_ref() != layer:
		_layer_ref = weakref(layer)
		_full = []
		_cut = []
		_cut_n = -1
		_fps_was = null
	var order: Array = layer.get("_order")
	# The layer made its list anew (a new week, another mode): that is the full one now.
	if not is_same(order, _cut):
		_full = order
		_cut_n = -1
	total = _full.size()
	var zoom := float((layer.get("map") as Object).get("зум")) if layer.get("map") is Object else 1.0
	var n := clampi(int(PER_ZOOM * pow(maxf(zoom, 0.1), 1.3)), MIN_N, maxi(total, MIN_N))
	if n >= total:
		n = total
	n = (n / 50) * 50 if n < total else n   # in steps: the list is not cut anew at every step of the zoom
	if n != _cut_n:
		_cut_n = n
		_cut = _full if n >= total else _full.slice(0, n)
		var sel := str(layer.get("selected"))
		if not sel.is_empty() and n < total:
			for c in _full:
				if str((c as Dictionary).get("id", "")) == sel:
					if not _cut.has(c):
						_cut.append(c)
					break
		layer.set("_order", _cut)
		layer.call("queue_redraw")
	shown = _cut.size()
	# Fewer redraws while the map moves.
	var db: Variant = layer.get("db")
	var bal: Variant = (db as Object).get("balance") if db is Object else null
	var cfg: Variant = (bal as Dictionary).get("карта") if bal is Dictionary else null
	if cfg is Dictionary:
		if _fps_was == null:
			_fps_was = (cfg as Dictionary).get("redraw_fps", 30.0)
		(cfg as Dictionary)["redraw_fps"] = minf(moving_fps, float(_fps_was))


## The layer as Pax Corporations made it: its full list and its redraw rate.
func restore() -> void:
	var layer: Object = _layer_ref.get_ref() if _layer_ref != null else null
	if layer != null and is_instance_valid(layer):
		if not _full.is_empty() and is_same(layer.get("_order"), _cut):
			layer.set("_order", _full)
			layer.call("queue_redraw")
		var db: Variant = layer.get("db")
		var bal: Variant = (db as Object).get("balance") if db is Object else null
		var cfg: Variant = (bal as Dictionary).get("карта") if bal is Dictionary else null
		if cfg is Dictionary and _fps_was != null:
			(cfg as Dictionary)["redraw_fps"] = _fps_was
	_fps_was = null
	_cut_n = -1
	shown = 0


func _exit_tree() -> void:
	restore()
