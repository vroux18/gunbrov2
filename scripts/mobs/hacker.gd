extends "res://scripts/rig3d.gd"
## Pirate (« hacker ») : robot pirate des Néons, capuche violette, lunettes vert acide, ordinateur au poignet.
## Modèle : assets/chars3d/hacker.glb (ou hacker_elite.glb), sculpté par tools/chars/hacker.py.
## Parts : pelvis (racine) > torso > head > head_glow, hood > hood_glow ; torso > chest_glow, holo_glow,
## arm_r/l > fore_r/l (fore_l > wrist_glow) ; pelvis > leg_r/l > shin_r/l. Bras en IK à deux os.
## États : « move » démarche furtive (accroupi, pas sur la pointe des pieds, mains levées, tête qui guette) ;
## « tell » (0,55 s) déploie l'écran holographique depuis son poignet et tape dessus des deux mains, les
## lueurs montent ; fire() : il pousse l'écran vers sa cible (geste de lancer), l'hologramme part et s'éteint ;
## « blink » (0,3 s) : il se brouille (parasites, tranches décalées, voile vert) pendant que mob3d le résorbe,
## et se recompose en parasites à l'arrivée. Mort (~0,8 s) : court-circuit, il tombe à genoux et s'affaisse.

const TELL_TIME := 0.55
const BLINK_TIME := 0.3
const THROW_TIME := 0.38
const GLITCH_IN := 0.28  # recomposition après la téléportation
## Repères du sculpt (tools/chars/hacker.py).
const WAIST := Vector3(0.0, 0.56, 0.0)
const HOLO := Vector3(0.0, 0.76, 0.3)
const KEYS := Vector3(0.0, -0.08, -0.1)  # centre du clavier dans le repère de l'écran
const EL := Vector3(0.205, 0.632, -0.025)
const HAND_C := Vector3(0.222, 0.49, 0.016)  # centre de la main gauche (repère du personnage)
const WRIST_SCREEN := Vector3(0.262, 0.56, 0.012)  # écran du poignet gauche
## Énergie des lueurs : vers 1, le vert du GLB rend #B6FF3C ; au-delà de ~1,5 il vire au jaune pâle.
const EYE_E := 1.0
const PIPE_E := 0.95
const HOLO_E := 0.85

var _eye_mat: StandardMaterial3D
var _pipe_mat: StandardMaterial3D
var _led_mat: StandardMaterial3D
var _wrist_mat: StandardMaterial3D
var _holo_mat: StandardMaterial3D
var _glitch_mat: StandardMaterial3D
var _seed := -1.0
var _hack := 0.0  # 0 marche -> 1 pose de piratage
var _holo := 0.0  # déploiement de l'écran
var _throw_t := 10.0  # temps depuis le lancer
var _in_t := 10.0  # temps depuis la réapparition
var _prev_state := "move"
var _look := 0.0
var _look_to := 0.0
var _look_cd := 0.0
var _glitched := false


func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	super.setup(path, tint, glow_energy)
	_eye_mat = _own_glow("head_glow", EYE_E)
	_pipe_mat = _own_glow("hood_glow", PIPE_E)
	_led_mat = _own_glow("chest_glow", 1.0)
	_wrist_mat = _own_glow("wrist_glow", 1.0)
	_holo_mat = _own_glow("holo_glow", HOLO_E)
	_holo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_holo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hg := p("holo_glow")
	if hg != null:
		for mi in Models.meshes(hg):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hg.visible = false
	# voile des parasites : vert acide additif par-dessus tout le corps
	_glitch_mat = StandardMaterial3D.new()
	_glitch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glitch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glitch_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glitch_mat.albedo_color = Color(0.7, 1.0, 0.25, 0.0)


## Matériau lumineux propre à cette instance (pour pulser sans toucher les autres pirates).
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
	_throw_t = 0.0


func revive() -> void:
	super.revive()
	_hack = 0.0
	_holo = 0.0
	_throw_t = 10.0
	_in_t = 10.0
	_set_glitch(0.0)
	model.visible = true


## Transform d'une part dans le repère du personnage.
func _model_xf(name: String) -> Transform3D:
	var n := p(name)
	var xf := Transform3D.IDENTITY
	while n != null and n != model:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	return xf


## IK à deux os : la main de `side` va en `target` (repère du personnage), coude tiré vers `pole`.
func _reach(side: String, target: Vector3, pole: Vector3) -> void:
	var arm := p("arm_" + side)
	var fore := p("fore_" + side)
	if arm == null or fore == null:
		return
	var sx := -1.0 if side == "r" else 1.0
	var cx := _model_xf("torso")
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


