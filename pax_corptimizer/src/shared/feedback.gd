extends PanelContainer
## «Связь с разработчиком» — a bug report, a wish or a rating for the author of the Pax CorpInc mods (Pax Corpface,
## Pax Corptimizer — each carries a copy of this file; texts «<prefix>fb_*»). A mod may not use the network, so the
## message travels inside a link: {k kind, p player id, l language, v versions, t text, n nickname, j journal} →
## JSON → gzip → base64url,
## opened as <сервер>/r?d=… (config/feedback.json «сервер» — the author's Cloudflare Worker,
## pax_corporations_dev/feedback_worker). The Worker posts it to the author's group through his bot and shows
## «sent» in a browser tab — no Telegram for the player. The player's id (random, kept in the settings, shared by the
## copies through Engine meta) lets the author ban: the Worker then refuses and says so. No server — sending is off.

const KINDS := [["bug", "#Баг", "🐞"], ["wish", "#Пожелание", "💡"], ["praise", "#Оценка/Похвала", "👍"], ["complaint", "#Оценка/Жалоба", "👎"]]
const MAX_LEN := 1500
const COOLDOWN_MS := 60000
const URL_MAX := 2000            # Windows opens links up to ~2 000 characters
const PLAYER := &"pax_corpinc_player"   # the player's id, shared by the copies
const NICK := &"pax_corpinc_nick"       # the player's nickname (optional), shared by the copies
const GZIP := 3                  # the compression mode GZIP
const REG := &"pax_whatsnew_registry"   # the author's mods register there (whatsnew.gd): their names and versions
const DIM := Color(1, 1, 1, 0.62)
const WheelGuard := preload("res://mods/pax_corptimizer/src/shared/wheel_guard.gd")

const LOG_META := &"pax_corpinc_log"   # the shared journal (log_hub.gd)
const JOURNAL_START := 12000     # characters of the journal tried first; fewer until the link fits

static var _last_send := -COOLDOWN_MS
static var _last_journal := -COOLDOWN_MS

var mod: Object
var prefix := ""
var on_help := Callable()      # the «?» mini tour (Pax Corpface), none — no «?»
var on_journal := Callable()   # opens the journal window (log_window.gd), set by the owner; none — no button
var tut := {}                  # parts for the mini tour
var _kind := "bug"
var _text: TextEdit
var _count: Label
var _status: Label
var _versions: CheckBox
var _journal: CheckBox
var _send: Button
var _id_label: Label


func _t(key: String) -> String:
	return str(mod.call("tr_key", prefix + key))


func setup(m: Object, lang_prefix: String, help: Callable = Callable()) -> void:
	mod = m
	prefix = lang_prefix
	on_help = help


func _cfg() -> Dictionary:
	var v: Variant = _json(mod, "config/feedback.json", {})
	return v if v is Dictionary else {}


