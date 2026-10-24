extends Node3D
## Rendu 3D du monde 1 (Nébuleuse 7). La simulation reste en 2D dans arena.gd ; ce nœud la met en scène :
## hangar de station (modèles Kenney CC0), ciel étoilé, lumière, caméra inclinée qui suit Jo, personnages
## et ennemis animés, projectiles lumineux, particules, effets de mort, butin, coffre, tourelles, drones.
## 1 unité 3D = 64 px de simulation. Axe x 2D -> x 3D, axe y 2D -> z 3D.

const Models = preload("res://scripts/models.gd")
const Actor3D = preload("res://scripts/actor3d.gd")
const Rig3D = preload("res://scripts/rig3d.gd")
const Mob3D = preload("res://scripts/mob3d.gd")
const Data = preload("res://scripts/data.gd")
const HangarShell = preload("res://scripts/decor/hangar_shell.gd")
const Door3D = preload("res://scripts/fx/door3d.gd")
const HangarProps = preload("res://scripts/decor/hangar_props.gd")
const HangarBay = preload("res://scripts/decor/hangar_bay.gd")

const K := 1.0 / 64.0
const ST := "res://assets/models/station/"
const SP := "res://assets/models/space/"
const JO_MODEL := "res://assets/chars3d/jo.glb"  # sculptée de zéro (tools/chars/jo.py)
const JO_GUN := "res://assets/models/blaster/blaster-b.glb"

const CYAN := Color("#3CF2D8")
const ORANGE := Color("#FF7A2F")
const GOLD := Color("#FFB347")
const RED := Color("#FF4D6D")
const MAGENTA := Color("#F23CB8")

# caméra
const CAM_PITCH := 56.0
const CAM_DIST := 11.5
const CAM_FOV := 38.0
## Recul, inclinaison et champ de la caméra de jeu, tailles de Jo et des ennemis : réglages du joueur
## (menu pause, mode développeur), dans l'autoload Dev (scripts/dev.gd).

var arena: Node
var hero2d: Node2D
var joy: Node
var active := false

var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var level: Node3D
var relais: Node3D
var hero: Rig3D
var hero_root: Node3D
var hero_light: OmniLight3D
var hero_shield: MeshInstance3D
var hero_ring: MeshInstance3D
var aim_line: MeshInstance3D
var aim_mat: StandardMaterial3D
var pads3d: Array = []

var mobs := {}  # id d'instance de l'ennemi -> Mob3D
var dying: Array = []  # Mob3D en train de mourir
var fx: Array = []  # effets temporaires {node, t, life, kind, ...}
var turret_nodes: Array = []
var ally_nodes: Array = []
var pickup_nodes := {}  # id du dictionnaire de ramassage -> Node3D (soins, objets)
## Tickets (la grande majorité du butin au sol) : pièce, trou et ombre dessinés par trois MultiMesh,
## trois appels de dessin quel que soit leur nombre ; id -> [position (Vector3), rotation (float)].
var tickets := {}
var _tk_mm: Array = []  # MultiMesh : pièce, trou, ombre
var chest_node: Node3D = null
var door_nodes: Array = []  # portails de fin de salle (scripts/fx/door3d.gd)
var chest_beam: MeshInstance3D = null

var bolt_mm: MultiMeshInstance3D
var halo_mm: MultiMeshInstance3D
var _glow_shader: Shader
var _ring_shader: Shader
var _dmg_labels: Array = []
var _font: Font

var cam_target := Vector3.ZERO
var shake := 0.0
var t := 0.0
var _flash_lights: Array = []
var _batch := {}  # Mesh -> Array[Transform3D] : décor statique regroupé en MultiMesh au montage
var _box_meshes := {}  # clé -> BoxMesh unité avec son matériau
var _flash_i := 0

func build(arena_node: Node, hero_node: Node2D, joy_node: Node) -> void:
	arena = arena_node
	hero2d = hero_node
	joy = joy_node
	_glow_shader = load("res://shaders/glow_billboard.gdshader")
	_ring_shader = load("res://shaders/ground_ring.gdshader")
	_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	_build_env()
	_build_level()
	_build_hero()
	_build_pools()
	arena.fired.connect(_on_fired)
	arena.enemy_hit.connect(_on_enemy_hit)
	arena.enemy_killed.connect(_on_enemy_killed)
	arena.enemy_spawned.connect(_on_enemy_spawned)
	arena.chest_opened.connect(_on_chest_opened)
	arena.bullet_blocked.connect(_on_blocked)
	arena.exploded.connect(_on_exploded)
	arena.shell_launched.connect(_on_shell)
	arena.doors_opened.connect(_on_doors_opened)
	arena.shockwave_started.connect(_on_shockwave)
	hero2d.damaged.connect(_on_hero_damaged)

