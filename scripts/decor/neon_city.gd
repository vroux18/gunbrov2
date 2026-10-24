extends RefCounted
## Cité Néon — la ville en contrebas, vue par-dessus les parapets : immeubles voisins plus bas que le toit,
## avenues où file la circulation, brume rose (maillage tools/decor/neon_shell_city.py, shader neon_city).
## Le ciel lui-même (panorama assets/decor/neon/shell/neon_sky.png) est posé par neon_world.env().

const NS := "res://assets/decor/neon/shell/"

static func build(v: Node) -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/neon_city.gdshader")
	var scn: Node = (load(NS + "city.glb") as PackedScene).instantiate()
	for mi in scn.find_children("*", "MeshInstance3D", true, false):
		var out := MeshInstance3D.new()
		out.mesh = (mi as MeshInstance3D).mesh
		out.material_override = m
		out.layers = 2
		out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.lod_bias = 100.0
		(v.level as Node3D).add_child(out)
	scn.free()

static func tris() -> int:
	var n := 0
	var scn: Node = (load(NS + "city.glb") as PackedScene).instantiate()
	for mi in scn.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in range(mesh.get_surface_count()):
			n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	scn.free()
	return n
