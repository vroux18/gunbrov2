extends Node
## Banc de prise de vue du décor de la coque : lance le jeu normal puis filme avec une caméra libre.
## godot --path . res://tools/decor/shell_look.tscn -- --autoplay --hero=300,800 --cam=x,y,z,cx,cy,cz[,fov]
## --stats : affiche chaque seconde les images par seconde, appels de dessin, objets et primitives.

var cam: Camera3D
var pose := []
var stats := false
var _acc := 0.0

func _ready() -> void:
	process_priority = 1000
	add_child(load("res://scenes/main.tscn").instantiate())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			for s in a.trim_prefix("--cam=").split(","):
				pose.append(float(s))
	stats = "--stats" in OS.get_cmdline_user_args()
	cam = Camera3D.new()
	cam.fov = pose[6] if pose.size() > 6 else 40.0
	cam.near = 0.05
	cam.far = 200.0
	add_child(cam)

func _process(dt: float) -> void:
	_acc += dt
	if stats and _acc >= 1.0:
		_acc = 0.0
		print("STATS fps=%d draw=%d obj=%d prim=%d" % [Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	if pose.size() < 6:
		return
	cam.position = Vector3(pose[0], pose[1], pose[2])
	cam.look_at(Vector3(pose[3], pose[4], pose[5]), Vector3.UP)
	cam.make_current()
