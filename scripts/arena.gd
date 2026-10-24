extends Node2D
## L'arène : une grande carte (plus grande que l'écran, caméra qui suit), des caisses en obstacles,
## des vagues d'ennemis par salle, les projectiles, les ramassages, le coffre de fin de salle,
## et les effets des pouvoirs (tourelles, drones, lames, missiles, mines, scies, nuages, feu, foudre, gel, ruée).
## Toute la simulation est ici, les entités ne font que se dessiner ; view3d.gd et scripts/fx/power_fx.gd suivent
## les signaux et lisent les listes (missiles, mines, scies…) pour le rendu.

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
signal bonus_choice  # élite abattue : un pouvoir de plus à choisir
## Effet de pouvoir pour le rendu (power_fx.gd) : "arc" {pts, col}, "strike" {pos}, "blast" {pos, r, col, kind},
## "pulse" {pos, r, col}, "meteor_call" {pos, delay}, "dash" {from, dir}, "dash_end" {pos}, "freeze" {pos, r},
## "cloud" {pos, r, life}, "fire" {pos, r, life}, "mine" {pos}, "revive" {pos}.
signal power_event(kind: String, info: Dictionary)

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
const FIRE := Color("#FF8A3C")
const ICE := Color("#9FDCFF")
const SHOCK := Color("#FFE45C")
const VENOM := Color("#8BE05A")
const GRID_CELL := 128.0

var sfx: Node
var hero: Node2D
var joy: Node
var cam: Camera2D
var ents: Node2D
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
# pouvoirs : entités simulées ici, rendues par power_fx.gd
var missiles: Array = []  # {pos, vel, t, dmg, target}
var mines: Array = []  # {pos, t, dmg}
var saws: Array = []  # {pos, vel, t, left, hit, target, dmg}
var minis: Array = []  # mini-drones kamikazes de la Nuée : {pos, vel, t, target}
var clouds: Array = []  # nuages toxiques : {pos, r, t, life, dps}
var fires: Array = []  # flaques de feu : {pos, r, t, life, dps}
var blade_pos := PackedVector2Array()  # lames orbitales, recalculées à chaque image
var blade_ang := 0.0
var _later: Array = []  # effets différés : {t, kind, pos, ...} (météores, morts qui explosent)
var _pt := {}  # minuteries des pouvoirs périodiques
var _dash_hits: Array = []
var _trail_last := Vector2.ZERO
var _boom_sfx := 0.0
var _grid := {}  # ennemis rangés par case (collisions des tirs et des zones)

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
	hero.dashed.connect(_on_dash)
	hero.dash_ended.connect(_on_dash_end)
	hero.shield_broke.connect(func(): pulse(hero.position, 260.0, hero.dmg * 2.0, Color("#5AA8FF")))
	hero.revived.connect(func():
		pulse(hero.position, 340.0, hero.dmg * 4.0, GOLD)
		power_event.emit("revive", {"pos": hero.position}))
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
	energy_level = 0
	energy_need = need_for(0)
	elapsed = 0.0
	turrets.clear()
	allies.clear()

func _clear_entities() -> void:
	for e in enemies:
		e.queue_free()
	enemies.clear()
	bullets.clear()
	pickups.clear()
	particles.clear()
	shells.clear()
	doors.clear()
	waves_fx.clear()
	chest = {}
	boss = null
	missiles.clear()
	mines.clear()
	saws.clear()
	minis.clear()
	clouds.clear()
	fires.clear()
	blade_pos.clear()
	_later.clear()
	_pt.clear()
	_grid.clear()

func start_room(r: int, mod: String) -> void:
	room = r
	Music.play(("boss" if r >= Data.ROOMS else "combat") + String(Data.WORLDS[Data.world]["music"]))
	Music.ambience(Data.world_id())
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
	allies.clear()
	sync_machines()
	_trail_last = hero.position
	queue_redraw()

## Tourelles et drones alliés : autant que le héros en a (après un choix de pouvoir ou en début de salle).
func sync_machines() -> void:
	while turrets.size() < hero.turrets:
		var i := turrets.size()
		var p: Vector2 = hero.position + Vector2.RIGHT.rotated(TAU * i / 3.0 + 0.5 + randf() * 0.3) * 110.0
		p.x = clampf(p.x, WALL + 40.0, W - WALL - 40.0)
		p.y = clampf(p.y, TOP + 40.0, H - WALL - 40.0)
		turrets.append({"pos": p, "cd": 0.0, "ang": 0.0, "mcd": 0.6})
	while allies.size() < hero.ally:
		allies.append({"ang": TAU * allies.size() / maxf(1.0, float(hero.ally)), "cd": 0.0})

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
	energy_need = need_for(energy_level)

