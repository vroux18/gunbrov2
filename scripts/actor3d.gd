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

func set_motion(spd: float, shoot_amount: float) -> void:
	speed = lerpf(speed, spd, 0.25)
	shooting = shoot_amount
	tree.set("parameters/loco/blend_position", speed)
	tree.set("parameters/arms/blend_amount", shooting)

func flash(t: float = 0.09) -> void:
	_flash_t = t
	for mi in meshes:
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
				(mi as MeshInstance3D).material_overlay = null
