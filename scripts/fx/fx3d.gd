extends Node3D
## Effets du combat (view3d.gd les déclenche) : éclairs de bouche, traînées, étincelles, impacts, ondes,
## explosions en boule de feu, fumée, débris, brûlures au sol, sceaux d'apparition.
## Tout passe par neuf réserves MultiMesh (fx_pool.gd) animées par la carte graphique : une émission écrit
## quelques instances, aucun nœud n'est créé. Une émission peut être différée (`delay`) : la particule
## reste invisible jusqu'à son heure, ce qui permet d'écrire d'un coup une séquence (explosions en chaîne,
## fumée qui s'échappe d'un cratère). Horloge propre `now`, qui suit le temps du jeu (ralentis compris).

const FxPool = preload("res://scripts/fx/fx_pool.gd")
const UP := Vector3.UP

## Couleurs des débris par genre d'ennemi (coques, sous-couches, accents lumineux des modèles sculptés).
const PALETTE := {
	"drone": [Color("#E8ECF4"), Color("#C8CEDC"), Color("#454E70"), Color("#FF4D6D")],
	"trooper": [Color("#C8CEDC"), Color("#9AA4B6"), Color("#2C3350"), Color("#FF4D6D")],
	"brute": [Color("#C8CEDC"), Color("#9AA4B6"), Color("#2C3350"), Color("#FFC83A"), Color("#FF7A2F")],
	"boss": [Color("#C8CEDC"), Color("#9AA4B6"), Color("#2C3350"), Color("#FF4D6D"), Color("#FFC83A")],
	"bomber": [Color("#C8CEDC"), Color("#1C2238"), Color("#FF7A2F"), Color("#EE3F5C")],
	"sniper": [Color("#C8CEDC"), Color("#2D2B5C"), Color("#6A5CFF"), Color("#9AA4B6")],
	"shield": [Color("#C8CEDC"), Color("#2C3350"), Color("#F45000"), Color("#FF7A2F")],
	"mortar": [Color("#9AA4B6"), Color("#2C3350"), Color("#7AD03A"), Color("#454E70")],
}
## Couleur d'accent (éclair, étincelles, onde) par genre.
const ACCENT := {
	"drone": Color("#FF4D6D"), "trooper": Color("#FF6A5A"), "brute": Color("#FF8A3C"), "boss": Color("#F23CB8"),
	"bomber": Color("#FF9A3C"), "sniper": Color("#9A7BFF"), "shield": Color("#FF8A2A"), "mortar": Color("#9BE15D"),
}
const WHITE_HOT := Color(1.0, 0.96, 0.85)
const FIRE_HOT := Color(2.1, 1.4, 0.5)
const FIRE_COOL := Color(0.75, 0.16, 0.05)
const GOLD := Color("#FFB347")

var view: Node3D
var now := 1.0
var glow: FxPool   # dégradé rond, additif : éclairs, étincelles étirées, braises, colonnes de lumière
var star: FxPool   # étoile à 4 branches : critiques, éclats de ramassage
var flare: FxPool  # flamme de bouche, étirée dans l'axe du tir
var fire: FxPool   # bouffées de feu additives
var smoke: FxPool  # bouffées de fumée opaques
var debris: FxPool # éclats de coque (prismes éclairés)
var decal: FxPool  # ondes, hexagones, lueurs au sol, sceaux
var scorch: FxPool # brûlures au sol
var trail: FxPool  # par image : traînées des projectiles et du butin
var marks: FxPool  # marques d'impact sur les caisses (wall_impact)
var _trail_n := 0
var _later: Array = []  # [heure, Callable] : secousses et lumières d'une séquence
var _drone_puff := {}   # id du Mob3D mourant -> prochaine bouffée de fumée

func setup(v: Node3D) -> void:
	view = v
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var radial: Texture2D = load("res://scripts/models.gd").radial()
	var puff: Texture2D = load("res://assets/fx/puff.png")
	var add_sh: Shader = load("res://shaders/fx_add.gdshader")
	var mix_sh: Shader = load("res://shaders/fx_mix.gdshader")
	scorch = FxPool.new(self, quad, load("res://shaders/fx_scorch.gdshader"), 40, {"tex": puff}, -4)
	decal = FxPool.new(self, quad, load("res://shaders/fx_decal.gdshader"), 160, {"energy": 1.0}, -3)
	smoke = FxPool.new(self, quad, mix_sh, 320, {"tex": puff, "fade_in": 0.1, "fade_pow": 1.0, "rise": 0.9, "spin": 1.2, "shade": 0.85}, 0)
	var prism := PrismMesh.new()
	prism.size = Vector3(1, 1, 1)
	debris = FxPool.new(self, prism, load("res://shaders/fx_debris.gdshader"), 320, {}, 0)
	# feu en fondu (pas additif) : les bouffées gardent leur forme ronde au lieu de saturer en blanc
	fire = FxPool.new(self, quad, mix_sh, 256, {"tex": puff, "fade_pow": 1.8, "spin": 2.0, "energy": 1.0, "shade": 0.55}, 1)
	trail = FxPool.new(self, quad, add_sh, 480, {"tex": radial, "energy": 1.0}, 1, true)
	glow = FxPool.new(self, quad, add_sh, 1024, {"tex": radial, "energy": 1.0, "fade_pow": 1.2}, 2)
	star = FxPool.new(self, quad, add_sh, 64, {"tex": load("res://assets/fx/star.png"), "energy": 1.0, "fade_pow": 1.5, "spin": 1.5}, 3)
	flare = FxPool.new(self, quad, add_sh, 64, {"tex": load("res://assets/fx/muzzle.png"), "energy": 1.0, "fade_pow": 0.7, "streak": 0.0}, 3)
	marks = FxPool.new(self, quad, load("res://shaders/fx_mark.gdshader"), WALL_MARKS, {}, -2)

## Vide tout (changement de salle) : on avance l'horloge, toutes les particules en cours sont mortes.
func clear() -> void:
	now += 1000.0
	_later.clear()
	_drone_puff.clear()
	_sync_time()

