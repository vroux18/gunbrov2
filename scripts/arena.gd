extends Node2D
## L'arène : une grande carte (plus grande que l'écran, caméra qui suit), des caisses en obstacles,
## des vagues d'ennemis par salle, les projectiles, les ramassages, le coffre de fin de salle,
## les tourelles et drones alliés des pouvoirs. Toute la simulation est ici, les entités ne font que se dessiner.

const Data = preload("res://scripts/data.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Bullet = preload("res://scripts/bullet.gd")
const Art = preload("res://scripts/art.gd")

signal room_cleared
signal hero_died
signal energy_full
signal item_found(item: Dictionary)
signal wave_changed
# événements pour le rendu 3D (view3d.gd) : la simulation ne dépend jamais d'eux
signal fired(pos: Vector2, vel: Vector2, hero_shot: bool, color: Color, radius: float)
signal enemy_hit(e: Node2D, pos: Vector2, dmg: float, crit: bool)
signal enemy_killed(e: Node2D)
signal enemy_spawned(e: Node2D)
signal chest_opened(pos: Vector2)
signal bullet_blocked(pos: Vector2, color: Color)
signal exploded(pos: Vector2, radius: float, color: Color)
signal shell_launched(from: Vector2, to: Vector2, flight: float, radius: float)
signal doors_opened
signal shockwave_started(pos: Vector2, max_r: float, speed: float, color: Color)
signal door_taken(door: Dictionary)
signal shield_blocked(e: Node2D, pos: Vector2, vel: Vector2)  # tir de Jo arrêté par le bouclier d'un rempart

const W := 2400.0
const H := 1400.0
const WALL := 36.0
const TOP := 250.0  # alcôve du vaisseau : décor, pas de jeu
const BG := Color("#0E1B33")
const FLOOR := Color("#122448")
const GRID := Color("#16305A")
const CRATE := Color("#2A3F6E")
const CRATE_TOP := Color("#3B5590")
const OUTLINE := Color("#0B0F1A")
const CYAN := Color("#3CF2D8")
const ORANGE := Color("#FF7A2F")
const GOLD := Color("#FFB347")
const RED := Color("#FF4D6D")

var sfx: Node
var hero: Node2D
var joy: Node
var cam: Camera2D
var ents: Node2D
var shots: Node2D
var fxn: Node2D
var fxa: Node2D  # couche additive : halos, particules
var obstacles: Array[Rect2] = []
var pads: Array[Vector2] = []

var enemies: Array = []
var bullets: Array = []
var pickups: Array = []
var particles: Array = []
var shells: Array = []  # obus du mortier en vol : {from, to, t, flight, r, dmg}
var waves_fx: Array = []  # ondes de choc au sol (videur, boss) : {pos, r, max, spd, dmg, hit}
var doors: Array = []  # portails de fin de salle : {pos, kind, title, desc, col}, Jo entre dans l'un d'eux
var turrets: Array = []
var allies: Array = []
var chest := {}

var room := 1
var modifier := "combat"
var waves: Array = []
var wave_i := 0
var spawn_queue: Array = []
var spawn_t := 0.0
var wave_gap := 0.0
var running := false
var cleared := false
var kills := 0
var tickets := 0
var energy := 0.0
var energy_need := 10.0
var energy_level := 0
var boss: Node2D = null
var hp_scale := 1.0
var elapsed := 0.0
var shake_t := 0.0
var _rng := RandomNumberGenerator.new()

func build(sfx_node: Node, hero_node: Node2D) -> void:
	sfx = sfx_node
	hero = hero_node
	hero.arena = self
	ents = Node2D.new()
	add_child(ents)
	shots = Node2D.new()
	add_child(shots)
	add_child(hero)
	fxn = Node2D.new()
	fxn.draw.connect(_draw_fx)
	add_child(fxn)
	fxa = Node2D.new()
	fxa.material = Art.additive()
	fxa.draw.connect(_draw_fxa)
	add_child(fxa)
	cam = Camera2D.new()
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(W)
	cam.limit_bottom = int(H)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 9.0
	cam.zoom = Vector2(1.5, 1.5)
	cam.enabled = false
	add_child(cam)
	hero.died.connect(func(): hero_died.emit())
	hero.damaged.connect(func(): shake_t = 0.22)
	_layout()
	queue_redraw()

## Monde choisi au Relais (Data.world) : refait l'agencement de l'arène.
func set_world() -> void:
	_layout()

func _layout() -> void:
	obstacles.clear()
	_rng.seed = 7
	# obstacles d'un autre monde : fournis par son décor (const BOXES de scripts/decor/<id>_world.gd)
	var wpath := "res://scripts/decor/%s_world.gd" % Data.world_id()
	if Data.world_id() != "n7" and ResourceLoader.exists(wpath):
		for b in load(wpath).BOXES:
			obstacles.append(b)
		_pads()
		return
	# caisses du hangar : quelques groupes, jamais au centre ni devant les sas
	var boxes := [
		Rect2(520, 300, 150, 110), Rect2(680, 300, 90, 90),
		Rect2(1700, 260, 140, 140), Rect2(1850, 330, 90, 70),
		Rect2(420, 950, 120, 120), Rect2(560, 1010, 160, 70),
		Rect2(1750, 980, 170, 100), Rect2(1680, 1090, 90, 90),
		Rect2(1120, 1150, 160, 70),
		Rect2(300, 620, 80, 160), Rect2(2020, 620, 80, 160),
		Rect2(1000, 620, 70, 70), Rect2(1330, 710, 70, 70),
	]
	for b in boxes:
		obstacles.append(b)
	_pads()

## Sas d'apparition des ennemis (les mêmes dans tous les mondes).
func _pads() -> void:
	pads.clear()
	pads.append(Vector2(130, TOP + 90))
	pads.append(Vector2(W - 130, TOP + 90))
	pads.append(Vector2(130, H - 130))
	pads.append(Vector2(W - 130, H - 130))
	pads.append(Vector2(W * 0.5, TOP + 80))
	pads.append(Vector2(W * 0.5, H - 110))
	pads.append(Vector2(110, (TOP + H) * 0.5))
	pads.append(Vector2(W - 110, (TOP + H) * 0.5))

# ---------------------------------------------------------------- partie
func reset_run() -> void:
	_clear_entities()
	kills = 0
	tickets = 0
	energy = 0.0
	energy_need = 10.0
	energy_level = 0
	elapsed = 0.0
	turrets.clear()
	allies.clear()

func _clear_entities() -> void:
	for e in enemies:
		e.queue_free()
	enemies.clear()
	for b in bullets:
		b.queue_free()
	bullets.clear()
	pickups.clear()
	particles.clear()
	shells.clear()
	doors.clear()
	waves_fx.clear()
	chest = {}
	boss = null

func start_room(r: int, mod: String) -> void:
	room = r
	Music.play(("boss" if r >= Data.ROOMS else "combat") + String(Data.WORLDS[Data.world]["music"]))
	modifier = mod
	_clear_entities()
	hero.position = Vector2(W * 0.5, (TOP + H) * 0.5)
	hero.dead = false
	cam.position = hero.position
	cam.reset_smoothing()
	waves = Data.waves_for(r, mod)
	wave_i = -1
	wave_gap = 1.3
	spawn_queue = []
	running = true
	cleared = false
	# difficulté : les ennemis gagnent 20 % de PV par salle, et chaque monde repart plus haut (+40 %)
	hp_scale = (1.0 + (r - 1) * 0.2) * (1.0 + 0.4 * Data.world)
	# tourelles et drones des pouvoirs, replacés à chaque salle
	turrets.clear()
	for i in range(hero.turrets):
		turrets.append({"pos": hero.position + Vector2.RIGHT.rotated(TAU * i / 3.0 + 0.5) * 110.0, "cd": 0.0, "ang": 0.0})
	allies.clear()
	for i in range(hero.ally):
		allies.append({"ang": TAU * i / 2.0, "cd": 0.0})
	queue_redraw()

func stop() -> void:
	running = false
	_clear_entities()

func _start_wave(i: int) -> void:
	wave_i = i
	spawn_queue = waves[i].duplicate()
	spawn_queue.shuffle()
	spawn_t = 0.3
	wave_changed.emit()

func consume_energy() -> void:
	energy -= energy_need
	energy = maxf(0.0, energy)
	energy_level += 1
	energy_need += 6.0

func enemies_left() -> int:
	return enemies.size() + spawn_queue.size()

# ---------------------------------------------------------------- boucle
func _process(dt: float) -> void:
	if not running:
		return
	elapsed += dt
	if shake_t > 0.0:
		shake_t -= dt
		cam.offset = Vector2(randf_range(-6, 6), randf_range(-6, 6))
	else:
		cam.offset = Vector2.ZERO
	# apparitions
	if not cleared:
		if spawn_queue.is_empty() and enemies.is_empty():
			wave_gap -= dt
			if wave_gap <= 0.0:
				if wave_i + 1 < waves.size():
					_start_wave(wave_i + 1)
					wave_gap = 1.0
				else:
					_room_done()
		elif not spawn_queue.is_empty():
			spawn_t -= dt
			if spawn_t <= 0.0:
				spawn_t = 0.22 if room < Data.ROOMS else 0.1
				_spawn(String(spawn_queue.pop_back()))
	# héros
	hero.update(dt, joy.move, joy.aim, joy.aim_active)
	_clamp_circle(hero, hero.radius)
	cam.position = hero.position
	# ennemis
	for e in enemies:
		e.tick(dt)
	for i in range(enemies.size()):
		var a: Node2D = enemies[i]
		for j in range(i + 1, enemies.size()):
			var b: Node2D = enemies[j]
			var d: Vector2 = b.position - a.position
			var min_d: float = a.radius + b.radius
			var l := d.length()
			if l < min_d and l > 0.01:
				var push := d.normalized() * (min_d - l) * 0.5
				a.position -= push
				b.position += push
	for e in enemies:
		_clamp_circle(e, e.radius)
	# projectiles
	var dead_bullets := []
	for b in bullets:
		if b.life <= 0.0:
			dead_bullets.append(b)
			continue
		if _bullet_walls(b):
			dead_bullets.append(b)
			continue
		if b.hero_shot:
			for e in enemies:
				if e.dead or e in b.hits:
					continue
				if (e.position - b.position).length() < e.radius + b.radius + (10.0 if e.kind == "shield" else 0.0):
					if e.blocks(b.position - b.vel.normalized() * 30.0):
						shield_blocked.emit(e, b.position, b.vel)
						bullet_blocked.emit(b.position, b.color)
						sfx.play("hit", randf_range(1.4, 1.7), -8.0)
						_burst(b.position, ORANGE, 5, 200.0, 2.0)
						dead_bullets.append(b)
						break
					if (e.position - b.position).length() >= e.radius + b.radius:
						continue
					enemy_hit.emit(e, b.position, b.dmg, b.radius > 6.0)
					e.hit(b.dmg)
					sfx.play("hit", randf_range(0.8, 1.2), -10.0)
					_burst(b.position, b.color, 4, 140.0, 2.0)
					if b.pierce > 0:
						b.pierce -= 1
						b.hits.append(e)
					else:
						dead_bullets.append(b)
					break
		else:
			if (hero.position - b.position).length() < hero.radius + b.radius:
				if hero.take_damage(b.dmg):
					sfx.play("hurt", 1.0)
				dead_bullets.append(b)
	for b in dead_bullets:
		bullets.erase(b)
		b.queue_free()
	# portails de fin de salle : Jo choisit sa route en entrant dans l'un d'eux
	if not doors.is_empty():
		for d in doors:
			if (hero.position - d["pos"]).length() < hero.radius + 44.0:
				var taken: Dictionary = d
				doors.clear()
				door_taken.emit(taken)
				break
	# ondes de choc : touchent Jo une fois, quand le front passe sur elle
	var spent := []
	for wv in waves_fx:
		wv["r"] += wv["spd"] * dt
		if not wv["hit"] and absf((hero.position - wv["pos"]).length() - wv["r"]) < 22.0 + hero.radius * 0.5:
			wv["hit"] = true
			if hero.take_damage(wv["dmg"]):
				sfx.play("hurt", 1.0)
		if wv["r"] >= wv["max"]:
			spent.append(wv)
	for wv in spent:
		waves_fx.erase(wv)
	# obus du mortier : explosent à l'arrivée sur la zone annoncée au sol
	var landed := []
	for sh in shells:
		sh["t"] += dt
		if sh["t"] >= sh["flight"]:
			landed.append(sh)
	for sh in landed:
		shells.erase(sh)
		explode(sh["to"], sh["r"], sh["dmg"], 0.0, Color("#9BE15D"))
	# tourelles et drones
	for tr in turrets:
		tr["cd"] -= dt
		var e: Node2D = nearest_enemy(tr["pos"], 440.0)
		if e != null:
			tr["ang"] = (e.position - tr["pos"]).angle()
			if tr["cd"] <= 0.0:
				tr["cd"] = 0.36
				var d: Vector2 = (e.position - tr["pos"]).normalized()
				spawn_bullet(tr["pos"] + d * 22.0, d * 700.0, hero.dmg * 0.55, true, 0, 0, GOLD, 4.0)
	for al in allies:
		al["ang"] += dt * 2.2
		al["cd"] -= dt
		var p: Vector2 = hero.position + Vector2.RIGHT.rotated(al["ang"]) * 74.0
		var e: Node2D = nearest_enemy(p, 420.0)
		if e != null and al["cd"] <= 0.0:
			al["cd"] = 0.5
			var d: Vector2 = (e.position - p).normalized()
			spawn_bullet(p + d * 14.0, d * 700.0, hero.dmg * 0.6, true, 0, 0, CYAN, 4.0)
	# ramassages
	var attract: float = 90.0 * hero.magnet * hero.pickup_mult
	if cleared:
		attract = 5000.0  # salle vidée : tout le butin au sol file vers Jo
	var taken := []
	for pk in pickups:
		pk["t"] += dt
		pk["pos"] += pk["vel"] * dt
		pk["vel"] *= 0.9
		var d: Vector2 = hero.position - pk["pos"]
		if d.length() < attract:
			pk["pos"] += d.normalized() * 520.0 * dt
		if d.length() < hero.radius + 14.0:
			taken.append(pk)
	for pk in taken:
		pickups.erase(pk)
		match String(pk["kind"]):
			"ticket":
				tickets += 1
				sfx.play("pick", randf_range(1.0, 1.3), -12.0)
			"hp":
				hero.heal(20.0)
				sfx.play("pick", 0.7, -6.0)
			"item":
				sfx.play("chest")
				item_found.emit(pk["item"])
	# coffre
	if not chest.is_empty() and not chest["open"]:
		if (hero.position - chest["pos"]).length() < hero.radius + 30.0:
			chest["open"] = true
			var bonus := 0
			if modifier == "elite":
				bonus = 1
			if modifier == "tresor":
				bonus = 1
			if room >= Data.ROOMS:
				bonus = 2
			sfx.play("chest")
			chest_opened.emit(chest["pos"])
			_burst(chest["pos"], GOLD, 24, 260.0, 4.0)
			item_found.emit(Data.roll_item(bonus))
	# particules
	var i := 0
	while i < particles.size():
		var pa: Dictionary = particles[i]
		pa["life"] -= dt
		if pa["life"] <= 0.0:
			particles.remove_at(i)
			continue
		pa["pos"] += pa["vel"] * dt
		pa["vel"] *= 0.92
		i += 1
	fxn.queue_redraw()
	fxa.queue_redraw()

func _room_done() -> void:
	cleared = true
	var p := hero.position + Vector2(0, -140)
	p.x = clampf(p.x, 200, W - 200)
	p.y = clampf(p.y, TOP + 160, H - 200)
	chest = {"pos": p, "open": false}
	sfx.play("level", 1.2)
	Music.stinger()
	room_cleared.emit()

# ---------------------------------------------------------------- apparitions et morts
func _spawn(spec: String) -> void:
	var elite := spec.begins_with("elite:")
	var kind := spec.trim_prefix("elite:")
	var e := Enemy.new()
	e.arena = self
	e.hero = hero
	e.setup(kind, elite, hp_scale)
	var pad: Vector2 = pads[randi() % pads.size()]
	for k in range(4):
		if (pad - hero.position).length() > 520.0:
			break
		pad = pads[randi() % pads.size()]
	if kind.begins_with("boss"):
		pad = Vector2(W * 0.5, TOP + 150.0)
		boss = e
	e.position = pad + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	ents.add_child(e)
	enemies.append(e)
	enemy_spawned.emit(e)
	sfx.play("spawn", randf_range(0.9, 1.2), -16.0)
	_burst(e.position, CYAN, 8, 180.0, 3.0)

func boss_summon(pos: Vector2, n: int, kind: String = "") -> void:
	for i in range(n):
		var e := Enemy.new()
		e.arena = self
		e.hero = hero
		var k := kind if kind != "" else ("bomber" if i % 2 == 1 and Data.has_model("bomber") else "drone")
		e.setup(k if Data.has_model(k) else "drone", false, hp_scale)
		e.position = pos + Vector2.RIGHT.rotated(TAU * i / n) * 90.0
		ents.add_child(e)
		enemies.append(e)
		enemy_spawned.emit(e)
		_burst(e.position, RED, 8, 180.0, 3.0)
	sfx.play("portal", 0.8)

## Ouvre les portails de fin de salle (liste de {kind, title, desc, col}) en arc devant Jo, dans l'aire de jeu
## et hors des caisses.
func open_doors(list: Array) -> void:
	doors.clear()
	var n := list.size()
	var cx := clampf(hero.position.x, WALL + 140.0 + (n - 1) * 160.0, W - WALL - 140.0 - (n - 1) * 160.0)
	var up := hero.position.y - 150.0 > TOP + 110.0  # assez de place au nord, sinon au sud
	for i in range(n):
		var k := float(i) - (n - 1) * 0.5
		# arc serré autour de Jo, pour que les trois portails et leurs panneaux tiennent à l'écran
		var p := Vector2(cx + k * 320.0, hero.position.y + (-1.0 if up else 1.0) * (150.0 - absf(k) * 90.0))
		for tries in range(8):
			if not _blocked(p, 70.0):
				break
			p.y += (-1.0 if up else 1.0) * (35.0 if tries % 2 == 0 else -70.0)
		p.x = clampf(p.x, WALL + 90.0, W - WALL - 90.0)
		p.y = clampf(p.y, TOP + 90.0, H - WALL - 90.0)
		var d: Dictionary = (list[i] as Dictionary).duplicate()
		d["pos"] = p
		doors.append(d)
	doors_opened.emit()
	sfx.play("portal", 1.1, -2.0)

## Onde de choc au sol (videur, boss) : un anneau qui s'élargit jusqu'à `max_r` ; le rendu suit le signal.
func shockwave(pos: Vector2, max_r: float, spd: float, dmg: float, col: Color) -> void:
	waves_fx.append({"pos": pos, "r": 0.0, "max": max_r, "spd": spd, "dmg": dmg, "hit": false})
	shockwave_started.emit(pos, max_r, spd, col)
	sfx.play("boom", 0.7, -5.0)
	shake_t = maxf(shake_t, 0.15)

## Explosion : blesse Jo dans le rayon, et les autres ennemis si `enemy_dmg` > 0 (pétard abattu).
func explode(pos: Vector2, r: float, hero_dmg: float, enemy_dmg: float, col: Color) -> void:
	exploded.emit(pos, r, col)
	sfx.play("boom", randf_range(1.0, 1.2), -3.0)
	_burst(pos, col, 18, 320.0, 5.0)
	shake_t = maxf(shake_t, 0.12)
	if hero_dmg > 0.0 and (hero.position - pos).length() < r + hero.radius * 0.5:
		if hero.take_damage(hero_dmg):
			sfx.play("hurt", 1.0)
	if enemy_dmg > 0.0:
		for o in enemies.duplicate():
			if not o.dead and (o.position - pos).length() < r + o.radius:
				o.hit(enemy_dmg)

## Obus en cloche vers `to`, qui tombe après `flight` secondes (zone annoncée au sol par le rendu).
func lob(from: Vector2, to: Vector2, flight: float, r: float, dmg: float) -> void:
	to.x = clampf(to.x, WALL + 20.0, W - WALL - 20.0)
	to.y = clampf(to.y, TOP + 20.0, H - WALL - 20.0)
	shells.append({"from": from, "to": to, "t": 0.0, "flight": flight, "r": r, "dmg": dmg})
	shell_launched.emit(from, to, flight, r)
	sfx.play("eshoot", 0.6, -6.0)

## Mort d'un ennemi. `rewarded` faux : il s'est détruit lui-même (pétard), sans butin ni énergie.
func on_enemy_died(e: Node2D, rewarded: bool = true) -> void:
	if e.kind == "bomber" and rewarded:
		# un pétard abattu explose quand même, plus faiblement, et blesse ses voisins
		explode(e.position, 70.0, e.dmg * 0.5, 30.0, Color("#FF9A3C"))
	if not rewarded:
		enemy_killed.emit(e)
		enemies.erase(e)
		e.queue_free()
		return
	kills += 1
	energy += float(e.energy) * hero.energy_mult
	sfx.play("kill", randf_range(0.9, 1.2), -4.0)
	var is_boss: bool = e.kind.begins_with("boss")
	_burst(e.position, RED if not is_boss else Color("#F23CB8"), 14 if not is_boss else 60, 220.0, 4.0)
	for i in range(e.tickets):
		pickups.append({"pos": e.position, "kind": "ticket", "vel": Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60, 200), "t": 0.0})
	if randf() < 0.07:
		pickups.append({"pos": e.position, "kind": "hp", "vel": Vector2.RIGHT.rotated(randf() * TAU) * 120.0, "t": 0.0})
	if e.elite:
		pickups.append({"pos": e.position, "kind": "item", "vel": Vector2.ZERO, "t": 0.0, "item": Data.roll_item(1)})
	if hero.vamp > 0:
		hero.heal(float(hero.vamp))
	if hero.boom > 0:
		var bd: float = 14.0 * hero.boom
		for o in enemies:
			if o != e and not o.dead and (o.position - e.position).length() < 100.0:
				o.hit(bd)
		_burst(e.position, ORANGE, 16, 300.0, 5.0)
		sfx.play("boom", 1.2, -6.0)
	if is_boss:
		boss = null
	enemy_killed.emit(e)
	enemies.erase(e)
	e.queue_free()
	if energy >= energy_need and not cleared:
		energy_full.emit()

