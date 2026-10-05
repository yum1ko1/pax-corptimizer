extends RefCounted
## The enterprises' manager: the player's switches over the game's own enterprises (Main.хозяйства[body]
## ["предприятия"]: {id, тип, провинция, тело, уровни, встал}) and a mirror of them for the window.
##
## When the game reads them (see AGENTS.md):
##   • `_days_passed` comes AFTER all the game's steps for the period (`_pax("_дни_прошли")` at the end of
##     `_start_period`), and an entry is read only from the game's NEXT step. So every switch — set_active,
##     set_throttle, set_priority, modernize — writes into the live entry at once through apply_now(body), never
##     waiting for the weekly tick.
##   • Inside days_passed the mutations (the queued construction, econ_add) go BEFORE the sync (sync_all),
##     otherwise a new object would show up in the mirror one step late.
##
## What a switch means in the game's terms:
##   active   — false: the entry «встал» (the game skips it: no output, no input, no power); back on — «встал»
##              cleared only if it was this manager that stopped it (an exhausted field stays stopped);
##   throttle — 0.1..1: the entry works with that share of its levels (its output, input, workers and power go down
##              together); the full levels are kept as «base», and what the game builds or tears down meanwhile
##              (the live levels moved away from what was written) goes into base;
##   priority — -9..9: the higher, the earlier in the list; the game walks the list in order, so the power
##              stations of a higher priority burn the fuel first when it is short;
##   modernize — one more level now: its cost (the type's «стоит») is paid at once, the level added by the game's
##              own economy (econ_add: Main.эк.добавить), then apply_now.

const MIN_THROTTLE := 0.1
const EPS := 0.0001
const PRIORITY_MAX := 9

var game: PaxGame
# body -> {id (String) -> {active, throttle, priority, base, written, stopped}}
var overrides: Dictionary = {}
# body -> [{id, type, province, sub_body, levels, base, active, exhausted, throttle, priority, load}]
var mirror: Dictionary = {}
# [{body, type, province, levels, sub_body}] — built in days_passed before the sync
var queue: Array = []
var version := 0                 # grows when the mirror is made anew by the game's step (the window redraws)


func start(g: PaxGame) -> void:
	game = g
	mirror.clear()


## A new game: nothing of the old one.
func reset() -> void:
	overrides.clear()
	mirror.clear()
	queue.clear()
	version += 1


# ---------- the switches: written into the live entry at once ----------

func set_active(body: String, id: int, on: bool) -> bool:
	if _entry(body, id).is_empty():
		return false
	_over(body, id)["active"] = on
	apply_now(body)
	return true


func set_throttle(body: String, id: int, share: float) -> bool:
	if _entry(body, id).is_empty():
		return false
	_over(body, id)["throttle"] = clampf(share, MIN_THROTTLE, 1.0)
	apply_now(body)
	return true


func set_priority(body: String, id: int, priority: int) -> bool:
	if _entry(body, id).is_empty():
		return false
	_over(body, id)["priority"] = clampi(priority, -PRIORITY_MAX, PRIORITY_MAX)
	apply_now(body)
	return true


## One more level of an enterprise, paid now. "" — done; otherwise why not: "no_entry", "no_economy", "short:<res>".
func modernize(body: String, id: int) -> String:
	var e := _entry(body, id)
	if e.is_empty():
		return "no_entry"
	var cost := cost_of(str(e.get("тип", "")))
	var short := _short(body, cost)
	if not short.is_empty():
		return "short:" + short
	if not _can_add():
		return "no_economy"
	_pay(body, cost)
	_econ_add(body, str(e["тип"]), int(e.get("провинция", 0)), 1.0, str(e.get("тело", "")))
	apply_now(body)   # the new level goes into base (the live levels moved) and works from the next step
	return ""


## The cost of one level of a type: {resource: amount} («деньги» — the treasury).
func cost_of(type: String) -> Dictionary:
	var types := _types()
	var t: Variant = types.get(type)
	if not (t is Dictionary):
		return {}
	var c: Variant = (t as Dictionary).get("стоит", {})
	return (c as Dictionary).duplicate() if c is Dictionary else {}


