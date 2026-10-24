extends Node3D
## Planche des objets sculptés de la Cité Néon (assets/decor/neon/props) sous un éclairage de nuit pluvieuse.
## godot --path . res://tools/decor/neon_props_planche.tscn --write-movie out.png --fixed-fps 10 --quit-after 4 -- [--view=jeu|proche] [--only=a,b,...] [--cols=N]

const NeonProps = preload("res://scripts/decor/neon_props.gd")
const Models = preload("res://scripts/models.gd")

func _ready() -> void:
	var view := "proche"
	var only: PackedStringArray = []
	var ncols := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="):
			view = a.trim_prefix("--view=")
		if a.begins_with("--cols="):
			ncols = int(a.trim_prefix("--cols="))
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
	var neutral := "--light=neutre" in OS.get_cmdline_user_args()  # lumière blanche : vraies couleurs
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#120E22")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.38, 0.8)
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_hdr_threshold = 1.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.1
	e.adjustment_contrast = 1.05
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 28, 0)
	sun.light_color = Color(0.72, 0.76, 1.0)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	if neutral:
		e.ambient_light_color = Color(0.7, 0.7, 0.78)
		e.background_color = Color("#2A2C38")
		sun.light_color = Color(1, 0.97, 0.92)
		sun.light_energy = 1.0
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 30)
	fl.mesh = pm
	fl.material_override = Models.toon(Color("#22243A"), 0.0)
	add_child(fl)
	var names: Array = []
	if only.is_empty():
		for f in DirAccess.get_files_at(NeonProps.PR):
			if f.ends_with(".glb"):
				names.append(f.get_basename())
	else:
		names = Array(only)
	var cols := ncols if ncols > 0 else (7 if only.is_empty() else mini(only.size(), 5))
	var gap := 2.3 if only.size() in range(1, 6) else 3.0
	for i in range(names.size()):
		var nm: String = names[i]
		var root := Node3D.new()
		root.position = Vector3((i % cols - (cols - 1) * 0.5) * gap, 0, int(i / cols) * gap - 2.0)
		add_child(root)
		for part in NeonProps.parts(nm):
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.transform = part[1]
			root.add_child(mi)
		var l := Label3D.new()
		l.text = nm
		l.position = root.position + Vector3(0, 0.01, 1.1)
		l.rotation_degrees.x = -90
		l.font_size = 26
		l.modulate = Color(0.8, 0.85, 1.0)
		add_child(l)
	var rows := int(ceil(names.size() / float(cols)))
	# néons de la ville : une lumière rose à gauche, une bleue à droite
	for L in [[Vector3(-cols * gap * 0.35, 3.0, rows * gap * 0.3), Color("#FF3CAC")], [Vector3(cols * gap * 0.35, 3.0, rows * gap * 0.3 - 2.0), Color("#3C8CFF")]]:
		var ol := OmniLight3D.new()
		ol.position = L[0]
		ol.light_color = L[1]
		ol.omni_range = 16.0
		ol.light_energy = 0.3 if neutral else 0.9
		add_child(ol)
	var cam := Camera3D.new()
	add_child(cam)
	var mid := Vector3(0, 0.3, (rows - 1) * gap * 0.5 - 2.0)
	if view == "jeu":
		cam.fov = 38
		var p := deg_to_rad(56.0)
		cam.position = mid + Vector3(0, sin(p), cos(p)) * (rows * 2.6 + 6.0)
		cam.look_at(mid)
	else:
		cam.fov = 30
		var span := maxf(cols * gap * 0.62, rows * gap) * (0.8 if only.size() in range(1, 6) else 1.05)
		cam.position = mid + Vector3(0.6, 1.0 + span * 1.25, 1.0 + span * 1.15)
		cam.look_at(mid + Vector3(0, 0, -0.2))
	cam.make_current()
