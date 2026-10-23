extends Node3D
## Banc d'essai des personnages sculptés : vue de face 3/4 et vue de jeu, repos, marche, tir.
## godot --path . res://tools/charlook.tscn --write-movie out.png --fixed-fps 10 --quit-after 30 -- --char=jo

const Rig3D = preload("res://scripts/rig3d.gd")
var state := "move"
var sc := 1.6
var script_path := ""

## Rig du personnage : scripts/mobs/<nom>.gd s'il existe (mobs), sinon le rig bipède générique.
func _new_rig() -> Node3D:
	if script_path != "":
		return load(script_path).new()
	return Rig3D.new()
const Models = preload("res://scripts/models.gd")
var rigs: Array = []

func _ready() -> void:
	var name := "jo"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--char="):
			name = a.trim_prefix("--char=")
		if a.begins_with("--state="):
			state = a.trim_prefix("--state=")
		if a.begins_with("--scale="):
			sc = float(a.trim_prefix("--scale="))
	if ResourceLoader.exists("res://scripts/mobs/%s.gd" % name):
		script_path = "res://scripts/mobs/%s.gd" % name
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0E1B33")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.58, 0.9)
	e.ambient_light_energy = 0.36
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_hdr_threshold = 1.0
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 28, 0)
	sun.light_energy = 0.82
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 20)
	floor.mesh = pm
	floor.material_override = Models.toon(Color("#232D52"), 0.0)
	add_child(floor)
	var poses := [[0.0, 0.0], [0.8, 0.0], [0.0, 1.0], [0.8, 1.0]]
	for i in range(4):
		var r := _new_rig()
		add_child(r)
		r.setup("res://assets/chars3d/%s.glb" % name)
		r.position = Vector3(-3.3 + i * 2.2, 0, 0)
		r.scale = Vector3.ONE * sc
		r.rotation.y = 0.5
		r.speed = poses[i][0]
		r.set_motion(poses[i][0], poses[i][1])
		r.shooting = poses[i][1]
		rigs.append([r, poses[i]])
	var cam := Camera3D.new()
	cam.fov = 34
	add_child(cam)
	cam.position = Vector3(0, 2.4, 7.0)
	cam.look_at(Vector3(0, 0.75, 0))
	cam.make_current()
	# deuxième rangée vue de jeu (caméra haute) : la même héroïne, plus loin, plus petite
	for i in range(3):
		var r := _new_rig()
		add_child(r)
		r.setup("res://assets/chars3d/%s.glb" % name)
		r.position = Vector3(-2.0 + i * 2.0, 0, -6.0)
		r.scale = Vector3.ONE * sc
		r.rotation.y = [0.0, PI, PI * 0.5][i]
		r.set_motion(0.7, 1.0 if i == 0 else 0.0)
		rigs.append([r, [0.7, 1.0 if i == 0 else 0.0]])

func _process(dt: float) -> void:
	for rp in rigs:
		var r = rp[0]
		r.set_motion(rp[1][0], rp[1][1])
		if state == "dead":
			if not r.dead:
				r.die()
		else:
			r.state = state
			r.state_t += dt
