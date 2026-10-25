extends RefCounted
## Le Relais, base des Passeurs : premier écran du jeu et hub entre les parties. Décor sculpté
## (tools/decor/relais_*.py -> assets/decor/relais/*.glb), fusionné au montage en un seul maillage par
## matériau ; à part, ce qui bouge : portail, éclats du Cœur, robots, hologrammes, particules.
## Appelé par view3d.gd (show_relais, set_shards, _tick_relais) ; la caméra et le départ restent dans la vue.
## Repère du Relais : Jo au centre du pont (0, 0, 0,6), portail derrière elle (0, 2,6, -2,2), la caméra
## regarde vers -Z depuis l'avant droit ; la moitié droite de l'écran (x > 3,5) est sous le menu : calme.

const Models = preload("res://scripts/models.gd")
const Rig3D = preload("res://scripts/rig3d.gd")
const D := "res://assets/decor/relais/"
const CYAN := Color("#3CF2D8")
const ORANGE := Color("#FF7A2F")
const GOLD := Color("#FFB347")
const VIOLET := Color("#8E6BFF")

const POSTS := [192.0, 222.0, 252.0, 288.0, 318.0, 348.0]  # bornes du pont (degrés, de +X vers +Z)
const R_POST := 4.02
const FLOOR_Y := -0.5  # sol de la station autour du pont
const WALL_C := Vector3(1.0, 0.0, -0.5)  # centre de l'arc de la baie
const WALL_R := 9.6
const PORTAL := Vector3(0, 2.6, -2.2)
const SOCKETS := 10  # socles d'éclats en couronne sur le portail (tools/decor/relais_shell.py)
const R_GEM := 2.6
# atelier (établi, mécano) et coin de la Loge (râtelier)
const PROJ := Vector3(-4.9, FLOOR_Y, -6.0)  # projecteur de la planète holographique (en haut à gauche)
const PLANET_H := 3.9
const BENCH := Vector3(2.3, 0.0, -0.75)
const BENCH_ROT := -0.55
const BENCH_S := 0.85
const RACK := Vector3(-3.55, FLOOR_Y, -3.85)
const RACK_ROT := 0.62
# patrouille du drone d'entretien : [position, pause en s]
const PATROL := [
	[Vector3(2.7, 2.15, -1.3), 1.8],
	[Vector3(1.2, 3.6, -0.6), 0.0],
	[Vector3(-1.5, 3.2, -0.5), 0.0],
	[Vector3(-2.7, 2.5, -2.4), 2.0],
	[Vector3(-3.9, 3.4, -4.6), 1.2],
	[Vector3(-1.2, 1.8, -4.8), 0.0],
	[Vector3(1.8, 1.6, -4.2), 0.0],
]

static var _parts := {}  # chemin -> [[Mesh, Transform3D, nom], ...]

# ---------------------------------------------------------------- montage
static func build(v: Node) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0, 0, -80)
	v.add_child(root)
	var st := {"t": 0.0}
	root.set_meta("st", st)
	var mg := {}
	_deck(mg)
	_shell(mg)
	_furniture(mg)
	_merge_end(mg, root, st)
	_floor(root)
	_sky(root)
	_portal(root)
	_holos(root, st)
	_bots(root, st)
	_particles(root)
	_lights(root, st)
	_scanner(root, st)
	# Jo (modèle et animation : scripts/rig3d.gd), sur sa scène : fond BD, lumières à elle (_hero_stage)
	var stage := Node3D.new()
	stage.position = HERO_STAGE
	root.add_child(stage)
	var rh := Rig3D.new()
	stage.add_child(rh)
	rh.setup(v.JO_MODEL, Color(1, 1, 1), 1.7)
	rh.make_hero(Color(0, 0, 0), 0.0, Color(1.0, 0.22, 0.28))  # matériau BD de Jo
	rh.scale = Vector3.ONE * HERO_SCALE  # Jo de 1,26 (tools/blender/jo.py)
	rh.position = Vector3(0, 0, 0.6)  # repris par view3d.gd (show_relais), dans le repère de la scène
	rh.rotation.y = 0.35
	rh.process_priority = -10  # Jo se pose avant la vue (view3d.gd -> tick) : la pose d'attente s'ajoute après
	root.set_meta("hero", rh)
	var sh := Models.shadow_blob(1.9)
	sh.position = Vector3(0, 0.01, 0.6)
	stage.add_child(sh)
	_hero_stage(stage, st)
	return root

