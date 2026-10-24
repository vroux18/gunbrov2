extends RefCounted
## Format des messages du mode duo. Le premier octet donne le type.
##  - HELLO, WELCOME, EV : dictionnaires (var_to_bytes), fiables, rares (salon, salle, portails, objets…).
##  - SNAP (hôte -> invité, 15 à 20 par seconde, non fiable) : instantané compact de la partie, en binaire,
##    avec les événements visuels survenus depuis le précédent (tirs, impacts, explosions, ondes, obus).
##  - INPUT (invité -> hôte, ~30 par seconde, non fiable) : position de sa Jo, sticks, état.
##  - HB : battement de cœur au salon (détecte une coupure quand rien d'autre ne passe).
## Positions en pixels entiers (int16), angles sur un octet, PV en dixièmes.

const Data = preload("res://scripts/data.gd")

const VERSION := 1
const HELLO := 1
const WELCOME := 2
const EV := 3
const SNAP := 4
const INPUT := 5
const HB := 6

## États d'ennemis connus (index sur 4 bits) ; un état inconnu passe pour « move ».
const STATES := ["move", "aim", "tell", "charge", "blink", "ring", "spiral", "idle", "dash", "spin", "burst", "warp", "summon", "rest", "lock", "fall"]

# événements visuels
const E_FIRE := 1
const E_HIT := 2
const E_BLOCK := 3
const E_SHIELD := 4
const E_BOOM := 5
const E_WAVE := 6
const E_SHELL := 7

static var _kinds: Array = []

## Genres d'ennemis, dans un ordre stable des deux côtés (même version du jeu).
static func kinds() -> Array:
	if _kinds.is_empty():
		_kinds = Data.ENEMIES.keys()
		_kinds.sort()
	return _kinds

static func kind_index(k: String) -> int:
	return maxi(0, kinds().find(k))

static func kind_name(i: int) -> String:
	var ks := kinds()
	return String(ks[i]) if i >= 0 and i < ks.size() else "drone"

# ---------------------------------------------------------------- outils
static func _buf(type: int) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.put_u8(type)
	return b

static func _pos(b: StreamPeerBuffer, v: Vector2) -> void:
	b.put_16(clampi(roundi(v.x), -32768, 32767))
	b.put_16(clampi(roundi(v.y), -32768, 32767))

static func _rpos(b: StreamPeerBuffer) -> Vector2:
	var x := b.get_16()
	var y := b.get_16()
	return Vector2(x, y)

static func _ang(v: Vector2) -> int:
	if v.length_squared() < 0.0001:
		return 64  # vers le bas
	return roundi(fposmod(v.angle(), TAU) / TAU * 256.0) % 256

static func _rang(b: StreamPeerBuffer) -> Vector2:
	return Vector2.RIGHT.rotated(b.get_u8() / 256.0 * TAU)

static func _u8(v: float) -> int:
	return clampi(roundi(v), 0, 255)

static func _u16(v: float) -> int:
	return clampi(roundi(v), 0, 65535)

static func _s8(v: float) -> int:
	return clampi(roundi(v * 127.0), -127, 127)

static func _col(b: StreamPeerBuffer, c: Color) -> void:
	b.put_u32(c.to_rgba32())

static func _rcol(b: StreamPeerBuffer) -> Color:
	return Color.hex(b.get_u32())

# ---------------------------------------------------------------- messages dictionnaires
static func dict_msg(type: int, d: Dictionary) -> PackedByteArray:
	var out := PackedByteArray([type])
	out.append_array(var_to_bytes(d))
	return out

static func read_dict(pk: PackedByteArray) -> Dictionary:
	if pk.size() < 2:
		return {}
	var v = bytes_to_var(pk.slice(1))
	return v if typeof(v) == TYPE_DICTIONARY else {}

# ---------------------------------------------------------------- héros
## h : {pos, aim, mv, dead, moving, firing, shield, choosing, hp, hp_max, invuln, revive}
static func _hero(b: StreamPeerBuffer, h: Dictionary) -> void:
	_pos(b, h["pos"])
	b.put_u8(_ang(h["aim"]))
	var mv: Vector2 = h["mv"]
	b.put_8(_s8(mv.x))
	b.put_8(_s8(mv.y))
	var f := 0
	f |= 1 if h["dead"] else 0
	f |= 2 if h["moving"] else 0
	f |= 4 if h["firing"] else 0
	f |= 8 if h["shield"] else 0
	f |= 16 if h["choosing"] else 0
	b.put_u8(f)
	b.put_u16(_u16(float(h["hp"]) * 10.0))
	b.put_u16(_u16(float(h["hp_max"]) * 10.0))
	b.put_u8(_u8(float(h["invuln"]) * 50.0))
	b.put_u8(_u8(float(h["revive"]) * 255.0))