func spawn_bullet(pos: Vector2, vel: Vector2, dmg: float, hero_shot: bool, pierce: int, bounce: int, color: Color, radius: float) -> void:
	var b := Bullet.new()
	b.position = pos
	b.vel = vel
	b.dmg = dmg
	b.hero_shot = hero_shot
	b.pierce = pierce
	b.bounce = bounce
	b.color = color
	b.radius = radius
	b.life = 1.4 if hero_shot else 3.2
	shots.add_child(b)
	bullets.append(b)
	fired.emit(pos, vel, hero_shot, color, radius)
	if not hero_shot:
		sfx.play("eshoot", randf_range(0.9, 1.1), -14.0)

## Direction corrigée pour contourner les caisses : si le point devant est bloqué, on tourne.
func steer(pos: Vector2, dir: Vector2, r: float) -> Vector2:
	if dir.length() < 0.01:
		return dir
	var probe := r * 2.2
	if not _blocked(pos + dir * probe, r):
		return dir
	for a in [0.9, -0.9, 1.6, -1.6, 2.4, -2.4]:
		var d2 := dir.rotated(a)
		if not _blocked(pos + d2 * probe, r):
			return d2
	return -dir

func _blocked(p: Vector2, r: float) -> bool:
	if p.x < WALL + r or p.x > W - WALL - r or p.y < TOP + r or p.y > H - WALL - r:
		return true
	for o in obstacles:
		if o.grow(r * 0.8).has_point(p):
			return true
	return false

