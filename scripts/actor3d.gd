extends Node3D
## Personnage Kenney (Mini Characters, CC0) animé : jambes sur la locomotion (repos, marche, course),
## bras sur « tenir l'arme » ou « tirer », arme accrochée à la main droite, flash de coup, mort.

const Models = preload("res://scripts/models.gd")

var model: Node3D
var ap: AnimationPlayer
var tree: AnimationTree
var skel: Skeleton3D
var gun: Node3D
var muzzle: Node3D
var meshes: Array = []
var speed := 0.0  # 0 repos, 0.5 marche, 1 course
var shooting := 0.0
var dead := false
var _flash_t := 0.0
var _flash_mat: StandardMaterial3D
var _tint: Color = Color.WHITE

static var _looped := {}

func setup(char_path: String, gun_path: String, tint: Color = Color.WHITE) -> void:
	model = Models.scene(char_path).instantiate()
	add_child(model)
	ap = model.find_children("*", "AnimationPlayer", true, false)[0]
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	meshes = Models.meshes(model)
	_tint = tint
	if tint != Color.WHITE:
		for mi in meshes:
			var m: MeshInstance3D = mi
			for s in range(m.mesh.get_surface_count()):
				var base: Material = m.mesh.surface_get_material(s)
				if base is StandardMaterial3D:
					var dup: StandardMaterial3D = base.duplicate()
					dup.albedo_color = tint
					m.set_surface_override_material(s, dup)
	# boucles (les animations Kenney sont livrées sans boucle)
	for an in ["idle", "walk", "sprint", "holding-right", "holding-right-shoot", "holding-both", "holding-both-shoot"]:
		if ap.has_animation(an):
			var a: Animation = ap.get_animation(an)
			a.loop_mode = Animation.LOOP_LINEAR
	_build_tree()
	if gun_path != "":
		var att := BoneAttachment3D.new()
		att.bone_name = "arm-right"
		skel.add_child(att)
		gun = Models.scene(gun_path).instantiate()
		_gun_path = gun_path
		gun.scale = Vector3.ONE * 0.55
		# l'arme Kenney pointe vers -Z ; le bras tendu de « holding-right » pointe vers +Z (l'avant du personnage)
		gun.rotation_degrees = Vector3(0, 180, 0)
		gun.position = Vector3(-0.02, -0.12, 0.08)
		att.add_child(gun)
		muzzle = Node3D.new()
		muzzle.position = Vector3(0, 0.05, -0.38)
		gun.add_child(muzzle)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1, 1, 1, 0.0)

func _track_prefix() -> String:
	var a: Animation = ap.get_animation("walk")
	var p := str(a.track_get_path(0))
	return p.substr(0, p.find(":"))

func _build_tree() -> void:
	tree = AnimationTree.new()
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(ap)
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	for pair in [["idle", 0.0], ["walk", 0.5], ["sprint", 1.0]]:
		var n := AnimationNodeAnimation.new()
		n.animation = pair[0]
		loco.add_blend_point(n, pair[1], -1, StringName(pair[0]))
	bt.add_node("loco", loco, Vector2(0, 0))
	var hold := AnimationNodeAnimation.new()
	hold.animation = "holding-right"
	bt.add_node("hold", hold, Vector2(0, 200))
	var shoot := AnimationNodeAnimation.new()
	shoot.animation = "holding-right-shoot"
	bt.add_node("shoot", shoot, Vector2(0, 400))
	var arms := AnimationNodeBlend2.new()
	bt.add_node("arms", arms, Vector2(200, 300))
	bt.connect_node("arms", 0, "hold")
	bt.connect_node("arms", 1, "shoot")
	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	var pre := _track_prefix()
	for b in ["arm-right", "arm-left"]:
		upper.set_filter_path(NodePath(pre + ":" + b), true)
	bt.add_node("upper", upper, Vector2(400, 100))
	bt.connect_node("upper", 0, "loco")
	bt.connect_node("upper", 1, "arms")
	var die := AnimationNodeAnimation.new()
	die.animation = "die"
	bt.add_node("die", die, Vector2(400, 400))
	var dead_blend := AnimationNodeBlend2.new()
	bt.add_node("dead", dead_blend, Vector2(600, 200))
	bt.connect_node("dead", 0, "upper")
	bt.connect_node("dead", 1, "die")
	bt.connect_node("output", 0, "dead")
	tree.tree_root = bt
	tree.active = true
	tree.set("parameters/upper/blend_amount", 1.0)