## Petit bruit déterministe par créneau (parasites).
func _hash(i: float) -> float:
	var x := sin(i * 12.9898 + _seed * 78.233) * 43758.5453
	return (x - floorf(x)) * 2.0 - 1.0


## Voile vert des parasites (n'écrase pas l'éclair blanc d'un coup reçu).
func _set_glitch(a: float) -> void:
	if _flash_t > 0.0:
		_glitched = false
		return
	var on := a > 0.01
	if on != _glitched:
		_overlay(_glitch_mat if on else null)
		_glitched = on
	_glitch_mat.albedo_color = Color(0.7, 1.0, 0.25, clampf(a, 0.0, 0.9))


## Parasites : chaque créneau de 1/30 s décale bassin, buste et tête d'un cran différent (tranches).
func _glitch_offsets(g: float) -> void:
	if g <= 0.0:
		model.visible = true
		return
	var slot := floorf(t * 30.0)
	for nm in ["pelvis", "torso", "head", "hood"]:
		var n := p(nm)
		if n != null:
			var k := float(nm.hash() % 97)
			n.position += Vector3(_hash(slot + k) * 0.07, _hash(slot + k + 31.0) * 0.012, _hash(slot + k + 57.0) * 0.03) * g
	model.scale = Vector3(1.0 + _hash(slot + 3.0) * 0.25 * g, 1.0 + _hash(slot + 9.0) * 0.08 * g, 1.0)
	model.visible = _hash(slot + 17.0) > -0.75 * g


