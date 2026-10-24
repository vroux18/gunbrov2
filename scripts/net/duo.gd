extends Node
## Mode duo coopératif (2 joueurs, 2 téléphones). Session : salon, connexion, poignée de main, lancement,
## fin de partie, coupures. La partie elle-même est simulée chez l'hôte (duo_host.gd) et rejouée chez
## l'invité (duo_guest.gd).
##
## Deux façons de se connecter (link.gd) :
##  - réseau local, sans serveur : l'hôte annonce sa partie par diffusion UDP (discovery.gd), l'invité la voit
##    dans la liste ou tape l'adresse IP de l'hôte ;
##  - Internet : relais Cloudflare (server/relay), salle à code de 4 lettres. L'adresse du relais est publiée
##    par le workflow deploy-relay.yml dans relay.txt (release « relay » du dépôt).
##
## Options de ligne de commande (essais à deux instances sur la même machine) :
##   --duo-host                      héberger (réseau local, ou relais avec --duo-relay)
##   --duo-join=127.0.0.1 | auto     rejoindre une adresse, ou le premier hôte entendu
##   --duo-relay=ws://127.0.0.1:8787 passer par ce relais ; --duo-room=ABCD code de salle
##   --duo-shots=DOSSIER             captures d'écran toutes les 3 s (rôle_temps.png)
##   --duo-down-at=S                 (hôte) met la Jo de l'invité à terre à S s de partie, pour tester la relève
##   --duo-quit-at=S                 quitte brutalement à S s de partie, pour tester la coupure
##   --duo-name=NOM                  nom affiché au partenaire

const Link = preload("res://scripts/net/link.gd")
const Discovery = preload("res://scripts/net/discovery.gd")
const Proto = preload("res://scripts/net/proto.gd")
const HostSync = preload("res://scripts/net/duo_host.gd")
const GuestSync = preload("res://scripts/net/duo_guest.gd")
const Lobby = preload("res://scripts/net/duo_lobby.gd")
const Save = preload("res://scripts/save.gd")
const UI = preload("res://scripts/ui.gd")

const RELAY_TXT := "https://github.com/vroux18/gunbrov2/releases/download/relay/relay.txt"
const RELAY_CACHE := "user://duo_relay.txt"
var lost_ms := 10000  # plus rien reçu du partenaire depuis : coupure (--duo-timeout=S pour les essais lents)

var main: Node
var link = null  # link.gd
var disc = null  # discovery.gd
var role := ""  # "" | "host" | "guest"
var phase := "off"  # off | lobby | run
var handshake := false  # partenaire accueilli (HELLO / WELCOME échangés)
var status := ""  # état lisible pour le salon
var my_name := ""
var partner_name := ""
var partner_items: Array = []
var partner_talents := {}  # talents permanents de l'invité (talents.gd), appliqués à sa Jo chez l'hôte
var world_override := -1
var run_id := 0
var relay_url := ""  # ws(s)://… ; vide : inconnu ; "-" : serveur non déployé
var relay_state := "idle"  # idle | fetching | ok | none
var lobby: Control = null
var sync: Node = null  # duo_host.gd ou duo_guest.gd pendant une partie
var start_info := {}  # invité : message « start » reçu

