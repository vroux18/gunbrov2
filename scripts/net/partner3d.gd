extends Node3D
## Mode duo : rendu 3D de la Jo du partenaire (même modèle sculpté que Jo, posé dans la vue 3D de view3d.gd),
## son anneau au sol, son nom au-dessus de la tête, et le cercle de relève quand elle est à terre.
## Suit un héros 2D (hero.gd) dont la position vient du réseau (ou de la simulation chez l'hôte).
## La Jo de l'invité porte une autre palette (jo2.gdshader) sur les deux écrans, pour qu'on se reconnaisse.

const Rig3D = preload("res://scripts/rig3d.gd")
const Models = preload("res://scripts/models.gd")
const JO_MODEL := "res://assets/chars3d/jo.glb"
const K := 1.0 / 64.0
const JO2_COL := Color("#B36BFF")  # violet de la Jo de l'invité
const JO1_COL := Color("#3CF2D8")

var view: Node3D
var hero2d: Node2D
var rig: Rig3D
var ring: MeshInstance3D
var revive_ring: MeshInstance3D
var label: Label3D
var col := JO1_COL
var revive := 0.0  # progression de la relève (0..1), posée par la session duo
var shooting := false
var _t := 0.0
var _mesh_n := 0
var _jo2 := false

static var _jo2_mat: ShaderMaterial = null

## `jo2` : palette de l'invité. `name` : affiché au-dessus de la tête. `marker_only` : pas de modèle (la Jo
## locale est déjà rendue par view3d.gd), seulement le cercle de relève et le message quand elle est à terre.
var marker_only := false
func setup(view_node: Node3D, h: Node2D, jo2: bool, name_text: String, only_marker: bool = false) -> void:
	view = view_node
	hero2d = h
	_jo2 = jo2
	marker_only = only_marker
	col = JO2_COL if jo2 else JO1_COL
	var shader: Shader = load("res://shaders/ground_ring.gdshader")
	if not marker_only:
		rig = Rig3D.new()
		add_child(rig)
		rig.setup(JO_MODEL, Color(1, 1, 1), 1.7)
		rig.make_hero(col.lightened(0.3), 0.009, Color(1.0, 0.22, 0.28))
		if jo2:
			recolor(rig)
		add_child(Models.shadow_blob(1.1))
		ring = _ring(shader, 1.5, col, 0.12, 0.0)
	revive_ring = _ring(shader, 2.9, Color(1.0, 0.85, 0.3, 0.9), 0.07, 0.35)
	revive_ring.visible = false
	label = Label3D.new()
	label.text = name_text
	label.font = load("res://assets/fonts/RussoOne-Regular.ttf")
	label.font_size = 56
	label.outline_size = 12
	label.modulate = col.lightened(0.35)
	label.outline_modulate = Color(0.03, 0.05, 0.1, 0.95)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.006
	label.position = Vector3(0, 1.95, 0)
	label.render_priority = 10
	add_child(label)
	visible = false

func _ring(shader: Shader, size: float, c: Color, width: float, fill: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("fill", fill)
	m.render_priority = 4
	mi.material_override = m
	mi.position.y = 0.04
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

## Palette de la Jo de l'invité, sur toutes les masses du modèle (équipement compris), lumières exceptées.
static func recolor(r: Rig3D) -> int:
	if _jo2_mat == null:
		_jo2_mat = ShaderMaterial.new()
		_jo2_mat.shader = load("res://scripts/net/jo2.gdshader")
		var ol := StandardMaterial3D.new()
		ol.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ol.cull_mode = BaseMaterial3D.CULL_FRONT
		ol.grow = true
		ol.grow_amount = 0.009
		ol.albedo_color = JO2_COL.lightened(0.25)
		ol.disable_receive_shadows = true
		_jo2_mat.next_pass = ol
	var n := 0
	for mi in Models.meshes(r.model):
		var m: MeshInstance3D = mi
		if not ("_glow" in String(m.name) + String(m.get_parent().name)):
			m.material_override = _jo2_mat
			n += 1
	return n

func _process(dt: float) -> void:
	_t += dt
	if view == null or hero2d == null or not is_instance_valid(hero2d):
		visible = false
		return
	visible = bool(view.active)
	if not visible:
		return
	position = Vector3(hero2d.position.x * K, 0.0, hero2d.position.y * K)
	if marker_only:
		_sync_marker()
		return
	var aim: Vector2 = hero2d.aim_dir
	rig.rotation.y = lerp_angle(rig.rotation.y, atan2(aim.x, aim.y), clampf(dt * 14.0, 0.0, 1.0))
	var mv := Vector3.ZERO
	var spd := 0.0
	if hero2d.moving:
		var md: Vector2 = hero2d.move_dir
		spd = 0.55 + 0.35 * md.length()
		mv = Vector3(md.x, 0, md.y).limit_length(1.0)
	rig.set_motion(spd, 1.0 if shooting else 0.0)
	rig.set_move(mv)
	rig.invuln = hero2d.invuln
	if hero2d.dead and not rig.dead:
		rig.die()
	elif not hero2d.dead and rig.dead:
		rig.revive()
	# équipement changé : la palette suit
	if _jo2:
		var n: int = rig.meshes.size()  # tenu à jour par apply_items (pas de parcours de l'arbre à chaque image)
		if n != _mesh_n:
			_mesh_n = n
			recolor(rig)
	ring.visible = not hero2d.dead
	_sync_marker()

func _sync_marker() -> void:
	if marker_only:
		label.visible = hero2d.dead
	else:
		(ring.material_override as ShaderMaterial).set_shader_parameter("color", Color(col, 0.75 + 0.25 * sin(_t * 4.0)))
	revive_ring.visible = hero2d.dead
	if hero2d.dead:
		var m: ShaderMaterial = revive_ring.material_override
		m.set_shader_parameter("progress", clampf(revive, 0.0, 1.0))
		m.set_shader_parameter("fill", 0.45 if revive > 0.0 else 0.12)
		revive_ring.scale = Vector3.ONE * (1.0 + 0.04 * sin(_t * 6.0))
	label.position.y = 0.6 if hero2d.dead else 1.95

func set_text(t: String) -> void:
	if label != null:
		label.text = t