static func p3(v: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(v.x * K, h, v.y * K)

# ---------------------------------------------------------------- ambiance
func _build_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/env/space.jpg")
	pano.energy_multiplier = 1.0
	sky.sky_material = pano
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	we.environment = env
	add_child(we)
	sun = SunLight.new()
	sun.add_to_group("sun")  # qualité adaptative (scripts/perf.gd)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	_env_defaults()
	cam = Camera3D.new()
	cam.fov = CAM_FOV
	cam.near = 0.5
	cam.far = 120.0
	add_child(cam)
	for i in range(3):
		var l := FlashLight.new()
		l.omni_range = 4.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		_flash_lights.append(l)

## Soleil : la portée de son ombre suit la caméra (profondeur du sol vu en haut de l'écran, avant le fondu de
## l'ombre) au lieu d'une distance fixe taillée pour le recul le plus large (26 m). Les objets hors de vue
## sortent de la passe d'ombre ; la carte, de même taille, couvre moins : ombres un peu plus nettes.
class SunLight extends DirectionalLight3D:
	const MAX_DIST := 26.0

	func _ready() -> void:
		process_priority = 1000  # après la caméra (view3d._place_camera)

	func _process(_dt: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or not shadow_enabled:
			return
		# rayon du haut de l'écran (champ vertical) : r = avant + haut * tan(fov / 2), composante avant = 1,
		# donc la profondeur où il touche le sol (y = 0) vaut hauteur / -r.y
		var b := cam.global_basis
		var ry := -b.z.y + b.y.y * tan(deg_to_rad(cam.fov * 0.5))
		var h := cam.global_position.y
		var d := MAX_DIST
		if ry < -0.05 and h > 0.0:
			d = clampf(h / -ry / directional_shadow_fade_start + 1.0, 8.0, MAX_DIST)
		if absf(d - directional_shadow_max_distance) > 0.25:
			directional_shadow_max_distance = d

## Éclair de lumière (tirs, explosions ; voir _flash_light) : caché tant qu'il est éteint. Une lumière
## d'énergie nulle reste comptée par le rendu : calculée pour chaque pixel des objets à sa portée (sol compris).
class FlashLight extends OmniLight3D:
	func _ready() -> void:
		visible = false
		process_priority = 1000  # après la vue, qui l'allume et l'éteint dans la même image

	func _process(_dt: float) -> void:
		var on := light_energy > 0.0
		if visible != on:
			visible = on

## Réglages d'ambiance de Nébuleuse 7 ; un autre monde les retouche ensuite dans son env(v).
func _env_defaults() -> void:
	var pano: PanoramaSkyMaterial = env.sky.sky_material
	pano.panorama = load("res://assets/env/space.jpg")
	pano.energy_multiplier = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.92)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	env.fog_enabled = false
	sun.rotation_degrees = Vector3(-58, 28, 0)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 0.9
	sun.shadow_bias = 0.04
	sun.directional_shadow_max_distance = 26.0

# ---------------------------------------------------------------- hangar
func _put(path: String, pos: Vector3, rot_y: float = 0.0, scl: Vector3 = Vector3.ONE, parent: Node3D = null, center: bool = false) -> Node3D:
	var n := Models.inst(path, center)
	n.position = pos
	n.rotation.y = rot_y
	n.scale = scl
	(parent if parent != null else level).add_child(n)
	return n

## Décor statique : ajouté au lot, monté par _flush_batch (fusionné par matériau).
func _bput(path: String, pos: Vector3, rot_y: float = 0.0, scl: Vector3 = Vector3.ONE, center: bool = false) -> void:
	var xf := Transform3D(Basis(Vector3.UP, rot_y) * Basis.from_scale(scl), pos)
	for part in Models.parts_of(path, center):
		var m: Mesh = part[0]
		if path.begins_with(SP):
			m = Models.tinted_mesh(m, 0.55)
		if not _batch.has(m):
			_batch[m] = []
		(_batch[m] as Array).append(xf * (part[1] as Transform3D))

## Boîte du décor (caisses) : maillage unité partagé par clé, mis à l'échelle par instance.
func _bbox(key: String, mat: Material, center: Vector3, size: Vector3, rot_y: float = 0.0) -> void:
	if not _box_meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE
		bm.material = mat
		_box_meshes[key] = bm
	var m: Mesh = _box_meshes[key]
	if not _batch.has(m):
		_batch[m] = []
	(_batch[m] as Array).append(Transform3D(Basis(Vector3.UP, rot_y) * Basis.from_scale(size), center))

## Ce qui est plat (socles, liserés, marquages : moins de FLAT_SHADOW de haut) ne projette pas d'ombre :
## elle tiendrait dans le biais de l'ombre, invisible, mais coûterait un dessin de plus dans la passe d'ombre.
const FLAT_SHADOW := 0.045
## attributs de sommet qui doivent concorder pour fusionner deux surfaces
const _MERGE_FMT := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_CUSTOM0 | Mesh.ARRAY_FORMAT_CUSTOM1 | Mesh.ARRAY_FORMAT_CUSTOM2 | Mesh.ARRAY_FORMAT_CUSTOM3 | Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS | Mesh.ARRAY_FORMAT_INDEX

## Fusion du lot : la salle est découpée en cases de cette taille (m, x et z, 6 x 4 cases) pour que la caméra
## et l'ombre écartent encore ce qu'elles ne voient pas (sans cases : 40 % de triangles en plus à l'écran).
const MERGE_CELL := Vector2(6.25, 5.5)

## Monte le lot statique. Les surfaces opaques sont fusionnées par matériau, par mode d'ombre et par case de la
## salle : un appel de dessin par matériau et par case au lieu d'un par maillage, dans chaque passe (couleur,
## soleil, ombre). Le reste (transparences, qui se trient par objet) garde un MultiMesh par maillage.
func _flush_batch() -> void:
	var groups := {}  # clé -> [SurfaceTool, matériau, ombre]
	for m in _batch.keys():
		var mesh: Mesh = m
		var xs: Array = _batch[m]
		var box: AABB = mesh.get_aabb()
		var h := 0.0
		for xf in xs:
			h = maxf(h, ((xf as Transform3D) * box).size.y)
		var cast := h >= FLAT_SHADOW
		var mats := []
		var mergeable := true
		for s in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(s)
			if mat == null and mesh is PrimitiveMesh:
				mat = (mesh as PrimitiveMesh).material
			mats.append(mat)
			mergeable = mergeable and _opaque(mat)
		if not mergeable:
			_mm(mesh, xs, cast)
			continue
		for s in range(mesh.get_surface_count()):
			var base := "%d/%d/%s/" % [(mats[s] as Material).get_instance_id(), _surface_fmt(mesh, s), cast]
			for xf in xs:
				var c := ((xf as Transform3D) * box).get_center()
				var key := base + str(Vector2i(floori(c.x / MERGE_CELL.x), floori(c.z / MERGE_CELL.y)))
				if not groups.has(key):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					groups[key] = [st, mats[s], cast]
				((groups[key] as Array)[0] as SurfaceTool).append_from(mesh, s, xf)
	for key in groups.keys():
		var g: Array = groups[key]
		var am := (g[0] as SurfaceTool).commit()
		am.surface_set_material(0, g[1])
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if g[2] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level.add_child(mi)
	_batch.clear()

## Attributs de sommet d'une surface (les maillages primitifs, BoxMesh, n'exposent pas leur format).
static func _surface_fmt(mesh: Mesh, s: int) -> int:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_format(s) & _MERGE_FMT
	var arrays := mesh.surface_get_arrays(s)
	var fmt := 0
	for i in range(Mesh.ARRAY_MAX):
		if arrays[i] != null:
			fmt |= 1 << i
	return fmt

## Matériau fusionnable : sans tri de transparence (opaque, ou découpé : alpha scissor / hash), et dont le
## shader ne dépend pas de l'instance (son origine : phase des balises, moyeu des hélices…). Un matériau peut
## le déclarer lui-même (méta « per_instance ») ; sinon on lit son code : MODEL_MATRIX n'y doit servir qu'à
## passer sommets et normales dans le monde.
static func _opaque(mat: Material) -> bool:
	if mat == null or mat.next_pass != null or bool(mat.get_meta("per_instance", false)):
		return false
	if mat is BaseMaterial3D:
		if (mat as BaseMaterial3D).billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
			return false  # tourné autour de l'origine de l'instance
		var t := (mat as BaseMaterial3D).transparency
		return t == BaseMaterial3D.TRANSPARENCY_DISABLED or t == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or t == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
		var code := (mat as ShaderMaterial).shader.code
		if "ALPHA" in code or "blend_" in code or "depth_draw_never" in code or "#include" in code:
			return false
		if mat.has_meta("per_instance"):
			return true
		code = code.replace("MODEL_MATRIX * vec4(VERTEX, 1.0)", "").replace("MODEL_MATRIX * vec4(NORMAL, 0.0)", "")
		return not ("MODEL_MATRIX" in code or "INSTANCE" in code or "NODE_POSITION" in code or "MODELVIEW" in code)
	return false

func _mm(mesh: Mesh, xforms: Array, cast: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level.add_child(mmi)
	return mmi

var _built_world := -1

func _build_level() -> void:
	level = Node3D.new()
	add_child(level)
	_built_world = Data.world
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	if Data.world_id() != "n7":
		# autre monde : son décor fournit build(v, rng), lights(v), env(v) (scripts/decor/<id>_world.gd)
		var wd: GDScript = load("res://scripts/decor/%s_world.gd" % Data.world_id())
		wd.build(self, rng)
		for p in arena.pads:
			_build_pad(p3(p))
		_flush_batch()
		wd.lights(self)
		wd.env(self)
		return
	HangarShell.build(self, rng)
	# sas d'apparition
	for p in arena.pads:
		_build_pad(p3(p))
	HangarProps.build(self, rng)
	HangarBay.build(self, rng)
	_flush_batch()
	HangarShell.lights(self)

## Monde choisi au Relais : reconstruit le décor et l'ambiance s'il a changé (après arena.set_world()).
func set_world() -> void:
	if _built_world == Data.world and level != null:
		return
	if level != null:
		level.queue_free()
		remove_child(level)
	pads3d.clear()
	_batch.clear()
	_env_defaults()
	_build_level()

func _build_pad(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	level.add_child(root)
	var base := Models.cyl(0.95, 1.0, 0.08, Models.toon(Color("#1B2440"), 0.2), 24)
	base.position.y = 0.04
	root.add_child(base)
	var ring := Models.torus(0.72, 0.82, Models.glow_mat(CYAN, 2.0), 32)
	ring.position.y = 0.09
	root.add_child(ring)
	var inner := Models.torus(0.35, 0.4, Models.glow_mat(CYAN, 1.2), 24)
	inner.position.y = 0.09
	root.add_child(inner)
	var glow := _ground_quad(2.6, CYAN, 0.0)
	glow.position.y = 0.1
	root.add_child(glow)
	pads3d.append({"root": root, "ring": ring, "glow": glow})

func _ground_quad(size: float, col: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = Models.radial()
	m.albedo_color = Color(col.r * 1.3, col.g * 1.3, col.b * 1.3, alpha)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Caisse de fret (aussi utilisée au Relais) : déléguée au décor du hangar.
func _crate(base: Vector3, size: Vector3, rot: float, rng: RandomNumberGenerator) -> void:
	HangarProps.crate(self, base, size, rot, rng)

# ---------------------------------------------------------------- héroïne
func _build_hero() -> void:
	hero_root = Node3D.new()
	add_child(hero_root)
	hero = Rig3D.new()
	hero_root.add_child(hero)
	hero.setup(JO_MODEL, Color(1, 1, 1), 1.7)
	# en jeu : liseré turquoise propre à Jo (la détache de la mêlée), voile rouge quand elle est touchée
	hero.make_hero(Color(0.5, 1.0, 0.94), 0.007, Color(1.0, 0.22, 0.28))
	hero.scale = Vector3.ONE * Dev.get_f("hero_scale")
	# lumière d'appoint côté caméra, qui n'éclaire que Jo (calque HERO_LAYER) : on voit surtout son dos et le
	# soleil l'éclaire de l'autre côté ; sans elle, Jo paraît éteinte
	var key := OmniLight3D.new()
	key.position = Vector3(0.0, 2.4, 1.8)
	key.omni_range = 4.5
	key.omni_attenuation = 0.6
	key.light_energy = 1.0
	key.light_color = Color(1.0, 0.97, 0.94)
	key.light_cull_mask = Rig3D.HERO_LAYER
	key.shadow_enabled = false
	hero_root.add_child(key)
	hero_root.add_child(Models.shadow_blob(1.1))
	hero2d.damaged.connect(func():
		hero.hit()
		hero.flash(0.22))
	arena.room_cleared.connect(hero.cheer)
	# poussière de pas, traînée des réacteurs
	var jfx: Node3D = load("res://scripts/jo_fx.gd").new()
	hero_root.add_child(jfx)
	jfx.setup(hero)
	# anneau au sol : net, avec crans et flèche de visée ; testé en profondeur (les pieds passent devant),
	# doublé d'un anneau discret visible à travers le décor
	var ring := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.9, 1.9)
	ring.mesh = pm
	var rm := ShaderMaterial.new()
	rm.shader = load("res://shaders/hero_ring.gdshader")
	rm.set_shader_parameter("color", CYAN)
	rm.set_shader_parameter("accent", ORANGE)
	rm.render_priority = 5
	ring.material_override = rm
	ring.position.y = 0.035
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hero_root.add_child(ring)
	hero_ring = ring
	var ghost := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(1.33, 1.33)
	ghost.mesh = gm
	var gmat := ShaderMaterial.new()
	gmat.shader = _ring_shader
	gmat.set_shader_parameter("color", Color(CYAN, 0.55))
	gmat.set_shader_parameter("width", 0.1)
	gmat.set_shader_parameter("fill", 0.0)
	gmat.render_priority = 4
	ghost.material_override = gmat
	ghost.position.y = 0.03
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.add_child(ghost)
	# ligne de visée (s'affiche quand le stick droit est poussé)
	aim_line = MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(0.22, 1.0)
	aim_line.mesh = q
	aim_mat = StandardMaterial3D.new()
	aim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aim_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	aim_mat.albedo_texture = Models.beam()
	aim_mat.albedo_color = Color(1.0, 0.55, 0.3, 0.32)
	aim_line.material_override = aim_mat
	aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hero_root.add_child(aim_line)
	# bulle de bouclier
	hero_shield = Models.sphere(0.62, Models.add_mat(Color(CYAN, 0.18), 1.0))
	hero_shield.position.y = 0.5
	hero_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hero_root.add_child(hero_shield)
	hero_light = OmniLight3D.new()
	hero_light.omni_range = 3.5
	hero_light.light_energy = 0.0
	hero_light.light_color = Color(1.0, 0.7, 0.4)
	hero_root.add_child(hero_light)

# ---------------------------------------------------------------- réserves (projectiles, halos, particules, chiffres)
func _billboard_mm(max_count: int, energy: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = max_count
	mm.visible_instance_count = 0
	var m := ShaderMaterial.new()
	m.shader = _glow_shader
	m.set_shader_parameter("tex", Models.radial())
	m.set_shader_parameter("energy", energy)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 200.0
	add_child(mmi)
	return mmi

const Fx3D = preload("res://scripts/fx/fx3d.gd")
var fxs: Fx3D  # réserves d'effets (scripts/fx/fx3d.gd)
const PowerFx = preload("res://scripts/fx/power_fx.gd")
var pfx: PowerFx  # rendu des pouvoirs de Jo (scripts/fx/power_fx.gd)
var _last_hit := {}  # id d'instance de l'ennemi -> [direction du dernier coup (Vector3), heure]
var _shells: Array = []  # obus du mortier en vol : [point d'arrivée (Vector2), heure d'arrivée]
var _fx_room := -1
var _fx_el := 0.0
var _markers: Array = []  # nœuds recyclés : zones d'impact du mortier
var _lobs: Array = []  # nœuds recyclés : obus en vol
var _shocks: Array = []  # nœuds recyclés : ondes de choc

func _build_pools() -> void:
	fxs = Fx3D.new()
	add_child(fxs)
	fxs.setup(self)
	pfx = PowerFx.new()
	add_child(pfx)
	pfx.setup(self, arena, hero2d)
	arena.shield_blocked.connect(_on_shield_blocked)
	arena.wave_changed.connect(_on_wave)
	arena.energy_full.connect(_on_energy_full)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cap := CapsuleMesh.new()
	cap.radius = 0.5
	cap.height = 3.0
	cap.radial_segments = 8
	cap.rings = 2
	mm.mesh = cap
	mm.instance_count = 400
	mm.visible_instance_count = 0
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/bolt.gdshader")
	bolt_mm = MultiMeshInstance3D.new()
	bolt_mm.multimesh = mm
	bolt_mm.material_override = bm
	bolt_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt_mm.extra_cull_margin = 200.0
	add_child(bolt_mm)
	halo_mm = _billboard_mm(400, 1.3)
	# tickets : mêmes maillages et matériaux que les anciens nœuds (pièce et trou projettent leur ombre)
	var coin := Models.cyl(0.13, 0.13, 0.04, Models.glow_mat(GOLD, 1.6), 16)
	var hole := Models.cyl(0.06, 0.06, 0.05, Models.toon(Color("#B07A20"), 0.0), 12)
	var blob := Models.shadow_blob(0.35)
	for mi in [coin, hole, blob]:
		var tm := MultiMesh.new()
		tm.transform_format = MultiMesh.TRANSFORM_3D
		tm.mesh = (mi as MeshInstance3D).mesh
		tm.instance_count = 128
		tm.visible_instance_count = 0
		var tmi := MultiMeshInstance3D.new()
		tmi.multimesh = tm
		tmi.material_override = (mi as MeshInstance3D).material_override
		tmi.cast_shadow = (mi as MeshInstance3D).cast_shadow
		add_child(tmi)
		_tk_mm.append(tm)
		(mi as Node).free()
	for i in range(32):
		var l := Label3D.new()
		l.font = _font
		l.font_size = 64
		l.pixel_size = 0.005
		l.outline_size = 18
		l.outline_modulate = Color(0.05, 0.05, 0.12, 0.95)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.visible = false
		l.render_priority = 10
		l.outline_render_priority = 9
		add_child(l)
		_dmg_labels.append({"node": l, "t": 0.0, "life": 0.0, "vel": Vector3.ZERO, "id": 0, "sum": 0.0, "crit": false, "pop": 1.0, "base": Vector3.ZERO})

# ---------------------------------------------------------------- partie
func start_room() -> void:
	active = true
	visible = true
	if relais != null:
		relais.visible = false
	level.visible = true
	hero_root.visible = true
	_clear_dynamic()
	var hp: Vector3 = p3(hero2d.position)
	cam_target = hp
	_place_camera(1.0)

func stop() -> void:
	active = false
	_clear_dynamic()

func _clear_dynamic() -> void:
	for k in mobs.keys():
		(mobs[k] as Node).queue_free()
	mobs.clear()
	for m in dying:
		(m as Node).queue_free()
	dying.clear()
	for f in fx:
		(f["node"] as Node).queue_free()
	fx.clear()
	for k in pickup_nodes.keys():
		(pickup_nodes[k] as Node).queue_free()
	pickup_nodes.clear()
	tickets.clear()
	for tm in _tk_mm:
		(tm as MultiMesh).visible_instance_count = 0
	for n in turret_nodes:
		(n as Node).queue_free()
	turret_nodes.clear()
	for n in ally_nodes:
		(n as Node).queue_free()
	ally_nodes.clear()
	if chest_node != null:
		chest_node.queue_free()
		chest_node = null
	for n in door_nodes:
		(n as Node).queue_free()
	door_nodes.clear()
	bolt_mm.multimesh.visible_instance_count = 0
	halo_mm.multimesh.visible_instance_count = 0
	for d in _dmg_labels:
		(d["node"] as Label3D).visible = false

func _process(dt: float) -> void:
	t += dt
	if _stop_until > 0 and Time.get_ticks_msec() >= _stop_until:
		Engine.time_scale = 1.0
		_stop_until = 0
	if not active or arena == null:
		_tick_relais(dt)
		return
	_sync_hero(dt)
	_sync_mobs(dt)
	_sync_bullets()
	_sync_pickups(dt)
	_sync_chest(dt)
	_sync_turrets(dt)
	pfx.tick(dt)
	_tick_fx(dt)
	_tick_labels(dt)
	_tick_pads(dt)
	_tick_doors()
	_place_camera(dt)

var boss_cam := 0.0  # > 0 : la caméra regarde le boss qui arrive

func _place_camera(dt: float) -> void:
	var hp := p3(hero2d.position)
	var look := Vector3.ZERO
	if joy != null and joy.aim_active:
		look = Vector3(joy.aim.x, 0, joy.aim.y) * 1.2
	var target := hp + look
	if boss_cam > 0.0:
		boss_cam -= dt
		if arena.boss != null:
			target = target.lerp(p3(arena.boss.position), clampf(boss_cam / 0.6, 0.0, 1.0) * 0.85)
	if not door_nodes.is_empty():
		# portails ouverts : la caméra se cale à mi-chemin entre Jo et les portails, panneaux compris
		var c := Vector3.ZERO
		for n in door_nodes:
			c += (n as Node3D).position
		c /= door_nodes.size()
		target = target.lerp(c + Vector3(0, 0, -0.6), 0.55)
	var W: float = arena.W * K
	var H: float = arena.H * K
	target.x = clampf(target.x, 6.5, W - 6.5)
	target.z = clampf(target.z, 2.6, H - 3.2)
	cam_target = cam_target.lerp(target, clampf(dt * 6.0, 0.0, 1.0))
	var pitch := deg_to_rad(Dev.get_f("cam_pitch"))
	var off := Vector3(0, sin(pitch), cos(pitch)) * Dev.get_f("cam_dist")
	cam.fov = Dev.get_f("cam_fov")
	var hs := Vector3.ONE * Dev.get_f("hero_scale")
	if hero.scale != hs:  # réglage du mode développeur : ne pas invalider tout le modèle à chaque image
		hero.scale = hs
	var sh := Vector3.ZERO
	if shake > 0.0:
		shake = maxf(0.0, shake - dt * 2.5)
		var a := shake * shake * 0.35
		sh = Vector3(randf_range(-a, a), randf_range(-a, a), randf_range(-a, a))
	cam.position = cam_target + off + sh
	cam.look_at(cam_target + sh * 0.5, Vector3.UP)
	cam.make_current()

## Réglage changé (menu pause, mode développeur) : appliqué tout de suite, même en pause.
func refresh_cam() -> void:
	if active:
		_place_camera(1.0)

## Arrêt sur image : le temps ralentit un instant (durée en secondes réelles).
var _stop_until := 0
func hit_stop(real_s: float, scale: float) -> void:
	# captures (--write-movie) : pas de ralenti à l'horloge réelle, les images restent reproductibles
	# (les options du moteur comme --fixed-fps ne figurent pas dans get_cmdline_args)
	if Engine.get_write_movie_path() != "" or "--fixed-fps" in OS.get_cmdline_user_args():
		return
	Engine.time_scale = scale
	_stop_until = Time.get_ticks_msec() + int(real_s * 1000.0)

func add_shake(v: float) -> void:
	shake = minf(1.0, shake + v)

func _sync_hero(dt: float) -> void:
	hero_root.position = p3(hero2d.position)
	var aim: Vector2 = hero2d.aim_dir
	var target_yaw := atan2(aim.x, aim.y)
	hero.rotation.y = lerp_angle(hero.rotation.y, target_yaw, clampf(dt * 16.0, 0.0, 1.0))
	var moving: bool = hero2d.moving
	var shooting: bool = joy != null and joy.aim_active
	var spd: float = 0.0
	var mv := Vector3.ZERO
	if moving:
		var md: Vector2 = hero2d.move_dir
		spd = 0.55 + 0.35 * md.length()
		mv = Vector3(md.x, 0, md.y).limit_length(1.0)
	hero.set_motion(spd, 1.0 if shooting else 0.0)
	hero.set_move(mv)
	# invulnérable : voile pulsé (Jo reste visible dans la mêlée)
	hero.invuln = hero2d.invuln
	if hero2d.dead and not hero.dead:
		hero.die()
	elif not hero2d.dead and hero.dead:
		_rebuild_hero_anim()
	aim_line.visible = shooting
	if shooting:
		var len: float = hero2d.rng * K * 0.9
		var ad := Vector3(aim.x, 0, aim.y).normalized()
		aim_line.position = ad * (len * 0.5 + 0.4) + Vector3(0, 0.04, 0)
		aim_line.rotation = Vector3(0, atan2(ad.x, ad.z), 0)
		aim_line.scale = Vector3(1, 1, len)
	hero_shield.visible = hero2d.shield_max > 0 and hero2d.shield_ready
	if hero_shield.visible:
		hero_shield.scale = Vector3.ONE * (1.0 + sin(t * 4.0) * 0.03)
	hero_light.light_energy = maxf(0.0, hero_light.light_energy - dt * 30.0)
	hero_light.visible = hero_light.light_energy > 0.0
	# anneau : doré et pulsé quand l'énergie est pleine
	var full: bool = arena.energy >= arena.energy_need
	var rmat: ShaderMaterial = hero_ring.material_override
	rmat.set_shader_parameter("color", GOLD.lerp(Color.WHITE, 0.3 + 0.3 * sin(t * 10.0)) if full else CYAN)
	rmat.set_shader_parameter("aim", hero.rotation.y)
	rmat.set_shader_parameter("spin", t * (2.4 if moving else 0.8))
	hero_ring.scale = Vector3.ONE * ((1.12 + 0.06 * sin(t * 10.0)) if full else 1.0)

func set_hero_items(items: Array) -> void:
	hero.apply_items(items)
	if relais != null:
		var rh: Rig3D = relais.get_meta("hero")
		rh.apply_items(items)

func _rebuild_hero_anim() -> void:
	hero.revive()

func _sync_mobs(dt: float) -> void:
	var seen := {}
	for e in arena.enemies:
		var id: int = e.get_instance_id()
		seen[id] = true
		var m: Mob3D = mobs.get(id)
		if m == null:
			m = _make_mob(e)
		m.sync(e, dt)
	for id in mobs.keys():
		if not seen.has(id):
			(mobs[id] as Node).queue_free()
			mobs.erase(id)
	var i := 0
	while i < dying.size():
		var dm: Mob3D = dying[i]
		if dm.tick_death(dt):
			dm.queue_free()
			dying.remove_at(i)
		else:
			i += 1

func _make_mob(e: Node2D) -> Mob3D:
	var m := Mob3D.new()
	add_child(m)
	m.setup(e.kind, e.elite, e.radius)
	m.position = p3(e.position)
	mobs[e.get_instance_id()] = m
	return m

func _sync_bullets() -> void:
	var mm := bolt_mm.multimesh
	var hm := halo_mm.multimesh
	var n := mini(arena.bullets.size(), mm.instance_count)
	fxs.trail_begin()
	for i in range(n):
		var b = arena.bullets[i]  # objet léger (scripts/bullet.gd), pas un nœud
		var v: Vector2 = b.vel
		var r: float = b.radius * K
		var c: Color = b.color
		var v3 := Vector3(v.x, 0.0, v.y) * K
		# capsule couchée dans l'axe du tir : rotation (cap) × bascule de 90° × échelle, écrite directement
		# (sans atan2 ni produits de bases : trois fois moins de calcul par tir, même transformation)
		var l := v.length()
		var dx := v.x / l if l > 0.0 else 0.0
		var dz := v.y / l if l > 0.0 else 1.0
		if b.hero_shot:
			# trait de Jo : capsule fine, halo discret, longue traînée (plus longue si le tir transperce)
			var pos := Vector3(b.position.x * K, 0.55, b.position.y * K)
			var sx := r * 1.7
			var sy := r * 2.3
			mm.set_instance_transform(i, Transform3D(Vector3(dz * sx, 0.0, -dx * sx), Vector3(dx * sy, 0.0, dz * sy), Vector3(0.0, -sx, 0.0), pos))
			mm.set_instance_color(i, c)
			var hs := r * 6.5
			hm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(hs, hs, hs)), pos))
			hm.set_instance_color(i, Color(c, 0.4))
			fxs.trail_add(pos, v3, c, r * 2.4, 0.075 if b.pierce == 0 else 0.12, Color(c.r * 0.5, c.g * 0.6, c.b, 1.0))
		else:
			# tir ennemi : orbe plus rond et plus gros, halo large qui palpite, traînée courte,
			# pour rester lisible au milieu des effets
			var pos := Vector3(b.position.x * K, 0.6, b.position.y * K)
			var pulse := 1.0 + 0.18 * sin(t * 28.0 + float(i))
			var sx := r * 2.5
			var sy := r * 1.15
			mm.set_instance_transform(i, Transform3D(Vector3(dz * sx, 0.0, -dx * sx), Vector3(dx * sy, 0.0, dz * sy), Vector3(0.0, -sx, 0.0), pos))
			mm.set_instance_color(i, c)
			var hs := r * 11.0 * pulse
			hm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(hs, hs, hs)), pos))
			hm.set_instance_color(i, Color(c, 0.8))
			fxs.trail_add(pos, v3, c, r * 2.6, 0.05)
	mm.visible_instance_count = n
	hm.visible_instance_count = n