## Énergie demandée pour le choix n° `level` : barre courte au début (les premiers choix arrivent vite),
## qui s'allonge ensuite.
static func need_for(level: int) -> float:
	return 4.0 + 3.0 * level + 0.6 * level * level

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
	# héros (le bouton d'esquive lance la ruée)
	if joy.has_method("take_dash") and joy.take_dash():
		hero.try_dash(joy.move)
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
	_grid_build()
	_tick_status(dt)
	# projectiles (objets légers, déplacés ici)
	var dead_bullets := []
	for b in bullets:
		b.position += b.vel * dt
		b.life -= dt
		if b.life <= 0.0:
			dead_bullets.append(b)
			continue
		if _bullet_walls(b):
			dead_bullets.append(b)
			continue
		if b.hero_shot:
			for e in _near(b.position, b.radius + 80.0):
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
					if _bullet_hit(b, e):
						dead_bullets.append(b)
					break
		else:
			if (hero.position - b.position).length() < hero.radius + b.radius:
				if hero.dodge_t <= 0.0 and hero.invuln <= 0.0 and randf() < [0.0, 0.25, 0.45][hero.lv("deflect")]:
					_deflect(b)
					continue
				if hero.take_damage(b.dmg):
					sfx.play("hurt", 1.0)
				dead_bullets.append(b)
	for b in dead_bullets:
		bullets.erase(b)
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
	# machines et pouvoirs
	_tick_machines(dt)
	_tick_powers(dt)
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
	# jamais dans une caisse : on le rapproche de Jo jusqu'à une place libre
	for k in range(12):
		if not _blocked(p, 40.0):
			break
		p = p.lerp(hero.position, 0.2) if k < 6 else p + Vector2.RIGHT.rotated(k) * 60.0
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
		bonus_choice.emit()
	if hero.vamp > 0:
		hero.heal(0.5 * hero.vamp)
	if hero.lv("impulse") > 0:
		hero.dash_stock = minf(float(hero.dash_max), hero.dash_stock + [0.0, 0.25, 0.4][hero.lv("impulse")] / hero.dash_cd)
	# effets de mort des pouvoirs (détonation, venin, contagion, éclats de glace, nuée) : une image plus tard,
	# pour que les chaînes d'explosions se lisent en cascade
	if not is_boss:
		_later.append({"t": 0.06, "kind": "death", "pos": e.position, "r": e.radius, "burn": e.burn_t > 0.0,
			"poison": e.poison_t > 0.0, "frozen": e.freeze_t > 0.0, "bomber": e.kind == "bomber"})
	if is_boss:
		boss = null
	enemy_killed.emit(e)
	enemies.erase(e)
	e.queue_free()
	if energy >= energy_need and not cleared:
		energy_full.emit()

func spawn_bullet(pos: Vector2, vel: Vector2, dmg: float, hero_shot: bool, pierce: int, bounce: int, color: Color, radius: float, elem: int = 0, src: int = 0, hop: int = 0, crit: bool = false) -> RefCounted:
	var b := Bullet.new()
	b.position = pos
	b.vel = vel
	b.dmg = dmg
	b.hero_shot = hero_shot
	b.pierce = pierce
	b.bounce = bounce
	b.color = color
	b.radius = radius
	b.elem = elem
	b.src = src
	b.hop = hop
	b.crit = crit
	b.life = 1.4 if hero_shot else 3.2
	bullets.append(b)
	fired.emit(pos, vel, hero_shot, color, radius)
	if not hero_shot:
		sfx.play("eshoot", randf_range(0.9, 1.1), -14.0)
	return b

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

# ---------------------------------------------------------------- pouvoirs
## Grille des ennemis (cases de GRID_CELL px) : les tirs et les zones ne testent que les ennemis proches.
func _grid_build() -> void:
	_grid.clear()
	for e in enemies:
		var k := _cell(e.position)
		if _grid.has(k):
			(_grid[k] as Array).append(e)
		else:
			_grid[k] = [e]

func _cell(p: Vector2) -> int:
	return int(floorf(p.x / GRID_CELL)) * 1000 + int(floorf(p.y / GRID_CELL))

