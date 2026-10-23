extends Node2D
## Jo, Passeuse : humaine en combinaison blanche et orange, blaster compact.
## Dessinée en code (vue de dessus 3/4, le corps tourne vers la visée). Stats = base × objets × pouvoirs.

const Data = preload("res://scripts/data.gd")
const Art = preload("res://scripts/art.gd")

signal died
signal damaged

const BASE := {"hp": 100.0, "speed": 265.0, "dmg": 10.0, "rate": 5.5, "range": 540.0, "bspeed": 780.0}
const OUTLINE := Color("#0B0F1A")
const SUIT := Color("#F4F1EA")
const SUIT_DARK := Color("#C9C2B4")
const ACCENT := Color("#FF7A2F")
const ACCENT_DARK := Color("#C85A1C")
const SKIN := Color("#F2C9A0")
const HAIR := Color("#3B2A2A")
const VISOR := Color("#3CF2D8")
const NAVY := Color("#1B2B4D")
const GUN := Color("#8A939E")

var arena: Node = null
var radius := 18.0

# stats effectives
var hp_max := 100.0
var hp := 100.0
var speed := 265.0
var dmg := 10.0
var rate := 5.5
var rng := 540.0
var bspeed := 780.0
var projectiles := 1
var pierce := 0
var bounce := 0
var crit := 0.0
var energy_mult := 1.0
var pickup_mult := 1.0
var shield_max := 0
var slow := 0.0
var vamp := 0
var boom := 0
var ally := 0
var turrets := 0
var magnet := 1.0

var powers := {}  # id -> nombre de fois pris
var items: Array = []  # instances équipées

var move_dir := Vector2.ZERO
var aim_dir := Vector2.DOWN
var fire_cd := 0.0
var invuln := 0.0
var shield_ready := true
var shield_t := 0.0
var anim := 0.0
var moving := false
var dead := false
var flash := 0.0
var preview := false  # dans le Relais : posée, immobile, pas de tir
var _spr: Sprite2D
var _glow: Sprite2D
var _flash: Sprite2D
var _flash_t := 0.0
var _recoil := 0.0

func _ready() -> void:
	_glow = Art.sprite(Art.GLOW, 1.1, true)
	_glow.modulate = Color(VISOR, 0.22)
	add_child(_glow)
	_spr = Art.sprite(Art.JO, 0.5)
	_spr.position = Vector2(0, -2)
	add_child(_spr)
	_flash = Art.sprite(Art.FLASH, 0.6, true)
	_flash.position = Vector2(0, -66)
	_flash.visible = false
	add_child(_flash)

func recalc() -> void:
	var mult := {"dmg": 1.0, "rate": 1.0, "speed": 1.0, "range": 1.0, "energy": 1.0, "pickup": 1.0}
	var hp_bonus := 0.0
	crit = 0.0
	for it in items:
		var tpl := Data.item_template(String(it["id"]))
		var v := Data.item_value(it)
		var stat := String(tpl["stat"])
		if stat == "hp":
			hp_bonus += v
		elif stat == "crit":
			crit += v
		else:
			mult[stat] += v
	var n := func(id: String) -> int: return int(powers.get(id, 0))
	var old_max := hp_max
	hp_max = BASE["hp"] + hp_bonus + 10.0 * n.call("heal")
	speed = BASE["speed"] * mult["speed"] * (1.0 + 0.15 * n.call("speed"))
	dmg = BASE["dmg"] * mult["dmg"] * (1.0 + 0.20 * n.call("dmg"))
	rate = BASE["rate"] * mult["rate"] * (1.0 + 0.25 * n.call("rate"))
	rng = BASE["range"] * mult["range"] * (1.0 + 0.25 * n.call("range"))
	bspeed = BASE["bspeed"]
	projectiles = 1 + n.call("double")
	pierce = n.call("pierce")
	bounce = n.call("bounce")
	crit += 0.15 * n.call("crit")
	energy_mult = mult["energy"]
	pickup_mult = mult["pickup"]
	magnet = 1.0 + 1.0 * n.call("magnet")
	shield_max = n.call("shield")
	slow = 0.10 * n.call("slow")
	vamp = n.call("vamp")
	boom = n.call("boom")
	ally = n.call("ally")
	turrets = n.call("turret")
	if hp_max > old_max:
		hp += hp_max - old_max
	hp = minf(hp, hp_max)

func add_power(id: String) -> void:
	powers[id] = int(powers.get(id, 0)) + 1
	if id == "heal":
		hp = minf(hp + 30.0, hp_max + 10.0)
	recalc()

func power_count(id: String) -> int:
	return int(powers.get(id, 0))

