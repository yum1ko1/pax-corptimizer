extends VBoxContainer
## «Оптимизация» window: live frame numbers, the analysis button and its report.

const FrameProfiler := preload("res://mods/pax_corptimizer/src/profiler/profiler.gd")
const Feedback := preload("res://mods/pax_corptimizer/src/shared/feedback.gd")
const LogWindow := preload("res://mods/pax_corptimizer/src/shared/log_window.gd")
const Upscale := preload("res://mods/pax_corptimizer/src/render/upscale.gd")
const Lod := preload("res://mods/pax_corptimizer/src/render/lod.gd")
const DIM := Color(1, 1, 1, 0.62)
const LAYER_SLOW: Array[int] = [0, 1, 2, 4]
const FPS_CAPS: Array[int] = [0, 60, 120, 144, 165]
const BOOSTY := "https://boosty.to/pax_yum1ko/donate"   # the author's Boosty: support the mods

var mod: PaxMod
var profiler: FrameProfiler

var _live: Label
var _run: Button
var _copy: Button
var _status: Label
var _out: RichTextLabel
var _t := 0.0


func setup(m: PaxMod, p: FrameProfiler) -> void:
	mod = m
	profiler = p


func _ready() -> void:
	name = "PaxCorptimizerPanel"
	custom_minimum_size = Vector2(520, 460)
	add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = mod.tr_key("pax_corptimizer_title")
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	_live = Label.new()
	_live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_live.text = profiler.live_text()
	add_child(_live)

	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 8)
	var slow_label := Label.new()
	slow_label.text = mod.tr_key("pax_corptimizer_layer_slow")
	slow_label.tooltip_text = mod.tr_key("pax_corptimizer_layer_slow_tip")
	slow_label.mouse_filter = Control.MOUSE_FILTER_PASS
	map_row.add_child(slow_label)
	var slow := OptionButton.new()
	slow.tooltip_text = mod.tr_key("pax_corptimizer_layer_slow_tip")
	for i: int in LAYER_SLOW.size():
		var v: int = LAYER_SLOW[i]
		slow.add_item(mod.tr_key("pax_corptimizer_layer_slow_" + str(v)), v)
		if v == profiler.tuner.layer_slow:
			slow.select(i)
	map_row.add_child(slow)
	var no3d_map := CheckBox.new()
	no3d_map.text = mod.tr_key("pax_corptimizer_no_3d_map")
	no3d_map.tooltip_text = mod.tr_key("pax_corptimizer_no_3d_map_tip")
	no3d_map.button_pressed = profiler.tuner.no_3d_under_map
	map_row.add_child(no3d_map)
	var apply_map := func() -> void: mod.call("set_map_tuning", slow.get_selected_id(), no3d_map.button_pressed)
	slow.item_selected.connect(func(_i: int) -> void: apply_map.call())
	no3d_map.toggled.connect(func(_on: bool) -> void: apply_map.call())
	add_child(map_row)

	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 8)
	var fps_label := Label.new()
	fps_label.text = mod.tr_key("pax_corptimizer_fps_cap")
	fps_label.tooltip_text = mod.tr_key("pax_corptimizer_fps_cap_tip")
	fps_label.mouse_filter = Control.MOUSE_FILTER_PASS
	fps_row.add_child(fps_label)
	var fps := OptionButton.new()
	fps.tooltip_text = mod.tr_key("pax_corptimizer_fps_cap_tip")
	for i: int in FPS_CAPS.size():
		var v: int = FPS_CAPS[i]
		fps.add_item(mod.tr_key("pax_corptimizer_fps_cap_off") if v == 0 else str(v), v)
		if v == profiler.tuner.fps_cap:
			fps.select(i)
	fps.item_selected.connect(func(i: int) -> void: mod.call("set_fps_cap", fps.get_item_id(i)))
	fps_row.add_child(fps)
	add_child(fps_row)
	_upscale_rows()
	_lod_rows()
	_threads_rows()

	var cover_v: Variant = mod.get("cover")
	var skip_on := true
	var skip_3d := true
	if cover_v is Object:
		skip_on = bool((cover_v as Object).get("enabled"))
		skip_3d = bool((cover_v as Object).get("hide_3d"))
	var skip_row := HBoxContainer.new()
	skip_row.add_theme_constant_override("separation", 12)
	var skip := CheckBox.new()
	skip.text = mod.tr_key("pax_corptimizer_skip_cover")
	skip.tooltip_text = mod.tr_key("pax_corptimizer_skip_cover_tip")
	skip.button_pressed = skip_on
	var no3d := CheckBox.new()
	no3d.text = mod.tr_key("pax_corptimizer_skip_3d")
	no3d.tooltip_text = mod.tr_key("pax_corptimizer_skip_3d_tip")
	no3d.button_pressed = skip_3d
	var apply := func(_on: bool) -> void: mod.call("set_skip_cover", skip.button_pressed, no3d.button_pressed)
	skip.toggled.connect(apply)
	no3d.toggled.connect(apply)
	skip_row.add_child(skip)
	skip_row.add_child(no3d)
	add_child(skip_row)

	var hint := Label.new()
	hint.text = mod.tr_key("pax_corptimizer_analyze_tip")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = DIM
	add_child(hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_run = Button.new()
	_run.text = mod.tr_key("pax_corptimizer_analyze")
	_run.pressed.connect(_start)
	row.add_child(_run)
	_copy = Button.new()
	_copy.text = mod.tr_key("pax_corptimizer_copy")
	_copy.disabled = profiler.last_plain.is_empty()
	_copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(profiler.last_plain)
		_status.text = mod.tr_key("pax_corptimizer_copied"))
	row.add_child(_copy)
	add_child(row)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = DIM
	add_child(_status)

	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.selection_enabled = true
	_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_out.custom_minimum_size = Vector2(0, 220)
	_out.text = profiler.last_text
	add_child(_out)

	# The author's Boosty: the player can always support the mods' developer.
	var support := HBoxContainer.new()
	support.add_theme_constant_override("separation", 8)
	var boosty := Button.new()
	boosty.icon = mod.call("icon", "ui/boosty") as Texture2D
	boosty.text = mod.tr_key("pax_corptimizer_boosty")
	boosty.tooltip_text = mod.tr_key("pax_corptimizer_boosty_tip")
	boosty.focus_mode = Control.FOCUS_NONE
	boosty.add_theme_constant_override("icon_max_width", 20)
	boosty.pressed.connect(func() -> void: mod.call("open_link", BOOSTY))
	support.add_child(boosty)
	var bug := Button.new()
	bug.icon = mod.call("icon", "ui/bug") as Texture2D
	bug.text = mod.tr_key("pax_corptimizer_bug")
	bug.tooltip_text = mod.tr_key("pax_corptimizer_bug_tip")
	bug.focus_mode = Control.FOCUS_NONE
	bug.add_theme_constant_override("icon_max_width", 20)
	bug.pressed.connect(_open_feedback)
	support.add_child(bug)
	var journal := Button.new()
	journal.text = "📜 " + mod.tr_key("pax_corptimizer_log_title")
	journal.tooltip_text = mod.tr_key("pax_corptimizer_log_open_tip")
	journal.focus_mode = Control.FOCUS_NONE
	journal.pressed.connect(_open_journal)
	support.add_child(journal)
	var thanks := Label.new()
	thanks.text = mod.tr_key("pax_corptimizer_boosty_text")
	thanks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	thanks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thanks.modulate = DIM
	support.add_child(thanks)
	add_child(support)

	profiler.progress.connect(_on_progress)
	profiler.finished.connect(_on_finished)


