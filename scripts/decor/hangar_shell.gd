extends RefCounted
## Nébuleuse 7 — coque du hangar : sol en tôle de pont, marquages peints, murs ouest / est, garde-corps sud,
## lumières et ambiance. Appelé par view3d.gd (_build_level) avec la vue `v` : helpers v._mm, v._bput,
## v._bbox, v.level (parent du décor), v.arena (W, H, WALL, TOP en px, obstacles, pads), v.K (px -> m).
## Textures et maillages générés par tools/decor/shell_floor.py et shell_walls.py (assets/decor/shell/).

const Models = preload("res://scripts/models.gd")
const ST := "res://assets/models/station/"
const SH := "res://assets/decor/shell/"
const CYAN := Color("#3CF2D8")
const ORANGE := Color("#FF7A2F")
## calque de rendu du sol et des marquages : les lumières d'ambiance ne les éclairent pas (un seul passage)
const DECK_LAYER := 2

static var _floor_mat: ShaderMaterial = null
static var _marks_mat: ShaderMaterial = null

static func build(v: Node, _rng: RandomNumberGenerator) -> void:
	var K: float = v.K
	var W: float = v.arena.W * K
	var H: float = v.arena.H * K
	var WALL: float = v.arena.WALL * K
	var TOP: float = v.arena.TOP * K
	var data: Dictionary = (load(SH + "deck_layout.json") as JSON).data
	var beacons := _beacons(W, WALL)
	_build_floor(v, data, W, H, TOP, beacons)
	_build_marks(v, data, beacons)
	_build_walls(v, beacons)
	_build_fx(v, data, W, H, TOP)

## Gyrophares : x, hauteur, z, phase (repris par les shaders du sol, des marquages et des murs).
static func _beacons(W: float, WALL: float) -> Array:
	return [Vector4(WALL + 0.22, 3.0, 7.45, 0.0), Vector4(WALL + 0.22, 3.0, 16.45, 2.1),
		Vector4(W - WALL - 0.22, 3.0, 7.45, 4.0), Vector4(W - WALL - 0.22, 3.0, 16.45, 1.0)]

static func _set_lights(m: ShaderMaterial, beacons: Array) -> void:
	m.set_shader_parameter("beacons", beacons)

static func _layout_tex(data: Dictionary) -> ImageTexture:
	var g: Array = data["grid"]
	var nx := int(g[3])
	var nz := int(g[4])
	var bytes := PackedByteArray()
	bytes.resize(nx * nz * 4)
	var cells: Array = data["cells"]
	for r in range(nz):
		var row: Array = cells[r]
		for c in range(nx):
			var cl: Array = row[c]
			var o := (r * nx + c) * 4
			for k in range(4):
				bytes[o + k] = int(cl[k])
	var img := Image.create_from_data(nx, nz, false, Image.FORMAT_RGBA8, bytes)
	return ImageTexture.create_from_image(img)

static func _deck_params(m: ShaderMaterial, data: Dictionary, lt: Texture2D) -> void:
	var g: Array = data["grid"]
	m.set_shader_parameter("layout_tex", lt)
	m.set_shader_parameter("grid", Vector4(g[0], g[1], g[2], 0.0))
	m.set_shader_parameter("grid_n", Vector2(g[3], g[4]))
	var mr: Array = data["macro"]
	m.set_shader_parameter("macro_rect", Vector4(mr[0], mr[1], mr[2], mr[3]))
	m.set_shader_parameter("macro_tex", load(SH + "deck_macro.png"))
	m.set_shader_parameter("atlas_tex", load(SH + "deck_atlas.png"))
	m.set_shader_parameter("detail_tex", load(SH + "deck_detail.png"))