func tick(dt: float) -> void:
	now += dt
	_sync_time()
	var i := 0
	while i < _later.size():
		if now >= float(_later[i][0]):
			var cb: Callable = _later[i][1]
			_later.remove_at(i)
			cb.call()
		else:
			i += 1

func _sync_time() -> void:
	for p in [glow, star, flare, fire, smoke, debris, decal, scorch, trail, marks]:
		(p as FxPool).set_time(now)

func later(delay: float, cb: Callable) -> void:
	_later.append([now + delay, cb])

# ---------------------------------------------------------------- briques
static func _c4(c: Color, a: float = -1.0) -> Color:
	return Color(c.r * 0.25, c.g * 0.25, c.b * 0.25, c.a if a < 0.0 else a)

## Particule : départ, vitesse, vie, gravité, tailles, frein, couleurs, param (> 0 étirement, sinon rotation).
func _p(pool: FxPool, pos: Vector3, vel: Vector3, life: float, grav: float, s0: float, s1: float, drag: float, col: Color, endc: Color, prm: float = 0.0, delay: float = 0.0) -> void:
	if prm == 0.0:
		prm = -randf_range(0.001, 1.0)
	var e := _c4(endc)
	pool.put(pos, vel, Vector3(now + delay, life, grav), Vector3(s0, s1, drag), _c4(col), Color(e.r, e.g, e.b, prm))

## Éclair rond (lueur qui gonfle et s'éteint).
func flash(pos: Vector3, col: Color, size: float, life: float, delay: float = 0.0) -> void:
	_p(glow, pos, Vector3.ZERO, life, 0.0, size * 0.75, size * 1.15, 0.0, col, col, -randf_range(0.001, 1.0), delay)

## Étoile à 4 branches qui tourne un peu.
func sparkle(pos: Vector3, col: Color, size: float, life: float, delay: float = 0.0) -> void:
	_p(star, pos, Vector3.ZERO, life, 0.0, size * 0.5, size * 1.2, 0.0, col, col, -randf_range(0.001, 1.0), delay)

## Gerbe d'étincelles étirées autour de `dir` (ouverture `spread` : 0 = droit, 1 = demi-sphère large).
func sparks(pos: Vector3, dir: Vector3, n: int, spd: float, spread: float, col: Color, endc: Color, life: float, grav: float = 9.0, size: float = 0.07, stretch: float = 0.035, delay: float = 0.0) -> void:
	for i in range(n):
		var r := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		var d := (dir + r * spread).normalized()
		var v := d * spd * randf_range(0.45, 1.0)
		_p(glow, pos, v, life * randf_range(0.55, 1.0), grav, size, size * 0.4, 2.5, col, endc, stretch, delay)

## Braises : points lumineux lents qui montent ou retombent.
func embers(pos: Vector3, n: int, spd: float, col: Color, endc: Color, life: float, rad: float = 0.3, delay: float = 0.0) -> void:
	for i in range(n):
		var off := Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * rad
		var v := Vector3(randf_range(-1, 1), randf_range(0.6, 1.6), randf_range(-1, 1)) * spd
		_p(glow, pos + off, v, life * randf_range(0.6, 1.0), 2.5, 0.09, 0.03, 1.5, col, endc, 0.02, delay + randf() * 0.1)

## Onde, hexagone, lueur au sol ou sceau (styles 0..3 de fx_decal.gdshader).
func wave(pos: Vector3, normal: Vector3, col: Color, s0: float, s1: float, life: float, width: float = 0.12, style: int = 0, fill: float = 0.0, delay: float = 0.0, spin: float = 0.0) -> void:
	decal.put(pos, normal, Vector3(now + delay, life, float(style)), Vector3(s0, s1, width), _c4(col), Color(fill, spin, randf(), 0.0))

## Colonne de lumière verticale (apparitions, coffre, pouvoirs).
func column(pos: Vector3, col: Color, h: float, life: float, w: float = 0.9, delay: float = 0.0) -> void:
	# traînée inversée : tête vive au sol, queue qui s'efface en haut
	_p(glow, Vector3(pos.x, 0.05, pos.z), -UP * 1.0, life, 0.0, w, w * 0.25, 0.0, col, col, h, delay)

## Bouffées de feu (boule de feu dodue) de rayon `r`.
func fireball(pos: Vector3, r: float, n: int, delay: float = 0.0, hot: Color = FIRE_HOT, cool: Color = FIRE_COOL) -> void:
	for i in range(n):
		var off := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.9), randf_range(-1, 1)) * r * 0.4
		var v := (off.normalized() * randf_range(1.2, 2.6) + UP * randf_range(0.6, 1.6)) * r
		var h := hot.lerp(cool, randf() * 0.35)
		_p(fire, pos + off, v, randf_range(0.32, 0.55), -1.5, r * randf_range(0.5, 0.75), r * randf_range(1.1, 1.5), 5.0, Color(h, 0.95), cool, 0.0, delay + randf() * 0.05)

## Fumée : bouffées grises qui montent, partent chaudes et refroidissent.
func smoke_puffs(pos: Vector3, r: float, n: int, life: float = 1.3, delay: float = 0.05, warm: Color = Color(0.5, 0.4, 0.38), cool: Color = Color(0.46, 0.46, 0.56), alpha: float = 0.9, spread: float = 1.0) -> void:
	for i in range(n):
		var off := Vector3(randf_range(-1, 1), randf_range(0, 0.6), randf_range(-1, 1)) * r * 0.5 * spread
		var v := off.normalized() * r * randf_range(0.6, 1.5) * spread + UP * r * randf_range(0.4, 1.0)
		_p(smoke, pos + off, v, life * randf_range(0.75, 1.2), 0.0, r * 0.45, r * randf_range(1.3, 1.9), 2.8, Color(warm, alpha), cool, 0.0, delay + randf() * 0.08)