## Ennemis rangés dans les cases qui touchent le disque (`pos`, `reach`) : à affiner par la vraie distance.
func _near(pos: Vector2, reach: float) -> Array:
	var x0 := int(floorf((pos.x - reach) / GRID_CELL))
	var x1 := int(floorf((pos.x + reach) / GRID_CELL))
	var y0 := int(floorf((pos.y - reach) / GRID_CELL))
	var y1 := int(floorf((pos.y + reach) / GRID_CELL))
	var out := []
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var k := cx * 1000 + cy
			if _grid.has(k):
				for e in _grid[k]:
					# la grille date du début de l'image : un ennemi libéré entre-temps est sauté
					if is_instance_valid(e):
						out.append(e)
	return out

## Dégâts d'un pouvoir sur un ennemi ; `show` : chiffre et étincelles comme un tir.
func hurt(e: Node2D, d: float, show: bool = false, crit: bool = false) -> void:
	if e == null or e.dead:
		return
	if e.freeze_t > 0.0 and hero.has_evo("blizzard"):
		d *= 2.0
	if show:
		enemy_hit.emit(e, e.position, d, crit)
	e.hit(d)

## Un tir de Jo (ou d'une machine) touche `e`. Vrai si le tir s'arrête là.
func _bullet_hit(b, e: Node2D) -> bool:
	var d: float = b.dmg
	if e.freeze_t > 0.0 and hero.has_evo("blizzard"):
		d *= 2.0
	enemy_hit.emit(e, b.position, d, b.crit)
	e.hit(d)
	sfx.play("hit", randf_range(0.8, 1.2), -10.0)
	_burst(b.position, b.color, 4, 140.0, 2.0)
	if b.elem != 0 and not e.dead:
		if b.elem & 1:
			ignite(e, hero.dmg * (0.35 + 0.25 * (hero.lv("fire") - 1)), 3.0)
		if b.elem & 2:
			frostbite(e)
	if b.elem & 4 and randf() < 0.25:
		chain(e, b.dmg * 0.7, 1 + hero.lv("shock"), SHOCK)
	if b.src == 2:
		chain(e, b.dmg * 0.8, 2, SHOCK)
	if b.src == 0 and hero.lv("giant") > 0 and not e.dead and not e.kind.begins_with("boss"):
		e.push += b.vel.normalized() * 110.0 * hero.lv("giant")
	if b.pierce > 0:
		b.pierce -= 1
		b.hits.append(e)
		return false
	if b.hop > 0:
		# ricochet vers l'ennemi suivant
		b.hits.append(e)
		var best: Node2D = null
		var bd := 340.0
		for o in _near(b.position, 340.0):
			if o.dead or o in b.hits:
				continue
			var dd: float = (o.position - b.position).length()
			if dd < bd:
				bd = dd
				best = o
		if best != null:
			b.hop -= 1
			b.vel = (best.position - b.position).normalized() * b.vel.length()
			b.life = maxf(b.life, 0.6)
			return false
	return true

## Tir ennemi renvoyé par le Déflecteur : il repart vers l'ennemi le plus proche, aux couleurs de Jo.
func _deflect(b) -> void:
	var e: Node2D = nearest_enemy(hero.position, 700.0)
	var d: Vector2 = (e.position - hero.position).normalized() if e != null else -b.vel.normalized()
	b.hero_shot = true
	b.vel = d * 760.0
	b.position = hero.position + d * 26.0
	b.dmg = hero.dmg * 2.0
	b.color = Color("#7FD8FF")
	b.radius = 6.0
	b.life = 1.4
	b.src = 1
	b.hits = []
	bullet_blocked.emit(hero.position + d * 24.0, Color("#5AA8FF"))
	sfx.play("hit", 1.6, -6.0)

func ignite(e: Node2D, dps: float, t: float) -> void:
	if e.dead:
		return
	e.burn_dps = maxf(e.burn_dps if e.burn_t > 0.0 else 0.0, dps)
	e.burn_t = maxf(e.burn_t, t)

## Balle givrante : ralenti, et gel au bout de quelques touches.
func frostbite(e: Node2D) -> void:
	var f := maxi(1, hero.lv("frost"))
	e.chill_t = maxf(e.chill_t, 1.6)
	e.frost += 1
	if e.frost >= 7 - f:
		e.frost = 0
		freeze(e, 0.7 + 0.3 * f)

