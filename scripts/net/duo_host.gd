extends Node
## Mode duo, côté hôte : la simulation reste arena.gd, avec une seconde Jo (celle de l'invité) dans
## arena.partner. Elle tire avec les sticks reçus de l'invité, se place là où l'invité dit être (il pilote sa
## propre Jo sans attendre le réseau) ; les coups, PV et morts restent décidés ici.
## Chaque 1/20 s (1/15 par le relais), un instantané part vers l'invité, avec les événements visuels.
## Relève : une Jo à terre se relève si sa partenaire reste 2 s près d'elle ; sinon à la salle suivante.
## Les deux à terre : partie perdue.

const Proto = preload("res://scripts/net/proto.gd")
const HeroScript = preload("res://scripts/hero.gd")
const Partner3D = preload("res://scripts/net/partner3d.gd")
const Data = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")

const REVIVE_R := 120.0  # px
const REVIVE_T := 2.0  # s

var duo: Node
var main: Node
var arena: Node
var hero: Node2D
var partner: Node2D
var p3d: Node3D
var marker: Node3D
var inp := {"pos": Vector2.ZERO, "mv": Vector2.ZERO, "aim": Vector2.ZERO, "aim_on": false, "choosing": false, "seq": -1}
var revive := [0.0, 0.0]
var events: Array = []
var _seq := 0
var _next_snap := 0
var _nid := 0
var _last_room := -1
var _energy_sent := -1
var _firing_partner := false
var _game_over := false
var _powers_seen := {}
var _last_door := {}
var _down_test := -1.0
var _wipe_test := -1.0
var _god := false
var _t := 0.0
var _wait_guest := 8.0  # la partie attend que l'invité soit prêt (au plus 8 s)

var _wait_msg := false

func begin() -> void:
	process_priority = -10  # avant arena.gd : les ennemis visent la bonne Jo dès cette image
	arena = main.arena
	hero = main.hero
	partner = HeroScript.new()
	partner.arena = arena
	partner.items = duo.partner_items
	partner.set_meta("profile", {"talents": duo.partner_talents})  # talents de l'invité (talents.gd)
	partner.recalc()
	partner.hp = partner.hp_max
	arena.add_child(partner)
	partner.position = hero.position + Vector2(90, 0)
	inp["pos"] = partner.position
	arena.partner = partner
	arena.partner_tickets = 0
	partner.died.connect(_on_partner_down)
	_last_room = arena.room
	arena.fired.connect(_ev_fired)
	arena.enemy_hit.connect(_ev_hit)
	arena.shield_blocked.connect(_ev_shield)
	arena.exploded.connect(_ev_boom)
	arena.shockwave_started.connect(_ev_wave)
	arena.shell_launched.connect(_ev_shell)
	arena.doors_opened.connect(_on_doors)
	arena.door_taken.connect(_on_door)
	arena.partner_item.connect(_on_partner_item)
	arena.energy_full.connect(_on_energy)
	p3d = Partner3D.new()
	main.view.add_child(p3d)
	p3d.setup(main.view, partner, true, "J2")
	partner.damaged.connect(func(): p3d.rig.flash(0.18))
	marker = Partner3D.new()
	main.view.add_child(marker)
	marker.setup(main.view, hero, false, "RELÈVE-MOI", true)
	var d := String(duo._arg("--duo-down-at="))
	if d != "":
		_down_test = float(d)
	var w := String(duo._arg("--duo-wipe-at="))
	if w != "":
		_wipe_test = float(w)
	_god = "--god" in OS.get_cmdline_user_args()
	arena.running = false
	main.hud.flash("EN ATTENTE DE J2…", 8.0, UI.ACCENT)

func end() -> void:
	for s in [[arena.fired, _ev_fired], [arena.enemy_hit, _ev_hit], [arena.shield_blocked, _ev_shield], [arena.exploded, _ev_boom], [arena.shockwave_started, _ev_wave], [arena.shell_launched, _ev_shell], [arena.doors_opened, _on_doors], [arena.door_taken, _on_door], [arena.partner_item, _on_partner_item], [arena.energy_full, _on_energy]]:
		if (s[0] as Signal).is_connected(s[1]):
			(s[0] as Signal).disconnect(s[1])
	if arena.partner == partner:
		arena.partner = null
	for n in [partner, p3d, marker]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	partner = null

