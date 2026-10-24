extends RefCounted
## Cité Néon — coque du toit-terrasse : sol mouillé (dalles, bitume, flaques qui reflètent les néons), marquages,
## parapets, tubes néon, rambardes, antennes, tour voisine au nord (écrans géants, enseignes, escalier de secours,
## passerelle). Appelé par neon_world.gd avec la vue `v` (v.level, v.arena, v.K).
## Textures et maillages : tools/decor/neon_shell_floor.py, neon_shell_edges.py, neon_shell_sky.py
## (assets/decor/neon/shell/). Éclairage du sol et des bords simulé en shader (shaders/neon_light.gdshaderinc).

const NS := "res://assets/decor/neon/shell/"
## calque du sol, des marquages et des bords : les lumières dynamiques ne les éclairent pas (un seul passage)
const DECK_LAYER := 2

static var _meta: Dictionary = {}

static func meta() -> Dictionary:
	if _meta.is_empty():
		_meta = (load(NS + "shell_meta.json") as JSON).data
	return _meta

static func build(v: Node, _rng: RandomNumberGenerator) -> void:
	var data: Dictionary = (load(NS + "roof_layout.json") as JSON).data
	var lt := _layout_tex(data)
	_build_floor(v, data, lt)
	_build_marks(v, data, lt)
	_build_edges(v)

## Paramètres partagés par tous les matériaux qui reçoivent les néons simulés (sol, marquages, bords).
static func light_params(m: ShaderMaterial) -> void:
	var md := meta()
	m.set_shader_parameter("facade_tex", load(NS + "neon_facade.png"))
	m.set_shader_parameter("sky_tex", load(NS + "neon_sky.png"))
	var fr: Array = md["facade_rect"]
	m.set_shader_parameter("facade_rect", Vector4(fr[0], fr[1], fr[2], fr[3]))
	m.set_shader_parameter("facade_z", float(md["facade_z"]))
	var sa := []
	var sb := []
	var sc := []
	for s in md["strips"]:
		var a: Array = s[0]
		var b: Array = s[1]
		var c: Array = s[2]
		sa.append(Vector3(a[0], a[1], a[2]))
		sb.append(Vector3(b[0], b[1], b[2]))
		sc.append(Vector4(c[0], c[1], c[2], float(s[3])))
	while sa.size() < 8:
		sa.append(Vector3.ZERO)
		sb.append(Vector3(0, 0, 1))
		sc.append(Vector4.ZERO)
	m.set_shader_parameter("strip_a", sa)
	m.set_shader_parameter("strip_b", sb)
	m.set_shader_parameter("strip_col", sc)
	m.set_shader_parameter("glyph_tex", load(NS + "neon_atlas.png"))
	var gr: Array = md["glyph_rect"]
	m.set_shader_parameter("glyph_rect", Vector4(gr[0], gr[1], gr[2], gr[3]))
	var rects := []
	var modes := []
	for s in md["screens"]:
		rects.append(Vector4(s[0], s[1], s[2], s[3]))
		modes.append(Vector4(s[4], s[5], s[6], 0.0))
	m.set_shader_parameter("ns_rect", rects)
	m.set_shader_parameter("ns_mode", modes)

static func _layout_tex(data: Dictionary) -> ImageTexture:
	var g: Array = data["grid"]
	var nx := int(g[4])
	var nz := int(g[5])
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

static func _roof_params(m: ShaderMaterial, data: Dictionary, lt: Texture2D) -> void:
	var g: Array = data["grid"]
	m.set_shader_parameter("layout_tex", lt)
	m.set_shader_parameter("grid", Vector4(g[0], g[1], g[2], g[3]))
	m.set_shader_parameter("grid_n", Vector2(g[4], g[5]))
	var mr: Array = data["macro"]
	m.set_shader_parameter("macro_rect", Vector4(mr[0], mr[1], mr[2], mr[3]))
	m.set_shader_parameter("macro_tex", load(NS + "roof_macro.png"))
	var he: Array = data["heli"]
	m.set_shader_parameter("heli", Vector3(he[0], he[1], he[2]))
	m.set_shader_parameter("atlas_tex", load(NS + "roof_atlas.png"))
	m.set_shader_parameter("detail_tex", load(NS + "roof_detail.png"))
	light_params(m)

## Sol : un seul quad sous tout le toit (parapets compris).
static func _build_floor(v: Node, data: Dictionary, lt: Texture2D) -> void:
	var K: float = v.K
	var W: float = v.arena.W * K
	var H: float = v.arena.H * K
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/neon_roof_floor.gdshader")
	_roof_params(m, data, lt)
	var rects := []
	var cells := []
	for k in range(9):
		var r: Array = data["ins_rects"][k]
		rects.append(Vector4(r[0], r[1], r[2], r[3]))
		var c: Array = data["ins_cells"][k]
		cells.append(Vector2(c[0], c[1]))
	m.set_shader_parameter("ins_rect", rects)
	m.set_shader_parameter("ins_cells", cells)
	var mr: Array = data["macro"]
	var z0: float = mr[1]
	var pm := PlaneMesh.new()
	pm.size = Vector2(W, H - z0)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	mi.position = Vector3(W * 0.5, 0.0, (z0 + H) * 0.5)
	mi.layers = DECK_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(v.level as Node3D).add_child(mi)

## Marquages peints : un MultiMesh de quads (cadre d'atlas en donnée personnalisée).
static func _build_marks(v: Node, data: Dictionary, lt: Texture2D) -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/neon_roof_marks.gdshader")
	_roof_params(m, data, lt)
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

## Parapets, rambardes, antennes, tour voisine : un maillage, un matériau.
static func _build_edges(v: Node) -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/neon_shell.gdshader")
	m.set_shader_parameter("atlas_tex", load(NS + "neon_atlas.png"))
	light_params(m)
	var scn: Node = (load(NS + "shell_edges.glb") as PackedScene).instantiate()
	for mi in scn.find_children("*", "MeshInstance3D", true, false):
		var out := MeshInstance3D.new()
		out.mesh = (mi as MeshInstance3D).mesh
		out.material_override = m
		out.layers = DECK_LAYER
		out.lod_bias = 100.0
		# la tour voisine ne porte pas d'ombre (la lune est derrière elle) ; parapets et rambardes, si
		out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if String(mi.name).begins_with("edges") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(v.level as Node3D).add_child(out)
	scn.free()

static func tris() -> int:
	var n := 0
	var scn: Node = (load(NS + "shell_edges.glb") as PackedScene).instantiate()
	for mi in scn.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in range(mesh.get_surface_count()):
			n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	scn.free()
	return n