func _sync_pickups(dt: float) -> void:
	var seen := {}
	_tk_n = 0
	var cap: int = (_tk_mm[0] as MultiMesh).instance_count
	if arena.pickups.size() > cap:
		while cap < arena.pickups.size():
			cap *= 2
		for tm in _tk_mm:
			(tm as MultiMesh).instance_count = cap
	for pk in arena.pickups:
		var k: int = int(pk.get("vid", 0))
		if k == 0:
			k = randi() + 1
			pk["vid"] = k
		seen[k] = true
		var np := p3(pk["pos"], 0.0)
		if String(pk["kind"]) == "ticket":
			_sync_ticket(pk, k, np, dt)
			continue
		var n: Node3D = pickup_nodes.get(k)
		if n == null:
			n = _make_pickup(pk)
			n.position = np
			pickup_nodes[k] = n
		var spin: Node3D = n.get_child(0)
		spin.rotation.y += dt * 3.0
		# petit bond en sortant de l'ennemi, puis flottement
		var pt: float = pk["t"]
		var hop := sin(pt / 0.45 * PI) * 0.8 if pt < 0.45 else 0.0
		spin.position.y = 0.35 + hop + sin(t * 4.0 + float(k % 100)) * 0.06
		# traînée quand il file vers Jo
		if dt > 0.0:
			var vel := (np - n.position) / dt
			if vel.length() > 3.5 and pt > 0.1:
				fxs.trail_add(np + Vector3(0, spin.position.y, 0), vel, n.get_meta("col"), 0.2, 0.07)
		n.position = np
	for k in pickup_nodes.keys():
		if not seen.has(k):
			var gone: Node3D = pickup_nodes[k]
			# ramassé par Jo (et non effacé par un changement de salle) : « pop » sur elle
			if gone.position.distance_to(p3(hero2d.position)) < 1.5:
				fxs.pickup_pop(p3(hero2d.position, 0.75), gone.get_meta("col"), gone.get_meta("kind") != "ticket")
			gone.queue_free()
			pickup_nodes.erase(k)
	for k in tickets.keys():
		if not seen.has(k):
			var gp: Vector3 = tickets[k][0]
			if gp.distance_to(p3(hero2d.position)) < 1.5:
				fxs.pickup_pop(p3(hero2d.position, 0.75), GOLD, false)
			tickets.erase(k)
	for tm in _tk_mm:
		(tm as MultiMesh).visible_instance_count = _tk_n