func freeze(e: Node2D, t: float) -> void:
	if e.dead:
		return
	if e.kind.begins_with("boss"):
		t *= 0.25
	elif e.elite:
		t *= 0.55
	if e.freeze_t <= 0.0:
		power_event.emit("freeze", {"pos": e.position, "r": e.radius})
	e.freeze_t = maxf(e.freeze_t, t)
	e.chill_t = maxf(e.chill_t, t + 1.0)

## Arc de foudre : saute d'ennemi en ennemi depuis `from_e` (déjà touché), `jumps` fois.
func chain(from_e: Node2D, d: float, jumps: int, col: Color) -> void:
	var pts := PackedVector2Array([from_e.position])
	var cur: Vector2 = from_e.position
	var seen := [from_e]
	for j in range(jumps):
		var best: Node2D = null
		var bd := 270.0
		for o in _near(cur, 270.0):
			if o.dead or o in seen:
				continue
			var dd: float = (o.position - cur).length()
			if dd < bd:
				bd = dd
				best = o
		if best == null:
			break
		seen.append(best)
		pts.append(best.position)
		cur = best.position
		hurt(best, d, true)
	if pts.size() > 1:
		power_event.emit("arc", {"pts": pts, "col": col})

## Explosion d'un pouvoir : ne blesse que les ennemis. `burn` > 0 : enflamme (dégâts par seconde).
func blast(pos: Vector2, r: float, d: float, col: Color, kind: String = "blast", burn: float = 0.0) -> void:
	for o in _near(pos, r + 80.0):
		if not o.dead and (o.position - pos).length() < r + o.radius:
			hurt(o, d)
			if burn > 0.0:
				ignite(o, burn, 3.0)
	power_event.emit("blast", {"pos": pos, "r": r, "col": col, "kind": kind})
	if elapsed - _boom_sfx > 0.07:
		_boom_sfx = elapsed
		sfx.play("boom", randf_range(1.1, 1.4) if r < 120.0 else 0.9, -8.0 if r < 120.0 else -4.0)
	if r >= 140.0:
		shake_t = maxf(shake_t, 0.1)

## Onde de choc de Jo : repousse, blesse, efface les tirs ennemis dans le rayon.
func pulse(pos: Vector2, r: float, d: float, col: Color) -> void:
	for o in _near(pos, r + 80.0):
		if o.dead:
			continue
		var v: Vector2 = o.position - pos
		if v.length() < r + o.radius:
			hurt(o, d, true)
			if not o.kind.begins_with("boss"):
				o.push += v.normalized() * (700.0 if not o.elite else 380.0)
	var gone := []
	for b in bullets:
		if not b.hero_shot and (b.position - pos).length() < r:
			gone.append(b)
	for b in gone:
		bullets.erase(b)
	power_event.emit("pulse", {"pos": pos, "r": r, "col": col})
	sfx.play("boom", 0.75, -5.0)
	shake_t = maxf(shake_t, 0.12)

## Contact d'un ennemi au corps à corps (Épines).
func on_contact(e: Node2D) -> void:
	var th: int = hero.lv("thorns")
	if th <= 0 or e.dead:
		return
	hurt(e, hero.dmg * (4.0 + 3.0 * (th - 1)), true)
	if not e.dead and not e.kind.begins_with("boss"):
		e.push += (e.position - hero.position).normalized() * 520.0
	power_event.emit("blast", {"pos": hero.position + (e.position - hero.position) * 0.5, "r": 40.0, "col": Color("#5AA8FF"), "kind": "thorns"})

## États des ennemis : brûlure, nuages, flaques de feu, aura glaciale.
func _tick_status(dt: float) -> void:
	for e in enemies.duplicate():
		if e.dead:
			continue
		if e.burn_t > 0.0:
			e.burn_t -= dt
			e.hit(e.burn_dps * dt)
	var i := 0
	while i < clouds.size():
		var c: Dictionary = clouds[i]
		c["t"] += dt
		if c["t"] >= c["life"]:
			clouds.remove_at(i)
			continue
		for e in _near(c["pos"], c["r"] + 80.0):
			if not e.dead and (e.position - c["pos"]).length() < c["r"] + e.radius:
				e.poison_t = 0.3
				e.hit(c["dps"] * dt)
		i += 1
	i = 0
	while i < fires.size():
		var f: Dictionary = fires[i]
		f["t"] += dt
		if f["t"] >= f["life"]:
			fires.remove_at(i)
			continue
		for e in _near(f["pos"], f["r"] + 80.0):
			if not e.dead and (e.position - f["pos"]).length() < f["r"] + e.radius:
				ignite(e, f["dps"], 1.5)
		i += 1
	var au: int = hero.lv("aura")
	if au > 0:
		var ar := aura_radius()
		var tick := false
		_pt["aura"] = float(_pt.get("aura", 0.0)) + dt
		if _pt["aura"] >= 0.5:
			_pt["aura"] = 0.0
			tick = au >= 2
		var bliz := false
		if hero.has_evo("blizzard"):
			_pt["bliz"] = float(_pt.get("bliz", 0.0)) + dt
			if _pt["bliz"] >= 3.0:
				_pt["bliz"] = 0.0
				bliz = true
				power_event.emit("pulse", {"pos": hero.position, "r": ar, "col": ICE})
		for e in _near(hero.position, ar + 80.0):
			if e.dead or (e.position - hero.position).length() > ar + e.radius:
				continue
			e.chill_t = maxf(e.chill_t, 0.35)
			if tick:
				frostbite(e)
			if bliz:
				freeze(e, 1.4)