var _args: PackedStringArray
var _autoplay := false
var _last_rx := 0
var _hb_t := 0.0
var _starting := false
var _remote_end := false
var _auto_go_t := -1.0
var _bw_t := 0.0
var _bw_out := 0
var _bw_in := 0
var _po := 0
var _pi := 0
var _shots_dir := ""
var _shot_t := 0.0
var _run_t := 0.0
var _items_wait: Array = []
var _ev_wait: Array = []
var energy_wait := false  # invité : choix de pouvoir arrivé pendant un autre écran
var _http: HTTPRequest = null
var bw_log: Array = []  # débits mesurés (ko/s montant, descendant), pour le rapport

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_args = OS.get_cmdline_user_args()
	_autoplay = "--autoplay" in _args
	my_name = OS.get_model_name()
	if my_name == "" or my_name == "GenericDevice":
		my_name = "Passeur"
	for a in _args:
		if a.begins_with("--duo-name="):
			my_name = a.trim_prefix("--duo-name=")
		if a.begins_with("--duo-shots="):
			_shots_dir = a.trim_prefix("--duo-shots=")
			DirAccess.make_dir_recursive_absolute(_shots_dir)
		if a.begins_with("--duo-timeout="):
			lost_ms = int(float(a.trim_prefix("--duo-timeout=")) * 1000.0)
		if a.begins_with("--duo-relay="):
			relay_url = a.trim_prefix("--duo-relay=")
			relay_state = "ok"
	_cmdline_start.call_deferred()

func _arg(prefix: String) -> String:
	for a in _args:
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""

## Démarrage automatique depuis la ligne de commande (essais sans téléphone).
func _cmdline_start() -> void:
	var room := _arg("--duo-room=").to_upper()
	if "--duo-host" in _args:
		if relay_url != "":
			host_relay(room)
		else:
			host_lan()
		open_lobby()
	elif _arg("--duo-join=") != "":
		join_lan(_arg("--duo-join="))
		open_lobby()
	elif relay_url != "" and room != "":
		join_relay(room)
		open_lobby()
	elif _arg("--duo-screen=") != "":
		# captures : un écran du salon (menu, internet)
		open_lobby()
		lobby.mode = _arg("--duo-screen=")
		if lobby.mode == "internet":
			fetch_relay()
		lobby.rebuild()

# ---------------------------------------------------------------- état
func active() -> bool:
	return link != null

func connected() -> bool:
	return link != null and link.state == "open" and link.peer_on and handshake

func in_run() -> bool:
	return phase == "run"

func is_host() -> bool:
	return role == "host"

func is_guest() -> bool:
	return role == "guest"

# ---------------------------------------------------------------- salon
## Bouton DUO du Relais : écran HÉBERGER / REJOINDRE / INTERNET.
func open_lobby() -> void:
	if main.state != "base" and main.state != "duo":
		return
	main._clear_screen()
	main.state = "duo"
	if phase != "run":
		phase = "lobby"
	lobby = Lobby.new()
	lobby.duo = self
	lobby.main = main
	main.screen = lobby
	main.ui_layer.add_child(lobby)
	if link != null:
		lobby.mode = "relay_room" if link.kind == "relay" else ("host_lan" if is_host() else "join_lan")
	elif is_guest():
		lobby.mode = "join_lan"
	lobby.rebuild()

## RETOUR du salon : coupe tout et revient au Relais.
func leave() -> void:
	shutdown()
	lobby = null
	main.show_base()

func shutdown() -> void:
	if link != null:
		if connected():
			link.send(Proto.dict_msg(Proto.EV, {"t": "bye"}), true)
			link.poll(0.0)
		link.close()
	link = null
	if disc != null:
		disc.stop()
	disc = null
	role = ""
	handshake = false
	partner_name = ""
	phase = "off"
	_ev_wait.clear()
	energy_wait = false
	world_override = -1
	_end_sync()

func host_lan() -> void:
	shutdown()
	phase = "lobby"
	role = "host"
	link = _new_link()
	if link.host_lan():
		disc = Discovery.new()
		disc.announce(my_name, Link.PORT)
		status = "En attente d'un partenaire…"
	else:
		status = link.error
	_last_rx = Time.get_ticks_msec()

## Rejoindre une adresse ; « auto » : le premier hôte entendu sur le réseau local.
func join_lan(ip: String) -> void:
	shutdown()
	phase = "lobby"
	role = "guest"
	if ip == "auto" or ip == "":
		listen_lan()
		_auto_join = true
		return
	link = _new_link()
	link.join_lan(ip)
	status = "Connexion à %s…" % ip
	_last_rx = Time.get_ticks_msec()

