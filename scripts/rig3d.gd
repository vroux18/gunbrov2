extends Node3D
## Personnage sculpté (tools/sculpt.py) animé en code : pièces séparées (torse, tête, bras, jambes, arme)
## articulées à leurs pivots. Marche, course, visée à deux mains, recul, respiration, coup reçu, chute.
## Couleurs par sommet ; les pièces « *_glow » sont lumineuses.

const Models = preload("res://scripts/models.gd")

var model: Node3D
var parts := {}  # nom -> Node3D
var rest := {}  # nom -> Transform3D
var meshes: Array = []
var speed := 0.0
var shooting := 0.0
var dead := false
var phase := 0.0
var t := 0.0
var recoil := 0.0
var _flash_t := 0.0
var _flash_mat: StandardMaterial3D
var _die_t := 0.0
var walk_amp := 1.0  # amplitude de la foulée (les lourds marchent plus raide)
var glow_color := Color(1, 1, 1)
## Pour les mobs : état de l'IA (« move », « aim », « tell », « charge », « ring ») et temps passé dedans.
var state := "move"
var state_t := 0.0
var elite := false

static var _body_mats := {}
static var _glow_mats := {}
static var _char_shader: Shader = null
static var _outline_mat: ShaderMaterial = null
## Contour des personnages (coque inversée) : une passe de plus par pièce ; « --no-outline » le coupe.
static var outline_enabled := not ("--no-outline" in OS.get_cmdline_user_args())

## Matériau des pièces sculptées : shaders/character.gdshader (rampe douce, liseré, reflet net) et
## son contour en deuxième passe. Paramètres : « tint » (couleur multipliée), « heat » (lueur ajoutée).
static func body_mat(tint: Color) -> ShaderMaterial:
	var key := tint.to_html()
	if _body_mats.has(key):
		return _body_mats[key]
	if _char_shader == null:
		_char_shader = load("res://shaders/character.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _char_shader
	m.set_shader_parameter("tint", tint)
	if outline_enabled:
		if _outline_mat == null:
			_outline_mat = ShaderMaterial.new()
			_outline_mat.shader = load("res://shaders/character_outline.gdshader")
		m.next_pass = _outline_mat
	_body_mats[key] = m
	return m

static func glow_mat(energy: float) -> StandardMaterial3D:
	var key := "%.2f" % energy
	if _glow_mats.has(key):
		return _glow_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(energy, energy, energy)
	_glow_mats[key] = m
	return m

func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	model = Models.scene(path).instantiate()
	add_child(model)
	for n in model.find_children("*", "Node3D", true, false):
		var nd: Node3D = n
		parts[String(nd.name)] = nd
		rest[String(nd.name)] = nd.transform
	for mi in Models.meshes(model):
		var m: MeshInstance3D = mi
		var nm := String(m.name) + String(m.get_parent().name)
		m.material_override = glow_mat(glow_energy) if "_glow" in nm else body_mat(tint)
	meshes = Models.meshes(model)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1, 1, 1, 0)

## Lumière teintée (équipement : couleur de rareté) — les pièces lumineuses de l'équipement sont blanches.
static func tint_glow_mat(col: Color, energy: float) -> StandardMaterial3D:
	var key := col.to_html() + "%.2f" % energy
	if _glow_mats.has(key):
		return _glow_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(col.r * energy, col.g * energy, col.b * energy)
	_glow_mats[key] = m
	return m

# ---------------------------------------------------------------- équipement (Jo)
const RARITY_GLOW := [Color("#9FB3C8"), Color("#3CF2D8"), Color("#C77DFF"), Color("#FFB347")]
## Bout du canon dans le repère de la part « gun », selon l'arme portée.
const MUZZLE := {"": Vector3(0, -0.2, 0.06), "blaster_garde": Vector3(0, -0.26, 0.06), "fusil_impulsion": Vector3(0, -0.3, 0.056)}
var _gear: Array = []
var _gun_id := ""
var _gun_meshes := {}  # MeshInstance3D -> Mesh d'origine (blaster de base)