# ---------------------------------------------------------------- Jo mise en valeur
## Jo au Relais : plus grande qu'avant (2,1), un peu avancée vers la caméra, devant un éclat de couverture BD
## (shaders/jo_backdrop.gdshader) qui la détache du portail blanc ; lumière de face chaude et contre-jour
## magenta qui ne touchent qu'elle (calque Rig3D.HERO_LAYER) ; pose d'attente vivante par-dessus son repos
## (_tick_pose). Le décor ne bouge pas.
const HERO_SCALE := 2.45
const HERO_STAGE := Vector3(-0.15, 0.0, 0.45)  # décalage de la scène de Jo (Jo à (0, 0, 0,6) dedans)
const BACKDROP_POS := Vector3(-0.45, 1.85, -0.35)  # centre de l'éclat, derrière Jo (repère de la scène)
const BACKDROP_SIZE := 3.2
const KEY_POS := Vector3(2.2, 3.0, 3.6)  # lumière de face (côté caméra, en haut à droite)
const KEY_E := 3.0
const RIM_POS := Vector3(-1.6, 2.4, -0.9)  # contre-jour (derrière, à gauche)
const RIM_E := 4.0
const POSE_SWAY := 1.0  # amplitude de la pose d'attente (0 : la pose de repos seule)

static func _hero_stage(stage: Node3D, st: Dictionary) -> void:
	var bd := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	bd.mesh = q
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/jo_backdrop.gdshader")
	bd.material_override = bm
	bd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bd.position = BACKDROP_POS
	bd.scale = Vector3.ONE * BACKDROP_SIZE
	stage.add_child(bd)
	st["backdrop"] = bd
	st["backdrop_mat"] = bm
	var key := OmniLight3D.new()
	key.position = KEY_POS
	key.light_color = Color(1.0, 0.92, 0.82)
	key.light_energy = KEY_E
	key.omni_range = 9.0
	key.omni_attenuation = 0.6
	key.light_cull_mask = Rig3D.HERO_LAYER
	stage.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = RIM_POS
	rim.light_color = Color("#FF3CAC")
	rim.light_energy = RIM_E
	rim.omni_range = 5.0
	rim.light_cull_mask = Rig3D.HERO_LAYER
	stage.add_child(rim)
	st["hero_lights"] = [key, rim]

## Pose d'attente : appui sur une jambe (bassin qui bascule, buste qui compense, jambe libre écartée, genou
## plié), poids qui change de pied toutes les quelques secondes, épaules et tête qui suivent, souffle. Ajoutée
## aux parts après l'animation de Jo, qui ne pose qu'à 12 i/s (« en deux ») : quand une part n'a plus la
## transformation écrite ici, Jo l'a reposée et on repart de sa pose. La pose d'attente avance elle aussi par
## crans de 1/12 s. `k` : 0 pendant le départ (Jo court vers le portail).
static func _tick_pose(st: Dictionary, rh: Node3D, t: float, k: float) -> void:
	var tq := floorf(t * 12.0) / 12.0
	# poids : -1 sur la jambe gauche, +1 sur la droite ; change en douceur toutes les ~7 s
	var w := clampf(sin(tq * 0.45) * 2.6, -1.0, 1.0) * k * POSE_SWAY
	var br := sin(tq * 2.1) * k * POSE_SWAY  # souffle
	var model: Node3D = rh.get("model")
	var offs := {
		"torso": [Vector3(-0.06 - 0.02 * br, 0.08 * w, -0.11 * w), Vector3(-0.045 * w, 0.006 * br, 0.0)],
		"leg_r": [Vector3(-0.16 * maxf(-w, 0.0), 0.0, 0.11 * w - 0.07 - 0.12 * maxf(-w, 0.0)), Vector3.ZERO],
		"leg_l": [Vector3(-0.16 * maxf(w, 0.0), 0.0, 0.11 * w + 0.07 + 0.12 * maxf(w, 0.0)), Vector3.ZERO],
		"shin_r": [Vector3(0.38 * maxf(-w, 0.0), 0.0, 0.0), Vector3.ZERO],
		"shin_l": [Vector3(0.38 * maxf(w, 0.0), 0.0, 0.0), Vector3.ZERO],
		"head": [Vector3(0.04 * br - 0.05, -0.12 * w, 0.15 * w), Vector3.ZERO],
		"arm_r": [Vector3(-0.12, 0.0, -0.2 - 0.06 * w), Vector3.ZERO],
		"arm_l": [Vector3(0.1, 0.0, 0.16 - 0.06 * w), Vector3.ZERO],
	}
	var mem: Dictionary = st.get("pose_mem", {})
	if st.get("pose_model") != model:
		mem = {}
		st["pose_model"] = model
	st["pose_mem"] = mem
	for nm in offs:
		var n: Node3D = rh.call("p", nm)
		if n == null:
			continue
		var m: Array = mem.get(nm, [])
		# Jo a reposé la part depuis notre dernière écriture : sa pose devient la base
		if m.is_empty() or not n.transform.is_equal_approx(m[1]):
			m = [n.transform, n.transform]
		var base: Transform3D = m[0]
		var o: Array = offs[nm]
		var xf := Transform3D(base.basis * Basis.from_euler(o[0]), base.origin + base.basis * (o[1] as Vector3))
		n.transform = xf
		mem[nm] = [base, xf]


static func _xf(pos: Vector3, rot_y: float = 0.0, s: float = 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rot_y).scaled(Vector3.ONE * s), pos)

