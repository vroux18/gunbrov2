extends Node2D
## Ennemis du monde 1 (Nébuleuse 7) : sentinelle (fonce), garde (tire à distance), colosse (charge),
## pétard (kamikaze qui explose), vigie (tireuse d'élite à laser de visée), rempart (bouclier frontal qui bloque
## les tirs), mortier (tir en cloche annoncé au sol), boss Le Portique.
## Élite : ×3 PV, ×1.25 vitesse, anneau d'or, lâche un objet. Dessin en code, deux tons, contour sombre.

const Data = preload("res://scripts/data.gd")
const Art = preload("res://scripts/art.gd")

const OUTLINE := Color("#0B0F1A")
const BODY := Color("#2C3350")
const BODY_DARK := Color("#1C2238")
const PLATE := Color("#B8C1CC")
const PLATE_DARK := Color("#8A939E")
const RED := Color("#FF4D6D")
const GOLD := Color("#FFB347")
const MAGENTA := Color("#F23CB8")
const VIOLET := Color("#B36BFF")
const ORANGE_BOOM := Color("#FF9A3C")
const SHIELD_COS := 0.42  # demi-angle du bouclier du rempart : ~65°

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
var aim_dir := Vector2.DOWN  # vigie : direction du laser de visée (figée juste avant le tir)
var _spr: Sprite2D
var _glow: Sprite2D


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
	if k == "sniper" or k == "mortar":
		fire_cd = randf_range(1.6, 2.6)
	# rendu 2D d'origine coupé : l'ennemi est dessiné en 3D par view3d.gd (mob3d.gd)

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
		"bomber":
			_bomber(dt, dir, dist, slow)
		"sniper":
			_sniper(dt, dir, dist, slow)
		"shield":
			_shield(dt, dir, dist, slow)
		"mortar":
			_mortar(dt, dir, dist, slow)
		"boss":
			_boss(dt, dir, dist, slow)
	if _spr != null:
		_spr.rotation = facing.angle()
		var m := Color.WHITE
		if flash > 0.0:
			m = Color(2.0, 2.0, 2.0)
		elif state == "tell":
			m = Color(1.6, 0.8, 0.8)
		_spr.modulate = m
		if state == "tell":
			_spr.position = Vector2(randf_range(-2, 2), randf_range(-2, 2))
		else:
			_spr.position = Vector2(0, sin(t * 6.0 + wobble) * 2.0) if kind == "drone" else Vector2.ZERO
	queue_redraw()

func _contact(dist: float) -> void:
	if dist < radius + hero.radius and contact_cd <= 0.0:
		if hero.take_damage(dmg):
			arena.sfx.play("hurt", 1.0)
		contact_cd = 0.7
		if kind == "drone":
			# la sentinelle rebondit après contact
			position -= (hero.position - position).normalized() * 18.0

## Pétard : roule vers Jo, s'arrête à portée, gonfle 0,55 s et explose (il meurt sans rapporter de butin).
func _bomber(dt: float, dir: Vector2, dist: float, slow: float) -> void:
	if state == "move":
		var v: Vector2 = arena.steer(position, dir, radius) * speed * slow
		position += v * dt
		facing = dir
		if dist < radius + hero.radius + 46.0:
			state = "tell"
			state_t = 0.55
			arena.sfx.play("eshoot", 0.55, -6.0)
	elif state == "tell":
		state_t -= dt
		if state_t <= 0.0:
			dead = true
			arena.explode(position, 82.0, dmg, 30.0, ORANGE_BOOM)
			arena.on_enemy_died(self, false)

## Vigie : reste loin, se cale 1,1 s en suivant Jo du laser, fige la visée 0,25 s, puis tir très rapide.
func _sniper(dt: float, dir: Vector2, dist: float, slow: float) -> void:
	if state == "move":
		var want := Vector2.ZERO
		if dist > 600.0:
			want = dir
		elif dist < 400.0:
			want = -dir
		else:
			want = dir.orthogonal() * sin(t * 0.9 + wobble)
		want = arena.steer(position, want, radius)
		position += want * speed * slow * dt
		facing = dir
		aim_dir = dir
		fire_cd -= dt
		if fire_cd <= 0.0 and dist < 900.0:
			state = "aim"
			state_t = 1.1
			arena.sfx.play("eshoot", 0.45, -10.0)
	elif state == "aim":
		state_t -= dt
		if state_t > 0.25:
			aim_dir = aim_dir.slerp(dir, clampf(dt * 6.0, 0.0, 1.0))
		facing = aim_dir
		if state_t <= 0.0:
			state = "move"
			arena.spawn_bullet(position + aim_dir * (radius + 10.0), aim_dir * 900.0, dmg, false, 0, 0, VIOLET, 5.0)
			fire_cd = randf_range(2.4, 3.2)
	_contact(dist)