var _auto_join := false

## Écoute les annonces des hôtes (liste du salon REJOINDRE).
func listen_lan() -> void:
	if disc == null:
		disc = Discovery.new()
	if not disc.listen():
		status = "Écoute impossible (port %d pris)" % Discovery.PORT
	else:
		status = "Recherche des parties sur le réseau…"

func host_relay(code: String = "") -> void:
	if relay_url == "" or relay_url == "-":
		status = "Serveur non déployé"
		return
	shutdown()
	phase = "lobby"
	role = "host"
	if code.length() != 4:
		code = random_code()
	link = _new_link()
	link.open_relay(relay_url, code, true)
	status = "Création de la salle…"
	_last_rx = Time.get_ticks_msec()

func join_relay(code: String) -> void:
	if relay_url == "" or relay_url == "-":
		status = "Serveur non déployé"
		return
	shutdown()
	phase = "lobby"
	role = "guest"
	link = _new_link()
	link.open_relay(relay_url, code.to_upper(), false)
	status = "Connexion à la salle %s…" % code.to_upper()
	_last_rx = Time.get_ticks_msec()

func _new_link():
	var l = Link.new()
	l.timeout_ms = lost_ms
	return l

static func random_code() -> String:
	var letters := "ABCDEFGHJKLMNPQRSTUVWXYZ"  # sans I ni O
	var s := ""
	for i in range(4):
		s += letters[randi() % letters.length()]
	return s

## Adresse du relais : publiée par le workflow dans relay.txt ; gardée en cache si le réseau manque.
func fetch_relay() -> void:
	if relay_state == "fetching" or relay_state == "ok":
		return
	relay_state = "fetching"
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 8.0
		add_child(_http)
		_http.request_completed.connect(_on_relay_txt)
	if _http.request(RELAY_TXT) != OK:
		_on_relay_txt(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())