## Éclats de coque : `n` prismes aux couleurs de `pal`, poussés dans `dir`, chauds (lueur) si `hot` > 0.
func chunks(pos: Vector3, pal: Array, n: int, spd: float, dir: Vector3 = Vector3.ZERO, size: float = 0.12, hot: float = 0.0, delay: float = 0.0, flat: bool = false) -> void:
	for i in range(n):
		var v := Vector3(randf_range(-1, 1), randf_range(0.7, 1.7), randf_range(-1, 1)).normalized() * spd * randf_range(0.5, 1.15) + dir * spd * 0.6
		var spin := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(8.0, 18.0)
		var s := size * randf_range(0.6, 1.4)
		var asp := randf_range(0.25, 0.45) if flat else randf_range(0.55, 1.4)
		var c: Color = pal[i % pal.size()]
		debris.put(pos + Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15)), v, Vector3(now + delay, randf_range(1.1, 1.7), 14.0), Vector3(s, asp, 0.8), c, Color(spin.x, spin.y, spin.z, hot * randf_range(0.5, 1.0)))

## Brûlure au sol (cratère), braises qui refroidissent.
func burn(pos: Vector3, size: float, life: float, ember: float = 1.0, emb_col: Color = Color(1.0, 0.45, 0.12), delay: float = 0.0, alpha: float = 0.55) -> void:
	scorch.put(Vector3(pos.x, 0.025, pos.z), UP, Vector3(now + delay, life, 0.0), Vector3(size * 0.7, size, ember), Color(0.05, 0.05, 0.09, alpha), Color(emb_col.r * 0.25, emb_col.g * 0.25, emb_col.b * 0.25, randf()))

# ---------------------------------------------------------------- traînées (réécrites à chaque image)
func trail_begin() -> void:
	_trail_n = 0

## Traînée de `pos` vers l'arrière (`vel` m/s sur `len_s` s), largeur `w`.
func trail_add(pos: Vector3, vel: Vector3, col: Color, w: float, len_s: float, endc: Color = Color(-1, 0, 0)) -> void:
	if _trail_n >= trail.cap:
		return
	if endc.r < 0.0:
		endc = col
	var e := _c4(endc)
	trail.put_at(_trail_n, pos, vel, Vector3(now, 1.0, 0.0), Vector3(w, w, 0.0), _c4(col), Color(e.r, e.g, e.b, maxf(len_s, 0.001)))
	_trail_n += 1

func trail_end() -> void:
	trail.show(_trail_n)

# ---------------------------------------------------------------- effets composés
## Éclair de bouche de Jo : flamme dans l'axe, cœur, deux étincelles, douille éjectée.
func muzzle(p: Vector3, d: Vector3, col: Color, big: bool) -> void:
	var k := 1.35 if big else 1.0
	_p(flare, p + d * 0.05, d * 5.0, 0.07, 0.0, 0.5 * k, 0.3 * k, 0.0, Color(1.0, 0.98, 0.92), col, 0.1 * k)
	flash(p, col.lerp(Color.WHITE, 0.3), 0.8 * k, 0.06)
	sparkle(p, col.lerp(Color.WHITE, 0.5), 0.55 * k, 0.05)
	sparks(p, d, 2, 9.0, 0.35, Color(1, 1, 0.95), col, 0.12, 4.0, 0.05, 0.025)
	var side := d.cross(UP).normalized()
	var v := side * randf_range(1.6, 2.4) + UP * randf_range(2.2, 3.0) - d * 0.6
	var spin := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * 22.0
	debris.put(p - d * 0.15, v, Vector3(now, 0.75, 14.0), Vector3(0.05, 2.2, 0.5), Color("#E8B04A"), Color(spin.x, spin.y, spin.z, 0.25))

## Tir ennemi : petit éclair à sa couleur.
func enemy_muzzle(p: Vector3, d: Vector3, col: Color) -> void:
	_p(flare, p + d * 0.03, d * 3.0, 0.08, 0.0, 0.3, 0.2, 0.0, col.lerp(Color.WHITE, 0.5), col, 0.07)
	flash(p, col, 0.55, 0.08)

## Coup qui porte : éclat blanc, étincelles orientées vers l'extérieur de la cible, critique doré.
func hit(p: Vector3, n: Vector3, col: Color, crit: bool) -> void:
	p -= _cam_fwd() * 0.35  # devant la coque, pas dedans
	flash(p, Color(1, 1, 1), 0.38, 0.05)
	flash(p, col, 0.75, 0.09)
	sparks(p, n + UP * 0.25, 5, 7.5, 0.6, Color(1, 1, 0.95), col, 0.22, 10.0, 0.055, 0.03)
	if crit:
		sparkle(p, Color(1.0, 0.82, 0.35), 1.5, 0.16)
		wave(p, -_cam_fwd(), Color(1.0, 0.75, 0.3), 0.2, 1.3, 0.2, 0.18)
		sparks(p, n + UP * 0.4, 8, 10.0, 0.8, Color(1, 0.95, 0.7), Color(1.0, 0.55, 0.15), 0.32, 9.0, 0.07, 0.035)

## Tir bloqué par le bouclier du Rempart : onde hexagonale sur le bouclier, ricochet et gerbe jaune-orange.
func shield_block(p: Vector3, n: Vector3, vel_in: Vector3) -> void:
	var c := Color(1.0, 0.72, 0.22)
	# le bouclier est vertical, donc vu par la tranche d'en haut : l'onde penche vers la caméra pour se lire
	var nv := (n * 0.6 - _cam_fwd()).normalized()
	wave(p + nv * 0.08, nv, Color(1.0, 0.85, 0.45), 0.45, 1.9, 0.34, 0.1, 1)
	wave(p + nv * 0.09, nv, Color(1.0, 0.95, 0.8), 0.25, 1.2, 0.16, 0.08, 0)
	flash(p, Color(1.0, 0.85, 0.5), 0.6, 0.08)
	var refl := vel_in.bounce(n) if vel_in.length() > 0.01 else n
	refl.y = 0.0
	refl = refl.normalized()
	# ricochet : le trait repart, dévié, et s'éteint
	_p(glow, p, refl * 12.0 + UP * 2.5, 0.24, 9.0, 0.14, 0.07, 1.0, Color(1, 1, 0.9), c, 0.06)
	sparks(p, refl + UP * 0.3, 6, 8.0, 0.45, Color(1, 0.95, 0.7), Color(1.0, 0.45, 0.1), 0.25, 12.0, 0.05, 0.03)

