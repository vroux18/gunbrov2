extends "res://scripts/rig3d.gd"
## Patineur (« roller ») : petit robot punk des Néons sur rollers, crête iroquoise rose. Modèle :
## assets/chars3d/roller.glb (ou roller_elite.glb), sculpté par tools/chars/roller.py.
## Parts : pelvis (racine) > torso > head > head_glow, crest_glow ; torso > chest_glow, arm_r/l > fore_r/l
## (+ jets_glow chez l'élite) ; pelvis > leg_r/l > shin_r/l > skate_r/l > wheels_glow_r/l ; trail_glow (racine) ;
## torso > trail_up_glow.
## États : « move » patine en zigzag (poussées alternées vers l'extérieur, bras qui balancent, penché dans les
## virages) ; « tell » (0,35 s) s'accroupit, bras armés en arrière, un roller en canard derrière, tremble ;
## « charge » (0,42 s) fonce en boule (très penché, bras en arrière), traînée rose derrière lui.
## Mort (~0,6 s) : touché, il part en roulade avant et finit sur le dos.

const TELL_TIME := 0.35
const CHARGE_TIME := 0.42
const ANKLE_Y := 0.13  # cheville au repos (tools/chars/roller.py) : les roues touchent le sol
const CENTER := Vector3(0, 0.38, 0)  # centre de la roulade
## Énergie des lueurs : vers 1, le rose du GLB rend #FF3CAC ; au-delà de ~1,6 il pâlit vers le lilas.
const CREST_E := 1.0
const EYE_E := 1.05
const WHEEL_E := 0.9
const TRAIL_E := 1.3
const TRAILS := ["trail_glow", "trail_up_glow"]

var _crest_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _wheel_mat: StandardMaterial3D
var _patch_mat: StandardMaterial3D
var _jet_mat: StandardMaterial3D
var _trail_mat: StandardMaterial3D
var _seed := -1.0
var _crouch := 0.0  # 0 patine -> 1 accroupi (élan)
var _dash := 0.0  # 0 -> 1 en boule pendant la charge
var _trail := 0.0  # longueur de la traînée
var _yaw_prev := 0.0
var _has_yaw := false
var _turn := 0.0  # vitesse de virage lissée (rad/s) : il se penche dedans
var _prev_state := "move"
var _burst := 0.0  # coup d'accélération au départ de la charge


func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	super.setup(path, tint, glow_energy)
	_crest_mat = _own_glow(["crest_glow"], CREST_E)
	_eye_mat = _own_glow(["head_glow"], EYE_E)
	_wheel_mat = _own_glow(["wheels_glow_r", "wheels_glow_l"], WHEEL_E)
	_patch_mat = _own_glow(["chest_glow"], 1.0)
	_jet_mat = _own_glow(["jets_glow"], 1.0)
	# traînée : mélange additif (le noir du dégradé est transparent), sans ombre
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.vertex_color_is_srgb = true
	_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.no_depth_test = false
	_trail_mat.albedo_color = Color(TRAIL_E, TRAIL_E, TRAIL_E)
	for nm in TRAILS:
		var tr := p(nm)
		if tr == null:
			continue
		for mi in Models.meshes(tr):
			var mm: MeshInstance3D = mi
			if mm == tr or (mm.get_parent() == tr and not parts.has(String(mm.name))):
				mm.material_override = _trail_mat
				mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tr.visible = false


