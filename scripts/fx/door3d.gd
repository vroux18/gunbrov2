extends Node3D
## Portail de fin de salle, planté dans l'arène : socle, anneau incliné vers la caméra, tourbillon à la couleur
## de la route, panneau holographique (titre et promesse), étincelles qui montent. Apparaît en rebondissant,
## grossit et s'emballe quand Jo approche, aspire Jo quand elle entre.

const Models = preload("res://scripts/models.gd")

var col := Color("#3CF2D8")
var t := 0.0
var delay := 0.0
var near := 0.0  # 0..1 : proximité de Jo
var entering := -1.0  # >= 0 : Jo vient d'entrer
var _frame: Node3D
var _spin: Node3D
var _disk_mat: ShaderMaterial
var _sign: Node3D
var _pool: MeshInstance3D
var _pool_mat: StandardMaterial3D

static var _font: Font = null
static var _font2: Font = null

func setup(d: Dictionary, stagger: float) -> void:
	col = d["col"]
	delay = stagger
	if _font == null:
		_font = load("res://assets/fonts/RussoOne-Regular.ttf")
		_font2 = load("res://assets/fonts/Rajdhani-Bold.ttf")
	var dark := Color("#1C2238")
	var steel := Color("#C8CEDC")
	# socle : galette sombre, liseré lumineux, flaque de lumière
	var base := Models.cyl(1.05, 1.18, 0.16, Models.toon(dark, 0.3), 40)
	base.position.y = 0.08
	add_child(base)
	var lip := Models.torus(1.0, 1.08, Models.glow_mat(col, 2.0), 48)
	lip.position.y = 0.17
	add_child(lip)
	_pool = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4.2, 4.2)
	_pool.mesh = pm
	_pool_mat = StandardMaterial3D.new()
	_pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pool_mat.albedo_texture = Models.radial()
	_pool_mat.albedo_color = Color(col.r, col.g, col.b, 0.5)
	_pool.material_override = _pool_mat
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pool.position.y = 0.03
	add_child(_pool)
	# cadre : anneau debout, penché vers la caméra pour se lire de haut
	_frame = Node3D.new()
	_frame.position = Vector3(0, 1.45, 0)
	_frame.rotation.x = -0.42
	add_child(_frame)
	var ring := Models.torus(1.08, 1.3, Models.toon(steel, 0.5), 56)
	ring.rotation.x = PI * 0.5
	_frame.add_child(ring)
	var inner := Models.torus(1.0, 1.1, Models.glow_mat(col, 2.6), 56)
	inner.rotation.x = PI * 0.5
	_frame.add_child(inner)
	# montants qui tiennent l'anneau au socle
	for sx in [-1.0, 1.0]:
		var leg := Models.box(Vector3(0.2, 0.9, 0.28), Models.toon(dark, 0.3))
		leg.position = Vector3(sx * 1.05, 0.55, 0.0)
		leg.rotation.z = -sx * 0.25
		add_child(leg)
	# couronne de plots qui tourne
	_spin = Node3D.new()
	_frame.add_child(_spin)
	for i in range(10):
		var a := TAU * i / 10.0
		var stud := Models.box(Vector3(0.16, 0.3, 0.3), Models.toon(dark, 0.3))
		stud.position = Vector3(cos(a), sin(a), 0) * 1.22
		stud.rotation.z = a
		_spin.add_child(stud)
		var led := Models.box(Vector3(0.06, 0.12, 0.32), Models.glow_mat(col if i % 2 == 0 else Color(1, 1, 1), 2.6))
		led.position = Vector3(cos(a), sin(a), 0) * 1.22
		led.rotation.z = a
		_spin.add_child(led)
	# tourbillon
	var disk := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.1, 2.1)
	disk.mesh = q
	_disk_mat = ShaderMaterial.new()
	_disk_mat.shader = load("res://shaders/portal.gdshader")
	_disk_mat.set_shader_parameter("col_a", col)
	_disk_mat.set_shader_parameter("col_b", col.darkened(0.55).lerp(Color("#5A2FB0"), 0.4))
	_disk_mat.set_shader_parameter("energy", 1.5)
	disk.material_override = _disk_mat
	disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_frame.add_child(disk)
	# panneau holographique devant le portail, côté caméra : toujours lisible, jamais sous le HUD
	_sign = Node3D.new()
	_sign.position = Vector3(0, 0.45, 1.55)
	add_child(_sign)
	var title := _label(String(d["title"]), _font, 120, Color(1, 1, 1), col, 0.0)
	_sign.add_child(title)
	var desc := _label(String(d["desc"]), _font2, 60, col.lightened(0.45), Color(0.04, 0.06, 0.12, 1), -0.4)
	_sign.add_child(desc)
	# étincelles qui montent
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_radius = 1.0
	p.emission_ring_inner_radius = 0.7
	p.emission_ring_height = 0.05
	p.emission_ring_axis = Vector3.UP
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.1
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = Models.glow_mat(col, 3.0)
	p.mesh = sm
	p.position.y = 0.2
	add_child(p)
	scale = Vector3.ONE * 0.001

func _label(text: String, font: Font, size: int, c: Color, outline: Color, y: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.outline_size = 22 if size > 80 else 14
	l.modulate = c
	l.outline_modulate = outline.darkened(0.55)
	l.pixel_size = 0.0045
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.position.y = y
	l.render_priority = 10
	l.outline_render_priority = 9
	return l

## Distance de Jo (en mètres) : le portail grossit et s'emballe quand elle approche.
func set_hero_distance(d: float) -> void:
	near = clampf(1.0 - (d - 1.2) / 3.0, 0.0, 1.0)

func enter() -> void:
	entering = 0.0

func _process(dt: float) -> void:
	t += dt
	var appear := clampf((t - delay) / 0.55, 0.0, 1.0)
	# apparition en rebond (easeOutBack)
	var c1 := 1.70158
	var e := 1.0 + (c1 + 1.0) * pow(appear - 1.0, 3.0) + c1 * pow(appear - 1.0, 2.0)
	var s := maxf(0.001, e) * (1.0 + 0.1 * near)
	if entering >= 0.0:
		entering += dt
		s *= 1.0 + 0.5 * sin(minf(entering / 0.5, 1.0) * PI) - minf(entering / 0.5, 1.0) * 0.4
	scale = Vector3.ONE * s
	_spin.rotation.z += dt * (0.8 + 3.5 * near + (8.0 if entering >= 0.0 else 0.0))
	_disk_mat.set_shader_parameter("energy", 1.4 + 1.2 * near + (2.0 if entering >= 0.0 else 0.0) + 0.15 * sin(t * 4.0))
	_sign.position.y = 0.45 + sin(t * 2.2) * 0.04
	_pool_mat.albedo_color.a = 0.35 + 0.35 * near + 0.08 * sin(t * 3.0)
