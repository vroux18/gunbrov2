extends "res://scripts/rig3d.gd"
## Pétard (« bomber ») : kamikaze roulant. Modèle : assets/chars3d/bomber.glb (ou bomber_elite.glb),
## sculpté par tools/chars/bomber.py.
## Parts : body (moyeux, étrier, tête), ball (la boule, roule autour de X), eye_glow, fuse + fuse_glow (voyant).
## États : « move » roule vite (la boule tourne au rythme du sol, cahote, la tête tangue, l'antenne fouette) ;
## « tell » (0,55 s) s'arrête net, gonfle, tremble, le voyant clignote de plus en plus vite, il vire au rouge vif.
## Mort (~0,15 s) : gonfle d'un coup, blanchit, puis disparaît (l'explosion est dessinée par le jeu).

const TELL_TIME := 0.55
const DIE_TIME := 0.15
const BALL_R := 0.2016  # rayon de la boule (tools/chars/bomber.py : R x SCALE), échelle du modèle
const ROLL_SPEED := 15.0  # rad/s à speed = 1 quand on ne mesure pas le déplacement réel (banc d'essai)
## La couleur du GLB est multipliée par cette énergie : au-delà de ~1,5 le rouge vire au rose pâle.
const GLOW_SCALE := 0.45
const RED_HOT := Color(1.0, 0.1, 0.16)
const HOT_TINT := Color(1.0, 0.32, 0.3)  # teinte multipliée : le jaune vire au rouge orangé, le blanc au rouge

var _roll := 0.0
var _roll_v := 0.0  # vitesse de roulement lissée (rad/s)
var _last_pos := Vector3.ZERO
var _has_last := false
var _seed := -1.0
var _glow_base := 1.35
var _eye_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _skin: ShaderMaterial  # matériau propre (shaders/character.gdshader) : rougit pendant la préparation
var _stop := 0.0  # temps depuis l'arrêt net (inertie de la tête)
var _sway := 0.0
var _sway_v := 0.0
var _prev_state := "move"


func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	super.setup(path, tint, glow_energy)
	_glow_base = glow_energy * GLOW_SCALE
	_eye_mat = _new_glow()
	_lamp_mat = _new_glow()
	_skin = body_mat(tint).duplicate() as ShaderMaterial
	_skin_heat(Color(1, 1, 1), RED_HOT, 0.0)
	for mi in meshes:
		var m: MeshInstance3D = mi
		var nm := String(m.get_parent().name) + String(m.name)
		if "fuse_glow" in nm:
			m.material_override = _lamp_mat
		elif "eye_glow" in nm:
			m.material_override = _eye_mat
		else:
			m.material_override = _skin


func _new_glow() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(_glow_base, _glow_base, _glow_base)
	return m


## Teinte multipliée et lueur ajoutée de la coque (paramètres de shaders/character.gdshader).
func _skin_heat(tint: Color, col: Color, e: float) -> void:
	_skin.set_shader_parameter("tint", tint)
	_skin.set_shader_parameter("heat_col", col)
	_skin.set_shader_parameter("heat", e)


func _energy(m: StandardMaterial3D, e: float) -> void:
	if m != null:
		m.albedo_color = Color(e, e, e)


func _scaled(name: String, rot: Vector3, off: Vector3, s: Vector3) -> void:
	var n := p(name)
	if n == null:
		return
	var r: Transform3D = rest[name]
	n.transform = Transform3D(r.basis * Basis.from_euler(rot) * Basis.from_scale(s), r.origin + off)


func _noise(x: float) -> float:
	return sin(x * 37.0) * 0.55 + sin(x * 53.0 + 1.3) * 0.3 + sin(x * 71.0 + 2.1) * 0.15


## Vitesse de roulement : déplacement réel du nœud au sol (en jeu), sinon `speed` (banc).
func _roll_rate(dt: float) -> float:
	var gp := global_position
	var moved := 0.0
	if _has_last and dt > 0.0:
		var d := gp - _last_pos
		var fwd := global_transform.basis.z
		var sc := maxf(fwd.length(), 1e-3)
		moved = d.dot(fwd / sc) / dt / (BALL_R * sc)
	_last_pos = gp
	_has_last = true
	if absf(moved) > 0.5:
		return moved
	return ROLL_SPEED * clampf(speed, 0.0, 1.5)


