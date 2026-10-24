extends Node3D
## Visuel 3D d'un ennemi, synchronisé sur l'ennemi simulé (enemy.gd).
## Sentinelle : drone flottant à œil rouge. Garde : soldat (Mini Character teinté) casqué à visière rouge.
## Colosse : marcheur blindé à bras-marteaux. Le Portique : mécha quadrupède surmonté d'une tourelle double.

const Models = preload("res://scripts/models.gd")
const Actor3D = preload("res://scripts/actor3d.gd")
const Rig3D = preload("res://scripts/rig3d.gd")
## Échelle des modèles sculptés (conçus à l'échelle de Jo, qui est affichée à 1,75).
const RIG_SCALE := {"drone": 1.75, "trooper": 1.75, "brute": 1.3, "boss": 1.05, "bomber": 1.75, "sniper": 1.75, "shield": 1.75, "mortar": 1.75, "roller": 1.75, "hacker": 1.75, "copter": 1.75, "bouncer": 1.3, "boss2": 1.05}
## Durée de l'animation de mort avant suppression du nœud.
const DEATH_T := {"drone": 0.85, "trooper": 1.3, "brute": 1.0, "boss": 1.6, "bomber": 0.2, "sniper": 0.9, "shield": 1.0, "mortar": 0.7, "roller": 0.7, "hacker": 0.85, "copter": 0.6, "bouncer": 1.0, "boss2": 1.6}
## Durée du télégraphe (état « tell ») par genre, pour remplir l'anneau au sol.
const TELL_T := {"brute": 0.7, "boss": 0.8, "bomber": 0.55, "shield": 0.5, "mortar": 0.9, "roller": 0.35, "hacker": 0.55, "bouncer": 0.8, "boss2": 0.8}
const NEON_PINK := Color("#FF3CAC")
const NEON_BLUE := Color("#3C8CFF")
const VIOLET := Color("#B36BFF")

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
var rig: Rig3D = null  # modèle sculpté (assets/chars3d/<kind>.glb + scripts/mobs/<kind>.gd)
var _last_state := ""
var _state_el := 0.0
var parts := {}
var t := 0.0
var _flash_t := 0.0
var _flash_mat: StandardMaterial3D
var _meshes: Array = []
var _elite_ring: MeshInstance3D = null
var _tell: MeshInstance3D = null
var _tell_mat: ShaderMaterial = null
var _laser: MeshInstance3D = null  # vigie : laser de visée
var _laser_mat: StandardMaterial3D = null
var _beam: MeshInstance3D = null  # gyro : faisceau du projecteur au sol
var _beam_mat: StandardMaterial3D = null
var yaw := 0.0
var dying := 0.0  # > 0 : animation de mort en cours
var death_dir := Vector3.ZERO  # sens du coup fatal (posé par view3d) : la Sentinelle part en vrille par là
var ground_y := 0.0

static var _ring_shader: Shader = null

func setup(k: String, is_elite: bool, radius_px: float) -> void:
	kind = k
	elite = is_elite
	body = Node3D.new()
	add_child(body)
	var r := radius_px * K * VIS
	if _build_rig(k, is_elite):
		pass
	else:
		_build_legacy(k, r)
	add_child(Models.shadow_blob(r * 3.2))
	_finish_setup(r)

## Modèle sculpté s'il existe, sinon ancien assemblage de primitives.
func _build_rig(k: String, is_elite: bool) -> bool:
	var scr := "res://scripts/mobs/%s.gd" % k
	var glb := "res://assets/chars3d/%s.glb" % k
	if not (ResourceLoader.exists(scr) and ResourceLoader.exists(glb)):
		return false
	var eglb := "res://assets/chars3d/%s_elite.glb" % k
	if is_elite and ResourceLoader.exists(eglb):
		glb = eglb
	rig = load(scr).new()
	rig.elite = is_elite
	body.add_child(rig)
	rig.setup(glb)
	rig.scale = Vector3.ONE * float(RIG_SCALE.get(k, 1.75)) * (1.12 if is_elite else 1.0)
	return true

func _build_legacy(k: String, r: float) -> void:
	match k:
		"drone":
			_build_drone(r)
		"trooper":
			_build_trooper(r)
		"brute":
			_build_brute(r)
		"boss":
			_build_boss(r)
		_:
			_build_placeholder(k, r)

