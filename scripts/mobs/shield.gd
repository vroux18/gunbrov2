extends "res://scripts/rig3d.gd"
## Rempart (« shield ») : porte-bouclier lourd. Modèle : assets/chars3d/shield.glb (ou shield_elite.glb),
## sculpté par tools/chars/shield.py.
## Parts : torso, back_glow (générateur dorsal), head + head_glow (visière), arm_r/l (mains sur les poignées du
## bouclier, orientées à chaque image), leg_r/l + shin_r/l (pied), shield (enfant du torse, pivot au bas du
## bouclier) + shield_glow (tuiles hexagonales).
## États : « move » marche lourde, bouclier tenu devant qui ballotte un peu en retard ;
## « tell » (0,5 s) se ramasse derrière le bouclier posé au sol, qui s'illumine par pulsations ;
## « charge » (0,35 s) coup de bouclier : bouclier projeté en avant et penché, buste penché, fente.
## Mort (~0,9 s) : les genoux lâchent, il s'affaisse en avant ; le bouclier grésille, s'éteint et tombe à plat.

const TELL_TIME := 0.5
const CHARGE_TIME := 0.35
## Repères du sculpt (tools/chars/shield.py), dans le repère du personnage.
const HIP := Vector3(0.0, 0.43, -0.07)
const SB := Vector3(0.0, 0.075, 0.43)  # pivot du bouclier (bas, au centre)
const GRIP_L := Vector3(0.1725, 0.5447, 0.2261)  # poignée gauche (la droite est symétrique)
const SHOULDER_L := Vector3(0.31, 0.83, -0.08)
## La couleur du GLB est multipliée par cette énergie : au-delà de ~1,6 l'ambre blanchit.
const GLOW_SCALE := 0.45

var _cur := {}  # nom -> [rotation, décalage] lissés
var _jit := {}  # nom -> [rotation, décalage] ajoutés après lissage (tremblements)
var _glow_base := 1.35
var _shield_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _lit := 0.0  # éclat lissé du bouclier
var _die_last := 0.0
var _seed := -1.0

const PARTS := ["torso", "head", "leg_r", "leg_l", "shin_r", "shin_l", "shield"]


func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	super.setup(path, tint, glow_energy)
	_glow_base = glow_energy * GLOW_SCALE
	_shield_mat = _own_glow("shield_glow")
	_eye_mat = _own_glow("head_glow")
	_core_mat = _own_glow("back_glow")
	for n in PARTS:
		_cur[n] = [Vector3.ZERO, Vector3.ZERO]