func nearest_enemy(pos: Vector2, max_d: float) -> Node2D:
	var best: Node2D = null
	var bd := max_d
	for e in enemies:
		if e.dead:
			continue
		var d: float = (e.position - pos).length() - e.radius
		if d < bd:
			bd = d
			best = e
	return best

# ---------------------------------------------------------------- collisions
func _clamp_circle(n: Node2D, r: float) -> void:
	n.position.x = clampf(n.position.x, WALL + r, W - WALL - r)
	n.position.y = clampf(n.position.y, TOP + r, H - WALL - r)
	for o in obstacles:
		var cx := clampf(n.position.x, o.position.x, o.end.x)
		var cy := clampf(n.position.y, o.position.y, o.end.y)
		var d := n.position - Vector2(cx, cy)
		var l := d.length()
		if l < r:
			if l < 0.001:
				d = Vector2(0, -1)
				l = 1.0
			n.position += d / l * (r - l)

## Vrai si le projectile doit disparaître.
func _bullet_walls(b: Node2D) -> bool:
	var p: Vector2 = b.position
	var hit := false
	if p.x < WALL or p.x > W - WALL:
		if b.bounce > 0:
			b.vel.x = -b.vel.x
			b.bounce -= 1
			b.position.x = clampf(p.x, WALL + 1, W - WALL - 1)
		else:
			hit = true
	if p.y < TOP or p.y > H - WALL:
		if b.bounce > 0:
			b.vel.y = -b.vel.y
			b.bounce -= 1
			b.position.y = clampf(p.y, TOP + 1, H - WALL - 1)
		else:
			hit = true
	if hit:
		_burst(p, b.color, 3, 100.0, 2.0)
		bullet_blocked.emit(p, b.color)
		return true
	for o in obstacles:
		if o.has_point(p):
			if b.bounce > 0:
				b.bounce -= 1
				# côté d'entrée : on compare les pénétrations
				var dx := minf(p.x - o.position.x, o.end.x - p.x)
				var dy := minf(p.y - o.position.y, o.end.y - p.y)
				if dx < dy:
					b.vel.x = -b.vel.x
					b.position.x += signf(b.vel.x) * (dx + 2.0)
				else:
					b.vel.y = -b.vel.y
					b.position.y += signf(b.vel.y) * (dy + 2.0)
				return false
			_burst(p, b.color, 3, 100.0, 2.0)
			bullet_blocked.emit(p, b.color)
			return true
	return false

