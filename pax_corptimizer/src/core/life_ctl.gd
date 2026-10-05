extends RefCounted
## The mod's life: loading (the settings, the profiler, the windows), the world's start, the frame, teardown, the console.
## Part of main.gd (split out of it; the host keeps one-line wrappers with the same names).

const Names024 := preload("res://mods/pax_corptimizer/src/shared/names024.gd")
const Host := preload("res://mods/pax_corptimizer/main.gd")
const Log := preload("res://mods/pax_corptimizer/src/shared/log.gd")

var app: Host   # the host: its modules and data
var _since_check := 0.0


func _init(host: Host) -> void:
	app = host


func _mod_loaded() -> void:
	Log.setup(app, "pax_corptimizer")
	app.tuning_ctl.apply_threads()
	app.timeline = Host.Timeline.new()
	app.timeline.name = "Timeline"
	app.add_child(app.timeline)
	app.armies = Host.ArmyHider.new()
	app.armies.name = "ArmyHider"
	app.add_child(app.armies)
	app.cover = Host.SkipCover.new()
	app.cover.name = "SkipCover"
	app.cover.mod = app
	app.cover.enabled = bool(app.get_setting("skip_cover", true))
	app.cover.hide_3d = bool(app.get_setting("skip_hide_3d", true))
	app.add_child(app.cover)
	app.tuner = Host.MapTuner.new()
	app.tuner.name = "MapTuner"
	app.tuner.cover = app.cover
	app.tuner.timeline = app.timeline
	# 2.0: «auto» by default (report 5: x4 removed the layer spikes); the 1.x setting «layer_slow» is not carried over.
	app.tuner.layer_slow = int(app.get_setting("layer_slow2", Host.MapTuner.AUTO))
	app.tuner.no_3d_under_map = bool(app.get_setting("no_3d_under_map", true))
	app.add_child(app.tuner)
	app.relief = Host.GameRelief.new()
	app.relief.setup(app)
	app.relief.enabled = bool(app.get_setting("relief", true))
	app.add_child(app.relief)
	app.profiler = Host.FrameProfiler.new()
	app.profiler.name = "FrameProfiler"
	app.profiler.mod = app
	app.profiler.hider = app.armies
	app.profiler.timeline = app.timeline
	app.profiler.tuner = app.tuner
	app.profiler.cover = app.cover
	app.add_child(app.profiler)
	app._load_layers()
	Pax.register_command("opt_analyze", func(_args: PackedStringArray) -> String:
		if Pax.game == null:
			return app.tr_key("pax_corptimizer_no_world")
		app.profiler.analyze()
		return app.tr_key("pax_corptimizer_started"), "opt_analyze — Pax Corptimizer: measure what costs frame time")
	Pax.register_command("opt_stats", func(_args: PackedStringArray) -> String:
		return app.profiler.live_text(), "opt_stats — Pax Corptimizer: FPS, spikes, where the frame time goes")
	Pax.register_command("opt_armies", func(_args: PackedStringArray) -> String:
		return _armies_debug(), "opt_armies — Pax Corptimizer: army lists of the map (debug of the army layers)")


func _mod_unloaded() -> void:
	Log.shutdown(app)
	app.armies.hide_foreign = false
	app.armies.hide_own = false
	app.armies.hide_bases = false
	app.armies.refresh()
	app.tuner.layer_slow = 1
	app.tuner.no_3d_under_map = false
	app.tuner.release()
	app.cover.stop()
	if app.relief != null:
		app.relief.restore()
	app.timeline.detach()
	if not app.upscale_snap.is_empty():
		Host.Upscale.restore(app.get_tree().root, app.upscale_snap)
	if app.whatsnew != null:
		app.whatsnew.teardown()
	app.whatsnew = null


func _world_ready(game: PaxGame) -> void:
	app._game = game
	_since_check = 1.0
	app.timeline.attach(game)
	app.profiler.start(game)
	app.cover.start(game)
	app.armies.set_map(app._map())
	app.armies.refresh()
	app.tuner.set_map(app._map())
	app.relief.start(game)
	app.tuner.set_fps_cap(int(app.get_setting("fps_cap", 0)))
	app.tuning_ctl.apply_upscale()
	var panel := Host.OptPanel.new()
	panel.setup(app, app.profiler)
	game.add_window(app.tr_key("pax_corptimizer_button"), panel, Vector2(520, 460))
	app.enterprises_ctl.world_ready(game)
	if app.whatsnew != null:
		app.whatsnew.teardown()
	app.whatsnew = Host.WhatsNew.new()
	app.whatsnew.setup(app, game, "pax_corptimizer_")
	app.get_tree().create_timer(3.5).timeout.connect(func() -> void:
		if app.whatsnew != null:
			app.whatsnew.maybe_show())


func _process(delta: float) -> void:
	if app._game == null or Pax.game != app._game:
		return
	_since_check += delta
	if _since_check < 0.25:
		return
	_since_check = 0.0
	# The game may rebuild its map (another planet, a loaded save) and builds the layers window lazily.
	var map := app._map()
	app.armies.set_map(map)
	app.tuner.set_map(map)
	# The game applies its own FPS setting at times — keep ours on top.
	if app.tuner.fps_cap > 0 and Engine.max_fps != app.tuner.fps_cap:
		app.tuner.set_fps_cap(app.tuner.fps_cap)
	app.tuning_ctl.keep_upscale()
	if not app.timeline.check(app._game):
		app.timeline.attach(app._game)
	if map != null:
		app._ensure_layer_boxes(map)


func _armies_debug() -> String:
	var map := app._map()
	if map == null:
		return app.tr_key("pax_corptimizer_no_world")
	var lines: PackedStringArray = []
	for prop: String in ["отряды_карты", "базы_карты", "_кэш_стопок", "бои_карты"]:
		var v: Variant = Names024.get_of(map, prop)
		lines.append("%s: %s" % [prop, str((v as Array).size()) if v is Array else str(v)])
	lines.append("_кадр_стопок: %s · process_frames: %d · frames_drawn: %d" % [str(Names024.get_of(map, "_кадр_стопок")),
		Engine.get_process_frames(), Engine.get_frames_drawn()])
	lines.append("hide: foreign=%s own=%s bases=%s · hidden now: %d" % [str(app.armies.hide_foreign), str(app.armies.hide_own),
		str(app.armies.hide_bases), app.armies.hidden_count()])
	return "\n".join(lines)
