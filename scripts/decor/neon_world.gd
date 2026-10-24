extends RefCounted
## Monde 2 — Cité Néon (mégapole cyberpunk, la nuit, sous la pluie) : décor de l'arène, un toit-terrasse au
## sommet d'une tour. Contrat avec le jeu (voir view3d.gd `_build_level`, arena.gd `_layout`) :
## - BOXES : obstacles de l'arène (Rect2 en px, dans l'aire de jeu W × H hors marges WALL et TOP), fournis par
##   neon_props.gd qui les habille (build) ;
## - build(v, rng) : construit le décor sous v.level (helpers v._mm, v._bput, v._bbox, v._ground_quad) ;
##   les sas d'apparition (arena.pads) sont posés par la vue elle-même ;
## - lights(v) : lumières (après le regroupement du décor statique) ;
## - env(v) : ambiance (v.env, v.sun), appliquée après les réglages par défaut de Nébuleuse 7 (view3d._env_defaults
##   remet le panorama et le reste quand on revient au monde 1).
## Coque (sol, bords, tour voisine) : neon_shell.gd ; ville en contrebas et ciel : neon_city.gd ;
## pluie, brume, drones-taxis : neon_fx.gd ; obstacles et accessoires : neon_props.gd.

const NeonShell = preload("res://scripts/decor/neon_shell.gd")
const NeonCity = preload("res://scripts/decor/neon_city.gd")
const NeonFx = preload("res://scripts/decor/neon_fx.gd")
const NeonProps = preload("res://scripts/decor/neon_props.gd")
## Obstacles : définis avec leur habillage par scripts/decor/neon_props.gd.
const BOXES := NeonProps.BOXES

const PINK := Color("#FF3CAC")
const BLUE := Color("#3C8CFF")
const VIOLET := Color("#8E4CFF")

static func build(v: Node, rng: RandomNumberGenerator) -> void:
	NeonShell.build(v, rng)
	NeonCity.build(v)
	NeonFx.build(v)
	NeonProps.build(v, rng)

## Trois lumières dynamiques au plus, pour les obstacles et les personnages (le sol et les bords ont leur
## éclairage simulé) : la façade rose au nord, les tubes bleus à l'est, les tubes roses à l'ouest.
static func lights(v: Node) -> void:
	var K: float = v.K
	var W: float = v.arena.W * K
	var H: float = v.arena.H * K
	var ls := [[Vector3(W * 0.5, 3.2, 1.2), Color("#E05AD0"), 13.0, 1.5],
		[Vector3(W - 1.2, 1.6, H * 0.55), BLUE, 10.0, 0.9],
		[Vector3(1.2, 1.6, H * 0.55), PINK, 10.0, 0.9]]
	for i in range(ls.size()):
		var L: Array = ls[i]
		var ol: OmniLight3D = ScreenLight.new() if i == 0 else OmniLight3D.new()
		ol.position = L[0]
		ol.light_color = L[1]
		ol.omni_range = L[2]
		ol.light_energy = L[3]
		ol.omni_attenuation = 1.3
		ol.light_cull_mask = 0xFFFFF & ~NeonShell.DECK_LAYER
		(v.level as Node3D).add_child(ol)

static func env(v: Node) -> void:
	var env: Environment = v.env
	var pano: PanoramaSkyMaterial = env.sky.sky_material
	pano.panorama = load(NeonShell.NS + "neon_sky.png")
	pano.energy_multiplier = 1.0
	env.ambient_light_color = Color(0.45, 0.48, 0.6)
	env.ambient_light_energy = 0.28
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	env.adjustment_saturation = 1.05
	var sun: DirectionalLight3D = v.sun
	# lune au nord, haute : ombres portées vers le sud
	sun.rotation_degrees = Vector3(-52, 180, 0)
	sun.light_color = Color(0.62, 0.66, 1.0)
	sun.light_energy = 0.7

## Lumière de la façade : prend la couleur de la scène en cours sur l'écran géant (même suite que
## neon_screen.gdshaderinc, écran 0, graine 1), avec un léger battement.
class ScreenLight extends OmniLight3D:
	const PAL := [Color("#FF3CAC"), Color("#3C8CFF"), Color("#8E4CFF"), Color("#B6FF3C"), Color("#FF8A3C")]
	var base := 1.5

	func _ready() -> void:
		base = light_energy

	func _process(dt: float) -> void:
		var t := Time.get_ticks_msec() / 1000.0
		var k := int(floor(1.0 * 3.0 + floor(t / 7.0 + 1.0))) % 5
		var target: Color = (PAL[k] as Color).lerp(Color("#E05AD0"), 0.35)
		light_color = light_color.lerp(target, clampf(dt * 3.0, 0.0, 1.0))
		light_energy = base * (0.92 + 0.08 * sin(t * 37.0))
