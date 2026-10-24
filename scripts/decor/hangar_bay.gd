extends RefCounted
## Nébuleuse 7 — quai nord, baie 07 (hors de l'aire de jeu, au-delà du garde-corps) : la Pie, navette des
## Passeurs, posée sur son aire ; pompes, consoles, râteliers de la compagnie de fret HÉLIX FRET, bras de chargement.
## Objets sculptés (tools/decor/bay_*.py -> assets/decor/bay/*.glb), sol peint (bay_floor.png).
## Appelé par view3d.gd avec la vue `v` (voir hangar_shell.gd) : le décor statique part dans le lot v._batch.

const Models = preload("res://scripts/models.gd")
const BAY := "res://assets/decor/bay/"
const ORANGE := Color("#FF7A2F")
const SHADE := Color(0.74, 0.74, 0.8)  # le quai reste plus sombre que l'aire de jeu

static var _mats := {}
static var _parts := {}
static var tris := 0  # triangles du quai posés (affichés avec --baystats)

static func _mesh_tris(m: Mesh) -> int:
	var n := 0
	for i in range(m.get_surface_count()):
		var arr := m.surface_get_arrays(i)
		var idx = arr[Mesh.ARRAY_INDEX]
		n += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n

# ---------------------------------------------------------------- matériaux
## Texture avec mipmaps (l'import par défaut n'en fait pas ; le sol est vu en biais).
static func tex(path: String) -> Texture2D:
	var key := "tex:" + path
	if _mats.has(key):
		return _mats[key]
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_mats[key] = t
	return t

## Métal peint usé : couleurs par sommet (écaillures, crasse sculptées) x salissures en projection triplanaire.
static func paint_mat() -> StandardMaterial3D:
	if _mats.has("paint"):
		return _mats["paint"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = SHADE
	m.albedo_texture = tex(BAY + "bay_grime.png")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.45, 0.45, 0.45)
	m.uv1_triplanar_sharpness = 2.0
	m.roughness = 0.66
	m.metallic_specular = 0.42
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.4
	_mats["paint"] = m
	return m

