extends Node2D
## Ennemis du monde 1 (Nébuleuse 7) : sentinelle (fonce), garde (tire à distance), colosse (charge), boss Le Portique.
## Élite : ×3 PV, ×1.25 vitesse, anneau d'or, lâche un objet. Dessin en code, deux tons, contour sombre.

const Data = preload("res://scripts/data.gd")

const OUTLINE := Color("#0B0F1A")
const BODY := Color("#2C3350")
const BODY_DARK := Color("#1C2238")
const PLATE := Color("#B8C1CC")
const PLATE_DARK := Color("#8A939E")
const RED := Color("#FF4D6D")
const GOLD := Color("#FFB347")
const MAGENTA := Color("#F23CB8")

var kind := "drone"
var elite := false
var hp := 20.0
var hp_max := 20.0
var speed := 100.0
var radius := 15.0
var dmg := 8.0
var energy := 1
var tickets := 1
var display_name := ""

var arena: Node = null
var hero: Node2D = null
var t := 0.0
var flash := 0.0
var state := "move"
var state_t := 0.0
var charge_dir := Vector2.ZERO
var fire_cd := 1.2
var contact_cd := 0.0
var wobble := 0.0
var dead := false
var facing := Vector2.DOWN
var spawned_at := {}  # boss : seuils de PV déjà utilisés
var pattern_t := 0.0
var charge_cd := 3.0

func setup(k: String, is_elite: bool, hp_scale: float) -> void:
	kind = k
	elite = is_elite
	var d: Dictionary = Data.ENEMIES[k]
	hp_max = float(d["hp"]) * hp_scale * (3.0 if elite else 1.0)
	hp = hp_max
	speed = float(d["speed"]) * (1.25 if elite else 1.0)
	radius = float(d["radius"]) * (1.2 if elite else 1.0)
	dmg = float(d["dmg"]) * (1.3 if elite else 1.0)
	energy = int(d["energy"]) * (3 if elite else 1)
	tickets = int(d["tickets"]) * (3 if elite else 1)
	display_name = String(d["name"])
	wobble = randf() * TAU
	fire_cd = randf_range(0.8, 1.8)
	charge_cd = randf_range(1.5, 3.0)

func hit(d: float) -> void:
	if dead:
		return
	hp -= d
	flash = 0.09
	if hp <= 0.0:
		dead = true
		arena.on_enemy_died(self)

func tick(dt: float) -> void:
	if dead or hero == null:
		return
	t += dt
	flash = maxf(0.0, flash - dt)
	contact_cd = maxf(0.0, contact_cd - dt)
	var slow := 1.0 - float(hero.slow)
	var to_hero: Vector2 = hero.position - position
	var dist := to_hero.length()
	var dir := to_hero.normalized() if dist > 1.0 else Vector2.DOWN
	match kind:
		"drone":
			var side := dir.orthogonal() * sin(t * 3.0 + wobble) * 0.6
			var v: Vector2 = arena.steer(position, (dir + side).normalized(), radius) * speed * slow
			position += v * dt
			facing = v.normalized()
			_contact(dist)
		"trooper":
			var want := Vector2.ZERO
			if dist > 340.0:
				want = dir
			elif dist < 220.0:
				want = -dir
			else:
				want = dir.orthogonal() * sin(t * 1.3 + wobble)
			want = arena.steer(position, want, radius)
			position += want * speed * slow * dt
			facing = dir
			fire_cd -= dt
			if state == "aim":
				state_t -= dt
				if state_t <= 0.0:
					state = "move"
					arena.spawn_bullet(position + dir * (radius + 6.0), dir * 390.0, dmg, false, 0, 0, RED, 4.5)
					fire_cd = randf_range(1.5, 2.2)
			elif fire_cd <= 0.0 and dist < 560.0:
				state = "aim"
				state_t = 0.38
			_contact(dist)
		"brute":
			charge_cd -= dt
			if state == "move":
				var wd: Vector2 = arena.steer(position, dir, radius)
				position += wd * speed * slow * dt
				facing = wd
				if charge_cd <= 0.0 and dist < 300.0:
					state = "tell"
					state_t = 0.7
					charge_dir = dir
			elif state == "tell":
				state_t -= dt
				charge_dir = dir
				if state_t <= 0.0:
					state = "charge"
					state_t = 0.45
					arena.sfx.play("hurt", 1.6, -6.0)
			elif state == "charge":
				state_t -= dt
				position += charge_dir * 560.0 * slow * dt
				facing = charge_dir
				if state_t <= 0.0:
					state = "move"
					charge_cd = randf_range(2.2, 3.4)
			_contact(dist)
		"boss":
			_boss(dt, dir, dist, slow)
	queue_redraw()