## Projectile arrêté par un mur ou une caisse.
func wall_hit(p: Vector3, col: Color) -> void:
	flash(p, col, 0.45, 0.07)
	sparks(p, UP * 0.6, 3, 5.0, 0.9, Color(1, 1, 0.95), col, 0.18, 10.0, 0.05, 0.025)

## Explosion dodue : éclair, boule de feu, onde au sol, étincelles, braises, fumée, brûlure.
func explosion(pos: Vector3, r: float, col: Color, big: bool = false, delay: float = 0.0, scorch_on: bool = true, h: float = 0.45, front: float = 0.0) -> void:
	var g := Vector3(pos.x, 0.0, pos.z)
	# `front` : le feu avance vers la caméra pour ne pas se cacher dans un gros modèle
	var fc := g + UP * h + Vector3(0, 0, front)
	flash(fc + UP * 0.15, WHITE_HOT, r * 1.5, 0.09, delay)
	flash(fc, col, r * 2.6, 0.22, delay)
	fireball(fc, r, 14 if big else 9, delay)
	smoke_puffs(fc - UP * 0.05, r, 10 if big else 6, 1.5 if big else 1.2, delay + 0.12)
	wave(g + UP * 0.06, UP, col, r * 0.5, r * 2.8, 0.4, 0.22, 0, 0.35, delay)
	wave(g + UP * 0.07, UP, Color(1.0, 0.85, 0.6), r * 0.4, r * 3.6, 0.22, 0.06, 0, 0.0, delay)
	wave(g + UP * 0.05, UP, col, r * 3.4, r * 3.4, 0.35, 0.0, 2, 0.0, delay)
	sparks(fc, UP * 0.5, 20 if big else 14, 12.0, 1.0, Color(1, 0.95, 0.7), Color(1.0, 0.4, 0.1), 0.5, 12.0, 0.08, 0.04, delay)
	embers(fc, 12 if big else 7, 2.2, Color(1.0, 0.7, 0.3), Color(0.9, 0.2, 0.05), 1.1, r * 0.6, delay + 0.05)
	if scorch_on:
		burn(g, r * 1.9, 4.0, 1.0, Color(1.0, 0.45, 0.12), delay)

## Obus du mortier : explosion plus sèche (vert-jaune), cratère qui fume un instant.
func crater(pos: Vector3, r: float) -> void:
	var g := Vector3(pos.x, 0.0, pos.z)
	var lime := Color("#B8F06A")
	flash(g + UP * 0.5, Color(0.95, 1.0, 0.8), r * 1.5, 0.08)
	flash(g + UP * 0.4, lime, r * 2.2, 0.2)
	fireball(g + UP * 0.35, r * 0.8, 6, 0.0, Color(2.2, 2.1, 1.0), Color(0.7, 0.3, 0.05))
	wave(g + UP * 0.06, UP, lime, r * 0.5, r * 2.5, 0.35, 0.2, 0, 0.3)
	wave(g + UP * 0.05, UP, lime, r * 2.8, r * 2.8, 0.3, 0.0, 2)
	sparks(g + UP * 0.4, UP * 0.6, 12, 10.0, 0.9, Color(1, 1, 0.8), lime, 0.4, 12.0, 0.07, 0.04)
	chunks(g + UP * 0.2, [Color("#3A3F52"), Color("#2C3350"), Color("#5A6170")], 6, 5.0, Vector3.ZERO, 0.09, 0.6)
	burn(g, r * 1.7, 3.2, 1.0, Color(1.0, 0.6, 0.15))
	# le cratère fume : bouffées qui s'échappent une à une pendant ~1,4 s
	for k in range(7):
		var off := Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3)) * r
		_p(smoke, g + off, Vector3(randf_range(-0.2, 0.2), randf_range(0.6, 1.0), randf_range(-0.2, 0.2)), randf_range(1.0, 1.4), 0.0, r * 0.5, r * 1.5, 1.0, Color(0.55, 0.52, 0.5, 0.85), Color(0.42, 0.43, 0.52), 0.0, 0.1 + k * 0.18)
	embers(g + UP * 0.1, 6, 1.0, Color(1.0, 0.75, 0.3), Color(0.8, 0.2, 0.05), 1.4, r * 0.5, 0.1)

