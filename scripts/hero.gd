extends Node2D
## Jo, Passeuse : humaine en combinaison blanche et orange, blaster compact.
## Dessinée en code (vue de dessus 3/4, le corps tourne vers la visée). Stats = base × objets × pouvoirs × talents.
## Esquive active : courte ruée invulnérable, en charges qui se rechargent (pouvoirs de la branche Mouvement).

const Data = preload("res://scripts/data.gd")
const Art = preload("res://scripts/art.gd")

signal died
signal damaged
signal dashed(from: Vector2, dir: Vector2)  # début d'une ruée
signal dash_ended(pos: Vector2)
signal revived  # Seconde chance
signal shield_broke  # bouclier qui cède (Forteresse : onde de choc)

const BASE := {"hp": 100.0, "speed": 265.0, "dmg": 10.0, "rate": 5.5, "range": 540.0, "bspeed": 780.0}
const DASH_TIME := 0.16
const DASH_SPEED := 1650.0
const DASH_CD := 2.4
## Couleur des tirs par élément (bit) : feu, givre, foudre.
const ELEM_COLS := {1: Color("#FF8A3C"), 2: Color("#9FDCFF"), 4: Color("#FFE45C")}
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
var Talents: Script = Data.talents_script()  # talents du Relais (scripts/talents.gd), null tant qu'ils n'existent pas
var profile: Dictionary = {}  # profil du joueur (talents), posé par main

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
var hop := 0  # rebonds d'ennemi en ennemi (Ricochet II)
var back := 0  # tirs arrière (1) et sur les côtés (2)
var fan_every := 0  # un tir sur N part en éventail
var fan_n := 0
var bsize := 1.0  # taille des tirs (Obus géants)
var crit := 0.0
var crit_mult := 2.0
var elem := 0  # bits : 1 feu, 2 givre, 4 foudre
var energy_mult := 1.0
var pickup_mult := 1.0
var shield_max := 0
var shield_time := 8.0
var slow := 0.0
var vamp := 0
var boom := 0
var ally := 0
var turrets := 0
var magnet := 1.0
var armor := 1.0  # multiplicateur des dégâts reçus
var regen := 0.0
var after_hit := 0.55  # invulnérabilité après un coup
var mach_rate := 1.0  # Surcharge : cadence et dégâts des machines
var mach_dmg := 1.0
var dash_max := 1
var dash_cd := DASH_CD
var dash_len := DASH_TIME

var powers := {}  # id -> niveau pris
var evo := {}  # évolutions prises
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
# ruée
var dash_stock := 1.0  # charges disponibles (partie entière) et recharge en cours (partie décimale)
var dash_t := 0.0  # > 0 : ruée en cours
var dash_dir := Vector2.RIGHT
var dodge_t := 0.0  # invulnérable par la ruée
var momentum_t := 0.0  # Élan : cadence augmentée après une ruée
var phoenix_used := false
var shot_i := 0
var _elem_i := 0
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

func lv(id: String) -> int:
	return int(powers.get(id, 0))

func has_evo(id: String) -> bool:
	return evo.has(id)

