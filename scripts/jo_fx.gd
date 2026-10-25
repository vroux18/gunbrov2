extends Node3D
## Effets propres à Jo en jeu : poussière sous les pas, traînée des réacteurs du sac en course, réacteurs
## qui s'allument avec la vitesse. Deux MultiMesh de quads face caméra (un appel de dessin chacun), en
## coordonnées du monde, au plus 64 particules. Le nœud lit l'état du rig ; il ne pilote rien.

const Models = preload("res://scripts/models.gd")
const DUST_N := 24
const JET_N := 40
## Points d'émission dans le repère des parts (voir tools/chars/jo.py).
const NOZZLES := [Vector3(-0.1505, -0.01, -0.2), Vector3(0.1505, -0.01, -0.2)]  # repère « torso »
const FOOT := Vector3(0.0, -0.33, 0.03)  # repère « leg_r » / « leg_l »

var rig: Node3D
var _dust: MultiMeshInstance3D
var _jet: MultiMeshInstance3D
var _dp: Array = []  # {pos, vel, life, max, size}
var _jp: Array = []
var _jet_acc := 0.0
var _last_s := 0.0
var _nozzle_mat: StandardMaterial3D = null
var _burst_cd := 0.0
var _shock: MeshInstance3D  # onde rouge au sol quand Jo est touchée
var _shock_mat: ShaderMaterial
var _shock_t := 1.0
var _last_hit := 0.0

func setup(r: Node3D) -> void:
	rig = r
	top_level = true
	var shader: Shader = load("res://shaders/glow_billboard.gdshader")
	_dust = _mm(DUST_N, shader, 0.85)
	_jet = _mm(JET_N, shader, 2.2)
	_shock = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	_shock.mesh = pm
	_shock_mat = ShaderMaterial.new()
	_shock_mat.shader = load("res://shaders/ground_ring.gdshader")
	_shock_mat.set_shader_parameter("color", Color(1.0, 0.3, 0.38))
	_shock_mat.set_shader_parameter("width", 0.16)
	_shock_mat.set_shader_parameter("fill", 0.12)
	_shock.material_override = _shock_mat
	_shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shock.visible = false
	add_child(_shock)
	# réacteurs : matériau à eux, plus lumineux en course
	var g: Node3D = rig.p("torso_glow")
	if g is MeshInstance3D:
		_nozzle_mat = (rig.glow_mat(1.7) as StandardMaterial3D).duplicate()
		(g as MeshInstance3D).material_override = _nozzle_mat