## Pont : plateforme ronde sculptée, bornes et rambardes à l'arrière.
static func _deck(mg: Dictionary) -> void:
	_add(mg, D + "deck.glb", Transform3D.IDENTITY)
	for a in POSTS:
		var r := deg_to_rad(a)
		_add(mg, D + "borne.glb", _xf(Vector3(cos(r), 0, sin(r)) * R_POST), "pulse")
	for i in range(POSTS.size() - 1):
		if POSTS[i + 1] - POSTS[i] > 32.0:
			continue
		var am := deg_to_rad((POSTS[i] + POSTS[i + 1]) * 0.5)
		var c := Vector3(cos(am), 0, sin(am)) * R_POST * cos(deg_to_rad(15.0))
		# lisses le long de X local, tangentes au cercle
		_add(mg, D + "rail.glb", _xf(c, -am - PI * 0.5))

## Grande baie en arc derrière le pont : travées sculptées, face vers le centre.
static func _shell(mg: Dictionary) -> void:
	var step := 2.0 * asin(1.5 / WALL_R)  # une travée de 3 de large
	var a := deg_to_rad(214.0)
	while a < deg_to_rad(345.0):
		var p := WALL_C + Vector3(cos(a), 0, sin(a)) * WALL_R
		p.y = FLOOR_Y
		_add(mg, D + "bay.glb", _xf(p, atan2(-cos(a), -sin(a))))
		a += step

## Mobilier statique : râtelier de la Loge, établi, plantes, socles de projecteurs.
static func _furniture(mg: Dictionary) -> void:
	_add(mg, D + "rack.glb", _xf(RACK, RACK_ROT))
	_add(mg, D + "bench.glb", _xf(BENCH, BENCH_ROT, BENCH_S), "pulse")
	_add(mg, D + "plant.glb", _xf(Vector3(-2.1, 0.0, -0.7), 2.0, 0.85))
	_add(mg, D + "plant_tall.glb", _xf(Vector3(4.3, FLOOR_Y, -6.6), 0.0, 1.15))
	_add(mg, D + "plant_tall.glb", _xf(Vector3(6.2, FLOOR_Y, -5.4), 1.0, 1.1))
	_add(mg, D + "projector.glb", _xf(PROJ))