## Nombre de choix déjà faits dans une branche (ouvre ses paliers).
func branch_count(b: String) -> int:
	var n := 0
	for id in powers:
		if String(Data.power(String(id)).get("b", "")) == b:
			n += int(powers[id])
	return n

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
	var old_max := hp_max
	hp_max = BASE["hp"] + hp_bonus + 20.0 * lv("heal")
	speed = BASE["speed"] * mult["speed"] * (1.0 + 0.12 * lv("speed"))
	dmg = BASE["dmg"] * mult["dmg"] * (1.0 + 0.20 * lv("dmg")) * (1.0 + 0.30 * lv("giant"))
	rate = BASE["rate"] * mult["rate"] * (1.0 + 0.20 * lv("rate"))
	rng = BASE["range"] * mult["range"] * (1.0 + 0.25 * lv("range"))
	bspeed = BASE["bspeed"] * (1.0 + 0.12 * lv("range"))
	# canon
	projectiles = 1 + lv("double") + (1 if has_evo("rafale") else 0)
	pierce = 999 if has_evo("rafale") else lv("pierce")
	bounce = 2 if lv("bounce") > 0 else 0
	hop = 1 if lv("bounce") >= 2 else 0
	back = lv("back")
	fan_every = [0, 4, 3][lv("fan")]
	fan_n = [0, 5, 7][lv("fan")]
	if has_evo("salve"):
		fan_every = 1
		fan_n = maxi(fan_n, 5)
	bsize = 1.0 + 0.4 * lv("giant") + (0.25 if has_evo("rafale") else 0.0)
	crit += 0.10 * lv("crit") + 0.05 * lv("fatal") + (0.15 if has_evo("sangfroid") else 0.0)
	crit_mult = 2.0 + lv("fatal")
	# éléments
	elem = (1 if lv("fire") > 0 else 0) | (2 if lv("frost") > 0 else 0) | (4 if lv("shock") > 0 else 0)
	boom = lv("boom")
	slow = 0.0
	# défense
	shield_max = lv("shield")
	shield_time = 3.0 if has_evo("forteresse") else 8.0 / (1.0 + 0.4 * maxi(0, shield_max - 1))
	armor = pow(0.88, lv("armor"))
	vamp = lv("vamp")
	regen = 1.0 * lv("regen")
	after_hit = 0.55 + 0.5 * lv("reflex")
	# machines
	turrets = lv("turret")
	ally = lv("ally") + (2 if has_evo("essaim") else 0)
	mach_rate = 1.0 + 0.30 * lv("overclock")
	mach_dmg = 1.0 + 0.25 * lv("overclock")
	# mouvement
	energy_mult = mult["energy"] * (1.0 + 0.15 * lv("magnet"))
	pickup_mult = mult["pickup"]
	magnet = 1.0 + 1.2 * lv("magnet")
	var old_dash := dash_max
	dash_max = 1 + lv("charges") + (1 if has_evo("comete") else 0)
	dash_cd = DASH_CD * pow(0.8, lv("turbo")) * (0.5 if has_evo("comete") else 1.0)
	var tcd := Data.talent(profile, "dash_cd")
	if tcd > 1.0:
		tcd *= 0.01  # talent donné en pour cent
	dash_cd *= 1.0 - clampf(tcd, 0.0, 0.6)
	dash_len = DASH_TIME * (1.3 if lv("phantom") > 0 else 1.0)
	if dash_max > old_dash:
		dash_stock += dash_max - old_dash
	dash_stock = minf(dash_stock, float(dash_max))
	# talents permanents du Relais : bonus de statistiques
	if Talents: Talents.apply(self)
	if hp_max > old_max:
		hp += hp_max - old_max
	hp = minf(hp, hp_max)

## Prend un pouvoir (un niveau de plus) ou une évolution.
func add_power(id: String) -> void:
	if not Data.evolution(id).is_empty():
		evo[id] = true
	else:
		powers[id] = lv(id) + 1
	if id == "heal":
		hp = minf(hp + 30.0, hp_max + 20.0)
	recalc()

func power_count(id: String) -> int:
	return lv(id)

func reset_run() -> void:
	powers = {}
	evo = {}
	dead = false
	invuln = 0.0
	dodge_t = 0.0
	dash_t = 0.0
	momentum_t = 0.0
	phoenix_used = false
	shield_ready = true
	shield_t = 0.0
	fire_cd = 0.0
	shot_i = 0
	recalc()
	dash_stock = float(dash_max)
	hp = hp_max

## Ruée : vers le stick gauche, sinon vers la visée. Faux si aucune charge n'est prête.
func try_dash(mv: Vector2) -> bool:
	if dead or preview or dash_t > 0.0 or dash_stock < 1.0:
		return false
	dash_stock -= 1.0
	dash_dir = mv.normalized() if mv.length() > 0.2 else aim_dir.normalized()
	dash_t = dash_len
	dodge_t = dash_len + 0.12
	if lv("momentum") > 0:
		momentum_t = 2.0
	dashed.emit(position, dash_dir)
	return true

