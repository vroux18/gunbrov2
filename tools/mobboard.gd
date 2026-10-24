extends Node3D
## Planche des ennemis vus à la caméra de jeu, à côté de Jo : même éclairage que le jeu (view3d.gd),
## rangées normales / élites face caméra, rangée de dos. Modèles montés par mob3d.gd (échelle, anneau d'élite).
## godot --path . res://tools/mobboard.tscn --write-movie out.png --fixed-fps 10 --quit-after 12 -- [--set=boss] [--dist=11.5] [--state=move]

const Mob3D = preload("res://scripts/mob3d.gd")
const Rig3D = preload("res://scripts/rig3d.gd")
const Models = preload("res://scripts/models.gd")
const Data = preload("res://scripts/data.gd")
const KINDS := ["drone", "trooper", "bomber", "sniper", "shield", "mortar", "brute"]

var mobs: Array = []  # [Mob3D, vitesse]
var heroes: Array = []
var state := "move"
var t := 0.0

func _ready() -> void:
	var set_name := "board"
	var kind := "drone"
	var dist := 11.5
	var pitch := 56.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--set="):
			set_name = a.trim_prefix("--set=")
		if a.begins_with("--dist="):
			dist = float(a.trim_prefix("--dist="))
		if a.begins_with("--pitch="):
			pitch = float(a.trim_prefix("--pitch="))
		if a.begins_with("--kind="):
			kind = a.trim_prefix("--kind=")
		if a.begins_with("--state="):
			state = a.trim_prefix("--state=")
	_env()
	if set_name == "solo":
		# un ennemi en gros plan (avec --dist=4) : normal et élite, de face et de dos, Jo pour l'échelle
		var w := {"brute": 1.6, "boss": 2.6, "shield": 1.2, "mortar": 1.2}.get(kind, 1.0) as float
		_hero(Vector3(-1.75 * w, 0, 0), 0.4)
		_mob(kind, false, Vector3(-0.6 * w, 0, 0), 0.4)
		_mob(kind, true, Vector3(0.55 * w, 0, 0), 0.4)
		_mob(kind, false, Vector3(1.7 * w, 0, 0), PI + 0.6)
	elif set_name == "close":
		# gros plan (avec --dist=5) : le rendu des matières
		_hero(Vector3(-1.9, 0, 0.2), 0.5)
		_mob("trooper", false, Vector3(-0.6, 0, 0), 0.3)
		_mob("drone", false, Vector3(0.6, 0, 0.3), 0.2)
		_mob("brute", false, Vector3(2.1, 0, -0.2), -0.4)
	elif set_name == "boss":
		_hero(Vector3(-4.2, 0, 1.6), 0.6)
		_mob("boss", false, Vector3(0.3, 0, -0.4), 0.3)
		_mob("drone", false, Vector3(-4.0, 0, -1.6), 0.5)
		_mob("trooper", true, Vector3(4.6, 0, 1.8), -0.6)
	elif set_name == "horde":
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		_hero(Vector3(0, 0, 0), 0.0)
		for i in range(30):
			var k: String = KINDS[i % KINDS.size()]
			var p := Vector3(rng.randf_range(-6.5, 6.5), 0, rng.randf_range(-3.6, 3.4))
			if p.length() < 1.2:
				p += p.normalized() * 1.5
			_mob(k, i % 5 == 0, p, rng.randf() * TAU)
	else:
		# planche en deux moitiés (vraie échelle de jeu) : --set=a (Sentinelle, Garde, Pétard, Vigie),
		# --set=b (Rempart, Mortier, Colosse)
		var ks: Array = KINDS.slice(0, 4) if set_name != "b" else KINDS.slice(4, 7)
		var dx := 2.4 if set_name != "b" else 3.0
		var x0 := -dx * ks.size() * 0.5
		_hero(Vector3(x0, 0, -2.3), 0.35)
		_hero(Vector3(x0, 0, 2.4), PI + 0.5)
		for i in range(ks.size()):
			var k: String = ks[i]
			var x := x0 + dx * (i + 1)
			_mob(k, false, Vector3(x, 0, -2.3), 0.35)
			_mob(k, true, Vector3(x - dx * 0.5, 0, 0.05), 0.35)
			_mob(k, false, Vector3(x, 0, 2.4), PI + 0.5)
	var cam := Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.5
	cam.far = 120.0
	add_child(cam)
	var pr := deg_to_rad(pitch)
	cam.position = Vector3(0, sin(pr), cos(pr)) * dist
	var focus := Vector3.ZERO
	if set_name == "close":
		focus = Vector3(0, 0.6, -0.4)
	elif set_name == "solo":
		focus = Vector3(0, 0.4, 0)
	cam.position += focus
	cam.look_at(focus, Vector3.UP)
	cam.make_current()

## Éclairage du jeu (view3d.gd, _build_env) et un sol de tôle sombre.
func _env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/env/space.jpg")
	sky.sky_material = pano
	env.background_mode = Environment.BG_SKY
	env.sky = sky
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
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 28, 0)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 26.0
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 30)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#3A404E")
	fm.roughness = 0.7
	fm.metallic = 0.3
	floor.material_override = fm
	add_child(floor)

func _hero(pos: Vector3, yaw: float) -> void:
	var h := Rig3D.new()
	add_child(h)
	h.setup("res://assets/chars3d/jo.glb", Color(1, 1, 1), 1.7)
	h.scale = Vector3.ONE * 1.75
	h.position = pos
	h.rotation.y = yaw
	var sb := Models.shadow_blob(1.1)
	sb.position = pos + Vector3(0, 0.02, 0)
	add_child(sb)
	heroes.append(h)

func _mob(k: String, elite: bool, pos: Vector3, yaw: float) -> void:
	var m := Mob3D.new()
	add_child(m)
	var r: float = float(Data.ENEMIES[k]["radius"]) * (1.2 if elite else 1.0)
	m.setup(k, elite, r)
	m.position = pos
	m.body.rotation.y = yaw
	mobs.append(m)

func _process(dt: float) -> void:
	t += dt
	if Engine.get_frames_drawn() == 6:
		print("PERF : appels de dessin %d, objets %d, primitives %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	for h in heroes:
		(h as Rig3D).set_motion(0.6, 0.0)
	for mm in mobs:
		var m: Mob3D = mm
		if m.rig == null:
			continue
		var st := state
		if st == "mix":
			st = ["move", "aim", "tell", "move"][int(m.position.x * 3.0 + 10.0) % 4]
		m.rig.state = st
		m.rig.state_t += dt
		m.rig.set_motion(0.6 if st == "move" else 0.0, 0.0)
		if m._elite_ring != null:
			m._elite_ring.rotation.y = t * 1.5