# ---------------------------------------------------------------- réception
func on_input(i: Dictionary) -> void:
	var s: int = i["seq"]
	var last: int = inp["seq"]
	if last >= 0 and ((s - last) & 0xFFFF) > 0x8000:
		return  # plus vieux que le dernier reçu
	inp = i

func on_ev(d: Dictionary) -> void:
	match String(d.get("t", "")):
		"ready":
			_go_now()
		"powers":
			# pouvoirs choisis par l'invité : appliqués à sa Jo ici (tourelles et drones compris)
			var pw: Dictionary = d.get("powers", {})
			for id in pw.keys():
				var have := int(_powers_seen.get(id, 0))
				for k in range(int(pw[id]) - have):
					partner.add_power(String(id))
					if id == "turret":
						arena.turrets.append({"pos": partner.position + Vector2.RIGHT.rotated(randf() * TAU) * 100.0, "cd": 0.0, "ang": 0.0})
					if id == "ally":
						arena.allies.append({"ang": randf() * TAU, "cd": 0.0})
				_powers_seen[id] = int(pw[id])
		"items":
			partner.items = d.get("items", [])
			partner.recalc()
			p3d.rig.apply_items(partner.items)

# ---------------------------------------------------------------- boucle
func _process(dt: float) -> void:
	if partner == null or main.state != "arena":
		return
	_t += dt
	if _wait_guest > 0.0:
		_wait_guest -= dt
		if _wait_guest <= 0.0:
			_go_now()
		return
	if not arena.running:
		arena.frozen = false
		return
	# montée de niveau, objet ou pause chez l'un des deux : la partie se fige pour les deux jusqu'à la fin du choix
	var frozen: bool = main.overlay != null or bool(inp["choosing"])
	arena.frozen = frozen
	var wait := frozen and main.overlay == null  # on attend le choix de l'autre : on le dit
	if wait != _wait_msg:
		_wait_msg = wait
		main.hud.flash("PAUSE · TON PARTENAIRE CHOISIT" if wait else "", 3600.0 if wait else 0.0, UI.GOLD)
	# la Jo de l'invité : ses sticks, sa position (lissée)
	if not partner.dead and not frozen:
		var before: Vector2 = partner.position
		_firing_partner = true
		partner.update(dt, inp["mv"], inp["aim"], inp["aim_on"])
		_firing_partner = false
		var target: Vector2 = inp["pos"]
		partner.position = target if before.distance_to(target) > 220.0 else before.lerp(target, clampf(dt * 18.0, 0.0, 1.0))
		arena._clamp_circle(partner, partner.radius)
		if inp["choosing"]:
			partner.invuln = maxf(partner.invuln, 0.3)
		if inp.get("dodge", false):
			partner.dodge_t = maxf(partner.dodge_t, 0.12)  # sa ruée la rend invulnérable ici aussi
	p3d.shooting = inp["aim_on"] and not partner.dead
	# l'hôte, pendant son propre choix (pouvoir, objet) : invulnérable, la partie continue
	if main.overlay != null and not hero.dead:
		hero.invuln = maxf(hero.invuln, 0.3)
	if _god and _down_test < 0.0 and _wipe_test < 0.0:
		partner.hp = partner.hp_max
	_tick_tests()
	if not frozen:
		_tick_revive(dt)
	if arena.room != _last_room:
		_on_new_room()
	var now := Time.get_ticks_msec()
	if now >= _next_snap:
		_next_snap = now + (50 if duo.link.kind == "lan" else 66)
		duo.send_raw(Proto.encode_snap(_snapshot(now)), false)

## L'invité est prêt (ou trop long) : la simulation démarre des deux côtés en même temps.
func _go_now() -> void:
	if _wait_guest <= 0.0 and arena.running:
		return
	_wait_guest = 0.0
	arena.running = true
	main.hud.flash("", 0.0)
	print("DUO : invité prêt, la partie démarre")

func _tick_tests() -> void:
	if _down_test >= 0.0 and duo._run_t >= _down_test and not partner.dead:
		_down_test = -1.0
		print("DUO : essai de relève, la Jo de l'invité est mise à terre")
		partner.invuln = 0.0
		partner.shield_ready = false
		partner.hp = 1.0
		partner.take_damage(9999.0)
	if _wipe_test >= 0.0 and duo._run_t >= _wipe_test:
		_wipe_test = -1.0
		print("DUO : essai de défaite, les deux Jo sont mises à terre")
		for h in [partner, hero]:
			if not h.dead:
				h.invuln = 0.0
				h.shield_ready = false
				h.hp = 1.0
				h.take_damage(9999.0)

