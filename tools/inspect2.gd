extends SceneTree
func _tree(n: Node, d: int) -> void:
	print("  ".repeat(d), n.name, " <", n.get_class(), ">", (" pos=" + str(n.position) + " rot=" + str(n.rotation_degrees) + " sc=" + str(n.scale)) if n is Node3D else "")
	for c in n.get_children():
		_tree(c, d + 1)
func _init() -> void:
	var n: Node = load("res://assets/models/chars/character-female-a.glb").instantiate()
	_tree(n, 0)
	var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0]
	for an in ["walk", "holding-right-shoot", "holding-right", "idle", "die"]:
		var a := ap.get_animation(an)
		var tr := []
		for i in range(a.get_track_count()):
			tr.append(str(a.track_get_path(i)) + ":" + str(a.track_get_type(i)))
		print(an, " loop=", a.loop_mode, " ", tr)
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	for i in range(sk.get_bone_count()):
		print(sk.get_bone_name(i), " rest=", sk.get_bone_rest(i).origin, " parent=", sk.get_bone_parent(i))
	var b: Node = load("res://assets/models/blaster/blaster-a.glb").instantiate()
	_tree(b, 0)
	quit()