## Équipe les objets {id, rarity} : chaque objet est un GLB sculpté (tools/chars/gear.py) dont les parts
## « cible__id » se rangent dans la part cible de Jo. Une arme remplace le blaster de base.
func apply_items(items: Array) -> void:
	for g in _gear:
		if is_instance_valid(g):
			(g as Node).get_parent().remove_child(g)
			(g as Node).queue_free()
	_gear.clear()
	var gun_id := ""
	for it in items:
		var id := String(it["id"])
		var path := "res://assets/chars3d/gear_%s.glb" % id
		if not ResourceLoader.exists(path):
			continue
		var glow: Color = RARITY_GLOW[clampi(int(it["rarity"]), 0, 3)]
		var inst: Node3D = Models.scene(path).instantiate()
		for n in inst.find_children("*__*", "Node3D", true, false):
			var nd: Node3D = n
			var target := p(String(nd.name).get_slice("__", 0))
			if target == null:
				continue
			nd.get_parent().remove_child(nd)
			nd.owner = null
			target.add_child(nd)
			nd.transform = Transform3D.IDENTITY
			_gear.append(nd)
			for mi in Models.meshes(nd):
				(mi as MeshInstance3D).material_override = tint_glow_mat(glow, 1.5) if "_glow" in String(mi.name) + String(mi.get_parent().name) else body_mat(Color(1, 1, 1))
		inst.queue_free()
		if id in MUZZLE:
			gun_id = id
	# arme de base masquée quand une arme est équipée
	if _gun_meshes.is_empty():
		for nm in ["gun", "gun_glow"]:
			var gn := p(nm)
			if gn is MeshInstance3D:
				_gun_meshes[gn] = (gn as MeshInstance3D).mesh
	for mi in _gun_meshes:
		(mi as MeshInstance3D).mesh = _gun_meshes[mi] if gun_id == "" else null
	_gun_id = gun_id
	meshes = Models.meshes(model)

func p(name: String) -> Node3D:
	return parts.get(name)

func set_motion(spd: float, shoot_amount: float) -> void:
	speed = lerpf(speed, spd, 0.2)
	shooting = lerpf(shooting, shoot_amount, 0.35)

func fire() -> void:
	recoil = 1.0

func flash(dur: float = 0.09) -> void:
	_flash_t = dur
	for mi in meshes:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = _flash_mat

func die() -> void:
	dead = true
	_die_t = 0.0

func revive() -> void:
	dead = false
	_die_t = 0.0
	model.rotation = Vector3.ZERO
	model.position = Vector3.ZERO
	for nm in rest:
		(parts[nm] as Node3D).transform = rest[nm]

func muzzle_position() -> Vector3:
	var g := p("gun")
	if g == null:
		return global_position + Vector3(0, 0.5, 0)
	return g.global_transform * (MUZZLE[_gun_id] as Vector3)

func _pose(name: String, rot: Vector3, off: Vector3 = Vector3.ZERO) -> void:
	var n := p(name)
	if n == null:
		return
	var r: Transform3D = rest[name]
	n.transform = Transform3D(r.basis * Basis.from_euler(rot), r.origin + off)

func _process(dt: float) -> void:
	t += dt
	if _flash_t > 0.0:
		_flash_t -= dt
		_flash_mat.albedo_color = Color(1.6, 1.6, 1.6, clampf(_flash_t * 10.0, 0.0, 0.85))
		if _flash_t <= 0.0:
			for mi in meshes:
				if is_instance_valid(mi):
					(mi as MeshInstance3D).material_overlay = null
	if dead:
		_die_t += dt
		animate_death(_die_t)
		return
	recoil = maxf(0.0, recoil - dt * 9.0)
	animate(dt)

## Chute par défaut : bascule en arrière, bras levés. Les sous-classes peuvent la remplacer.
func animate_death(dt_total: float) -> void:
	var k := clampf(dt_total / 0.45, 0.0, 1.0)
	model.rotation.x = lerpf(0.0, -1.45, k * k)
	model.position.y = lerpf(0.0, 0.08, k)
	_pose("arm_r", Vector3(-2.6 * k, 0, 0.4 * k))
	_pose("arm_l", Vector3(-2.6 * k, 0, -0.4 * k))

## Animation bipède par défaut (Jo, Garde). Les mobs non humanoïdes la remplacent.
func animate(dt: float) -> void:
	phase += dt * (6.0 + 6.0 * speed) * clampf(speed * 2.0, 0.0, 1.0)
	var s := sin(phase)
	var c := cos(phase)
	var amp := clampf(speed * 1.4, 0.0, 1.0) * walk_amp
	var breathe := sin(t * 2.4) * 0.012 * (1.0 - amp)
	# jambes
	_pose("leg_r", Vector3(s * 0.75 * amp, 0, 0))
	_pose("leg_l", Vector3(-s * 0.75 * amp, 0, 0))
	# torse : rebond, roulis et torsion de la marche, respiration au repos, penché en course
	var bob := absf(c) * 0.035 * amp
	_pose("torso", Vector3(0.18 * speed * speed, s * 0.12 * amp * (1.0 - shooting * 0.7), c * 0.04 * amp), Vector3(0, bob + breathe, 0))
	# tête : compense la torsion, petit hochement
	_pose("head", Vector3(-c * 0.05 * amp - 0.1 * speed * speed, -s * 0.1 * amp, 0))
	# bras : balancier en marche, visée à deux mains quand on tire
	var aim_r := Vector3(-PI * 0.5 + recoil * 0.35, 0, 0.05)
	var aim_l := Vector3(-PI * 0.44, -0.55, -0.35)
	var swing_r := Vector3(-s * 0.7 * amp, 0, 0.08)
	var swing_l := Vector3(s * 0.7 * amp, 0, -0.08)
	_pose("arm_r", swing_r.lerp(aim_r, shooting))
	_pose("arm_l", swing_l.lerp(aim_l, shooting))