func aura_radius() -> float:
	return 150.0 + 45.0 * hero.lv("aura")

## Tourelles, drones, lames orbitales, missiles, mines, scies, mini-drones.
func _tick_machines(dt: float) -> void:
	var mr: float = hero.mach_rate
	var md: float = hero.mach_dmg
	for tr in turrets:
		tr["cd"] -= dt
		var e: Node2D = nearest_enemy(tr["pos"], 440.0)
		if e != null:
			tr["ang"] = (e.position - tr["pos"]).angle()
			if tr["cd"] <= 0.0:
				tr["cd"] = 0.36 / mr
				var d: Vector2 = (e.position - tr["pos"]).normalized()
				spawn_bullet(tr["pos"] + d * 22.0, d * 700.0, hero.dmg * 0.55 * md, true, 0, 0, GOLD, 4.0, 0, 1)
			if hero.has_evo("artillerie"):
				tr["mcd"] = float(tr.get("mcd", 1.0)) - dt
				if tr["mcd"] <= 0.0:
					tr["mcd"] = 1.3 / mr
					_launch_missile(tr["pos"], Vector2.RIGHT.rotated(tr["ang"]))
	var essaim: bool = hero.has_evo("essaim")
	for al in allies:
		al["ang"] += dt * 2.2
		al["cd"] -= dt
		var p: Vector2 = hero.position + Vector2.RIGHT.rotated(al["ang"]) * 74.0
		var e: Node2D = nearest_enemy(p, 420.0)
		if e != null and al["cd"] <= 0.0:
			al["cd"] = 0.5 / mr
			var d: Vector2 = (e.position - p).normalized()
			spawn_bullet(p + d * 14.0, d * 700.0, hero.dmg * 0.6 * md, true, 0, 0, SHOCK if essaim else CYAN, 4.5 if essaim else 4.0, 0, 2 if essaim else 1)
	# lames orbitales
	blade_pos.clear()
	var nb: int = blade_count()
	if nb > 0:
		var storm: bool = hero.has_evo("moulinette")
		blade_ang += dt * (5.2 if storm else 4.2)
		var rr := blade_radius()
		for k in range(nb):
			var p: Vector2 = hero.position + Vector2.RIGHT.rotated(blade_ang + TAU * k / nb) * rr
			blade_pos.append(p)
			for e in _near(p, 100.0):
				if e.dead or e.touch_cd > 0.0 or (e.position - p).length() > e.radius + 20.0:
					continue
				hurt(e, hero.dmg * 1.1 * md, true)
				e.touch_cd = 0.3 / mr
				if not e.dead and not e.kind.begins_with("boss"):
					e.push += (e.position - hero.position).normalized() * 160.0
			if storm:
				var cut := []
				for b in bullets:
					if not b.hero_shot and (b.position - p).length() < 26.0:
						cut.append(b)
				for b in cut:
					bullets.erase(b)
					bullet_blocked.emit(b.position, b.color)
	# missiles
	var ml: int = hero.lv("missile")
	if ml > 0:
		_pt["missile"] = float(_pt.get("missile", 0.0)) + dt * mr
		if _pt["missile"] >= 2.0 and nearest_enemy(hero.position, 900.0) != null:
			_pt["missile"] = 0.0
			var n := (1 + ml) * (2 if hero.has_evo("artillerie") else 1)
			for k in range(n):
				_launch_missile(hero.position, Vector2.RIGHT.rotated(TAU * k / n + randf() * 0.5))
	var i := 0
	while i < missiles.size():
		var m: Dictionary = missiles[i]
		m["t"] += dt
		var tg = m["target"]
		if tg == null or not is_instance_valid(tg) or tg.dead:
			tg = nearest_enemy(m["pos"], 900.0)
			m["target"] = tg
		var spd := minf(640.0, 240.0 + m["t"] * 900.0)
		if tg != null:
			var want: Vector2 = (tg.position - m["pos"]).normalized()
			m["vel"] = (m["vel"] as Vector2).normalized().slerp(want, clampf(dt * 5.0, 0.0, 1.0)) * spd
		else:
			m["vel"] = (m["vel"] as Vector2).normalized() * spd
		m["pos"] += m["vel"] * dt
		var boom: bool = m["t"] > 3.0 or _blocked(m["pos"], 4.0)
		if tg != null and (tg.position - m["pos"]).length() < tg.radius + 12.0:
			boom = true
		if boom:
			blast(m["pos"], 72.0, m["dmg"], Color("#FFB347"), "missile")
			missiles.remove_at(i)
			continue
		i += 1
	# mines : semées en marchant
	var mi: int = hero.lv("mine")
	if mi > 0 and hero.moving:
		_pt["mine"] = float(_pt.get("mine", 0.0)) + dt
		if _pt["mine"] >= [0.0, 1.6, 1.3, 1.0][mi]:
			_pt["mine"] = 0.0
			mines.append({"pos": hero.position, "t": 0.0, "dmg": hero.dmg * 3.0 * md})
			if mines.size() > 10:
				mines.remove_at(0)
	i = 0
	while i < mines.size():
		var mn: Dictionary = mines[i]
		mn["t"] += dt
		var go: bool = mn["t"] > 25.0
		if mn["t"] > 0.4 and not go:
			for e in _near(mn["pos"], 120.0):
				if not e.dead and (e.position - mn["pos"]).length() < e.radius + 30.0:
					go = true
					break
		if go:
			blast(mn["pos"], 100.0, mn["dmg"], ORANGE, "mine")
			mines.remove_at(i)
			continue
		i += 1
	# scies volantes
	var sl: int = hero.lv("saw")
	if sl > 0:
		_pt["saw"] = float(_pt.get("saw", 0.0)) + dt * mr
		if _pt["saw"] >= 3.0:
			var first: Node2D = nearest_enemy(hero.position, 700.0)
			if first != null:
				_pt["saw"] = 0.0
				for k in range(sl):
					var d: Vector2 = (first.position - hero.position).normalized().rotated((k - (sl - 1) * 0.5) * 0.6)
					saws.append({"pos": hero.position + d * 30.0, "vel": d * 760.0, "t": 0.0, "left": 6, "hit": [], "target": first if k == 0 else null, "dmg": hero.dmg * 2.5 * md})
	i = 0
	while i < saws.size():
		var sw: Dictionary = saws[i]
		sw["t"] += dt
		var tg = sw["target"]
		if tg != null and (not is_instance_valid(tg) or tg.dead):
			tg = null
		if tg != null:
			sw["vel"] = (tg.position - sw["pos"]).normalized() * 760.0
		sw["pos"] += sw["vel"] * dt
		# rebond sur les murs
		var sp: Vector2 = sw["pos"]
		var sv: Vector2 = sw["vel"]
		if sp.x < WALL + 10.0 or sp.x > W - WALL - 10.0:
			sv.x = -sv.x
		if sp.y < TOP + 10.0 or sp.y > H - WALL - 10.0:
			sv.y = -sv.y
		sw["vel"] = sv
		sw["pos"] = Vector2(clampf(sp.x, WALL + 10.0, W - WALL - 10.0), clampf(sp.y, TOP + 10.0, H - WALL - 10.0))
		for e in _near(sw["pos"], 100.0):
			if e.dead or e in sw["hit"] or (e.position - sw["pos"]).length() > e.radius + 18.0:
				continue
			hurt(e, sw["dmg"], true)
			sw["hit"].append(e)
			sw["left"] -= 1
			var nx: Node2D = null
			var bd := 460.0
			for o in enemies:
				if o.dead or o in sw["hit"]:
					continue
				var dd: float = (o.position - sw["pos"]).length()
				if dd < bd:
					bd = dd
					nx = o
			tg = nx
			break
		sw["target"] = tg
		if sw["left"] <= 0 or sw["t"] > 3.5:
			saws.remove_at(i)
			continue
		i += 1
	# mini-drones kamikazes
	i = 0
	while i < minis.size():
		var mm: Dictionary = minis[i]
		mm["t"] += dt
		var tg = mm["target"]
		if tg == null or not is_instance_valid(tg) or tg.dead:
			tg = nearest_enemy(mm["pos"], 700.0)
			mm["target"] = tg
		if tg != null:
			mm["vel"] = (mm["vel"] as Vector2).lerp((tg.position - mm["pos"]).normalized() * 430.0, clampf(dt * 4.0, 0.0, 1.0))
		mm["pos"] += mm["vel"] * dt
		if (tg != null and (tg.position - mm["pos"]).length() < tg.radius + 10.0) or mm["t"] > 4.0:
			blast(mm["pos"], 64.0, hero.dmg * 2.2 * md, VENOM, "mini")
			minis.remove_at(i)
			continue
		i += 1

