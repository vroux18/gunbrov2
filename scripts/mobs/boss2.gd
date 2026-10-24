extends "res://scripts/rig3d.gd"
## L'Enseigne (boss du monde 2) : mécha-mascotte au torse en panneau publicitaire, tête en enseigne au néon,
## bras-projecteurs de scène, jambes trapues. Modèle : assets/chars3d/boss2.glb, sculpté par tools/chars/boss2.py.
## Parts : base (bassin) > leg_r/l > shin_r/l ; upper (tourelle de taille) > screen_glow (écran, shader),
## bezel_glow (néons du cadre), head > head_glow, arm_r/l > proj_r/l > proj_r/l_glow (lentilles).
## États (enemy.gd, _boss2) :
## « move » marche lourde, l'écran passe une pub qui défile puis le visage, les projecteurs visent Jo ;
##   éventail : recul des projecteurs (détecté sur fire_cd), pluie d'obus : projecteurs au ciel (pattern_t).
## « tell » (0,8 s) écran en alerte, bras levés en V, il se cabre et tremble.
## « spiral » (2,2 s) tout le haut du corps tourne, calé sur les trois bras de la spirale de tirs : l'écran
##   et les deux projecteurs (écartés à 120°) visent chacun un bras ; lentilles qui crépitent, faisceaux.
## « ring » deux frappes au sol des projecteurs (à 0 et à 0,55 s, comme les deux ondes), visage furieux.
## Mort (~1,6 s) : l'écran grésille, se fend et s'éteint, l'enseigne tombe, il s'effondre.

const SCREEN_SHADER := preload("res://shaders/boss2_screen.gdshader")
const SPIRAL_RATE := 2.6  # rad/s : angle de la spirale = t * 2,6 dans enemy.gd
const ARM_SPREAD := 2.094  # 120° : écran + deux projecteurs = trois bras de spirale
const K := 1.0 / 64.0
## Écran : repère dans la part screen_glow (panneau penché de 15° en arrière), demi-tailles.
const S_Y := Vector3(0.0, 0.9659, -0.2588)
const S_N := Vector3(0.0, 0.2588, 0.9659)
const S_HALF := Vector2(0.74, 0.49)
const LENS := Vector3(0.0, -0.6, 0.64)  # centre de la lentille dans le repère de proj_r/l
const BEAM_LEN := 3.2

const PARTS := ["base", "leg_r", "leg_l", "shin_r", "shin_l", "upper", "head", "arm_r", "arm_l", "proj_r", "proj_l"]

var _cur := {}  # part -> [rotation, décalage] lissés
var _jit := {}  # ajouts après lissage (tremblements, chocs)
var _st := ""
var _el := 0.0
var _was_move := false
var _spin := 0.0  # rotation du haut du corps (repère du bassin)
var _seed := 0.0
var _e: WeakRef = null
var _e_look := 0.0
var _fc_prev := 0.0
var _pt_prev := 0.0
var _hp := 1.0
var _lob_t := 9.0
var _impact := 0.0  # choc d'une frappe (décroît)
var _ouch_t := 0.0
var _ouch_cd := 0.0
var _show_t := 0.0  # cycle pub / visage
var _blink_t := 2.0
var _look := 0.0
var _look_to := 0.0
var _hw := Vector2.ZERO  # ballant de l'enseigne (ressort)
var _hv := Vector2.ZERO
var _strobe := 0.0
var _bench_fire := 1.0
var _bench_lob := 4.0
var _die_last := 0.0
var _slam_done := [false, false]

var _screen: ShaderMaterial
var _bezel_mat: StandardMaterial3D
var _sign_mat: StandardMaterial3D
var _lens_mat := {}
var _base_mat: StandardMaterial3D
var _beams := {}
var _beam_mats := {}
var _light: OmniLight3D

static var _beam_shader: Shader = null


