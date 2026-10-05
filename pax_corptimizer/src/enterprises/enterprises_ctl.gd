extends RefCounted
## The enterprises' manager at work: made at the mod's load, the game's step (days_passed: the mutations, then the
## sync), the save and the switches (manager.gd writes them into the live entries at once).
## Part of main.gd (its wrappers: set_enterprise_active, set_enterprise_throttle, set_enterprise_priority,
## modernize_enterprise, enterprise_rows).

const Host := preload("res://mods/pax_corptimizer/main.gd")
const Manager := preload("res://mods/pax_corptimizer/src/enterprises/manager.gd")
const Log := preload("res://mods/pax_corptimizer/src/shared/log.gd")

var app: Host   # the host: its modules and data
var manager: Manager = Manager.new()


func _init(host: Host) -> void:
	app = host


func world_ready(game: PaxGame) -> void:
	if manager.game != game:
		manager.reset()   # another game: the old switches mean other enterprises
	manager.start(game)   # no window of its own any more (it stood empty: the switches are for other mods' calls)


## After all the game's steps of the period: the queued construction first, then the sync (the same step's mirror).
func days_passed(game: PaxGame) -> void:
	if manager.game != game:
		manager.start(game)
	manager.days_passed()


func save_state() -> Dictionary:
	return manager.state()


func game_loaded(game: PaxGame, st: Dictionary) -> void:
	manager.start(game)
	manager.load_state(st)


func set_active(body: String, id: int, on: bool) -> bool:
	var ok := manager.set_active(body, id, on)
	if ok:
		Log.info("enterprises", "%s #%d %s" % [body, id, "on" if on else "off"])
	return ok


func set_throttle(body: String, id: int, share: float) -> bool:
	return manager.set_throttle(body, id, share)


func set_priority(body: String, id: int, priority: int) -> bool:
	return manager.set_priority(body, id, priority)


func modernize(body: String, id: int) -> String:
	var why := manager.modernize(body, id)
	Log.info("enterprises", "%s #%d modernize: %s" % [body, id, "done" if why.is_empty() else why])
	return why
