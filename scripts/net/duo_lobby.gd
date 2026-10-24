extends Control
## Salon DUO (bouton DUO du Relais) : HÉBERGER ou REJOINDRE sur le réseau local, ou INTERNET (salle à code).
## Montre l'état de la connexion et le partenaire ; l'hôte lance la partie (PARTIR ENSEMBLE).
## Le Relais 3D reste visible à gauche, le panneau est à droite (même mise en page que la Loge).

const UI = preload("res://scripts/ui.gd")
const Fx = preload("res://scripts/ui/fx.gd")
const Discovery = preload("res://scripts/net/discovery.gd")

var duo: Node
var main: Node
var mode := "menu"  # menu | host_lan | join_lan | internet | relay_room
var _status: Label
var _partner: Label
var _go: Button
var _hosts: VBoxContainer
var _hosts_sig := ""
var _ip: LineEdit
var _code: LineEdit
var _relay_box: VBoxContainer
var _relay_sig := ""
var _room_l: Label
var _box: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_status = null
	_partner = null
	_go = null
	_hosts = null
	_hosts_sig = ""
	_relay_box = null
	_relay_sig = ""
	_room_l = null
	add_child(main._side_shade(0.22))
	var ins := UI.safe_insets(get_viewport())
	_box = UI.vbox(12)
	_box.anchor_left = 0.42
	_box.anchor_right = 1.0
	_box.offset_right = -float(ins["right"]) - 28.0
	_box.anchor_top = 0.06
	_box.anchor_bottom = 0.96
	add_child(_box)
	var head := UI.hbox(14)
	_box.add_child(head)
	head.add_child(UI.title("DUO", 64, UI.TEXT, UI.ORANGE))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var back := UI.button("RETOUR" if mode == "menu" else "ANNULER", 24, UI.MUTED, 170)
	back.custom_minimum_size = Vector2(170, 76)
	back.pressed.connect(_back)
	head.add_child(back)
	match mode:
		"menu":
			_build_menu()
		"host_lan":
			_build_host_lan()
		"join_lan":
			_build_join_lan()
		"internet":
			_build_internet()
		"relay_room":
			_build_relay_room()
	Fx.slide_in(_box, Vector2(140, 0), 0.0, 0.35)

func _back() -> void:
	main.sfx.play("click", 0.9, -6.0)
	if mode == "menu":
		duo.leave()
		return
	duo.shutdown()
	duo.phase = "lobby"
	mode = "menu"
	rebuild()