func animate(dt: float) -> void:
	if _seed < 0.0:
		_seed = randf() * TAU
	var tt := t + _seed
	var telling := state == "tell"
	if telling and _prev_state != "tell":
		_stop = 0.0
	_prev_state = state
	_stop += dt
	var u := clampf(state_t / TELL_TIME, 0.0, 1.0) if telling else 0.0
	# roulement : la boule suit le sol ; arrêt net en préparation
	var goal := 0.0 if telling else _roll_rate(dt)
	_roll_v = lerpf(_roll_v, goal, 1.0 - exp(-dt * (30.0 if telling else 10.0)))
	_roll = fmod(_roll + _roll_v * dt, TAU)
	var sp := clampf(absf(_roll_v) / ROLL_SPEED, 0.0, 1.2)
	# la tête est un pendule sur l'axe de la boule : penchée vers l'avant en roulant, elle bascule à l'arrêt net
	var sway_goal := 0.2 * sp
	if telling and _stop < dt * 1.5:
		_sway_v += 7.0  # coup d'inertie vers l'avant au freinage
	var n_sub := ceili(dt / 0.005)
	var h := dt / float(maxi(n_sub, 1))
	for i in range(n_sub):  # ressort amorti, en sous-pas (stable à tout pas de temps)
		_sway_v += ((sway_goal - _sway) * 260.0 - _sway_v * 15.0) * h
		_sway += _sway_v * h
	# cahots : petits bonds irréguliers au rythme du roulement
	var bump := absf(sin(_roll * 2.0 + 0.6)) * 0.01 + maxf(0.0, sin(tt * 7.3)) * maxf(0.0, sin(tt * 3.1)) * 0.022
	bump *= sp
	var wob := (sin(tt * 11.0) * 0.05 + sin(tt * 6.4 + 1.0) * 0.04) * sp
	# préparation : gonfle par à-coups, tremble de plus en plus
	var swell := 1.0 + 0.2 * smoothstep(0.0, 0.7, u) + 0.05 * u * sin(t * (18.0 + 30.0 * u))
	var shake := (0.004 + 0.014 * u * u) if telling else 0.0
	var jit := Vector3(_noise(t), 0.0, _noise(t + 3.3)) * shake
	var jrot := Vector3(_noise(t + 6.1), _noise(t + 1.7), _noise(t + 8.2)) * shake * 6.0
	var squash := 1.0 + 0.05 * sin(tt * 14.0) * sp
	model.scale = Vector3(swell * (2.0 - squash), swell * squash, swell * (2.0 - squash)) if telling else Vector3(2.0 - squash, squash, 2.0 - squash)
	model.position = jit
	_pose("body", Vector3(_sway, 0, wob) + jrot, Vector3(0, bump, 0))
	# la boule gonfle un peu plus que le reste (elle pousse sur les moyeux)
	var bs := 1.0 + 0.06 * smoothstep(0.2, 1.0, u)
	_scaled("ball", Vector3(_roll - _sway, 0, 0), Vector3(0, (bs - 1.0) * BALL_R, 0), Vector3.ONE * bs)
	# antenne : fouette vers l'arrière en vitesse, se dresse et vibre en préparation
	var whip := -0.55 * sp - _sway_v * 0.05 + sin(tt * 9.0) * 0.12 * sp
	if telling:
		whip = sin(t * 60.0) * 0.12 * u + _noise(t + 2.0) * 0.08 * u
	_pose("fuse", Vector3(whip, 0, sin(tt * 7.0) * 0.1 * sp + _noise(t + 5.0) * 0.1 * u))
	# voyant : clignote lentement en roulant, de plus en plus vite en préparation
	var freq := 2.2 + 3.0 * sp
	if telling:
		freq = 4.0 + 26.0 * u * u
	var blink := 1.0 if fmod(tt * freq, 1.0) < 0.5 else 0.0
	if telling:
		blink = 1.0 if fmod(state_t * freq, 1.0) < 0.5 else 0.15
	_energy(_lamp_mat, _glow_base * (0.4 + 0.8 * blink + 0.4 * u))
	_scaled("fuse_glow", Vector3.ZERO, Vector3.ZERO, Vector3.ONE * (1.0 + 0.35 * blink * (0.4 + u)))
	_energy(_eye_mat, _glow_base * (1.0 + 0.1 * sin(tt * 5.0) + (0.3 * blink + 0.3) * u))
	var es := 1.0 + 0.05 * sin(tt * 6.0) + 0.18 * u
	_scaled("eye_glow", Vector3.ZERO, Vector3.ZERO, Vector3.ONE * es)
	# il vire au rouge vif, par pulsations calées sur le voyant
	var hot := smoothstep(0.0, 1.0, u) * (0.7 + 0.3 * blink)
	_skin_heat(Color(1, 1, 1).lerp(HOT_TINT, hot), RED_HOT, 0.45 * hot)


func animate_death(dt_total: float) -> void:
	var k := clampf(dt_total / DIE_TIME, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 2.0)
	model.position = Vector3.ZERO
	model.scale = Vector3.ONE * (1.25 + 0.4 * e) * Vector3(1.0, 1.0 + 0.06 * sin(k * PI), 1.0)
	_skin_heat(HOT_TINT.lerp(Color(1, 1, 1), e), RED_HOT.lerp(Color(1.0, 0.62, 0.32), e), 0.6 + 1.3 * e)
	_energy(_lamp_mat, _glow_base * 2.0)
	_energy(_eye_mat, _glow_base * (1.6 + 0.8 * e))
	model.visible = k < 1.0


func revive() -> void:
	super.revive()
	model.visible = true
	model.scale = Vector3.ONE
	_skin_heat(Color(1, 1, 1), RED_HOT, 0.0)
	_roll_v = 0.0
	_has_last = false