## Sol de la station autour du pont : grand plan peint (relais_textures.py), répété.
static func _floor(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(44, 28)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(D + "floor.png")
	m.uv1_scale = Vector3(11, 7, 1)
	m.albedo_color = Color(0.62, 0.62, 0.7)
	m.roughness = 0.55
	m.metallic_specular = 0.4
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = m
	mi.position = Vector3(1, FLOOR_Y, -2)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

## Nébuleuse vue par la baie (toile peinte, lointaine) et le vaisseau des Passeurs amarré dehors.
static func _sky(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(110, 55)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = load(D + "nebula.png")
	m.albedo_color = Color(0.85, 0.85, 0.9)
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.position = Vector3(0, 6, -42)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var ship := _inst(root, D + "ship.glb", _xf(Vector3(11.5, 1.6, -21.0), PI + 0.35, 1.0), Color(0.36, 0.4, 0.55), 1.0)
	root.set_meta("ship", ship)

## Portail : cadre fixe à dix socles en couronne, anneau intérieur tournant, disque tourbillonnant.
static func _portal(root: Node3D) -> void:
	var portal := Node3D.new()
	portal.position = PORTAL
	root.add_child(portal)
	_inst(portal, D + "portal.glb", Transform3D.IDENTITY)
	var spin := _inst(portal, D + "portal_ring.glb", Transform3D.IDENTITY)
	var disk := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(4.0, 4.0)
	disk.mesh = q
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/portal.gdshader")
	disk.material_override = pm
	disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# flaque de lumière au pied du portail
	var pool := MeshInstance3D.new()
	var pp := PlaneMesh.new()
	pp.size = Vector2(5.5, 4.0)
	pool.mesh = pp
	pool.material_override = Models.add_mat(Color(CYAN, 0.3), 1.0, Models.radial()).duplicate()
	pool.position = Vector3(0, 0.012, -1.3)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pool)
	root.set_meta("portal_pool", pool)
	# fond sombre derrière le tourbillon : le portail ouvre sur ailleurs, il ne laisse pas voir la baie
	var back := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 2.02
	bc.bottom_radius = 2.02
	bc.height = 0.02
	bc.radial_segments = 40
	bc.rings = 1
	back.mesh = bc
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color("#0B0F2C")
	back.material_override = bm
	back.rotation.x = PI * 0.5
	back.position.z = -0.08
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	portal.add_child(back)
	portal.add_child(disk)
	root.set_meta("portal", spin)
	root.set_meta("portal_disk", pm)
	# éclats du Cœur : cristaux posés dans les coupelles, pointe vers l'extérieur
	var gem_mesh: Mesh = (_parts_of(D + "gem.glb")[0] as Array)[0]
	var gems := []
	for i in range(SOCKETS):
		var a := deg_to_rad(lerpf(162.0, 18.0, i / float(SOCKETS - 1)))
		var gem := MeshInstance3D.new()
		gem.mesh = gem_mesh
		gem.position = Vector3(cos(a), sin(a), 0.0) * R_GEM + Vector3(0, 0, 0.02)
		gem.rotation.z = a - PI * 0.5
		gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		portal.add_child(gem)
		gems.append(gem)
	root.set_meta("shards", gems)
	var halo := []
	for i in range(SOCKETS):
		var h := MeshInstance3D.new()
		var hq := QuadMesh.new()
		hq.size = Vector2(1.5, 1.5)
		h.mesh = hq
		h.position = (gems[i] as Node3D).position * 1.13 + Vector3(0, 0, 0.15)
		h.material_override = Models.add_mat(Color(CYAN, 0.0), 1.0, Models.radial()).duplicate()
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		portal.add_child(h)
		halo.append(h)
	root.set_meta("shard_halo", halo)

## Hologrammes : écrans flottants (atelier, Loge) et planète tournante au-dessus du projecteur.
static func _holos(root: Node3D, st: Dictionary) -> void:
	var holos := []
	var shader: Shader = load("res://shaders/relais_holo.gdshader")
	var specs := [
		# [position, rotation y, taille, sorte, couleur]
		[BENCH + Vector3(1.05, 2.35, -0.5), BENCH_ROT - 0.2, Vector2(0.95, 0.6), 1, CYAN],
		[Vector3(2.6, 2.4, -6.4), -0.25, Vector2(1.2, 0.75), 0, CYAN],
		[RACK + Vector3(0.0, 3.85, 0.15).rotated(Vector3.UP, RACK_ROT), RACK_ROT, Vector2(1.4, 0.85), 2, CYAN],
	]
	for i in range(specs.size()):
		var sp: Array = specs[i]
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = sp[2]
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("kind", sp[3])
		m.set_shader_parameter("col", sp[4])
		m.set_shader_parameter("energy", 1.2)
		m.set_shader_parameter("seed", float(i) * 0.37)
		mi.material_override = m
		mi.position = sp[0]
		mi.rotation.y = sp[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		holos.append(mi)
	st["holos"] = holos
	# planète holographique : sphère filaire turquoise, anneau orange, petite lune
	var planet := Node3D.new()
	planet.position = PROJ + Vector3(0, PLANET_H, 0)
	root.add_child(planet)
	var sm := SphereMesh.new()
	sm.radius = 0.42
	sm.height = 0.84
	sm.radial_segments = 16
	sm.rings = 8
	var core := MeshInstance3D.new()
	core.mesh = sm
	core.material_override = _holo_mat(CYAN, 0.35)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(core)
	var ring := Models.torus(0.62, 0.68, _holo_mat(ORANGE, 0.9), 40)
	ring.rotation = Vector3(0.45, 0, 0.2)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(ring)
	var moon := Models.sphere(0.07, _holo_mat(CYAN, 1.2))
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(moon)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.16
	cm.height = PLANET_H - 0.6
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	beam.material_override = _beam_mat()
	beam.position = PROJ + Vector3(0, 0.27 + (PLANET_H - 0.6) * 0.5, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	st["planet"] = planet
	st["moon"] = moon

static func _holo_mat(col: Color, a: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_color = Color(col.r * 1.4, col.g * 1.4, col.b * 1.4, a)
	m.rim_enabled = false
	return m

static func _beam_mat() -> StandardMaterial3D:
	var m := _holo_mat(CYAN, 0.16)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 1))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	m.albedo_texture = gt
	return m

## Robots de la base : le mécano à l'établi, le drone d'entretien en patrouille.
static func _bots(root: Node3D, st: Dictionary) -> void:
	# robots : personnages, en style BD comme Jo et les ennemis (Rig3D.char_mat) ; le décor garde son rendu
	var mec := _inst(root, D + "mecano.glb", _xf(BENCH + Vector3(0.1, 0, -0.78).rotated(Vector3.UP, BENCH_ROT), BENCH_ROT - 0.25, 1.1), Color(1, 1, 1), 1.8, true)
	st["mecano"] = mec
	st["mecano_parts"] = _named(mec)
	var msh := Models.shadow_blob(0.9)
	msh.position = mec.position + Vector3(0, 0.01, 0)
	root.add_child(msh)
	var dr := _inst(root, D + "drone_relais.glb", _xf(PATROL[0][0], 0.0, 1.25), Color(1, 1, 1), 1.8, true)
	st["drone"] = dr
	st["drone_parts"] = _named(dr)
	var dsh := Models.shadow_blob(0.6)
	root.add_child(dsh)
	st["drone_shadow"] = dsh
	# étincelles du chalumeau (posées à chaque image sur la pointe)
	var sp := CPUParticles3D.new()
	sp.amount = 22
	sp.lifetime = 0.45
	sp.explosiveness = 0.0
	sp.local_coords = false
	sp.direction = Vector3(0, 1, 0)
	sp.spread = 70.0
	sp.initial_velocity_min = 1.2
	sp.initial_velocity_max = 2.6
	sp.gravity = Vector3(0, -7.0, 0)
	sp.scale_amount_min = 0.6
	sp.scale_amount_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	g.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
	sp.color_ramp = g
	sp.mesh = _spark_mesh()
	sp.emitting = false
	root.add_child(sp)
	st["sparks"] = sp
	var flare := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.45, 0.45)
	flare.mesh = fq
	flare.material_override = Models.add_mat(Color(0.7, 0.95, 1.0, 0.0), 1.0, Models.radial(), true).duplicate()
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flare)
	st["flare"] = flare