var _tk_n := 0  # tickets écrits dans les MultiMesh à cette image
const TK_TILT := Basis(Vector3.RIGHT, PI * 0.5)  # pièce posée sur la tranche

## Ticket : même mouvement que les autres ramassages (rotation, bond, flottement, traînée vers Jo).
func _sync_ticket(pk: Dictionary, k: int, np: Vector3, dt: float) -> void:
	var st: Array = tickets.get(k, [])
	if st.is_empty():
		st = [np, 0.0]
		tickets[k] = st
	var rot: float = st[1] + dt * 3.0
	st[1] = rot
	var pt: float = pk["t"]
	var hop := sin(pt / 0.45 * PI) * 0.8 if pt < 0.45 else 0.0
	var sy := 0.35 + hop + sin(t * 4.0 + float(k % 100)) * 0.06
	if dt > 0.0:
		var vel := (np - (st[0] as Vector3)) / dt
		if vel.length() > 3.5 and pt > 0.1:
			fxs.trail_add(np + Vector3(0, sy, 0), vel, GOLD, 0.2, 0.07)
	st[0] = np
	var coin: MultiMesh = _tk_mm[0]
	var xf := Transform3D(Basis(Vector3.UP, rot) * TK_TILT, np + Vector3(0, sy, 0))
	coin.set_instance_transform(_tk_n, xf)
	(_tk_mm[1] as MultiMesh).set_instance_transform(_tk_n, xf)
	(_tk_mm[2] as MultiMesh).set_instance_transform(_tk_n, Transform3D(Basis(), np + Vector3(0, 0.02, 0)))
	_tk_n += 1