func _on_relay_txt(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var url := ""
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		url = body.get_string_from_utf8().strip_edges()
		if url.begins_with("https://"):
			url = "wss://" + url.trim_prefix("https://")
		elif url.begins_with("http://"):
			url = "ws://" + url.trim_prefix("http://")
		if not (url.begins_with("wss://") or url.begins_with("ws://")):
			url = ""
		if url != "":
			var f := FileAccess.open(RELAY_CACHE, FileAccess.WRITE)
			if f != null:
				f.store_string(url)
	elif result != HTTPRequest.RESULT_SUCCESS and FileAccess.file_exists(RELAY_CACHE):
		# pas de réseau pour GitHub : dernière adresse connue
		url = FileAccess.get_file_as_string(RELAY_CACHE).strip_edges()
	if url != "":
		relay_url = url
		relay_state = "ok"
	else:
		relay_url = "-"
		relay_state = "none"
		print("DUO : relais introuvable (%d, HTTP %d) : serveur non déployé" % [result, code])

## Hôte : PARTIR ensemble.
func go() -> void:
	if not is_host() or not connected() or phase == "run":
		return
	main.state = "base"
	main._depart()

## main._depart() : en duo, seul l'hôte lance ; l'invité attend le signal de l'hôte.
func intercept_depart() -> bool:
	if not connected():
		return false
	if _starting:
		return false
	_freeze_lobby()
	if is_host():
		run_id = (run_id + 1) % 256
		world_override = -1
		world_override = main._chosen_world()  # le monde choisi au Relais de l'hôte
		link.send(Proto.dict_msg(Proto.EV, {"t": "start", "world": world_override, "run": run_id, "items": main.hero.items, "name": my_name}), true)
		phase = "run"
		return false
	return true

## Départ lancé : le salon s'efface (fondu de main._depart) et ne répond plus.
func _freeze_lobby() -> void:
	if lobby != null and is_instance_valid(lobby):
		for b in lobby.find_children("*", "BaseButton", true, false):
			(b as BaseButton).disabled = true
		lobby.set_process(false)

## main.start_run() vient de démarrer la partie : on branche la simulation duo.
func on_run_started() -> void:
	if not connected():
		phase = "off" if link == null else "lobby"
		return
	phase = "run"
	_run_t = 0.0
	_remote_end = false
	_end_sync()
	if is_host():
		sync = HostSync.new()
	else:
		sync = GuestSync.new()
	sync.duo = self
	sync.main = main
	add_child(sync)
	sync.begin()
	for d in _ev_wait:
		sync.on_ev(d)
	_ev_wait.clear()
	energy_wait = false
	if is_guest():
		send_ev({"t": "ready"})
	print("DUO : partie lancée (%s, monde %d, partie %d)" % [role, world_override + 1, run_id])

func _end_sync() -> void:
	if sync != null:
		sync.end()
		sync.queue_free()
		sync = null

## Fin de partie locale (K.O., victoire, abandon) : prévient le partenaire.
func on_show_end(won: bool, title: String, subtitle: String) -> void:
	if not in_run():
		return
	if _remote_end:
		return
	if is_host():
		var a: Node = main.arena
		send_ev({"t": "over", "won": won, "title": title, "sub": subtitle, "room": a.room, "kills": a.kills})
	else:
		# l'invité abandonne : il quitte la session, l'hôte rentre au Relais
		send_ev({"t": "quit"})
	_end_sync()
	if not is_host():
		_drop_after_end = true

var _drop_after_end := false

## main._end_run() : retour au Relais ; si le partenaire est toujours là, on revient au salon.
func after_run() -> void:
	if phase != "run" and phase != "lobby":
		return
	_end_sync()
	if _drop_after_end:
		_drop_after_end = false
		shutdown()
		return
	phase = "lobby"
	_ev_wait.clear()
	energy_wait = false
	world_override = -1
	if connected():
		open_lobby.call_deferred()

## main._on_hero_died() en duo : vrai si la session prend la main (le partenaire peut relever).
func on_local_down() -> void:
	if sync != null:
		sync.local_down()

## main._show_item() : un objet arrivé pendant un autre écran attend qu'il se ferme.
func defer_item(item: Dictionary) -> bool:
	if in_run() and main.overlay != null:
		_items_wait.append(item)
		return true
	return false

func send_ev(d: Dictionary) -> void:
	if link != null:
		link.send(Proto.dict_msg(Proto.EV, d), true)

func send_raw(pk: PackedByteArray, reliable: bool) -> void:
	if link != null:
		link.send(pk, reliable)

## Bandeau de message au Relais (coupure, refus…).
func toast(msg: String, col: Color = UI.DANGER) -> void:
	var l := UI.label(msg, 26, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08))
	l.add_theme_constant_override("outline_size", 10)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.flat(Color(col.darkened(0.6), 0.92), col, 16, 3))
	p.add_child(l)
	p.anchor_left = 0.15
	p.anchor_right = 0.85
	p.anchor_top = 0.04
	p.offset_bottom = 70
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.ui_layer.add_child(p)
	var tw := p.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)
	print("DUO : " + msg)