## Silhouette provisoire d'un genre sans modèle sculpté (le jeu reste jouable en attendant le modèle).
func _build_placeholder(k: String, r: float) -> void:
	var col: Color = {"bomber": Color("#FFC93C"), "sniper": VIOLET, "shield": ORANGE, "mortar": Color("#9BE15D"), "roller": NEON_PINK, "hacker": Color("#B6FF3C"), "copter": NEON_BLUE, "bouncer": Color("#FF8A3C"), "boss2": NEON_PINK}.get(k, PLATE)
	var b := Models.sphere(r, Models.toon(col, 0.3))
	b.position.y = r
	body.add_child(b)
	var eye := _eye(r * 0.3, RED)
	eye.position = Vector3(0, r * 1.2, r * 0.8)
	body.add_child(eye)
	if k == "shield":
		var sh := Models.box(Vector3(r * 2.4, r * 1.8, 0.08), Models.glow_mat(ORANGE, 1.2))
		sh.position = Vector3(0, r * 1.1, r * 1.2)
		body.add_child(sh)

func _finish_setup(r: float) -> void:
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
	if kind == "bomber":
		# l'anneau du pétard montre le rayon réel de l'explosion (82 px)
		_tell.scale = Vector3.ONE * (82.0 * 2.0 * K) / (r * 3.0)
	if kind == "bouncer":
		# l'anneau du videur montre la portée de son onde de choc (280 px)
		_tell.scale = Vector3.ONE * (280.0 * 2.0 * K) / (r * 3.0)
	if kind == "copter":
		_build_beam()
	if kind == "sniper":
		_laser = MeshInstance3D.new()
		var q := PlaneMesh.new()
		q.size = Vector2(0.07, 1.0)
		_laser.mesh = q
		_laser_mat = StandardMaterial3D.new()
		_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_laser_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_laser_mat.albedo_color = Color(VIOLET, 0.0)
		_laser.material_override = _laser_mat
		_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_laser.visible = false
		add_child(_laser)

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
	if rig != null:
		rig.flash()
		return
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
	if st != _last_state:
		if rig != null and (_last_state == "aim" or (_last_state == "tell" and kind in ["mortar", "hacker"])):
			rig.fire()
		_last_state = st
		_state_el = 0.0
	else:
		_state_el += dt
	var moving := true
	if rig != null:
		rig.state = st
		rig.state_t = _state_el
		var spd := 0.5
		var sh := 0.0
		match kind:
			"drone":
				spd = 1.0
			"trooper":
				spd = 0.0 if st == "aim" else 0.5
				sh = 1.0 if st == "aim" else 0.0
			"brute", "boss":
				spd = 1.0 if st == "charge" else (0.0 if st == "tell" or st == "ring" else 0.55)
			"bomber":
				spd = 0.0 if st == "tell" else 1.0
			"sniper":
				spd = 0.0 if st == "aim" else 0.6
				sh = 1.0 if st == "aim" else 0.0
			"shield":
				spd = 1.0 if st == "charge" else (0.0 if st == "tell" else 0.5)
			"mortar":
				spd = 0.0 if st == "tell" else 0.5
			"roller":
				spd = 1.0 if st == "charge" else (0.0 if st == "tell" else 0.9)
			"hacker":
				spd = 0.0 if st == "tell" or st == "blink" else 0.5
				sh = 1.0 if st == "tell" else 0.0
			"copter":
				spd = 0.7
				sh = 1.0 if st == "aim" else 0.0
			"bouncer":
				spd = 0.0 if st == "tell" or st == "ring" else 0.55
			"boss2":
				spd = 0.0 if st == "tell" or st == "spiral" else 0.55
				sh = 1.0 if st == "spiral" else 0.0
		rig.set_motion(spd, sh)
	match kind if rig == null else "":
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
	var telling := st == "tell" or st == "ring" or st == "charge" or st == "spiral"
	_tell.visible = telling
	if telling:
		var p := 1.0
		if st == "tell":
			p = 1.0 - clampf(e.state_t / float(TELL_T.get(kind, 0.7)), 0.0, 1.0)
		_tell_mat.set_shader_parameter("progress", p)
		_tell_mat.set_shader_parameter("color", MAGENTA if (kind == "boss" and st == "ring") else RED)
	if _laser != null:
		_sync_laser(e, st)
	if _beam != null:
		var ad: Vector2 = e.aim_dir
		_beam.rotation.y = atan2(ad.x, ad.y)
		# rouge quand Jo est prise dans le faisceau, clignote pendant la rafale
		var lk := clampf(float(e.lock) / 0.6, 0.0, 1.0)
		var c := Color(0.55, 0.75, 1.0).lerp(Color(1.0, 0.25, 0.35), lk if st != "aim" else 1.0)
		var a := 0.18 + 0.2 * lk
		if st == "aim":
			a = 0.45 if int(t * 24.0) % 2 == 0 else 0.25
		_beam_mat.albedo_color = Color(c, a)
	if kind == "hacker":
		# éclipse de la téléportation : le pirate se résorbe, puis réapparaît ailleurs
		body.scale = Vector3.ONE * (maxf(0.05, 1.0 - _state_el / 0.15) if st == "blink" else 1.0)
	if _elite_ring != null:
		_elite_ring.rotation.y = t * 1.5
	if _flash_t > 0.0:
		_flash_t -= dt
		_flash_mat.albedo_color = Color(1.6, 1.6, 1.6, clampf(_flash_t * 10.0, 0.0, 0.8))
		if _flash_t <= 0.0:
			for mi in _meshes:
				(mi as MeshInstance3D).material_overlay = null