func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	super.setup(path, tint, glow_energy)
	_seed = randf() * 10.0
	for n in PARTS:
		_cur[n] = [Vector3.ZERO, Vector3.ZERO]
	_screen = ShaderMaterial.new()
	_screen.shader = SCREEN_SHADER
	_screen.set_shader_parameter("ax_y", S_Y)
	_screen.set_shader_parameter("ax_n", S_N)
	_screen.set_shader_parameter("half_size", S_HALF)
	_screen.set_shader_parameter("ad_seed", randf())
	_set_mat("screen_glow", _screen)
	_bezel_mat = _own_glow("bezel_glow", 1.3)
	_sign_mat = _own_glow("head_glow", 1.3)
	_base_mat = _own_glow("base_glow", 1.2)
	for side in ["r", "l"]:
		_lens_mat[side] = _own_glow("proj_%s_glow" % side, 1.3)
		_build_beam(side)
	_light = OmniLight3D.new()
	_light.light_color = Color("#FF3CAC")
	_light.light_energy = 1.2
	_light.omni_range = 4.5
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.95, 0.8)
	var up := p("upper")
	if up != null:
		up.add_child(_light)


func _set_mat(part: String, m: Material) -> void:
	var n := p(part)
	if n == null:
		return
	for mi in Models.meshes(n):
		var mm: MeshInstance3D = mi
		if mm == n or (mm.get_parent() == n and not parts.has(String(mm.name))):
			mm.material_override = m


## Matériau lumineux propre à cette instance (énergie réglable sans toucher les autres).
func _own_glow(part: String, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(e, e, e)
	_set_mat(part, m)
	return m


func _energy(m: StandardMaterial3D, e: float) -> void:
	if m != null:
		m.albedo_color = Color(e, e, e)


## Faisceau du projecteur : cône additif qui part de la lentille et s'évanouit.
func _build_beam(side: String) -> void:
	var host := p("proj_%s_glow" % side)
	if host == null:
		return
	if _beam_shader == null:
		_beam_shader = Shader.new()
		_beam_shader.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0);