func _make_pickup(pk: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var spin := Node3D.new()
	root.add_child(spin)
	root.set_meta("kind", String(pk["kind"]))
	root.set_meta("col", GOLD)
	match String(pk["kind"]):  # les tickets passent par _sync_ticket
		"hp":
			root.set_meta("col", RED)
			var box := Models.box(Vector3(0.32, 0.24, 0.32), Models.toon(Color("#F4F1EA"), 0.5))
			spin.add_child(box)
			var c1 := Models.box(Vector3(0.22, 0.26, 0.07), Models.glow_mat(RED, 2.0))
			spin.add_child(c1)
			var c2 := Models.box(Vector3(0.07, 0.26, 0.22), Models.glow_mat(RED, 2.0))
			spin.add_child(c2)
			root.add_child(Models.shadow_blob(0.5))
		"item":
			var col: Color = Data.RARITY_COLORS[int(pk["item"]["rarity"])]
			root.set_meta("col", col)
			var gem := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.2
			sm.height = 0.55
			sm.radial_segments = 4
			sm.rings = 2
			gem.mesh = sm
			gem.material_override = Models.glow_mat(col, 1.8)
			spin.add_child(gem)
			var beam := _beam(col, 3.2, 0.32)
			root.add_child(beam)
			var g := _ground_quad(1.6, col, 0.7)
			g.position.y = 0.04
			root.add_child(g)
	return root

func _beam(col: Color, h: float, r: float) -> MeshInstance3D:
	var mi := Models.cyl(r * 0.6, r, h, null, 16)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = Models.beam()
	m.albedo_color = Color(col.r * 1.2, col.g * 1.2, col.b * 1.2, 0.55)
	m.uv1_scale = Vector3(1, -1, 1)
	m.uv1_offset = Vector3(0, 1, 0)
	mi.material_override = m
	mi.position.y = h * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _make_chest() -> Node3D:
	var n := Node3D.new()
	var body := Node3D.new()
	n.add_child(body)
	var navy := Models.toon(Color("#1F2A52"), 0.4)
	var gold := Models.toon(Color("#FFB347"), 0.5, Color("#FFB347"), 0.4)
	var base := Models.box(Vector3(1.0, 0.5, 0.7), navy)
	base.position.y = 0.25
	body.add_child(base)
	for x in [-0.42, 0.42]:
		var band := Models.box(Vector3(0.1, 0.52, 0.72), gold)
		band.position = Vector3(x, 0.26, 0)
		body.add_child(band)
	var seam := Models.box(Vector3(1.02, 0.05, 0.72), Models.glow_mat(Color("#FFD98A"), 3.0))
	seam.position.y = 0.5
	body.add_child(seam)
	var hinge := Node3D.new()
	hinge.position = Vector3(0, 0.5, -0.35)
	body.add_child(hinge)
	var lid := Models.box(Vector3(1.02, 0.22, 0.72), navy)
	lid.position = Vector3(0, 0.11, 0.35)
	hinge.add_child(lid)
	var lid_band := Models.box(Vector3(0.12, 0.24, 0.74), gold)
	lid_band.position = Vector3(0, 0.11, 0.35)
	hinge.add_child(lid_band)
	var lock := Models.box(Vector3(0.2, 0.2, 0.06), Models.glow_mat(Color("#FFB347"), 2.4))
	lock.position = Vector3(0, 0.04, 0.72)
	hinge.add_child(lock)
	n.set_meta("body", body)
	n.set_meta("hinge", hinge)
	return n

func _sync_chest(dt: float) -> void:
	if arena.chest.is_empty():
		if chest_node != null:
			chest_node.queue_free()
			chest_node = null
		return
	if chest_node == null:
		chest_node = Node3D.new()
		add_child(chest_node)
		var crate := _make_chest()
		chest_node.add_child(crate)
		chest_node.set_meta("crate", crate)
		chest_beam = _beam(GOLD, 4.0, 0.5)
		chest_node.add_child(chest_beam)
		var g := _ground_quad(2.4, GOLD, 0.8)
		g.position.y = 0.04
		chest_node.add_child(g)
		chest_node.set_meta("glow", g)
		chest_node.add_child(Models.shadow_blob(1.4))
		chest_node.scale = Vector3.ONE * 0.01
		_spawn_ring(p3(arena.chest["pos"], 0.05), GOLD, 3.0, 0.5)
		_spawn_column(p3(arena.chest["pos"]), GOLD, 5.0, 0.5)
	chest_node.position = p3(arena.chest["pos"])
	var opened: bool = arena.chest["open"]
	chest_node.scale = chest_node.scale.lerp(Vector3.ONE, clampf(dt * 8.0, 0.0, 1.0))
	var crate: Node3D = chest_node.get_meta("crate")
	var hinge: Node3D = crate.get_meta("hinge")
	var body: Node3D = crate.get_meta("body")
	if not opened:
		body.position.y = absf(sin(t * 3.0)) * 0.08
		crate.rotation.y = sin(t * 1.5) * 0.15
	else:
		hinge.rotation.x = lerpf(hinge.rotation.x, -1.9, clampf(dt * 10.0, 0.0, 1.0))
		body.position.y = lerpf(body.position.y, 0.0, clampf(dt * 10.0, 0.0, 1.0))
	chest_beam.visible = not opened
	(chest_node.get_meta("glow") as Node3D).visible = not opened

func _sync_turrets(dt: float) -> void:
	while turret_nodes.size() < arena.turrets.size():
		var n := Node3D.new()
		var tm := Models.inst(SP + "turret_single.glb", true)
		Models.tint_node(tm, 0.7)
		tm.scale = Vector3.ONE * 1.1
		n.add_child(tm)
		n.add_child(Models.shadow_blob(1.0))
		var ring := _ground_quad(1.4, GOLD, 0.5)
		ring.position.y = 0.03
		n.add_child(ring)
		add_child(n)
		turret_nodes.append(n)
		n.scale = Vector3.ONE * 0.01
		_spawn_ring(p3(arena.turrets[turret_nodes.size() - 1]["pos"], 0.05), GOLD, 2.0, 0.4)
	for i in range(arena.turrets.size()):
		var tr: Dictionary = arena.turrets[i]
		var n: Node3D = turret_nodes[i]
		n.position = p3(tr["pos"])
		n.scale = n.scale.lerp(Vector3.ONE, clampf(dt * 10.0, 0.0, 1.0))
		var ang: float = tr["ang"]
		(n.get_child(0) as Node3D).rotation.y = lerp_angle((n.get_child(0) as Node3D).rotation.y, atan2(cos(ang), sin(ang)) + PI, clampf(dt * 12.0, 0.0, 1.0))
	while ally_nodes.size() < arena.allies.size():
		var d := Node3D.new()
		var core := Models.sphere(0.16, Models.toon(Color("#F4F1EA"), 0.5))
		d.add_child(core)
		var eye := Models.sphere(0.07, Models.glow_mat(CYAN, 3.0))
		eye.position = Vector3(0, 0, 0.13)
		d.add_child(eye)
		var ring := Models.torus(0.18, 0.22, Models.glow_mat(CYAN, 1.8))
		d.add_child(ring)
		add_child(d)
		ally_nodes.append(d)
	for i in range(arena.allies.size()):
		var al: Dictionary = arena.allies[i]
		var p: Vector2 = hero2d.position + Vector2.RIGHT.rotated(al["ang"]) * 74.0
		var d: Node3D = ally_nodes[i]
		d.position = p3(p, 1.0 + sin(t * 4.0 + i) * 0.08)
		d.rotation.y = hero.rotation.y

func _tick_pads(dt: float) -> void:
	var spawning: bool = not arena.spawn_queue.is_empty()
	for pd in pads3d:
		var g: MeshInstance3D = pd["glow"]
		var m: StandardMaterial3D = g.material_override
		var target := 0.55 + 0.3 * sin(t * 8.0) if spawning else 0.12
		m.albedo_color.a = lerpf(m.albedo_color.a, target, clampf(dt * 5.0, 0.0, 1.0))
		(pd["ring"] as Node3D).rotation.y += dt * (3.0 if spawning else 0.6)

# ---------------------------------------------------------------- effets
## Éclair de lumière : prend la lumière la plus éteinte des trois (une plus forte en cours est gardée).
func _flash_light(pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var l: OmniLight3D = _flash_lights[0]
	for o in _flash_lights:
		if (o as OmniLight3D).light_energy < l.light_energy:
			l = o
	if l.light_energy > energy:
		return
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.visible = true

func _add_fx(node: Node3D, life: float, kind: String, extra: Dictionary = {}) -> void:
	if node.get_parent() == null:
		add_child(node)
	var d := {"node": node, "t": 0.0, "life": life, "kind": kind}
	d.merge(extra)
	fx.append(d)

## Nœud recyclé libre dans `arr` (ou neuf, fait par `maker`) ; les nœuds libérés par _clear_dynamic sont oubliés.
func _take(arr: Array, maker: Callable) -> Node3D:
	var i := 0
	while i < arr.size():
		if not is_instance_valid(arr[i]) or (arr[i] as Node).is_queued_for_deletion():
			arr.remove_at(i)
			continue
		if not (arr[i] as Node3D).visible:
			(arr[i] as Node3D).visible = true
			return arr[i]
		i += 1
	var n: Node3D = maker.call()
	add_child(n)
	arr.append(n)
	return n

## Onde au sol, éclair, débris, colonne : passent par les réserves MultiMesh de fxs (aucun nœud créé).
func _spawn_ring(pos: Vector3, col: Color, size: float, life: float, width: float = 0.1) -> void:
	fxs.wave(pos, Vector3.UP, col, size * 0.2, size, life, width)

func _spawn_flash(pos: Vector3, col: Color, size: float, life: float) -> void:
	fxs.flash(pos, col, size, life)

func _spawn_debris(pos: Vector3, col: Color, n: int, spd: float) -> void:
	fxs.chunks(pos + Vector3(0, 0.4, 0), [col], n, spd)

func _spawn_column(pos: Vector3, col: Color, h: float, life: float) -> void:
	fxs.column(pos, col, h, life)

func _tick_fx(dt: float) -> void:
	# changement de salle, ou nouvelle partie (le chrono de l'arène repart de zéro) : les effets en cours
	# disparaissent ; une pause (écran de choix) ne touche à rien
	if arena.room != _fx_room or arena.elapsed < _fx_el:
		fxs.clear()
		_shells.clear()
		_last_hit.clear()
	_fx_room = arena.room
	_fx_el = arena.elapsed
	fxs.tick(dt)
	fxs.tick_dying(dying)
	fxs.trail_end()
	var i := 0
	while i < fx.size():
		var f: Dictionary = fx[i]
		f["t"] += dt
		var p: float = f["t"] / f["life"]
		var node: Node3D = f["node"]
		if not is_instance_valid(node):
			fx.remove_at(i)
			continue
		if p >= 1.0:
			if f.get("pooled", false):
				node.visible = false
			else:
				node.queue_free()
			fx.remove_at(i)
			continue
		match String(f["kind"]):
			"shock":
				# onde de choc : rayon linéaire, exactement celui de la simulation (le front qui blesse)
				var sz: float = f["max"] * p
				node.scale = Vector3(sz, 1, sz)
				var smat: ShaderMaterial = (node as MeshInstance3D).material_override
				smat.set_shader_parameter("energy", 2.4 * (1.0 - p * 0.6))
			"marker":
				var mat: ShaderMaterial = (node as MeshInstance3D).material_override
				mat.set_shader_parameter("progress", p)
				mat.set_shader_parameter("energy", 1.4 + 1.6 * p * absf(sin(f["t"] * (8.0 + 22.0 * p))))
			"lob":
				var a: Vector3 = f["from"]
				var b: Vector3 = f["to"]
				node.position = a.lerp(b, p) + Vector3(0, f["h"] * 4.0 * p * (1.0 - p), 0)
				node.rotation.x += dt * 9.0
				# traînée de l'obus : lueur verte et fumée claire
				fxs.flash(node.position, Color("#9BE15D"), 0.45, 0.22)
				if int(f["t"] * 60.0) % 3 == 0:
					fxs.smoke_puffs(node.position, 0.25, 1, 0.5, 0.0, Color(0.6, 0.7, 0.55), Color(0.4, 0.42, 0.5), 0.5, 0.2)
		i += 1
	# éteinte (énergie nulle) : masquée, elle sort des listes de lumières des objets (moins de calcul par pixel)
	for l in _flash_lights:
		var ol: OmniLight3D = l
		ol.light_energy = maxf(0.0, ol.light_energy - dt * 16.0)
		ol.visible = ol.light_energy > 0.0

## Chiffre de dégâts : jaillit en rebondissant ; les coups rapprochés sur un même ennemi s'additionnent
## dans le même chiffre (moins de fouillis) ; un critique sort en gros, doré, avec « ! ».
func _damage_number(pos: Vector3, dmg: float, crit: bool, id: int = 0) -> void:
	var best: Dictionary = {}
	if id != 0:
		for d in _dmg_labels:
			if int(d["id"]) == id and (d["node"] as Label3D).visible and bool(d["crit"]) == crit and float(d["t"]) < 0.35:
				best = d
				break
	var l: Label3D
	if best.is_empty():
		best = _dmg_labels[0]
		for d in _dmg_labels:
			if not (d["node"] as Label3D).visible:
				best = d
				break
			if float(d["t"]) / float(d["life"]) > float(best["t"]) / float(best["life"]):
				best = d
		l = best["node"]
		best["sum"] = 0.0
		best["id"] = id
		best["crit"] = crit
		l.position = pos + Vector3(randf_range(-0.4, 0.4), 1.2 + (0.25 if crit else 0.0), randf_range(-0.15, 0.15))
		best["vel"] = Vector3(randf_range(-0.7, 0.7), 2.8 if not crit else 3.2, 0)
		l.visible = true
	else:
		l = best["node"]
		best["vel"] = Vector3((best["vel"] as Vector3).x * 0.5, 1.4, 0)
	best["sum"] = float(best["sum"]) + dmg
	var v := int(round(float(best["sum"])))
	best["t"] = 0.0
	if crit:
		l.text = "%d!" % v
		l.modulate = Color("#FFD24A")
		l.outline_modulate = Color(0.42, 0.1, 0.0, 1.0)
		l.font_size = 108
		best["life"] = 0.95
		best["pop"] = 1.9
	else:
		l.text = str(v)
		l.modulate = Color.WHITE if v < 40 else Color("#FFF2C8")
		l.outline_modulate = Color(0.05, 0.05, 0.14, 0.95)
		l.font_size = 58 + mini(v / 10, 4) * 6
		best["life"] = 0.72
		best["pop"] = 1.55

func _tick_labels(dt: float) -> void:
	for d in _dmg_labels:
		var l: Label3D = d["node"]
		if not l.visible:
			continue
		d["t"] += dt
		var tt: float = d["t"]
		var p: float = tt / d["life"]
		if p >= 1.0:
			l.visible = false
			d["id"] = 0
			continue
		var v: Vector3 = d["vel"]
		v.y -= 7.5 * dt
		v.x *= 1.0 - dt * 3.0
		d["vel"] = v
		l.position += v * dt
		# rebond d'échelle : jaillit au-delà de sa taille, ressort amorti, puis rétrécit en s'effaçant
		var pop: float = d["pop"]
		var s := 1.0
		if tt < 0.05:
			s = lerpf(0.35, pop, tt / 0.05)
		else:
			var u := tt - 0.05
			s = 1.0 + (pop - 1.0) * exp(-u * 16.0) * cos(u * 34.0)
		var a := 1.0
		if p > 0.7:
			var q := (p - 0.7) / 0.3
			a = 1.0 - q * q
			s *= 1.0 - q * 0.35
		l.scale = Vector3.ONE * s
		l.modulate.a = a
		l.outline_modulate.a = 0.95 * a

# ---------------------------------------------------------------- événements de la simulation
func _on_fired(pos: Vector2, vel: Vector2, hero_shot: bool, color: Color, radius: float) -> void:
	if not active:
		return
	var d := Vector3(vel.x, 0.0, vel.y).normalized()
	if hero_shot and (pos - hero2d.position).length() < 60.0:
		hero_light.light_energy = 2.4
		hero_light.visible = true
		fxs.muzzle(hero.muzzle_position(), d, color, radius > 6.0)
	else:
		fxs.enemy_muzzle(p3(pos, 0.55 if hero_shot else 0.6), d, color)

func _on_enemy_hit(e: Node2D, pos: Vector2, dmg: float, crit: bool) -> void:
	if not active:
		return
	var id: int = e.get_instance_id()
	var m: Mob3D = mobs.get(id)
	if m != null:
		m.flash()
		if m.rig != null:
			m.rig.flash(0.05)  # éclat blanc bref : le modèle reste lisible sous un feu nourri
	var n := Vector3(pos.x - e.position.x, 0.0, pos.y - e.position.y).normalized()
	_last_hit[id] = -n
	fxs.hit(p3(pos, 0.6), n, CYAN, crit)
	_damage_number(p3(e.position), dmg, crit, id)
	if crit:
		add_shake(0.06)

var _shield_pos := Vector2(-1, -1)

func _on_blocked(pos: Vector2, color: Color) -> void:
	if not active or pos == _shield_pos:
		return
	fxs.wall_hit(p3(pos, 0.55), color)

## Tir de Jo arrêté par le bouclier d'un Rempart : onde hexagonale et ricochet (pas de chiffre de dégâts).
func _on_shield_blocked(e: Node2D, pos: Vector2, vel: Vector2) -> void:
	if not active:
		return
	_shield_pos = pos
	var f: Vector2 = e.facing
	var nrm := Vector3(f.x, 0.0, f.y).normalized()
	fxs.shield_block(p3(pos, 0.62), nrm, Vector3(vel.x, 0.0, vel.y) * K)
	_flash_light(p3(pos, 0.9), Color(1.0, 0.7, 0.3), 0.8, 2.5)

func _on_enemy_killed(e: Node2D) -> void:
	if not active:
		return
	var id: int = e.get_instance_id()
	var m: Mob3D = mobs.get(id)
	var pos := p3(e.position)
	var big: bool = e.kind == "brute" or e.kind == "bouncer" or e.kind.begins_with("boss") or e.elite
	var dir: Vector3 = _last_hit.get(id, Vector3.ZERO)
	_last_hit.erase(id)
	if m != null:
		mobs.erase(id)
		m.death_dir = dir
		m.start_death()
		dying.append(m)
	fxs.death("boss" if e.kind.begins_with("boss") else e.kind, pos, dir, e.elite)
	var acc: Color = Fx3D.ACCENT.get(e.kind, RED)
	if not e.kind.begins_with("boss"):
		_flash_light(pos + Vector3(0, 1.0, 0), acc.lerp(Color(1.0, 0.7, 0.4), 0.5), 4.0 if big else 2.0, 6.0 if big else 4.0)
	match e.kind:
		"brute":
			add_shake(0.7)
			hit_stop(0.09, 0.2)
		"boss", "boss2":
			add_shake(0.6)
			hit_stop(0.12, 0.3)
		"bomber":
			pass  # secousse donnée par l'explosion
		_:
			add_shake(0.5 if e.elite else 0.2)
			if e.elite:
				hit_stop(0.07, 0.25)
	# pouvoirs (Détonation, etc.) : rendus par pfx (scripts/fx/power_fx.gd)

## Explosion (pétard, obus du mortier) : boule de feu dodue, onde au sol de la taille du rayon de dégâts,
## fumée, brûlure ; l'obus du mortier laisse un cratère qui fume.
func _on_exploded(pos: Vector2, radius: float, col: Color) -> void:
	if not active:
		return
	var p := p3(pos)
	var rr := radius * K
	var shell := false
	for i in range(_shells.size()):
		if (_shells[i][0] as Vector2).distance_to(pos) < 3.0:
			_shells.remove_at(i)
			shell = true
			break
	if shell:
		fxs.crater(p, rr)
		_flash_light(p + Vector3(0, 1.0, 0), Color("#C8F07A"), 3.5, rr * 4.0)
		add_shake(0.3)
	else:
		fxs.explosion(p, rr * 0.95, col, rr > 1.2)
		_flash_light(p + Vector3(0, 1.0, 0), Color(1.0, 0.65, 0.3), 5.0, rr * 5.0)
		add_shake(0.55)
		hit_stop(0.05, 0.3)

## Onde de choc du videur ou du boss : anneau au sol qui s'élargit à la vitesse réelle de la simulation.
func _on_shockwave(pos: Vector2, max_r: float, spd: float, col: Color) -> void:
	if not active:
		return
	var mi := _take(_shocks, func() -> Node3D:
		var n := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.0, 1.0)
		n.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = _ring_shader
		m.set_shader_parameter("width", 0.07)
		m.set_shader_parameter("fill", 0.06)
		m.set_shader_parameter("progress", 1.0)
		n.material_override = m
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return n) as MeshInstance3D
	(mi.material_override as ShaderMaterial).set_shader_parameter("color", col)
	mi.position = p3(pos, 0.05)
	mi.scale = Vector3(0.01, 1, 0.01)
	_add_fx(mi, max_r / spd, "shock", {"max": max_r * 2.0 * K, "pooled": true})
	fxs.flash(p3(pos, 0.3), col, 2.2, 0.2)
	_flash_light(p3(pos, 1.0), col, 3.0, 6.0)
	add_shake(0.5)

## Obus du mortier : zone d'impact annoncée au sol (se remplit jusqu'à l'impact) et obus en cloche.
func _on_shell(from: Vector2, to: Vector2, flight: float, radius: float) -> void:
	if not active:
		return
	_shells.append([to, fxs.now + flight])
	var mi := _take(_markers, func() -> Node3D:
		var n := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1, 1)
		n.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = _ring_shader
		m.set_shader_parameter("color", RED)
		m.set_shader_parameter("width", 0.1)
		m.set_shader_parameter("fill", 0.3)
		n.material_override = m
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return n) as MeshInstance3D
	(mi.material_override as ShaderMaterial).set_shader_parameter("progress", 0.0)
	mi.scale = Vector3.ONE * radius * 2.0 * K
	mi.position = p3(to, 0.04)
	_add_fx(mi, flight, "marker", {"pooled": true})
	var ball: Node3D = _take(_lobs, func() -> Node3D:
		var b := Models.sphere(0.16, Models.glow_mat(Color("#9BE15D"), 2.2))
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return b)
	var a := p3(from, 1.1)
	ball.position = a
	_add_fx(ball, flight, "lob", {"from": a, "to": p3(to, 0.1), "h": 2.6 + (to - from).length() * K * 0.25, "pooled": true})
	fxs.enemy_muzzle(a, Vector3.UP, Color("#9BE15D"))