# ---------------------------------------------------------------- effets et dessin
func _burst(pos: Vector2, col: Color, n: int, spd: float, r: float) -> void:
	for i in range(n):
		particles.append({"pos": pos, "vel": Vector2.RIGHT.rotated(randf() * TAU) * randf_range(spd * 0.3, spd), "life": randf_range(0.25, 0.5), "max": 0.5, "col": col, "r": r})

func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), BG)
	# alcôve du vaisseau (haut) : quai sombre, vaisseau garé, garde-corps
	draw_rect(Rect2(WALL, WALL, W - 2 * WALL, TOP - WALL), Color("#0B1A36"))
	draw_texture_rect(Art.SHIP, Rect2(W * 0.5 - 450, -40, 900, 420), false, Color(0.8, 0.85, 0.95))
	for k in range(int((W - 2 * WALL) / 60)):
		draw_rect(Rect2(WALL + k * 60 + 10, TOP - 22, 40, 6), Color(ORANGE, 0.75))
	draw_rect(Rect2(WALL, TOP - 10, W - 2 * WALL, 10), Color("#2A3F6E"))
	draw_line(Vector2(WALL, TOP), Vector2(W - WALL, TOP), Color(CYAN, 0.7), 4.0)
	# sol : dalles métalliques
	draw_texture_rect(Art.FLOOR, Rect2(WALL, TOP, W - 2 * WALL, H - TOP - WALL), true)
	# lignes de guidage au sol
	draw_line(Vector2(WALL, (TOP + H) * 0.5), Vector2(W - WALL, (TOP + H) * 0.5), Color(CYAN, 0.14), 8.0)
	draw_line(Vector2(W * 0.5, TOP), Vector2(W * 0.5, H - WALL), Color(CYAN, 0.14), 8.0)
	for p in pads:
		draw_texture_rect(Art.PAD, Rect2(p - Vector2(70, 70), Vector2(140, 140)), false)
	# murs : plaques sombres, bandeau lumineux
	draw_rect(Rect2(0, 0, W, H), Color("#1B2B4D"), false, WALL * 2.0)
	draw_rect(Rect2(0, 0, W, H), Color("#0B0F1A"), false, 6.0)
	draw_rect(Rect2(WALL, WALL, W - 2 * WALL, H - 2 * WALL), Color(CYAN, 0.45), false, 3.0)
	for k in range(int(W / 200)):
		draw_rect(Rect2(k * 200 + 60, H - WALL + 8, 80, 8), Color(CYAN, 0.6))
		draw_rect(Rect2(k * 200 + 60, WALL - 16, 80, 8), Color(CYAN, 0.6))
	for k in range(int(H / 200)):
		draw_rect(Rect2(WALL - 16, k * 200 + 60, 8, 80), Color(CYAN, 0.6))
		draw_rect(Rect2(W - WALL + 8, k * 200 + 60, 8, 80), Color(CYAN, 0.6))
	# conteneurs : découpés en cellules à peu près carrées pour ne pas déformer le dessin
	for o in obstacles:
		var cols := maxi(1, int(round(o.size.x / 90.0)))
		var rows := maxi(1, int(round(o.size.y / 90.0)))
		var cw := o.size.x / cols
		var ch := o.size.y / rows
		for cx in range(cols):
			for cy in range(rows):
				draw_texture_rect(Art.CRATE, Rect2(o.position + Vector2(cx * cw, cy * ch), Vector2(cw, ch)), false)

