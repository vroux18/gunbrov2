extends Node3D
const Models = preload("res://scripts/models.gd")
func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0B1020")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.62, 0.9)
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 28, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)
	var list := ["station/container.glb", "station/container-flat.glb", "station/container-tall.glb", "station/container-wide.glb", "station/container-flat-open.glb", "station/structure.glb", "station/structure-barrier.glb", "station/structure-panel.glb", "station/computer-system.glb", "station/skip.glb", "blaster/crate-medium.glb", "blaster/crate-small.glb", "blaster/crate-wide.glb", "space/barrels.glb", "space/machine_generator.glb", "station/rail.glb", "station/wall.glb", "station/wall-window.glb", "station/wall-pillar.glb", "station/floor-panel.glb", "station/floor.glb", "station/display-wall.glb", "station/table-display-planet.glb", "space/craft_cargoA.glb"]
	for i in range(list.size()):
		var n := Models.inst("res://assets/models/" + list[i], true)
		n.position = Vector3((i % 8) * 2.0 - 7.0, 0, int(i / 8) * 2.4 - 2.4)
		add_child(n)
		var l := Label3D.new()
		l.text = list[i].get_file().get_basename()
		l.position = n.position + Vector3(0, 0.02, 0.9)
		l.rotation_degrees.x = -90
		l.font_size = 28
		add_child(l)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.position = Vector3(0, 9, 9)
	cam.look_at(Vector3(0, 0, 0.3))
	cam.make_current()