## Verre fumé (verrières, baies) : brillant.
static func glass_mat() -> StandardMaterial3D:
	if _mats.has("glass"):
		return _mats["glass"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = SHADE
	m.roughness = 0.12
	m.metallic = 0.3
	m.metallic_specular = 0.9
	m.rim_enabled = true
	m.rim = 0.5
	m.rim_tint = 0.2
	_mats["glass"] = m
	return m

static func glow_mat(energy: float) -> StandardMaterial3D:
	var key := "glow%.2f" % energy
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(energy, energy, energy)
	m.disable_receive_shadows = true
	_mats[key] = m
	return m

static func blink_mat() -> ShaderMaterial:
	if _mats.has("blink"):
		return _mats["blink"]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/bay_blink.gdshader")
	_mats["blink"] = m
	return m

## Matériau d'une part sculptée d'après son nom : *_glow lumineux, *_blink clignotant, *_glass verre.
static func mat_for(part_name: String) -> Material:
	if "_blink" in part_name:
		return blink_mat()
	if "_glow" in part_name:
		return glow_mat(2.2)
	if "_glass" in part_name:
		return glass_mat()
	return paint_mat()

## Maillages d'un GLB sculpté, chacun avec le matériau de sa part, et leur transformation locale.
static func parts(path: String) -> Array:
	if _parts.has(path):
		return _parts[path]
	var root: Node = Models.scene(path).instantiate()
	var out := []
	_collect(root, Transform3D.IDENTITY, out)
	root.free()
	_parts[path] = out
	return out

static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var nm := String(n.name) + "/" + String(n.get_parent().name if n.get_parent() else "")
		var m: Mesh = (n as MeshInstance3D).mesh.duplicate()
		for i in range(m.get_surface_count()):
			m.surface_set_material(i, mat_for(nm))
		out.append([m, here, nm, _mesh_tris(m)])
	for c in n.get_children():
		_collect(c, here, out)

## Objet statique : ajouté au lot (un MultiMesh par maillage pour tout le décor).
static func put(v: Node, name: String, pos: Vector3, rot_y: float = 0.0, scl: float = 1.0) -> void:
	put_xf(v, name, Transform3D(Basis(Vector3.UP, rot_y) * Basis.from_scale(Vector3.ONE * scl), pos))

## Objet en nœuds (pièces animées) : un MeshInstance3D par part, nommé comme la part.
static func node(name: String) -> Node3D:
	var root := Node3D.new()
	root.name = name
	for p in parts(BAY + name + ".glb"):
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.transform = p[1]
		mi.name = String(p[2]).get_slice("/", 0)
		root.add_child(mi)
		tris += int(p[3])
	return root

## Objet statique placé par une transformation complète (travées étirées du garde-corps).
static func put_xf(v: Node, name: String, xf: Transform3D) -> void:
	for p in parts(BAY + name + ".glb"):
		var m: Mesh = p[0]
		tris += int(p[3])
		if not v._batch.has(m):
			v._batch[m] = []
		(v._batch[m] as Array).append(xf * (p[1] as Transform3D))

## Quads du décor (vitres, plinthes, flaques de lumière) : un MultiMesh sans ombre.
static func _quads(v: Node, size: Vector2, mat: Material, xforms: Array) -> MultiMeshInstance3D:
	var qm := QuadMesh.new()
	qm.size = size
	qm.material = mat
	return v._mm(qm, xforms)

# ---------------------------------------------------------------- disposition
# (positions en m ; tools/decor/bay_floor.py et bay_props.py reprennent le vaisseau, les pompes et l'aire)
const SHIP_OFF := Vector3(0.2, 0.0, 1.86)  # par rapport à (W/2, 0, 0) : rampe de soute dans l'axe du sas
const PAD := Rect2(14.6, 0.5, 8.7, 2.72)  # aire de posé (x, z)
const GAP := 1.6  # demi-largeur du passage vers le sas dans le garde-corps

static func build(v: Node, _rng: RandomNumberGenerator) -> void:
	var W: float = v.arena.W * v.K
	var TOP: float = v.arena.TOP * v.K
	var WALLW: float = v.arena.WALL * v.K
	var level: Node3D = v.level
	var cx := W * 0.5
	tris = 0
	_floor(v, W, TOP)
	_north_wall(v, W)
	_rail(v, W, TOP, WALLW)
	# la Pie, navette des Passeurs (une instance : nœuds simples, ombres portées)
	var ship := node("bay_ship")
	ship.position = Vector3(cx, 0, 0) + SHIP_OFF
	level.add_child(ship)
	# lumière chaude de la soute (seule lumière dynamique du quai) : rampe et intérieur éclairés
	var hl := OmniLight3D.new()
	hl.position = Vector3(cx, 1.15, 2.75)
	hl.light_color = Color(1.0, 0.82, 0.6)
	hl.omni_range = 2.6
	hl.light_energy = 0.9
	hl.omni_attenuation = 1.6
	level.add_child(hl)
	_props(v)
	_beacons(v, cx)
	_screens(v)
	_signs(v, cx)
	level.add_child(arm(Vector3(8.8, 0, 2.15)))
	if "--baystats" in OS.get_cmdline_user_args():
		print("quai nord : %d triangles sculptés (dont la Pie)" % tris)

## Pont peint : une plaque texturée pour tout le quai (joints, rivets, aire de posé, marquages, traces).
static func _floor(v: Node, W: float, TOP: float) -> void:
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(W, TOP)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = tex(BAY + "bay_floor.png")
	fm.albedo_color = Color(0.8, 0.8, 0.84)
	fm.roughness = 0.7
	fm.metallic_specular = 0.45
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	fl.material_override = fm
	fl.position = Vector3(W * 0.5, 0.0, TOP * 0.5)
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(v.level as Node3D).add_child(fl)

## Mur nord : modules de 3 m (poteau en I, socle à grilles, gaines) et grandes vitres sur la nébuleuse.
static func _north_wall(v: Node, W: float) -> void:
	var panes := []
	var x := -0.75
	while x < W + 1.5:
		put(v, "bay_wall", Vector3(x, 0, 0))
		panes.append(Transform3D(Basis(), Vector3(x, 1.88, 0.13)))
		x += 3.0
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.5, 0.62, 0.14)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.05
	gm.metallic_specular = 1.0
	gm.rim_enabled = true
	gm.rim = 0.6
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quads(v, Vector2(2.92, 2.84), gm, panes)
	# la nébuleuse derrière les baies : toile de fond (bande du panorama) vue au travers des vitres
	var bd := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(W + 8.0, 10.0)
	bd.mesh = bq
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_texture = tex(BAY + "bay_nebula.jpg")
	bm.albedo_color = Color(0.85, 0.85, 0.9)
	bm.disable_receive_shadows = true
	bd.material_override = bm
	bd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bd.position = Vector3(W * 0.5, -0.5, -2.6)
	(v.level as Node3D).add_child(bd)