## Mort : le garde s'effondre, les machines s'affaissent ; le rendu supprime le nœud à la fin.
## Faisceau du projecteur du gyro : un cône posé au sol (même ouverture et portée que la simulation).
func _build_beam() -> void:
	var half := 0.28
	var reach := 400.0 * K
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	for i in range(n):
		var a0 := -half + 2.0 * half * i / n
		var a1 := -half + 2.0 * half * (i + 1) / n
		st.set_uv(Vector2(0.5, 0.0))
		st.add_vertex(Vector3.ZERO)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(Vector3(sin(a0), 0, cos(a0)) * reach)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(Vector3(sin(a1), 0, cos(a1)) * reach)
	_beam = MeshInstance3D.new()
	_beam.mesh = st.commit()
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_texture = Models.beam()
	_beam_mat.albedo_color = Color(0.55, 0.75, 1.0, 0.22)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position.y = 0.05
	add_child(_beam)

## Laser de visée de la vigie : suit la cible, se fige et clignote dans le dernier quart de seconde.
func _sync_laser(e: Node2D, st: String) -> void:
	_laser.visible = st == "aim"
	if st != "aim":
		return
	var ad: Vector2 = e.aim_dir
	var d := Vector3(ad.x, 0, ad.y).normalized()
	var start := Vector3(0, 0.95, 0) + d * 0.5
	if rig != null and rig.has_method("muzzle_position"):
		start = rig.muzzle_position() - global_position
	var len := 15.0
	_laser.position = start + d * (len * 0.5)
	_laser.rotation = Vector3(0, atan2(d.x, d.z), 0)
	var locked: bool = e.state_t < 0.25
	var prog := 1.0 - clampf(e.state_t / 1.1, 0.0, 1.0)
	_laser.scale = Vector3(2.2 if locked else 1.0, 1, len)
	var a := (0.9 if int(t * 30.0) % 2 == 0 else 0.4) if locked else 0.2 + 0.45 * prog
	_laser_mat.albedo_color = Color(VIOLET.r * 1.6, VIOLET.g * 1.6, VIOLET.b * 1.6, a)

func start_death() -> void:
	dying = 0.001
	_tell.visible = false
	if _laser != null:
		_laser.visible = false
	if _beam != null:
		_beam.visible = false
	if _elite_ring:
		_elite_ring.visible = false
	if actor != null:
		actor.die()
	if rig != null:
		rig.die()

## Sentinelle abattue : petit sursaut, puis chute en vrille (spirale qui se resserre) jusqu'au sol vers 0,5 s.
func _drone_fall(dt: float) -> void:
	var k := clampf(dying / 0.5, 0.0, 1.0)
	var d := death_dir if death_dir.length() > 0.01 else Vector3(0, 0, 1)
	var sw := Vector3(sin(dying * 16.0), 0.0, cos(dying * 16.0) - 1.0) * 0.22 * (1.0 - k)
	body.position = d * 0.9 * (1.0 - (1.0 - k) * (1.0 - k)) + sw + Vector3(0, 0.45 * sin(PI * k), 0)
	body.rotation.y += dt * 20.0 * (1.0 - k * 0.8)
	body.rotation.z = lerpf(body.rotation.z, 0.7, clampf(dt * 8.0, 0.0, 1.0))

## Renvoie vrai quand l'animation de mort est terminée.
func tick_death(dt: float) -> bool:
	dying += dt
	if rig != null:
		var dt_end: float = DEATH_T.get(kind, 1.0)
		if kind == "drone":
			_drone_fall(dt)
		if dying > dt_end - 0.35:
			body.scale = Vector3.ONE * maxf(0.01, (dt_end - dying) / 0.35)
		return dying > dt_end
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