## Portails de fin de salle : plantés dans l'arène là où la simulation les a placés.
func _on_doors_opened() -> void:
	if not active:
		return
	for n in door_nodes:
		(n as Node).queue_free()
	door_nodes.clear()
	var i := 0
	for d in arena.doors:
		var n := Door3D.new()
		n.position = p3(d["pos"])
		add_child(n)
		n.setup(d, 0.15 * i)
		door_nodes.append(n)
		_spawn_column(n.position, d["col"], 5.0, 0.6)
		_spawn_ring(n.position + Vector3(0, 0.05, 0), d["col"], 4.0, 0.5)
		i += 1
	add_shake(0.25)

func _tick_doors() -> void:
	if door_nodes.is_empty():
		return
	var hp := p3(hero2d.position)
	for n in door_nodes:
		(n as Door3D).set_hero_distance((n as Node3D).position.distance_to(hp))

## Jo entre dans un portail : il s'emballe et l'aspire, les autres se referment.
func door_enter(d: Dictionary) -> void:
	var at := p3(d["pos"])
	for n in door_nodes:
		var dn: Door3D = n
		if dn.position.distance_to(at) < 0.1:
			dn.enter()
		else:
			dn.entering = 0.0
	_spawn_flash(at + Vector3(0, 1.4, 0), d["col"], 3.0, 0.35)
	_spawn_column(at, d["col"], 7.0, 0.5)
	_flash_light(at + Vector3(0, 1.5, 0), d["col"], 4.0, 6.0)
	add_shake(0.35)

