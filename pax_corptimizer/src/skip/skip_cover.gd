extends Node
## Time-skip screen: while the game skips time the heavy parts of the frame are paused and a GPU-only animation
## is shown, so the one busy CPU thread works on the world instead of drawing it.
## A skip is any of Main's flags in SKIP_FLAGS (the skip window, «to the next event», the time machine).
## Paused: the map's canvases (icons, fill, lines, figurines, background) and its texture viewport, optionally
## the 3D scene. The map CanvasLayer itself is NOT hidden: closing the map makes the game rebuild things (a
## 4-second frame in the measurements).
## Where the screen goes: with the map open — a Control added last to the map's CanvasLayer, so it is above
## everything the map draws and below the game's HUD (the skip window keeps working); on the globe — its own
## CanvasLayer just under the HUD (3D is always under canvas layers).

const Names024 := preload("res://mods/pax_corptimizer/src/shared/names024.gd")
const SKIP_FLAGS: PackedStringArray = ["идёт_перемотка", "мотаем_до_события", "_прыжок_вперёд_машиной"]
## After the days the game waits for the AI's results of the skip (Main.итоги_ждём — a Dictionary, not empty while
## waiting; Main._ждём_последствий): the screen stays for this whole stage — it never starts from these alone.
const RESULT_FLAGS: PackedStringArray = ["итоги_ждём", "_ждём_последствий"]
const MAP_CANVASES: PackedStringArray = ["холст", "слой", "слой_линий", "показ_фигурок", "фон"]
const LABEL_EVERY := 0.25
const STALL_SEC := 12.0   # no new day for this long while a flag is still up — the skip is over, the flag is stale
                          # (2.0.1 had 1.5 s: a heavy day of a long skip took longer and the clock vanished mid-skip)

var mod: PaxMod
var enabled := true
var hide_3d := true
var active := false
var shown := 0            # how many skips got the screen (for the report)
var frames := 0           # frames shown with the screen
var last_flag := ""       # which flag started the last skip
var where := ""           # "map" | "layer" — where the last screen was put

var _game: PaxGame
var _saved: Array = []    # [object, property, old value]
var _screen: Control
var _own_layer: CanvasLayer
var _date: Label
var _t := 0.0
var _day := -1
var _still := 0.0         # real seconds without a new day while the screen is up
var _stale := ""          # a flag that stayed up after its skip: ignored until it goes down or days move again


func _ready() -> void:
	# The game pauses the tree when a skip ends: the screen must still see it and go away.
	process_mode = Node.PROCESS_MODE_ALWAYS


func start(game: PaxGame) -> void:
	stop()
	_game = game


func skipping_flag() -> String:
	if _game == null or not is_instance_valid(_game.main):
		return ""
	for flag: String in SKIP_FLAGS:
		var v: Variant = _game.main.get(flag)
		if v is bool and bool(v):
			return flag
	return ""


## The game waits for the AI's results of the skip.
func waiting_results() -> bool:
	if _game == null or not is_instance_valid(_game.main):
		return false
	for flag: String in RESULT_FLAGS:
		var v: Variant = _game.main.get(flag)
		if (v is bool and bool(v)) or (v is Dictionary and not (v as Dictionary).is_empty()):
			return true
	return false


func _process(delta: float) -> void:
	if _game == null or Pax.game != _game or not is_instance_valid(_game.main):
		if active:
			stop()
		return
	var flag := skipping_flag()
	if flag != _stale:
		_stale = ""   # only the flag going down clears a stale one (days running again do not: that is play, not a skip)
	if not _stale.is_empty():
		flag = ""
	var results := active and waiting_results()   # the results stage keeps the screen, never starts it
	if not flag.is_empty() and enabled and not active:
		last_flag = flag
		_begin()
	elif active and ((flag.is_empty() and not results) or not enabled):
		stop()
	if not active:
		return
	frames += 1
	var d := _game.day()
	if d != _day or results:
		_day = d
		_still = 0.0
	else:
		_still += delta
		if _still >= STALL_SEC:
			_stale = flag
			stop()
			return
	_t += delta
	if _t >= LABEL_EVERY and is_instance_valid(_date):
		_t = 0.0
		_date.text = _game.date_text()


func _begin() -> void:
	active = true
	shown += 1
	_day = _game.day()
	_still = 0.0
	_saved = []
	var map: CanvasLayer = null
	var map_v: Variant = _game.main.get("полит_карта")
	if is_instance_valid(map_v) and map_v is CanvasLayer and (map_v as CanvasLayer).visible:
		map = map_v
		for prop: String in MAP_CANVASES:
			var ci: Variant = Names024.get_of(map, prop)
			if is_instance_valid(ci) and ci is CanvasItem and (ci as CanvasItem).visible:
				_save_set(ci as Object, "visible", false)
		var vp: Variant = map.get("вп")
		if is_instance_valid(vp) and vp is SubViewport:
			_save_set(vp as Object, "render_target_update_mode", SubViewport.UPDATE_DISABLED)
	if hide_3d:
		_save_set(get_tree().root, "disable_3d", true)
	_screen = _build_screen()
	if map != null:
		where = "map"
		map.add_child(_screen)
	else:
		where = "layer"
		_own_layer = CanvasLayer.new()
		_own_layer.name = "PaxCorptimizerSkipLayer"
		var hud := _game.hud_layer()
		_own_layer.layer = (hud.layer - 1) if hud != null else 50
		add_child(_own_layer)
		_own_layer.add_child(_screen)


func stop() -> void:
	if not active:
		return
	active = false
	for i: int in range(_saved.size() - 1, -1, -1):
		var s: Array = _saved[i]
		var obj: Variant = s[0]
		var prop: String = s[1]
		if is_instance_valid(obj) and obj is Object:
			(obj as Object).set(prop, s[2])
	_saved = []
	if is_instance_valid(_screen):
		_screen.queue_free()
	if is_instance_valid(_own_layer):
		_own_layer.queue_free()
	_screen = null
	_own_layer = null
	_date = null


func _save_set(obj: Object, prop: String, value: Variant) -> void:
	_saved.append([obj, prop, obj.get(prop)])
	obj.set(prop, value)


func _build_screen() -> Control:
	var root := Control.new()
	root.name = "PaxCorptimizerSkipScreen"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.015, 0.03)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := mod.shader("shaders/warp.gdshader")
	if sh != null:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		bg.material = mat
	root.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -120.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Label.new()
	title.text = mod.tr_key("pax_corptimizer_skip_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	_date = Label.new()
	_date.text = _game.date_text()
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date.add_theme_font_size_override("font_size", 22)
	box.add_child(_date)
	var hint := Label.new()
	hint.text = mod.tr_key("pax_corptimizer_skip_hint")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)
	root.add_child(box)
	return root