func _tick_revive(dt: float) -> void:
	var hs := [hero, partner]
	for i in range(2):
		var h: Node2D = hs[i]
		var o: Node2D = hs[1 - i]
		if not h.dead:
			revive[i] = 0.0
			continue
		if not o.dead and o.position.distance_to(h.position) < REVIVE_R:
			revive[i] += dt / REVIVE_T
			if revive[i] >= 1.0:
				revive[i] = 0.0
				_revive(h)
		else:
			revive[i] = maxf(0.0, revive[i] - dt * 0.5)
	marker.revive = revive[0]
	p3d.revive = revive[1]

func _revive(h: Node2D, frac: float = 0.5) -> void:
	h.dead = false
	h.hp = h.hp_max * frac
	h.invuln = 2.0
	if h == hero:
		main.joy.enabled = true
		main.hud.flash("RELEVÉE !", 1.4, UI.ACCENT)
	else:
		main.hud.flash("J2 EST RELEVÉE", 1.4, UI.ACCENT)
	main.sfx.play("level", 1.3, -4.0)
	print("DUO : relève de %s" % ("J1 (hôte)" if h == hero else "J2 (invité)"))

## main._on_hero_died() : Jo de l'hôte à terre.
func local_down() -> void:
	main.sfx.play("boom", 0.6)
	main.view.add_shake(0.8)
	if partner.dead:
		_both_down()
	else:
		main.hud.flash("À TERRE · J2 PEUT TE RELEVER", 2.5, UI.DANGER)
		print("DUO : J1 (hôte) à terre")

func _on_partner_down() -> void:
	print("DUO : J2 (invité) à terre")
	if hero.dead:
		_both_down()
	else:
		main.hud.flash("J2 À TERRE · VA LA RELEVER", 2.5, UI.DANGER)

func _both_down() -> void:
	if _game_over:
		return
	_game_over = true
	print("DUO : les deux Jo sont à terre, partie perdue")
	main.hud.flash("K.O.", 1.2, UI.DANGER)
	main.joy.enabled = false
	await get_tree().create_timer(1.1, true, false, true).timeout
	if main.state != "arena" or not is_instance_valid(self):
		return
	main._pause_for_overlay()
	main._show_end(false, "RAPPEL AU RELAIS", "Les deux Passeuses sont à terre. Le butin reste.")

## Nouvelle salle (portail franchi) : les Jo à terre se relèvent à moitié, l'invité est replacé.
func _on_new_room() -> void:
	_last_room = arena.room
	for h in [hero, partner]:
		if h.dead or h.hp <= 0.0:
			_revive(h)
	revive = [0.0, 0.0]
	partner.position = hero.position + Vector2(90, 0)
	inp["pos"] = partner.position
	arena._clamp_circle(partner, partner.radius)
	events.clear()
	var d := _last_door
	duo.send_ev({"t": "room", "room": arena.room, "mod": arena.modifier, "pos": partner.position, "hpos": hero.position, "title": d.get("title", ""), "col": d.get("col", Color.WHITE)})
	print("DUO : salle %d (%s)" % [arena.room, arena.modifier])

# ---------------------------------------------------------------- événements vers l'invité
func _ev_fired(pos: Vector2, vel: Vector2, hero_shot: bool, color: Color, radius: float) -> void:
	if _firing_partner:
		return  # l'invité dessine déjà ses propres tirs, sans attendre le réseau
	var b: int = hero.bounce if hero_shot else 0
	var p: int = hero.pierce if hero_shot else 0
	events.append({"k": Proto.E_FIRE, "ms": Time.get_ticks_msec(), "pos": pos, "vel": vel, "col": color, "r": radius, "hero": hero_shot, "bounce": b, "pierce": p})

func _ev_hit(e: Node2D, pos: Vector2, dmg: float, crit: bool) -> void:
	events.append({"k": Proto.E_HIT, "ms": Time.get_ticks_msec(), "id": _id_of(e), "pos": pos, "dmg": dmg, "crit": crit})

func _ev_shield(e: Node2D, pos: Vector2, vel: Vector2) -> void:
	events.append({"k": Proto.E_SHIELD, "ms": Time.get_ticks_msec(), "id": _id_of(e), "pos": pos, "vel": vel})

