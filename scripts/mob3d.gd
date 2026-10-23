extends Node3D
## Visuel 3D d'un ennemi, synchronisé sur l'ennemi simulé (enemy.gd).
## Sentinelle : drone flottant à œil rouge. Garde : soldat (Mini Character teinté) casqué à visière rouge.
## Colosse : marcheur blindé à bras-marteaux. Le Portique : mécha quadrupède surmonté d'une tourelle double.

const Models = preload("res://scripts/models.gd")
const Actor3D = preload("res://scripts/actor3d.gd")

const METAL := Color("#2C3350")
const METAL_D := Color("#1C2238")
const PLATE := Color("#9AA4B6")
const PLATE_D := Color("#66708A")
const RED := Color("#FF4D6D")
const MAGENTA := Color("#F23CB8")
const GOLD := Color("#FFB347")
const ORANGE := Color("#FF7A2F")

const K := 1.0 / 64.0
const VIS := 1.35  # les visuels débordent un peu de la hitbox : plus lisibles sur téléphone

var kind := "drone"
var elite := false
var body: Node3D  # partie qui tourne vers la cible
var actor: Actor3D = null
var parts := {}
var t := 0.0
var _flash_t := 0.0
var _flash_mat: StandardMaterial3D
var _meshes: Array = []
var _elite_ring: MeshInstance3D = null
var _tell: MeshInstance3D = null
var _tell_mat: ShaderMaterial = null
var yaw := 0.0
var dying := 0.0  # > 0 : animation de mort en cours
var ground_y := 0.0

static var _ring_shader: Shader = null

func setup(k: String, is_elite: bool, radius_px: float) -> void:
	kind = k
	elite = is_elite
	body = Node3D.new()
	add_child(body)
	var r := radius_px * K * VIS
	match k:
		"drone":
			_build_drone(r)
		"trooper":
			_build_trooper(r)
		"brute":
			_build_brute(r)
		"boss":
			_build_boss(r)
	add_child(Models.shadow_blob(r * 3.2))
	_meshes = Models.meshes(body)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1, 1, 1, 0)
	if elite:
		_elite_ring = _ground_ring(r * 2.8, GOLD, 0.1, 0.12)
		add_child(_elite_ring)
	_tell = _ground_ring(r * 3.0, RED, 0.12, 0.25)
	_tell.visible = false
	add_child(_tell)
	_tell_mat = _tell.material_override

func _ground_ring(size: float, col: Color, width: float, fill: float) -> MeshInstance3D:
	if _ring_shader == null:
		_ring_shader = load("res://shaders/ground_ring.gdshader")
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = _ring_shader
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("fill", fill)
	mi.material_override = m
	mi.position.y = 0.03
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

# ---------------------------------------------------------------- modèles
func _eye(r: float, col: Color, energy: float = 3.0) -> MeshInstance3D:
	var e := Models.sphere(r, Models.glow_mat(col, energy))
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return e

