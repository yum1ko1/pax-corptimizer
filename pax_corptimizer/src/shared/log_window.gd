extends PanelContainer
## «Журнал модов» — the shared journal of the Pax CorpInc mods (log_hub.gd) for the player: what the mods did and
## which errors happened (also the engine's errors in our scripts), filtered by level, mod and words; «Copy» puts it
## on the clipboard, «Send to the developer» uploads it to the author's server (the same link as the feedback window:
## config/feedback.json «сервер»; the author reads the journals on his private page, not in Telegram).
## «?» — the mini tour (Pax Corpface), or a short help in place when there is no tour.

const Feedback := preload("res://mods/pax_corptimizer/src/shared/feedback.gd")
const WheelGuard := preload("res://mods/pax_corptimizer/src/shared/wheel_guard.gd")
const META := &"pax_corpinc_log"
const RANK := ["debug", "info", "warn", "error"]
const COLORS := {"debug": Color(0.6, 0.62, 0.66), "info": Color(0.82, 0.86, 0.9), "warn": Color(1.0, 0.78, 0.35),
	"error": Color(1.0, 0.45, 0.42)}
const SHOW_MAX := 400
const DIM := Color(1, 1, 1, 0.62)

var mod: Object
var prefix := ""
var on_help := Callable()
var tut := {}                     # parts for the mini tour
var _level: OptionButton
var _mods: OptionButton
var _find: LineEdit
var _list: RichTextLabel
var _status: Label
var _help_text: Label
var _seen := -1
var _wait := 0.0


func _t(key: String) -> String:
	return str(mod.call("tr_key", prefix + key))


func setup(m: Object, lang_prefix: String, help: Callable = Callable()) -> void:
	mod = m
	prefix = lang_prefix
	on_help = help


func _hub() -> Object:
	var h: Variant = Engine.get_meta(META) if Engine.has_meta(META) else null
	return h as Object if h is Object and is_instance_valid(h) else null


func _ready() -> void:
	name = "PaxCorpIncJournal"
	set_meta(&"pax_corp_skin_skip", true)
	set_meta(&"pax_interface_skip_skin", true)
	z_index = 36
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not has_theme_stylebox_override("panel"):
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.09, 0.11, 0.14, 0.97)
		sb.border_color = Color(1, 1, 1, 0.14)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(18)
		add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(760, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var title := Label.new()
	title.text = "📜 " + _t("log_title")
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var help := Button.new()
	help.text = "?"
	help.tooltip_text = _t("log_help_tip")
	help.focus_mode = Control.FOCUS_NONE
	help.custom_minimum_size = Vector2(34, 30)
	head.add_child(help)
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(34, 30)
	x.pressed.connect(func() -> void: visible = false)
	head.add_child(x)

	_help_text = Label.new()
	_help_text.text = _t("log_help")
	_help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_text.modulate = DIM
	_help_text.visible = false
	v.add_child(_help_text)
	help.pressed.connect(func() -> void:
		if on_help.is_valid():
			on_help.call()
		else:
			_help_text.visible = not _help_text.visible)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	v.add_child(filters)
	tut["filters"] = filters
	_level = OptionButton.new()
	for k in ["log_lv_all", "log_lv_warn", "log_lv_error"]:
		_level.add_item(_t(k))
	_level.select(1)
	_level.focus_mode = Control.FOCUS_NONE
	_level.item_selected.connect(func(_i: int) -> void: _redraw())
	filters.add_child(_level)
	_mods = OptionButton.new()
	_mods.add_item(_t("log_mod_all"))
	for id in ["pax_corporations", "pax_corpface", "pax_corptimizer", "pax_corpinc3d"]:
		_mods.add_item(id.trim_prefix("pax_"))
	_mods.focus_mode = Control.FOCUS_NONE
	_mods.item_selected.connect(func(_i: int) -> void: _redraw())
	filters.add_child(_mods)
	_find = LineEdit.new()
	_find.placeholder_text = _t("log_find")
	_find.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_find.text_changed.connect(func(_s: String) -> void: _redraw())
	filters.add_child(_find)

	_list = RichTextLabel.new()
	_list.bbcode_enabled = true
	_list.selection_enabled = true
	_list.scroll_following = true
	_list.custom_minimum_size = Vector2(0, 360)
	_list.add_theme_font_size_override("normal_font_size", 12)
	v.add_child(_list)
	tut["list"] = _list

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var copy := Button.new()
	copy.text = "📋 " + _t("log_copy")
	copy.tooltip_text = _t("log_copy_tip")
	copy.focus_mode = Control.FOCUS_NONE
	copy.pressed.connect(func() -> void:
		var h := _hub()
		if h != null:
			DisplayServer.clipboard_set(str(h.call("text", "debug", 800)))
			_status.text = _t("log_copied"))
	row.add_child(copy)
	var clear := Button.new()
	clear.text = "🗑 " + _t("log_clear")
	clear.focus_mode = Control.FOCUS_NONE
	clear.pressed.connect(func() -> void:
		var h := _hub()
		if h != null:
			h.call("clear")
		_redraw())
	row.add_child(clear)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var send := Button.new()
	send.text = "📤 " + _t("log_send")
	send.tooltip_text = _t("log_send_tip")
	send.focus_mode = Control.FOCUS_NONE
	send.pressed.connect(func() -> void: _status.text = Feedback.send_journal(mod, prefix))
	row.add_child(send)
	tut["send"] = send

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = DIM
	v.add_child(_status)
	add_child(WheelGuard.new())
	_redraw()


func toggle() -> void:
	visible = not visible
	if visible:
		_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_wait -= delta
	var h := _hub()
	if _wait > 0.0 or h == null or int(h.get("serial")) == _seen:
		return
	_wait = 0.5
	_redraw()


func _redraw() -> void:
	if _list == null:
		return
	var h := _hub()
	if h == null:
		_list.text = _t("log_none")
		return
	_seen = int(h.get("serial"))
	var lo: int = [0, 2, 3][_level.selected]
	var only := "" if _mods.selected <= 0 else "pax_" + _mods.get_item_text(_mods.selected)
	var words := _find.text.strip_edges().to_lower()
	var shown: Array = (h.call("entries") as Array).filter(func(e: Dictionary) -> bool:
		return RANK.find(str(e["l"])) >= lo and (only.is_empty() or str(e["m"]) == only) \
			and (words.is_empty() or str(e["s"]).to_lower().contains(words) or str(e["c"]).to_lower().contains(words)))
	shown = shown.slice(maxi(0, shown.size() - SHOW_MAX))
	var parts: PackedStringArray = []
	for e in shown:
		var line: String = h.call("line_of", e)
		parts.append("[color=#%s]%s[/color]" % [(COLORS.get(str(e["l"]), Color.WHITE) as Color).to_html(false),
			line.replace("[", "[lb]")])
	_list.text = "\n".join(parts) if not parts.is_empty() else _t("log_empty")
	_status.text = _t("log_counts") % [int(h.get("errors")), int(h.get("warnings"))]
