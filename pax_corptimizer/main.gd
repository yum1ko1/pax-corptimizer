extends PaxMod
## Pax Corptimizer — finds what slows the game down and switches it off.
## - Tab layers window of the political map: «Чужие армии», «Свои армии», «Военные базы» (src/armies.gd).
## - Time-skip screen: during a skip the map's drawing (and 3D) pause, a GPU animation shows (src/skip_cover.gd).
## - Map tuning: the map's layer redraws come less often, no 3D behind the open map (src/map_tuner.gd).
## - Game relief: the game's own frame and time-skip work made lighter (src/game/game_relief.gd).
## - «Оптимизация» window: the main-thread timeline of a frame (src/timeline.gd), live numbers and an A/B
##   analysis of suspects (src/profiler.gd, src/panel.gd).
## - «Предприятия» window: switches over the game's enterprises — on/off, throttle, priority, +1 level — written into
##   the live entries at once, applied again after each step of the game (src/enterprises/).
## Console (F8): opt_analyze — run the analysis, opt_stats — live numbers, opt_armies — army lists on the map.

const ArmyHider := preload("res://mods/pax_corptimizer/src/map/armies.gd")
const FrameProfiler := preload("res://mods/pax_corptimizer/src/profiler/profiler.gd")
const Timeline := preload("res://mods/pax_corptimizer/src/profiler/timeline.gd")
const MapTuner := preload("res://mods/pax_corptimizer/src/map/map_tuner.gd")
const OptPanel := preload("res://mods/pax_corptimizer/src/settings/panel.gd")
const SkipCover := preload("res://mods/pax_corptimizer/src/skip/skip_cover.gd")
const WhatsNew := preload("res://mods/pax_corptimizer/src/shared/whatsnew.gd")
# The parts of the mod's work, each its own object (src/<feature>/*_ctl.gd, each holds «app» — this object).
# main.gd only registers: modules, shared state and one-line entry points with the old names (the game's
# callbacks, the windows, the other mods' api.call, the console). New logic goes into a part, not here.
const LifeCtl := preload("res://mods/pax_corptimizer/src/core/life_ctl.gd")
const TuningCtl := preload("res://mods/pax_corptimizer/src/settings/tuning_ctl.gd")
const Upscale := preload("res://mods/pax_corptimizer/src/render/upscale.gd")
const LayersCtl := preload("res://mods/pax_corptimizer/src/map/layers_ctl.gd")
const EnterprisesCtl := preload("res://mods/pax_corptimizer/src/enterprises/enterprises_ctl.gd")
const GameRelief := preload("res://mods/pax_corptimizer/src/game/game_relief.gd")

## Layer checkbox → setting key (checked = shown, like the game's own layers).
const LAYERS: PackedStringArray = ["show_foreign", "show_own", "show_bases"]
const BOX_PREFIX := "PaxCorptimizer_"

var armies: ArmyHider
var profiler: FrameProfiler
var timeline: Timeline
var tuner: MapTuner
var cover: SkipCover
var relief: GameRelief               # the game's own work in a frame made lighter (src/game/game_relief.gd)
var whatsnew: WhatsNew
var _game: PaxGame


var life_ctl: LifeCtl = LifeCtl.new(self)         # the mod's life
var upscale_snap: Array = []        # the root viewport as the game had it (restored when the mod goes)
var tuning_ctl: TuningCtl = TuningCtl.new(self)   # the ⚙ settings applied
var layers_ctl: LayersCtl = LayersCtl.new(self)   # the map's layers the player can switch off
var enterprises_ctl: EnterprisesCtl = EnterprisesCtl.new(self)   # the switches over the game's enterprises


func _mod_loaded() -> void:
	life_ctl._mod_loaded()


func _mod_unloaded() -> void:
	life_ctl._mod_unloaded()


func _world_ready(game: PaxGame) -> void:
	life_ctl._world_ready(game)


## After ALL the game's steps of the period: the queued construction, then the enterprises' sync.
func _days_passed(game: PaxGame, _from_day: int, _days: int) -> void:
	enterprises_ctl.days_passed(game)


func _save_state(_game_s: PaxGame) -> Dictionary:
	return {"enterprises": enterprises_ctl.save_state()}


func _game_loaded(game: PaxGame, state: Dictionary) -> void:
	enterprises_ctl.game_loaded(game, state.get("enterprises", {}) if state.get("enterprises") is Dictionary else {})


# ---------- the enterprises (src/enterprises/): the window and other mods ----------

func set_enterprise_active(body: String, id: int, on: bool) -> bool:
	return enterprises_ctl.set_active(body, id, on)


func set_enterprise_throttle(body: String, id: int, share: float) -> bool:
	return enterprises_ctl.set_throttle(body, id, share)


func set_enterprise_priority(body: String, id: int, priority: int) -> bool:
	return enterprises_ctl.set_priority(body, id, priority)


func modernize_enterprise(body: String, id: int) -> String:
	return enterprises_ctl.modernize(body, id)


func enterprise_rows(body: String) -> Array:
	return enterprises_ctl.manager.rows(body)


func enterprise_cost(type: String) -> Dictionary:
	return enterprises_ctl.manager.cost_of(type)


func enterprise_version() -> int:
	return enterprises_ctl.manager.version


## The bodies with enterprises: the home body first.
func enterprise_bodies() -> PackedStringArray:
	var out := PackedStringArray()
	if _game == null:
		return out
	var home := _game.home_body()
	for b in enterprises_ctl.manager._bodies():
		if str(b) == home:
			out.insert(0, home)
		else:
			out.append(str(b))
	return out


func set_skip_cover(on: bool, hide_3d: bool) -> void:
	tuning_ctl.set_skip_cover(on, hide_3d)


func set_fps_cap(cap: int) -> void:
	tuning_ctl.set_fps_cap(cap)


func set_threads(on: bool) -> void:
	tuning_ctl.set_threads(on)


func set_relief(on: bool) -> void:
	set_setting("relief", on)
	if relief != null:
		relief.set_enabled(on)


func set_map_tuning(layer_slow: int, no_3d: bool) -> void:
	tuning_ctl.set_map_tuning(layer_slow, no_3d)


func set_upscale(mode: String, scale: float, sharpness: float, aa: String) -> void:
	tuning_ctl.set_upscale(mode, scale, sharpness, aa)


func _process(delta: float) -> void:
	life_ctl._process(delta)


func _map() -> CanvasLayer:
	return layers_ctl._map()


# ---------- layers window (Tab) ----------

func _load_layers() -> void:
	layers_ctl._load_layers()


## Our checkboxes go right after the game's layer checkboxes (map._галки), copying their look.
func _ensure_layer_boxes(map: CanvasLayer) -> void:
	layers_ctl._ensure_layer_boxes(map)