func _text(t: String, size: int = 21, col: Color = UI.MUTED) -> Label:
	var l := UI.label(t, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(l)
	return l

func _big(t: String, sub: String, col: Color, cb: Callable) -> Button:
	var b := UI.button(t, 30, col)
	b.custom_minimum_size = Vector2(0, 96)
	b.add_theme_font_override("font", UI.TITLE)
	b.pressed.connect(func():
		main.sfx.play("click", 1.0, -6.0)
		cb.call())
	_box.add_child(b)
	if sub != "":
		var l := UI.label(sub, 18, UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(l)
	return b

func _status_rows() -> void:
	_status = _text("", 22, UI.TEXT)
	_partner = _text("", 24, UI.ACCENT)

func _go_button(label: String) -> void:
	_go = UI.primary(label, 40)
	_go.custom_minimum_size = Vector2(0, 104)
	_go.pressed.connect(func(): duo.go())
	_box.add_child(_go)

# ---------------------------------------------------------------- écrans
func _build_menu() -> void:
	_text("Deux téléphones, une partie en coopération. Les ennemis visent la Jo la plus proche ; une Jo à terre se relève si l'autre reste 2 s près d'elle.", 20)
	_big("HÉBERGER", "Réseau local : même Wi-Fi, ou partage de connexion de ce téléphone.", UI.ACCENT, func():
		duo.host_lan()
		mode = "host_lan"
		rebuild())
	_big("REJOINDRE", "Réseau local : la partie hébergée apparaît toute seule.", UI.ACCENT, func():
		duo.shutdown()
		duo.phase = "lobby"
		duo.role = "guest"
		duo.listen_lan()
		mode = "join_lan"
		rebuild())
	_big("INTERNET", "Par le relais en ligne : une salle, un code à 4 lettres.", UI.ORANGE, func():
		duo.fetch_relay()
		mode = "internet"
		rebuild())
	if duo.status.begins_with("Connexion perdue"):
		_text(duo.status, 19, UI.DANGER)

func _build_host_lan() -> void:
	_text("Tu héberges la partie (J1).", 22, UI.TEXT)
	var ips := Discovery.local_ipv4()
	var ip_txt := "Adresse de ce téléphone : " + (", ".join(ips) if not ips.is_empty() else "aucun réseau local")
	var l := _text(ip_txt, 26, UI.GOLD)
	l.add_theme_font_override("font", UI.TITLE)
	_text("Ton partenaire touche REJOINDRE : ta partie apparaît. Sinon, il tape cette adresse.", 19)
	_status_rows()
	_go_button("PARTIR ENSEMBLE")

func _build_join_lan() -> void:
	_text("Parties trouvées sur le réseau :", 22, UI.TEXT)
	_hosts = UI.vbox(8)
	_box.add_child(_hosts)
	_text("Ou l'adresse de l'hôte :", 20)
	var row := UI.hbox(10)
	_box.add_child(row)
	_ip = LineEdit.new()
	_ip.placeholder_text = "192.168.1.20"
	_ip.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	_ip.custom_minimum_size = Vector2(0, 72)
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip.add_theme_font_size_override("font_size", 30)
	_ip.text_submitted.connect(func(t: String): duo.join_lan(t.strip_edges()))
	row.add_child(_ip)
	var j := UI.button("REJOINDRE", 24, UI.ACCENT, 190)
	j.custom_minimum_size = Vector2(190, 72)
	j.pressed.connect(func():
		if _ip.text.strip_edges() != "":
			duo.join_lan(_ip.text.strip_edges()))
	row.add_child(j)
	_status_rows()

func _build_internet() -> void:
	_relay_box = UI.vbox(12)
	_box.add_child(_relay_box)
	_status_rows()
	_fill_internet()

func _fill_internet() -> void:
	for c in _relay_box.get_children():
		c.queue_free()
	_relay_sig = String(duo.relay_state)
	match String(duo.relay_state):
		"fetching", "idle":
			_relay_box.add_child(UI.label("Recherche du serveur relais…", 22, UI.TEXT))
		"none":
			var l := UI.label("Serveur non déployé.", 30, UI.DANGER)
			l.add_theme_font_override("font", UI.TITLE)
			_relay_box.add_child(l)
			var m := UI.label("Le relais Internet n'est pas encore en ligne (procédure : server/relay/README.md). Le réseau local marche sans lui.", 19, UI.MUTED)
			m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_relay_box.add_child(m)
		"ok":
			var c := UI.button("CRÉER UNE SALLE", 30, UI.ORANGE)
			c.custom_minimum_size = Vector2(0, 96)
			c.add_theme_font_override("font", UI.TITLE)
			c.pressed.connect(func():
				duo.host_relay()
				mode = "relay_room"
				rebuild())
			_relay_box.add_child(c)
			_relay_box.add_child(UI.label("Ou rejoindre avec le code :", 20, UI.MUTED))
			var row := UI.hbox(10)
			_relay_box.add_child(row)
			_code = LineEdit.new()
			_code.placeholder_text = "ABCD"
			_code.max_length = 4
			_code.custom_minimum_size = Vector2(0, 76)
			_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_code.add_theme_font_size_override("font_size", 38)
			_code.alignment = HORIZONTAL_ALIGNMENT_CENTER
			_code.text_changed.connect(func(t: String):
				var up := t.to_upper()
				if up != t:
					var cpos := _code.caret_column
					_code.text = up
					_code.caret_column = cpos)
			row.add_child(_code)
			var j := UI.button("REJOINDRE", 24, UI.ORANGE, 190)
			j.custom_minimum_size = Vector2(190, 76)
			j.pressed.connect(func():
				if _code.text.strip_edges().length() == 4:
					duo.join_relay(_code.text.strip_edges())
					mode = "relay_room"
					rebuild())
			row.add_child(j)

func _build_relay_room() -> void:
	_room_l = _text("", 52, UI.GOLD)
	_room_l.add_theme_font_override("font", UI.TITLE)
	_text("Donne ce code à ton partenaire : INTERNET, puis REJOINDRE." if duo.is_host() else "Connexion à la salle par le relais.", 19)
	_status_rows()
	if duo.is_host():
		_go_button("PARTIR ENSEMBLE")

# ---------------------------------------------------------------- rafraîchissement
func _process(_dt: float) -> void:
	if duo == null:
		return
	if _status != null:
		_status.text = duo.status
	if _partner != null:
		if duo.connected():
			_partner.text = ("Partenaire : %s (J2)" if duo.is_host() else "Hôte : %s (J1)") % duo.partner_name
		else:
			_partner.text = ""
	if _go != null:
		_go.disabled = not duo.connected()
		_go.modulate.a = 1.0 if duo.connected() else 0.45
	if _room_l != null and duo.link != null:
		_room_l.text = "SALLE  " + String(duo.link.room)
	if _relay_box != null and String(duo.relay_state) != _relay_sig:
		_fill_internet()
	if _hosts != null and duo.disc != null:
		var sig := ",".join(duo.disc.hosts.keys())
		if sig != _hosts_sig:
			_hosts_sig = sig
			for c in _hosts.get_children():
				c.queue_free()
			if duo.disc.hosts.is_empty():
				_hosts.add_child(UI.label("Aucune pour l'instant… (même Wi-Fi ?)", 19, UI.MUTED))
			for ip in duo.disc.hosts.keys():
				var b := UI.button("%s  ·  %s" % [duo.disc.hosts[ip]["name"], ip], 24, UI.ACCENT)
				b.custom_minimum_size = Vector2(0, 76)
				b.pressed.connect(func(): duo.join_lan(String(ip)))
				_hosts.add_child(b)