func _ev_boom(pos: Vector2, r: float, col: Color) -> void:
	events.append({"k": Proto.E_BOOM, "ms": Time.get_ticks_msec(), "pos": pos, "r": r, "col": col})

func _ev_wave(pos: Vector2, max_r: float, spd: float, col: Color) -> void:
	events.append({"k": Proto.E_WAVE, "ms": Time.get_ticks_msec(), "pos": pos, "max": max_r, "spd": spd, "col": col})

func _ev_shell(from: Vector2, to: Vector2, flight: float, r: float) -> void:
	events.append({"k": Proto.E_SHELL, "ms": Time.get_ticks_msec(), "from": from, "to": to, "flight": flight, "r": r})

func _on_doors() -> void:
	duo.send_ev({"t": "doors", "doors": arena.doors.duplicate(true)})

func _on_door(d: Dictionary) -> void:
	_last_door = d
	duo.send_ev({"t": "door", "d": d})

func _on_partner_item(item: Dictionary) -> void:
	duo.send_ev({"t": "item", "item": item})

func _on_energy() -> void:
	if arena.energy_level != _energy_sent:
		_energy_sent = arena.energy_level
		duo.send_ev({"t": "energy"})

## Fin de partie décidée chez l'invité : n'arrive pas (l'hôte décide), présent pour l'interface commune.
func remote_over(_d: Dictionary) -> void:
	pass

# ---------------------------------------------------------------- instantané
func _id_of(e: Node) -> int:
	if not e.has_meta("nid"):
		_nid = (_nid % 65534) + 1
		e.set_meta("nid", _nid)
	return int(e.get_meta("nid"))

func _hero_state(h: Node2D, i: int) -> Dictionary:
	var firing: bool = main.joy.aim_active if i == 0 else bool(inp["aim_on"])
	var choosing: bool = main.overlay != null if i == 0 else bool(inp["choosing"])
	return {"pos": h.position, "aim": h.aim_dir, "mv": h.move_dir, "dead": h.dead, "moving": h.moving, "firing": firing and not h.dead,
		"shield": h.shield_max > 0 and h.shield_ready, "choosing": choosing, "hp": h.hp, "hp_max": h.hp_max, "invuln": h.invuln, "revive": revive[i]}

func _snapshot(now: int) -> Dictionary:
	_seq = (_seq + 1) & 0xFFFF
	var en := []
	for e in arena.enemies:
		if e.dead:
			continue
		var st := Proto.STATES.find(String(e.state))
		en.append({"id": _id_of(e), "kind": Proto.kind_index(e.kind), "elite": e.elite, "state": maxi(0, st), "pos": e.position,
			"facing": e.facing, "aim": e.aim_dir, "st": e.state_t, "hp": clampf(e.hp / maxf(1.0, e.hp_max), 0.0, 1.0), "lock": e.lock})
	var pks := []
	for pk in arena.pickups:
		if not pk.has("nid"):
			_nid = (_nid % 65534) + 1
			pk["nid"] = _nid
		var k := 0
		match String(pk["kind"]):
			"hp":
				k = 1
			"item":
				k = 2 + int(pk["item"]["rarity"])
		pks.append({"id": pk["nid"], "kind": k, "pos": pk["pos"]})
	var ch := {"st": 0, "pos": Vector2.ZERO}
	if not arena.chest.is_empty():
		ch = {"st": 2 if arena.chest["open"] else 1, "pos": arena.chest["pos"]}
	var evs := events.slice(0, 255)
	events = events.slice(255)
	return {"seq": _seq, "ms": now, "run": duo.run_id, "room": arena.room, "cleared": arena.cleared, "boss_room": arena.room >= Data.ROOMS,
		"wave": arena.wave_i + 1, "waves": arena.waves.size(), "queue": arena.spawn_queue.size(), "kills": arena.kills,
		"energy": arena.energy, "need": arena.energy_need, "ptk": arena.partner_tickets, "frozen": arena.frozen,
		"heroes": [_hero_state(hero, 0), _hero_state(partner, 1)], "enemies": en, "pickups": pks, "chest": ch,
		"turrets": arena.turrets, "events": evs}

## Robot (--autoplay) : relever la partenaire à terre, ne pas s'en éloigner de plus d'un écran.
func bot_goal(me: Node2D) -> Vector2:
	if partner == null:
		return Vector2.INF
	if partner.dead and not me.dead:
		return partner.position
	if me.position.distance_to(partner.position) > 420.0:
		return partner.position
	return Vector2.INF