func _draw_fx() -> void:
	# tourelles
	for tr in turrets:
		var p: Vector2 = tr["pos"]
		fxn.draw_circle(p, 22.0, OUTLINE)
		fxn.draw_circle(p, 18.0, Color("#3B5590"))
		fxn.draw_circle(p, 12.0, Color("#5673B5"))
		fxn.draw_line(p, p + Vector2.RIGHT.rotated(tr["ang"]) * 26.0, OUTLINE, 12.0)
		fxn.draw_line(p, p + Vector2.RIGHT.rotated(tr["ang"]) * 26.0, GOLD, 7.0)
		fxn.draw_circle(p, 5.0, GOLD)
	# drones alliés
	for al in allies:
		var p: Vector2 = hero.position + Vector2.RIGHT.rotated(al["ang"]) * 74.0
		fxn.draw_circle(p, 13.0, OUTLINE)
		fxn.draw_circle(p, 10.0, CYAN)
		fxn.draw_circle(p, 4.0, Color.WHITE)
	# ramassages
	for pk in pickups:
		var p: Vector2 = pk["pos"]
		match String(pk["kind"]):
			"ticket":
				fxn.draw_circle(p, 10.0, OUTLINE)
				fxn.draw_circle(p, 8.0, GOLD)
				fxn.draw_circle(p + Vector2(-2, -2), 3.0, Color("#FFE2A8"))
			"hp":
				fxn.draw_circle(p, 13.0, OUTLINE)
				fxn.draw_circle(p, 11.0, Color("#F4F1EA"))
				fxn.draw_rect(Rect2(p + Vector2(-7, -2), Vector2(14, 4)), RED)
				fxn.draw_rect(Rect2(p + Vector2(-2, -7), Vector2(4, 14)), RED)
			"item":
				var col: Color = Data.RARITY_COLORS[int(pk["item"]["rarity"])]
				var bob := sin(pk["t"] * 5.0) * 3.0
				fxn.draw_rect(Rect2(p + Vector2(-15, -15 + bob), Vector2(30, 30)), OUTLINE)
				fxn.draw_rect(Rect2(p + Vector2(-12, -12 + bob), Vector2(24, 24)), col)
				fxn.draw_rect(Rect2(p + Vector2(-12, -12 + bob), Vector2(24, 8)), Color(1, 1, 1, 0.35))
	# coffre
	if not chest.is_empty():
		var p: Vector2 = chest["pos"]
		var open: bool = chest["open"]
		fxn.draw_texture_rect(Art.CHEST, Rect2(p - Vector2(45, 38), Vector2(90, 75)), false, Color.WHITE if not open else Color(0.5, 0.5, 0.55))

