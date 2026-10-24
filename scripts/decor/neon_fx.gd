extends RefCounted
## Cité Néon — ambiance animée : pluie (MultiMesh, animée en shader), éclaboussures sur le toit, brume colorée
## basse (quads additifs), drones-taxis qui traversent le vide, lumière de la façade qui suit l'écran géant.
## Tout vit sous v.level (libéré au changement de monde).

const NS := "res://assets/decor/neon/shell/"
const RAIN_DROPS := 900
const SPLASHES := 120

static func build(v: Node) -> void:
	var K: float = v.K
	var W: float = v.arena.W * K
	var H: float = v.arena.H * K
	var level: Node3D = v.level
	_rain(level)
	_splashes(level)
	_mist(level, W, H)
	_flyers(level, W, H)

static func _shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m

## MultiMesh sans données : chaque instance se place seule dans le shader (INSTANCE_ID, TIME, caméra).
static func _procedural_mm(level: Node3D, mesh: PrimitiveMesh, count: int, mat: Material) -> void:
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in range(count):
		mm.set_instance_transform(i, Transform3D.IDENTITY)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(Vector3(-200, -80, -200), Vector3(400, 200, 400))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level.add_child(mmi)

static func _rain(level: Node3D) -> void:
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	qm.center_offset = Vector3(0, 0.5, 0)
	_procedural_mm(level, qm, RAIN_DROPS, _shader_mat("res://shaders/neon_rain.gdshader"))

static func _splashes(level: Node3D) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	_procedural_mm(level, pm, SPLASHES, _shader_mat("res://shaders/neon_splash.gdshader"))

## Nappes de brume : dans le vide autour du toit (rose, violet), montant le long des parapets, et un voile
## très léger au pied des parapets (la teinte des tubes) ; jamais au milieu de l'aire de jeu.
static func _mist(level: Node3D, W: float, H: float) -> void:
	var pink := Color("#FF3CAC")
	var violet := Color("#8E4CFF")
	var blue := Color("#3C8CFF")
	var zn := 3.3
	# [centre, taille (x, z) ou (largeur, hauteur) si debout, teinte, énergie, debout (axe de la normale), graine]
	var quads := [
		[Vector3(-7.0, -3.0, (zn + H) * 0.5), Vector2(14.0, H - zn + 10.0), pink, 0.5, "", 1.0],
		[Vector3(-9.0, -10.0, (zn + H) * 0.5), Vector2(18.0, H - zn + 16.0), violet, 0.6, "", 2.0],
		[Vector3(W + 7.0, -3.0, (zn + H) * 0.5), Vector2(14.0, H - zn + 10.0), violet, 0.5, "", 3.0],
		[Vector3(W + 9.0, -10.0, (zn + H) * 0.5), Vector2(18.0, H - zn + 16.0), pink, 0.6, "", 4.0],
		[Vector3(W * 0.5, -4.0, H + 5.0), Vector2(W + 20.0, 10.0), pink, 0.5, "", 5.0],
		[Vector3(W * 0.5, -2.5, 1.65), Vector2(W + 12.0, 3.3), violet, 0.55, "", 6.0],
		[Vector3(W * 0.5, -6.0, 1.65), Vector2(W + 12.0, 3.3), pink, 0.65, "", 7.0],
		[Vector3(-0.7, -2.0, (zn + H) * 0.5), Vector2(H - zn + 6.0, 6.0), pink, 0.14, "x", 8.0],
		[Vector3(W + 0.7, -2.0, (zn + H) * 0.5), Vector2(H - zn + 6.0, 6.0), blue, 0.14, "x", 9.0],
		[Vector3(W * 0.5, -2.0, H + 0.7), Vector2(W + 6.0, 6.0), violet, 0.14, "z", 10.0],
		[Vector3(1.2, 0.18, (zn + H) * 0.5), Vector2(1.8, H - zn - 0.6), pink, 0.07, "", 11.0],
		[Vector3(W - 1.2, 0.18, (zn + H) * 0.5), Vector2(1.8, H - zn - 0.6), blue, 0.07, "", 12.0],
		[Vector3(W * 0.5, 0.18, H - 1.0), Vector2(W - 2.0, 1.6), violet, 0.06, "", 13.0],
	]
	for q in quads:
		var m := _shader_mat("res://shaders/neon_mist.gdshader")
		var sz: Vector2 = q[1]
		var c: Color = q[2]
		m.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
		m.set_shader_parameter("energy", q[3])
		m.set_shader_parameter("seed", q[5])
		m.set_shader_parameter("scale", Vector2(maxf(sz.x / 3.0, 1.0), maxf(sz.y / 3.0, 1.0)))
		var mi := MeshInstance3D.new()
		var axis: String = q[4]
		if axis == "":
			var pm := PlaneMesh.new()
			pm.size = sz
			mi.mesh = pm
		else:
			var qm := QuadMesh.new()
			qm.size = sz
			mi.mesh = qm
			m.set_shader_parameter("rise", 1.0)
			m.set_shader_parameter("edge", 0.18)
			if axis == "x":
				mi.rotation.y = PI * 0.5
		mi.material_override = m
		mi.position = q[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level.add_child(mi)

## Drones-taxis : un MultiMesh, trajectoires dans le vide (sous le niveau du toit) et dans la faille au nord.
static func _flyers(level: Node3D, W: float, H: float) -> void:
	var scn: Node = (load(NS + "taxi.glb") as PackedScene).instantiate()
	var mesh: Mesh = (scn.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	scn.free()
	var m := _shader_mat("res://shaders/neon_flyer.gdshader")
	m.set_shader_parameter("body_tints", [Vector3(0.95, 0.72, 0.15), Vector3(0.95, 0.25, 0.6), Vector3(0.2, 0.8, 0.85), Vector3(0.85, 0.85, 0.9)])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	# [milieu, cap (rad), vitesse, longueur, phase, teinte, échelle]
	var paths := [
		[Vector3(-7.5, -5.0, 10.0), PI, 9.0, 110.0, 0.1, 0.1, 1.2],
		[Vector3(-11.0, -12.0, 10.0), 0.0, 12.0, 120.0, 0.6, 0.4, 1.3],
		[Vector3(W + 7.5, -6.5, 10.0), 0.0, 10.0, 110.0, 0.35, 0.6, 1.2],
		[Vector3(W + 12.0, -15.0, 10.0), PI, 13.0, 120.0, 0.8, 0.9, 1.3],
		[Vector3(W * 0.5, -3.2, 1.65), -PI * 0.5, 11.0, 90.0, 0.25, 0.1, 1.0],
		[Vector3(W * 0.5, -8.0, H + 6.0), PI * 0.5, 9.0, 100.0, 0.55, 0.35, 1.3],
		[Vector3(-26.0, -20.0, 0.0), PI, 14.0, 130.0, 0.4, 0.85, 1.5],
	]
	mm.instance_count = paths.size()
	for i in range(paths.size()):
		var p: Array = paths[i]
		var b := Basis(Vector3.UP, float(p[1])) * Basis.from_scale(Vector3.ONE * float(p[6]))
		mm.set_instance_transform(i, Transform3D(b, p[0]))
		mm.set_instance_custom_data(i, Color(float(p[2]) / float(p[6]), float(p[3]) / float(p[6]), p[4], p[5]))
	mesh.surface_set_material(0, m)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(Vector3(-200, -80, -200), Vector3(400, 200, 400))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level.add_child(mmi)
