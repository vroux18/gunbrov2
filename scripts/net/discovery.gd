extends RefCounted
## Découverte des parties sur le réseau local : l'hôte annonce sa partie par diffusion UDP chaque seconde,
## l'invité écoute et liste les hôtes entendus (adresse, nom). Marche sur un même Wi-Fi et sur un partage de
## connexion (le téléphone qui partage est en général 192.168.43.1 ou 10.x.x.1).
## Sur Android, activer la diffusion prend un verrou multicast (permission CHANGE_WIFI_MULTICAST_STATE) :
## sans lui, beaucoup de téléphones jettent les paquets diffusés reçus.

const PORT := 47811
const MAGIC := "PASSEURS1"

var _udp: PacketPeerUDP = null
var _announce := ""
var _t := 0.0
var hosts := {}  # ip -> {name, port, seen (ms)}

## Hôte : annonce `name` (et le port de la partie) jusqu'à stop().
func announce(name: String, game_port: int) -> void:
	stop()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_udp.bind(0)
	_announce = "%s|%s|%d" % [MAGIC, name.replace("|", " "), game_port]
	_t = 0.0

## Invité : écoute les annonces.
func listen() -> bool:
	stop()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	var err := _udp.bind(PORT, "0.0.0.0")
	if err != OK:
		_udp = null
		return false
	return true

func stop() -> void:
	if _udp != null:
		_udp.close()
		_udp = null
	_announce = ""
	hosts.clear()

func poll(dt: float) -> void:
	if _udp == null:
		return
	if _announce != "":
		_t -= dt
		if _t <= 0.0:
			_t = 1.0
			var pk := _announce.to_utf8_buffer()
			for addr in broadcast_targets():
				_udp.set_dest_address(addr, PORT)
				_udp.put_packet(pk)
		return
	while _udp.get_available_packet_count() > 0:
		var pk := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var parts := pk.get_string_from_utf8().split("|")
		if parts.size() == 3 and parts[0] == MAGIC and ip != "":
			hosts[ip] = {"name": parts[1], "port": int(parts[2]), "seen": Time.get_ticks_msec()}
	var now := Time.get_ticks_msec()
	for ip in hosts.keys():
		if now - int(hosts[ip]["seen"]) > 4000:
			hosts.erase(ip)

## Adresses de diffusion : générale, celle de chaque réseau /24 de l'appareil, et la boucle locale (essais à
## deux instances sur la même machine).
static func broadcast_targets() -> Array:
	var out := ["255.255.255.255", "127.0.0.1"]
	for a in local_ipv4():
		var p := String(a).split(".")
		var b := "%s.%s.%s.255" % [p[0], p[1], p[2]]
		if not b in out:
			out.append(b)
	return out

## Adresses IPv4 de l'appareil sur le réseau local (à donner à l'autre joueur en secours).
static func local_ipv4() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.count(".") != 3 or s.begins_with("127.") or s.begins_with("169.254."):
			continue
		out.append(s)
	# les adresses privées d'abord (Wi-Fi, partage de connexion)
	out.sort_custom(func(x, y): return _rank(x) < _rank(y))
	return out

static func _rank(s: String) -> int:
	if s.begins_with("192.168."):
		return 0
	if s.begins_with("10."):
		return 1
	if s.begins_with("172."):
		return 2
	return 3