## Mort d'un ennemi, propre à chaque genre. `dir` : sens du dernier coup reçu (les débris partent avec).
func death(kind: String, pos: Vector3, dir: Vector3, elite: bool) -> void:
	var pal: Array = PALETTE.get(kind, PALETTE["trooper"])
	var acc: Color = ACCENT.get(kind, Color("#FF4D6D"))
	if elite:
		pal = pal + [GOLD]
	# éclairs et feu un peu devant le modèle (vers la caméra), sinon la coque les cache
	var c := pos + UP * 0.6 - _cam_fwd() * 0.45
	match kind:
		"drone":
			flash(c, WHITE_HOT, 1.6, 0.1)
			flash(c, acc, 2.4, 0.24)
			fireball(c, 0.5, 6)
			sparks(c, dir + UP * 0.3, 9, 9.0, 0.7, Color(1, 0.95, 0.85), acc, 0.3)
			chunks(c, pal, 5, 4.5, dir, 0.1, 0.4)
			wave(pos + UP * 0.05, UP, acc, 0.3, 1.8, 0.3, 0.14)
		"trooper":
			flash(c, WHITE_HOT, 1.3, 0.1)
			flash(c, acc, 2.0, 0.22)
			fireball(c, 0.45, 4)
			sparks(c, dir + UP * 0.4, 11, 9.0, 0.8, Color(1, 0.95, 0.85), Color(1.0, 0.45, 0.2), 0.35)
			chunks(c, pal, 8, 5.0, dir, 0.12, 0.5)
			smoke_puffs(c, 0.45, 3, 1.0, 0.1)
			wave(pos + UP * 0.05, UP, acc, 0.4, 2.3, 0.32, 0.14)
		"sniper":
			flash(c, Color(0.95, 0.9, 1.0), 1.3, 0.1)
			flash(c, acc, 2.2, 0.25)
			sparkle(c + UP * 0.2, acc.lerp(Color.WHITE, 0.3), 1.8, 0.2)
			sparks(c, dir + UP * 0.4, 12, 10.0, 0.8, Color(0.95, 0.9, 1.0), acc, 0.35)
			chunks(c + UP * 0.2, [Color("#B9A8FF"), Color("#6A5CFF"), Color("#E0D8FF")], 6, 5.5, dir, 0.09, 0.0, 0.0, true)
			chunks(c, pal, 5, 4.0, dir, 0.11, 0.3)
			wave(pos + UP * 0.05, UP, acc, 0.4, 2.3, 0.32, 0.14)
		"shield":
			flash(c, WHITE_HOT, 1.4, 0.1)
			flash(c, acc, 2.4, 0.25)
			fireball(c, 0.55, 5)
			# le bouclier vole en éclats : plaques hexagonales orange encore chaudes
			chunks(c + UP * 0.1, [Color("#F45000"), Color("#FF7A2F"), Color("#FFB347")], 9, 6.0, dir, 0.15, 1.0, 0.0, true)
			chunks(c, pal, 6, 4.5, dir, 0.13, 0.3)
			sparks(c, dir + UP * 0.4, 14, 10.0, 0.9, Color(1, 0.95, 0.7), Color(1.0, 0.45, 0.1), 0.4)
			smoke_puffs(c, 0.55, 4, 1.1, 0.1)
			wave(pos + UP * 0.05, UP, acc, 0.5, 2.8, 0.36, 0.16)
		"mortar":
			flash(c, Color(0.95, 1.0, 0.85), 1.4, 0.1)
			flash(c, acc, 2.4, 0.25)
			fireball(c, 0.55, 5)
			chunks(c, pal, 9, 5.0, dir, 0.13, 0.5)
			sparks(c, dir + UP * 0.4, 12, 9.0, 0.8, Color(1, 1, 0.8), acc, 0.35)
			smoke_puffs(c, 0.6, 5, 1.3, 0.1)
			wave(pos + UP * 0.05, UP, acc, 0.5, 2.6, 0.34, 0.16)
		"bomber":
			# l'explosion elle-même passe par `explosion` (signal exploded) : ici, les morceaux de la coque
			chunks(c, pal, 7, 6.0, dir, 0.12, 0.8)
		"brute":
			_brute_death(pos, dir, pal)
		"boss":
			_boss_death(pos, pal)
		_:
			flash(c, acc, 1.6, 0.2)
			chunks(c, pal, 6, 4.5, dir, 0.12, 0.3)
	if elite and kind != "boss":
		sparkle(c + UP * 0.3, GOLD, 2.4, 0.3)
		wave(pos + UP * 0.06, UP, GOLD, 0.6, 3.6, 0.45, 0.1)
		sparks(c, UP, 14, 9.0, 0.9, Color(1, 0.95, 0.7), GOLD, 0.5, 6.0, 0.08, 0.04)

## Colosse : grosse explosion, carcasse qui pète encore deux fois et fume.
func _brute_death(pos: Vector3, dir: Vector3, pal: Array) -> void:
	var g := Vector3(pos.x, 0.0, pos.z)
	explosion(g, 1.45, Color("#FF8A3C"), true, 0.0, true, 1.0, 0.7)
	chunks(g + UP * 0.8, pal, 16, 7.0, dir, 0.17, 0.7)
	chunks(g + UP * 0.6, pal, 6, 3.5, dir, 0.26, 0.4)
	for k in range(2):
		var off := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.5, 0.5))
		var d := 0.22 + k * 0.2
		off.z += 0.6
		flash(g + off + UP * 0.9, WHITE_HOT, 1.6, 0.1, d)
		fireball(g + off + UP * 0.9, 0.65, 6, d)
		sparks(g + off + UP * 0.8, UP, 8, 9.0, 0.9, Color(1, 0.95, 0.7), Color(1.0, 0.4, 0.1), 0.35, 12.0, 0.07, 0.035, d)
		later(d, func(): view.add_shake(0.3); view._flash_light(g + off + UP * 1.0, Color(1.0, 0.6, 0.3), 2.5, 4.5))
	# l'épave fume encore un moment
	for k in range(8):
		var off2 := Vector3(randf_range(-0.5, 0.5), 0.4, randf_range(-0.5, 0.5))
		_p(smoke, g + off2, Vector3(randf_range(-0.3, 0.3), randf_range(0.8, 1.3), randf_range(-0.3, 0.3)), randf_range(1.0, 1.4), 0.0, 0.45, 1.4, 0.8, Color(0.4, 0.38, 0.4, 0.75), Color(0.3, 0.31, 0.4), 0.0, 0.5 + k * 0.14)

