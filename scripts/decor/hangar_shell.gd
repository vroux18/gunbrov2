extends RefCounted
## Nébuleuse 7 — coque du hangar : sol, marquages, murs, garde-corps, habillage lumineux, lumières d'ambiance.
## Appelé par view3d.gd (_build_level) avec la vue `v` : helpers v._mm, v._bput, v._bbox, v._ground_quad,
## v.level (parent du décor), v.arena (W, H, WALL, TOP en px, obstacles, pads), v.K (px -> m).

const Models = preload("res://scripts/models.gd")
const ST := "res://assets/models/station/"
const CYAN := Color("#3CF2D8")
const ORANGE := Color("#FF7A2F")

static func build(v: Node, rng: RandomNumberGenerator) -> void:
	var K: float = v.K
	var W: float = v.arena.W * K
	var H: float = v.arena.H * K
	var WALL: float = v.arena.WALL * K
	var TOP: float = v.arena.TOP * K
	var level: Node3D = v.level
	# sol : dalles 1×1, dessus à y = 0 (les dalles Kenney font 0,3 d'épaisseur)
	var plain := []
	var panel := []
	var detail := []
	for ix in range(int(ceil(W))):
		for iz in range(int(ceil(H))):
			var xf := Transform3D(Basis(), Vector3(ix + 0.5, -0.3, iz + 0.5))
			if iz + 0.5 < TOP:
				continue  # quai nord : hangar_bay.gd
			var r := rng.randf()
			if (ix + iz) % 2 == 0 and r < 0.7:
				panel.append(xf)
			elif r < 0.08:
				detail.append(xf)
			else:
				plain.append(xf)
	v._mm(Models.mesh_of(ST + "floor.glb"), plain)
	v._mm(Models.mesh_of(ST + "floor-panel.glb"), panel)
	v._mm(Models.mesh_of(ST + "floor-detail.glb"), detail)
	# bandes lumineuses au sol (croix centrale et bord du quai)
	var strip_mat := Models.glow_mat(CYAN, 1.6)
	var s1 := Models.box(Vector3(W - 2 * WALL, 0.02, 0.06), strip_mat)
	s1.position = Vector3(W * 0.5, 0.012, (TOP + H) * 0.5)
	level.add_child(s1)
	var s2 := Models.box(Vector3(0.06, 0.02, H - TOP - WALL), strip_mat)
	s2.position = Vector3(W * 0.5, 0.012, (TOP + H - WALL) * 0.5)
	level.add_child(s2)
	# murs : ouest, est (hauts), sud (garde-corps bas pour ne pas masquer le jeu) ; le mur nord est au quai
	var wall_scale := Vector3(1.0, 1.7, 1.0)
	for iz in range(int(TOP) - 1, int(ceil(H))):
		var z := iz + 0.5
		var piece := ST + ("wall-window.glb" if iz % 5 == 2 else ("wall-pillar.glb" if iz % 5 == 0 else "wall.glb"))
		v._bput(piece, Vector3(WALL - 0.15, 0, z), PI * 0.5, wall_scale)
		v._bput(piece, Vector3(W - WALL + 0.15, 0, z), -PI * 0.5, wall_scale)
	for ix in range(int(ceil(W))):
		v._bput(ST + "rail.glb", Vector3(ix + 0.5, 0, H - WALL + 0.1), PI)
	_details(v, W, H, WALL, TOP)

## Lumières d'ambiance colorées (peu nombreuses : chaque lumière coûte sur téléphone). Appelé après le lot.
static func lights(v: Node) -> void:
	var K: float = v.K
	var W: float = v.arena.W * K
	var H: float = v.arena.H * K
	var TOP: float = v.arena.TOP * K
	var ls := [[Vector3(W * 0.5, 2.5, 1.8), ORANGE, 9.0, 1.4], [Vector3(W * 0.2, 2.2, (TOP + H) * 0.5), CYAN, 9.0, 0.6], [Vector3(W * 0.8, 2.2, (TOP + H) * 0.5), Color("#8E6BFF"), 9.0, 0.6]]
	for L in ls:
		var ol := OmniLight3D.new()
		ol.position = L[0]
		ol.light_color = L[1]
		ol.omni_range = L[2]
		ol.light_energy = L[3]
		ol.omni_attenuation = 1.4
		(v.level as Node3D).add_child(ol)

## Habillage : flaques de lumière au sol, bandes de danger le long des murs, barres lumineuses, emblème central.
static func _details(v: Node, W: float, H: float, WALL: float, TOP: float) -> void:
	var level: Node3D = v.level
	# flaques de lumière des plafonniers (un seul MultiMesh additif)
	var pool := PlaneMesh.new()
	pool.size = Vector2(5.5, 5.5)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.albedo_texture = Models.radial()
	pm.albedo_color = Color(0.55, 0.65, 1.0, 0.16)
	pool.material = pm
	var pools := []
	var x := 4.5
	while x < W - 3.0:
		var z := TOP + 3.2
		while z < H - 2.0:
			pools.append(Transform3D(Basis(), Vector3(x, 0.015, z)))
			z += 6.0
		x += 7.0
	v._mm(pool, pools)
	# bandes de danger au pied des murs ouest, est et sud
	var hz := StandardMaterial3D.new()
	hz.albedo_texture = load("res://assets/env/hazard.png")
	hz.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hz.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hz.albedo_color = Color(0.75, 0.75, 0.75, 0.85)
	hz.texture_repeat = true
	var strips := [
		[Vector3(W * 0.5, 0.014, H - WALL - 0.25), Vector2(W - 2 * WALL, 0.42), 0.0, (W - 2 * WALL) / 1.7],
		[Vector3(WALL + 0.25, 0.014, (TOP + H - WALL) * 0.5), Vector2(H - WALL - TOP, 0.42), PI * 0.5, (H - WALL - TOP) / 1.7],
		[Vector3(W - WALL - 0.25, 0.014, (TOP + H - WALL) * 0.5), Vector2(H - WALL - TOP, 0.42), PI * 0.5, (H - WALL - TOP) / 1.7],
	]
	for st in strips:
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = st[1]
		mi.mesh = plane
		var m: StandardMaterial3D = hz.duplicate()
		m.uv1_scale = Vector3(st[3], 1, 1)
		mi.material_override = m
		mi.position = st[0]
		mi.rotation.y = st[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level.add_child(mi)
	# barres lumineuses verticales sur les piliers des murs latéraux
	var bar := Models.glow_mat(CYAN, 1.8)
	for iz in range(int(TOP) - 1, int(ceil(H))):
		if iz % 5 == 0:
			v._bbox("wall_bar", bar, Vector3(WALL + 0.02, 1.0, iz + 0.5), Vector3(0.04, 1.2, 0.12))
			v._bbox("wall_bar", bar, Vector3(W - WALL - 0.02, 1.0, iz + 0.5), Vector3(0.04, 1.2, 0.12))
	# emblème du Relais peint au centre de l'arène
	var c := Vector3(W * 0.5, 0.016, (TOP + H - WALL) * 0.5)
	for r in [[2.6, 2.68, 0.28], [1.7, 1.74, 0.18]]:
		var ring := Models.torus(r[0], r[1], Models.glow_mat(CYAN, r[2]), 64)
		ring.scale = Vector3(1, 0.05, 1)
		ring.position = c
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level.add_child(ring)
	for k in range(4):
		var a := TAU * k / 4.0 + PI * 0.25
		v._bbox("emblem_tick", Models.glow_mat(ORANGE, 0.6), c + Vector3(cos(a), 0, sin(a)) * 3.0, Vector3(0.36, 0.01, 0.1), -a)
