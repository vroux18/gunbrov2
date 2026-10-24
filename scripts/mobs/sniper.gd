extends "res://scripts/rig3d.gd"
## Vigie (« sniper ») : tireuse d'élite élancée à lentille-viseur violette. Modèle : assets/chars3d/sniper.glb
## (ou sniper_elite.glb), sculpté par tools/chars/sniper.py.
## Parts : pelvis (racine) > chest > head + head_glow, cape, chest_glow, arm_r/l > fore_r/l, gun > gun_glow,
## muzzle_glow ; pelvis > leg_r/l > shin_r/l. Bras en IK à deux os sur le fusil (posé directement).
## États : « move » démarche souple, fusil en travers de la poitrine, tête qui balaie la salle ;
## « aim » (1,1 s) pose un genou à terre, fusil épaulé droit devant (+Z), lentille et lunette qui pulsent
## de plus en plus fort ; fire() : recul net (fusil qui se cabre, buste rejeté). Mort : chute en arrière.

const AIM_TIME := 1.1
## Repères du sculpt (tools/chars/sniper.py).
const GRIP := Vector3(-0.085, 0.88, 0.17)
const FORE_GRIP := 0.33
const HAND_C := Vector3(0.182, 0.578, 0.025)  # centre de la main gauche (repère du personnage)
const EL := Vector3(0.176, 0.775, -0.012)
## Énergie des lueurs : vers 1, le violet du GLB rend #8E6BFF ; au-delà de ~1,5 il vire au lavande pâle.
const LENS_E := 1.0
const SCOPE_E := 1.0
const LINE_E := 0.95

var _lens_mat: StandardMaterial3D
var _scope_mat: StandardMaterial3D
var _muzzle_mat: StandardMaterial3D
var _line_mat: StandardMaterial3D
var _aim := 0.0  # 0 fusil en travers -> 1 épaulé
var _kneel := 0.0  # 0 debout -> 1 un genou à terre
var _seed := -1.0
var _look := 0.0
var _fire_t := 10.0  # temps depuis le dernier tir (recul plus long que rig3d.recoil)
var _beat_ph := 0.0  # phase de la pulsation (accumulée : sa fréquence monte pendant la visée)


func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	super.setup(path, tint, glow_energy)
	_lens_mat = _own_glow("head_glow", LENS_E)
	_scope_mat = _own_glow("gun_glow", SCOPE_E)
	_muzzle_mat = _own_glow("muzzle_glow", SCOPE_E)
	_line_mat = _own_glow("chest_glow", LINE_E)