## Garde-corps sculpté (montants, lisse, sous-lisse) en travées étirées, plinthe à bandes, bornes du sas.
static func _rail(v: Node, W: float, TOP: float, WALLW: float) -> void:
	var cx := W * 0.5
	var z := TOP - 0.05
	var kick := []
	for side in [-1, 1]:
		var a: float = WALLW + 0.02 if side < 0 else cx + GAP
		var b: float = cx - GAP if side < 0 else W - WALLW - 0.02
		var n := int(round((b - a) / 1.5))
		var step := (b - a) / n
		for i in range(n):
			put_xf(v, "bay_rail", Transform3D(Basis.from_scale(Vector3(step / 1.5, 1, 1)), Vector3(a + i * step, 0, z)))
		kick.append(Transform3D(Basis.from_scale(Vector3(b - a, 1, 1)), Vector3((a + b) * 0.5, 0.1, z + 0.045)))
		put(v, "bay_gate", Vector3(cx + side * GAP, 0, z))
	var sm := ShaderMaterial.new()
	sm.shader = _kick_shader()
	sm.set_shader_parameter("tex", tex(BAY + "bay_kick.png"))
	_quads(v, Vector2(1.0, 0.16), sm, kick)
	# bord lumineux de l'aire de jeu (limite lisible), plus discret qu'avant
	var edge := Models.box(Vector3(W - 2.0 * WALLW, 0.02, 0.05), Models.glow_mat(ORANGE, 1.3))
	edge.position = Vector3(cx, 0.012, TOP + 0.05)
	(v.level as Node3D).add_child(edge)