## Upscaling: the upscaler (what this computer cannot do is greyed out, DLSS and XeSS among them — not in the engine),
## the render scale, FSR's sharpness, the anti-aliasing.
## «Детали по дальности» (render/lod.gd) and «Значки корпораций по дальности» (map/icons_lod.gd), with what they do now.
func _lod_rows() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = mod.tr_key("pax_corptimizer_lod")
	label.tooltip_text = mod.tr_key("pax_corptimizer_lod_tip")
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var opt := OptionButton.new()
	opt.tooltip_text = mod.tr_key("pax_corptimizer_lod_tip")
	var cur := str(mod.get_setting("lod2", "off"))
	for i in Lod.MODES.size():
		opt.add_item(mod.tr_key("pax_corptimizer_lod_" + str(Lod.MODES[i])), i)
		if Lod.MODES[i] == cur:
			opt.select(i)
	opt.item_selected.connect(func(i: int) -> void: mod.call("set_lod", Lod.MODES[i]))
	row.add_child(opt)
	add_child(row)
	var icons := CheckBox.new()
	icons.text = mod.tr_key("pax_corptimizer_icons_lod")
	icons.tooltip_text = mod.tr_key("pax_corptimizer_icons_lod_tip")
	icons.button_pressed = bool(mod.get_setting("icons_lod", true))
	icons.toggled.connect(func(on: bool) -> void: mod.call("set_icons_lod", on))
	add_child(icons)
	var now := Label.new()
	now.add_theme_font_size_override("font_size", 12)
	now.modulate = Color(1, 1, 1, 0.7)
	now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(now)
	var tick := Timer.new()
	tick.wait_time = 0.5
	tick.autostart = true
	_lod_now = now
	tick.timeout.connect(_show_lod)
	add_child(tick)