func _ready() -> void:
	name = "PaxCorpIncFeedback"
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
	custom_minimum_size = Vector2(600, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var title := Label.new()
	title.text = _t("fb_title")
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if on_help.is_valid():
		var help := Button.new()
		help.text = "?"
		help.tooltip_text = _t("fb_help_tip")
		help.focus_mode = Control.FOCUS_NONE
		help.custom_minimum_size = Vector2(34, 30)
		help.pressed.connect(func() -> void: on_help.call())
		head.add_child(help)
	# ⚙ — the player's nickname, shown in brackets after his number (the developer sees who wrote).
	var gear := Button.new()
	gear.text = "⚙"
	gear.tooltip_text = _t("fb_nick_tip")
	gear.focus_mode = Control.FOCUS_NONE
	gear.custom_minimum_size = Vector2(34, 30)
	head.add_child(gear)
	tut["gear"] = gear
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(34, 30)
	x.pressed.connect(func() -> void: visible = false)
	head.add_child(x)

	var nick_row := HBoxContainer.new()
	nick_row.add_theme_constant_override("separation", 8)
	nick_row.visible = false
	v.add_child(nick_row)
	var nl := Label.new()
	nl.text = _t("fb_nick")
	nick_row.add_child(nl)
	var nick := LineEdit.new()
	nick.max_length = 24
	nick.placeholder_text = _t("fb_nick_ph")
	nick.text = nick_name()
	nick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nick.text_changed.connect(func(s: String) -> void:
		var clean := s.strip_edges().replace("(", "").replace(")", "")
		mod.call("set_setting", "fb_nick", clean)
		Engine.set_meta(NICK, clean)
		mod.call("log_info", "feedback: nickname «%s»" % clean)
		_id_label.text = _t("fb_player") % _who())
	nick_row.add_child(nick)
	gear.pressed.connect(func() -> void: nick_row.visible = not nick_row.visible)

	var sub := Label.new()
	sub.text = _t("fb_sub")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.modulate = DIM
	v.add_child(sub)

	var kinds := HBoxContainer.new()
	kinds.add_theme_constant_override("separation", 6)
	v.add_child(kinds)
	tut["kinds"] = kinds
	var group := ButtonGroup.new()
	for k in KINDS:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.text = "%s %s" % [str(k[2]), str(k[1])]
		b.tooltip_text = _t("fb_kind_" + str(k[0]) + "_tip")
		b.button_pressed = str(k[0]) == _kind
		var id := str(k[0])
		b.pressed.connect(func() -> void:
			_kind = id
			_journal.visible = id == "bug"   # the journal goes with bug reports only
			_text.placeholder_text = _t("fb_hint_" + id))
		kinds.add_child(b)

	_text = TextEdit.new()
	_text.custom_minimum_size = Vector2(0, 200)
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.placeholder_text = _t("fb_hint_" + _kind)
	_text.text_changed.connect(_on_text)
	v.add_child(_text)
	tut["text"] = _text

	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 10)
	v.add_child(opts)
	_versions = CheckBox.new()
	_versions.text = _t("fb_versions")
	_versions.tooltip_text = _t("fb_versions_tip")
	_versions.button_pressed = true
	opts.add_child(_versions)
	_journal = CheckBox.new()
	_journal.text = _t("fb_journal")
	_journal.tooltip_text = _t("fb_journal_tip")
	_journal.button_pressed = true
	_journal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opts.add_child(_journal)
	tut["journal"] = _journal
	_count = Label.new()
	_count.modulate = DIM
	opts.add_child(_count)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_send = Button.new()
	_send.text = _t("fb_send")
	_send.tooltip_text = _t("fb_send_tip")
	_send.focus_mode = Control.FOCUS_NONE
	_send.pressed.connect(_do_send)
	row.add_child(_send)
	tut["send"] = _send

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = DIM
	_status.text = _t("fb_rules")
	v.add_child(_status)
	# The answers: the developer's replies to this player's messages (the server's page for his number).
	var mine := Button.new()
	mine.text = "💬 " + _t("fb_mine")
	mine.tooltip_text = _t("fb_mine_tip")
	mine.focus_mode = Control.FOCUS_NONE
	mine.pressed.connect(func() -> void:
		var server := str(_cfg().get("сервер", "")).strip_edges().trim_suffix("/")
		if server.begins_with("https://"):
			mod.call("open_link", "%s/me?p=%s&l=%s" % [server, player_id(), "ru" if TranslationServer.get_locale().begins_with("ru") else "en"]))
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 8)
	v.add_child(links)
	links.add_child(mine)
	tut["mine"] = mine
	if on_journal.is_valid():
		var jb := Button.new()
		jb.text = "📜 " + _t("log_title")
		jb.tooltip_text = _t("log_open_tip")
		jb.focus_mode = Control.FOCUS_NONE
		jb.pressed.connect(func() -> void: on_journal.call())
		links.add_child(jb)
		tut["journal_button"] = jb
	add_child(WheelGuard.new())
	var idl := Label.new()
	_id_label = idl
	idl.text = _t("fb_player") % _who()
	idl.tooltip_text = _t("fb_player_tip")
	idl.mouse_filter = Control.MOUSE_FILTER_PASS
	idl.add_theme_font_size_override("font_size", 11)
	idl.modulate = Color(1, 1, 1, 0.45)
	v.add_child(idl)
	_on_text()


func toggle() -> void:
	visible = not visible
	if visible:
		_text.grab_focus()


func _on_text() -> void:
	if _text.text.length() > MAX_LEN:
		var col := _text.get_caret_column()
		_text.text = _text.text.substr(0, MAX_LEN)
		_text.set_caret_line(_text.get_line_count() - 1)
		_text.set_caret_column(mini(col, _text.get_line(_text.get_line_count() - 1).length()))
	_count.text = "%d / %d" % [_text.text.length(), MAX_LEN]


func _tag() -> String:
	for k in KINDS:
		if str(k[0]) == _kind:
			return str(k[1])
	return "#Баг"


func _mods_line() -> String:
	return mods_line()


## The author's mods in this game and their versions (their «What's new» copies register them).
static func mods_line() -> String:
	var reg: Dictionary = Engine.get_meta(REG, {}) if Engine.has_meta(REG) else {}
	var parts: PackedStringArray = []
	for id in reg.keys():
		var o: Variant = reg[id]
		if o is Object and is_instance_valid(o):
			parts.append("%s %s" % [str((o as Object).call("display_name")), str((o as Object).call("version"))])
	parts.sort()
	return " · ".join(parts)


func player_id() -> String:
	return player_of(mod)


func nick_name() -> String:
	return nick_of(mod)


## The player's id: 8 letters and digits, made once, kept in the mod's settings and shared with the other copies.
static func player_of(m: Object) -> String:
	# The shared number first (one for all the author's mods), then this mod's own.
	var own := str(Engine.get_meta(PLAYER, "")) if Engine.has_meta(PLAYER) else ""
	if own.is_empty():
		own = str(m.call("get_setting", "fb_player", ""))
	if own.is_empty():
		var abc := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
		for i in 8:
			own += abc[randi() % abc.length()]
	if str(m.call("get_setting", "fb_player", "")) != own:
		m.call("set_setting", "fb_player", own)
	Engine.set_meta(PLAYER, own)
	return own


