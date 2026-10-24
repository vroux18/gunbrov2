extends Node3D
## Banc d'essai des objets du quai nord : godot --path . res://tools/decor/bay_look.tscn --write-movie out.png
##   --fixed-fps 10 --quit-after 12 -- --prop=bay_ship [--view=close|front|top] [--dist=8] [--yaw=30]
## Même lumière que le jeu (soleil, ambiance, panorama), matériaux de scripts/decor/hangar_bay.gd.

const Bay = preload("res://scripts/decor/hangar_bay.gd")
const Models = preload("res://scripts/models.gd")

# --scene : tout le quai, monté par hangar_bay.gd avec ce nœud dans le rôle de la vue (view3d.gd)
const K := 1.0 / 64.0
var arena := {"W": 2400.0, "H": 1400.0, "WALL": 36.0, "TOP": 250.0}
var level: Node3D
var _batch := {}

func _mm(mesh: Mesh, xforms: Array, cast: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level.add_child(mmi)
	return mmi

func _ready() -> void:
	var prop := "bay_ship"
	var view := "close"
	var dist := 9.0
	var yaw := 28.0
	var pitch := 22.0
	var h := 0.9
	var tx := 0.0
	var tz := 0.0
	var scene := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--prop="):
			prop = a.trim_prefix("--prop=")
		elif a.begins_with("--view="):
			view = a.trim_prefix("--view=")
		elif a.begins_with("--dist="):
			dist = float(a.trim_prefix("--dist="))
		elif a.begins_with("--yaw="):
			yaw = float(a.trim_prefix("--yaw="))
		elif a.begins_with("--pitch="):
			pitch = float(a.trim_prefix("--pitch="))
		elif a.begins_with("--h="):
			h = float(a.trim_prefix("--h="))
		elif a.begins_with("--x="):
			tx = float(a.trim_prefix("--x="))
		elif a.begins_with("--z="):
			tz = float(a.trim_prefix("--z="))
		elif a == "--scene":
			scene = true
	if view == "game":
		pitch = 56.0
		yaw = 0.0
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/env/space.jpg")
	sky.sky_material = pano
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.58, 0.9)
	e.ambient_light_energy = 0.36
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
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
	add_child(sun)
	var ol := OmniLight3D.new()
	ol.position = Vector3(0, 2.5, -0.1)
	ol.light_color = Color("#FF7A2F")
	ol.omni_range = 9.0
	ol.light_energy = 1.4
	ol.omni_attenuation = 1.4
	add_child(ol)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 20)
	floor.mesh = pm
	floor.material_override = Models.toon(Color("#2C3246"), 0.0)
	add_child(floor)
	if scene:
		level = Node3D.new()
		add_child(level)
		ol.position = Vector3(18.75, 2.5, 1.8)
		floor.position = Vector3(18.75, -0.01, 12.0)
		var rng := RandomNumberGenerator.new()
		Bay.build(self, rng)
		for m in _batch.keys():
			_mm(m, _batch[m], true)
	else:
		add_child(Bay.node(prop))
	var cam := Camera3D.new()
	cam.fov = 38.0 if view == "game" else 32.0
	add_child(cam)
	var target := Vector3(tx, h, tz)
	var dir := Vector3(sin(deg_to_rad(yaw)) * cos(deg_to_rad(pitch)), sin(deg_to_rad(pitch)), cos(deg_to_rad(yaw)) * cos(deg_to_rad(pitch)))
	if view == "game":
		target = Vector3(tx, 0, 5.16)
		dist = 11.5
	cam.position = target + dir * dist
	cam.look_at(target)
	cam.make_current()