## Petit quad lumineux face caméra pour les particules (taille portée par le quad : l'échelle des
## particules n'est pas fiable en rendu Compatibility).
static func _spark_mesh(energy: float = 1.4, size: float = 0.08) -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Models.radial()
	m.albedo_color = Color(energy, energy, energy)
	q.material = m
	return q

## Scanner de la Loge (gros plan) et éclair du départ.
static func _scanner(root: Node3D, st: Dictionary) -> void:
	var sc := Node3D.new()
	sc.position = Vector3(0, 0, 0.6)
	sc.visible = false
	root.add_child(sc)
	st["scanner"] = sc
	var fm := _holo_mat(CYAN, 0.0)
	fm.albedo_texture = _scan_tex()
	var disc := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.6, 2.6)
	disc.mesh = pm
	disc.material_override = fm
	disc.position.y = 0.03
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sc.add_child(disc)
	st["scan_floor"] = disc
	st["scan_floor_mat"] = fm
	var rm := _holo_mat(CYAN, 0.0)
	var ring := Models.torus(0.95, 1.0, rm, 40)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sc.add_child(ring)
	st["scan_ring"] = ring
	st["scan_ring_mat"] = rm
	var fl := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3.0, 3.0)
	fl.mesh = q
	var flm := Models.add_mat(Color(0.75, 1.0, 1.0, 0.0), 1.6, Models.radial()).duplicate()
	fl.material_override = flm
	fl.position = PORTAL + Vector3(0, 0, 0.1)
	fl.visible = false
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fl)
	st["launch_flash"] = fl

## Motif du scanner au sol : deux cercles et des graduations (dessiné une fois).
static func _scan_tex() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5)
			var r := d.length() / (n * 0.5)
			var a := 0.0
			a = maxf(a, 1.0 - absf(r - 0.94) / 0.025)
			a = maxf(a, (1.0 - absf(r - 0.7) / 0.02) * 0.7)
			var ang := atan2(d.y, d.x)
			if r > 0.76 and r < 0.88 and fmod(ang + TAU, TAU / 24.0) < 0.06:
				a = maxf(a, 0.8)
			if r < 0.68:
				a = maxf(a, 0.12 * r)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

## Poussières lumineuses qui flottent dans la base (douces, lentes).
static func _particles(root: Node3D) -> void:
	var p := CPUParticles3D.new()
	p.amount = 46
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(7.5, 2.6, 4.5)
	p.position = Vector3(0.5, 2.6, -2.0)
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 0.03
	p.initial_velocity_max = 0.14
	p.gravity = Vector3(0, 0.03, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 1.0, 0.95, 0.0))
	g.add_point(0.3, Color(0.6, 1.0, 0.95, 0.55))
	g.add_point(0.7, Color(0.75, 0.7, 1.0, 0.45))
	g.set_color(g.get_point_count() - 1, Color(0.75, 0.7, 1.0, 0.0))
	p.color_ramp = g
	p.mesh = _spark_mesh(0.9, 0.09)
	root.add_child(p)

## Deux lumières dynamiques (plus le soleil de la vue) : portail cyan, lampe chaude de l'atelier.
static func _lights(root: Node3D, st: Dictionary) -> void:
	var plight := OmniLight3D.new()
	plight.position = Vector3(0, 2.4, -1.2)
	plight.light_color = CYAN
	plight.omni_range = 7.5
	plight.light_energy = 1.7
	root.add_child(plight)
	st["portal_light"] = plight
	var warm := OmniLight3D.new()
	warm.position = BENCH + Vector3(-1.0, 3.4, 2.4)
	warm.light_color = Color("#FFB070")
	warm.omni_range = 7.5
	warm.light_energy = 0.7
	root.add_child(warm)
	st["warm_light"] = warm

# ---------------------------------------------------------------- éclats
static func set_shards(root: Node3D, n: int) -> void:
	var gems: Array = root.get_meta("shards")
	var halo: Array = root.get_meta("shard_halo")
	for i in range(gems.size()):
		var g: MeshInstance3D = gems[i]
		var on := i < n
		# allumé : turquoise vif ; en sommeil : cristal violet à peine lumineux
		g.material_override = Rig3D.tint_glow_mat(CYAN, 2.2) if on else Rig3D.tint_glow_mat(Color("#7A5CFF"), 0.75)
		(halo[i] as MeshInstance3D).visible = on
	root.set_meta("shards_on", n)

