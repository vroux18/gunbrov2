extends Node3D
## Planche de Jo : modèles côte à côte, chacun de face trois quarts et de dos (et de profil avec --side).
## godot --path . res://tools/jo_board.tscn --write-movie out.png --fixed-fps 10 --quit-after 12 -- --models=jo,concept_anneau
## Options : --models=nom,nom (assets/chars3d/<nom>.glb) ou --skins=id,id (apparences de scripts/loot.gd, sur Jo) ;
## --labels=texte|texte ; --run (court en tirant) ; --items=id,id (équipement porté).

const Rig3D = preload("res://scripts/rig3d.gd")
const Models = preload("res://scripts/models.gd")
const Loot = preload("res://scripts/loot.gd")

var cam: Camera3D
var rigs: Array = []
var t := 0.0
var run := false

func _ready() -> void:
	var models := []
	var skins := []
	var labels := []
	var items := []
	var side := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--models="):
			models = Array(a.trim_prefix("--models=").split(","))
		elif a.begins_with("--skins="):
			skins = Array(a.trim_prefix("--skins=").split(","))
		elif a.begins_with("--labels="):
			labels = Array(a.trim_prefix("--labels=").split("|"))
		elif a.begins_with("--items="):
			for id in a.trim_prefix("--items=").split(","):
				items.append({"id": id, "rarity": 2})
		elif a == "--run":
			run = true
		elif a == "--side":
			side = true
	_env()
	var entries := []
	for m in models:
		entries.append({"model": "res://assets/chars3d/%s.glb" % m, "skin": ""})
	for s in skins:
		entries.append({"model": "res://assets/chars3d/jo.glb", "skin": s})
	var views := [0.6, PI + 0.5]
	if side:
		views = [0.6, PI * 0.5, PI + 0.5]
	var n := entries.size() * views.size()
	var gap := 1.1
	var w := (n - 1) * gap
	cam.fov = 24.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	var dist := maxf(7.6, w * 1.4 + 3.4)
	cam.position = Vector3(0, 1.6, dist)
	cam.look_at(Vector3(0, 0.98, 0), Vector3.UP)
	var i := 0
	for ei in range(entries.size()):
		var e: Dictionary = entries[ei]
		for yaw in views:
			var x := -w * 0.5 + i * gap
			_jo(e, Vector3(x, 0, 0), yaw, items)
			i += 1
		if ei < labels.size():
			var l := Label3D.new()
			l.text = labels[ei]
			l.font = load("res://assets/fonts/RussoOne-Regular.ttf")
			l.font_size = 64
			l.pixel_size = 0.005
			l.outline_size = 14
			l.position = Vector3(-w * 0.5 + (i - views.size() * 0.5 - 0.5) * gap, -0.22, 0.6)
			l.no_depth_test = true
			add_child(l)

func _jo(e: Dictionary, pos: Vector3, yaw: float, items: Array) -> void:
	var r := Rig3D.new()
	add_child(r)
	r.setup(e["model"], Color(1, 1, 1), 1.7)
	r.make_hero(Color(0.5, 1.0, 0.94), 0.007, Color(1.0, 0.22, 0.28))
	r.position = pos
	r.rotation.y = yaw
	r.scale = Vector3.ONE * 1.6
	if not items.is_empty():
		r.apply_items(items)
	if String(e["skin"]) != "":
		r.show_palette(Loot.skin_palette(String(e["skin"])))
	r._jo_gest_cd = 99.0
	r._jo_look_cd = 99.0
	rigs.append(r)
	var sh := Models.shadow_blob(1.0)
	sh.position = pos + Vector3(0, 0.02, 0)
	add_child(sh)

func _env() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#141B33")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.9)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.4
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 28, 0)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 180, 0)
	key.light_energy = 0.35
	key.light_cull_mask = Rig3D.HERO_LAYER
	add_child(key)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 40)
	floor.mesh = pm
	floor.material_override = Models.toon(Color("#2C3050"), 0.0)
	add_child(floor)
	cam = Camera3D.new()
	add_child(cam)

func _process(dt: float) -> void:
	t += dt
	for r in rigs:
		r.set_motion(0.9 if run else 0.0, 1.0 if run else 0.0)
		r.set_move(Vector3(sin(r.rotation.y), 0, cos(r.rotation.y)) * 0.9 if run else Vector3.ZERO)
