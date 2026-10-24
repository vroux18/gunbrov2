extends "res://scripts/rig3d.gd"
## Le Portique (boss du monde 1) : quadrupède à grand œil, nacelles-canons rouges et anneau de portail sur le dos.
## Marche lourde en diagonale (pattes avant gauche + arrière droite, puis l'inverse), coque qui tangue,
## anneau qui tourne et pulse. « ring » : se dresse, l'anneau s'emballe et le voile du portail s'ouvre, éclat au tir.
## « tell » : se tasse, tremble, l'œil se plisse et s'embrase. « charge » : penché en avant, foulée rapide.
## Mort : les pattes cèdent, la coque s'écrase, l'arche bascule en arrière et s'éteint.

## Orientation de la coque (et des canons, de l'œil, de l'arche) par rapport aux pattes, en radians.
var aim_yaw := 0.0

const LEGS := {"fl": 45.0, "fr": -45.0, "bl": 135.0, "br": -135.0}
const PAIR := {"fl": 0.0, "br": 0.0, "fr": 0.5, "bl": 0.5}
const KNEE_REACH := 0.76  # distance horizontale hanche -> genou (pour garder les pieds au sol en s'accroupissant)

var _yaw := 0.0
var _st := ""
var _el := 0.0
var _gait := 0.0
var _ring_ang := 0.0
var _ring_spd := 0.6
var _flare := 0.0
var _crouch := 0.0
var _rear := 0.0
var _lean := 0.0
var _glare := 0.0
var _ring_k := 0.0
var _amp := 0.0
var _seed := 0.0
var _death_prev := 0.0

var _eye_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _arch_mat: StandardMaterial3D
var _muzzle_mat: StandardMaterial3D
var _reactor_mat: StandardMaterial3D
var _portal_mat: StandardMaterial3D
var _ring_n := Vector3.UP  # axe de l'anneau (repère de la coque)

func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	super.setup(path, tint, glow_energy)
	_seed = randf() * 10.0
	_eye_mat = _glow(1.5)
	_ring_mat = _glow(1.5)
	_arch_mat = _glow(1.8)
	_muzzle_mat = _glow(1.8)
	_reactor_mat = _glow(2.2)
	_portal_mat = _glow(1.0)
	_portal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_portal_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_portal_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_portal_mat.no_depth_test = false
	_set_mat("eye_glow", _eye_mat)
	_set_mat("ring_glow", _ring_mat)
	_set_mat("arch_glow", _arch_mat)
	_set_mat("cannon_r_glow", _muzzle_mat)
	_set_mat("cannon_l_glow", _muzzle_mat)
	_set_mat("hull_glow", _reactor_mat)
	_set_mat("portal_glow", _portal_mat)
	var tilt := deg_to_rad(58.0)
	_ring_n = Vector3(0, sin(tilt), cos(tilt))
	var po := p("portal_glow")
	if po != null:
		po.visible = false

## Bouche des canons : milieu des deux nacelles (pour faire partir les tirs au bon endroit).
func muzzle_position() -> Vector3:
	var a := p("cannon_r_glow")
	var b := p("cannon_l_glow")
	if a == null or b == null:
		return super.muzzle_position()
	return (a.global_transform * Vector3(-0.26, 0.04, 0.64) + b.global_transform * Vector3(0.26, 0.04, 0.64)) * 0.5

