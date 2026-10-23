extends SceneTree
## Outil : affiche la taille, l'ossature et les animations des modèles (godot --headless --script tools/inspect.gd).

func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is MeshInstance3D and n.mesh:
		var a: AABB = (xf * n.transform) * n.mesh.get_aabb()
		out = a
		first = false
	for c in n.get_children():
		if c is Node3D:
			var b := _aabb(c, xf * (n.transform if n is Node3D else Transform3D.IDENTITY))
			if b.size != Vector3.ZERO:
				out = b if first else out.merge(b)
				first = false
	return out

func _init() -> void:
	var files := ["res://assets/models/chars/character-female-a.glb", "res://assets/models/station/container.glb",
		"res://assets/models/station/floor.glb", "res://assets/models/station/wall.glb", "res://assets/models/station/floor-panel.glb",
		"res://assets/models/space/turret_single.glb", "res://assets/models/space/craft_cargoA.glb", "res://assets/models/blaster/blaster-a.glb",
		"res://assets/models/station/computer.glb", "res://assets/models/station/display-wall.glb"]
	for f in files:
		var ps: PackedScene = load(f)
		var inst := ps.instantiate()
		print("== ", f, "  aabb=", _aabb(inst, Transform3D.IDENTITY))
		var sk: Skeleton3D = inst.find_child("*", true, false) as Skeleton3D
		for s in inst.find_children("*", "Skeleton3D", true, false):
			var names := []
			for i in range(s.get_bone_count()):
				names.append(s.get_bone_name(i))
			print("   bones: ", names)
		for ap in inst.find_children("*", "AnimationPlayer", true, false):
			var lst := []
			for a in ap.get_animation_list():
				lst.append("%s(%.2f)" % [a, ap.get_animation(a).length])
			print("   anims: ", ", ".join(lst))
		inst.free()
	quit()
