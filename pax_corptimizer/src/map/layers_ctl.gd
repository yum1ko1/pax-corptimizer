extends RefCounted
## The map's layers the player can switch off (their boxes on the political map).
## Part of main.gd (split out of it; the host keeps one-line wrappers with the same names).

const Names024 := preload("res://mods/pax_corptimizer/src/shared/names024.gd")
const Host := preload("res://mods/pax_corptimizer/main.gd")

var app: Host   # the host: its modules and data


func _init(host: Host) -> void:
	app = host


func _map() -> CanvasLayer:
	if app._game == null:
		return null
	var v: Variant = app._game.main.get("полит_карта")
	return v as CanvasLayer if is_instance_valid(v) and v is CanvasLayer else null


func _load_layers() -> void:
	app.armies.hide_foreign = not bool(app.get_setting("show_foreign", true))
	app.armies.hide_own = not bool(app.get_setting("show_own", true))
	app.armies.hide_bases = not bool(app.get_setting("show_bases", true))


## Our checkboxes go right after the game's layer checkboxes (map._галки), copying their look.
func _ensure_layer_boxes(map: CanvasLayer) -> void:
	var galki_v: Variant = Names024.get_of(map, "_галки")
	if not (galki_v is Dictionary):
		return
	var boxes: Array = []
	for v: Variant in (galki_v as Dictionary).values():
		if is_instance_valid(v) and v is CheckBox and (v as CheckBox).get_parent() != null:
			boxes.append(v)
	if boxes.is_empty():
		return
	# All checkboxes in one list — add to it; each in its own row — add rows' siblings.
	var first: CheckBox = boxes[0]
	var same_parent := true
	for b: Variant in boxes:
		if (b as CheckBox).get_parent() != first.get_parent():
			same_parent = false
	var anchor: Control = null
	for b: Variant in boxes:
		var c: Control = b if same_parent else (b as CheckBox).get_parent() as Control
		if c != null and (anchor == null or c.get_index() > anchor.get_index()):
			anchor = c
	if anchor == null or anchor.get_parent() == null:
		return
	var list := anchor.get_parent()
	if list.get_node_or_null(Host.BOX_PREFIX + Host.LAYERS[0]) != null:
		return
	for key: String in Host.LAYERS:
		var cb := first.duplicate(0) as CheckBox
		cb.name = Host.BOX_PREFIX + key
		cb.text = app.tr_key("pax_corptimizer_layer_" + key)
		cb.tooltip_text = app.tr_key("pax_corptimizer_layer_" + key + "_tip")
		cb.disabled = false
		cb.set_pressed_no_signal(bool(app.get_setting(key, true)))
		cb.toggled.connect(_on_layer_toggled.bind(key))
		list.add_child(cb)
		list.move_child(cb, anchor.get_index() + 1)
		anchor = cb


func _on_layer_toggled(on: bool, key: String) -> void:
	app.set_setting(key, on)
	_load_layers()
	app.armies.refresh()