func _mm(n: int, shader: Shader, energy: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = n
	mm.visible_instance_count = 0
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("tex", Models.radial())
	m.set_shader_parameter("energy", energy)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 50.0
	add_child(mmi)
	return mmi

func _world(part: String, local: Vector3) -> Vector3:
	var n: Node3D = rig.p(part)
	return n.global_transform * local if n != null else rig.global_position

func _puff(pos: Vector3, vel: Vector3, size: float, life: float) -> void:
	if _dp.size() >= DUST_N:
		_dp.pop_front()
	_dp.append({"pos": pos, "vel": vel, "life": life, "max": life, "size": size})

func _process(dt: float) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var live: bool = rig.is_visible_in_tree() and not rig.dead
	var spd: float = rig.speed
	var running := live and spd > 0.3
	# --- poussière : une bouffée à chaque pied posé, une gerbe au départ et à l'arrêt
	var s := sin(float(rig.phase))
	if running and signf(s) != signf(_last_s):
		var leg := "leg_l" if s > 0.0 else "leg_r"
		var p := _world(leg, FOOT)
		p.y = 0.06
		for i in range(2):
			var a := randf() * TAU
			_puff(p + Vector3(cos(a), 0, sin(a)) * 0.06, Vector3(cos(a) * 0.6, 0.4, sin(a) * 0.6), randf_range(0.3, 0.42), 0.45)
	_last_s = s
	_burst_cd -= dt
	var acc: Vector3 = rig._jo_acc
	if live and acc.length() > 4.0 and _burst_cd <= 0.0:
		_burst_cd = 0.35
		var base := rig.global_position + Vector3(0, 0.06, 0)
		var back := -acc.normalized()
		for i in range(4):
			var a := randf() * TAU
			var v := Vector3(cos(a), 0, sin(a)) * 0.45 + back * 0.6 + Vector3(0, 0.3, 0)
			_puff(base + Vector3(cos(a), 0, sin(a)) * 0.12, v, randf_range(0.28, 0.4), 0.5)
	# --- réacteurs : traînée de braises turquoise en course, lueur plus vive
	if _nozzle_mat != null:
		var e := 1.7 + 2.6 * clampf(spd, 0.0, 1.0) * (0.85 + 0.15 * sin(rig.t * 40.0)) if live else 1.7
		_nozzle_mat.albedo_color = Color(e, e, e)
	if running and _nozzle_mat != null:  # seulement si le modèle a des réacteurs (part « torso_glow »)
		_jet_acc += dt * 44.0 * clampf(spd, 0.0, 1.0)
		var torso: Node3D = rig.p("torso")
		var down := -torso.global_transform.basis.y.normalized() if torso != null else Vector3.DOWN
		var backv := -rig.global_transform.basis.z.normalized()
		while _jet_acc >= 1.0:
			_jet_acc -= 1.0
			var nz: Vector3 = NOZZLES[randi() % 2]
			var p := _world("torso", nz)
			if _jp.size() >= JET_N:
				_jp.pop_front()
			var v := down * 1.6 + backv * 0.6 + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))
			_jp.append({"pos": p, "vel": v, "life": 0.32, "max": 0.32, "size": randf_range(0.2, 0.28)})
	# --- coup reçu : onde rouge qui s'élargit sous Jo
	var h: float = rig._jo_hit_t
	if h > _last_hit + 0.5:
		_shock_t = 0.0
	_last_hit = h
	_shock_t += dt
	var k := clampf(_shock_t / 0.32, 0.0, 1.0)
	_shock.visible = k < 1.0 and live
	if _shock.visible:
		var sz := lerpf(0.9, 2.6, 1.0 - (1.0 - k) * (1.0 - k))
		_shock.global_transform = Transform3D(Basis().scaled(Vector3(sz, 1, sz)), rig.global_position + Vector3(0, 0.04, 0))
		_shock_mat.set_shader_parameter("color", Color(1.0, 0.3, 0.38, 1.0 - k))
	# --- mise à jour et dessin
	_draw(_dust.multimesh, _dp, dt, Color(0.72, 0.76, 1.0), 0.42, 1.0, 0.4)
	_draw(_jet.multimesh, _jp, dt, Color(0.24, 0.95, 0.85), 0.9, 0.35, 6.0)

func _draw(mm: MultiMesh, ps: Array, dt: float, col: Color, alpha: float, grow_to: float, drag: float) -> void:
	var i := 0
	while i < ps.size():
		var q: Dictionary = ps[i]
		q["life"] -= dt
		if q["life"] <= 0.0:
			ps.remove_at(i)
			continue
		q["vel"] *= maxf(0.0, 1.0 - drag * dt)
		q["pos"] += q["vel"] * dt
		if q["pos"].y < 0.04:
			q["pos"].y = 0.04
		i += 1
	var n := mini(ps.size(), mm.instance_count)
	for k in range(n):
		var q: Dictionary = ps[k]
		var a: float = clampf(q["life"] / q["max"], 0.0, 1.0)
		var sz: float = q["size"] * lerpf(grow_to, 1.0, a) if grow_to < 1.0 else q["size"] * lerpf(1.6, 1.0, a)
		mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(sz, sz, sz)), q["pos"]))
		var c := col.lerp(Color(1.0, 0.6, 0.3), (1.0 - a) * 0.5) if grow_to < 1.0 else col
		mm.set_instance_color(k, Color(c.r, c.g, c.b, alpha * a))
	mm.visible_instance_count = n