## Le Portique : chapelet d'explosions sur la carcasse pendant 1,3 s, puis l'explosion finale.
func _boss_death(pos: Vector3, pal: Array) -> void:
	var g := Vector3(pos.x, 0.0, pos.z)
	var mag := Color("#F23CB8")
	for k in range(8):
		var d := 0.08 + k * 0.15
		var off := Vector3(randf_range(-1.4, 1.4), randf_range(0.8, 1.8), randf_range(0.2, 1.4))
		var col := mag if k % 2 == 0 else Color("#FF8A3C")
		flash(g + off, WHITE_HOT, 2.4, 0.12, d)
		flash(g + off, col, 3.2, 0.25, d)
		fireball(g + off, 0.95, 8, d)
		smoke_puffs(g + off, 0.8, 3, 1.4, d + 0.1)
		sparks(g + off, UP * 0.4, 10, 10.0, 1.0, Color(1, 0.95, 0.8), col, 0.4, 10.0, 0.08, 0.04, d)
		chunks(g + off, pal, 4, 5.0, Vector3.ZERO, 0.16, 0.6, d)
		wave(g + UP * 0.06, UP, col, 0.4, 2.6, 0.3, 0.15, 0, 0.2, d)
		later(d, func(): view.add_shake(0.35); view._flash_light(g + off, col, 3.0, 6.0))
	var fd := 1.35
	explosion(g, 3.0, mag, true, fd, true, 1.2, 1.2)
	explosion(g + Vector3(0.8, 0, 0.4), 1.8, Color("#FF8A3C"), true, fd + 0.08, false, 1.0, 1.2)
	flash(g + UP * 1.2, WHITE_HOT, 10.0, 0.3, fd)
	wave(g + UP * 0.08, UP, Color(1.0, 0.85, 1.0), 1.0, 16.0, 0.7, 0.05, 0, 0.0, fd)
	wave(g + UP * 0.09, UP, mag, 1.0, 12.0, 0.9, 0.12, 0, 0.25, fd + 0.05)
	chunks(g + UP * 1.0, pal, 30, 9.0, Vector3.ZERO, 0.22, 0.8, fd)
	sparks(g + UP * 1.0, UP, 40, 16.0, 1.0, Color(1, 0.95, 0.85), mag, 0.8, 10.0, 0.1, 0.05, fd)
	sparkle(g + UP * 1.5, Color(1.0, 0.8, 1.0), 9.0, 0.5, fd)
	embers(g + UP * 0.5, 30, 3.0, Color(1.0, 0.6, 0.9), mag, 2.0, 1.5, fd)
	column(g, mag, 10.0, 0.9, 3.0, fd)
	later(fd, func():
		view.add_shake(1.0)
		view.hit_stop(0.45, 0.25)
		view._flash_light(g + UP * 2.0, mag, 6.0, 14.0)
		view._flash_light(g + UP * 1.0, Color(1.0, 0.7, 0.4), 5.0, 10.0))

## Sentinelle qui tombe : fumée derrière elle, petit choc à l'arrivée au sol (appelé à chaque image).
func tick_dying(dying: Array) -> void:
	for m in dying:
		if not is_instance_valid(m) or m.kind != "drone":
			continue
		var id: int = m.get_instance_id()
		var src: Node3D = m.rig if m.rig != null else m.body
		var p: Vector3 = src.global_position + UP * 0.45
		var nxt: float = _drone_puff.get(id, 0.0)
		if m.dying < 0.6 and now >= nxt:
			_drone_puff[id] = now + 0.03
			_p(smoke, p, Vector3(randf_range(-0.3, 0.3), 0.6, randf_range(-0.3, 0.3)), 0.8, 0.0, 0.18, 0.6, 1.5, Color(0.5, 0.45, 0.45, 0.8), Color(0.35, 0.35, 0.45))
			_p(glow, p, Vector3.ZERO, 0.12, 0.0, 0.3, 0.15, 0.0, Color(1.0, 0.6, 0.25), Color(1.0, 0.3, 0.1))
		if m.dying >= 0.5 and not _drone_puff.has(-id):
			_drone_puff[-id] = true
			var gp := Vector3(p.x, 0.05, p.z)
			flash(gp + UP * 0.3, Color(1.0, 0.7, 0.4), 1.1, 0.12)
			smoke_puffs(gp + UP * 0.2, 0.4, 4, 0.9, 0.0)
			sparks(gp + UP * 0.2, UP, 6, 6.0, 0.9, Color(1, 0.9, 0.7), Color(1.0, 0.4, 0.1), 0.3)
			burn(gp, 0.8, 2.0, 0.6)

## Apparition d'un ennemi sur un sas : sceau qui tourne, colonne, étincelles qui montent.
func spawn_in(pos: Vector3, col: Color, boss: bool) -> void:
	var k := 2.6 if boss else 1.0
	var g := Vector3(pos.x, 0.0, pos.z)
	wave(g + UP * 0.05, UP, col, 0.6 * k, 2.4 * k, 0.6, 0.0, 3, 0.0, 0.0, 4.0)
	wave(g + UP * 0.06, UP, Color(1, 1, 1), 0.2 * k, 2.2 * k, 0.3, 0.1, 0, 0.15)
	column(g, col, 3.8 * k, 0.45, 0.9 * k)
	flash(g + UP * 0.8, col, 1.8 * k, 0.2)
	sparks(g + UP * 0.1, UP, 8 if not boss else 24, 6.0, 0.35, Color(1, 1, 1), col, 0.5, -2.0, 0.06, 0.03)

## Début de vague : chaque sas s'allume (sceau large, colonne, gerbe), en cascade.
func wave_start(pads: Array, col: Color) -> void:
	var i := 0
	for p in pads:
		var g: Vector3 = p
		var d := i * 0.06
		var wc := col.lerp(Color.WHITE, 0.35)
		wave(g + UP * 0.05, UP, wc, 1.2, 4.4, 1.0, 0.0, 3, 0.0, d, -3.0)
		wave(g + UP * 0.06, UP, col, 0.4, 5.5, 0.6, 0.1, 0, 0.25, d)
		wave(g + UP * 0.07, UP, Color(1, 1, 1), 0.3, 3.0, 0.3, 0.06, 0, 0.0, d + 0.08)
		wave(g + UP * 0.04, UP, col, 3.4, 3.4, 0.7, 0.0, 2, 0.0, d)
		column(g, wc, 6.0, 0.8, 1.6, d)
		flash(g + UP * 0.6, col, 3.0, 0.3, d)
		sparks(g + UP * 0.1, UP, 16, 8.0, 0.3, Color(1, 1, 1), col, 0.8, -1.0, 0.08, 0.04, d)
		i += 1

## Ramassage qui arrive sur Jo : petit éclat et anneau.
func pickup_pop(p: Vector3, col: Color, big: bool = false) -> void:
	var k := 1.8 if big else 1.0
	sparkle(p, col.lerp(Color.WHITE, 0.3), 0.9 * k, 0.16)
	flash(p, col, 0.7 * k, 0.12)
	wave(Vector3(p.x, 0.06, p.z), UP, col, 0.2, 1.0 * k, 0.22, 0.2)
	sparks(p, UP, 4 if not big else 10, 4.0, 0.8, Color(1, 1, 0.9), col, 0.3, 6.0, 0.05, 0.03)