# ---------------------------------------------------------------- boucle
func _process(dt: float) -> void:
	if disc != null:
		disc.poll(dt)
		if _auto_join and link == null and not disc.hosts.is_empty():
			_auto_join = false
			var ip: String = disc.hosts.keys()[0]
			print("DUO : hôte trouvé par diffusion : %s (%s)" % [ip, disc.hosts[ip]["name"]])
			join_lan(ip)
	if link == null:
		return
	var now := Time.get_ticks_msec()
	var was_on: bool = link.peer_on
	for pk in link.poll(dt):
		_last_rx = now
		_receive(pk)
	if link == null:
		return
	# arrivée / départ du partenaire
	if link.state == "open" and link.peer_on and not was_on:
		_last_rx = now
		if is_guest():
			send_raw(Proto.dict_msg(Proto.HELLO, {"v": Proto.VERSION, "game": main.version, "name": my_name, "items": main.hero.items, "talents": main.profile.get("talents", {})}), true)
			status = "Connecté, poignée de main…"
		else:
			status = "Partenaire en approche…"
	if link.kind == "relay" and link.state == "open" and is_host() and not link.peer_on:
		status = "Salle %s ouverte : en attente d'un partenaire…" % link.room
	if link.state == "closed" or (was_on and not link.peer_on) or (handshake and now - _last_rx > lost_ms):
		var why: String = link.error
		if why == "":
			why = "plus de nouvelles du partenaire" if handshake else "connexion impossible"
		if was_on and not link.peer_on and is_host() and link.state == "open":
			why = "le partenaire s'est déconnecté"
		_lost(why)
		return
	# battement au salon (en partie, instantanés et entrées suffisent)
	if connected() and not in_run():
		_hb_t -= dt
		if _hb_t <= 0.0:
			_hb_t = 1.0
			send_raw(PackedByteArray([Proto.HB]), false)
	if _auto_go_t >= 0.0:
		_auto_go_t -= dt
		if _auto_go_t < 0.0:
			go()
	# objets en attente d'un écran libre
	if in_run() and not _items_wait.is_empty() and main.overlay == null and main.state == "arena":
		main._show_item(_items_wait.pop_front())
	if in_run() and energy_wait and main.overlay == null and main.state == "arena":
		energy_wait = false
		main._show_power_choice()
	_tick_tests(dt)
	_tick_bandwidth(dt)

func _receive(pk: PackedByteArray) -> void:
	if pk.is_empty():
		return
	match pk[0]:
		Proto.SNAP:
			if sync != null and is_guest():
				sync.on_snap(Proto.decode_snap(pk))
		Proto.INPUT:
			if sync != null and is_host():
				sync.on_input(Proto.decode_input(pk))
		Proto.HELLO:
			var d := Proto.read_dict(pk)
			if is_host():
				if int(d.get("v", 0)) != Proto.VERSION or String(d.get("game", "")) != String(main.version):
					send_raw(Proto.dict_msg(Proto.WELCOME, {"ok": false, "why": "versions différentes (hôte %s)" % main.version}), true)
					status = "Partenaire refusé : versions différentes (%s / %s)" % [main.version, d.get("game", "?")]
					return
				partner_name = String(d.get("name", "J2"))
				partner_items = d.get("items", [])
				partner_talents = d.get("talents", {})
				handshake = true
				send_raw(Proto.dict_msg(Proto.WELCOME, {"ok": true, "name": my_name, "items": main.hero.items}), true)
				status = "%s est connecté" % partner_name
				print("DUO : partenaire connecté (%s) via %s" % [partner_name, link.kind])
				if disc != null:
					disc.stop()
				if _autoplay:
					_auto_go_t = 1.5
		Proto.WELCOME:
			var d := Proto.read_dict(pk)
			if not bool(d.get("ok", false)):
				_lost(String(d.get("why", "refusé par l'hôte")))
				return
			partner_name = String(d.get("name", "J1"))
			partner_items = d.get("items", [])
			handshake = true
			status = "Connecté à %s. L'hôte lance la partie." % partner_name
			print("DUO : connecté à l'hôte (%s) via %s" % [partner_name, link.kind])
			if disc != null:
				disc.stop()
		Proto.EV:
			_on_ev(Proto.read_dict(pk))
		Proto.HB:
			pass

