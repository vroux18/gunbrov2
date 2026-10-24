extends Node3D
## Banc d'essai de Jo : vue de jeu (caméra haute à 56°, au milieu de gardes), planche de poses, gros plan.
## godot --path . res://tools/jo_bench.tscn --write-movie out.png --fixed-fps 10 --quit-after 30 -- --mode=top|poses|close
## Options : --ol=<couleur du liseré> --olw=<épaisseur> (0 : sans liseré), --scale=<échelle de Jo en jeu>.

const Rig3D = preload("res://scripts/rig3d.gd")
const Models = preload("res://scripts/models.gd")

var mode := "top"
var ol := Color("#FFE2C4")
var olw := 0.0
var sc := 1.75
var jos: Array = []  # {rig, yaw, move, speed, shoot, ...}
var mobs: Array = []
var t := 0.0
var cam: Camera3D

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=")
		if a.begins_with("--ol="):
			ol = Color(a.trim_prefix("--ol="))
		if a.begins_with("--olw="):
			olw = float(a.trim_prefix("--olw="))
		if a.begins_with("--scale="):
			sc = float(a.trim_prefix("--scale="))
	_env()
	match mode:
		"top":
			_top()
		"poses":
			_poses()
		"run":
			_run()
		_:
			_close()

func _env() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0B1226")
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
	sun.shadow_bias = 0.04
	add_child(sun)
	# sol du hangar : dalles bleu marine à joints sombres
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 40)
	floor.mesh = pm
	floor.material_override = Models.toon(Color("#2C3050"), 0.0)
	add_child(floor)
	for i in range(-14, 15):
		for j in range(-9, 10):
			if (i + j) % 3 == 0:
				var tile := Models.box(Vector3(1.3, 0.01, 1.3), Models.toon(Color("#262A48"), 0.0))
				tile.position = Vector3(i * 2.0, 0.005, j * 2.0)
				add_child(tile)
	# toile de fond sombre derrière les planches
	var back := Models.box(Vector3(80, 30, 0.1), Models.glow_mat(Color("#0B1226"), 1.0))
	back.position = Vector3(0, 10, -20)
	add_child(back)
	cam = Camera3D.new()
	add_child(cam)

func _jo(pos: Vector3, yaw: float, scl: float, cfg: Dictionary) -> Node3D:
	var r := Rig3D.new()
	add_child(r)
	r.setup("res://assets/chars3d/jo.glb", Color(1, 1, 1), 1.7)
	r.make_hero(ol, olw, Color(1.0, 0.25, 0.3))
	r.position = pos
	r.rotation.y = yaw
	r.scale = Vector3.ONE * scl
	if cfg.has("items"):
		r.apply_items(cfg["items"])
	var c := cfg.duplicate()
	c["rig"] = r
	jos.append(c)
	var sh := Models.shadow_blob(1.1 * scl / 1.75)
	sh.position = pos + Vector3(0, 0.02, 0)
	add_child(sh)
	return r

func _mob(kind: String, pos: Vector3, yaw: float) -> void:
	var r: Node3D = load("res://scripts/mobs/%s.gd" % kind).new()
	add_child(r)
	r.setup("res://assets/chars3d/%s.glb" % kind)
	r.position = pos
	r.rotation.y = yaw
	r.scale = Vector3.ONE * (1.3 if kind == "brute" else 1.75)
	mobs.append(r)
	var sh := Models.shadow_blob(1.0)
	sh.position = pos + Vector3(0, 0.02, 0)
	add_child(sh)

## Vue de jeu : Jo au centre (court et tire), d'autres Jo autour sous plusieurs angles, une mêlée de gardes.
func _top() -> void:
	cam.fov = 38.0
	var pitch := deg_to_rad(56.0)
	cam.position = Vector3(0, sin(pitch), cos(pitch)) * 11.5
	cam.look_at(Vector3.ZERO, Vector3.UP)
	_jo(Vector3(0, 0, 0), 0.6, sc, {"speed": 0.85, "shoot": 1.0, "move": Vector3(-0.7, 0, -0.7)})
	_jo(Vector3(-4.2, 0, -1.6), PI, sc, {"speed": 0.85, "shoot": 0.0, "move": Vector3(0, 0, -1)})
	_jo(Vector3(4.2, 0, -1.6), -PI * 0.5, sc, {"speed": 0.0, "shoot": 1.0})
	var hj := _jo(Vector3(-4.6, 0, 2.2), 0.0, sc, {"speed": 0.0, "shoot": 1.0, "hitloop": 1.0})
	var fx: Node3D = load("res://scripts/jo_fx.gd").new()
	add_child(fx)
	fx.setup(hj)
	_jo(Vector3(4.6, 0, 2.2), PI * 0.5, sc, {"speed": 0.85, "shoot": 0.0, "move": Vector3(1, 0, 0)})
	# Jo cachée derrière deux gardes : test de la silhouette « rayons X »
	_jo(Vector3(0.5, 0, -3.6), 0.3, sc, {"speed": 0.0, "shoot": 1.0})
	_mob("brute", Vector3(0.5, 0, -2.75), PI)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in range(18):
		var a := rng.randf() * TAU
		var d := rng.randf_range(1.3, 3.4)
		var p := Vector3(cos(a) * d * 1.5, 0, sin(a) * d)
		var k: String = ["trooper", "trooper", "trooper", "drone", "bomber", "shield"][i % 6]
		_mob(k, p, atan2(-p.x, -p.z))

