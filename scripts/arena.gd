extends Node2D
## L'arène : une grande carte (plus grande que l'écran, caméra qui suit), des caisses en obstacles,
## des vagues d'ennemis par salle, les projectiles, les ramassages, le coffre de fin de salle,
## les tourelles et drones alliés des pouvoirs. Toute la simulation est ici, les entités ne font que se dessiner.

const Data = preload("res://scripts/data.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Bullet = preload("res://scripts/bullet.gd")

signal room_cleared
signal hero_died
signal energy_full
signal item_found(item: Dictionary)
signal wave_changed

const W := 2400.0
const H := 1400.0
const WALL := 36.0
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
var obstacles: Array[Rect2] = []
var pads: Array[Vector2] = []

var enemies: Array = []
var bullets: Array = []
var pickups: Array = []
var particles: Array = []
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

func _layout() -> void:
	obstacles.clear()
	_rng.seed = 7
	# caisses du hangar : quelques groupes, jamais au centre ni devant les sas
	var boxes := [
		Rect2(520, 300, 150, 110), Rect2(680, 300, 90, 90),
		Rect2(1700, 260, 140, 140), Rect2(1850, 330, 90, 70),
		Rect2(420, 950, 120, 120), Rect2(560, 1010, 160, 70),
		Rect2(1750, 980, 170, 100), Rect2(1680, 1090, 90, 90),
		Rect2(1120, 180, 160, 70), Rect2(1120, 1150, 160, 70),
		Rect2(300, 620, 80, 160), Rect2(2020, 620, 80, 160),
		Rect2(1000, 620, 70, 70), Rect2(1330, 710, 70, 70),
	]
	for b in boxes:
		obstacles.append(b)
	pads.clear()
	pads.append(Vector2(120, 120))
	pads.append(Vector2(W - 120, 120))
	pads.append(Vector2(120, H - 120))
	pads.append(Vector2(W - 120, H - 120))
	pads.append(Vector2(W * 0.5, 100))
	pads.append(Vector2(W * 0.5, H - 100))
	pads.append(Vector2(100, H * 0.5))
	pads.append(Vector2(W - 100, H * 0.5))

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
	chest = {}
	boss = null

func start_room(r: int, mod: String) -> void:
	room = r
	modifier = mod
	_clear_entities()
	hero.position = Vector2(W * 0.5, H * 0.5)
	hero.dead = false
	cam.position = hero.position
	cam.reset_smoothing()
	waves = Data.waves_for(r, mod)
	wave_i = -1
	wave_gap = 1.3
	spawn_queue = []
	running = true
	cleared = false
	hp_scale = 1.0 + (r - 1) * 0.13
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
				if (e.position - b.position).length() < e.radius + b.radius:
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

func _room_done() -> void:
	cleared = true
	var p := hero.position + Vector2(0, -140)
	p.x = clampf(p.x, 200, W - 200)
	p.y = clampf(p.y, 200, H - 200)
	chest = {"pos": p, "open": false}
	sfx.play("level", 1.2)
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
	if kind == "boss":
		pad = Vector2(W * 0.5, 160.0)
		boss = e
	e.position = pad + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	ents.add_child(e)
	enemies.append(e)
	_burst(e.position, CYAN, 8, 180.0, 3.0)

func boss_summon(pos: Vector2, n: int) -> void:
	for i in range(n):
		var e := Enemy.new()
		e.arena = self
		e.hero = hero
		e.setup("drone", false, hp_scale)
		e.position = pos + Vector2.RIGHT.rotated(TAU * i / n) * 90.0
		ents.add_child(e)
		enemies.append(e)
		_burst(e.position, RED, 8, 180.0, 3.0)
	sfx.play("portal", 0.8)

func on_enemy_died(e: Node2D) -> void:
	kills += 1
	energy += float(e.energy) * hero.energy_mult
	sfx.play("kill", randf_range(0.9, 1.2), -4.0)
	_burst(e.position, RED if e.kind != "boss" else Color("#F23CB8"), 14 if e.kind != "boss" else 60, 220.0, 4.0)
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
	if e.kind == "boss":
		boss = null
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
	if p.x < WALL + r or p.x > W - WALL - r or p.y < WALL + r or p.y > H - WALL - r:
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
	n.position.y = clampf(n.position.y, WALL + r, H - WALL - r)
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
	if p.y < WALL or p.y > H - WALL:
		if b.bounce > 0:
			b.vel.y = -b.vel.y
			b.bounce -= 1
			b.position.y = clampf(p.y, WALL + 1, H - WALL - 1)
		else:
			hit = true
	if hit:
		_burst(p, b.color, 3, 100.0, 2.0)
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
			return true
	return false

# ---------------------------------------------------------------- effets et dessin
func _burst(pos: Vector2, col: Color, n: int, spd: float, r: float) -> void:
	for i in range(n):
		particles.append({"pos": pos, "vel": Vector2.RIGHT.rotated(randf() * TAU) * randf_range(spd * 0.3, spd), "life": randf_range(0.25, 0.5), "max": 0.5, "col": col, "r": r})

func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), BG)
	draw_rect(Rect2(WALL, WALL, W - 2 * WALL, H - 2 * WALL), FLOOR)
	_rng.seed = 42
	for i in range(28):
		var px := _rng.randf_range(WALL, W - 300)
		var py := _rng.randf_range(WALL, H - 220)
		draw_rect(Rect2(px, py, _rng.randf_range(120, 300), _rng.randf_range(80, 220)), Color("#14284F"))
	var x := WALL
	while x < W:
		draw_line(Vector2(x, WALL), Vector2(x, H - WALL), GRID, 2.0)
		x += 100.0
	var y := WALL
	while y < H:
		draw_line(Vector2(WALL, y), Vector2(W - WALL, y), GRID, 2.0)
		y += 100.0
	# lignes de guidage cyan au sol
	draw_line(Vector2(WALL, H * 0.5), Vector2(W - WALL, H * 0.5), Color(CYAN, 0.12), 6.0)
	draw_line(Vector2(W * 0.5, WALL), Vector2(W * 0.5, H - WALL), Color(CYAN, 0.12), 6.0)
	# murs
	draw_rect(Rect2(0, 0, W, H), Color("#1B2B4D"), false, WALL * 2.0)
	draw_rect(Rect2(WALL, WALL, W - 2 * WALL, H - 2 * WALL), Color(CYAN, 0.5), false, 3.0)
	# bandes de danger aux angles
	for c in [Vector2(WALL, WALL), Vector2(W - WALL - 140, WALL), Vector2(WALL, H - WALL - 14), Vector2(W - WALL - 140, H - WALL - 14)]:
		for k in range(7):
			draw_rect(Rect2(c.x + k * 20, c.y, 10, 14), Color(ORANGE, 0.8))
	# sas d'apparition
	for p in pads:
		draw_circle(p, 46.0, Color(CYAN, 0.08))
		draw_arc(p, 40.0, 0.0, TAU, 32, Color(CYAN, 0.5), 3.0, true)
		draw_arc(p, 24.0, 0.0, TAU, 24, Color(CYAN, 0.3), 2.0, true)
	# caisses
	for o in obstacles:
		draw_rect(o.grow(4.0), OUTLINE)
		draw_rect(o, CRATE)
		draw_rect(Rect2(o.position, Vector2(o.size.x, o.size.y * 0.42)), CRATE_TOP)
		draw_rect(Rect2(o.position + Vector2(8, 8), Vector2(o.size.x - 16, 6)), Color(ORANGE, 0.7))
		draw_rect(o, Color(CYAN, 0.25), false, 2.0)