func update(dt: float, mv: Vector2, am: Vector2, aim_active: bool) -> void:
	if dead:
		return
	invuln = maxf(0.0, invuln - dt)
	dodge_t = maxf(0.0, dodge_t - dt)
	momentum_t = maxf(0.0, momentum_t - dt)
	flash = maxf(0.0, flash - dt)
	fire_cd -= dt
	if shield_max > 0 and not shield_ready:
		shield_t -= dt
		if shield_t <= 0.0:
			shield_ready = true
	if regen > 0.0:
		hp = minf(hp_max, hp + regen * dt)
	if dash_stock < float(dash_max):
		dash_stock = minf(float(dash_max), dash_stock + dt / dash_cd)
	move_dir = mv
	moving = mv.length() > 0.05
	if dash_t > 0.0:
		# ruée en trois pas : les caisses arrêtent Jo au lieu de se laisser traverser
		dash_t -= dt
		for k in range(3):
			position += dash_dir * DASH_SPEED * dt / 3.0
			if arena != null:
				arena._clamp_circle(self, radius)
		moving = true
		anim += dt * 20.0
		if dash_t <= 0.0:
			dash_t = 0.0
			dash_ended.emit(position)
	elif moving:
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
	# le tir ne part que quand le stick droit est poussé ; sinon Jo regarde où elle va
	var fire := false
	if aim_active:
		aim_dir = am.normalized()
		fire = true
	elif moving and dash_t <= 0.0:
		aim_dir = mv.normalized()
	rotation = aim_dir.angle() + PI * 0.5
	if fire and fire_cd <= 0.0 and arena != null:
		var r := rate
		if momentum_t > 0.0:
			r *= 1.0 + 0.6 + 0.4 * (lv("momentum") - 1)
		fire_cd = 1.0 / r
		_shoot()
	queue_redraw()

func _shoot() -> void:
	shot_i += 1
	var dirs: Array[Vector2] = []
	var n := projectiles
	for i in range(n):
		var spread := 0.0
		if n > 1:
			spread = deg_to_rad(-7.0 * (n - 1) * 0.5 + 7.0 * i)
		dirs.append(aim_dir.rotated(spread + randf_range(-0.02, 0.02)))
	# salve en éventail : 5 ou 7 tirs sur ±34°
	if fan_every > 0 and shot_i % fan_every == 0:
		for i in range(fan_n):
			var a := lerpf(-0.6, 0.6, float(i) / float(fan_n - 1))
			if absf(a) > 0.05:
				dirs.append(aim_dir.rotated(a))
	if back >= 1:
		dirs.append(-aim_dir)
	if back >= 2:
		dirs.append(aim_dir.rotated(PI * 0.5))
		dirs.append(aim_dir.rotated(-PI * 0.5))
	for d in dirs:
		var damage := dmg
		var is_crit := randf() < crit
		if is_crit:
			damage *= crit_mult
			if has_evo("sangfroid"):
				heal(1.0)
		var col := VISOR
		var look := 0
		if elem != 0:
			# couleur tournante entre les éléments pris : chaque tir porte tous leurs effets
			for k in range(3):
				_elem_i = (_elem_i + 1) % 3
				if elem & (1 << _elem_i):
					look = 1 << _elem_i
					col = ELEM_COLS[look]
					break
		if is_crit:
			col = col.lerp(Color("#FFF2A8"), 0.6)
		var r := (7.0 if is_crit else 5.0) * bsize
		var b = arena.spawn_bullet(position + d * 34.0, d * bspeed, damage, true, pierce, bounce, col, r, elem, 0, hop, is_crit)
		b.look = look
	arena.sfx.play("shoot", randf_range(0.9, 1.1), -8.0 if dirs.size() < 4 else -10.0)
	_flash_t = 0.05
	_flash.modulate = VISOR
	_recoil = 5.0

func take_damage(amount: float) -> bool:
	if dead or invuln > 0.0 or dodge_t > 0.0 or preview:
		return false
	if shield_max > 0 and shield_ready:
		shield_ready = false
		shield_t = shield_time
		invuln = 0.4
		flash = 0.15
		if has_evo("forteresse"):
			shield_broke.emit()
		return false
	hp -= amount * armor
	invuln = after_hit
	flash = 0.18
	damaged.emit()
	if hp <= 0.0:
		if lv("phoenix") > 0 and not phoenix_used:
			phoenix_used = true
			hp = hp_max * 0.5
			invuln = 2.0
			revived.emit()
			return true
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
