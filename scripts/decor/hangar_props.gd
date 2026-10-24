extends RefCounted
## Nébuleuse 7 — obstacles (caisses de fret posées sur les rectangles bloquants de la simulation) et
## accessoires non bloquants des coins. Appelé par view3d.gd avec la vue `v` (voir hangar_shell.gd).

const Models = preload("res://scripts/models.gd")
const ST := "res://assets/models/station/"
const SP := "res://assets/models/space/"

static func build(v: Node, rng: RandomNumberGenerator) -> void:
	var K: float = v.K
	var W: float = v.arena.W * K
	var H: float = v.arena.H * K
	var WALL: float = v.arena.WALL * K
	var TOP: float = v.arena.TOP * K
	for o in v.arena.obstacles:
		crate_block(v, o, rng)
	# décor des coins de l'arène (non bloquant, au ras des murs)
	for c in [Vector3(WALL + 0.45, 0, TOP + 0.6), Vector3(W - WALL - 0.45, 0, TOP + 0.6)]:
		v._bput(SP + "barrels.glb", c, rng.randf() * TAU, Vector3.ONE * 0.9, true)
	for c in [Vector3(WALL + 0.4, 0, H - WALL - 0.5), Vector3(W - WALL - 0.4, 0, H - WALL - 0.5)]:
		v._bput(SP + "machine_barrel.glb", c, 0.0, Vector3.ONE * 0.9, true)

## Une caisse de fret faite en code (pièces ajoutées au lot) : coque acier, couvercle clair, montants
## sombres, bande orange, voyant.
static func crate(v: Node, base: Vector3, size: Vector3, rot: float, rng: RandomNumberGenerator) -> void:
	var b := Basis(Vector3.UP, rot)
	var steel := Models.toon(Color("#28325A"), 0.3)
	var lid := Models.toon(Color("#3A4778"), 0.25)
	var post := Models.toon(Color("#1C2238"), 0.2)
	v._bbox("crate_body", steel, base + Vector3(0, size.y * 0.5, 0), size - Vector3(0.06, 0.06, 0.06), rot)
	v._bbox("crate_lid", lid, base + Vector3(0, size.y, 0), Vector3(size.x - 0.16, 0.06, size.z - 0.16), rot)
	for cx in [-1, 1]:
		for cz in [-1, 1]:
			var off := b * Vector3(cx * (size.x * 0.5 - 0.05), 0, cz * (size.z * 0.5 - 0.05))
			v._bbox("crate_post", post, base + off + Vector3(0, size.y * 0.5, 0), Vector3(0.1, size.y, 0.1), rot)
	v._bbox("crate_band", Models.toon(Color("#FF7A2F"), 0.2, Color("#FF7A2F"), 0.35), base + Vector3(0, size.y * 0.78, 0), Vector3(size.x + 0.01, 0.08, size.z + 0.01), rot)
	v._bbox("crate_ribs", post, base + Vector3(0, size.y * 0.36, 0), Vector3(size.x * 0.6, size.y * 0.42, size.z + 0.02), rot)
	var red := rng.randf() < 0.3
	v._bbox("crate_led_r" if red else "crate_led_c", Models.glow_mat(Color("#FF4D6D") if red else Color("#3CF2D8"), 2.5), base + b * Vector3(size.x * 0.28, size.y * 0.62, size.z * 0.5 + 0.02), Vector3(0.1, 0.06, 0.03), rot)


static func crate_block(v: Node, o: Rect2, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = v.p3(o.get_center())
	var sx: float = o.size.x * v.K
	var sz: float = o.size.y * v.K
	var cols := maxi(1, int(round(sx / 1.15)))
	var rows := maxi(1, int(round(sz / 1.15)))
	var cw: float = sx / cols
	var ch: float = sz / rows
	for ix in range(cols):
		for iz in range(rows):
			var h := 0.85 + rng.randf() * 0.4
			var pos: Vector3 = c + Vector3(-sx * 0.5 + cw * (ix + 0.5), 0, -sz * 0.5 + ch * (iz + 0.5))
			crate(v, pos, Vector3(cw - 0.04, h, ch - 0.04), rng.randf_range(-0.03, 0.03), rng)
			if rng.randf() < 0.16:
				v._bput(ST + ("container-tall.glb" if rng.randf() < 0.5 else "container.glb"), pos + Vector3(rng.randf_range(-0.15, 0.15), h, rng.randf_range(-0.15, 0.15)), rng.randf() * TAU, Vector3.ONE * 1.2, true)
	v._bbox("crate_rim", Models.glow_mat(Color("#FF7A2F"), 1.1), c + Vector3(0, 0.015, 0), Vector3(sx + 0.14, 0.03, sz + 0.14))
