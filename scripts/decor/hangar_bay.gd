extends RefCounted
## Nébuleuse 7 — quai nord (hors de l'aire de jeu, au-dessus du garde-corps) : vaisseau du Relais garé,
## consoles, machines. Appelé par view3d.gd avec la vue `v` (voir hangar_shell.gd).

const Models = preload("res://scripts/models.gd")
const ST := "res://assets/models/station/"
const SP := "res://assets/models/space/"
const CYAN := Color("#3CF2D8")
const ORANGE := Color("#FF7A2F")

static func build(v: Node, rng: RandomNumberGenerator) -> void:
	var W: float = v.arena.W * v.K
	var TOP: float = v.arena.TOP * v.K
	var level: Node3D = v.level
	# sol du quai
	var bay := []
	for ix in range(int(ceil(W))):
		for iz in range(int(ceil(TOP))):
			if iz + 0.5 < TOP:
				bay.append(Transform3D(Basis(), Vector3(ix + 0.5, -0.3, iz + 0.5)))
	v._mm(Models.mesh_of(ST + "floor-panel-straight.glb"), bay)
	# bord lumineux du quai, garde-corps interrompu au centre devant le sas
	var edge := Models.box(Vector3(W - 2.0 * v.arena.WALL * v.K, 0.03, 0.08), Models.glow_mat(ORANGE, 1.8))
	edge.position = Vector3(W * 0.5, 0.015, TOP + 0.05)
	level.add_child(edge)
	for ix in range(int(ceil(W))):
		var x := ix + 0.5
		if absf(x - W * 0.5) < 1.6:
			continue
		v._bput(ST + "rail.glb", Vector3(x, 0, TOP - 0.05), 0.0)
	# mur nord à fenêtres sur la nébuleuse, bandeau orange
	for ix in range(int(ceil(W))):
		var piece := ST + ("wall-window.glb" if ix % 3 != 0 else "wall-pillar.glb")
		v._bput(piece, Vector3(ix + 0.5, 0, 0.15), 0.0, Vector3(1.0, 2.2, 1.0))
	v._bbox("north_strip", Models.glow_mat(ORANGE, 1.6), Vector3(W * 0.5, 2.15, 0.33), Vector3(W, 0.06, 0.04))
	# vaisseau du Relais garé au centre du quai
	var ship: Node3D = v._put(SP + "craft_cargoA.glb", Vector3(W * 0.5, 0.0, TOP * 0.5 + 0.1), PI * 0.5, Vector3.ONE * 2.3, null, true)
	Models.tint_node(ship, 0.5)
	var eng: MeshInstance3D = v._ground_quad(3.5, CYAN, 0.6)
	eng.position = Vector3(W * 0.5 - 3.4, 0.6, TOP * 0.5 + 0.1)
	level.add_child(eng)
	# consoles et machines le long du mur nord
	var x := 1.6
	while x < W - 1.4:
		if absf(x - W * 0.5) > 4.2:
			var r := rng.randf()
			if r < 0.3:
				v._bput(ST + "computer-wide.glb", Vector3(x, 0, 0.65), 0.0, Vector3.ONE * 1.4)
			elif r < 0.5:
				v._bput(ST + "computer-system.glb", Vector3(x, 0, 0.6), 0.0, Vector3.ONE * 1.4)
			elif r < 0.65:
				v._bput(SP + "machine_generator.glb", Vector3(x, 0, 1.0), rng.randf() * TAU, Vector3.ONE * 1.1, true)
			elif r < 0.8:
				v._bput(ST + "container-tall.glb", Vector3(x, 0, 0.75), rng.randf_range(-0.3, 0.3), Vector3.ONE * 1.5)
				v._bput(ST + "container.glb", Vector3(x + 0.7, 0, 1.4), rng.randf_range(-0.3, 0.3), Vector3.ONE * 1.3)
			else:
				v._bput(SP + "barrels.glb", Vector3(x, 0, 1.1), rng.randf() * TAU, Vector3.ONE * 1.1, true)
		x += rng.randf_range(1.6, 2.4)
	# caisses et tonneaux devant le vaisseau
	for side in [-1, 1]:
		v._bput(ST + "container-wide.glb", Vector3(W * 0.5 + side * 5.0, 0, TOP - 1.2), side * 0.2, Vector3.ONE * 1.4)
		v._bput(SP + "satelliteDish.glb", Vector3(W * 0.5 + side * 7.0, 0, 1.3), side * 0.6, Vector3.ONE * 1.2, true)