func _on_enemy_spawned(e: Node2D) -> void:
	if not active:
		return
	var pos := p3(e.position)
	var boss: bool = e.kind.begins_with("boss")
	fxs.spawn_in(pos, MAGENTA if boss else CYAN, boss)
	if boss:
		add_shake(0.8)
		boss_cam = 2.0
		_flash_light(pos + Vector3(0, 2.0, 0), MAGENTA, 5.0, 10.0)

## Début de vague : tous les sas s'allument en cascade, une lumière sur le plus proche de Jo.
func _on_wave() -> void:
	if not active:
		return
	var pts: Array = []
	var near := Vector3.ZERO
	var best := INF
	var hp := p3(hero2d.position)
	for pd in arena.pads:
		var q := p3(pd)
		pts.append(q)
		if q.distance_to(hp) < best:
			best = q.distance_to(hp)
			near = q
	var col := MAGENTA if arena.room >= Data.ROOMS else CYAN
	fxs.wave_start(pts, col)
	if not pts.is_empty():
		_flash_light(near + Vector3(0, 1.5, 0), col, 3.0, 7.0)

## Énergie pleine : l'écran de choix fige le jeu dans la même image ; l'éclat est déjà « en cours » (vieilli).
func _on_energy_full() -> void:
	if not active:
		return
	var p := p3(hero2d.position)
	fxs.power_burst(p, CYAN, Color(0.75, 1.0, 1.0), 0.12)
	_flash_light(p + Vector3(0, 1.2, 0), CYAN, 3.5, 6.0)