func _glow(e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(e, e, e)
	return m

func _set_mat(part: String, m: Material) -> void:
	var n := p(part)
	if n == null:
		return
	for mi in Models.meshes(n):
		var mm: MeshInstance3D = mi
		if mm == n or (mm.get_parent() == n and not parts.has(String(mm.name))):
			mm.material_override = m

func _energy(m: StandardMaterial3D, e: float, a: float = 1.0) -> void:
	m.albedo_color = Color(e, e, e, a)

## Pose d'une patte : soulèvement (autour de l'axe tangent), balancier (autour de Y), pli du genou.
func _leg(lg: String, lift: float, swing: float, fold: float) -> void:
	var a := deg_to_rad(LEGS[lg])
	var radial := Vector3(sin(a), 0, cos(a))
	var k := radial.cross(Vector3.UP).normalized()
	var leg := p("leg_" + lg)
	if leg != null:
		var r: Transform3D = rest["leg_" + lg]
		leg.transform = Transform3D(r.basis * Basis(Vector3.UP, swing) * Basis(k, lift), r.origin)
	var shin := p("shin_" + lg)
	if shin != null:
		var r2: Transform3D = rest["shin_" + lg]
		shin.transform = Transform3D(r2.basis * Basis(k, -fold), r2.origin)

func _xf(part: String, b: Basis, off: Vector3 = Vector3.ZERO) -> void:
	var n := p(part)
	if n == null:
		return
	var r: Transform3D = rest[part]
	n.transform = Transform3D(r.basis * b, r.origin + off)

func animate(dt: float) -> void:
	if state != _st:
		if _st == "ring":
			_flare = 1.0
		_st = state
		_el = 0.0
	else:
		_el += dt
	var f := 1.0 - exp(-dt * 10.0)
	var tell := state == "tell"
	var ring := state == "ring"
	var charge := state == "charge"
	var tk := clampf(_el / 0.8, 0.0, 1.0) if tell else 0.0
	var rk := clampf(_el / 0.4, 0.0, 1.0) if ring else 0.0
	_flare = maxf(0.0, _flare - dt * 2.6)
	_crouch = lerpf(_crouch, (0.1 + 0.12 * tk) if tell else (0.04 if charge else 0.0), f)
	_rear = lerpf(_rear, rk if ring else 0.0, 1.0 - exp(-dt * 14.0))
	_lean = lerpf(_lean, 1.0 if charge else (0.35 * tk if tell else 0.0), f)
	_glare = lerpf(_glare, tk if tell else (0.75 if charge else 0.0), 1.0 - exp(-dt * 12.0))
	_ring_k = lerpf(_ring_k, rk, 1.0 - exp(-dt * 16.0))
	_yaw = lerp_angle(_yaw, aim_yaw, 1.0 - exp(-dt * 8.0))

	# ---------------- pattes : marche diagonale lourde
	var amp := 1.0 if charge else (0.0 if (tell or ring) else clampf(speed * 1.4, 0.0, 1.0))
	_amp = lerpf(_amp, amp, 1.0 - exp(-dt * 6.0))
	var freq := 2.1 if charge else 0.55 + 0.45 * _amp
	_gait += dt * TAU * freq * clampf(_amp * 3.0, 0.0, 1.0)
	var crouch_lift := _crouch / KNEE_REACH
	for lg in LEGS:
		var a := deg_to_rad(LEGS[lg])
		var fwd := -signf(sin(a))
		var u := fposmod(_gait / TAU + PAIR[lg], 1.0)
		var lift := 0.0
		var stride := 0.0
		if u < 0.38:
			var s := u / 0.38
			lift = sin(PI * s) * 0.34
			stride = lerpf(-1.0, 1.0, smoothstep(0.0, 1.0, s))
		else:
			var s2 := (u - 0.38) / 0.62
			stride = lerpf(1.0, -1.0, s2)
		lift *= _amp
		stride *= _amp * (0.2 if charge else 0.15)
		var tremble := sin(t * 63.0 + a * 3.0) * 0.025 * tk
		_leg(lg, lift + crouch_lift + tremble, stride * fwd, lift * 1.25 + crouch_lift)

	# ---------------- base et coque : tangage de la marche, tassement, cabrage
	var step := 0.5 + 0.5 * cos(_gait * 2.0)  # 1 au moment où une paire se pose
	var bob := -step * 0.06 * _amp
	var roll := sin(_gait) * 0.05 * _amp
	var pitch := cos(_gait * 2.0) * 0.02 * _amp
	var breathe := sin(t * 1.7) * 0.018 * (1.0 - _amp)
	var shake := Vector3(sin(t * 57.0 + _seed), sin(t * 71.0) * 0.6, sin(t * 49.0 + 1.7)) * 0.03 * tk
	_xf("base", Basis(), Vector3(0, -_crouch, 0))
	var hull_rot := Basis(Vector3.UP, _yaw) * Basis.from_euler(Vector3(pitch + 0.2 * _lean - 0.22 * _rear, 0, roll))
	_xf("hull", hull_rot, Vector3(0, bob + breathe - 0.1 * _crouch + 0.14 * _rear, 0.06 * _lean) + shake)

	# ---------------- œil et paupière
	var eye_e := 1.5 + 5.0 * _glare + 0.4 * sin(t * 3.0) + 3.0 * _ring_k
	_energy(_eye_mat, eye_e)
	var es := 1.0 + 0.08 * _glare + 0.05 * _glare * sin(t * 30.0)
	_xf("eye_glow", Basis().scaled(Vector3(es, es, es)))
	_xf("lid", Basis.from_euler(Vector3(0.12 * _glare, 0, 0)), Vector3(0, -0.045 * _glare, 0.02 * _glare))

	# ---------------- canons : visée, recul
	var cpitch := -0.08 * sin(t * 1.3) * (1.0 - shooting) + (0.15 * _lean) - 0.18 * _rear
	for side in ["r", "l"]:
		var sx := -1.0 if side == "r" else 1.0
		var kick := recoil
		_xf("cannon_" + side, Basis.from_euler(Vector3(cpitch - 0.22 * kick, sx * 0.05 * shooting, 0)), Vector3(0, 0.02 * kick, -0.13 * kick))
	_energy(_muzzle_mat, 1.8 + 1.2 * shooting + 5.0 * recoil + 1.5 * _glare)

	# ---------------- arche et anneau
	var target_spd := 0.7 + 1.6 * _amp
	if ring:
		target_spd = 3.0 + 16.0 * rk
	elif charge:
		target_spd = 4.0
	_ring_spd = lerpf(_ring_spd, target_spd, 1.0 - exp(-dt * (8.0 if ring else 2.5)))
	_ring_ang += _ring_spd * dt
	var rn := _ring_n
	_xf("ring", Basis(rn, _ring_ang))
	var pulse := 0.5 + 0.5 * sin(t * 3.2)
	var ring_e := 1.2 + 0.6 * pulse + 6.0 * _ring_k + 1.8 * _ring_k * sin(t * 42.0) + 4.0 * _flare
	_energy(_ring_mat, ring_e)
	_energy(_arch_mat, 1.4 + 0.8 * pulse + 4.0 * _ring_k + 4.0 * _flare)
	var asc := 1.0 + 0.05 * _ring_k * sin(t * 34.0) + 0.1 * _flare
	_xf("arch", Basis().scaled(Vector3(asc, asc, asc)))
	# voile du portail : s'ouvre en tourbillonnant pendant la charge de l'anneau, éclate au tir
	var po := p("portal_glow")
	if po != null:
		var open := maxf(_ring_k, _flare)
		po.visible = open > 0.02
		if po.visible:
			var ps := clampf(open, 0.05, 1.0) * (1.0 + 0.25 * _flare)
			_xf("portal_glow", Basis(rn, -_ring_ang * 1.8) * Basis().scaled(Vector3(ps, ps, ps)))
			_energy(_portal_mat, 1.4 + 1.0 * _flare, clampf(0.35 + 0.5 * _ring_k + 0.45 * _flare, 0.0, 1.0))
	# réacteur
	_energy(_reactor_mat, 1.3 + 0.3 * sin(t * 5.0) + 1.5 * _lean + 1.2 * _ring_k)

## Mort (~1,2 s) : les pattes cèdent, la coque s'écrase en piquant du nez, l'arche bascule en arrière et s'éteint.
func animate_death(dt_total: float) -> void:
	var ddt := clampf(dt_total - _death_prev, 0.0, 0.1)
	_death_prev = dt_total
	var fall := clampf(dt_total / 0.55, 0.0, 1.0)
	var fe := fall * fall
	# rebond à l'impact
	var bounce := sin(clampf((dt_total - 0.55) / 0.35, 0.0, 1.0) * PI) * 0.06
	_xf("base", Basis(), Vector3(0, -0.6 * fe + bounce, 0))
	for lg in LEGS:
		var a := deg_to_rad(LEGS[lg])
		var j := sin(a * 2.0 + 1.0) * 0.12
		_leg(lg, -0.05 * fe + j * fe, j * 0.4 * fe, -0.75 * fe)
	_xf("hull", Basis(Vector3.UP, _yaw) * Basis.from_euler(Vector3(0.22 * fe, 0, 0.1 * fe)), Vector3(0, -0.06 * fe, 0))
	# l'œil grésille puis s'éteint
	var flick := 1.0 if fmod(dt_total * 17.0, 1.0) > 0.35 else 0.3
	var fade := clampf(1.0 - dt_total / 0.9, 0.0, 1.0)
	_energy(_eye_mat, (1.5 + 4.0 * (1.0 - fall)) * fade * flick + 0.12)
	_xf("lid", Basis.from_euler(Vector3(0.3 * fe, 0, 0)), Vector3(0, -0.1 * fe, 0.03 * fe))
	_energy(_muzzle_mat, 1.8 * fade + 0.05)
	_energy(_reactor_mat, 2.0 * fade * flick + 0.1)
	# l'anneau ralentit, l'arche bascule en arrière et tombe
	_ring_spd = lerpf(_ring_spd, 0.0, 1.0 - exp(-ddt * 5.0))
	_ring_ang += _ring_spd * ddt
	_xf("ring", Basis(_ring_n, _ring_ang))
	var ak := clampf((dt_total - 0.2) / 0.75, 0.0, 1.0)
	var ae := ak * ak
	var land := sin(clampf((dt_total - 0.95) / 0.25, 0.0, 1.0) * PI) * 0.05
	_xf("arch", Basis.from_euler(Vector3(-0.7 * ae, 0.3 * ae, -0.75 * ae)), Vector3(0.95 * ae, -1.2 * ae + land, -0.55 * ae))
	var rf := clampf(1.0 - dt_total / 1.1, 0.0, 1.0)
	_energy(_ring_mat, (1.2 + 5.0 * maxf(0.0, 1.0 - dt_total * 4.0)) * rf * flick + 0.22)
	_energy(_arch_mat, 1.4 * rf + 0.15)
	var po := p("portal_glow")
	if po != null:
		po.visible = false