# ---------------------------------------------------------------- butin visible (le « patchwork » des Passeurs)
const RARITY_GLOW := [Color("#9FB3C8"), Color("#3CF2D8"), Color("#C77DFF"), Color("#FFB347")]
const GUNS := {"blaster_garde": "res://assets/models/blaster/blaster-c.glb", "fusil_impulsion": "res://assets/models/blaster/blaster-f.glb"}
var _gear: Array = []
var _gun_path := ""

func _bone(name: String) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	att.bone_name = name
	skel.add_child(att)
	_gear.append(att)
	return att

func _gun_swap(path: String) -> void:
	if gun == null or path == _gun_path:
		return
	var parent := gun.get_parent()
	var keep_xf := gun.transform
	parent.remove_child(gun)
	gun.queue_free()
	gun = Models.scene(path).instantiate()
	gun.transform = keep_xf
	parent.add_child(gun)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0.05, -0.38)
	gun.add_child(muzzle)
	_gun_path = path
	meshes = Models.meshes(model)

## Équipement de base des Passeurs : sac de saut à lumière cyan et oreillette (silhouette reconnaissable).
var _kit: Array = []
func passeur_kit() -> void:
	var t := BoneAttachment3D.new()
	t.bone_name = "torso"
	skel.add_child(t)
	var pack := Models.box(Vector3(0.22, 0.2, 0.1), Models.toon(Color("#F4F1EA"), 0.45))
	pack.position = Vector3(0, 0.07, -0.14)
	t.add_child(pack)
	var stripe := Models.box(Vector3(0.23, 0.04, 0.105), Models.toon(Color("#FF7A2F"), 0.3))
	stripe.position = Vector3(0, 0.12, -0.14)
	t.add_child(stripe)
	for x in [-0.06, 0.06]:
		var jet := Models.cyl(0.035, 0.04, 0.08, Models.glow_mat(Color("#3CF2D8"), 2.4), 10)
		jet.position = Vector3(x, -0.04, -0.19)
		t.add_child(jet)
	var h := BoneAttachment3D.new()
	h.bone_name = "head"
	skel.add_child(h)
	var ear := Models.box(Vector3(0.05, 0.09, 0.08), Models.toon(Color("#2C3350"), 0.3))
	ear.position = Vector3(0.18, 0.12, 0.0)
	h.add_child(ear)
	var mic := Models.box(Vector3(0.02, 0.02, 0.12), Models.glow_mat(Color("#3CF2D8"), 2.0))
	mic.position = Vector3(0.17, 0.07, 0.08)
	h.add_child(mic)
	_kit = [t, h]
	meshes = Models.meshes(model)

