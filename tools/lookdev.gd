extends Node3D
## Banc d'essai visuel : alignement des personnages et des ennemis sous la lumière du jeu.
## godot --path . res://tools/lookdev.tscn --write-movie out.png --fixed-fps 10 --quit-after 12

const Models = preload("res://scripts/models.gd")
const Actor3D = preload("res://scripts/actor3d.gd")
const Mob3D = preload("res://scripts/mob3d.gd")

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0E1B33")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.7, 0.95)
	e.ambient_light_energy = 0.7
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_hdr_threshold = 1.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 20)
	floor.mesh = pm
	floor.material_override = Models.toon(Color("#3B4466"), 0.0)
	add_child(floor)
	var names := ["female-a", "female-b", "female-c", "female-d", "female-e", "female-f", "male-a", "male-b", "male-c", "male-d", "male-e", "male-f"]
	for i in range(names.size()):
		var a := Actor3D.new()
		add_child(a)
		a.setup("res://assets/models/chars/character-%s.glb" % names[i], "res://assets/models/blaster/blaster-a.glb")
		a.position = Vector3(-6.6 + i * 1.2, 0, 2.0)
		a.scale = Vector3.ONE * 1.3
		a.set_motion(0.0, 1.0 if i % 2 == 0 else 0.0)
		var l := Label3D.new()
		l.text = names[i]
		l.position = Vector3(-6.6 + i * 1.2, 0.05, 3.0)
		l.rotation_degrees.x = -90
		l.font_size = 40
		add_child(l)
	var kinds := [["drone", 15.0, false], ["trooper", 18.0, false], ["brute", 30.0, false], ["boss", 58.0, false], ["trooper", 18.0, true], ["drone", 15.0, true]]
	var x := -6.0
	for k in kinds:
		var m := Mob3D.new()
		add_child(m)
		m.setup(k[0], k[2], k[1])
		m.position = Vector3(x, 0, -1.5)
		m.body.rotation.y = 0.0
		x += 2.6 if k[0] != "boss" else 4.0
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.position = Vector3(0, 7.5, 9.5)
	cam.look_at(Vector3(0, 0.4, 0.6))
	cam.make_current()
