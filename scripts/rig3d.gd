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

static func body_mat(tint: Color) -> StandardMaterial3D:
	var key := tint.to_html()
	if _body_mats.has(key):
		return _body_mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = tint
	m.roughness = 0.62
	m.metallic_specular = 0.35
	m.rim_enabled = true
	m.rim = 0.45
	m.rim_tint = 0.35
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

func muzzle_position() -> Vector3:
	var g := p("gun_glow")
	if g == null:
		g = p("gun")
	if g == null:
		return global_position + Vector3(0, 0.5, 0)
	return g.global_transform * Vector3(0, -0.2, 0.06)

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