static func _rhero(b: StreamPeerBuffer) -> Dictionary:
	var h := {}
	h["pos"] = _rpos(b)
	h["aim"] = _rang(b)
	var mx := b.get_8()
	var my := b.get_8()
	h["mv"] = Vector2(mx, my) / 127.0
	var f := b.get_u8()
	h["dead"] = f & 1 != 0
	h["moving"] = f & 2 != 0
	h["firing"] = f & 4 != 0
	h["shield"] = f & 8 != 0
	h["choosing"] = f & 16 != 0
	h["hp"] = b.get_u16() / 10.0
	h["hp_max"] = b.get_u16() / 10.0
	h["invuln"] = b.get_u8() / 50.0
	h["revive"] = b.get_u8() / 255.0
	return h

# ---------------------------------------------------------------- instantané
static func encode_snap(s: Dictionary) -> PackedByteArray:
	var b := _buf(SNAP)
	b.put_u16(int(s["seq"]) & 0xFFFF)
	b.put_u32(int(s["ms"]) & 0xFFFFFFFF)
	b.put_u8(int(s["run"]) & 0xFF)
	b.put_u8(int(s["room"]))
	b.put_u8((1 if s["cleared"] else 0) | (2 if s["boss_room"] else 0))
	b.put_u8(_u8(s["wave"]))
	b.put_u8(_u8(s["waves"]))
	b.put_u8(_u8(s["queue"]))
	b.put_u16(_u16(s["kills"]))
	b.put_u16(_u16(float(s["energy"]) * 10.0))
	b.put_u16(_u16(float(s["need"]) * 10.0))
	b.put_u16(_u16(s["ptk"]))
	_hero(b, s["heroes"][0])
	_hero(b, s["heroes"][1])
	var en: Array = s["enemies"]
	var n := mini(en.size(), 255)
	b.put_u8(n)
	for i in range(n):
		var e: Dictionary = en[i]
		b.put_u16(int(e["id"]) & 0xFFFF)
		b.put_u8(int(e["kind"]))
		b.put_u8((1 if e["elite"] else 0) | ((int(e["state"]) & 15) << 1))
		_pos(b, e["pos"])
		b.put_u8(_ang(e["facing"]))
		b.put_u8(_ang(e["aim"]))
		b.put_u8(_u8(float(e["st"]) * 50.0))
		b.put_u8(_u8(float(e["hp"]) * 255.0))
		b.put_u8(_u8(float(e["lock"]) * 100.0))
	var pk: Array = s["pickups"]
	n = mini(pk.size(), 255)
	b.put_u8(n)
	for i in range(n):
		b.put_u16(int(pk[i]["id"]) & 0xFFFF)
		b.put_u8(int(pk[i]["kind"]))
		_pos(b, pk[i]["pos"])
	var ch: Dictionary = s["chest"]
	b.put_u8(int(ch["st"]))
	_pos(b, ch["pos"])
	var tu: Array = s["turrets"]
	n = mini(tu.size(), 255)
	b.put_u8(n)
	for i in range(n):
		_pos(b, tu[i]["pos"])
		b.put_u8(_ang(Vector2.RIGHT.rotated(float(tu[i]["ang"]))))
	var ev: Array = s["events"]
	n = mini(ev.size(), 255)
	b.put_u8(n)
	for i in range(n):
		_event(b, ev[i], int(s["ms"]))
	return b.data_array