# ---------------------------------------------------------------- vie
## Animation du décor (hors caméra) ; `launching` : départ en cours (le portail s'emballe) ;
## `focus` : 0 vue large, 1 gros plan de la Loge (le scanner d'équipement s'allume autour de Jo).
static func tick(root: Node3D, dt: float, launching: bool, focus: float = 0.0) -> void:
	var st: Dictionary = root.get_meta("st")
	st["t"] = float(st["t"]) + dt
	var t: float = st["t"]
	var spin: Node3D = root.get_meta("portal")
	spin.rotation.z += dt * (0.25 if not launching else 3.5)
	var pm: ShaderMaterial = root.get_meta("portal_disk")
	pm.set_shader_parameter("energy", 1.4 + (1.2 if launching else 0.12 * sin(t * 1.7)))
	# éclats : lente pulsation, l'un après l'autre
	var halo: Array = root.get_meta("shard_halo")
	for i in range(halo.size()):
		var h: MeshInstance3D = halo[i]
		if h.visible:
			var k := 0.5 + 0.5 * sin(t * 2.0 - i * 0.6)
			(h.material_override as StandardMaterial3D).albedo_color.a = 0.35 + 0.3 * k
	# lumières qui respirent
	if st.has("pulse"):
		var e := 1.5 + 0.55 * sin(t * 1.8)
		(st["pulse"] as StandardMaterial3D).albedo_color = Color(e, e, e)
	var pool: MeshInstance3D = root.get_meta("portal_pool")
	(pool.material_override as StandardMaterial3D).albedo_color.a = 0.24 + 0.08 * sin(t * 1.7) + (0.3 if launching else 0.0)
	var ship: Node3D = root.get_meta("ship")
	ship.position.y = 1.6 + sin(t * 0.45) * 0.18
	ship.rotation.z = sin(t * 0.3) * 0.03
	(st["portal_light"] as OmniLight3D).light_energy = (1.6 + 0.25 * sin(t * 1.7)) * (1.8 if launching else 1.0)
	# hologrammes
	var planet: Node3D = st["planet"]
	planet.rotation.y = t * 0.6
	planet.position.y = PROJ.y + PLANET_H + sin(t * 1.1) * 0.05
	var moon: Node3D = st["moon"]
	moon.position = Vector3(cos(t * 1.4) * 0.78, sin(t * 1.4) * 0.22, sin(t * 1.4) * 0.78)
	for h in st["holos"]:
		var hn: Node3D = h
		hn.position.y += sin(t * 1.3 + hn.position.x) * 0.0015
	_tick_mecano(st, t, dt)
	_tick_drone(st, t, dt)
	_tick_scanner(st, t, focus)
	_tick_launch(root, st, dt, launching)
	# Jo : pose d'attente, fond BD (s'efface au départ et dans la Loge, où le scanner prend la place)
	var rh: Node3D = root.get_meta("hero")
	var pk := float(st.get("pose_k", 1.0))
	pk = move_toward(pk, 0.0 if launching else 1.0, dt * 3.0)
	st["pose_k"] = pk
	_tick_pose(st, rh, t, pk)
	var bk := pk * (1.0 - clampf(focus * 1.5, 0.0, 1.0))
	var bd: MeshInstance3D = st["backdrop"]
	bd.visible = bk > 0.01
	var bm: ShaderMaterial = st["backdrop_mat"]
	bm.set_shader_parameter("opacity", 0.55 * bk)
	bm.set_shader_parameter("spin", floorf(t * 12.0) / 12.0 * 0.08)
	bd.scale = Vector3.ONE * BACKDROP_SIZE * (1.0 + 0.015 * sin(floorf(t * 12.0) / 12.0 * 2.1))

## Loge : anneau au sol et anneau de balayage qui monte et descend le long de Jo.
static func _tick_scanner(st: Dictionary, t: float, focus: float) -> void:
	var sc: Node3D = st["scanner"]
	sc.visible = focus > 0.02
	if not sc.visible:
		return
	var k := clampf(focus, 0.0, 1.0)
	(st["scan_floor_mat"] as StandardMaterial3D).albedo_color.a = 0.75 * k
	(st["scan_ring_mat"] as StandardMaterial3D).albedo_color.a = 0.55 * k
	var ring: Node3D = st["scan_ring"]
	ring.position.y = 0.15 + (0.5 - 0.5 * cos(t * 1.6)) * 2.4
	(st["scan_floor"] as Node3D).rotation.y = t * 0.5