func reset_run() -> void:
	powers = {}
	dead = false
	invuln = 0.0
	shield_ready = true
	shield_t = 0.0
	fire_cd = 0.0
	recalc()
	hp = hp_max

func update(dt: float, mv: Vector2, am: Vector2, aim_active: bool) -> void:
	if dead:
		return
	invuln = maxf(0.0, invuln - dt)
	flash = maxf(0.0, flash - dt)
	fire_cd -= dt
	if shield_max > 0 and not shield_ready:
		shield_t -= dt
		if shield_t <= 0.0:
			shield_ready = true
	move_dir = mv
	moving = mv.length() > 0.05
	if moving:
		position += mv * speed * dt
		anim += dt * 11.0 * mv.length()
	_recoil = maxf(0.0, _recoil - dt * 40.0)
	_flash_t -= dt
	_flash.visible = _flash_t > 0.0
	_flash.rotation += dt * 20.0
	var bob := absf(sin(anim)) * 3.0 if moving else 0.0
	_spr.position = Vector2(0, -2 + _recoil - bob)
	_spr.rotation = sin(anim) * 0.06 if moving else 0.0
	_spr.scale = Vector2(0.5, 0.5 - _recoil * 0.004)
	var m := Color.WHITE
	if flash > 0.0:
		m = Color(1.7, 1.7, 1.7)
	elif invuln > 0.0 and int(invuln * 20.0) % 2 == 0 and not preview:
		m = Color(1.0, 1.0, 1.0, 0.5)
	_spr.modulate = m
	var target_dir := Vector2.ZERO
	var fire := false
	if aim_active:
		target_dir = am.normalized()
		fire = true
	else:
		var e: Node2D = arena.nearest_enemy(position, rng) if arena != null else null
		if e != null:
			target_dir = (e.position - position).normalized()
			fire = true
	if target_dir != Vector2.ZERO:
		aim_dir = target_dir
	elif moving:
		aim_dir = mv.normalized()
	rotation = aim_dir.angle() + PI * 0.5
	if fire and fire_cd <= 0.0 and arena != null:
		fire_cd = 1.0 / rate
		_shoot()
	queue_redraw()

func _shoot() -> void:
	var muzzle := position + aim_dir * 34.0
	var n := projectiles
	for i in range(n):
		var spread := 0.0
		if n > 1:
			spread = deg_to_rad(-7.0 * (n - 1) * 0.5 + 7.0 * i)
		var d := aim_dir.rotated(spread + randf_range(-0.02, 0.02))
		var damage := dmg
		var is_crit := randf() < crit
		if is_crit:
			damage *= 2.0
		arena.spawn_bullet(muzzle, d * bspeed, damage, true, pierce, bounce, VISOR if not is_crit else Color("#FFF2A8"), 5.0 if not is_crit else 7.0)
	arena.sfx.play("shoot", randf_range(0.9, 1.1), -8.0)
	_flash_t = 0.05
	_flash.modulate = VISOR
	_recoil = 5.0

func take_damage(amount: float) -> bool:
	if dead or invuln > 0.0 or preview:
		return false
	if shield_max > 0 and shield_ready:
		shield_ready = false
		shield_t = 8.0 / shield_max
		invuln = 0.4
		flash = 0.15
		return false
	hp -= amount
	invuln = 0.55
	flash = 0.18
	damaged.emit()
	if hp <= 0.0:
		hp = 0.0
		dead = true
		died.emit()
	return true

func heal(v: float) -> void:
	hp = minf(hp_max, hp + v)

# ---------------------------------------------------------------- dessin
func _cap(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	draw_line(a, b, OUTLINE, (r + 3.0) * 2.0)
	draw_circle(a, r + 3.0, OUTLINE)
	draw_circle(b, r + 3.0, OUTLINE)
	draw_line(a, b, col, r * 2.0)
	draw_circle(a, r, col)
	draw_circle(b, r, col)

func _poly(pts: PackedVector2Array, col: Color, outline: float = 3.0) -> void:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var big := PackedVector2Array()
	for p in pts:
		big.append(c + (p - c) * (1.0 + outline / maxf(1.0, (p - c).length())) )
	draw_polygon(big, PackedColorArray([OUTLINE]))
	draw_polygon(pts, PackedColorArray([col]))

func _draw() -> void:
	# ombre au sol (le sprite porte le corps)
	draw_circle(Vector2(0, 10), 24.0, Color(0, 0, 0, 0.35))
	if shield_max > 0 and shield_ready:
		draw_arc(Vector2.ZERO, radius + 22.0, 0.0, TAU, 48, Color(VISOR, 0.6), 4.0, true)
		draw_arc(Vector2.ZERO, radius + 26.0, 0.0, TAU, 48, Color(VISOR, 0.2), 8.0, true)