func blade_count() -> int:
	var bl: int = hero.lv("blades")
	if bl <= 0:
		return 0
	return (1 + bl) * (2 if hero.has_evo("moulinette") else 1)

func blade_radius() -> float:
	if hero.has_evo("moulinette"):
		return 120.0 + 34.0 * sin(elapsed * 2.4)
	return 92.0

func _launch_missile(from: Vector2, dir: Vector2) -> void:
	if missiles.size() >= 40:
		return
	missiles.append({"pos": from + dir * 20.0, "vel": dir * 240.0, "t": 0.0, "dmg": hero.dmg * 2.2 * hero.mach_dmg, "target": null})

## Pouvoirs à minuterie (météores, orage, onde de choc), effets différés, ruée en cours.
func _tick_powers(dt: float) -> void:
	# effets différés
	var i := 0
	while i < _later.size():
		var ev: Dictionary = _later[i]
		ev["t"] -= dt
		if ev["t"] > 0.0:
			i += 1
			continue
		_later.remove_at(i)
		match String(ev["kind"]):
			"death":
				_death_fx(ev)
			"meteor":
				blast(ev["pos"], 125.0, hero.dmg * 6.0, FIRE, "meteor", hero.dmg * 0.6)
				_add_fire(ev["pos"], 80.0, 3.0, hero.dmg * 0.6)
				shake_t = maxf(shake_t, 0.18)
	if cleared:
		return
	# météores
	var me: int = hero.lv("meteor")
	if me > 0:
		_pt["meteor"] = float(_pt.get("meteor", 0.0)) + dt
		if _pt["meteor"] >= 5.0 and not enemies.is_empty():
			_pt["meteor"] = 0.0
			for k in range(me):
				var p := _crowd_spot()
				var delay := 0.75 + 0.25 * k
				_later.append({"t": delay, "kind": "meteor", "pos": p})
				power_event.emit("meteor_call", {"pos": p, "delay": delay})
	# orage
	var st: int = hero.lv("storm")
	if st > 0:
		_pt["storm"] = float(_pt.get("storm", 0.0)) + dt
		if _pt["storm"] >= [0.0, 2.5, 1.5][st]:
			var cands := []
			for e in enemies:
				if not e.dead and (e.position - hero.position).length() < 700.0:
					cands.append(e)
			if not cands.is_empty():
				_pt["storm"] = 0.0
				var tg: Node2D = cands.pick_random()
				power_event.emit("strike", {"pos": tg.position})
				hurt(tg, hero.dmg * 3.0, true)
				if not tg.dead:
					chain(tg, hero.dmg * 1.5, 3, SHOCK)
				sfx.play("boom", 1.6, -8.0)
	# onde de choc
	var rp: int = hero.lv("repulse")
	if rp > 0:
		_pt["repulse"] = float(_pt.get("repulse", 0.0)) + dt
		if _pt["repulse"] >= [0.0, 6.0, 4.0][rp] and nearest_enemy(hero.position, 260.0) != null:
			_pt["repulse"] = 0.0
			pulse(hero.position, 210.0 + 40.0 * rp, hero.dmg * 2.0, Color("#5AA8FF"))
	# ruée en cours : Fantôme (traverse et blesse), Traînée ardente
	if hero.dash_t > 0.0:
		var ph: int = hero.lv("phantom")
		if ph > 0:
			for e in _near(hero.position, 120.0):
				if e.dead or e in _dash_hits or (e.position - hero.position).length() > e.radius + hero.radius + 12.0:
					continue
				_dash_hits.append(e)
				hurt(e, hero.dmg * (2.5 + 1.5 * (ph - 1)), true)
	var tl: int = hero.lv("trail")
	if tl > 0 and (hero.dash_t > 0.0 or (tl >= 2 and hero.moving)):
		var step := 42.0 if hero.dash_t > 0.0 else 70.0
		if (hero.position - _trail_last).length() >= step:
			_trail_last = hero.position
			_add_fire(hero.position, 48.0 if hero.dash_t > 0.0 else 38.0, 2.6 if hero.dash_t > 0.0 else 1.6, hero.dmg * 0.9 * tl)
	else:
		_trail_last = hero.position