func _on_ev(d: Dictionary) -> void:
	var t := String(d.get("t", ""))
	match t:
		"start":
			if not is_guest():
				return
			start_info = d
			world_override = int(d.get("world", 0))
			run_id = int(d.get("run", 0))
			partner_items = d.get("items", partner_items)
			if main.state == "arena" or main.overlay != null:
				main._end_run(false)
			_starting = true
			main.state = "base"
			phase = "run"
			main._depart()
			_starting = false
		"bye":
			_lost("le partenaire a quitté le salon")
		"quit":
			if is_host() and in_run():
				_lost("J2 a abandonné la partie")
		"over":
			if is_guest() and in_run() and sync != null:
				_remote_end = true
				sync.remote_over(d)
		_:
			if sync != null:
				sync.on_ev(d)
			elif in_run():
				_ev_wait.append(d)  # la partie démarre encore de ce côté : rejoué dès qu'elle est prête

## Coupure : retour au Relais avec un message (le butin de la partie en cours est gardé).
func _lost(why: String) -> void:
	var was_run := in_run()
	print("DUO : coupure (%s)" % why)
	_end_sync()
	if link != null:
		link.close()
	link = null
	if disc != null:
		disc.stop()
	disc = null
	handshake = false
	role = ""
	phase = "off"
	world_override = -1
	_auto_join = false
	status = "Connexion perdue : " + why
	if was_run and (main.state == "arena" or main.overlay != null):
		main._end_run(false)
		toast("Partie interrompue : " + why)
	elif main.state == "duo":
		if lobby != null and is_instance_valid(lobby):
			lobby.mode = "menu"
			lobby.rebuild()
		toast(why)
	else:
		toast(why)

# ---------------------------------------------------------------- mesures, essais
func _tick_bandwidth(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	if _bw_t <= 0.0:
		_bw_t = now
	if now - _bw_t < 5000.0 or link == null:
		return
	var span := (now - _bw_t) / 1000.0
	var o: int = link.bytes_out - _bw_out
	var i: int = link.bytes_in - _bw_in
	var po: int = link.pkts_out - _po
	var pi: int = link.pkts_in - _pi
	_bw_out = link.bytes_out
	_bw_in = link.bytes_in
	_po = link.pkts_out
	_pi = link.pkts_in
	var ko_o := o / 1024.0 / span
	var ko_i := i / 1024.0 / span
	if in_run():
		bw_log.append([ko_o, ko_i])
		var jit := ""
		if is_guest() and sync != null and not sync.late_ms.is_empty():
			# gigue : retard de chaque instantané sur le plus rapide (le tampon d'interpolation doit la couvrir)
			var lm: Array = sync.late_ms.duplicate()
			lm.sort()
			jit = ", gigue médiane %.0f ms, 95 %% %.0f ms (tampon %.0f ms)" % [lm[lm.size() / 2], lm[int(lm.size() * 0.95)], sync.delay_ms]
		print("NET : %s %s, montant %.1f ko/s, descendant %.1f ko/s, paquets %.0f/%.0f par s, ennemis %d%s" % [role, link.kind, ko_o, ko_i, po / span, pi / span, main.arena.enemies.size(), jit])
	_bw_t = now

func _tick_tests(dt: float) -> void:
	if in_run():
		_run_t += dt
	var q := _arg("--duo-quit-at=")
	if q != "" and in_run() and _run_t >= float(q):
		print("DUO : essai de coupure, fin brutale du processus")
		get_tree().quit()
	if _shots_dir != "" and DisplayServer.get_name() != "headless":
		# toutes les 3 s d'horloge murale, nommées par l'heure : les captures des deux instances s'apparient
		var now := Time.get_unix_time_from_system()
		if now - _shot_t >= 3.0:
			_shot_t = now
			var img := get_viewport().get_texture().get_image()
			if img != null:
				img.save_png("%s/%s_%d.png" % [_shots_dir, role if role != "" else "solo", int(now)])

## Robot (--autoplay) : où aller en duo (relever le partenaire, ne pas trop s'éloigner). Vector2.INF : libre.
func bot_goal(me: Node2D) -> Vector2:
	if sync == null:
		return Vector2.INF
	return sync.bot_goal(me)