## The nickname the player wrote (⚙), "" — none.
static func nick_of(m: Object) -> String:
	var n := str(Engine.get_meta(NICK, "")) if Engine.has_meta(NICK) else ""
	if n.is_empty():
		n = str(m.call("get_setting", "fb_nick", ""))
	return n


## «AB12CD34 (nickname)».
func _who() -> String:
	var n := nick_name()
	return player_id() + (" (%s)" % n if not n.is_empty() else "")


## The link that carries the message (gzip + base64url inside); with the journal when asked and it fits.
func _link(server: String, text: String) -> String:
	return link_of(mod, server, _kind, text, _versions.button_pressed, _journal.button_pressed and _kind == "bug")


## {k kind, p player, l language, v versions, t text, n nickname, j journal} → JSON → gzip → base64url → <server>/r?d=…
## The journal (log_hub.report) is cut until the whole link fits URL_MAX; none if even the text alone is too long.
static func link_of(m: Object, server: String, kind: String, text: String, versions: bool, journal: bool) -> String:
	var d := {"k": kind, "p": player_of(m), "l": "ru" if TranslationServer.get_locale().begins_with("ru") else "en",
		"v": mods_line() if versions else "", "t": text, "n": nick_of(m)}
	var hub: Variant = Engine.get_meta(LOG_META) if Engine.has_meta(LOG_META) else null
	var chars := JOURNAL_START if journal and hub is Object and is_instance_valid(hub) else 0
	while true:
		if chars > 0:
			d["j"] = str((hub as Object).call("report", chars))
		else:
			d.erase("j")
		var packed: PackedByteArray = JSON.stringify(d).to_utf8_buffer().compress(GZIP)
		var b64 := Marshalls.raw_to_base64(packed).replace("+", "-").replace("/", "_").replace("=", "")
		var link := "%s/r?d=%s" % [server.trim_suffix("/"), b64]
		if link.length() <= URL_MAX or chars == 0:
			return link
		chars = int(float(chars) * 0.7) if chars > 400 else 0
	return ""


## The server from config/feedback.json («сервер»), "" — none.
static func server_of(m: Object) -> String:
	var v: Variant = _json(m, "config/feedback.json", {})
	return str((v as Dictionary).get("сервер", "")).strip_edges() if v is Dictionary else ""


## «Send the journal to the developer» (the journal window): uploads it to the author's server, which keeps it for him
## (his private page — not Telegram). Returns the status line for the window.
static func send_journal(m: Object, prefix: String) -> String:
	var now := Time.get_ticks_msec()
	if now - _last_journal < COOLDOWN_MS:
		return str(m.call("tr_key", prefix + "fb_wait")) % ceili(float(COOLDOWN_MS - (now - _last_journal)) / 1000.0)
	var server := server_of(m)
	if not server.begins_with("https://"):
		return str(m.call("tr_key", prefix + "fb_no_bot"))
	var link := link_of(m, server, "log", "", true, true)
	var opened: Variant = m.call("open_link", link)
	if opened is bool and not bool(opened):
		DisplayServer.clipboard_set(link)
		return str(m.call("tr_key", prefix + "fb_link_refused"))
	_last_journal = now
	return str(m.call("tr_key", prefix + "log_sent"))


func _log(text: String) -> void:
	if mod != null and mod.has_method("log_info"):
		mod.call("log_info", "feedback: " + text)


func _do_send() -> void:
	_status.text = _t("fb_sending")
	_log("send pressed")
	var body := _text.text.strip_edges()
	if body.length() < 5:
		_status.text = _t("fb_too_short")
		return
	var now := Time.get_ticks_msec()
	if now - _last_send < COOLDOWN_MS:
		_status.text = _t("fb_wait") % ceili(float(COOLDOWN_MS - (now - _last_send)) / 1000.0)
		return
	var server := str(_cfg().get("сервер", "")).strip_edges()
	if not server.begins_with("https://"):
		_log("no server in config/feedback.json")
		_status.text = _t("fb_no_bot")
		return
	var link := _link(server, body)
	_log("link of %d characters, player %s, nickname «%s»" % [link.length(), player_id(), nick_name()])
	if link.length() > URL_MAX:
		# Too long for one link: how much shorter it must be.
		var fits := int(float(body.length()) * float(URL_MAX - server.length() - 10) / float(link.length() - server.length() - 10))
		_status.text = _t("fb_too_long") % maxi(0, body.length() - fits + 20)
		return
	var opened: Variant = mod.call("open_link", link)
	_log("open_link -> %s" % str(opened))
	if opened is bool and not bool(opened):
		# The game refused to open it: the player can open the link himself.
		DisplayServer.clipboard_set(link)
		_status.text = _t("fb_link_refused")
		return
	_last_send = now
	_status.text = _t("fb_sent")


## A JSON file of the mod as written: game 0.24's load_json translates Russian keys and values on the way in
## («ключ» → «key», «название» → «title_name»), and the mod's data stopped matching its code. read_text does not.
static func _json(m: Object, relative: String, default_value: Variant = null) -> Variant:
	var text: String = str(m.call("read_text", relative)) if is_instance_valid(m) else ""
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	return default_value if parsed == null else parsed