## Matériau lumineux propre à cette instance (pulsations indépendantes).
func _own_glow(part_name: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(_glow_base, _glow_base, _glow_base)
	for mi in meshes:
		var mm: MeshInstance3D = mi
		if part_name in String(mm.name) + String(mm.get_parent().name):
			mm.material_override = m
	return m


func _set_energy(m: StandardMaterial3D, e: float) -> void:
	if m != null:
		m.albedo_color = Color(e, e, e)


func _noise(x: float) -> float:
	return sin(x * 37.0) * 0.55 + sin(x * 53.0 + 1.3) * 0.3 + sin(x * 71.0 + 2.1) * 0.15


func _apply(tgt: Dictionary, dt: float, rate: float) -> void:
	var k := 1.0 - exp(-dt * rate)
	for n in PARTS:
		var c: Array = _cur.get(n, [Vector3.ZERO, Vector3.ZERO])
		var g: Array = tgt.get(n, [Vector3.ZERO, Vector3.ZERO])
		c[0] = (c[0] as Vector3).lerp(g[0], k)
		c[1] = (c[1] as Vector3).lerp(g[1], k)
		_cur[n] = c
		var j: Array = _jit.get(n, [Vector3.ZERO, Vector3.ZERO])
		_pose(n, c[0] + j[0], c[1] + j[1])
	_jit.clear()
	_hold_grips()


## Bras rigides orientés pour que les mains restent sur les poignées du bouclier (repère du torse).
func _hold_grips() -> void:
	var sh := p("shield")
	if sh == null:
		return
	for side in ["r", "l"]:
		var sx := -1.0 if side == "r" else 1.0
		var arm := p("arm_" + side)
		if arm == null:
			continue
		var grip := Vector3(GRIP_L.x * sx, GRIP_L.y, GRIP_L.z)
		var shoulder := Vector3(SHOULDER_L.x * sx, SHOULDER_L.y, SHOULDER_L.z)
		var target: Vector3 = sh.transform * (grip - SB)
		var r: Transform3D = rest["arm_" + side]
		var hand_rest := grip - shoulder
		var d := target - r.origin
		if d.length() < 0.01:
			continue
		var q := Quaternion(hand_rest.normalized(), d.normalized())
		arm.transform = Transform3D(Basis(q), r.origin)


func animate(dt: float) -> void:
	if _seed < 0.0:
		_seed = randf() * TAU
	var tgt := {}
	var rate := 10.0
	var lit_goal := 0.0
	if state == "tell":
		lit_goal = _anim_tell(tgt)
		rate = 14.0
	elif state == "charge":
		lit_goal = _anim_charge(tgt, dt)
		rate = 26.0
	else:
		_anim_walk(tgt, dt)
	_apply(tgt, dt, rate)
	_lit = lerpf(_lit, lit_goal, 1.0 - exp(-dt * 14.0))
	var hum := 0.06 * sin(t * 4.0 + _seed) + 0.03 * sin(t * 11.0)
	var e := _glow_base * (1.0 + hum * (1.0 - _lit) + 0.4 * _lit)
	if state == "tell":
		var u := clampf(state_t / TELL_TIME, 0.0, 1.0)
		e += _glow_base * 0.25 * u * (0.5 + 0.5 * sin(state_t * (16.0 + 40.0 * u)))
	# plus fort sans virer au jaune pâle : on retient le vert et le bleu quand il s'illumine
	var hot := clampf((e / _glow_base - 1.0) * 2.0, 0.0, 1.0)
	_shield_mat.albedo_color = Color(e, e * (1.0 - 0.32 * hot), e * (1.0 - 0.6 * hot))
	_set_energy(_eye_mat, _glow_base * (1.0 + 0.6 * _lit))
	_set_energy(_core_mat, _glow_base * (1.0 + 0.1 * sin(t * 3.0 + _seed) + 0.4 * _lit))


## Marche lourde : foulée courte, genou qui plie, choc au contact, buste qui roule ; le bouclier suit en retard.
func _anim_walk(tgt: Dictionary, dt: float) -> void:
	var go := clampf(speed * 2.0, 0.0, 1.0)
	phase += dt * (4.6 + 3.0 * speed) * go
	var amp := clampf(speed * 1.4, 0.0, 1.0)
	var s := sin(phase)
	var c := cos(phase)
	var a := 0.42 * amp
	tgt["leg_r"] = [Vector3(-s * a, 0, 0), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(s * a, 0, 0), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(maxf(0.0, c) * 0.8 * amp, 0, 0), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(maxf(0.0, -c) * 0.8 * amp, 0, 0), Vector3.ZERO]
	var spread := 0.4 * (1.0 - cos(a * s))
	var stomp := pow(absf(s), 6.0) * 0.02 * amp
	var lift := (1.0 - absf(s)) * 0.018 * amp
	var breathe := sin(t * 2.0 + _seed) * 0.01 * (1.0 - amp)
	tgt["torso"] = [Vector3(0.06 * amp, -s * 0.07 * amp, s * 0.05 * amp), Vector3(0, -spread - stomp + lift + breathe, 0)]
	tgt["head"] = [Vector3(-0.04 * amp + sin(phase * 2.0 - 0.8) * 0.03 * amp, s * 0.08 * amp, -s * 0.04 * amp), Vector3.ZERO]
	# bouclier : contre la torsion du buste (reste face à l'avant), rebondit en retard sur le pas
	var lag := sin(phase * 2.0 - 1.1)
	tgt["shield"] = [Vector3(lag * 0.025 * amp - 0.06 * amp, s * 0.06 * amp, -s * 0.04 * amp), Vector3(0, lag * 0.012 * amp, 0)]


## Préparation : se ramasse derrière le bouclier posé au sol, tête rentrée, tremble ; le bouclier s'illumine.
func _anim_tell(tgt: Dictionary) -> float:
	var u := clampf(state_t / TELL_TIME, 0.0, 1.0)
	var k := smoothstep(0.0, 0.45, u)
	var shake := (0.004 + 0.012 * u * u) * k
	var drop := 0.15 * k
	tgt["torso"] = [Vector3(0.24 * k, 0, 0), Vector3(0, -drop, -0.01 * k)]
	_jit["torso"] = [Vector3(_noise(t) * shake, 0, _noise(t + 3.0) * shake), Vector3(_noise(t + 6.0) * shake * 0.5, 0, 0)]
	# genoux pliés : pieds à plat sous le buste abaissé, jambes un peu écartées
	tgt["leg_r"] = [Vector3(-1.2 * k, 0, -0.1 * k), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(-1.05 * k, 0, 0.1 * k), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(1.75 * k, 0, 0), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(1.6 * k, 0, 0), Vector3.ZERO]
	tgt["head"] = [Vector3(-0.05 * k, 0, 0), Vector3(0, -0.07 * k, -0.02 * k)]
	# bouclier planté au sol : compense la descente du buste, redressé
	tgt["shield"] = [Vector3(-0.16 * k, 0, 0), Vector3(0, drop - 0.05 * k, 0.02 * k)]
	_jit["shield"] = [Vector3.ZERO, Vector3(_noise(t + 1.0) * shake * 0.6, 0, 0)]
	return 0.3 + 0.7 * u


## Coup de bouclier : projeté en avant d'un coup, penché, buste en appui sur la jambe avant.
func _anim_charge(tgt: Dictionary, dt: float) -> float:
	var u := clampf(state_t / CHARGE_TIME, 0.0, 1.0)
	var k := smoothstep(0.0, 0.3, u)
	phase += dt * 14.0
	var s := sin(phase)
	tgt["torso"] = [Vector3(0.34 * k, 0, 0), Vector3(0, -0.05 * k, 0.06 * k)]
	tgt["leg_r"] = [Vector3(0.35 * k + s * 0.12 * k, 0, 0), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(-0.85 * k - s * 0.12 * k, 0, 0), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(0.35 * k, 0, 0), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(0.6 * k, 0, 0), Vector3.ZERO]
	tgt["head"] = [Vector3(-0.3 * k, 0, 0), Vector3.ZERO]
	# le bouclier part devant (au-delà du recul du buste) et bascule le haut vers l'avant
	tgt["shield"] = [Vector3(-0.1 * k, 0, 0), Vector3(0, 0.05 * k, 0.17 * k)]
	return 1.0


## Mort : genoux qui lâchent, buste affaissé vers l'avant ; le bouclier grésille, s'éteint et bascule à plat.
func animate_death(dt_total: float) -> void:
	var dt := dt_total - _die_last
	if dt < 0.0 or dt > 0.25:
		dt = 0.016
	_die_last = dt_total
	var k1 := smoothstep(0.0, 0.28, dt_total)
	var k2 := smoothstep(0.2, 0.7, dt_total)
	var tgt := {}
	tgt["shin_r"] = [Vector3(1.4 * k1, 0, 0), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(1.4 * k1, 0, 0), Vector3.ZERO]
	tgt["leg_r"] = [Vector3(-0.35 * k1 - 0.4 * k2, 0, -0.1 * k1), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(-0.35 * k1 - 0.4 * k2, 0, 0.1 * k1), Vector3.ZERO]
	tgt["torso"] = [Vector3(0.15 * k1 + 0.55 * k2, 0, 0.08 * k2), Vector3(0, -0.04 * k1, 0)]
	tgt["head"] = [Vector3(0.4 * k2, 0, 0.2 * k2), Vector3.ZERO]
	_apply(tgt, dt, 22.0)
	model.position.y = -0.17 * k1 - 0.04 * k2
	model.position.z = 0.05 * k2
	# bouclier : posé debout au sol, puis bascule vers l'avant autour de son bord bas jusqu'à plat
	var torso := p("torso")
	var sh := p("shield")
	if torso != null and sh != null:
		var kf := smoothstep(0.12, 0.62, dt_total)
		var fall := kf * kf * 1.42
		var bounce := sin(clampf((dt_total - 0.62) / 0.14, 0.0, 1.0) * PI) * 0.06
		var b := Basis(Vector3.RIGHT, fall - bounce) * Basis(Vector3.FORWARD, 0.12 * kf)
		var origin := Vector3(0.04 * kf, -model.position.y + 0.0, SB.z + 0.05 * kf - model.position.z)
		var want := Transform3D(b, origin)  # dans le repère du modèle (compense son affaissement)
		sh.transform = torso.transform.affine_inverse() * want
		_hold_grips_free(k1)
	# extinction : grésillements puis noir
	var fade := 1.0 - smoothstep(0.1, 0.55, dt_total)
	var crackle := 1.0 if fmod(dt_total * 23.0, 1.0) < 0.55 else 0.25
	_set_energy(_shield_mat, _glow_base * (0.06 + 1.2 * fade * crackle))
	_set_energy(_eye_mat, _glow_base * (0.08 + 0.92 * (1.0 - smoothstep(0.2, 0.6, dt_total))))
	_set_energy(_core_mat, _glow_base * (0.15 + 0.85 * (1.0 - smoothstep(0.3, 0.8, dt_total))))


## Mort : les bras lâchent les poignées et tombent le long du corps.
func _hold_grips_free(k: float) -> void:
	for side in ["r", "l"]:
		var sx := -1.0 if side == "r" else 1.0
		var arm := p("arm_" + side)
		if arm == null:
			continue
		var r: Transform3D = rest["arm_" + side]
		var b := Basis.from_euler(Vector3(0.5 * k, 0, sx * 0.35 * k))
		arm.transform = Transform3D(b, r.origin)


func revive() -> void:
	super.revive()
	_die_last = 0.0
	for n in PARTS:
		_cur[n] = [Vector3.ZERO, Vector3.ZERO]
