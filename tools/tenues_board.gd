extends Node3D
## Planche des apparences de Jo (scripts/loot.gd SKINS, tenues de tools/chars/tenues.py) :
##   --mode=face : face trois quarts, gros plan, quatre apparences par image (--row=0 à 3)
##   --mode=top  : caméra de jeu (56°, recul 11,5, Jo à l'échelle de la partie), de dos puis de face
##   --mode=gear : trois apparences avec équipement (règle tenue / équipement)
## godot --path . res://tools/tenues_board.tscn --write-movie out.png --fixed-fps 10 --quit-after 12 -- --mode=top
## Options : --items=id,id (équipement porté par toutes), --only=id,id (apparences montrées).

const Rig3D = preload("res://scripts/rig3d.gd")
const Models = preload("res://scripts/models.gd")
const Loot = preload("res://scripts/loot.gd")

var cam: Camera3D
var rigs: Array = []
var t := 0.0

func _ready() -> void:
	var mode := "face"
	var items := []
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=")
		elif a.begins_with("--items="):
			for id in a.trim_prefix("--items=").split(","):
				items.append({"id": id, "rarity": 2})
		elif a.begins_with("--only="):
			only = Array(a.trim_prefix("--only=").split(","))
	_env()
	var ids := []
	for s in Loot.SKINS:
		if only.is_empty() or only.has(s["id"]):
			ids.append(String(s["id"]))
	match mode:
		"top":
			cam.fov = 38.0
			var pitch := deg_to_rad(56.0)
			cam.position = Vector3(0, sin(pitch), cos(pitch)) * 11.5
			cam.look_at(Vector3.ZERO, Vector3.UP)
			for row in range(4):
				for i in range(8):
					var k := (row % 2) * 8 + i
					if k >= ids.size():
						continue
					var yaw := PI + 0.35 if row < 2 else 0.5
					_jo(ids[k], Vector3(-5.6 + i * 1.6, 0, -2.85 + row * 1.9), yaw, 1.15, items, row < 2)
		"gear":
			cam.fov = 30.0
			cam.position = Vector3(0, 2.6, 9.0)
			cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
			var sel := ids.slice(0, 4)
			for i in range(sel.size()):
				_jo(sel[i], Vector3(-3.3 + i * 2.2, 0, 0), 0.6, 2.0, items, false)
		_:
			# une rangée de quatre (--row=0 à 3)
			var row := 0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--row="):
					row = int(a.trim_prefix("--row="))
			cam.fov = 30.0
			cam.position = Vector3(0, 2.3, 8.2)
			cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
			var sel := ids.slice(row * 4, row * 4 + 4)
			for i in range(sel.size()):
				_jo(sel[i], Vector3(-2.85 + i * 1.9, 0, 0), 0.55, 1.75, items, false)

func _jo(id: String, pos: Vector3, yaw: float, scl: float, items: Array, shoot: bool) -> void:
	var r := Rig3D.new()
	add_child(r)
	r.setup("res://assets/chars3d/jo.glb", Color(1, 1, 1), 1.7)
	r.make_hero(Color(0.5, 1.0, 0.94), 0.007, Color(1.0, 0.22, 0.28))
	r.position = pos
	r.rotation.y = yaw
	r.scale = Vector3.ONE * scl
	if not items.is_empty():
		r.apply_items(items)
	r.show_palette(Loot.skin_palette(id))
	r._jo_gest_cd = 99.0
	r._jo_look_cd = 99.0
	r.set_meta("shoot", shoot)
	rigs.append(r)
	var sh := Models.shadow_blob(1.1 * scl / 1.75)
	sh.position = pos + Vector3(0, 0.02, 0)
	add_child(sh)
	var l := Label3D.new()
	l.text = String(Loot.skin(id)["name"])
	l.font_size = 40
	l.pixel_size = 0.006 * scl / 1.75
	l.outline_size = 8
	l.position = pos + Vector3(0, -0.02, 0.75 * scl / 1.75)
	l.rotation.x = -PI * 0.5 if cam.fov > 35.0 else 0.0
	l.no_depth_test = true
	l.modulate = Loot.TIER_COLORS[int(Loot.skin(id)["tier"])]
	add_child(l)

func _env() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0B1226")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.58, 0.9)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 28, 0)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	add_child(sun)
	var key := DirectionalLight3D.new()  # comme la lumière d'appoint de Jo en partie (calque HERO_LAYER)
	key.rotation_degrees = Vector3(-35, 0, 0)
	key.light_energy = 0.45
	key.light_cull_mask = Rig3D.HERO_LAYER
	add_child(key)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 40)
	floor.mesh = pm
	floor.material_override = Models.toon(Color("#2C3050"), 0.0)
	add_child(floor)
	cam = Camera3D.new()
	add_child(cam)

func _process(dt: float) -> void:
	t += dt
	for r in rigs:
		var sh: bool = r.get_meta("shoot")
		r.set_motion(0.0, 1.0 if sh else 0.0)