## Course en cercle sous la caméra de jeu : poussière de pas, traînée des réacteurs, penché dans le virage.
func _run() -> void:
	cam.fov = 38.0
	var pitch := deg_to_rad(56.0)
	cam.position = Vector3(0, sin(pitch), cos(pitch)) * 7.0
	cam.look_at(Vector3.ZERO, Vector3.UP)
	var r := _jo(Vector3(2.2, 0, 0), 0.0, sc, {"speed": 0.9, "shoot": 0.0, "orbit": 2.2})
	var fx: Node3D = load("res://scripts/jo_fx.gd").new()
	add_child(fx)
	fx.setup(r)

## Planche de poses : face 3/4, deux rangées de cinq.
func _poses() -> void:
	cam.fov = 30.0
	cam.position = Vector3(0, 2.6, 12.5)
	cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	var row_only := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--row="):
			row_only = int(a.trim_prefix("--row="))
	var cfgs := [
		{"label": "repos", "speed": 0.0, "shoot": 0.0, "yaw": 0.3},
		{"label": "course", "speed": 0.9, "shoot": 0.0, "yaw": 1.2, "move": Vector3(1, 0, 0.4)},
		{"label": "course + tir", "speed": 0.9, "shoot": 1.0, "yaw": 0.9, "move": Vector3(0.8, 0, 0.6)},
		{"label": "recule en tirant", "speed": 0.9, "shoot": 1.0, "yaw": 0.4, "move": Vector3(-0.4, 0, -1)},
		{"label": "pas chassé", "speed": 0.9, "shoot": 1.0, "yaw": 0.0, "move": Vector3(1, 0, 0)},
		{"label": "coup reçu", "speed": 0.0, "shoot": 1.0, "yaw": 1.1, "hit": 2.0},
		{"label": "victoire", "speed": 0.0, "shoot": 0.0, "yaw": 0.2, "cheer": 1.1},
		{"label": "geste : blaster", "speed": 0.0, "shoot": 0.0, "yaw": 0.2, "gest": [0, 0.9]},
		{"label": "geste : salut", "speed": 0.0, "shoot": 0.0, "yaw": 0.0, "gest": [1, 0.75]},
		{"label": "geste : radio", "speed": 0.0, "shoot": 0.0, "yaw": 0.3, "gest": [2, 0.9]},
	]
	for i in range(cfgs.size()):
		var row := i / 5
		var col := i % 5
		if row != row_only:
			continue
		var pos := Vector3(-4.4 + col * 2.2, 0, 0)
		var c: Dictionary = cfgs[i]
		_jo(pos, c["yaw"], 1.75, c)
		var l := Label3D.new()
		l.text = c["label"]
		l.font_size = 48
		l.pixel_size = 0.006
		l.outline_size = 10
		l.position = pos + Vector3(0, -0.05, 1.1)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		add_child(l)

## Gros plan : quatre vues (face, trois quarts, profil, dos) à l'échelle du Relais.
func _close() -> void:
	cam.fov = 30.0
	cam.position = Vector3(0, 2.6, 9.0)
	cam.look_at(Vector3(0, 1.1, 0), Vector3.UP)
	var stuff := "--stuff" in OS.get_cmdline_user_args()
	var items := [{"id": "casque_garde", "rarity": 2}, {"id": "plastron", "rarity": 1}, {"id": "bottes", "rarity": 3}, {"id": "pile", "rarity": 1}, {"id": "fusil_impulsion", "rarity": 2}, {"id": "module_canon", "rarity": 0}] if stuff else []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--items="):
			items = []
			for id in a.trim_prefix("--items=").split(","):
				items.append({"id": id, "rarity": items.size() % 4})
	for i in range(4):
		var c := {"speed": 0.0, "shoot": 1.0 if i == 1 else 0.0, "yaw": [0.0, 0.7, PI * 0.5, PI][i], "calm": true}
		if not items.is_empty():
			c["items"] = items
		_jo(Vector3(-3.3 + i * 2.2, 0, 0), c["yaw"], 2.0, c)

func _process(dt: float) -> void:
	t += dt
	for c in jos:
		var r = c["rig"]
		if c.has("orbit"):
			var rad: float = c["orbit"]
			var w := 3.4 / rad
			var a := t * w
			r.position = Vector3(cos(a), 0, -sin(a)) * rad
			var d := Vector3(-sin(a), 0, -cos(a))
			c["move"] = d
			r.rotation.y = atan2(d.x, d.z)
		r.set_motion(c.get("speed", 0.0), c.get("shoot", 0.0))
		var mv: Vector3 = c.get("move", Vector3.ZERO)
		r.set_move(mv.normalized() * 0.9 if mv != Vector3.ZERO else Vector3.ZERO)
		if c.has("hit") and absf(t - float(c["hit"])) < dt * 0.5:
			r.hit(1.0)
			r.flash(0.22)
		if c.has("cheer") and absf(t - float(c["cheer"])) < dt * 0.5:
			r.cheer()
		if c.has("gest"):
			var g: Array = c["gest"]
			if absf(t - (2.0 - float(g[1]))) < dt * 0.5:
				r.gesture(int(g[0]))
		if c.has("hitloop") and int((t + 0.15) / c["hitloop"]) != int((t + 0.15 - dt) / c["hitloop"]):
			r.hit(1.0)
			r.flash(0.22)
		if c.has("calm"):
			r._jo_gest_cd = 99.0
			r._jo_look_cd = 99.0
		if c.get("shoot", 0.0) > 0.5 and int(t * 6.0) != int((t - dt) * 6.0):
			r.fire()
	for m in mobs:
		m.set_motion(0.5, 0.0)