## Départ : quand Jo passe le portail, éclair blanc-turquoise qui gonfle et s'efface.
static func _tick_launch(root: Node3D, st: Dictionary, dt: float, launching: bool) -> void:
	var fl: MeshInstance3D = st["launch_flash"]
	var rh: Node3D = root.get_meta("hero")
	if launching and not rh.visible and float(st.get("flash_t", -1.0)) < 0.0:
		st["flash_t"] = 0.0
	if not launching:
		st["flash_t"] = -1.0
	var ft: float = st.get("flash_t", -1.0)
	fl.visible = ft >= 0.0 and ft < 0.8
	if ft >= 0.0:
		ft += dt
		st["flash_t"] = ft
		var k := clampf(ft / 0.8, 0.0, 1.0)
		fl.scale = Vector3.ONE * (1.0 + k * 2.5)
		(fl.material_override as StandardMaterial3D).albedo_color.a = (1.0 - k) * 0.9

## Mécano : soude au chalumeau, serre à la clé, puis lève la tête vers Jo et sautille (boucle de 9 s).
static func _tick_mecano(st: Dictionary, t: float, dt: float) -> void:
	var P: Dictionary = st["mecano_parts"]
	var c := fmod(t, 9.0)
	var weld := c < 3.6
	var wrench := c >= 3.6 and c < 6.4
	var look := c >= 6.4
	var body: Node3D = P["body"]
	var head: Node3D = P["head"]
	var arm_r: Node3D = P["arm_r"]
	var arm_l: Node3D = P["arm_l"]
	var lean := 0.0
	if weld or wrench:
		lean = 0.1
	body.rotation = Vector3(lerpf(body.rotation.x, lean, dt * 4.0), 0, sin(t * 2.0) * 0.03)
	body.position.y = 0.4 + absf(sin(t * (2.0 if not look else 7.0))) * (0.01 if not look else 0.05)
	var hx := 0.1 if (weld or wrench) else -0.2
	var hy := 0.0 if not look else 0.7 + sin(t * 3.0) * 0.12
	head.rotation = Vector3(lerpf(head.rotation.x, hx, dt * 5.0), lerpf(head.rotation.y, hy, dt * 4.0), sin(t * 1.3) * 0.06)
	# bras gauche (chalumeau) : petits gestes rapides en soudant
	var jl := Vector3(-0.9 + sin(t * 23.0) * 0.03, sin(t * 3.1) * 0.12, 0) if weld else Vector3(-0.35, 0, 0.1)
	arm_l.rotation = arm_l.rotation.lerp(jl, clampf(dt * 8.0, 0.0, 1.0))
	# bras droit (clé) : cliquet
	var jr := Vector3(-0.95 + 0.3 * maxf(0.0, sin(t * 6.0)), 0, -0.1) if wrench else (Vector3(-2.3, 0, -0.45 + sin(t * 9.0) * 0.3) if look and c > 7.0 else Vector3(-0.35, 0, -0.05))
	arm_r.rotation = arm_r.rotation.lerp(jr, clampf(dt * 8.0, 0.0, 1.0))
	# yeux : clignent
	var eyes: Node3D = P["eyes_glow"]
	eyes.scale.y = 0.15 if fmod(t, 3.7) < 0.12 else 1.0
	# étincelles et éclat du chalumeau
	var torch: Node3D = P["torch_glow"]
	var tip := torch.global_position
	var sp: CPUParticles3D = st["sparks"]
	sp.global_position = tip
	sp.emitting = weld and fmod(t, 1.2) < 0.9
	var flare: MeshInstance3D = st["flare"]
	flare.global_position = tip + Vector3(0, 0.03, 0.05)
	var fa := (0.4 + 0.25 * sin(t * 41.0) * sin(t * 13.0)) if sp.emitting else 0.0
	(flare.material_override as StandardMaterial3D).albedo_color.a = fa
	torch.scale = Vector3.ONE * (1.0 + fa)
	(st["warm_light"] as OmniLight3D).light_energy = 0.7 + fa * 0.4