func _add_fire(pos: Vector2, r: float, life: float, dps: float) -> void:
	fires.append({"pos": pos, "r": r, "t": 0.0, "life": life, "dps": dps})
	if fires.size() > 40:
		fires.remove_at(0)
	power_event.emit("fire", {"pos": pos, "r": r, "life": life})

## Point le plus peuplé (météores) : parmi quelques ennemis, celui qui a le plus de voisins.
func _crowd_spot() -> Vector2:
	var best := hero.position
	var bn := -1
	var pool := enemies.duplicate()
	pool.shuffle()
	for e in pool.slice(0, 14):
		if e.dead:
			continue
		var n := 0
		for o in _near(e.position, 140.0):
			if (o.position - e.position).length() < 140.0:
				n += 1
		if n > bn:
			bn = n
			best = e.position
	return best

## Effets de mort des pouvoirs, une image après la mort.
func _death_fx(ev: Dictionary) -> void:
	var pos: Vector2 = ev["pos"]
	var bo: int = hero.lv("boom")
	if bo > 0 and not ev["bomber"]:
		var r := 80.0 + 15.0 * bo
		var d: float = hero.dmg * (1.0 + 0.6 * bo)
		if hero.has_evo("pyro"):
			blast(pos, r * 1.8, d * 1.5, FIRE, "pyro", hero.dmg * 0.7)
		else:
			blast(pos, r, d, ORANGE, "boom")
	var ve: int = hero.lv("venom")
	if ve > 0:
		var cr := 55.0 + 18.0 * ve
		clouds.append({"pos": pos, "r": cr, "t": 0.0, "life": 3.0, "dps": hero.dmg * (0.5 + 0.35 * ve)})
		if clouds.size() > 14:
			clouds.remove_at(0)
		power_event.emit("cloud", {"pos": pos, "r": cr, "life": 3.0})
	if hero.lv("spread") > 0 and (ev["burn"] or ev["poison"]):
		for o in _near(pos, 220.0):
			if o.dead or (o.position - pos).length() > 140.0 + o.radius:
				continue
			if ev["burn"]:
				ignite(o, hero.dmg * 0.6, 3.0)
			if ev["poison"]:
				o.poison_t = 0.5
				o.hit(hero.dmg * 0.8)
		power_event.emit("pulse", {"pos": pos, "r": 140.0, "col": FIRE if ev["burn"] else VENOM})
	if hero.lv("shatter") > 0 and ev["frozen"]:
		blast(pos, 115.0, hero.dmg * 3.0, ICE, "shatter")
		for o in _near(pos, 200.0):
			if not o.dead and (o.position - pos).length() < 115.0 + o.radius:
				freeze(o, 1.0)
	var sw: int = hero.lv("swarm")
	if sw > 0 and randf() < [0.0, 0.25, 0.45][sw] and minis.size() < 16:
		minis.append({"pos": pos, "vel": Vector2.RIGHT.rotated(randf() * TAU) * 180.0, "t": 0.0, "target": null})

func _on_dash(from: Vector2, dir: Vector2) -> void:
	_dash_hits.clear()
	_trail_last = from
	power_event.emit("dash", {"from": from, "dir": dir})
	sfx.play("shoot", 0.55, -4.0)

func _on_dash_end(pos: Vector2) -> void:
	power_event.emit("dash_end", {"pos": pos})
	var db: int = hero.lv("dashboom")
	if hero.has_evo("comete"):
		blast(pos, 190.0, hero.dmg * 7.0, FIRE, "comete", hero.dmg * 0.8)
		_add_fire(pos, 90.0, 3.0, hero.dmg * 0.8)
	elif db > 0:
		blast(pos, 100.0 + 30.0 * db, hero.dmg * (2.5 + 2.0 * db), ORANGE, "dashboom")

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
func _bullet_walls(b) -> bool:
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
