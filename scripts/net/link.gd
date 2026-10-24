extends RefCounted
## Lien réseau du mode duo, deux transports derrière la même interface :
##  - réseau local : ENetMultiplayerPeer (UDP), utilisé comme simple tuyau à paquets (pas de RPC, pas de
##    SceneMultiplayer) : l'hôte écoute, l'invité se connecte à son adresse ;
##  - Internet : WebSocketPeer vers le relais Cloudflare (server/relay), qui fait suivre les messages binaires
##    d'un joueur à l'autre dans une salle à code de 4 lettres.
## On interroge le lien à chaque image (poll) ; il compte les octets dans les deux sens pour mesurer le débit.

const PORT := 47810

var kind := ""  # "lan" | "relay"
var is_host := false
var state := "idle"  # idle | connecting | open | closed
var peer_on := false  # le partenaire est là
var error := ""  # raison de la fermeture, lisible
var room := ""  # code de salle (relais)
var bytes_out := 0
var bytes_in := 0
var pkts_out := 0
var pkts_in := 0

var _enet: ENetMultiplayerPeer = null
var _ws: WebSocketPeer = null
var _t0 := 0
var _ping_t := 0.0
var _peer_id := 0
var timeout_ms := 10000  # coupure déclarée après ce silence (essais sous xvfb : --duo-timeout=S)

# ---------------------------------------------------------------- ouverture
func host_lan(port: int = PORT) -> bool:
	kind = "lan"
	is_host = true
	_enet = ENetMultiplayerPeer.new()
	var err := _enet.create_server(port, 1)
	if err != OK:
		_fail("port %d déjà pris (une autre partie ouverte ?)" % port)
		return false
	_enet.peer_connected.connect(func(id: int):
		_peer_id = id
		_tune_peer(id)
		peer_on = true)
	_enet.peer_disconnected.connect(func(_id: int):
		peer_on = false
		_peer_id = 0)
	state = "open"
	return true

func join_lan(ip: String, port: int = PORT) -> bool:
	kind = "lan"
	is_host = false
	_enet = ENetMultiplayerPeer.new()
	var err := _enet.create_client(ip, port)
	if err != OK:
		_fail("adresse invalide : " + ip)
		return false
	_enet.peer_connected.connect(func(id: int):
		if id == 1:
			_peer_id = 1
			_tune_peer(1)
			state = "open"
			peer_on = true)
	_enet.peer_disconnected.connect(func(id: int):
		if id == 1:
			peer_on = false
			_fail("l'hôte s'est déconnecté"))
	state = "connecting"
	_t0 = Time.get_ticks_msec()
	return true

## Relais : `base` = ws(s)://hôte[:port], `code` = 4 lettres. L'hôte crée la salle, l'invité la rejoint.
func open_relay(base: String, code: String, as_host: bool) -> bool:
	kind = "relay"
	is_host = as_host
	room = code.to_upper()
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 18
	_ws.outbound_buffer_size = 1 << 18
	var url := base.strip_edges().trim_suffix("/") + "/room/" + room + "?role=" + ("host" if as_host else "guest")
	var err := _ws.connect_to_url(url)
	if err != OK:
		_fail("relais injoignable")
		return false
	state = "connecting"
	_t0 = Time.get_ticks_msec()
	return true

## Délai de détection d'une coupure : quelques secondes plutôt que les 30 s par défaut d'ENet.
func _tune_peer(id: int) -> void:
	var p := _enet.get_peer(id)
	if p != null:
		p.set_timeout(0, mini(3000, timeout_ms), timeout_ms)

func _fail(why: String) -> void:
	if state != "closed":
		error = why
	state = "closed"
	peer_on = false

# ---------------------------------------------------------------- boucle
## Reçoit tout ce qui est arrivé : renvoie la liste des paquets de jeu.
func poll(dt: float) -> Array:
	var out: Array = []
	if _enet != null:
		_enet.poll()
		if state == "connecting" and Time.get_ticks_msec() - _t0 > maxi(7000, timeout_ms):
			_fail("pas de réponse de l'hôte (même Wi-Fi ? bonne adresse ?)")
			close()
			return out
		while _enet.get_available_packet_count() > 0:
			var pk := _enet.get_packet()
			bytes_in += pk.size() + 40  # en-têtes IP, UDP et ENet (estimés)
			pkts_in += 1
			out.append(pk)
	elif _ws != null:
		_ws.poll()
		var st := _ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			_ping_t -= dt
			if _ping_t <= 0.0:
				_ping_t = 5.0
				_ws.send_text("ping")
			while _ws.get_available_packet_count() > 0:
				var pk := _ws.get_packet()
				bytes_in += pk.size() + 6
				pkts_in += 1
				if _ws.was_string_packet():
					_control(pk.get_string_from_utf8())
				else:
					out.append(pk)
		elif st == WebSocketPeer.STATE_CLOSED:
			if state != "closed":
				var why := error
				if why == "":
					var code := _ws.get_close_code()
					if code == 4000:
						why = "l'hôte a quitté la salle"
					elif state == "connecting":
						why = "relais injoignable"
					else:
						why = "connexion au relais perdue"
				_fail(why)
		elif state == "connecting" and Time.get_ticks_msec() - _t0 > 10000:
			_fail("relais injoignable (délai dépassé)")
			_ws.close()
	return out

## Messages texte du relais : bienvenue, arrivée ou départ du partenaire, refus.
func _control(txt: String) -> void:
	if txt == "pong":
		return
	var m = JSON.parse_string(txt)
	if typeof(m) != TYPE_DICTIONARY:
		return
	match String(m.get("t", "")):
		"hello":
			state = "open"
			room = String(m.get("code", room))
			peer_on = bool(m.get("peer", false))
		"peer":
			peer_on = bool(m.get("on", false))
			if not peer_on and not is_host:
				error = "l'hôte a quitté la salle"
		"err":
			var why := String(m.get("why", ""))
			error = {"occupied": "code déjà pris", "no_room": "aucune salle avec ce code", "full": "salle pleine"}.get(why, why)
			state = "closed"

# ---------------------------------------------------------------- envoi
func send(data: PackedByteArray, reliable: bool) -> void:
	if state != "open" or not peer_on:
		return
	if _enet != null:
		_enet.set_target_peer(_peer_id if is_host else 1)
		_enet.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
		_enet.put_packet(data)
		bytes_out += data.size() + 40
	elif _ws != null:
		_ws.send(data, WebSocketPeer.WRITE_MODE_BINARY)
		bytes_out += data.size() + 6
	pkts_out += 1

func close() -> void:
	if _enet != null:
		_enet.close()
		_enet = null
	if _ws != null:
		_ws.close(1000, "bye")
		_ws.poll()
		_ws = null
	if state != "closed":
		state = "closed"
	peer_on = false