var _lod_now: Label


func _show_lod() -> void:
	if not is_instance_valid(_lod_now) or not _lod_now.is_visible_in_tree():
		return
	var l: Variant = mod.get("lod")
	var ic: Variant = mod.get("icons_lod")
	var vp := get_viewport()
	var share := int(round(float((l as Object).get("now_share")) * 100.0)) if l is Object else 0
	var shown := int((ic as Object).get("shown")) if ic is Object else 0
	var total := int((ic as Object).get("total")) if ic is Object else 0
	_lod_now.text = mod.tr_key("pax_corptimizer_lod_now") % [share, vp.texture_mipmap_bias if vp != null else 0.0,
		vp.mesh_lod_threshold if vp != null else 1.0, shown, total]


## «Многопоточность»: one switch for the mods' heavy work on the processor's other cores, and what runs there.
func _threads_rows() -> void:
	var cb := CheckBox.new()
	cb.text = mod.tr_key("pax_corptimizer_threads")
	cb.tooltip_text = mod.tr_key("pax_corptimizer_threads_tip")
	cb.button_pressed = bool(mod.get_setting("threads", true))
	cb.toggled.connect(func(on: bool) -> void: mod.call("set_threads", on))
	add_child(cb)
	var rel := CheckBox.new()
	rel.text = mod.tr_key("pax_corptimizer_relief")
	rel.tooltip_text = mod.tr_key("pax_corptimizer_relief_tip")
	rel.button_pressed = bool(mod.get_setting("relief", true))
	rel.toggled.connect(func(on: bool) -> void: mod.call("set_relief", on))
	add_child(rel)
	var info := Label.new()
	var cores := OS.get_processor_count()
	info.text = mod.tr_key("pax_corptimizer_threads_info") % [cores, maxi(1, cores - 1)]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 12)
	info.modulate = Color(1, 1, 1, 0.7)
	add_child(info)


