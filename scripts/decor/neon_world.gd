extends RefCounted
## Monde 2 — Cité Néon (mégapole cyberpunk, la nuit, sous la pluie) : décor de l'arène.
## Contrat avec le jeu (voir view3d.gd `_build_level`, arena.gd `_layout`) :
## - BOXES : obstacles de l'arène (Rect2 en px, dans l'aire de jeu W × H hors marges WALL et TOP), fournis par
##   neon_props.gd qui les habille (build) ;
## - build(v, rng) : construit le décor sous v.level (helpers v._mm, v._bput, v._bbox, v._ground_quad) ;
##   les sas d'apparition (arena.pads) sont posés par la vue elle-même ;
## - lights(v) : lumières (après le regroupement du décor statique) ;
## - env(v) : ambiance (v.env, v.sun), appliquée après les réglages par défaut de Nébuleuse 7.
## Version provisoire : sol sombre, bandes néon ; le vrai décor la remplace.

const Models = preload("res://scripts/models.gd")
const PINK := Color("#FF3CAC")
const BLUE := Color("#3C8CFF")

const NeonProps = preload("res://scripts/decor/neon_props.gd")
## Obstacles : définis avec leur habillage par scripts/decor/neon_props.gd.
const BOXES := NeonProps.BOXES

static func build(v: Node, rng: RandomNumberGenerator) -> void:
	var K: float = v.K
	var W: float = v.arena.W * K
	var H: float = v.arena.H * K
	var level: Node3D = v.level
	var floor_mi := Models.box(Vector3(W, 0.2, H), Models.toon(Color("#1A1630"), 0.2))
	floor_mi.position = Vector3(W * 0.5, -0.1, H * 0.5)
	level.add_child(floor_mi)
	NeonProps.build(v, rng)

static func lights(v: Node) -> void:
	var K: float = v.K
	var W: float = v.arena.W * K
	var H: float = v.arena.H * K
	for L in [[Vector3(W * 0.25, 3.0, H * 0.5), PINK], [Vector3(W * 0.75, 3.0, H * 0.5), BLUE]]:
		var ol := OmniLight3D.new()
		ol.position = L[0]
		ol.light_color = L[1]
		ol.omni_range = 14.0
		ol.light_energy = 1.2
		(v.level as Node3D).add_child(ol)

static func env(v: Node) -> void:
	var env: Environment = v.env
	env.ambient_light_color = Color(0.45, 0.35, 0.75)
	env.ambient_light_energy = 0.35
	var sun: DirectionalLight3D = v.sun
	sun.light_color = Color(0.6, 0.65, 1.0)
	sun.light_energy = 0.45