func _draw_fx() -> void:
	# tourelles
	for tr in turrets:
		var p: Vector2 = tr["pos"]
		fxn.draw_circle(p, 20.0, OUTLINE)
		fxn.draw_circle(p, 16.0, Color("#3B5590"))
		fxn.draw_line(p, p + Vector2.RIGHT.rotated(tr["ang"]) * 24.0, OUTLINE, 10.0)
		fxn.draw_line(p, p + Vector2.RIGHT.rotated(tr["ang"]) * 24.0, GOLD, 6.0)
		fxn.draw_circle(p, 5.0, GOLD)
	# drones alliés
	for al in allies:
		var p: Vector2 = hero.position + Vector2.RIGHT.rotated(al["ang"]) * 74.0
		fxn.draw_circle(p, 12.0, OUTLINE)
		fxn.draw_circle(p, 9.0, CYAN)
		fxn.draw_circle(p, 3.5, Color.WHITE)
	# ramassages
	for pk in pickups:
		var p: Vector2 = pk["pos"]
		match String(pk["kind"]):
			"ticket":
				fxn.draw_circle(p, 9.0, OUTLINE)
				fxn.draw_circle(p, 7.0, GOLD)
				fxn.draw_circle(p + Vector2(-2, -2), 2.5, Color.WHITE)
			"hp":
				fxn.draw_circle(p, 12.0, OUTLINE)
				fxn.draw_circle(p, 10.0, Color("#F4F1EA"))
				fxn.draw_rect(Rect2(p + Vector2(-6, -2), Vector2(12, 4)), RED)
				fxn.draw_rect(Rect2(p + Vector2(-2, -6), Vector2(4, 12)), RED)
			"item":
				var col: Color = Data.RARITY_COLORS[int(pk["item"]["rarity"])]
				var bob := sin(pk["t"] * 5.0) * 3.0
				fxn.draw_circle(p, 26.0, Color(col, 0.18))
				fxn.draw_rect(Rect2(p + Vector2(-14, -14 + bob), Vector2(28, 28)), OUTLINE)
				fxn.draw_rect(Rect2(p + Vector2(-11, -11 + bob), Vector2(22, 22)), col)
	# coffre
	if not chest.is_empty():
		var p: Vector2 = chest["pos"]
		var open: bool = chest["open"]
		var pulse := 0.5 + 0.5 * sin(elapsed * 4.0)
		if not open:
			fxn.draw_circle(p, 50.0 + pulse * 8.0, Color(GOLD, 0.12))
		fxn.draw_rect(Rect2(p + Vector2(-30, -22), Vector2(60, 44)), OUTLINE)
		fxn.draw_rect(Rect2(p + Vector2(-26, -18), Vector2(52, 36)), Color("#3B5590") if not open else Color("#2A3F6E"))
		fxn.draw_rect(Rect2(p + Vector2(-26, -18), Vector2(52, 14)), GOLD if not open else Color("#8A6A2E"))
		fxn.draw_circle(p + Vector2(0, 2), 5.0, GOLD if not open else Color("#8A6A2E"))
	# particules
	for pa in particles:
		var a: float = clampf(pa["life"] / pa["max"], 0.0, 1.0)
		fxn.draw_circle(pa["pos"], pa["r"] * (0.5 + a), Color(pa["col"], a))
