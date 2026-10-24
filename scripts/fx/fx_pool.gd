extends RefCounted
## Réserve d'effets en MultiMesh : un seul nœud, un seul appel de dessin, aucun nœud créé par effet.
## Mode anneau (`put`) : chaque émission écrit une instance à la suite et la carte graphique anime la
## particule à partir de son âge (shaders/fx_*.gdshader) ; une instance est réécrite quand l'anneau revient
## sur elle. Mode image (`put_at` + `show`) : instances réécrites à chaque image (traînées des projectiles).
## Données d'instance : colonnes de la base = c0, c1, c2, origine = c3, plus couleur et données libres.

var mmi: MultiMeshInstance3D
var mm: MultiMesh
var mat: ShaderMaterial
var cap := 0
var head := 0

func _init(parent: Node, mesh: Mesh, shader: Shader, capacity: int, params: Dictionary = {}, priority: int = 0, per_frame: bool = false) -> void:
	cap = capacity
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = cap
	# boîte fixe : la position réelle est calculée par le shader, le moteur ne doit ni la recalculer ni trier
	mm.custom_aabb = AABB(Vector3(-15, -10, -15), Vector3(70, 40, 60))
	var dead := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3(-1000.0, 0.0, 0.0)), Vector3.ZERO)
	for i in range(cap):
		mm.set_instance_transform(i, dead)
		mm.set_instance_color(i, Color(0, 0, 0, 0))
		mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	mm.visible_instance_count = 0 if per_frame else cap
	mat = ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = priority
	for k in params:
		mat.set_shader_parameter(k, params[k])
	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = mm.custom_aabb
	parent.add_child(mmi)

func put(c0: Vector3, c1: Vector3, c2: Vector3, c3: Vector3, col: Color, cust: Color) -> void:
	put_at(head, c0, c1, c2, c3, col, cust)
	head = (head + 1) % cap

func put_at(i: int, c0: Vector3, c1: Vector3, c2: Vector3, c3: Vector3, col: Color, cust: Color) -> void:
	mm.set_instance_transform(i, Transform3D(Basis(c0, c1, c2), c3))
	mm.set_instance_color(i, col)
	mm.set_instance_custom_data(i, cust)

func show(n: int) -> void:
	mm.visible_instance_count = mini(n, cap)

func set_time(t: float) -> void:
	mat.set_shader_parameter("fx_time", t)