## Jo touchée : gerbe rouge, onde rouge.
func hero_hit(p: Vector3) -> void:
	var red := Color("#FF4D6D")
	flash(p + UP * 0.6, Color(1.0, 0.5, 0.5), 1.3, 0.12)
	sparks(p + UP * 0.6, UP * 0.5, 10, 7.0, 1.0, Color(1, 0.9, 0.9), red, 0.3, 10.0, 0.06, 0.03)
	wave(Vector3(p.x, 0.06, p.z), UP, red, 0.3, 2.0, 0.3, 0.16, 0, 0.25)

## Énergie pleine / pouvoir : anneaux et colonne autour de Jo. `pre` vieillit l'effet (image figée sous l'écran de choix).
func power_burst(p: Vector3, col: Color, col2: Color, pre: float = 0.0) -> void:
	var g := Vector3(p.x, 0.0, p.z)
	var d := -pre
	wave(g + UP * 0.05, UP, col, 0.6, 4.2, 0.7, 0.0, 3, 0.0, d, 3.0)
	wave(g + UP * 0.06, UP, col, 0.3, 4.5, 0.5, 0.14, 0, 0.3, d)
	wave(g + UP * 0.07, UP, col2, 0.2, 2.6, 0.35, 0.1, 0, 0.0, d)
	column(g, col, 5.0, 0.6, 1.6, d)
	flash(g + UP * 0.8, col2, 3.2, 0.25, d)
	sparkle(g + UP * 1.0, col2.lerp(Color.WHITE, 0.4), 2.6, 0.3, d)
	sparks(g + UP * 0.3, UP, 18, 8.0, 0.7, Color(1, 1, 1), col, 0.6, 3.0, 0.07, 0.035, d)

## Coffre ouvert : fontaine d'étincelles dorées.
func chest_burst(p: Vector3) -> void:
	var g := Vector3(p.x, 0.0, p.z)
	sparkle(g + UP * 0.9, Color(1.0, 0.9, 0.6), 3.0, 0.3)
	sparks(g + UP * 0.6, UP, 24, 9.0, 0.5, Color(1, 0.97, 0.8), GOLD, 0.9, 9.0, 0.08, 0.035)
	embers(g + UP * 0.6, 14, 1.5, Color(1.0, 0.85, 0.4), GOLD, 1.6, 0.5)
	wave(g + UP * 0.06, UP, GOLD, 0.6, 4.0, 0.7, 0.0, 3, 0.0, 0.0, 2.0)

var _fwd := Vector3(0, -0.83, -0.56)
var _fwd_t := -1.0

## Axe de la caméra (relu une fois par image).
func _cam_fwd() -> Vector3:
	if _fwd_t != now:
		_fwd_t = now
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			_fwd = -cam.global_transform.basis.z
	return _fwd

# ---------------------------------------------------------------- tirs de Jo et impacts sur le décor
## Réglages : flamme de bouche, douilles, fumée de canon, impacts sur les murs et les caisses.
const SHOT_FLARE := 1.0      # taille des flammes de bouche de Jo
const SHOT_CASING := 1.0     # taille des douilles éjectées (0 : aucune)
const SHOT_SMOKE := 0.3      # opacité de la fumée de canon en rafale (0 : aucune)
const WALL_MARKS := 48       # marques d'impact gardées en même temps (anneau)
const WALL_MARK_LIFE := 3.5  # s avant qu'une marque s'efface
const WALL_SPARKS := 6       # étincelles par impact
const WALL_MARK_SIZE := 0.3  # diamètre d'une marque (m)
const WALL_MARK_OUT := 0.04  # décollement de la face (m) : les cornières des caisses dépassent un peu
const BRASS := Color("#F2C14E")
## Styles de flamme par arme (rig3d.GUN_FEEL « fx ») : « glow » couleur de la flamme et de l'éclair (mêlée à la
## couleur du tir selon « mix » : 0 = couleur du tir, 1 = couleur de l'arme), longueur et largeur de la flamme,
## douille (couleur, taille, allongement ; taille 0 : rien d'éjecté).
const SHOT_STYLE := {
	"blaster": {"glow": Color(0.6, 1.0, 0.95), "mix": 0.0, "len": 0.1, "w": 0.55, "case": BRASS, "cs": 0.05, "ca": 2.0},
	"garde": {"glow": Color(1.0, 0.85, 0.5), "mix": 0.55, "len": 0.08, "w": 0.62, "case": BRASS, "cs": 0.055, "ca": 2.2},
	"impulsion": {"glow": Color(0.55, 0.85, 1.0), "mix": 0.6, "len": 0.24, "w": 0.42, "case": Color(0, 0, 0), "cs": 0.0, "ca": 1.0},
	"rivet": {"glow": Color(1.0, 0.5, 0.18), "mix": 0.75, "len": 0.05, "w": 0.8, "case": Color("#B8C0CE"), "cs": 0.055, "ca": 1.1},
	"rayon": {"glow": Color(1.0, 0.35, 0.85), "mix": 0.7, "len": 0.06, "w": 0.42, "case": Color(0, 0, 0), "cs": 0.0, "ca": 1.0},
}