## Construction for the next days_passed: done there before the sync.
func queue_build(body: String, type: String, province: int, levels: float, sub_body: String = "") -> void:
	queue.append({"body": body, "type": type, "province": province, "levels": levels, "sub_body": sub_body})


# ---------- the game's step ----------

## Called from _days_passed: first the mutations (the queued construction), then the sync — so what was built shows
## in the mirror in the same step, not one later.
func days_passed() -> void:
	var built := queue.duplicate()
	queue.clear()
	for q in built:
		var qd: Dictionary = q
		_econ_add(str(qd["body"]), str(qd["type"]), int(qd["province"]), float(qd["levels"]), str(qd.get("sub_body", "")))
	sync_all()


## Every body with an economy: the switches applied again over what the game did in its step, the mirror made anew.
func sync_all() -> void:
	for body in _bodies():
		apply_now(str(body))
	version += 1


## The switches into the live entries of a body NOW (the game reads them on its very next step) and its mirror.
func apply_now(body: String) -> void:
	var farm := _farm(body)
	if farm.is_empty():
		return
	var list: Array = farm.get("предприятия", [])
	var ov: Dictionary = overrides.get(body, {})
	var seen := {}
	var any_priority := false
	for p in list:
		if not (p is Dictionary):
			continue
		var pd: Dictionary = p
		var key := str(int(pd.get("id", -1)))
		if not ov.has(key):
			continue
		seen[key] = true
		var o: Dictionary = ov[key]
		var live := float(pd.get("уровни", 0.0))
		if o.has("written"):
			var drift := live - float(o["written"])
			if absf(drift) > EPS:
				o["base"] = maxf(float(o.get("base", live)) + drift, 0.0)   # the game built or tore down meanwhile
		else:
			o["base"] = live
		var lv := float(o["base"]) * float(o.get("throttle", 1.0))
		pd["уровни"] = lv
		o["written"] = lv
		if not bool(o.get("active", true)):
			if not bool(pd.get("встал", false)):
				o["stopped"] = true
			pd["встал"] = true
		elif bool(o.get("stopped", false)):
			pd["встал"] = false
			o["stopped"] = false
		if int(o.get("priority", 0)) != 0:
			any_priority = true
		# Back to the game's own state — nothing to keep.
		if bool(o.get("active", true)) and float(o.get("throttle", 1.0)) >= 1.0 and int(o.get("priority", 0)) == 0:
			ov.erase(key)
	for key in ov.keys():
		if not seen.has(key):
			ov.erase(key)   # torn down
	if ov.is_empty():
		overrides.erase(body)
	if any_priority:
		_order(list, ov)
	farm.erase("_мощности")   # the game's capacity cache (Экономика.сбросить_кэш): built anew on its next step
	_mirror(body, farm)


## Higher priority first, otherwise the game's own order (a stable sort in place: the game keeps the same Array).
static func _order(list: Array, ov: Dictionary) -> void:
	var dec: Array = []
	for i in list.size():
		var pr := 0
		if list[i] is Dictionary:
			var o: Variant = ov.get(str(int((list[i] as Dictionary).get("id", -1))))
			pr = int((o as Dictionary).get("priority", 0)) if o is Dictionary else 0
		dec.append([pr, i, list[i]])
	dec.sort_custom(func(a: Array, b: Array) -> bool:
		if int(a[0]) != int(b[0]):
			return int(a[0]) > int(b[0])
		return int(a[1]) < int(b[1]))
	for i in dec.size():
		list[i] = (dec[i] as Array)[2]


