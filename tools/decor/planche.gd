extends Node3D
## Planche des objets de fret sculptés (assets/decor/props) sous l'éclairage du hangar.
## godot --path . res://tools/decor/planche.tscn --write-movie out.png --fixed-fps 10 --quit-after 4 -- [--view=jeu|proche] [--only=a,b,...]

const HangarProps = preload("res://scripts/decor/hangar_props.gd")
const Models = preload("res://scripts/models.gd")

func _ready() -> void:
	var view := "proche"
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="):
			view = a.trim_prefix("--view=")
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
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
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	e.adjustment_contrast = 1.05
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 28, 0)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 0.82
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 30)
	fl.mesh = pm
	fl.material_override = Models.toon(Color("#2A3458"), 0.0)
	add_child(fl)
	var names: Array = HangarProps.CATALOG.keys() if only.is_empty() else Array(only)
	var cols := 6 if only.is_empty() else mini(only.size(), 5)
	var gap := 1.75
	for i in range(names.size()):
		var nm: String = names[i]
		var root := Node3D.new()
		root.position = Vector3((i % cols - (cols - 1) * 0.5) * gap, 0, int(i / cols) * gap - 2.0)
		add_child(root)
		for part in HangarProps.parts(nm):
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.transform = part[1]
			root.add_child(mi)
		var l := Label3D.new()
		l.text = nm
		l.position = root.position + Vector3(0, 0.01, 0.75)
		l.rotation_degrees.x = -90
		l.font_size = 22
		l.modulate = Color(0.8, 0.85, 1.0)
		add_child(l)
	var cam := Camera3D.new()
	add_child(cam)
	var rows := int(ceil(names.size() / float(cols)))
	var mid := Vector3(0, 0.3, (rows - 1) * gap * 0.5 - 2.0)
	if view == "jeu":
		cam.fov = 38
		var p := deg_to_rad(56.0)
		cam.position = mid + Vector3(0, sin(p), cos(p)) * (rows * 2.6 + 4.0)
		cam.look_at(mid)
	else:
		cam.fov = 30
		var span := maxf(cols * gap * 0.62, rows * gap)
		cam.position = mid + Vector3(0.6, 1.0 + span * 1.45, 1.0 + span * 1.05)
		cam.look_at(mid + Vector3(0, 0, -0.2))
	cam.make_current()