## Matériau lumineux propre à cette instance (pour pulser sans toucher les autres patineurs).
func _own_glow(names: Array, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(e, e, e)
	for nm in names:
		var n := p(nm)
		if n == null:
			continue
		for mi in Models.meshes(n):
			var mm: MeshInstance3D = mi
			if mm == n or (mm.get_parent() == n and not parts.has(String(mm.name))):
				mm.material_override = m
	return m


func _energy(m: StandardMaterial3D, e: float) -> void:
	if m != null:
		m.albedo_color = Color(e, e, e)


func revive() -> void:
	super.revive()
	_crouch = 0.0
	_dash = 0.0
	_trail = 0.0
	_has_yaw = false
	for nm in TRAILS:
		if p(nm) != null:
			p(nm).visible = false


## Transform d'une part dans le repère du personnage.
func _model_xf(name: String) -> Transform3D:
	var n := p(name)
	var xf := Transform3D.IDENTITY
	while n != null and n != model:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	return xf


## Vitesse de virage mesurée sur l'orientation réelle (le zigzag du jeu), pour se pencher dedans.
func _turn_rate(dt: float) -> float:
	var f := global_transform.basis.z
	var yaw := atan2(f.x, f.z)
	var r := 0.0
	if _has_yaw and dt > 0.0:
		r = wrapf(yaw - _yaw_prev, -PI, PI) / dt
	_yaw_prev = yaw
	_has_yaw = true
	return clampf(r, -8.0, 8.0)


## Jambe : cuisse (avant/arrière x, écart z, rotation y), genou ; le roller reste à plat (cheville).
func _leg(side: String, thigh: Vector3, knee: float, base_x: float, toe_out: float) -> void:
	_pose("leg_" + side, thigh)
	_pose("shin_" + side, Vector3(knee, 0, 0))
	# la cheville compense l'inclinaison du bassin, de la cuisse et du genou : roues à plat
	_pose("skate_" + side, Vector3(-(base_x + thigh.x + knee), toe_out, -thigh.z * 0.75))


func animate(dt: float) -> void:
	if _seed < 0.0:
		_seed = randf() * TAU
	var telling := state == "tell"
	var charging := state == "charge"
	if charging and _prev_state != "charge":
		_burst = 1.0
	_prev_state = state
	_burst = maxf(0.0, _burst - dt * 4.0)
	_crouch = move_toward(_crouch, 1.0 if telling else 0.0, dt * (9.0 if telling else 5.0))
	_dash = move_toward(_dash, 1.0 if charging else 0.0, dt * (10.0 if charging else 3.0))
	_trail = move_toward(_trail, 1.0 if charging else 0.0, dt * (7.0 if charging else 3.5))
	var cr := smoothstep(0.0, 1.0, _crouch)
	var da := smoothstep(0.0, 1.0, _dash)
	var u := clampf(state_t / TELL_TIME, 0.0, 1.0) if telling else 0.0
	_turn = lerpf(_turn, _turn_rate(dt), clampf(dt * 6.0, 0.0, 1.0))
	# --- foulée de patin : une poussée par jambe et par cycle, plus vive à pleine vitesse
	var glide := (1.0 - cr) * (1.0 - da)
	var amp := clampf(speed * 1.2, 0.0, 1.0) * glide
	phase += dt * (5.2 + 2.6 * speed) * maxf(amp, 0.15)
	var s := sin(phase)
	var c := cos(phase)
	var push_l := maxf(0.0, s)  # la gauche pousse vers l'extérieur pendant que la droite porte
	var push_r := maxf(0.0, -s)
	var tt := t + _seed
	# --- corps entier : penché dans les virages (autour des roues), en avant dans la charge
	var lean := clampf(-_turn * 0.09, -0.32, 0.32) * (1.0 - da)
	model.rotation = Vector3(0.0, 0.0, lean)
	model.position = Vector3.ZERO
	# --- bassin : bas et en arrière (position de patineur), glisse au-dessus de la jambe d'appui
	var base_x := 0.18 * glide + 0.32 * cr + 0.62 * da  # bassin basculé vers l'avant
	var shiver := Vector3(sin(t * 61.0), 0, cos(t * 53.0)) * 0.006 * u
	var sway := s * 0.03 * amp
	_pose("pelvis", Vector3(base_x, -s * 0.18 * amp, s * 0.07 * amp), Vector3(sway, 0, -0.02 * cr) + shiver)
	# --- jambes : appui fléchi, poussée tendue en arrière et vers l'extérieur ; ramassées dans la charge
	var thigh_r := Vector3(-0.72 + 0.62 * push_r, 0.0, -0.55 * push_r) * amp
	var thigh_l := Vector3(-0.72 + 0.62 * push_l, 0.0, 0.55 * push_l) * amp
	var knee_r := (0.98 - 0.75 * push_r) * amp
	var knee_l := (0.98 - 0.75 * push_l) * amp
	# élan : accroupi, roller droit derrière et en canard (prêt à pousser)
	thigh_r += Vector3(-0.95, 0.0, -0.12) * cr
	knee_r += 1.35 * cr
	thigh_l += Vector3(-0.35, -0.2, 0.22) * cr
	knee_l += 0.95 * cr
	# charge : en boule, un pied devant l'autre
	var jit := sin(t * 47.0) * 0.03 * da
	thigh_r += Vector3(-1.15 + jit, 0.0, -0.08) * da
	knee_r += 1.25 * da
	thigh_l += Vector3(-0.7 - jit, 0.0, 0.1) * da
	knee_l += 1.05 * da
	var idle := (1.0 - amp) * glide
	thigh_r += Vector3(-0.3, 0, -0.05) * idle
	thigh_l += Vector3(-0.3, 0, 0.05) * idle
	knee_r += 0.45 * idle
	knee_l += 0.45 * idle
	_leg("r", thigh_r - Vector3(base_x * 0.0, 0, 0), knee_r, base_x, -0.55 * cr * u + 0.2 * push_r * amp)
	_leg("l", thigh_l, knee_l, base_x, -0.2 * push_l * amp + 0.25 * cr)
	# roues au sol : le bassin descend de ce qu'ont replié les jambes
	var pel := p("pelvis")
	if pel != null:
		var ar := _model_xf("skate_r").origin
		var al := _model_xf("skate_l").origin
		pel.position.y += ANKLE_Y - minf(ar.y, al.y)
		# le pied qui revient sous le corps décolle un peu
		var sk := p("skate_" + ("l" if c > 0.0 else "r"))
		if sk != null:
			sk.position.y += maxf(0.0, absf(c) - 0.5) * 0.05 * amp
	# --- buste : contre-roulis, penché vers l'avant ; armé en arrière pendant l'élan
	var t_rot := Vector3(0.2 * glide + 0.15 * cr + 0.42 * da + 0.12 * _burst, s * 0.26 * amp, -s * 0.06 * amp)
	_pose("torso", t_rot, Vector3(0, absf(c) * 0.008 * amp, 0))
	# --- tête : redressée pour regarder devant ; la crête frémit
	var nod := -c * 0.06 * amp + sin(t * 30.0) * 0.03 * u
	_pose("head", Vector3(-(base_x + t_rot.x) * 0.7 + nod - 0.08 * cr, -s * 0.18 * amp, -lean * 0.4 + s * 0.05 * amp))
	var crest_k := 1.0 + 0.04 * sin(tt * 9.0) * amp
	var cg := p("crest_glow")
	if cg != null:
		var cb: Transform3D = rest["crest_glow"]
		cg.transform = Transform3D(cb.basis * Basis.from_euler(Vector3(0.12 * amp * sin(phase * 2.0) + 0.2 * da, 0, 0)).scaled(Vector3.ONE * crest_k), cb.origin)
	# --- bras : balancier en travers du corps (patineur de vitesse) ; armés derrière (élan), plaqués (charge)
	var sw := s * 0.95 * amp
	var arm_r := Vector3(sw - 0.1, 0.0, -0.1 - 0.2 * maxf(0.0, s) * amp)
	var arm_l := Vector3(-sw - 0.1, 0.0, 0.1 + 0.2 * maxf(0.0, -s) * amp)
	var fore_r := Vector3(-0.5 - 0.4 * maxf(0.0, -s) * amp, 0, 0)
	var fore_l := Vector3(-0.5 - 0.4 * maxf(0.0, s) * amp, 0, 0)
	var wind := 0.4 + 0.6 * smoothstep(0.0, 0.8, u)
	arm_r = arm_r.lerp(Vector3(1.25 * wind, 0.2, -0.45), cr)
	arm_l = arm_l.lerp(Vector3(1.25 * wind, -0.2, 0.45), cr)
	fore_r = fore_r.lerp(Vector3(-0.3, 0, 0), cr)
	fore_l = fore_l.lerp(Vector3(-0.3, 0, 0), cr)
	arm_r = arm_r.lerp(Vector3(0.8 + 0.06 * sin(t * 33.0), 0.1, -0.16), da)
	arm_l = arm_l.lerp(Vector3(0.8 + 0.06 * sin(t * 37.0), -0.1, 0.16), da)
	fore_r = fore_r.lerp(Vector3(-0.15, 0, 0), da)
	fore_l = fore_l.lerp(Vector3(-0.15, 0, 0), da)
	_pose("arm_r", arm_r)
	_pose("arm_l", arm_l)
	_pose("fore_r", fore_r)
	_pose("fore_l", fore_l)
	# --- traînée de vitesse : s'étire dans la charge, se rétracte ensuite
	var tl := smoothstep(0.0, 1.0, _trail)
	var tlen := 0.05 + 0.95 * tl * (1.0 + 0.08 * sin(t * 40.0))
	_trail_mat.albedo_color = Color.WHITE * TRAIL_E * (0.4 + 0.6 * tl)
	for nm in TRAILS:
		var tr := p(nm)
		if tr == null:
			continue
		tr.visible = _trail > 0.02
		# la traînée haute reste à l'horizontale malgré le buste penché
		var tilt := -(base_x + t_rot.x) if nm == "trail_up_glow" else 0.0
		var rb: Transform3D = rest[nm]
		tr.transform = Transform3D(rb.basis * Basis.from_euler(Vector3(tilt, 0, 0)) * Basis.from_scale(Vector3(1, 1, tlen)), rb.origin)
	# --- lueurs : crête et roues s'allument pendant l'élan et la charge
	var beat := 0.5 + 0.5 * sin(t * (10.0 + 30.0 * u))
	_energy(_crest_mat, CREST_E * (1.0 + 0.05 * sin(tt * 3.0) + u * (0.2 + 0.3 * beat) + 0.35 * da))
	_energy(_eye_mat, EYE_E * (1.0 + 0.3 * u + 0.25 * da))
	_energy(_wheel_mat, WHEEL_E * (0.95 + 0.15 * amp * absf(s) + 0.4 * u * beat + 0.7 * da))
	_energy(_patch_mat, 0.9 + 0.1 * sin(tt * 4.0) + 0.3 * da)
	_energy(_jet_mat, 0.85 + 0.35 * cr * beat + 0.35 * da)
	var jg := p("jets_glow")
	if jg != null:
		var jb: Transform3D = rest["jets_glow"]
		jg.transform = Transform3D(jb.basis.scaled(Vector3(1.0 + 0.3 * da, 1.0 + 0.4 * cr * beat + 1.6 * da + 0.3 * da * sin(t * 50.0), 1.0 + 0.3 * da)), jb.origin)


## Mort : touché, il se recroqueville et part en roulade avant, puis s'étale sur le dos ; les lueurs s'éteignent.
func animate_death(dt_total: float) -> void:
	var k1 := smoothstep(0.0, 0.1, dt_total)  # coup reçu : se met en boule
	var kr := smoothstep(0.02, 0.42, dt_total)  # roulade
	var k3 := smoothstep(0.36, 0.5, dt_total)  # s'étale
	var ang := kr * (TAU * 0.75 + 0.15) - 0.15 * k3  # trois quarts de tour : finit sur le dos
	var b := Basis(Vector3.RIGHT, ang)
	var hop := sin(kr * PI) * 0.08
	var travel := Vector3(0, hop - 0.32 * k3, 0.45 * kr)
	model.transform = Transform3D(b, CENTER - b * CENTER + travel)
	var tuck := k1 * (1.0 - k3)
	_pose("pelvis", Vector3(0.4 * tuck, 0, 0))
	_pose("torso", Vector3(0.5 * tuck - 0.1 * k3, 0, 0.1 * k3))
	_pose("head", Vector3(0.4 * tuck - 0.3 * k3, 0.3 * k3, 0.2 * k3))
	_leg("r", Vector3(-1.4 * tuck - 0.4 * k3, 0, -0.2 * k3), 1.6 * tuck + 0.3 * k3, 0.0, 0.0)
	_leg("l", Vector3(-1.2 * tuck - 0.9 * k3, 0, 0.25 * k3), 1.5 * tuck + 1.0 * k3, 0.0, 0.0)
	_pose("arm_r", Vector3(-0.9 * tuck - 2.2 * k3, 0, -0.3 - 0.5 * k3))
	_pose("arm_l", Vector3(-0.9 * tuck - 2.0 * k3, 0, 0.3 + 0.6 * k3))
	_pose("fore_r", Vector3(-1.2 * tuck - 0.2 * k3, 0, 0))
	_pose("fore_l", Vector3(-1.2 * tuck - 0.3 * k3, 0, 0))
	for nm in TRAILS:
		if p(nm) != null:
			p(nm).visible = false
	var fade := 1.0 - smoothstep(0.15, 0.5, dt_total)
	var flick := 1.0 if fmod(dt_total * 14.0, 1.0) < 0.6 else 0.3
	_energy(_crest_mat, CREST_E * (0.15 + 0.85 * fade * flick))
	_energy(_eye_mat, EYE_E * (0.05 + 0.95 * fade * flick))
	_energy(_wheel_mat, WHEEL_E * (0.2 + 0.8 * fade))
	_energy(_patch_mat, 0.1 + 0.9 * fade)
	_energy(_jet_mat, 0.1 + 0.9 * fade)