## Rempart : avance bouclier en avant ; le bouclier pivote lentement, il faut le contourner. Coup de bouclier de près.
func _shield(dt: float, dir: Vector2, dist: float, slow: float) -> void:
	charge_cd -= dt
	var turn := (1.9 if elite else 1.4) * dt
	if state == "move":
		var a := facing.angle_to(dir)
		facing = facing.rotated(clampf(a, -turn, turn))
		var wd: Vector2 = arena.steer(position, dir, radius)
		position += wd * speed * slow * dt
		if charge_cd <= 0.0 and dist < 190.0 and absf(a) < 0.6:
			state = "tell"
			state_t = 0.5
	elif state == "tell":
		state_t -= dt
		var a2 := facing.angle_to(dir)
		facing = facing.rotated(clampf(a2, -turn, turn))
		if state_t <= 0.0:
			state = "charge"
			state_t = 0.35
			charge_dir = facing
			arena.sfx.play("hurt", 1.3, -6.0)
	elif state == "charge":
		state_t -= dt
		position += charge_dir * 430.0 * slow * dt
		if state_t <= 0.0:
			state = "move"
			charge_cd = randf_range(2.4, 3.4)
	_contact(dist)

## Vrai si un tir venant de `from` touche le bouclier (devant le rempart).
func blocks(from: Vector2) -> bool:
	if kind != "shield" or dead:
		return false
	return (from - position).normalized().dot(facing) > SHIELD_COS

## Mortier : garde ses distances, se plante 0,9 s, puis tire un obus en cloche là où Jo va être.
func _mortar(dt: float, dir: Vector2, dist: float, slow: float) -> void:
	if state == "move":
		var want := Vector2.ZERO
		if dist > 560.0:
			want = dir
		elif dist < 300.0:
			want = -dir
		else:
			want = dir.orthogonal() * sin(t * 0.7 + wobble) * 0.6
		want = arena.steer(position, want, radius)
		position += want * speed * slow * dt
		facing = dir
		fire_cd -= dt
		if fire_cd <= 0.0 and dist < 760.0:
			state = "tell"
			state_t = 0.9
	elif state == "tell":
		state_t -= dt
		facing = dir
		if state_t <= 0.0:
			state = "move"
			var target: Vector2 = hero.position + hero.move_dir * hero.speed * 0.55
			arena.lob(position + dir * (radius + 6.0), target, 1.1, 62.0, dmg)
			fire_cd = randf_range(3.0, 4.0)
	_contact(dist)

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
	draw_circle(Vector2(0, radius * 0.5), radius * 1.1, Color(0, 0, 0, 0.35))
	if elite:
		draw_arc(Vector2.ZERO, radius + 12.0, t * 1.5, t * 1.5 + TAU, 40, Color(GOLD, 0.85), 4.0, true)
	if state == "tell":
		var p := 1.0 - state_t / (0.8 if kind == "boss" else 0.7)
		draw_arc(Vector2.ZERO, radius + 8.0 + p * 20.0, 0.0, TAU, 40, Color(RED, 0.9 - p * 0.6), 4.0, true)
		draw_line(Vector2.ZERO, charge_dir * (radius + 90.0), Color(RED, 0.5), 6.0)
	elif state == "aim":
		draw_circle(facing * (radius + 26.0), 6.0 + 4.0 * sin(t * 40.0), RED)
	elif state == "ring":
		draw_arc(Vector2.ZERO, radius + 14.0, 0.0, TAU, 48, Color(MAGENTA, 0.8), 5.0, true)
	# barre de vie des gros
	if (kind == "brute" or elite) and hp < hp_max:
		var w := radius * 2.2
		draw_rect(Rect2(Vector2(-w * 0.5, -radius - 18.0), Vector2(w, 6.0)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(Vector2(-w * 0.5, -radius - 18.0), Vector2(w * hp / hp_max, 6.0)), RED)