func _contact(dist: float) -> void:
	if dist < radius + hero.radius and contact_cd <= 0.0:
		if hero.take_damage(dmg):
			arena.sfx.play("hurt", 1.0)
		contact_cd = 0.7
		if kind == "drone":
			# la sentinelle rebondit après contact
			position -= (hero.position - position).normalized() * 18.0

func _boss(dt: float, dir: Vector2, dist: float, slow: float) -> void:
	pattern_t += dt
	facing = dir
	# invocation de sentinelles aux deux tiers et au tiers
	for th in [0.66, 0.33]:
		if hp / hp_max < th and not spawned_at.has(th):
			spawned_at[th] = true
			arena.boss_summon(position, 4)
	if state == "move":
		if dist > 260.0:
			position += arena.steer(position, dir, radius) * speed * slow * dt
		else:
			position += dir.orthogonal() * speed * 0.6 * slow * dt
		fire_cd -= dt
		if fire_cd <= 0.0:
			# salve de trois tirs vers la Passeuse
			for a in [-0.18, 0.0, 0.18]:
				arena.spawn_bullet(position + dir * (radius + 8.0), dir.rotated(a) * 360.0, dmg * 0.6, false, 0, 0, RED, 5.0)
			fire_cd = 1.5
		if pattern_t > 2.8:
			pattern_t = 0.0
			state = "ring"
			state_t = 0.4
		charge_cd -= dt
		if charge_cd <= 0.0 and dist < 420.0:
			state = "tell"
			state_t = 0.8
			charge_dir = dir
			charge_cd = 7.0
	elif state == "ring":
		state_t -= dt
		if state_t <= 0.0:
			var n := 16
			for i in range(n):
				var a := TAU * i / n + t
				arena.spawn_bullet(position + Vector2.RIGHT.rotated(a) * (radius + 6.0), Vector2.RIGHT.rotated(a) * 240.0, dmg * 0.5, false, 0, 0, MAGENTA, 5.0)
			arena.sfx.play("boom", 0.7, -4.0)
			state = "move"
	elif state == "tell":
		state_t -= dt
		charge_dir = dir
		if state_t <= 0.0:
			state = "charge"
			state_t = 0.6
	elif state == "charge":
		state_t -= dt
		position += charge_dir * 520.0 * dt
		if state_t <= 0.0:
			state = "move"
	_contact(dist)