## Flamme de bouche de Jo selon l'arme portée. `first` : premier tir de la salve (flamme complète, douille,
## fumée) ; sinon seulement la flamme dans l'axe de ce tir. `heat` : chauffe du canon (rig3d.jo_heat).
func shot_muzzle(p: Vector3, d: Vector3, col: Color, style: String, big: bool, heat: float, first: bool) -> void:
	var st: Dictionary = SHOT_STYLE.get(style, SHOT_STYLE["blaster"])
	var k := (1.3 if big else 1.0) * SHOT_FLARE
	var c := col.lerp(st["glow"], st["mix"])
	var w: float = st["w"]
	_p(flare, p + d * 0.05, d * 5.0, 0.065, 0.0, w * k, w * 0.55 * k, 0.0, Color(1.0, 0.98, 0.92), c, float(st["len"]) * k)
	if not first:
		return
	var side := d.cross(UP).normalized()
	# disque tourné vers la caméra (vu d'en haut, un disque dans l'axe du tir serait vu par la tranche)
	var face := (d * 0.55 - _cam_fwd()).normalized()
	flash(p, c, 0.9 * k, 0.06)
	flash(p - d * 0.02, Color(1, 1, 0.95), 0.3 * k, 0.035)
	match style:
		"garde":
			# frein de bouche : deux jets courts sur les côtés, étincelles chaudes
			for sd in [side, -side]:
				_p(flare, p + d * 0.03, (sd as Vector3) * 4.0 + d * 1.5, 0.06, 0.0, 0.34 * k, 0.16 * k, 0.0, Color(1, 0.95, 0.8), c, 0.06)
			sparks(p, d, 3, 9.0, 0.4, Color(1, 0.95, 0.8), Color(1.0, 0.55, 0.2), 0.14, 6.0, 0.05, 0.025)
		"impulsion":
			# anneaux d'impulsion qui partent devant le canon
			wave(p + d * 0.15, face, c.lerp(Color.WHITE, 0.3), 0.1 * k, 0.5 * k, 0.1, 0.2)
			wave(p + d * 0.45, face, c, 0.06 * k, 0.36 * k, 0.09, 0.26, 0, 0.0, 0.025)
		"rivet":
			# gerbe d'étincelles orange qui retombent, petite bouffée à chaque coup
			sparks(p, d + UP * 0.2, 6, 8.0, 0.6, Color(1, 0.9, 0.6), Color(1.0, 0.4, 0.1), 0.32, 14.0, 0.055, 0.03)
			_p(smoke, p + d * 0.12, d * 1.2 + UP * 0.3, 0.45, 0.0, 0.1, 0.32, 3.0, Color(0.62, 0.6, 0.62, 0.3), Color(0.5, 0.52, 0.6))
		"rayon":
			# rayon : étoile rose et anneau, pas de douille
			sparkle(p, c.lerp(Color.WHITE, 0.25), 1.0 * k, 0.08)
			wave(p + d * 0.1, face, c, 0.08 * k, 0.5 * k, 0.12, 0.2)
		_:
			sparkle(p, c.lerp(Color.WHITE, 0.5), 0.55 * k, 0.05)
			sparks(p, d, 2, 9.0, 0.35, Color(1, 1, 0.95), c, 0.12, 4.0, 0.05, 0.025)
	var cs: float = float(st["cs"]) * SHOT_CASING
	if cs > 0.0:
		shot_casing(p - d * 0.15, d, st["case"], cs, st["ca"])
	# rafale continue : le canon fume (filet clair qui monte), plus dense quand il chauffe
	if heat > 0.5 and SHOT_SMOKE > 0.0:
		var a := SHOT_SMOKE * clampf((heat - 0.5) * 1.5, 0.0, 1.0)
		_p(smoke, p + d * 0.05 + UP * 0.05, Vector3(randf_range(-0.15, 0.15), 0.5, randf_range(-0.15, 0.15)) + d * 0.3, randf_range(0.6, 0.9), 0.0, 0.07, 0.3, 1.5, Color(0.8, 0.82, 0.88, a), Color(0.62, 0.64, 0.74), 0.0, 0.03)

## Douille (ou rivet usé) éjectée sur le côté de l'arme : vole, rebondit une fois au sol, reste un instant, s'efface.
func shot_casing(p: Vector3, d: Vector3, col: Color, size: float, asp: float) -> void:
	var side := d.cross(UP).normalized()
	var v := side * randf_range(1.6, 2.6) + UP * randf_range(2.0, 3.0) - d * randf_range(0.4, 0.9)
	var spin := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(16.0, 26.0)
	debris.put(p, v, Vector3(now, randf_range(1.1, 1.4), 14.0), Vector3(size, asp, 0.6), col, Color(spin.x, spin.y, spin.z, 0.35))

## Tir arrêté par un mur ou une caisse : étincelles renvoyées selon la normale `n`, éclat, poussière, éclats de
## peinture et, sur une caisse (`mark`), une marque chaude qui refroidit puis s'efface.
func wall_impact(p: Vector3, n: Vector3, col: Color, mark: bool, strong: bool = false) -> void:
	var k := 1.3 if strong else 1.0
	var q := p + n * 0.06
	flash(q, Color(1, 1, 0.95), 0.36 * k, 0.04)
	flash(q, col, 0.9 * k, 0.1)
	sparkle(q, col.lerp(Color.WHITE, 0.6), 0.5 * k, 0.05)
	sparks(q, n + UP * 0.35, WALL_SPARKS, 7.5 * k, 0.5, Color(1, 1, 0.92), col, 0.24, 11.0, 0.05, 0.03)
	sparks(q, n + UP * 0.6, 2, 4.0, 0.7, Color(1, 0.85, 0.5), Color(1.0, 0.4, 0.1), 0.45, 9.0, 0.035, 0.02)
	# poussière soufflée hors de l'impact, qui retombe lentement
	_p(smoke, q, n * 0.9 + UP * 0.25, randf_range(0.45, 0.6), 0.0, 0.12 * k, 0.42 * k, 4.0, Color(0.6, 0.6, 0.66, 0.32), Color(0.45, 0.47, 0.56))
	# éclats de peinture
	for i in range(2):
		var v := (n + Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 0.9), randf_range(-0.6, 0.6))).normalized() * randf_range(2.0, 3.5)
		var sp := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * 18.0
		debris.put(q, v, Vector3(now, randf_range(0.5, 0.8), 12.0), Vector3(0.035, 0.35, 1.0), Color(0.3, 0.32, 0.4), Color(sp.x, sp.y, sp.z, 0.0))
	if mark:
		var hot := col.lerp(Color(1.0, 0.6, 0.25), 0.5)
		marks.put(p + n * WALL_MARK_OUT, n, Vector3(now, WALL_MARK_LIFE, 0.0), Vector3(WALL_MARK_SIZE * k, 1.0, 0.0), Color(0.08, 0.08, 0.11, 0.85), Color(hot.r * 0.25, hot.g * 0.25, hot.b * 0.25, randf()))