func _on_chest_opened(pos: Vector2) -> void:
	if not active:
		return
	var p := p3(pos)
	_spawn_column(p, GOLD, 6.0, 0.7)
	_spawn_ring(p + Vector3(0, 0.05, 0), GOLD, 4.0, 0.5)
	_spawn_flash(p + Vector3(0, 0.7, 0), GOLD, 2.0, 0.25)
	fxs.chest_burst(p)
	_flash_light(p + Vector3(0, 1.2, 0), GOLD, 3.0, 6.0)
	add_shake(0.25)

## Pouvoir choisi : colonne, anneaux, gerbe autour de Jo, bref ralenti.
func power_fx() -> void:
	var p := p3(hero2d.position)
	fxs.power_burst(p, ORANGE, GOLD)
	_flash_light(p + Vector3(0, 1.2, 0), ORANGE, 3.5, 6.0)
	add_shake(0.3)
	hit_stop(0.3, 0.35)

func _on_hero_damaged() -> void:
	if not active:
		return
	hero.flash(0.12)
	add_shake(0.4)
	fxs.hero_hit(p3(hero2d.position))
	_flash_light(p3(hero2d.position, 1.0), RED, 2.5, 4.0)
	hit_stop(0.06, 0.3)

# ---------------------------------------------------------------- Relais (base)
func show_relais(items: Array) -> void:
	active = false
	_clear_dynamic()
	visible = true
	level.visible = false
	hero_root.visible = false
	if relais == null:
		_build_relais()
	relais.visible = true
	var rh: Rig3D = relais.get_meta("hero")
	rh.set_motion(0.0, 0.0)
	rh.apply_items(items)
	rh.position = Vector3(0, 0, 0.6)
	rh.visible = true
	relais_focus = 0.0
	launch_t = -1.0

func _build_relais() -> void:
	relais = preload("res://scripts/decor/relais.gd").build(self)

var relais_focus := 0.0  # 0 : vue large du Relais, 1 : gros plan sur Jo (Loge)
var _focus := 0.0

## Éclats du Cœur récupérés : allume les socles correspondants.
func set_shards(n: int) -> void:
	if relais == null:
		_build_relais()
	preload("res://scripts/decor/relais.gd").set_shards(relais, n)

var launch_t := -1.0  # >= 0 : départ en cours (Jo court dans le portail)

## Départ : Jo se tourne, court vers le portail, la caméra plonge dedans ; `done` est appelé à la fin.
func launch(done: Callable) -> void:
	launch_t = 0.0
	_launch_done = done
	relais_focus = 0.0

var _launch_done: Callable

func _tick_relais(dt: float) -> void:
	if relais == null or not relais.visible:
		return
	preload("res://scripts/decor/relais.gd").tick(relais, dt, launch_t >= 0.0, _focus)
	var rh: Rig3D = relais.get_meta("hero")
	if launch_t >= 0.0:
		launch_t += dt
		rh.rotation.y = lerp_angle(rh.rotation.y, PI, clampf(dt * 10.0, 0.0, 1.0))
		rh.set_motion(1.0, 0.0)
		rh.position = rh.position.move_toward(Vector3(0, 0, -2.0), dt * 3.2)
		if rh.position.z < -1.6:
			rh.visible = false
		var k := clampf(launch_t / 1.2, 0.0, 1.0)
		var base := relais.position
		var from := base + Vector3(3.2, 3.4, 9.5)
		var to := base + Vector3(0, 2.6, 1.0)
		cam.position = from.lerp(to, k * k)
		cam.look_at(base + Vector3(3.4, 1.6, 0).lerp(Vector3(0, 2.6, -2.2), k), Vector3.UP)
		cam.make_current()
		if launch_t >= 1.25 and _launch_done.is_valid():
			var cb := _launch_done
			_launch_done = Callable()
			launch_t = -1.0
			cb.call()
		return
	cam.fov = CAM_FOV  # le réglage de champ ne vaut qu'en partie
	_focus = lerpf(_focus, relais_focus, clampf(dt * 4.0, 0.0, 1.0))
	rh.rotation.y = lerpf(0.35, 0.35 + sin(t * 0.6) * 0.5, _focus)
	var base := relais.position
	var a := sin(t * 0.25) * 0.08 * (1.0 - _focus)
	var wide_pos := base + Vector3(sin(a) * 9.5 + 3.2, 3.4, cos(a) * 9.5)
	var wide_look := base + Vector3(3.4, 1.6, 0)
	var close_pos := base + Vector3(1.5, 2.7, 7.8)
	var close_look := base + Vector3(2.55, 1.3, 0.6)
	cam.position = wide_pos.lerp(close_pos, _focus)
	cam.look_at(wide_look.lerp(close_look, _focus), Vector3.UP)
	cam.make_current()
