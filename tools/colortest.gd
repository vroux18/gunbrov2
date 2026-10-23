extends Node3D
func _ready() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.2, 0.2)
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = e
	add_child(we)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.2, 0.2, 0.2)
	q.material_override = m
	q.position = Vector3(-0.6, 0, -2)
	add_child(q)
	var cl := CanvasLayer.new()
	add_child(cl)
	var r := ColorRect.new()
	r.color = Color(0.2, 0.2, 0.2)
	r.position = Vector2(900, 100)
	r.size = Vector2(200, 200)
	cl.add_child(r)
