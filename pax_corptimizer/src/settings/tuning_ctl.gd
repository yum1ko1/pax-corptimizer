extends RefCounted
## The ⚙ settings applied: the cover over a skip, the FPS cap, the map's tuning.
## Part of main.gd (split out of it; the host keeps one-line wrappers with the same names).

const Host := preload("res://mods/pax_corptimizer/main.gd")

var app: Host   # the host: its modules and data


func _init(host: Host) -> void:
	app = host


func set_skip_cover(on: bool, hide_3d: bool) -> void:
	app.cover.enabled = on
	app.cover.hide_3d = hide_3d
	app.set_setting("skip_cover", on)
	app.set_setting("skip_hide_3d", hide_3d)


## «Многопоточность»: the mods' heavy work on worker threads (Engine meta «pax_threads», read by Pax Corporations'
## economy and statuses — parallel.gd — and by Pax CorpInc3D's towns, networks and big maps). On by default.
func set_threads(on: bool) -> void:
	app.set_setting("threads", on)
	apply_threads()


func apply_threads() -> void:
	Engine.set_meta(&"pax_threads", bool(app.get_setting("threads", true)))


func set_fps_cap(cap: int) -> void:
	app.tuner.set_fps_cap(cap)
	app.set_setting("fps_cap", app.tuner.fps_cap)


## Upscaling and anti-aliasing of the 3D view (src/render/upscale.gd).
func set_upscale(mode: String, scale: float, sharpness: float, aa: String) -> void:
	app.set_setting("upscale_mode", mode)
	app.set_setting("upscale_scale", scale)
	app.set_setting("upscale_sharp", sharpness)
	app.set_setting("upscale_aa", aa)
	apply_upscale()


func apply_upscale() -> void:
	var vp := app.get_tree().root as Viewport
	if vp == null:
		return
	if app.upscale_snap.is_empty():
		app.upscale_snap = Host.Upscale.snapshot(vp)
	var mode := str(app.get_setting("upscale_mode", "off"))
	var aa := str(app.get_setting("upscale_aa", "game"))
	if mode == "off" and aa == "game":
		Host.Upscale.restore(vp, app.upscale_snap)
		return
	Host.Upscale.apply(vp, mode, float(app.get_setting("upscale_scale", 0.77)), float(app.get_setting("upscale_sharp", 0.5)), aa)


## The game may set its own resolution scale at times: ours is put back while one is chosen.
func keep_upscale() -> void:
	var mode := str(app.get_setting("upscale_mode", "off"))
	if mode == "off" or not Host.Upscale.available(mode):
		return
	var vp := app.get_tree().root as Viewport
	if vp != null and absf(vp.scaling_3d_scale - float(app.get_setting("upscale_scale", 0.77))) > 0.001:
		apply_upscale()


func set_map_tuning(layer_slow: int, no_3d: bool) -> void:
	app.tuner.layer_slow = maxi(Host.MapTuner.AUTO, layer_slow)
	app.tuner.no_3d_under_map = no_3d
	if not no_3d:
		app.tuner.release()
	app.set_setting("layer_slow2", app.tuner.layer_slow)
	app.set_setting("no_3d_under_map", no_3d)