uniform float len = 3.0;
varying float k;
void vertex() { k = VERTEX.y / len + 0.5; }
void fragment() {
	float fres = abs(dot(NORMAL, VIEW));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * (1.0 - k) * (1.0 - k) * (0.2 + 0.8 * fres * fres);
}
"""
	var cm := CylinderMesh.new()
	cm.top_radius = 0.75
	cm.bottom_radius = 0.2
	cm.height = BEAM_LEN
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	var m := ShaderMaterial.new()
	m.shader = _beam_shader
	m.set_shader_parameter("len", BEAM_LEN)
	var col := Color("#FF3CAC") if side == "r" else Color("#3C8CFF")
	m.set_shader_parameter("tint", Color(col.r, col.g, col.b, 0.0))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.x = PI * 0.5
	mi.position = LENS + Vector3(0, 0, BEAM_LEN * 0.5 - 0.02)
	mi.visible = false
	host.add_child(mi)
	_beams[side] = mi
	_beam_mats[side] = m


func _beam(side: String, a: float) -> void:
	var mi: MeshInstance3D = _beams.get(side)
	if mi == null:
		return
	mi.visible = a > 0.01
	var m: ShaderMaterial = _beam_mats[side]
	var col := Color("#FF3CAC") if side == "r" else Color("#3C8CFF")
	m.set_shader_parameter("tint", Color(col.r * 1.3, col.g * 1.3, col.b * 1.3, a))


## Ennemi simulé correspondant (lu seulement) : la spirale se cale sur son horloge, l'éventail et la pluie
## d'obus se lisent sur ses minuteries. Introuvable (banc d'essai) : on s'en passe.
func _enemy(dt: float) -> Object:
	if _e != null:
		var o = _e.get_ref()
		if o != null and is_instance_valid(o) and not o.dead:
			return o
		_e = null
	_e_look -= dt
	if _e_look > 0.0:
		return null
	_e_look = 0.5
	var n: Node = get_parent()
	var arena: Object = null
	for i in range(5):
		if n == null:
			break
		var a = n.get("arena")
		if a is Node:
			arena = a
			break
		n = n.get_parent()
	if arena == null or arena.get("enemies") == null:
		return null
	var gp := global_position
	var me := Vector2(gp.x, gp.z) / K
	var best: Object = null
	var bd := 200.0
	for en in arena.enemies:
		if is_instance_valid(en) and String(en.kind) == "boss2":
			var d: float = (en.position as Vector2).distance_to(me)
			if d < bd:
				bd = d
				best = en
	if best != null:
		_e = weakref(best)
		_fc_prev = best.fire_cd
		_pt_prev = best.pattern_t
	return best


func flash(dur: float = 0.09) -> void:
	super.flash(dur)
	if _ouch_cd <= 0.0 and not dead:
		_ouch_t = 0.45
		_ouch_cd = 2.8


## Pluie d'obus : les projecteurs pointent le ciel et crachent.
func lob() -> void:
	_lob_t = 0.0


func _noise(x: float) -> float:
	return sin(x * 37.0) * 0.55 + sin(x * 53.0 + 1.3) * 0.3 + sin(x * 71.0 + 2.1) * 0.15


func _apply(tgt: Dictionary, dt: float, rate: float) -> void:
	var k := 1.0 - exp(-dt * rate)
	for n in PARTS:
		var c: Array = _cur[n]
		var g: Array = tgt.get(n, [Vector3.ZERO, Vector3.ZERO])
		c[0] = (c[0] as Vector3).lerp(g[0], k)
		c[1] = (c[1] as Vector3).lerp(g[1], k)
		var j: Array = _jit.get(n, [Vector3.ZERO, Vector3.ZERO])
		var nd := p(n)
		if nd == null:
			continue
		var r: Transform3D = rest[n]
		var b := Basis.from_euler(c[0] + j[0])
		if n == "upper":
			b = Basis(Vector3.UP, _spin) * b
		nd.transform = Transform3D(r.basis * b, r.origin + c[1] + j[1])
	_jit.clear()


func _jadd(n: String, rot: Vector3, off: Vector3 = Vector3.ZERO) -> void:
	var j: Array = _jit.get(n, [Vector3.ZERO, Vector3.ZERO])
	_jit[n] = [j[0] + rot, j[1] + off]


func animate(dt: float) -> void:
	var e := _enemy(dt)
	if state != _st:
		_st = state
		_el = 0.0
		_slam_done = [false, false]
	else:
		_el += dt
	var pre := 0.0
	if e != null:
		var fc: float = e.fire_cd
		var pt: float = e.pattern_t
		if state == "move" and _was_move:
			if fc > _fc_prev + 0.4:
				fire()
			if pt < _pt_prev - 1.0:
				lob()
		if state == "move":
			pre = smoothstep(2.8, 3.2, pt)
		_fc_prev = fc
		_pt_prev = pt
		var hp := clampf(float(e.hp) / maxf(float(e.hp_max), 1.0), 0.0, 1.0)
		# appel des patineurs (aux deux tiers et au tiers) : projecteurs levés, éclat
		for th in [0.66, 0.33]:
			if _hp >= th and hp < th:
				lob()
		_hp = hp
	elif state == "move":
		# banc d'essai : éventail toutes les 1,7 s, pluie d'obus de temps en temps
		_bench_fire -= dt
		_bench_lob -= dt
		if _bench_fire <= 0.0:
			_bench_fire = 1.7
			fire()
		if _bench_lob <= 0.0:
			_bench_lob = 6.5
			lob()
	_was_move = state == "move"
	_lob_t += dt
	_impact = maxf(0.0, _impact - dt * 3.5)
	_ouch_t = maxf(0.0, _ouch_t - dt)
	_ouch_cd = maxf(0.0, _ouch_cd - dt)

	var tgt := {}
	var rate := 10.0
	var spiral_a := -1.0
	match state:
		"tell":
			rate = 14.0
			_pose_tell(tgt)
		"spiral":
			rate = 12.0
			spiral_a = _pose_spiral(tgt, dt, e)
		"ring":
			rate = 26.0
			_pose_ring(tgt)
		_:
			_pose_walk(tgt, dt, pre)
	if state != "spiral":
		_spin = lerp_angle(_spin, 0.0, 1.0 - exp(-dt * 3.5))
		_spin = wrapf(_spin, -PI, PI)
	_sign_spring(dt, tgt)
	_apply(tgt, dt, rate)
	_lights(dt, pre, spiral_a)


## Marche lourde : pas raides, choc au contact, bassin qui roule, enseigne qui ballotte ; projecteurs vers Jo.
func _pose_walk(tgt: Dictionary, dt: float, pre: float) -> void:
	var go := clampf(speed * 2.0, 0.0, 1.0)
	phase += dt * (3.4 + 2.0 * speed) * go
	var amp := clampf(speed * 1.6, 0.0, 1.0)
	var s := sin(phase)
	var c := cos(phase)
	tgt["leg_r"] = [Vector3(s * 0.4 * amp - 0.1 * pre, 0, -0.04), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(-s * 0.4 * amp - 0.1 * pre, 0, 0.04), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(maxf(0.0, -c) * 0.75 * amp + 0.2 * pre, 0, 0), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(maxf(0.0, c) * 0.75 * amp + 0.2 * pre, 0, 0), Vector3.ZERO]
	var spread := 0.07 * absf(s) * amp
	var stomp := pow(absf(s), 8.0) * 0.04 * amp
	var breathe := sin(t * 1.8) * 0.015 * (1.0 - amp)
	tgt["base"] = [Vector3(0.03 * amp, 0, s * 0.06 * amp), Vector3(0, -spread - stomp + breathe - 0.07 * pre, 0)]
	tgt["upper"] = [Vector3(0.04 * amp + 0.05 * pre - 0.1 * recoil, -s * 0.07 * amp, -s * 0.035 * amp), Vector3(0, 0, -0.06 * recoil)]
	tgt["head"] = [Vector3(sin(phase * 2.0 - 0.8) * 0.05 * amp, 0, 0), Vector3.ZERO]
	var sw := sin(phase - 0.6) * amp
	var idle := sin(t * 1.4 + _seed) * 0.04 * (1.0 - amp)
	var lift := -0.12 - 0.6 * pre
	var lob_k := smoothstep(0.0, 0.12, _lob_t) * (1.0 - smoothstep(0.5, 0.8, _lob_t))
	for side in ["r", "l"]:
		var sg := 1.0 if side == "r" else -1.0
		var arm := Vector3(lift + sw * 0.1 * sg + idle, 0.12 * sg, 0.0)
		var pj := Vector3(0.12 + 0.3 * pre - 0.42 * recoil, 0, 0)
		var pjo := Vector3(0, 0.03 * recoil, -0.14 * recoil)
		# pluie d'obus : projecteurs dressés vers le ciel
		arm = arm.lerp(Vector3(-1.75, 0.05 * sg, -0.25 * sg), lob_k)
		pj = pj.lerp(Vector3(-0.15, 0, 0), lob_k)
		tgt["arm_" + side] = [arm, Vector3.ZERO]
		tgt["proj_" + side] = [pj, pjo]
	if lob_k > 0.0:
		var kick := maxf(0.0, 1.0 - _lob_t / 0.25)
		_jadd("proj_r", Vector3(-0.3 * kick, 0, 0))
		_jadd("proj_l", Vector3(-0.3 * kick, 0, 0))
		tgt["upper"][0] += Vector3(-0.1 * lob_k, 0, 0)
	if pre > 0.0:
		var sh := 0.02 * pre
		_jadd("upper", Vector3(_noise(t) * sh, 0, _noise(t + 3.0) * sh))


## Préparation de la spirale : se cabre, bras levés en V qui tremblent de plus en plus.
func _pose_tell(tgt: Dictionary) -> void:
	var u := clampf(_el / 0.8, 0.0, 1.0)
	var up := smoothstep(0.0, 0.35, u)
	var shake := (0.01 + 0.05 * u * u) * up
	tgt["base"] = [Vector3.ZERO, Vector3(0, -0.09 * up, 0)]
	tgt["leg_r"] = [Vector3(-0.2 * up, 0, -0.12 * up), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(-0.2 * up, 0, 0.12 * up), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(0.38 * up, 0, 0), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(0.38 * up, 0, 0), Vector3.ZERO]
	tgt["upper"] = [Vector3(-0.16 * up, 0, 0), Vector3(0, 0.03 * up, 0)]
	tgt["head"] = [Vector3(-0.12 * up, 0, 0), Vector3.ZERO]
	tgt["arm_r"] = [Vector3(-2.35 * up, 0.1 * up, -0.55 * up), Vector3.ZERO]
	tgt["arm_l"] = [Vector3(-2.35 * up, -0.1 * up, 0.55 * up), Vector3.ZERO]
	tgt["proj_r"] = [Vector3(0.35 * up, 0, 0), Vector3.ZERO]
	tgt["proj_l"] = [Vector3(0.35 * up, 0, 0), Vector3.ZERO]
	_jadd("upper", Vector3(_noise(t) * shake * 0.5, 0, _noise(t + 4.7) * shake * 0.6))
	_jadd("arm_r", Vector3(_noise(t + 1.1) * shake, 0, _noise(t + 2.3) * shake))
	_jadd("arm_l", Vector3(_noise(t + 6.1) * shake, 0, _noise(t + 7.9) * shake))
	_jadd("head", Vector3(_noise(t + 9.0) * shake, _noise(t + 5.5) * shake, 0))


## Spirale : haut du corps qui tourne, calé sur la spirale simulée ; renvoie l'angle affiché par l'écran.
func _pose_spiral(tgt: Dictionary, dt: float, e: Object) -> float:
	var u := smoothstep(0.0, 0.25, _el)
	var target := _spin - SPIRAL_RATE * dt
	if e != null:
		# bras de spirale : direction 2D (cos a, sin a) -> 3D (cos a, 0, sin a) ; lacet monde atan2(cos a, sin a)
		var a: float = float(e.t) * SPIRAL_RATE
		var z := global_transform.basis.z
		var parent_yaw := atan2(z.x, z.z)
		var want := atan2(cos(a), sin(a)) - parent_yaw
		# un des trois émetteurs (écran, projecteurs à ±120°) : le plus proche
		var best := want
		var bd := 99.0
		for k in range(3):
			var w := want + ARM_SPREAD * float(k)
			var d := absf(wrapf(w - _spin, -PI, PI))
			if d < bd:
				bd = d
				best = w
		target = _spin + wrapf(best - _spin, -PI, PI)
	_spin = lerp_angle(_spin, target, 1.0 - exp(-dt * (30.0 if _el > 0.2 else 10.0)))
	_spin = wrapf(_spin, -PI, PI)
	var shake := 0.012
	tgt["base"] = [Vector3.ZERO, Vector3(0, -0.08, 0)]
	tgt["leg_r"] = [Vector3(-0.18, 0, -0.14), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(-0.18, 0, 0.14), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(0.34, 0, 0), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(0.34, 0, 0), Vector3.ZERO]
	tgt["upper"] = [Vector3(-0.06, 0, 0), Vector3(0, 0.02, 0)]
	tgt["arm_r"] = [Vector3(-0.95 * u - 1.4 * (1.0 - u), -ARM_SPREAD * u, -0.3 * (1.0 - u)), Vector3.ZERO]
	tgt["arm_l"] = [Vector3(-0.95 * u - 1.4 * (1.0 - u), ARM_SPREAD * u, 0.3 * (1.0 - u)), Vector3.ZERO]
	tgt["proj_r"] = [Vector3(0.95, 0, 0), Vector3.ZERO]
	tgt["proj_l"] = [Vector3(0.95, 0, 0), Vector3.ZERO]
	# les projecteurs crépitent à chaque tir (toutes les 0,07 s)
	var pulse := 0.5 + 0.5 * sin(t * TAU / 0.07)
	_jadd("proj_r", Vector3(-0.06 * pulse, 0, 0), Vector3(0, 0, -0.03 * pulse))
	_jadd("proj_l", Vector3(-0.06 * pulse, 0, 0), Vector3(0, 0, -0.03 * pulse))
	_jadd("upper", Vector3(_noise(t) * shake, 0, _noise(t + 2.0) * shake))
	_jadd("head", Vector3(_noise(t + 5.0) * 0.04, 0, _noise(t + 8.0) * 0.05))
	return _spin


## Deux frappes au sol (à 0 et 0,55 s, comme les ondes) : penché en avant, projecteurs écrasés au sol,
## relevés au-dessus de la tête entre les deux.
func _pose_ring(tgt: Dictionary) -> void:
	var el := _el
	var down := 0.0
	var up := 0.0
	if el < 0.22:
		down = smoothstep(0.0, 0.07, el)
	elif el < 0.55:
		down = 1.0 - smoothstep(0.22, 0.36, el)
		up = smoothstep(0.24, 0.42, el)
		if el > 0.46:
			var k := smoothstep(0.46, 0.55, el)
			down = k
			up = 1.0 - k
	elif el < 0.8:
		down = 1.0
	else:
		down = 1.0 - smoothstep(0.8, 1.05, el)
	for i in range(2):
		var at := 0.06 if i == 0 else 0.56
		if not _slam_done[i] and el >= at:
			_slam_done[i] = true
			_impact = 1.0
			_hv += Vector2(5.0, (randf() - 0.5) * 4.0)
	var dk := down
	var uk := up
	tgt["base"] = [Vector3(0.0, 0, 0), Vector3(0, -0.3 * dk - 0.04 * uk, 0.05 * dk)]
	tgt["leg_r"] = [Vector3(-0.5 * dk, 0, -0.1 * dk), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(-0.5 * dk, 0, 0.1 * dk), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(0.95 * dk + 0.1 * uk, 0, 0), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(0.95 * dk + 0.1 * uk, 0, 0), Vector3.ZERO]
	tgt["upper"] = [Vector3(0.5 * dk - 0.22 * uk, 0, 0), Vector3(0, 0, 0.06 * dk)]
	tgt["head"] = [Vector3(-0.2 * dk + 0.1 * uk, 0, 0), Vector3.ZERO]
	for side in ["r", "l"]:
		var sg := 1.0 if side == "r" else -1.0
		# frappe : bras à la verticale (contre le buste penché), avant-bras télescopique sorti
		var arm := Vector3(-0.42 * dk - 2.75 * uk, 0.12 * sg * dk, -0.1 * sg * uk)
		var pj := Vector3(-0.15 * dk - 0.45 * uk, 0, 0)
		tgt["arm_" + side] = [arm, Vector3.ZERO]
		tgt["proj_" + side] = [pj, Vector3(0, -0.3 * dk, 0.05 * dk)]
	var sh := 0.05 * _impact * _impact
	_jadd("base", Vector3.ZERO, Vector3(_noise(t) * sh, absf(_noise(t + 1.0)) * sh * 0.5, 0))
	_jadd("upper", Vector3(_noise(t + 3.0) * sh, 0, _noise(t + 4.0) * sh))


## Ressort de l'enseigne : elle ballotte au bout de son mât (pas, chocs, rotation).
func _sign_spring(dt: float, tgt: Dictionary) -> void:
	var drive := Vector2.ZERO
	var b: Array = tgt.get("base", [Vector3.ZERO, Vector3.ZERO])
	drive.y = (b[0] as Vector3).z * 2.0
	if state == "spiral":
		drive.y += 0.12
	var dt2 := minf(dt, 0.05)
	var acc := (drive - _hw) * 120.0 - _hv * 9.0
	_hv += acc * dt2
	_hw += _hv * dt2
	var h: Array = tgt.get("head", [Vector3.ZERO, Vector3.ZERO])
	tgt["head"] = [(h[0] as Vector3) + Vector3(_hw.x * 0.1, 0, _hw.y * 0.1), h[1]]


## Écran, néons, lentilles, faisceaux, lumière portée.
func _lights(dt: float, pre: float, spiral_a: float) -> void:
	var s := _screen
	s.set_shader_parameter("clock", t + _seed)
	# cycle de la pub et du visage (le visage coupe la pub quand il encaisse)
	_show_t += dt
	var cyc := fmod(_show_t, 8.0)
	var face := 1.0 if cyc > 5.0 else 0.0
	var mood := 0.0
	var ouch := 1.0 if _ouch_t > 0.0 else 0.0
	if ouch > 0.0:
		face = 1.0
	_blink_t -= dt
	if _blink_t <= 0.0:
		_blink_t = randf_range(1.8, 3.6)
	var blink := 1.0 if _blink_t < 0.12 else 0.0
	if randf() < dt * 0.8:
		_look_to = randf_range(-1.0, 1.0)
	_look = lerpf(_look, _look_to, 1.0 - exp(-dt * 8.0))
	var alert := 0.0
	var spiral := 0.0
	var fl := 0.0
	match state:
		"tell":
			alert = 1.0
		"spiral":
			spiral = 1.0
		"ring":
			face = 1.0
			mood = 1.0
			fl = _impact * 0.8
	if pre > 0.0:
		face = 1.0
		mood = 1.0 if pre > 0.3 else 0.0
	fl = maxf(fl, recoil * 0.35)
	fl = maxf(fl, maxf(0.0, 1.0 - _lob_t / 0.3) * 0.5)
	var glitch := 0.0
	if _hp < 0.66:
		glitch = 0.15 if _hp > 0.33 else 0.45
	s.set_shader_parameter("face", face)
	s.set_shader_parameter("mood", mood)
	s.set_shader_parameter("ouch", ouch)
	s.set_shader_parameter("blink", blink)
	s.set_shader_parameter("look", _look)
	s.set_shader_parameter("alert", alert)
	s.set_shader_parameter("spiral", spiral)
	s.set_shader_parameter("spin", t * 5.0)
	s.set_shader_parameter("flash", fl)
	s.set_shader_parameter("glitch", glitch)
	s.set_shader_parameter("noise", 0.0)
	s.set_shader_parameter("crack", 0.0)
	s.set_shader_parameter("off", 0.0)
	var se := 1.15
	if alert > 0.0:
		se = 1.0 + 0.3 * clampf(_el / 0.8, 0.0, 1.0)
	s.set_shader_parameter("energy", se)
	# néons : bourdonnement, coupure brève de temps en temps (enseigne fatiguée)
	var buzz := 1.0
	if fmod(t + _seed * 3.0, 5.3) < 0.18:
		buzz = 0.35 if int(t * 30.0) % 2 == 0 else 1.0
	var hot := 0.0
	if state == "tell":
		hot = clampf(_el / 0.8, 0.0, 1.0)
	elif state == "spiral":
		hot = 1.0
	_energy(_sign_mat, (1.3 + 0.8 * hot + 1.0 * _impact) * buzz)
	_energy(_bezel_mat, 1.25 + 0.15 * sin(t * 3.0) + 0.8 * hot + 0.8 * _impact)
	_energy(_base_mat, 1.2 + 0.3 * sin(t * 4.0))
	# lentilles et faisceaux
	_strobe = 0.5 + 0.5 * sin(t * TAU / 0.07)
	var lens := 1.3 + 0.2 * sin(t * 2.5) + 0.9 * recoil + 0.6 * pre
	var beam := 0.05 + 0.08 * recoil
	if state == "tell":
		lens = 1.3 + 0.8 * hot + 0.3 * hot * sin(t * 40.0)
		beam = 0.1 + 0.12 * hot
	elif state == "spiral":
		lens = 1.5 + 0.8 * _strobe
		beam = 0.16 + 0.1 * _strobe
	elif state == "ring":
		lens = 1.3 + 1.0 * _impact
		beam = 0.0
	var lob_k := maxf(0.0, 1.0 - _lob_t / 0.5)
	lens += 1.0 * lob_k
	beam = maxf(beam, 0.2 * lob_k)
	for side in ["r", "l"]:
		_energy(_lens_mat[side], lens)
		_beam(side, beam)
	if _light != null:
		var lc := Color("#FF3CAC")
		if state == "spiral":
			lc = Color("#8E4CFF")
		elif state == "tell" and int(t * 14.0) % 2 == 0:
			lc = Color("#FFB347")
		_light.light_color = lc
		_light.light_energy = 1.0 + 0.6 * hot + 1.5 * _impact + 0.4 * recoil


## Mort : l'écran grésille, se fend et s'éteint ; l'enseigne tombe de son mât ; les genoux lâchent et le
## buste s'affaisse en avant, projecteurs au sol ; les néons meurent en clignotant.
func animate_death(dt_total: float) -> void:
	var dt := dt_total - _die_last
	if dt < 0.0 or dt > 0.25:
		dt = 0.016
	_die_last = dt_total
	var k1 := smoothstep(0.3, 0.7, dt_total)  # genoux
	var k2 := smoothstep(0.55, 1.0, dt_total)  # buste
	var tgt := {}
	tgt["base"] = [Vector3(0.08 * k2, 0, 0.05 * k2), Vector3(0, -0.42 * k1 - 0.06 * k2, 0.04 * k2)]
	tgt["leg_r"] = [Vector3(-0.7 * k1, 0, -0.18 * k1), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(-0.7 * k1, 0, 0.18 * k1), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(1.35 * k1, 0, 0), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(1.35 * k1, 0, 0), Vector3.ZERO]
	tgt["upper"] = [Vector3(0.5 * k2, 0, 0.12 * k2), Vector3(0, -0.05 * k2, 0.08 * k2)]
	tgt["arm_r"] = [Vector3(-0.35 * k2, 0, -0.35 * k1), Vector3(0, -0.05 * k2, 0)]
	tgt["arm_l"] = [Vector3(-0.35 * k2, 0, 0.35 * k1), Vector3(0, -0.05 * k2, 0)]
	tgt["proj_r"] = [Vector3(0.5 * k2, 0, 0.2 * k2), Vector3.ZERO]
	tgt["proj_l"] = [Vector3(0.5 * k2, 0, -0.2 * k2), Vector3.ZERO]
	# l'enseigne se décroche (0,25 s), bascule en avant et tombe à côté de lui
	var hk := smoothstep(0.22, 0.85, dt_total)
	var hf := hk * hk
	var land := sin(clampf((dt_total - 0.85) / 0.2, 0.0, 1.0) * PI) * 0.05
	tgt["head"] = [Vector3(0.9 * hf, 0.5 * hf, -1.2 * hf), Vector3(1.0 * hf, -1.45 * hf + land, 0.75 * hf)]
	# tremblement de la panne avant l'effondrement
	var sh := 0.03 * (1.0 - smoothstep(0.25, 0.5, dt_total))
	_jadd("upper", Vector3(_noise(dt_total) * sh, 0, _noise(dt_total + 2.0) * sh))
	_jadd("arm_r", Vector3(_noise(dt_total + 4.0) * sh * 2.0, 0, 0))
	_jadd("arm_l", Vector3(_noise(dt_total + 6.0) * sh * 2.0, 0, 0))
	_spin = lerp_angle(_spin, 0.0, 1.0 - exp(-dt * 6.0))
	_apply(tgt, dt, 16.0)
	# écran : neige, fissure, extinction
	var s := _screen
	s.set_shader_parameter("clock", t + dt_total)
	s.set_shader_parameter("alert", 0.0)
	s.set_shader_parameter("spiral", 0.0)
	s.set_shader_parameter("face", 1.0)
	s.set_shader_parameter("ouch", 1.0)
	s.set_shader_parameter("noise", clampf(dt_total / 0.15, 0.0, 1.0) * (1.0 if fmod(dt_total * 9.0, 1.0) > 0.5 else 0.55))
	s.set_shader_parameter("glitch", 1.0)
	s.set_shader_parameter("crack", smoothstep(0.25, 0.45, dt_total))
	s.set_shader_parameter("off", smoothstep(0.55, 0.95, dt_total))
	s.set_shader_parameter("flash", maxf(0.0, 1.0 - dt_total / 0.12))
	var flick := 1.0 if fmod(dt_total * 13.0, 1.0) > 0.4 else 0.25
	var fade := clampf(1.0 - dt_total / 0.9, 0.0, 1.0)
	# l'enseigne reste allumée pendant sa chute (on la voit tomber), grésille et meurt à l'impact
	var sign_fade := clampf(1.0 - (dt_total - 0.85) / 0.35, 0.0, 1.0)
	var sflick := 1.0 if fmod(dt_total * 17.0 + 0.3, 1.0) > 0.3 else 0.3
	_energy(_sign_mat, 1.5 * sign_fade * sflick + 0.06)
	_energy(_bezel_mat, (1.3 * fade * flick) + 0.05)
	_energy(_base_mat, 1.2 * fade + 0.05)
	for side in ["r", "l"]:
		_energy(_lens_mat[side], 1.6 * fade * (flick if side == "r" else 1.0 - flick * 0.5) + 0.06)
		_beam(side, 0.0)
	if _light != null:
		_light.light_energy = 1.5 * fade * flick