## Équipe visuellement les objets (instances {id, rarity}) : casque, plastron, bottes, sac, module, arme.
func apply_items(items: Array, default_gun: String) -> void:
	for g in _gear:
		var gn: Node = g
		gn.get_parent().remove_child(gn)
		gn.queue_free()
	_gear.clear()
	var gun_path := default_gun
	for it in items:
		var id := String(it["id"])
		var glow: Color = RARITY_GLOW[clampi(int(it["rarity"]), 0, 3)]
		var gm := Models.glow_mat(glow, 2.2)
		match id:
			"blaster_garde", "fusil_impulsion":
				gun_path = GUNS[id]
			"visiere":
				var h := _bone("head")
				var band := Models.box(Vector3(0.36, 0.08, 0.36), Models.toon(Color("#2C3350"), 0.3))
				band.position = Vector3(0, 0.2, 0.0)
				h.add_child(band)
				var vis := Models.box(Vector3(0.3, 0.07, 0.05), gm)
				vis.position = Vector3(0, 0.2, 0.19)
				h.add_child(vis)
			"casque_garde":
				var h := _bone("head")
				var dome := Models.sphere(0.21, Models.toon(Color("#E8ECF2"), 0.5))
				dome.scale = Vector3(1.05, 0.9, 1.05)
				dome.position = Vector3(0, 0.2, -0.01)
				h.add_child(dome)
				var vis := Models.box(Vector3(0.3, 0.06, 0.06), gm)
				vis.position = Vector3(0, 0.17, 0.2)
				h.add_child(vis)
			"plastron":
				var t := _bone("torso")
				var plate := Models.box(Vector3(0.3, 0.17, 0.06), Models.toon(Color("#8A939E"), 0.45))
				plate.position = Vector3(0, 0.08, 0.13)
				t.add_child(plate)
				var trim := Models.box(Vector3(0.31, 0.03, 0.065), gm)
				trim.position = Vector3(0, 0.14, 0.13)
				t.add_child(trim)
			"veste":
				var t := _bone("torso")
				var collar := Models.box(Vector3(0.32, 0.06, 0.26), Models.toon(Color("#FF7A2F"), 0.35))
				collar.position = Vector3(0, 0.16, 0.0)
				t.add_child(collar)
				var stripe := Models.box(Vector3(0.04, 0.16, 0.27), gm)
				stripe.position = Vector3(0.1, 0.06, 0.0)
				t.add_child(stripe)
			"bottes", "jambieres":
				for b in ["leg-left", "leg-right"]:
					var l := _bone(b)
					var boot := Models.box(Vector3(0.12, 0.08, 0.15), Models.toon(Color("#2C3350") if id == "bottes" else Color("#C8D0DA"), 0.4))
					boot.position = Vector3(0, -0.13 if id == "bottes" else -0.07, 0.02)
					l.add_child(boot)
					var led := Models.box(Vector3(0.125, 0.025, 0.155), gm)
					led.position = Vector3(0, -0.1 if id == "bottes" else -0.04, 0.02)
					l.add_child(led)
			"pile", "aimant":
				var t := _bone("torso")
				var pack := Models.box(Vector3(0.24, 0.24, 0.12), Models.toon(Color("#3A4670"), 0.35))
				pack.position = Vector3(0, 0.06, -0.15)
				t.add_child(pack)
				if id == "pile":
					var cell := Models.cyl(0.05, 0.05, 0.2, gm, 10)
					cell.position = Vector3(0.0, 0.07, -0.23)
					t.add_child(cell)
				else:
					var ring := Models.torus(0.07, 0.1, gm)
					ring.rotation.x = PI * 0.5
					ring.position = Vector3(0, 0.08, -0.23)
					t.add_child(ring)
			"module_canon", "cellule":
				var sh := _bone("arm-left")
				var mod := Models.box(Vector3(0.12, 0.12, 0.16), Models.toon(Color("#5A6470"), 0.4))
				mod.position = Vector3(0.04, 0.02, 0.0)
				sh.add_child(mod)
				var tip := Models.box(Vector3(0.05, 0.05, 0.06), gm)
				tip.position = Vector3(0.04, 0.02, 0.1)
				sh.add_child(tip)
	_gun_swap(gun_path)
	meshes = Models.meshes(model)

func set_motion(spd: float, shoot_amount: float) -> void:
	speed = lerpf(speed, spd, 0.25)
	shooting = shoot_amount
	tree.set("parameters/loco/blend_position", speed)
	tree.set("parameters/arms/blend_amount", shooting)

func flash(t: float = 0.09) -> void:
	_flash_t = t
	for mi in meshes:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = _flash_mat

func die() -> void:
	if dead:
		return
	dead = true
	tree.active = false
	ap.play("die")

func muzzle_position() -> Vector3:
	return muzzle.global_position if muzzle != null else global_position + Vector3(0, 0.6, 0)

func _process(dt: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= dt
		_flash_mat.albedo_color = Color(1.6, 1.6, 1.6, clampf(_flash_t * 10.0, 0.0, 0.85))
		if _flash_t <= 0.0:
			for mi in meshes:
				if is_instance_valid(mi):
					(mi as MeshInstance3D).material_overlay = null