func _mirror(body: String, farm: Dictionary) -> void:
	var ov: Dictionary = overrides.get(body, {})
	var loads: Dictionary = farm.get("загрузка", {}) if farm.get("загрузка") is Dictionary else {}
	var rows: Array = []
	for p in farm.get("предприятия", []):
		if not (p is Dictionary):
			continue
		var pd: Dictionary = p
		var key := str(int(pd.get("id", -1)))
		var o: Dictionary = ov.get(key, {})
		var stopped := bool(pd.get("встал", false))
		rows.append({"id": int(pd.get("id", -1)), "type": str(pd.get("тип", "")), "province": int(pd.get("провинция", 0)),
			"sub_body": str(pd.get("тело", "")), "levels": float(pd.get("уровни", 0.0)),
			"base": float(o.get("base", pd.get("уровни", 0.0))), "active": bool(o.get("active", not stopped)),
			"exhausted": stopped and not bool(o.get("stopped", false)), "throttle": float(o.get("throttle", 1.0)),
			"priority": int(o.get("priority", 0)), "load": float(loads.get(str(pd.get("тип", "")), 1.0))})
	mirror[body] = rows


## The mirror of a body (made on demand if the game has not stepped yet).
func rows(body: String) -> Array:
	if not mirror.has(body):
		var farm := _farm(body)
		if not farm.is_empty():
			_mirror(body, farm)
	return mirror.get(body, [])


# ---------- save ----------

func state() -> Dictionary:
	return {"overrides": overrides.duplicate(true), "queue": queue.duplicate(true)}


## Loaded with a save: the switches back and applied at once (the save keeps the written levels and the base).
func load_state(st: Dictionary) -> void:
	overrides = (st.get("overrides", {}) as Dictionary).duplicate(true) if st.get("overrides") is Dictionary else {}
	queue = (st.get("queue", []) as Array).duplicate(true) if st.get("queue") is Array else []
	mirror.clear()
	sync_all()


# ---------- the game ----------

func _farm(body: String) -> Dictionary:
	if game == null or not is_instance_valid(game.main):
		return {}
	var all: Variant = game.main.get("хозяйства")
	if not (all is Dictionary):
		return {}
	var f: Variant = (all as Dictionary).get(body)
	return f if f is Dictionary and (f as Dictionary).get("предприятия") is Array else {}


func _bodies() -> Array:
	if game == null or not is_instance_valid(game.main):
		return []
	var all: Variant = game.main.get("хозяйства")
	return (all as Dictionary).keys() if all is Dictionary else []


func _entry(body: String, id: int) -> Dictionary:
	for p in _farm(body).get("предприятия", []):
		if p is Dictionary and int((p as Dictionary).get("id", -1)) == id:
			return p
	return {}


func _over(body: String, id: int) -> Dictionary:
	if not overrides.has(body):
		overrides[body] = {}
	var ov: Dictionary = overrides[body]
	var key := str(id)
	if not ov.has(key):
		ov[key] = {"active": true, "throttle": 1.0, "priority": 0}
	return ov[key]


func _economy() -> Object:
	if game == null or not is_instance_valid(game.main):
		return null
	var e: Variant = game.main.get("эк")
	return e as Object if e is Object else null


func _types() -> Dictionary:
	var e := _economy()
	var t: Variant = e.get("типы") if e != null else null
	return t if t is Dictionary else {}


func _can_add() -> bool:
	var e := _economy()
	return e != null and e.has_method("добавить")


## The game's construction (econ_add): Main.эк.добавить — the same entry gets the levels (one entry per type and
## province), the capacity cache is reset by the game itself.
func _econ_add(body: String, type: String, province: int, levels: float, sub_body: String) -> bool:
	var farm := _farm(body)
	var e := _economy()
	if farm.is_empty() or e == null or not e.has_method("добавить"):
		return false
	e.call("добавить", farm, type, province, levels, sub_body)
	return true


## The first resource there is not enough of ("" — enough of all). Money is the treasury's, the rest the body's.
func _short(body: String, cost: Dictionary) -> String:
	var store := game.resources(body)
	for k in cost.keys():
		var need := float(cost[k])
		var have := game.money() if str(k) == "деньги" else float(store.get(k, 0.0))
		if have + EPS < need:
			return str(k)
	return ""


func _pay(body: String, cost: Dictionary) -> void:
	for k in cost.keys():
		if str(k) == "деньги":
			game.add_money(-float(cost[k]))
		else:
			game.add_resource(body, str(k), -float(cost[k]))