func _upscale_rows() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = mod.tr_key("pax_corptimizer_upscale")
	label.tooltip_text = mod.tr_key("pax_corptimizer_upscale_tip")
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var mode := OptionButton.new()
	mode.tooltip_text = mod.tr_key("pax_corptimizer_upscale_tip")
	var cur_mode := str(mod.get_setting("upscale_mode", "off"))
	for i: int in Upscale.MODES.size():
		var m: String = Upscale.MODES[i]
		mode.add_item(mod.tr_key("pax_corptimizer_upscale_" + m), i)
		if not Upscale.available(m):
			mode.set_item_disabled(i, true)
			mode.set_item_tooltip(i, mod.tr_key("pax_corptimizer_upscale_na_" + ("engine" if m in ["dlss", "xess"] else "renderer")))
		if m == cur_mode:
			mode.select(i)
	row.add_child(mode)
	var scale := OptionButton.new()
	var cur_scale := float(mod.get_setting("upscale_scale", 0.77))
	for i: int in Upscale.SCALES.size():
		scale.add_item(mod.tr_key("pax_corptimizer_scale_%d" % i) + " (%d%%)" % roundi(Upscale.SCALES[i] * 100.0), i)
		if absf(Upscale.SCALES[i] - cur_scale) < 0.005:
			scale.select(i)
	row.add_child(scale)
	add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	var sharp_label := Label.new()
	sharp_label.text = mod.tr_key("pax_corptimizer_sharpness")
	row2.add_child(sharp_label)
	var sharp := HSlider.new()
	sharp.min_value = 0.0
	sharp.max_value = 1.0
	sharp.step = 0.05
	sharp.value = float(mod.get_setting("upscale_sharp", 0.5))
	sharp.custom_minimum_size = Vector2(120, 0)
	row2.add_child(sharp)
	var aa_label := Label.new()
	aa_label.text = mod.tr_key("pax_corptimizer_aa")
	aa_label.tooltip_text = mod.tr_key("pax_corptimizer_aa_tip")
	aa_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row2.add_child(aa_label)
	var aa := OptionButton.new()
	var cur_aa := str(mod.get_setting("upscale_aa", "game"))
	for i: int in Upscale.AA.size():
		aa.add_item(mod.tr_key("pax_corptimizer_aa_" + Upscale.AA[i]), i)
		if Upscale.AA[i] == cur_aa:
			aa.select(i)
	row2.add_child(aa)
	add_child(row2)
	var apply := func() -> void:
		mod.call("set_upscale", Upscale.MODES[maxi(mode.selected, 0)], Upscale.SCALES[maxi(scale.selected, 0)], sharp.value, Upscale.AA[maxi(aa.selected, 0)])
	mode.item_selected.connect(func(_i: int) -> void: apply.call())
	scale.item_selected.connect(func(_i: int) -> void: apply.call())
	sharp.drag_ended.connect(func(_changed: bool) -> void: apply.call())
	aa.item_selected.connect(func(_i: int) -> void: apply.call())


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5 or not is_visible_in_tree():
		return
	_t = 0.0
	_live.text = profiler.live_text()
	_run.disabled = profiler.running


func _start() -> void:
	_run.disabled = true
	_out.text = ""
	profiler.analyze()


func _on_progress(text: String) -> void:
	_status.text = text
	_run.disabled = profiler.running


func _on_finished(text: String) -> void:
	_status.text = mod.tr_key("pax_corptimizer_done")
	_out.text = text
	_copy.disabled = false
	_run.disabled = false


## «Связь с разработчиком» (feedback.gd) on the game's HUD layer.
var _feedback: Feedback


func _open_feedback() -> void:
	if not is_instance_valid(_feedback):
		var g: Variant = mod.get("_game")
		var layer: Variant = (g as PaxGame).hud_layer() if g is PaxGame else null
		_feedback = Feedback.new()
		_feedback.setup(mod, "pax_corptimizer_")
		_feedback.on_journal = _open_journal
		_feedback.visible = false
		if layer is CanvasLayer:
			(layer as CanvasLayer).add_child(_feedback)
		else:
			get_tree().root.add_child(_feedback)
	_feedback.reset_size()
	var view := get_viewport_rect().size
	_feedback.position = Vector2(maxf(16.0, (view.x - 600.0) / 2.0), maxf(16.0, view.y * 0.12))
	_feedback.toggle()


## «Журнал модов» (log_window.gd) on the game's HUD layer; «?» shows its help in place.
var _journal: LogWindow


func _open_journal() -> void:
	if not is_instance_valid(_journal):
		var g: Variant = mod.get("_game")
		var layer: Variant = (g as PaxGame).hud_layer() if g is PaxGame else null
		_journal = LogWindow.new()
		_journal.setup(mod, "pax_corptimizer_")
		_journal.visible = false
		if layer is CanvasLayer:
			(layer as CanvasLayer).add_child(_journal)
		else:
			get_tree().root.add_child(_journal)
	_journal.reset_size()
	var view := get_viewport_rect().size
	_journal.position = Vector2(maxf(16.0, (view.x - 760.0) / 2.0), maxf(16.0, view.y * 0.1))
	_journal.toggle()


func _exit_tree() -> void:
	if is_instance_valid(_feedback):
		_feedback.queue_free()
	if is_instance_valid(_journal):
		_journal.queue_free()