## Plinthe : motif à bandes répété en coordonnées du monde (le quad est étiré sur toute la longueur).
static func _kick_shader() -> Shader:
	if _mats.has("kick_shader"):
		return _mats["kick_shader"]
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
varying vec2 wuv;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wuv = vec2(w.x / 0.64, 1.0 - (w.y - 0.02) / 0.16);
}
void fragment() {
	ALBEDO = texture(tex, wuv).rgb * 0.8;
	ROUGHNESS = 0.75;
	SPECULAR = 0.35;
}
"""
	_mats["kick_shader"] = sh
	return sh

## Équipement du quai : pompe et groupe de parc reliés à la Pie, râteliers, palettes, consoles, projecteurs.
static func _props(v: Node) -> void:
	# ouest : stockage HÉLIX FRET
	put(v, "bay_gas", Vector3(2.1, 0, 0.35))
	put(v, "bay_drums", Vector3(3.3, 0, 1.25), 0.4)
	put(v, "bay_rack_a", Vector3(6.0, 0, 0.36))
	put(v, "bay_pallet_a", Vector3(4.6, 0, 2.55), 0.12)
	put(v, "bay_pallet_c", Vector3(6.4, 0, 2.75), -0.08)
	put(v, "bay_pallet_b", Vector3(10.0, 0, 1.25), 0.05)
	put(v, "bay_console2", Vector3(12.0, 0, 0.55))
	put(v, "bay_pump", Vector3(13.6, 0, 0.95))
	put(v, "bay_flood", Vector3(14.1, 0, 3.0), atan2(4.8, -1.1))
	# est : énergie sol, consoles, conteneur, râtelier
	put(v, "bay_power", Vector3(24.4, 0, 1.3))
	put(v, "bay_flood", Vector3(23.75, 0, 3.0), atan2(-4.8, -1.1))
	put(v, "bay_console", Vector3(26.2, 0, 0.55))
	put(v, "bay_container", Vector3(28.0, 0, 1.45), 0.06)
	put(v, "bay_rack_b", Vector3(31.0, 0, 0.36))
	put(v, "bay_console", Vector3(33.7, 0, 0.55))
	put(v, "bay_drums", Vector3(35.6, 0, 1.05), 1.3)
	put(v, "bay_pallet_b", Vector3(35.2, 0, 2.5), -0.1)
	put(v, "bay_cart", Vector3(29.4, 0, 1.75), 0.3)
	put(v, "bay_reel", Vector3(31.9, 0, 1.4), -PI * 0.5)
	put(v, "bay_cones", Vector3(13.9, 0, 2.0), 0.4)
	put(v, "bay_cones", Vector3(24.2, 0, 2.55), 2.2)
	# flaques de lumière des projecteurs sur l'aire (additives)
	var pool := StandardMaterial3D.new()
	pool.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pool.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pool.albedo_texture = Models.radial()
	pool.albedo_color = Color(1.0, 0.86, 0.62, 0.32)
	pool.disable_receive_shadows = true
	var pools := []
	for p in [Vector3(15.7, 0.02, 2.6), Vector3(22.2, 0.02, 2.6)]:
		pools.append(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), p))
	_quads(v, Vector2(3.2, 1.8), pool, pools)

## Balises de l'aire de posé : chenillard le long des bords visibles (pas sous la rampe).
static func _beacons(v: Node, cx: float) -> void:
	var x := PAD.position.x
	while x <= PAD.end.x + 0.01:
		if absf(x - cx) > 1.0:
			put(v, "bay_beacon", Vector3(x, 0, PAD.end.y))
		x += PAD.size.x / 6.0
	for zz in [PAD.position.y + 0.3, PAD.position.y + 1.3]:
		put(v, "bay_beacon", Vector3(PAD.position.x, 0, zz))
		put(v, "bay_beacon", Vector3(PAD.end.x, 0, zz))

## Écrans animés des consoles : un nœud par écran (shader bay_screen : manifeste, niveaux, radar, courbe).
static func _screens(v: Node) -> void:
	var sh: Shader = load("res://shaders/bay_screen.gdshader")
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-20.0))
	var n := tilt * Vector3(0, 0, 1)
	var list := [[12.0 - 0.42, 0], [12.0 + 0.42, 3], [26.2, 1], [33.7, 2]]
	var i := 0
	for s in list:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.62, 0.32)
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("mode", s[1])
		m.set_shader_parameter("seed", float(i) * 1.37)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(tilt, Vector3(s[0], 1.12, 0.55 - 0.12) + n * 0.035)
		mi.name = "bay_screen_%d" % i
		(v.level as Node3D).add_child(mi)
		i += 1

## Signalisation BAIE 07 : caissons sur les poteaux qui encadrent l'aire, grand caisson au-dessus de la Pie.
static func _signs(v: Node, cx: float) -> void:
	var font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	for s in [[Vector3(12.75, 1.2, 0.52), 1.0, "BAIE 07"], [Vector3(24.75, 1.2, 0.52), 1.0, "BAIE 07"], [Vector3(cx, 2.45, 0.52), 1.9, "BAIE 07 · HÉLIX FRET"]]:
		put(v, "bay_sign", s[0], 0.0, s[1])
		var lb := Label3D.new()
		lb.text = s[2]
		lb.font = font
		lb.font_size = 64
		lb.pixel_size = 0.0032 * float(s[1]) * (0.45 if String(s[2]).length() > 8 else 1.0)
		lb.modulate = Color(1.0, 0.86, 0.66)
		lb.outline_size = 0
		lb.position = s[0] + Vector3(0, 0, 0.035 * float(s[1]))
		(v.level as Node3D).add_child(lb)

# ---------------------------------------------------------------- pièces animées
## Bras de chargement articulé (GLB hiérarchisé, matériaux d'après le nom des parts).
static func arm(pos: Vector3) -> Node3D:
	var a := BayArm.new()
	a.name = "bay_arm"
	a.position = pos
	var root: Node3D = Models.scene(BAY + "bay_arm.glb").instantiate()
	a.add_child(root)
	for n in root.find_children("*", "Node3D", true, false):
		a.parts[String(n.name)] = n
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_override = mat_for(String(n.name))
			tris += _mesh_tris((n as MeshInstance3D).mesh)
	return a

## Pivote entre la palette et le chariot, pose et reprend sa caisse ; cycle lent, poignet toujours d'aplomb.
class BayArm extends Node3D:
	var parts := {}
	var t := 0.0

	func _process(dt: float) -> void:
		if not parts.has("arm_turret"):
			return
		t += dt
		var p := fmod(t, 11.0) / 11.0
		var s: float
		if p < 0.2:
			s = 0.0
		elif p < 0.5:
			s = smoothstep(0.2, 0.5, p)
		elif p < 0.7:
			s = 1.0
		else:
			s = 1.0 - smoothstep(0.7, 1.0, p)
		var low := 1.0 - clampf(minf(absf(p - 0.1), absf(p - 0.6)) / 0.1, 0.0, 1.0)
		var sh := lerpf(0.2, 0.55, low)
		var el := lerpf(0.05, 0.4, low)
		(parts["arm_turret"] as Node3D).rotation.y = lerpf(-1.25, 0.95, s)
		(parts["arm_lower"] as Node3D).rotation.x = sh
		(parts["arm_upper"] as Node3D).rotation.x = el
		(parts["arm_head"] as Node3D).rotation.x = -(sh + el)
		(parts["arm_head"] as Node3D).rotation.y = sin(t * 0.6) * 0.3