## Matériau lumineux propre à cette instance (pour pulser sans toucher les autres Vigies).
func _own_glow(part_name: String, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(e, e, e)
	var n := p(part_name)
	if n != null:
		for mi in Models.meshes(n):
			var mm: MeshInstance3D = mi
			if mm == n or (mm.get_parent() == n and not parts.has(String(mm.name))):
				mm.material_override = m
	return m


func _energy(m: StandardMaterial3D, e: float) -> void:
	if m != null:
		m.albedo_color = Color(e, e, e)


func fire() -> void:
	super.fire()
	_fire_t = 0.0


func revive() -> void:
	super.revive()
	_aim = 0.0
	_kneel = 0.0
	_fire_t = 10.0


## Bout du canon (le laser de visée part d'ici).
func muzzle_position() -> Vector3:
	var m := p("muzzle_glow")
	if m == null:
		return super.muzzle_position()
	return m.global_transform.origin


## Transform d'une part dans le repère du personnage.
func _model_xf(name: String) -> Transform3D:
	var n := p(name)
	var xf := Transform3D.IDENTITY
	while n != null and n != model:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	return xf


## Fusil posé directement dans le repère du personnage : poignée en `grip`, canon selon `dir`.
func _place_gun(grip: Vector3, dir: Vector3, up_hint: Vector3) -> Transform3D:
	var z := dir.normalized()
	var x := up_hint.cross(z).normalized()
	var y := z.cross(x)
	var want := Transform3D(Basis(x, y, z), grip)
	var g := p("gun")
	if g != null:
		g.transform = _model_xf("chest").affine_inverse() * want
	return want


## IK à deux os : la main de `side` va en `target` (repère du personnage), coude tiré vers `pole`.
func _reach(side: String, target: Vector3, pole: Vector3) -> void:
	var arm := p("arm_" + side)
	var fore := p("fore_" + side)
	if arm == null or fore == null:
		return
	var sx := -1.0 if side == "r" else 1.0
	var cx := _model_xf("chest")
	var tgt := cx.affine_inverse() * target
	var ra: Transform3D = rest["arm_" + side]
	var rf: Transform3D = rest["fore_" + side]
	var s := ra.origin
	var e0 := s + rf.origin
	var h0 := e0 + (Vector3(HAND_C.x * sx, HAND_C.y, HAND_C.z) - Vector3(EL.x * sx, EL.y, EL.z))
	var l1 := (e0 - s).length()
	var l2 := (h0 - e0).length()
	var d := tgt - s
	var dl := clampf(d.length(), absf(l1 - l2) + 0.005, l1 + l2 - 0.002)
	var dn := d.normalized()
	var a := (l1 * l1 - l2 * l2 + dl * dl) / (2.0 * dl)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var pn := (pole - dn * pole.dot(dn)).normalized()
	var e := s + dn * a + pn * h
	var ba := Basis(Quaternion((e0 - s).normalized(), (e - s).normalized()))
	arm.transform = Transform3D(ba, s)
	var hand := s + dn * dl
	var u1 := ba.inverse() * (hand - e).normalized()
	fore.transform = Transform3D(Basis(Quaternion((h0 - e0).normalized(), u1)), rf.origin)


func animate(dt: float) -> void:
	if _seed < 0.0:
		_seed = randf() * TAU
	var aiming := state == "aim"
	_aim = move_toward(_aim, 1.0 if aiming else 0.0, dt * (6.5 if aiming else 4.0))
	_kneel = move_toward(_kneel, 1.0 if aiming else 0.0, dt * (5.0 if aiming else 3.5))
	var a := smoothstep(0.0, 1.0, _aim)
	var kn := smoothstep(0.0, 1.0, _kneel)
	var u := clampf(state_t / AIM_TIME, 0.0, 1.0) if aiming else 0.0
	var go := clampf(speed * 2.0, 0.0, 1.0) * (1.0 - kn)
	phase += dt * (5.6 + 4.4 * speed) * go
	var s := sin(phase)
	var c := cos(phase)
	var amp := clampf(speed * 1.4, 0.0, 1.0) * (1.0 - kn)
	var breathe := sin(t * 2.1 + _seed) * 0.008
	# --- jambes : foulée légère et rebondie (genou qui se replie haut), ou un genou à terre
	var lr := -s * 0.52 * amp
	var ll := s * 0.52 * amp
	var kr := (0.12 + maxf(0.0, c) * 0.95) * amp
	var kl := (0.12 + maxf(0.0, -c) * 0.95) * amp
	_pose("leg_r", Vector3(lerpf(lr, 0.22, kn), 0, lerpf(0.0, -0.05, kn)))
	_pose("shin_r", Vector3(lerpf(kr, 1.55, kn), 0, 0))
	_pose("leg_l", Vector3(lerpf(ll, -1.62, kn), 0, lerpf(0.0, 0.1, kn)))
	_pose("shin_l", Vector3(lerpf(kl, 1.62, kn), 0, 0))
	# --- bassin : rebond à chaque pas, roulis des hanches ; descend pour le genou à terre
	var bob := pow(absf(c), 1.5) * 0.03 * amp - 0.012 * amp
	var spread := 0.275 * (1.0 - cos(0.52 * amp * s))
	var drop := -0.288 * kn
	_pose("pelvis", Vector3(0.04 * amp, -s * 0.1 * amp, s * 0.06 * amp), Vector3(0, bob - spread + drop + breathe * (1.0 - amp), 0.02 * kn))
	# --- buste : contre-roulis, penché en avant pour viser ; recul : rejeté en arrière
	_fire_t += dt
	var rk := exp(-_fire_t * 8.0) if _fire_t < 0.8 else 0.0  # recul : coup sec puis retour
	_pose("chest", Vector3(0.05 * amp + 0.12 * a - 0.16 * rk, s * 0.12 * amp + 0.05 * a, -s * 0.05 * amp + 0.03 * a), Vector3(0, breathe, -0.015 * rk))
	# --- tête : balaie la salle en marchant (vigie), se colle à la lunette en visée
	var scan := sin(t * 0.8 + _seed) * 0.45 * (1.0 - a)
	_look = lerpf(_look, scan, clampf(dt * 3.0, 0.0, 1.0))
	_pose("head", Vector3(-c * 0.04 * amp + 0.2 * a - 0.12 * rk, _look - s * 0.08 * amp - 0.12 * a, -0.16 * a))
	# --- cape : flotte derrière en marchant, se pose en visée, claque au tir
	_pose("cape", Vector3(0.18 * amp + sin(phase * 2.0 + 0.7) * 0.07 * amp + sin(t * 1.7 + _seed) * 0.03 + 0.35 * rk, 0, s * 0.06 * amp))
	# --- fusil : en travers (canon vers le haut à gauche) -> épaulé droit devant
	var pel := _model_xf("pelvis")
	var carry_grip := pel * Vector3(-0.115, 0.79 - 0.62, 0.15) + Vector3(0, -absf(s) * 0.012 * amp, 0)
	var carry_dir := Vector3(0.62, 0.62, 0.38) + Vector3(0, 0, s * 0.05 * amp)
	var aim_grip := Vector3(GRIP.x + 0.03 * a, GRIP.y + drop + 0.1 * kn, GRIP.z + 0.03 * kn) + Vector3(0, 0.0, -0.07 * rk)
	var aim_dir := Vector3(0, 0.35 * rk, 1)
	var steady := (1.0 - u) * 0.004 + u * 0.002  # léger tremblement qui se stabilise
	aim_grip += Vector3(sin(t * 13.0), sin(t * 17.0 + 1.0), 0) * steady * a
	var grip := carry_grip.lerp(aim_grip, a)
	var dir := carry_dir.normalized().slerp(aim_dir.normalized(), a)
	var up_hint := Vector3(-0.6, 0.8, 0).normalized().slerp(Vector3.UP, a)
	var gx := _place_gun(grip, dir, up_hint)
	# --- mains : droite sur la poignée, gauche sous le garde-main
	_reach("r", gx * Vector3(0, -0.012, -0.004), Vector3(-0.6, -0.7, -0.3))
	_reach("l", gx * Vector3(0, -0.01, FORE_GRIP), Vector3(0.7, -0.6, -0.1))
	# --- lueurs : la lentille et la lunette se chargent pendant la visée
	_beat_ph = fmod(_beat_ph + dt * (8.0 + 30.0 * u), TAU)
	var beat := 0.5 + 0.5 * sin(_beat_ph)
	var charge := u * a
	var le := LENS_E * (1.0 + 0.06 * sin(t * 2.5 + _seed) + charge * (0.25 + 0.55 * beat) + rk * 0.5)
	_energy(_lens_mat, le)
	_energy(_scope_mat, SCOPE_E * (1.0 + charge * (0.3 + 0.7 * beat) + rk * 0.8))
	_energy(_muzzle_mat, SCOPE_E * (1.0 + charge * 1.2 + rk * 2.5))
	_energy(_line_mat, LINE_E * (1.0 + charge * 0.4 * beat))
	var hg := p("head_glow")
	if hg != null:
		hg.scale = Vector3.ONE * (1.0 + charge * (0.04 + 0.08 * beat) + rk * 0.1)
	var mg := p("muzzle_glow")
	if mg != null:
		mg.scale = Vector3.ONE * (1.0 + charge * 0.6 * beat + rk * 2.2)


## Mort : touchée, elle se cabre, les genoux lâchent, puis elle bascule en arrière, bras et fusil qui lui
## échappent sur le côté ; la lentille s'éteint.
func animate_death(dt_total: float) -> void:
	var k1 := smoothstep(0.0, 0.2, dt_total)  # coup reçu, genoux qui lâchent
	var k2 := smoothstep(0.12, 0.6, dt_total)  # chute en arrière
	var e2 := k2 * k2
	var bounce := sin(clampf((dt_total - 0.6) / 0.14, 0.0, 1.0) * PI) * 0.025
	_pose("pelvis", Vector3(0.15 * k1 * (1.0 - e2), 0, 0), Vector3(0, -0.1 * k1 * (1.0 - e2), 0))
	# jambes : fléchies sous le choc, puis allongées au sol (un genou relevé)
	_pose("leg_r", Vector3(-0.35 * k1 * (1.0 - e2) + 0.05 * e2, 0, -0.12 * k2))
	_pose("leg_l", Vector3(-0.2 * k1 * (1.0 - e2) - 0.5 * e2, 0, 0.1 * k2))
	_pose("shin_r", Vector3(0.7 * k1 * (1.0 - e2) + 0.15 * e2, 0, 0))
	_pose("shin_l", Vector3(0.5 * k1 * (1.0 - e2) + 1.0 * e2, 0, 0))
	_pose("chest", Vector3(-0.3 * k1 + 0.15 * e2, 0.15 * k1, 0.1 * k1))
	_pose("head", Vector3(-0.4 * k1 + 0.3 * e2, -0.35 * k1, 0.2 * k1))
	_pose("cape", Vector3(0.6 * k1 - 0.6 * e2, 0, 0))
	# le fusil lui échappe et tombe à plat sur le côté ; bras ouverts
	var gdir := Vector3(0, 0, 1).slerp(Vector3(-0.92, 0.3, 0.25).normalized(), k2)
	var gx := _place_gun(Vector3(-0.1 - 0.3 * k2, 0.85 - 0.1 * k2, 0.17 - 0.1 * k2), gdir, Vector3(0, 1, 0).slerp(Vector3(0, 0, -1), k2))
	_reach("r", Vector3(-0.34, 0.86 + 0.08 * k1, 0.05 - 0.05 * k2), Vector3(-0.6, -0.6, -0.3))
	_reach("l", Vector3(0.36, 0.82 + 0.15 * k1, 0.02), Vector3(0.7, -0.5, -0.2))
	model.rotation.x = -1.45 * e2
	model.position = Vector3(0, 0.07 * e2 + bounce, -0.1 * e2)
	var fade := 1.0 - smoothstep(0.1, 0.55, dt_total)
	_energy(_lens_mat, LENS_E * (0.12 + 0.88 * fade + 0.6 * (1.0 - k1)))
	_energy(_scope_mat, SCOPE_E * (0.1 + 0.9 * fade))
	_energy(_muzzle_mat, SCOPE_E * (0.05 + 0.95 * fade))
	_energy(_line_mat, LINE_E * (0.1 + 0.9 * fade))