static func decode_snap(pk: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.data_array = pk
	b.seek(1)
	var s := {}
	s["seq"] = b.get_u16()
	s["ms"] = b.get_u32()
	s["run"] = b.get_u8()
	s["room"] = b.get_u8()
	var f := b.get_u8()
	s["cleared"] = f & 1 != 0
	s["boss_room"] = f & 2 != 0
	s["wave"] = b.get_u8()
	s["waves"] = b.get_u8()
	s["queue"] = b.get_u8()
	s["kills"] = b.get_u16()
	s["energy"] = b.get_u16() / 10.0
	s["need"] = b.get_u16() / 10.0
	s["ptk"] = b.get_u16()
	s["heroes"] = [_rhero(b), _rhero(b)]
	var en := []
	for i in range(b.get_u8()):
		var e := {}
		e["id"] = b.get_u16()
		e["kind"] = b.get_u8()
		var ef := b.get_u8()
		e["elite"] = ef & 1 != 0
		e["state"] = (ef >> 1) & 15
		e["pos"] = _rpos(b)
		e["facing"] = _rang(b)
		e["aim"] = _rang(b)
		e["st"] = b.get_u8() / 50.0
		e["hp"] = b.get_u8() / 255.0
		e["lock"] = b.get_u8() / 100.0
		en.append(e)
	s["enemies"] = en
	var pks := []
	for i in range(b.get_u8()):
		var id := b.get_u16()
		var k := b.get_u8()
		pks.append({"id": id, "kind": k, "pos": _rpos(b)})
	s["pickups"] = pks
	var cst := b.get_u8()
	s["chest"] = {"st": cst, "pos": _rpos(b)}
	var tus := []
	for i in range(b.get_u8()):
		var p := _rpos(b)
		tus.append({"pos": p, "ang": _rang(b).angle()})
	s["turrets"] = tus
	var evs := []
	var ms: int = s["ms"]
	for i in range(b.get_u8()):
		evs.append(_revent(b, ms))
	s["events"] = evs
	return s

# ---------------------------------------------------------------- événements visuels
## e : {k, ms, ...} ; l'âge (ms de l'instantané - ms de l'événement) tient sur un octet, par pas de 4 ms.
static func _event(b: StreamPeerBuffer, e: Dictionary, snap_ms: int) -> void:
	var k: int = e["k"]
	b.put_u8(k)
	b.put_u8(_u8((snap_ms - int(e["ms"])) / 4.0))
	match k:
		E_FIRE:
			_pos(b, e["pos"])
			_pos(b, e["vel"])
			_col(b, e["col"])
			b.put_u8(_u8(float(e["r"]) * 10.0))
			b.put_u8((1 if e["hero"] else 0))
			b.put_u8(int(e["bounce"]))
			b.put_u8(int(e["pierce"]))
		E_HIT:
			b.put_u16(int(e["id"]) & 0xFFFF)
			_pos(b, e["pos"])
			b.put_u16(_u16(e["dmg"]))
			b.put_u8(1 if e["crit"] else 0)
		E_BLOCK:
			_pos(b, e["pos"])
			_col(b, e["col"])
		E_SHIELD:
			b.put_u16(int(e["id"]) & 0xFFFF)
			_pos(b, e["pos"])
			_pos(b, e["vel"])
		E_BOOM:
			_pos(b, e["pos"])
			b.put_u16(_u16(e["r"]))
			_col(b, e["col"])
		E_WAVE:
			_pos(b, e["pos"])
			b.put_u16(_u16(e["max"]))
			b.put_u16(_u16(e["spd"]))
			_col(b, e["col"])
		E_SHELL:
			_pos(b, e["from"])
			_pos(b, e["to"])
			b.put_u16(_u16(float(e["flight"]) * 1000.0))
			b.put_u16(_u16(e["r"]))

static func _revent(b: StreamPeerBuffer, snap_ms: int) -> Dictionary:
	var e := {}
	var k := b.get_u8()
	e["k"] = k
	e["ms"] = snap_ms - b.get_u8() * 4
	match k:
		E_FIRE:
			e["pos"] = _rpos(b)
			e["vel"] = _rpos(b)
			e["col"] = _rcol(b)
			e["r"] = b.get_u8() / 10.0
			e["hero"] = b.get_u8() != 0
			e["bounce"] = b.get_u8()
			e["pierce"] = b.get_u8()
		E_HIT:
			e["id"] = b.get_u16()
			e["pos"] = _rpos(b)
			e["dmg"] = b.get_u16()
			e["crit"] = b.get_u8() != 0
		E_BLOCK:
			e["pos"] = _rpos(b)
			e["col"] = _rcol(b)
		E_SHIELD:
			e["id"] = b.get_u16()
			e["pos"] = _rpos(b)
			e["vel"] = _rpos(b)
		E_BOOM:
			e["pos"] = _rpos(b)
			e["r"] = b.get_u16()
			e["col"] = _rcol(b)
		E_WAVE:
			e["pos"] = _rpos(b)
			e["max"] = b.get_u16()
			e["spd"] = b.get_u16()
			e["col"] = _rcol(b)
		E_SHELL:
			e["from"] = _rpos(b)
			e["to"] = _rpos(b)
			e["flight"] = b.get_u16() / 1000.0
			e["r"] = b.get_u16()
	return e

# ---------------------------------------------------------------- entrées de l'invité
## i : {seq, pos, mv, aim, aim_on, choosing}
static func encode_input(i: Dictionary) -> PackedByteArray:
	var b := _buf(INPUT)
	b.put_u16(int(i["seq"]) & 0xFFFF)
	_pos(b, i["pos"])
	var mv: Vector2 = i["mv"]
	var am: Vector2 = i["aim"]
	b.put_8(_s8(mv.x))
	b.put_8(_s8(mv.y))
	b.put_8(_s8(am.x))
	b.put_8(_s8(am.y))
	b.put_u8((1 if i["aim_on"] else 0) | (2 if i["choosing"] else 0) | (4 if i.get("dodge", false) else 0))
	return b.data_array

static func decode_input(pk: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.data_array = pk
	b.seek(1)
	var i := {}
	i["seq"] = b.get_u16()
	i["pos"] = _rpos(b)
	var mx := b.get_8()
	var my := b.get_8()
	var ax := b.get_8()
	var ay := b.get_8()
	i["mv"] = Vector2(mx, my) / 127.0
	i["aim"] = Vector2(ax, ay) / 127.0
	var f := b.get_u8()
	i["aim_on"] = f & 1 != 0
	i["choosing"] = f & 2 != 0
	i["dodge"] = f & 4 != 0  # ruée en cours : invulnérable
	return i