func _halo(size: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = Models.radial()
	m.albedo_color = Color(col.r * 1.4, col.g * 1.4, col.b * 1.4, 0.8)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _build_drone(r: float) -> void:
	var s := r * 1.35
	var hover := Node3D.new()
	hover.position.y = 0.62
	body.add_child(hover)
	parts["hover"] = hover
	var eye_col := RED if not elite else GOLD
	var core := Models.sphere(s, Models.toon(METAL, 0.5))
	core.scale = Vector3(1.0, 0.7, 1.0)
	hover.add_child(core)
	var cap := Models.sphere(s * 0.8, Models.toon(PLATE, 0.45), s * 0.8)
	cap.position.y = s * 0.3
	cap.scale = Vector3(1.0, 0.6, 1.0)
	hover.add_child(cap)
	# lentille rouge sur le dessus : lisible depuis la caméra haute
	var lens := Models.cyl(s * 0.34, s * 0.4, s * 0.12, Models.glow_mat(eye_col, 3.0), 16)
	lens.position.y = s * 0.55
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hover.add_child(lens)
	var ring := Models.torus(s * 1.2, s * 1.38, Models.glow_mat(eye_col, 1.6))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hover.add_child(ring)
	parts["ring"] = ring
	var eye := _eye(s * 0.3, eye_col, 4.0)
	eye.position = Vector3(0, 0.0, s * 0.92)
	hover.add_child(eye)
	var halo := _halo(s * 2.6, eye_col)
	halo.position = Vector3(0, s * 0.3, 0)
	hover.add_child(halo)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if elite:
		hover.scale = Vector3.ONE * 1.15

func _build_trooper(r: float) -> void:
	actor = Actor3D.new()
	body.add_child(actor)
	actor.setup("res://assets/models/chars/character-male-b.glb", "res://assets/models/blaster/blaster-h.glb", Color(0.42, 0.45, 0.58) if not elite else Color(0.75, 0.62, 0.4))
	actor.scale = Vector3.ONE * (1.6 if not elite else 1.85)
	# casque de garde : coque claire, visière rouge lumineuse
	var att := BoneAttachment3D.new()
	att.bone_name = "head"
	actor.skel.add_child(att)
	var helm := Models.sphere(0.2, Models.toon(PLATE, 0.5))
	helm.scale = Vector3(1.08, 0.95, 1.1)
	helm.position = Vector3(0, 0.15, -0.01)
	att.add_child(helm)
	var visor := Models.box(Vector3(0.32, 0.075, 0.08), Models.glow_mat(RED if not elite else GOLD, 3.0))
	visor.position = Vector3(0, 0.15, 0.2)
	att.add_child(visor)
	var crest := Models.box(Vector3(0.05, 0.08, 0.3), Models.toon(METAL, 0.3))
	crest.position = Vector3(0, 0.36, 0.0)
	att.add_child(crest)
	parts["visor"] = visor
	# armure de faction : plastron sombre à bande rouge, épaulières
	var t := BoneAttachment3D.new()
	t.bone_name = "torso"
	actor.skel.add_child(t)
	var chest := Models.box(Vector3(0.3, 0.18, 0.28), Models.toon(METAL, 0.4))
	chest.position = Vector3(0, 0.08, 0.0)
	t.add_child(chest)
	var stripe := Models.box(Vector3(0.31, 0.035, 0.285), Models.glow_mat(RED if not elite else GOLD, 2.0))
	stripe.position = Vector3(0, 0.1, 0.0)
	t.add_child(stripe)
	for b in ["arm-left", "arm-right"]:
		var a2 := BoneAttachment3D.new()
		a2.bone_name = b
		actor.skel.add_child(a2)
		var pad := Models.box(Vector3(0.13, 0.08, 0.14), Models.toon(PLATE if not elite else GOLD, 0.45))
		pad.position = Vector3(0, 0.03, 0)
		a2.add_child(pad)
	actor.meshes = Models.meshes(actor.model)
	_meshes = Models.meshes(body)

func _build_brute(r: float) -> void:
	var s := r * 1.6
	var root := Node3D.new()
	body.add_child(root)
	parts["root"] = root
	# jambes
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(side * s * 0.42, s * 0.62, 0)
		root.add_child(leg)
		var thigh := Models.box(Vector3(s * 0.3, s * 0.55, s * 0.36), Models.toon(METAL_D, 0.3))
		thigh.position.y = -s * 0.28
		leg.add_child(thigh)
		var foot := Models.box(Vector3(s * 0.38, s * 0.16, s * 0.56), Models.toon(PLATE_D, 0.3))
		foot.position = Vector3(0, -s * 0.56, s * 0.08)
		leg.add_child(foot)
		parts["leg%d" % side] = leg
	# torse
	var torso := Node3D.new()
	torso.position.y = s * 0.95
	root.add_child(torso)
	parts["torso"] = torso
	var chest := Models.box(Vector3(s * 1.15, s * 0.7, s * 0.8), Models.toon(METAL, 0.45))
	torso.add_child(chest)
	var plate := Models.box(Vector3(s * 0.95, s * 0.36, s * 0.12), Models.toon(PLATE, 0.4))
	plate.position = Vector3(0, s * 0.08, s * 0.42)
	torso.add_child(plate)
	var core := Models.box(Vector3(s * 0.4, s * 0.16, s * 0.06), Models.glow_mat(ORANGE, 2.5))
	core.position = Vector3(0, -s * 0.16, s * 0.42)
	torso.add_child(core)
	var head := Models.box(Vector3(s * 0.46, s * 0.3, s * 0.46), Models.toon(PLATE, 0.5))
	head.position = Vector3(0, s * 0.48, s * 0.06)
	torso.add_child(head)
	var eye := _eye(s * 0.11, RED, 4.0)
	eye.position = Vector3(0, s * 0.5, s * 0.3)
	torso.add_child(eye)
	var halo := _halo(s * 0.8, RED)
	halo.position = Vector3(0, s * 0.5, s * 0.36)
	torso.add_child(halo)
	# épaules et bras-marteaux
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.position = Vector3(side * s * 0.72, s * 0.2, 0)
		torso.add_child(arm)
		var shoulder := Models.sphere(s * 0.26, Models.toon(PLATE_D, 0.4))
		arm.add_child(shoulder)
		var fore := Models.box(Vector3(s * 0.26, s * 0.62, s * 0.28), Models.toon(METAL_D, 0.3))
		fore.position.y = -s * 0.36
		arm.add_child(fore)
		var hammer := Models.cyl(s * 0.24, s * 0.24, s * 0.42, Models.toon(PLATE_D, 0.4), 8)
		hammer.rotation.x = PI * 0.5
		hammer.position = Vector3(0, -s * 0.74, s * 0.08)
		arm.add_child(hammer)
		var stripe := Models.cyl(s * 0.25, s * 0.25, s * 0.08, Models.glow_mat(ORANGE, 2.0), 8)
		stripe.rotation.x = PI * 0.5
		stripe.position = Vector3(0, -s * 0.74, s * 0.08)
		arm.add_child(stripe)
		parts["arm%d" % side] = arm
	if elite:
		root.scale = Vector3.ONE * 1.15

func _build_boss(r: float) -> void:
	var s := r * 1.05
	var root := Node3D.new()
	body.add_child(root)
	parts["root"] = root
	var hull := Node3D.new()
	hull.position.y = s * 0.95
	root.add_child(hull)
	parts["hull"] = hull
	# pattes : quatre segments articulés
	var legs := []
	for i in range(4):
		var a := PI * 0.25 + PI * 0.5 * i
		var hip := Node3D.new()
		hip.position = Vector3(sin(a), 0, cos(a)) * s * 0.55
		hip.rotation.y = a
		hull.add_child(hip)
		var upper := Models.box(Vector3(s * 0.2, s * 0.2, s * 0.75), Models.toon(PLATE_D, 0.35))
		upper.position = Vector3(0, s * 0.1, s * 0.35)
		upper.rotation.x = -0.45
		hip.add_child(upper)
		var knee := Models.sphere(s * 0.16, Models.toon(METAL, 0.4))
		knee.position = Vector3(0, s * 0.3, s * 0.7)
		hip.add_child(knee)
		var lower := Models.box(Vector3(s * 0.17, s * 1.05, s * 0.17), Models.toon(METAL_D, 0.3))
		lower.position = Vector3(0, -s * 0.2, s * 0.86)
		lower.rotation.x = 0.25
		hip.add_child(lower)
		var foot := Models.cyl(s * 0.2, s * 0.26, s * 0.12, Models.toon(PLATE_D, 0.3), 8)
		foot.position = Vector3(0, -s * 0.7, s * 1.0)
		hip.add_child(foot)
		legs.append(hip)
	parts["legs"] = legs
	# coque hexagonale
	var shell := Models.cyl(s * 0.78, s * 0.9, s * 0.5, Models.toon(METAL, 0.45), 6)
	hull.add_child(shell)
	var top := Models.cyl(s * 0.62, s * 0.78, s * 0.18, Models.toon(METAL_D, 0.4), 6)
	top.position.y = s * 0.33
	hull.add_child(top)
	var band := Models.cyl(s * 0.91, s * 0.91, s * 0.08, Models.glow_mat(MAGENTA, 2.2), 6)
	band.position.y = -s * 0.1
	hull.add_child(band)
	parts["band"] = band
	# tourelle double (Space Kit) sur le dos, tournée vers la cible
	var turret := Models.inst("res://assets/models/space/turret_double.glb", true)
	Models.tint_node(turret, 0.6)
	turret.scale = Vector3.ONE * s * 1.1
	turret.position.y = s * 0.4
	turret.rotation.y = PI
	hull.add_child(turret)
	parts["turret"] = turret
	# visière avant
	var visor := Models.box(Vector3(s * 0.7, s * 0.14, s * 0.12), Models.glow_mat(MAGENTA, 3.0))
	visor.position = Vector3(0, s * 0.08, s * 0.82)
	hull.add_child(visor)
	var halo := _halo(s * 2.0, MAGENTA)
	halo.position = Vector3(0, s * 0.08, s * 0.9)
	hull.add_child(halo)
	var core := _eye(s * 0.16, ORANGE, 3.0)
	core.position = Vector3(0, s * 0.45, 0)
	hull.add_child(core)

# ---------------------------------------------------------------- animation
var _punch := 0.0

func flash() -> void:
	_flash_t = 0.09
	_punch = 1.0
	if actor != null:
		actor.flash()
		return
	for mi in _meshes:
		(mi as MeshInstance3D).material_overlay = _flash_mat

func sync(e: Node2D, dt: float) -> void:
	t += dt
	position = Vector3(e.position.x * K, ground_y, e.position.y * K)
	var f: Vector2 = e.facing
	if f.length() > 0.01:
		var target := atan2(f.x, f.y)
		yaw = lerp_angle(yaw, target, clampf(dt * 12.0, 0.0, 1.0))
	body.rotation.y = yaw
	# petit sursaut à l'impact
	_punch = maxf(0.0, _punch - dt * 9.0)
	body.scale = Vector3(1.0 + _punch * 0.12, 1.0 - _punch * 0.08, 1.0 + _punch * 0.12)
	var st: String = e.state
	var moving := true
	match kind:
		"drone":
			var hover: Node3D = parts["hover"]
			hover.position.y = 0.62 + sin(t * 5.0 + e.wobble) * 0.06
			var rg: Node3D = parts["ring"]
			rg.rotation.x = sin(t * 2.0 + e.wobble) * 0.3
			rg.rotation.z = cos(t * 2.0 + e.wobble) * 0.3
			hover.rotation.z = sin(t * 3.0) * 0.12
		"trooper":
			var aiming := st == "aim"
			actor.set_motion(0.5 if not aiming else 0.0, 1.0 if aiming else 0.0)
		"brute":
			var spd := 1.0 if st == "charge" else 0.6
			var w := t * (14.0 if st == "charge" else 7.0)
			(parts["leg-1"] as Node3D).rotation.x = sin(w) * 0.5 * spd
			(parts["leg1"] as Node3D).rotation.x = -sin(w) * 0.5 * spd
			var torso: Node3D = parts["torso"]
			torso.rotation.x = 0.35 if st == "charge" else (-0.2 if st == "tell" else 0.0)
			var raise := -2.2 if st == "tell" else (-0.6 if st == "charge" else sin(w) * 0.35)
			(parts["arm-1"] as Node3D).rotation.x = raise
			(parts["arm1"] as Node3D).rotation.x = raise if st != "move" else -sin(w) * 0.35
		"boss":
			var legs: Array = parts["legs"]
			for i in range(legs.size()):
				var hip: Node3D = legs[i]
				hip.rotation.x = sin(t * 5.0 + i * PI * 0.5) * 0.12
			var hull: Node3D = parts["hull"]
			hull.rotation.z = sin(t * 2.5) * 0.03
			var band: MeshInstance3D = parts["band"]
			band.scale = Vector3.ONE * (1.0 + (0.06 * sin(t * 30.0) if st == "ring" else 0.0))
	# télégraphe d'attaque au sol
	var telling := st == "tell" or st == "ring" or st == "charge"
	_tell.visible = telling
	if telling:
		var p := 1.0
		if st == "tell":
			p = 1.0 - clampf(e.state_t / (0.8 if kind == "boss" else 0.7), 0.0, 1.0)
		_tell_mat.set_shader_parameter("progress", p)
		_tell_mat.set_shader_parameter("color", MAGENTA if (kind == "boss" and st == "ring") else RED)
	if _elite_ring != null:
		_elite_ring.rotation.y = t * 1.5
	if _flash_t > 0.0:
		_flash_t -= dt
		_flash_mat.albedo_color = Color(1.6, 1.6, 1.6, clampf(_flash_t * 10.0, 0.0, 0.8))
		if _flash_t <= 0.0:
			for mi in _meshes:
				(mi as MeshInstance3D).material_overlay = null

## Mort : le garde s'effondre, les machines s'affaissent ; le rendu supprime le nœud à la fin.
func start_death() -> void:
	dying = 0.001
	_tell.visible = false
	if _elite_ring:
		_elite_ring.visible = false
	if actor != null:
		actor.die()

## Renvoie vrai quand l'animation de mort est terminée.
func tick_death(dt: float) -> bool:
	dying += dt
	match kind:
		"trooper":
			if dying > 0.9:
				position.y -= dt * 0.8
		"drone":
			var hover: Node3D = parts["hover"]
			hover.position.y = maxf(0.12, hover.position.y - dt * 3.0)
			hover.rotation.z += dt * 12.0
			if dying > 0.25:
				return true
		_:
			body.scale = Vector3.ONE * maxf(0.01, 1.0 - dying * 3.0)
			if dying > 0.3:
				return true
	return dying > 1.4