## Drone d'entretien : suit sa ronde (courbe lissée), s'arrête pour scanner, se penche dans le mouvement.
static func _tick_drone(st: Dictionary, t: float, dt: float) -> void:
	var dr: Node3D = st["drone"]
	var P: Dictionary = st["drone_parts"]
	if not st.has("leg"):
		st["leg"] = 0
		st["leg_t"] = 0.0
		st["pause"] = float(PATROL[0][1])
	var n := PATROL.size()
	var i: int = st["leg"]
	var pause: float = st["pause"]
	var pos: Vector3
	var vel := Vector3.ZERO
	if pause > 0.0:
		st["pause"] = pause - dt
		pos = PATROL[i][0]
	else:
		var p0: Vector3 = PATROL[(i - 1 + n) % n][0]
		var p1: Vector3 = PATROL[i][0]
		var p2: Vector3 = PATROL[(i + 1) % n][0]
		var p3: Vector3 = PATROL[(i + 2) % n][0]
		var seg := p1.distance_to(p2)
		var u: float = float(st["leg_t"]) + dt * 1.1 / maxf(seg, 0.1)
		if u >= 1.0:
			u = 0.0
			i = (i + 1) % n
			st["leg"] = i
			st["pause"] = float(PATROL[i][1])
			pos = PATROL[i][0]
		else:
			pos = p1.cubic_interpolate(p2, p0, p3, u)
			vel = (p1.cubic_interpolate(p2, p0, p3, minf(u + 0.02, 1.0)) - pos) / 0.02 / maxf(seg, 0.1) * 1.1
		st["leg_t"] = u
	pos.y += sin(t * 2.3) * 0.06
	dr.position = pos
	var hv := Vector3(vel.x, 0, vel.z)
	var face := dr.rotation.y
	if hv.length() > 0.05:
		face = atan2(hv.x, hv.z)
	else:
		face = lerp_angle(face, atan2(3.2 - pos.x, 9.5 - pos.z) + sin(t * 0.9) * 0.4, dt * 2.0)
	dr.rotation.y = lerp_angle(dr.rotation.y, face, clampf(dt * 4.0, 0.0, 1.0))
	dr.rotation.x = lerpf(dr.rotation.x, clampf(hv.length() * 0.35, 0.0, 0.35), dt * 4.0)
	(P["rotor"] as Node3D).rotation.y = t * 26.0
	var brush: Node3D = P["brush"]
	brush.rotation.x = sin(t * 2.0) * 0.3 if pause > 0.0 else 0.0
	(P["eye_glow"] as Node3D).scale = Vector3.ONE * (1.0 + (0.12 * sin(t * 8.0) if pause > 0.0 else 0.0))
	var dsh: Node3D = st["drone_shadow"]
	var ground := 0.0 if Vector2(pos.x, pos.z).length() < 4.3 else FLOOR_Y
	dsh.position = Vector3(pos.x, ground + 0.02, pos.z)
	dsh.scale = Vector3.ONE * clampf(1.4 - (pos.y - ground) * 0.2, 0.5, 1.2)

# ---------------------------------------------------------------- objets sculptés
## Instance d'un GLB sculpté, matériaux posés (couleurs par sommet ; « _glow » lumineux). `character` : un
## personnage (robots), rendu comme les ennemis (style BD si le réglage Dev « comic » est actif).
static func _inst(parent: Node3D, path: String, xf: Transform3D, tint: Color = Color(1, 1, 1), glow: float = 1.8, character := false) -> Node3D:
	var n: Node3D = Models.scene(path).instantiate()
	n.transform = xf
	parent.add_child(n)
	for mi in Models.meshes(n):
		var m: MeshInstance3D = mi
		var nm := String(m.name) + String(m.get_parent().name)
		m.material_override = Rig3D.glow_mat(glow) if "_glow" in nm else (Rig3D.char_mat(tint) if character else Rig3D.body_mat(tint))
		if "_glow" in nm:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

static func _named(n: Node) -> Dictionary:
	var out := {}
	for c in n.find_children("*", "Node3D", true, false):
		out[String(c.name)] = c
	return out

# ---------------------------------------------------------------- fusion du décor statique
## Maillages d'un GLB sculpté avec leur transformation et le nom de leur part (« _glow » : lumineux).
static func _parts_of(path: String) -> Array:
	if _parts.has(path):
		return _parts[path]
	var n: Node3D = Models.scene(path).instantiate()
	var out := []
	_collect(n, n.transform, out)
	n.free()
	_parts[path] = out
	return out

static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([(n as MeshInstance3D).mesh, xf, String(n.name) + "/" + String(n.get_parent().name)])
	for c in n.get_children():
		if c is Node3D:
			_collect(c, xf * (c as Node3D).transform, out)

## Ajoute un GLB sculpté au décor fusionné. `group` : surface de ses parts lumineuses (« glow » fixe,
## « pulse » qui respire).
static func _add(mg: Dictionary, path: String, xf: Transform3D, group: String = "glow") -> void:
	for p in _parts_of(path):
		var key := group if "_glow" in String(p[2]) else "body"
		if "_pulse" in String(p[2]):
			key = "pulse"
		if not mg.has(key):
			var s := SurfaceTool.new()
			s.begin(Mesh.PRIMITIVE_TRIANGLES)
			mg[key] = s
		var m: Mesh = p[0]
		for si in range(m.get_surface_count()):
			(mg[key] as SurfaceTool).append_from(m, si, xf * (p[1] as Transform3D))

## Un seul maillage pour tout le décor statique : une surface par matériau (corps, lueurs, lueurs qui respirent).
static func _merge_end(mg: Dictionary, root: Node3D, st: Dictionary) -> void:
	var am := ArrayMesh.new()
	var mats := []
	for key in ["body", "glow", "pulse"]:
		if not mg.has(key):
			continue
		(mg[key] as SurfaceTool).commit(am)
		mats.append(_mat(key, st))
	for i in range(mats.size()):
		am.surface_set_material(i, mats[i])
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	root.set_meta("static", mi)

static func _mat(key: String, st: Dictionary) -> Material:
	if key == "body":
		return Rig3D.body_mat(Color(1, 1, 1))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(1.8, 1.8, 1.8)
	if key == "pulse":
		st["pulse"] = m
	return m