func _draw_fxa() -> void:
	# halos (additifs) : coffre, objets, sas actifs, particules
	if not chest.is_empty() and not chest["open"]:
		var pulse := 0.5 + 0.5 * sin(elapsed * 4.0)
		_glow(fxa, chest["pos"], 90.0 + pulse * 16.0, Color(GOLD, 0.45))
	for pk in pickups:
		if String(pk["kind"]) == "item":
			var col: Color = Data.RARITY_COLORS[int(pk["item"]["rarity"])]
			_glow(fxa, pk["pos"], 70.0, Color(col, 0.6))
		elif String(pk["kind"]) == "ticket":
			_glow(fxa, pk["pos"], 26.0, Color(GOLD, 0.35))
	if not spawn_queue.is_empty():
		for p in pads:
			_glow(fxa, p, 120.0 + 20.0 * sin(elapsed * 6.0), Color(CYAN, 0.25))
	for pa in particles:
		var a: float = clampf(pa["life"] / pa["max"], 0.0, 1.0)
		_glow(fxa, pa["pos"], pa["r"] * 6.0 * (0.4 + a), Color(pa["col"], a * 0.9))

func _glow(on: Node2D, pos: Vector2, size: float, col: Color) -> void:
	on.draw_texture_rect(Art.GLOW, Rect2(pos - Vector2(size, size) * 0.5, Vector2(size, size)), false, col)
