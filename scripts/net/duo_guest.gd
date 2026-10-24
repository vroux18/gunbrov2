extends Node
## Mode duo, côté invité : arena.gd ne simule pas (arena.running reste faux), elle sert de décor de données
## pour le rendu (view3d.gd, mob3d.gd, hud.gd) : ennemis fantômes, ramassages, coffre, portails, tourelles,
## remplis d'après les instantanés de l'hôte.
## Le temps de rendu est celui de l'hôte moins un petit retard (DELAY) : les positions sont interpolées entre
## deux instantanés, les événements (tirs, impacts, explosions) rejoués à leur heure. L'invité pilote sa
## propre Jo sans attendre le réseau ; ses tirs sont dessinés tout de suite (les dégâts, eux, sont comptés
## chez l'hôte). PV, mort et relève de sa Jo viennent de l'hôte.

const Proto = preload("res://scripts/net/proto.gd")
const HeroScript = preload("res://scripts/hero.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Partner3D = preload("res://scripts/net/partner3d.gd")
const Data = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")

var duo: Node
var main: Node
var arena: Node
var me: Node2D  # Jo de l'invité (main.hero)
var partner: Node2D  # Jo de l'hôte (fantôme)
var p3d: Node3D
var marker: Node3D
var buf: Array = []  # instantanés reçus, triés par heure de l'hôte
var evq: Array = []  # événements en attente de leur heure
var ghosts := {}  # id réseau -> ennemi fantôme
var picks := {}  # id réseau -> ramassage
var offset := 0.0  # heure de l'hôte - heure locale (ms)
var _has_offset := false
var delay_ms := 100.0
var _seq := 0
var _next_in := 0
var _last_hp := -1.0
var _cleared := false
var _wave := 0
var _chest_open := false
var _powers_sig := ""
var _items_sig := ""
var _sync_t := 0.0
var _boss_seen := false
var late_ms: Array = []  # retards mesurés (réception - émission estimée), pour le rapport
var _pos_err := 0.0
var _room_miss := 0

func begin() -> void:
	arena = main.arena
	me = main.hero
	arena.running = false  # l'hôte simule ; ici on ne fait que rejouer
	delay_ms = 100.0 if duo.link.kind == "lan" else 150.0
	partner = HeroScript.new()
	partner.arena = null
	partner.items = duo.partner_items
	partner.recalc()
	arena.add_child(partner)
	partner.position = me.position
	me.position = me.position + Vector2(90, 0)
	p3d = Partner3D.new()
	main.view.add_child(p3d)
	p3d.setup(main.view, partner, false, "J1")
	p3d.rig.apply_items(partner.items)
	marker = Partner3D.new()
	main.view.add_child(marker)
	marker.setup(main.view, me, true, "RELÈVE-MOI", true)
	Partner3D.recolor(main.view.hero)  # sa propre Jo à la palette de l'invité, comme chez l'hôte
	_powers_sig = var_to_str(me.powers)
	_items_sig = _items_key(me.items)

func end() -> void:
	for id in ghosts.keys():
		var e: Node2D = ghosts[id]
		if is_instance_valid(e):
			arena.enemies.erase(e)
			e.queue_free()
	ghosts.clear()
	for n in [partner, p3d, marker]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	partner = null
	# la Jo locale retrouve sa palette normale (prochaine partie solo)
	if main.view != null and main.view.hero != null:
		main.view.hero.make_hero(Color(0.5, 1.0, 0.94), 0.009, Color(1.0, 0.22, 0.28))
		main.view.set_hero_items(me.items)

static func _items_key(items: Array) -> String:
	var k := ""
	for it in items:
		k += String(it.get("uid", it.get("id", ""))) + ";"
	return k

# ---------------------------------------------------------------- réception
func on_snap(s: Dictionary) -> void:
	if int(s["run"]) != duo.run_id:
		return  # d'une autre partie
	if int(s["room"]) != arena.room:
		# d'une autre salle : le message « room » est en route ; s'il tarde (perdu), on se recale seul
		_room_miss += 1
		if _room_miss > 15 and int(s["room"]) > arena.room:
			print("DUO : salle %d manquée, recalage" % int(s["room"]))
			_new_room({"room": int(s["room"]), "mod": "combat", "pos": me.position, "hpos": s["heroes"][0]["pos"]})
		return
	_room_miss = 0
	var now := float(Time.get_ticks_msec())
	var sample := float(s["ms"]) - now
	if not _has_offset:
		offset = sample
		_has_offset = true
	elif sample > offset:
		offset = lerpf(offset, sample, 0.3)  # arrivé plus vite : l'estimation se recale vite
	else:
		offset = lerpf(offset, sample, 0.02)  # arrivé en retard : on suit lentement (gigue)
	late_ms.append(offset - sample)
	if late_ms.size() > 200:
		late_ms.pop_front()
	# tampon adaptatif : couvre 90 % de la gigue mesurée (Wi-Fi de téléphone : rafales), entre 80 et 250 ms
	if late_ms.size() >= 20 and int(s["seq"]) % 20 == 0:
		var lm := late_ms.duplicate()
		lm.sort()
		var want := clampf(float(lm[int(lm.size() * 0.9)]) + 40.0, 80.0, 250.0)
		delay_ms = lerpf(delay_ms, want, 0.5)
	# rangé à sa place (non fiable : l'ordre d'arrivée n'est pas garanti)
	var i := buf.size()
	while i > 0 and int(buf[i - 1]["ms"]) > int(s["ms"]):
		i -= 1
	buf.insert(i, s)
	while buf.size() > 12:
		buf.pop_front()
	for e in s["events"]:
		evq.append(e)
	_apply_latest(buf[buf.size() - 1])

func on_ev(d: Dictionary) -> void:
	match String(d.get("t", "")):
		"room":
			_new_room(d)
		"doors":
			arena.doors = d.get("doors", [])
			arena.doors_opened.emit()
			main.hud.flash("CHOISIS TON PORTAIL", 1.1, UI.ACCENT)
		"door":
			var dd: Dictionary = d.get("d", {})
			arena.doors.clear()
			main.sfx.play("portal")
			main.joy.enabled = false
			main.joy.reset()
			if not dd.is_empty():
				main.view.door_enter(dd)
		"item":
			main._show_item(d.get("item", {}))
		"energy":
			if main.overlay != null:
				duo.energy_wait = true  # choisi dès que l'écran en cours se ferme
			else:
				main._show_power_choice()

func _new_room(d: Dictionary) -> void:
	var r := int(d.get("room", arena.room + 1))
	arena.start_room(r, String(d.get("mod", "combat")))
	arena.running = false
	for id in ghosts.keys():
		arena.enemies.erase(ghosts[id])
	ghosts.clear()  # libérés par start_room
	picks.clear()
	buf.clear()
	evq.clear()
	_cleared = false
	_wave = 0
	_chest_open = false
	me.position = d.get("pos", me.position)
	partner.position = d.get("hpos", partner.position)
	main.view.start_room()
	main.hud.fade = 1.0
	var title := String(d.get("title", ""))
	main.hud.flash(("SALLE %d · %s" % [r, title]) if r < Data.ROOMS else main._boss_title(), 1.8, d.get("col", UI.ACCENT))
	main.joy.enabled = main.overlay == null
	print("DUO : salle %d (%s), invité replacé" % [r, d.get("mod", "")])

## Fin de partie décidée par l'hôte (les deux à terre, victoire, abandon).
func remote_over(d: Dictionary) -> void:
	arena.room = int(d.get("room", arena.room))
	arena.kills = int(d.get("kills", arena.kills))
	if main.overlay != null:
		main._clear_overlay()
	if bool(d.get("won", false)):
		main._victory()
	else:
		main._pause_for_overlay()
		main._show_end(false, String(d.get("title", "RAPPEL AU RELAIS")), String(d.get("sub", "")))
	print("DUO : fin de partie reçue de l'hôte (%s)" % d.get("title", ""))

## Ce qui ne s'interpole pas : compteurs, coffre, ramassages, tourelles, PV de sa propre Jo.
func _apply_latest(s: Dictionary) -> void:
	arena.kills = int(s["kills"])
	arena.energy = float(s["energy"])
	arena.energy_need = maxf(1.0, float(s["need"]))
	arena.tickets = int(s["ptk"])
	var nw := int(s["waves"])
	if arena.waves.size() != nw:
		arena.waves = []
		arena.waves.resize(nw)
	var w := int(s["wave"])
	arena.wave_i = w - 1
	if w > _wave:
		_wave = w
		arena.wave_changed.emit()
	if arena.spawn_queue.size() != int(s["queue"]):
		arena.spawn_queue = []
		arena.spawn_queue.resize(int(s["queue"]))
	if bool(s["cleared"]) and not _cleared:
		_cleared = true
		arena.cleared = true
		main.sfx.play("level", 1.2)
		Music.stinger()
		arena.room_cleared.emit()
	# coffre
	var ch: Dictionary = s["chest"]
	if int(ch["st"]) == 0:
		arena.chest = {}
		_chest_open = false
	else:
		var open := int(ch["st"]) == 2
		arena.chest = {"pos": ch["pos"], "open": open}
		if open and not _chest_open:
			main.sfx.play("chest")
			arena.chest_opened.emit(ch["pos"])
		_chest_open = open
	# tourelles
	var tu: Array = s["turrets"]
	while arena.turrets.size() < tu.size():
		arena.turrets.append({"pos": Vector2.ZERO, "cd": 0.0, "ang": 0.0})
	while arena.turrets.size() > tu.size():
		arena.turrets.pop_back()
	# sa propre Jo : PV, bouclier, à terre ou relevée (décidé chez l'hôte)
	var h: Dictionary = s["heroes"][1]
	me.hp_max = float(h["hp_max"])
	var hp := float(h["hp"])
	if _last_hp >= 0.0 and hp < _last_hp - 0.05 and not bool(h["dead"]):
		me.flash = 0.18
		me.damaged.emit()
	_last_hp = hp
	me.hp = hp
	if me.shield_max > 0:
		me.shield_ready = bool(h["shield"])
	if float(h["invuln"]) > me.invuln + 0.2:
		me.invuln = float(h["invuln"])
	if bool(h["dead"]) and not me.dead:
		me.dead = true
		main.joy.reset()
		main.sfx.play("boom", 0.6)
		main.view.add_shake(0.8)
		main.hud.flash("À TERRE · J1 PEUT TE RELEVER", 2.5, UI.DANGER)
		print("DUO : J2 (invité) à terre")
	elif not bool(h["dead"]) and me.dead:
		me.dead = false
		main.hud.flash("RELEVÉE !", 1.4, UI.ACCENT)
		main.sfx.play("level", 1.3, -4.0)
		print("DUO : J2 (invité) relevée")
	marker.revive = float(h["revive"])
	p3d.revive = float(s["heroes"][0]["revive"])

# ---------------------------------------------------------------- boucle
func _process(dt: float) -> void:
	if partner == null or main.state != "arena":
		return
	arena.elapsed += dt
	# sa propre Jo : pilotée ici, sans attendre le réseau
	if not me.dead:
		me.update(dt, main.joy.move, main.joy.aim, main.joy.aim_active)
		arena._clamp_circle(me, me.radius)
	_tick_bullets(dt)
	var rt := float(Time.get_ticks_msec()) + offset - delay_ms
	_interpolate(rt, dt)
	_play_events(rt)
	# effets dont la simulation est chez l'hôte : rien à faire vivre ici
	arena.shells.clear()
	arena.waves_fx.clear()
	arena.particles.clear()
	for pk in picks.values():
		pk["t"] += dt
	_send_input()
	_sync_t -= dt
	if _sync_t <= 0.0:
		_sync_t = 0.25
		_sync_loadout()

## Tirs : trajectoires rejouées en ligne droite (rebonds sur les murs et caisses), effacés au contact.
## Les tirs sont des objets légers (scripts/bullet.gd) : on les avance ici, l'arène ne simule pas chez l'invité.
func _tick_bullets(dt: float) -> void:
	var gone := []
	for b in arena.bullets:
		b.position += b.vel * dt
		b.life -= dt
		if b.life <= 0.0 or arena._bullet_walls(b):
			gone.append(b)
			continue
		if b.hero_shot:
			for e in arena.enemies:
				if e in b.hits:
					continue
				if (e.position - b.position).length() < e.radius + b.radius:
					if b.pierce > 0:
						b.pierce -= 1
						b.hits.append(e)
					else:
						gone.append(b)
					break
		else:
			for h in [me, partner]:
				if not h.dead and (h.position - b.position).length() < h.radius + b.radius:
					gone.append(b)
					break
	for b in gone:
		arena.bullets.erase(b)

func _interpolate(rt: float, dt: float) -> void:
	if buf.is_empty():
		return
	var a: Dictionary = buf[0]
	var b: Dictionary = buf[buf.size() - 1]
	for i in range(buf.size() - 1):
		if float(buf[i]["ms"]) <= rt and float(buf[i + 1]["ms"]) >= rt:
			a = buf[i]
			b = buf[i + 1]
			break
	if rt >= float(b["ms"]):
		a = b
	var span := float(b["ms"]) - float(a["ms"])
	var k := 1.0 if span <= 0.0 else clampf((rt - float(a["ms"])) / span, 0.0, 1.0)
	# Jo de l'hôte
	var ha: Dictionary = a["heroes"][0]
	var hb: Dictionary = b["heroes"][0]
	partner.position = (ha["pos"] as Vector2).lerp(hb["pos"], k)
	partner.aim_dir = hb["aim"]
	partner.move_dir = hb["mv"]
	partner.moving = hb["moving"]
	partner.dead = hb["dead"]
	partner.hp = hb["hp"]
	partner.hp_max = hb["hp_max"]
	partner.invuln = hb["invuln"]
	p3d.shooting = hb["firing"]
	# ennemis : présents dans l'instantané le plus récent des deux, positions interpolées
	var prev := {}
	for e in a["enemies"]:
		prev[int(e["id"])] = e
	var seen := {}
	for e in b["enemies"]:
		var id := int(e["id"])
		seen[id] = true
		var g: Node2D = ghosts.get(id)
		if g == null:
			g = _spawn_ghost(e)
		var pa: Dictionary = prev.get(id, e)
		g.position = (pa["pos"] as Vector2).lerp(e["pos"], k)
		g.facing = e["facing"]
		g.aim_dir = e["aim"]
		var st := int(e["state"])
		g.state = String(Proto.STATES[st]) if st < Proto.STATES.size() else "move"
		g.state_t = lerpf(float(pa["st"]), float(e["st"]), k)
		g.lock = e["lock"]
		g.hp = float(e["hp"]) * g.hp_max
		g.flash = maxf(0.0, g.flash - dt)
	for id in ghosts.keys():
		if not seen.has(id):
			_kill_ghost(id)
	# ramassages
	var pseen := {}
	for p in b["pickups"]:
		var id := int(p["id"])
		pseen[id] = true
		var pk: Dictionary = picks.get(id, {})
		if pk.is_empty():
			var kind := "ticket"
			if int(p["kind"]) == 1:
				kind = "hp"
			elif int(p["kind"]) >= 2:
				kind = "item"
			pk = {"pos": p["pos"], "kind": kind, "vel": Vector2.ZERO, "t": 0.0, "item": {"id": "", "rarity": clampi(int(p["kind"]) - 2, 0, 3)}}
			picks[id] = pk
			arena.pickups.append(pk)
		var from: Vector2 = pk["pos"]
		pk["pos"] = from.lerp(p["pos"], clampf(dt * 14.0, 0.0, 1.0))
	for id in picks.keys():
		if not pseen.has(id):
			arena.pickups.erase(picks[id])
			picks.erase(id)
	# tourelles
	var tu: Array = b["turrets"]
	for i in range(mini(tu.size(), arena.turrets.size())):
		arena.turrets[i]["pos"] = tu[i]["pos"]
		arena.turrets[i]["ang"] = tu[i]["ang"]

func _spawn_ghost(e: Dictionary) -> Node2D:
	var g := Enemy.new()
	g.arena = arena
	g.hero = me
	var kind := Proto.kind_name(int(e["kind"]))
	g.setup(kind, bool(e["elite"]), 1.0)
	g.position = e["pos"]
	arena.ents.add_child(g)
	arena.enemies.append(g)
	ghosts[int(e["id"])] = g
	if kind.begins_with("boss"):
		arena.boss = g
	arena.enemy_spawned.emit(g)
	main.sfx.play("spawn", randf_range(0.9, 1.2), -16.0)
	return g

func _kill_ghost(id: int) -> void:
	var g: Node2D = ghosts[id]
	ghosts.erase(id)
	if not is_instance_valid(g):
		return
	g.dead = true
	arena.enemy_killed.emit(g)
	main.sfx.play("kill", randf_range(0.9, 1.2), -4.0)
	arena.enemies.erase(g)
	if arena.boss == g:
		arena.boss = null
	g.queue_free()

## Événements visuels de l'hôte, rejoués quand le temps de rendu atteint leur heure.
func _play_events(rt: float) -> void:
	if evq.is_empty():
		return
	evq.sort_custom(func(x, y): return int(x["ms"]) < int(y["ms"]))
	var n := 0
	while n < evq.size() and float(evq[n]["ms"]) <= rt:
		var e: Dictionary = evq[n]
		var late := clampf((rt - float(e["ms"])) / 1000.0, 0.0, 0.5)
		match int(e["k"]):
			Proto.E_FIRE:
				var vel: Vector2 = e["vel"]
				arena.spawn_bullet(e["pos"] + vel * late, vel, 0.0, e["hero"], int(e["pierce"]), int(e["bounce"]), e["col"], float(e["r"]))
				var bl = arena.bullets[arena.bullets.size() - 1]
				bl.life -= late
			Proto.E_HIT:
				var g: Node2D = ghosts.get(int(e["id"]))
				if g != null and is_instance_valid(g):
					g.flash = 0.09
					arena.enemy_hit.emit(g, e["pos"], float(e["dmg"]), bool(e["crit"]))
					main.sfx.play("hit", randf_range(0.8, 1.2), -10.0)
			Proto.E_SHIELD:
				var g: Node2D = ghosts.get(int(e["id"]))
				if g != null and is_instance_valid(g):
					arena.shield_blocked.emit(g, e["pos"], e["vel"])
					main.sfx.play("hit", randf_range(1.4, 1.7), -8.0)
			Proto.E_BOOM:
				arena.explode(e["pos"], float(e["r"]), 0.0, 0.0, e["col"])
			Proto.E_WAVE:
				arena.shockwave(e["pos"], float(e["max"]), float(e["spd"]), 0.0, e["col"])
			Proto.E_SHELL:
				arena.lob(e["from"], e["to"], float(e["flight"]), float(e["r"]), 0.0)
		n += 1
	evq = evq.slice(n)
	# événements trop vieux (horloge recalée, salle changée) : jetés
	while evq.size() > 400:
		evq.pop_front()

func _send_input() -> void:
	var now := Time.get_ticks_msec()
	if now < _next_in:
		return
	_next_in = now + (33 if duo.link.kind == "lan" else 50)
	_seq = (_seq + 1) & 0xFFFF
	var j: Node = main.joy
	var alive: bool = not me.dead
	duo.send_raw(Proto.encode_input({"seq": _seq, "pos": me.position, "mv": j.move if alive else Vector2.ZERO,
		"aim": j.aim if alive else Vector2.ZERO, "aim_on": alive and j.aim_active, "choosing": main.overlay != null}), false)

## Pouvoirs choisis et objets équipés par l'invité : envoyés à l'hôte qui simule sa Jo.
func _sync_loadout() -> void:
	var ps := var_to_str(me.powers)
	if ps != _powers_sig:
		_powers_sig = ps
		duo.send_ev({"t": "powers", "powers": me.powers})
	var ik := _items_key(me.items)
	if ik != _items_sig:
		_items_sig = ik
		duo.send_ev({"t": "items", "items": me.items})
		Partner3D.recolor(main.view.hero)  # le nouvel équipement prend la palette de J2

func local_down() -> void:
	pass  # la mort de la Jo locale est décidée chez l'hôte (instantanés)

## Robot (--autoplay) : relever la partenaire à terre, ne pas s'en éloigner de plus d'un écran.
func bot_goal(m: Node2D) -> Vector2:
	if partner == null:
		return Vector2.INF
	if partner.dead and not m.dead:
		return partner.position
	if m.position.distance_to(partner.position) > 420.0:
		return partner.position
	return Vector2.INF