func animate(dt: float) -> void:
	if _seed < 0.0:
		_seed = randf() * TAU
	var telling := state == "tell"
	var blinking := state == "blink"
	if _prev_state == "blink" and not blinking:
		_in_t = 0.0
	_prev_state = state
	_throw_t += dt
	_in_t += dt
	var u := clampf(state_t / TELL_TIME, 0.0, 1.0) if telling else 0.0
	_hack = move_toward(_hack, 1.0 if telling else 0.0, dt * (9.0 if telling else 4.0))
	var hk := smoothstep(0.0, 1.0, _hack)
	var th := clampf(_throw_t / THROW_TIME, 0.0, 1.0)
	var throwing := _throw_t < THROW_TIME
	var tk := sin(th * PI) if throwing else 0.0  # amplitude du geste de lancer
	var push := smoothstep(0.0, 0.35, th) if throwing else 0.0
	# --- démarche furtive : grands pas lents sur la pointe des pieds, accroupi
	var still := maxf(hk, tk)
	var amp := clampf(speed * 2.0, 0.0, 1.0) * (1.0 - still)
	phase += dt * (3.4 + 2.6 * speed) * clampf(speed * 2.0, 0.0, 1.0) * (1.0 - still)
	var s := sin(phase)
	var c := cos(phase)
	var tt := t + _seed
	var breathe := sin(tt * 2.2) * 0.006
	var crouch := 0.75 * (1.0 - hk * 0.6)
	var lr := -s * 0.6 * amp - 0.32 * crouch
	var ll := s * 0.6 * amp - 0.32 * crouch
	var kr := 0.55 * crouch + maxf(0.0, c) * 1.05 * amp
	var kl := 0.55 * crouch + maxf(0.0, -c) * 1.05 * amp
	_pose("leg_r", Vector3(lr, 0, -0.04 - 0.08 * hk))
	_pose("shin_r", Vector3(kr, 0, 0))
	_pose("leg_l", Vector3(ll, 0, 0.04 + 0.08 * hk))
	_pose("shin_l", Vector3(kl, 0, 0))
	# bassin : descend avec l'accroupi, monte sur la pointe des pieds à mi-pas
	var drop := -0.05 * crouch + absf(s) * 0.022 * amp
	_pose("pelvis", Vector3(0.12 * crouch * (1.0 - hk), -s * 0.12 * amp, s * 0.05 * amp), Vector3(0, drop + breathe, 0))
	# --- buste : penché en avant (furtif), droit pour taper ; lancer : torsion et poussée vers l'avant
	var t_rot := Vector3(0.22 * (1.0 - hk) + 0.06 * hk + 0.2 * tk - 0.06 * u * hk, s * 0.1 * amp - 0.35 * tk + 0.1 * push, -s * 0.04 * amp)
	_pose("torso", t_rot, Vector3(0, breathe * 0.5, 0.02 * tk))
	# --- tête : guette à droite et à gauche par coups secs ; baissée sur l'écran pendant le piratage
	_look_cd -= dt
	if _look_cd <= 0.0:
		_look_cd = randf_range(0.5, 1.3)
		_look_to = randf_range(-0.7, 0.7) if randf() < 0.7 else 0.0
	_look = lerpf(_look, _look_to * (1.0 - hk), clampf(dt * 10.0, 0.0, 1.0))
	_pose("head", Vector3(-0.12 * (1.0 - hk) + 0.22 * hk - c * 0.04 * amp - 0.15 * tk, _look + 0.3 * tk, 0.06 * sin(tt * 1.3) * (1.0 - hk)))
	# capuche : ballotte un peu derrière la tête
	_pose("hood", Vector3(0.05 * c * amp - 0.08 * tk, -_look * 0.15, 0.04 * s * amp))
	# --- écran holographique : jaillit du poignet, se pose devant lui, part vers la cible au lancer
	if telling:
		_holo = move_toward(_holo, 1.0, dt / 0.16)
	elif not throwing:
		_holo = move_toward(_holo, 0.0, dt * 6.0)
	var hg := p("holo_glow")
	var hgk := smoothstep(0.0, 1.0, _holo)
	if hg != null:
		var rb: Transform3D = rest["holo_glow"]
		var tx := _model_xf("torso")
		var wrist := tx.affine_inverse() * (_model_xf("fore_l") * (WRIST_SCREEN - EL))
		var org := wrist.lerp(rb.origin, hgk)
		var sc := 0.08 + 0.92 * hgk
		var flick := 1.0
		if telling and state_t < 0.18:
			flick = 0.4 if int(t * 40.0) % 2 == 0 else 1.0  # s'allume en grésillant
		var stand := 0.0
		if throwing:
			org += Vector3(0, 0.2 * push, 0.55 * push)
			sc *= 1.0 + 0.4 * push
			stand = 0.75 * push  # se redresse face à la cible en partant
		hg.transform = Transform3D(rb.basis * Basis.from_euler(Vector3(stand, 0, 0)).scaled(Vector3(sc, sc * (0.6 + 0.4 * hgk), sc)), org)
		hg.visible = hgk > 0.02 or throwing
		var he := HOLO_E * flick * (0.6 + 0.4 * hgk + 0.5 * u * u)
		if throwing:
			he = HOLO_E * (1.0 + 1.0 * (1.0 - push)) * (1.0 - smoothstep(0.35, 0.9, th))
			hg.visible = th < 0.98
		_energy(_holo_mat, he)
	# --- bras : furtifs (mains levées devant la poitrine), tapent sur le clavier, poussent l'écran au lancer
	var pel := _model_xf("pelvis")
	var bob := Vector3(0, absf(s) * 0.015 * amp, 0)
	var sneak_r := pel * Vector3(-0.11, 0.73 - 0.5, 0.17) + bob + Vector3(0, -c * 0.015 * amp, 0)
	var sneak_l := pel * Vector3(0.11, 0.75 - 0.5, 0.16) + bob + Vector3(0, c * 0.015 * amp, 0)
	var tr := sneak_r
	var tl := sneak_l
	if hg != null and hk > 0.0:
		var hx := _model_xf("holo_glow")
		var key := floorf(t * 13.0 + _seed)
		var tap_r := maxf(0.0, sin(t * 26.0 * PI * 0.5 + 0.0)) * 0.02
		var tap_l := maxf(0.0, sin(t * 26.0 * PI * 0.5 + PI)) * 0.02
		# touches visées au hasard sur le clavier (sous l'écran : KEYS dans son repère), doigts qui tapent
		var kr_ := KEYS + Vector3(-0.05 + _hash(key) * 0.04, 0.012 + tap_r, _hash(key + 5.0) * 0.025)
		var kl_ := KEYS + Vector3(0.05 + _hash(key + 9.0) * 0.04, 0.012 + tap_l, _hash(key + 13.0) * 0.025)
		# repère de l'écran sans son échelle (les mains suivent la taille réelle du clavier)
		var hxo := Transform3D(hx.basis.orthonormalized(), hx.origin)
		var kbr := hxo * kr_
		var kbl := hxo * kl_
		tr = tr.lerp(kbr, hk)
		tl = tl.lerp(kbl, hk)
	if throwing:
		var tx2 := _model_xf("torso")
		tr = tr.lerp(tx2 * Vector3(-0.04, 0.24, 0.42), tk)
		tl = tl.lerp(tx2 * Vector3(0.2, 0.12, 0.05), tk)
	_reach("r", tr, Vector3(-0.8, -0.5, -0.2))
	_reach("l", tl, Vector3(0.8, -0.5, -0.2))
	# --- lueurs : lunettes et passepoil montent pendant le piratage, éclair au lancer
	var beat := 0.5 + 0.5 * sin(t * (9.0 + 26.0 * u))
	_energy(_eye_mat, EYE_E * (1.0 + 0.05 * sin(tt * 2.7) + 0.35 * u * hk + 0.15 * u * beat + 0.4 * tk))
	_energy(_pipe_mat, PIPE_E * (0.9 + 0.1 * sin(tt * 1.9) + 0.4 * u * hk * beat + 0.3 * tk))
	_energy(_led_mat, 0.85 + 0.15 * (1.0 if fmod(tt * 2.0, 1.0) < 0.5 else 0.0) + 0.4 * u)
	_energy(_wrist_mat, 0.9 + 0.6 * hk + 0.3 * beat * u)
	# --- parasites : téléportation (mob3d le résorbe) puis recomposition à l'arrivée
	model.scale = Vector3.ONE
	var g := 0.0
	if blinking:
		g = 0.35 + 0.65 * clampf(state_t / BLINK_TIME * 2.0, 0.0, 1.0)
	elif _in_t < GLITCH_IN:
		g = 1.0 - _in_t / GLITCH_IN
	_glitch_offsets(g)
	_set_glitch(g * (0.35 + 0.35 * maxf(0.0, _hash(floorf(t * 30.0) + 41.0))))
	if g > 0.0:
		_energy(_eye_mat, EYE_E * (1.6 if _hash(floorf(t * 30.0) + 7.0) > 0.0 else 0.3))