# ---------------------------------------------------------------- dessin
func _cap(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	draw_line(a, b, OUTLINE, (r + 3.0) * 2.0)
	draw_circle(a, r + 3.0, OUTLINE)
	draw_circle(b, r + 3.0, OUTLINE)
	draw_line(a, b, col, r * 2.0)
	draw_circle(a, r, col)
	draw_circle(b, r, col)

func _disc(c: Vector2, r: float, col: Color, outline: float = 3.0) -> void:
	draw_circle(c, r + outline, OUTLINE)
	draw_circle(c, r, col)

func _draw() -> void:
	var mod := Color.WHITE
	if flash > 0.0:
		mod = Color(2.0, 2.0, 2.0)
	var tell := state == "tell"
	var shake := Vector2(randf_range(-2, 2), randf_range(-2, 2)) if tell else Vector2.ZERO
	draw_circle(Vector2(0, radius * 0.45), radius * 1.05, Color(0, 0, 0, 0.35))
	if elite:
		draw_arc(Vector2.ZERO, radius + 9.0, 0.0, TAU, 40, Color(GOLD, 0.8), 4.0, true)
	var ang := facing.angle()
	match kind:
		"drone":
			_disc(shake, radius, BODY * mod)
			draw_circle(shake + Vector2(0, -3), radius * 0.6, BODY_DARK * mod)
			draw_arc(shake, radius * 0.8, t * 2.0, t * 2.0 + PI * 1.4, 20, RED * mod, 3.0, true)
			draw_circle(shake + Vector2.RIGHT.rotated(ang) * radius * 0.45, 4.5, RED * mod)
			for i in range(3):
				var a := t * 1.5 + TAU * i / 3.0
				draw_circle(shake + Vector2.RIGHT.rotated(a) * (radius + 2.0), 3.0, PLATE * mod)
		"trooper":
			var f := Vector2.RIGHT.rotated(ang)
			var s := f.orthogonal()
			# jambes
			var sw := sin(t * 9.0) * 5.0
			_cap(-s * 7.0 - f * 2.0, -s * 8.0 - f * 10.0 + f * sw, 5.0, BODY_DARK * mod)
			_cap(s * 7.0 - f * 2.0, s * 8.0 - f * 10.0 - f * sw, 5.0, BODY_DARK * mod)
			# torse blindé
			_disc(Vector2.ZERO, radius, PLATE * mod)
			draw_circle(-f * 4.0, radius * 0.7, PLATE_DARK * mod)
			# bras et fusil
			_cap(s * 12.0, f * 18.0 + s * 4.0, 4.5, PLATE * mod)
			_cap(-s * 12.0, f * 18.0 - s * 4.0, 4.5, PLATE * mod)
			_cap(f * 14.0, f * 34.0, 4.0, BODY_DARK * mod)
			if state == "aim":
				draw_circle(f * 36.0, 6.0 + 4.0 * sin(t * 40.0), RED)
			# casque et visière rouge
			_disc(f * 2.0, radius * 0.62, BODY * mod)
			draw_polygon(PackedVector2Array([f * 8.0 + s * 7.0, f * 13.0 + s * 4.0, f * 13.0 - s * 4.0, f * 8.0 - s * 7.0]), PackedColorArray([RED * mod]))
		"brute":
			var f := Vector2.RIGHT.rotated(ang)
			var s := f.orthogonal()
			var col := BODY if not (tell or state == "charge") else RED.darkened(0.35)
			# corps massif
			var pts := PackedVector2Array()
			for i in range(8):
				var a := TAU * i / 8.0 + PI / 8.0
				pts.append(shake + Vector2.RIGHT.rotated(a) * radius)
			var big := PackedVector2Array()
			for p in pts:
				big.append(p * 1.1)
			draw_polygon(big, PackedColorArray([OUTLINE]))
			draw_polygon(pts, PackedColorArray([col * mod]))
			draw_circle(shake - f * radius * 0.3, radius * 0.55, BODY_DARK * mod)
			# bras-marteaux
			_cap(shake + s * radius * 0.9, shake + s * radius * 0.9 + f * radius * 0.9, 9.0, PLATE_DARK * mod)
			_cap(shake - s * radius * 0.9, shake - s * radius * 0.9 + f * radius * 0.9, 9.0, PLATE_DARK * mod)
			# œil
			draw_circle(shake + f * radius * 0.45, 7.0, RED * mod)
			draw_circle(shake + f * radius * 0.45, 3.0, Color.WHITE)
		"boss":
			var f := Vector2.RIGHT.rotated(ang)
			var s := f.orthogonal()
			var col := BODY if state != "tell" and state != "charge" else RED.darkened(0.3)
			# quatre pattes
			for i in [-1, 1]:
				for j in [-1, 1]:
					var base: Vector2 = s * i * radius * 0.7 + f * j * radius * 0.5
					var foot: Vector2 = base + s * i * radius * 0.7 + f * j * radius * 0.3 + f * sin(t * 6.0 + i + j) * 6.0
					_cap(shake + base, shake + foot, 9.0, PLATE_DARK * mod)
			_disc(shake, radius, col * mod, 4.0)
			draw_circle(shake - f * radius * 0.25, radius * 0.6, BODY_DARK * mod)
			# canons
			_cap(shake + s * radius * 0.55, shake + s * radius * 0.55 + f * radius * 1.1, 8.0, PLATE * mod)
			_cap(shake - s * radius * 0.55, shake - s * radius * 0.55 + f * radius * 1.1, 8.0, PLATE * mod)
			# tête : visière large
			_disc(shake + f * radius * 0.35, radius * 0.45, PLATE * mod)
			draw_polygon(PackedVector2Array([shake + f * radius * 0.5 + s * radius * 0.35, shake + f * radius * 0.75 + s * radius * 0.2, shake + f * radius * 0.75 - s * radius * 0.2, shake + f * radius * 0.5 - s * radius * 0.35]), PackedColorArray([MAGENTA * mod]))
			if state == "ring":
				draw_arc(Vector2.ZERO, radius + 14.0, 0.0, TAU, 48, Color(MAGENTA, 0.8), 5.0, true)
	# barre de vie des gros
	if (kind == "brute" or elite) and hp < hp_max:
		var w := radius * 2.2
		draw_rect(Rect2(Vector2(-w * 0.5, -radius - 16.0), Vector2(w, 6.0)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(Vector2(-w * 0.5, -radius - 16.0), Vector2(w * hp / hp_max, 6.0)), RED)
