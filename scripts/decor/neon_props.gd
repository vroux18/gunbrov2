extends RefCounted
## Monde 2 — Cité Néon : obstacles (et leur habillage) et accessoires de l'arène. Appelé par neon_world.gd.
## Version provisoire : blocs sombres à liseré néon ; le vrai décor la remplace.

const Models = preload("res://scripts/models.gd")
const PINK := Color("#FF3CAC")

## Obstacles de l'arène (Rect2 en px) : collision de la simulation, à couvrir entièrement par le décor.
const BOXES := [
	Rect2(480, 330, 140, 120), Rect2(1760, 330, 140, 120),
	Rect2(420, 980, 160, 90), Rect2(1820, 980, 160, 90),
	Rect2(1080, 560, 90, 90), Rect2(1230, 760, 90, 90),
	Rect2(780, 700, 70, 150), Rect2(1550, 520, 70, 150),
	Rect2(1120, 1150, 160, 70),
]

static func build(v: Node, rng: RandomNumberGenerator) -> void:
	var K: float = v.K
	for o in v.arena.obstacles:
		var r: Rect2 = o
		var c: Vector3 = v.p3(r.get_center())
		v._bbox("neon_block", Models.toon(Color("#2A2448"), 0.3), c + Vector3(0, 0.4, 0), Vector3(r.size.x * K, 0.8, r.size.y * K))
		v._bbox("neon_rim", Models.glow_mat(PINK, 1.6), c + Vector3(0, 0.82, 0), Vector3(r.size.x * K + 0.06, 0.04, r.size.y * K + 0.06))