## Sol : un seul quad sur toute l'aire de jeu (le quai nord est à hangar_bay.gd).
static func _build_floor(v: Node, data: Dictionary, W: float, H: float, TOP: float, beacons: Array) -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/n7_deck_floor.gdshader")
	var lt := _layout_tex(data)
	_deck_params(m, data, lt)
	m.set_shader_parameter("detail_n", load(SH + "deck_detail_n.png"))
	var rects := []
	var cells := []
	for k in range(9):
		var r: Array = data["ins_rects"][k]
		rects.append(Vector4(r[0], r[1], r[2], r[3]))
		var c: Array = data["ins_cells"][k]
		cells.append(Vector2(c[0], c[1]))
	m.set_shader_parameter("ins_rect", rects)
	m.set_shader_parameter("ins_cells", cells)
	_set_lights(m, beacons)
	_floor_mat = m
	var pm := PlaneMesh.new()
	pm.size = Vector2(W, H - TOP)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	mi.position = Vector3(W * 0.5, 0.0, (TOP + H) * 0.5)
	mi.layers = DECK_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(v.level as Node3D).add_child(mi)

## Marquages peints : un MultiMesh de quads (cadre d'atlas en donnée personnalisée).
static func _build_marks(v: Node, data: Dictionary, beacons: Array) -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/n7_deck_marks.gdshader")
	_deck_params(m, data, (_floor_mat.get_shader_parameter("layout_tex") as Texture2D))
	_set_lights(m, beacons)
	_marks_mat = m
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	pm.material = m
	var list: Array = data["decals"]
	var marks: Dictionary = data["marks"]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = pm
	mm.instance_count = list.size()
	for i in range(list.size()):
		var d: Array = list[i]
		var uv: Array = marks[d[0]]["uv"]
		var b := Basis(Vector3.UP, deg_to_rad(float(d[5]))) * Basis.from_scale(Vector3(d[3], 1.0, d[4]))
		mm.set_instance_transform(i, Transform3D(b, Vector3(d[1], 0.004 + 0.0004 * (i % 4), d[2])))
		mm.set_instance_custom_data(i, Color(uv[0], uv[1], uv[2], uv[3]))
		mm.set_instance_color(i, Color(float(d[6]) / 32.0, float(d[7]) / 32.0, 0.5 + float(d[9]), float(d[8])))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.layers = DECK_LAYER
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(v.level as Node3D).add_child(mmi)

## Murs ouest / est et garde-corps sud : un maillage opaque (un matériau, atlas) et les vitres des hublots.
static func _build_walls(v: Node, beacons: Array) -> void:
	var meta: Dictionary = (load(SH + "wall_meta.json") as JSON).data
	var sr: Array = meta["scroll"]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/n7_shell_wall.gdshader")
	m.set_shader_parameter("atlas_tex", load(SH + "wall_atlas.png"))
	m.set_shader_parameter("scroll_rect", Vector4(sr[0], sr[1], sr[2], sr[3]))
	_set_lights(m, beacons)
	var g := ShaderMaterial.new()
	g.shader = load("res://shaders/n7_porthole.gdshader")
	g.set_shader_parameter("sky_tex", load("res://assets/env/space.jpg"))
	var scn: Node = (load(SH + "shell_walls.glb") as PackedScene).instantiate()
	for mi in scn.find_children("*", "MeshInstance3D", true, false):
		var src: MeshInstance3D = mi
		var out := MeshInstance3D.new()
		out.mesh = src.mesh
		var glass := String(src.name).begins_with("glass")
		out.material_override = g if glass else m
		out.layers = DECK_LAYER
		out.lod_bias = 100.0  # toujours le maillage complet
		out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if glass else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		(v.level as Node3D).add_child(out)
	scn.free()