## Mort : court-circuit (secousses, parasites, lunettes qui grésillent), il tombe à genoux puis s'affaisse en
## avant, la capuche sur le nez ; l'hologramme s'éteint.
func animate_death(dt_total: float) -> void:
	var k1 := smoothstep(0.0, 0.12, dt_total)  # électrocuté : se raidit
	var k2 := smoothstep(0.1, 0.38, dt_total)  # tombe à genoux
	var k3 := smoothstep(0.3, 0.55, dt_total)  # s'affaisse en avant
	var zap := (1.0 - smoothstep(0.25, 0.5, dt_total))
	var slot := floorf(dt_total * 30.0)
	var jit := Vector3(_hash(slot), 0, _hash(slot + 3.0)) * 0.025 * zap
	_pose("leg_r", Vector3(-0.15 * k1 * (1.0 - k2) + 0.05 * k2, 0, -0.1 * k2))
	_pose("leg_l", Vector3(-0.15 * k1 * (1.0 - k2) - 0.35 * k2, 0, 0.12 * k2))
	_pose("shin_r", Vector3(1.75 * k2, 0, 0))
	_pose("shin_l", Vector3(1.4 * k2, 0, 0))
	_pose("pelvis", Vector3(0.1 * k2, 0, 0), Vector3(0, -0.2 * k2, 0) + jit)
	_pose("torso", Vector3(-0.25 * k1 * (1.0 - k2) + 0.55 * k3, 0.2 * _hash(slot + 5.0) * zap, 0.1 * k3) + Vector3(_hash(slot + 8.0), 0, 0) * 0.08 * zap)
	_pose("head", Vector3(-0.35 * k1 * (1.0 - k3) + 0.6 * k3, 0.4 * _hash(slot + 11.0) * zap + 0.3 * k3, 0.25 * k3))
	_pose("hood", Vector3(0.25 * k3, 0, 0))
	_pose("arm_r", Vector3(-0.7 * k1 * (1.0 - k3) - 0.4 * k3, 0, -0.45 * k1 * (1.0 - k3) - 0.15))
	_pose("arm_l", Vector3(-0.5 * k1 * (1.0 - k3) - 0.5 * k3, 0, 0.45 * k1 * (1.0 - k3) + 0.15))
	_pose("fore_r", Vector3(-0.3 * k1, 0, 0))
	_pose("fore_l", Vector3(-0.6 * k1 * (1.0 - k3), 0, 0))
	model.rotation = Vector3(0.75 * k3, 0, 0)
	model.position = Vector3(0, 0.02 * k3, -0.05 * k3)
	model.scale = Vector3.ONE
	model.visible = true
	var hg := p("holo_glow")
	if hg != null:
		hg.visible = false
	var on := 1.0 if _hash(slot + 21.0) > -0.2 + 0.8 * k3 else 0.15
	var fade := 1.0 - smoothstep(0.2, 0.6, dt_total)
	_energy(_eye_mat, EYE_E * (0.06 + 0.94 * fade * on))
	_energy(_pipe_mat, PIPE_E * (0.08 + 0.92 * fade * on))
	_energy(_led_mat, 0.05 + 0.95 * fade)
	_energy(_wrist_mat, 0.05 + 0.95 * fade * on)
	_set_glitch(zap * 0.5 * maxf(0.0, _hash(slot + 33.0)))