## Vapeur des grilles de caniveau et poussière en suspension (particules CPU, un appel de dessin chacune).
static func _build_fx(v: Node, data: Dictionary, W: float, H: float, TOP: float) -> void:
	var level: Node3D = v.level
	var g: Array = data["grid"]
	var cells: Array = data["cells"]
	var vents := []
	for r in range(int(g[4])):
		for c in [0, int(g[3]) - 1]:
			var cl: Array = cells[r][c]
			if (int(cl[1]) >> 4) == 4 and int(cl[2]) == 0:
				vents.append(Vector3(g[0] + (c + 0.5) * g[2], 0.05, g[1] + (r + 1) * g[2]))
	var puff := StandardMaterial3D.new()
	puff.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff.vertex_color_use_as_albedo = true
	puff.albedo_texture = Models.radial()
	puff.disable_receive_shadows = true
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	qm.material = puff
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.78, 0.95, 0.0))
	ramp.set_color(1, Color(0.75, 0.78, 0.95, 0.0))
	ramp.add_point(0.25, Color(0.78, 0.8, 0.95, 0.13))
	ramp.add_point(0.7, Color(0.7, 0.72, 0.9, 0.06))
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.35))
	grow.add_point(Vector2(1, 1.0))
	# trois vapeurs, réparties entre les deux murs
	var picks := []
	for i in range(vents.size()):
		if i % 3 == 1:
			picks.append(vents[i])
	for p in picks.slice(0, 4):
		var st := CPUParticles3D.new()
		st.mesh = qm
		st.amount = 9
		st.lifetime = 3.2
		st.preprocess = 3.0
		st.position = p
		st.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		st.emission_box_extents = Vector3(0.18, 0.02, 0.5)
		st.direction = Vector3(0.25 if p.x < W * 0.5 else -0.25, 1, 0)
		st.spread = 18.0
		st.gravity = Vector3(0, 0.15, 0)
		st.initial_velocity_min = 0.35
		st.initial_velocity_max = 0.6
		st.damping_min = 0.15
		st.damping_max = 0.3
		st.angle_min = 0.0
		st.angle_max = 360.0
		st.scale_amount_min = 0.7
		st.scale_amount_max = 1.2
		st.scale_amount_curve = grow
		st.color_ramp = ramp
		st.local_coords = false
		level.add_child(st)
	# poussière : quelques grains pâles qui dérivent lentement dans tout le hangar
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	dm.albedo_texture = Models.radial()
	var dq := QuadMesh.new()
	dq.size = Vector2(0.05, 0.05)
	dq.material = dm
	var dramp := Gradient.new()
	dramp.set_color(0, Color(0.8, 0.8, 1.0, 0.0))
	dramp.set_color(1, Color(0.8, 0.8, 1.0, 0.0))
	dramp.add_point(0.5, Color(0.85, 0.82, 1.0, 0.45))
	var dust := CPUParticles3D.new()
	dust.mesh = dq
	dust.amount = 90
	dust.lifetime = 14.0
	dust.preprocess = 14.0
	dust.position = Vector3(W * 0.5, 1.6, (TOP + H) * 0.5)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(W * 0.5 - 1.0, 1.4, (H - TOP) * 0.5 - 0.5)
	dust.direction = Vector3(1, 0.2, 0.3)
	dust.spread = 180.0
	dust.gravity = Vector3.ZERO
	dust.initial_velocity_min = 0.02
	dust.initial_velocity_max = 0.08
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.4
	dust.color_ramp = dramp
	dust.local_coords = false
	level.add_child(dust)

## Lumières d'ambiance colorées (3 au plus, sans le sol ni les marquages : ils ont leur éclairage simulé).
static func lights(v: Node) -> void:
	var K: float = v.K
	var W: float = v.arena.W * K
	var H: float = v.arena.H * K
	var TOP: float = v.arena.TOP * K
	var ls := [[Vector3(W * 0.5, 2.5, 1.8), ORANGE, 9.0, 1.4], [Vector3(W * 0.2, 2.2, (TOP + H) * 0.5), Color("#8E6BFF"), 9.0, 0.6], [Vector3(W * 0.8, 2.2, (TOP + H) * 0.5), Color("#6B8BFF"), 9.0, 0.6]]
	for L in ls:
		var ol := OmniLight3D.new()
		ol.position = L[0]
		ol.light_color = L[1]
		ol.omni_range = L[2]
		ol.light_energy = L[3]
		ol.omni_attenuation = 1.4
		ol.light_cull_mask = 0xFFFFF & ~DECK_LAYER
		(v.level as Node3D).add_child(ol)
