extends "res://scripts/rig3d.gd"
## Videur (« bouncer ») : gros robot videur en costume, poings américains néon orange. Modèle :
## assets/chars3d/bouncer.glb (ou bouncer_elite.glb), sculpté par tools/chars/bouncer.py.
## Parts : torso (racine, hanches) > chain (ballotte), head > shades > shades_glow, arm_r/l > fore_r/l (avec
## le poing) > knuck_r_glow / knuck_l_glow, leg_r/l > shin_r/l (avec la chaussure).
## États : « move » marche lourde et chaloupée (épaules qui roulent, buste qui tourne, bras écartés qui
## balancent, tête qui reste droite, chaîne qui ballotte) ;
## « tell » (0,8 s) se cabre, lève les deux poings joints au-dessus de la tête, qui s'illuminent et tremblent
## de plus en plus ; « ring » (0,35 s) s'accroupit et frappe le sol à deux poings (écrasement à l'impact,
## éclair des poings, puis il se relève à moitié). Mort (~1 s) : chancelle, tombe à la renverse comme un
## arbre, bras en croix ; les lunettes s'envolent et retombent ; les poings s'éteignent.

const TELL_TIME := 0.8
const RING_TIME := 0.35
const SLAM_T := 0.08  # instant de l'impact dans « ring »
## Énergie des lueurs : vers 1, l'orange du GLB rend #FF8A3C ; au-delà de ~1,8 il vire au jaune pâle.
const KNUCK_E := 1.0
const SHADE_E := 0.85

var _cur := {}  # nom -> [rotation, décalage] lissés
var _jit := {}  # nom -> [rotation, décalage] ajoutés après lissage (tremblements, chocs)
var _knuck_mat: StandardMaterial3D
var _shade_mat: StandardMaterial3D
var _seed := -1.0
var _chain := Vector2.ZERO  # balancier de la chaîne (ressort amorti)
var _chain_v := Vector2.ZERO
var _prev_tr := Vector3.ZERO
var _die_last := 0.0

const PARTS := ["torso", "head", "chain", "shades", "arm_r", "arm_l", "fore_r", "fore_l", "leg_r", "leg_l", "shin_r", "shin_l"]


func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	super.setup(path, tint, glow_energy)
	_knuck_mat = _own_glow(["knuck_r_glow", "knuck_l_glow"], KNUCK_E)
	_shade_mat = _own_glow(["shades_glow"], SHADE_E)
	for n in PARTS:
		_cur[n] = [Vector3.ZERO, Vector3.ZERO]


## Matériau lumineux propre à cette instance (pour faire chauffer les poings sans toucher les autres).
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


func _scaled(name: String, s: float) -> void:
	var n := p(name)
	if n == null:
		return
	var r: Transform3D = rest[name]
	n.transform = Transform3D(r.basis.scaled_local(Vector3.ONE * s), r.origin)


func _noise(x: float) -> float:
	return sin(x * 37.0) * 0.55 + sin(x * 53.0 + 1.3) * 0.3 + sin(x * 71.0 + 2.1) * 0.15


## Cibles lissées puis appliquées (les changements d'état se fondent au lieu de sauter).
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


## Chaîne : pendule amorti qui suit en retard les mouvements du buste.
func _swing_chain(dt: float) -> void:
	var tr: Vector3 = (_cur["torso"] as Array)[0]
	var d := (tr - _prev_tr) / maxf(dt, 0.001)
	_prev_tr = tr
	_chain_v += Vector2(-d.x, -d.z) * 0.9
	var n_sub := ceili(dt / 0.005)
	var h := dt / float(maxi(n_sub, 1))
	for i in range(n_sub):
		_chain_v += (-_chain * 160.0 - _chain_v * 9.0) * h
		_chain += _chain_v * h
	_chain = _chain.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
	var c: Array = _cur["chain"]
	_pose("chain", (c[0] as Vector3) + Vector3(_chain.x, 0, _chain.y), c[1])


func animate(dt: float) -> void:
	if _seed < 0.0:
		_seed = randf() * TAU
	var tgt := {}
	var rate := 10.0
	var glow := KNUCK_E * (1.0 + 0.08 * sin(t * 3.0 + _seed))
	var ks := 1.0
	model.scale = Vector3.ONE
	model.position = Vector3.ZERO
	if state == "tell":
		var u := clampf(state_t / TELL_TIME, 0.0, 1.0)
		_anim_tell(tgt, u)
		rate = 13.0
		var pulse := 0.5 + 0.5 * sin(t * (10.0 + 30.0 * u))
		glow = KNUCK_E * (1.0 + 0.45 * smoothstep(0.1, 0.9, u) + 0.35 * u * pulse)
		ks = 1.0 + 0.22 * smoothstep(0.1, 0.8, u) + 0.05 * u * pulse
	elif state == "ring":
		var u := state_t
		_anim_ring(tgt, u)
		rate = 30.0 if u < SLAM_T else 9.0
		var hit := clampf((u - SLAM_T) / 0.2, 0.0, 1.0)
		glow = KNUCK_E * (2.2 - 1.2 * hit) if u >= SLAM_T else KNUCK_E * 1.6
		ks = 1.25 + 0.25 * (1.0 - hit) if u >= SLAM_T else 1.22
		# écrasement à l'impact
		var sq := (1.0 - hit) * (1.0 if u >= SLAM_T else 0.0)
		model.scale = Vector3(1.0 + 0.05 * sq, 1.0 - 0.07 * sq, 1.0 + 0.05 * sq)
	else:
		_anim_walk(tgt, dt)
	_apply(tgt, dt, rate)
	_swing_chain(dt)
	_energy(_knuck_mat, glow)
	_scaled("knuck_r_glow", ks)
	_scaled("knuck_l_glow", ks)
	_energy(_shade_mat, SHADE_E * (0.85 + 0.15 * sin(t * 1.7 + _seed)))


## Marche lourde et chaloupée : foulée courte, buste qui roule d'une épaule sur l'autre et tourne,
## choc à chaque pas, bras écartés qui balancent en opposition, tête qui reste droite (il fixe sa cible).
func _anim_walk(tgt: Dictionary, dt: float) -> void:
	var go := clampf(speed * 2.0, 0.0, 1.0)
	phase += dt * (4.0 + 2.4 * speed) * go
	var amp := clampf(speed * 1.5, 0.0, 1.0)
	var s := sin(phase)
	var c := cos(phase)
	var a := 0.42 * amp
	tgt["leg_r"] = [Vector3(-s * a, 0, -0.05), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(s * a, 0, 0.05), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(maxf(0.0, c) * 0.75 * amp, 0, 0.05), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(maxf(0.0, -c) * 0.75 * amp, 0, -0.05), Vector3.ZERO]
	var spread := 0.4 * (1.0 - cos(a * s))
	var stomp := pow(absf(s), 6.0) * 0.03 * amp
	var lift := (1.0 - absf(s)) * 0.02 * amp
	var breathe := sin(t * 1.9 + _seed) * 0.012 * (1.0 - amp)
	# épaules qui roulent : roulis marqué, rotation du buste, léger penché en avant
	var roll := s * 0.1 * amp
	var twist := -s * 0.16 * amp
	tgt["torso"] = [Vector3(0.05 + 0.06 * amp, twist, roll), Vector3(0, -spread - stomp + lift + breathe, 0)]
	tgt["head"] = [Vector3(-0.06 * amp + sin(phase * 2.0 - 0.7) * 0.03 * amp, -twist * 0.85 + sin(t * 0.6 + _seed) * 0.15 * (1.0 - amp), -roll * 0.8), Vector3.ZERO]
	var sw := sin(phase - 0.5)
	var idle := sin(t * 1.5 + _seed) * 0.04 * (1.0 - amp)
	tgt["arm_r"] = [Vector3(sw * 0.3 * amp + idle, 0, -0.16 - 0.04 * absf(s) * amp), Vector3.ZERO]
	tgt["arm_l"] = [Vector3(-sw * 0.3 * amp + idle, 0, 0.16 + 0.04 * absf(s) * amp), Vector3.ZERO]
	tgt["fore_r"] = [Vector3(-0.32 - 0.12 * amp + sin(phase - 1.1) * 0.15 * amp, 0, 0), Vector3.ZERO]
	tgt["fore_l"] = [Vector3(-0.32 - 0.12 * amp - sin(phase - 1.1) * 0.15 * amp, 0, 0), Vector3.ZERO]


## Préparation : se cabre, jambes campées, deux poings joints levés au-dessus de la tête, qui tremblent.
func _anim_tell(tgt: Dictionary, u: float) -> void:
	var up := smoothstep(0.0, 0.3, u)
	var shake := (0.012 + 0.06 * u * u) * up
	var n1 := _noise(t)
	var n2 := _noise(t + 4.7)
	var n3 := _noise(t + 9.1)
	var rear := -0.2 * up
	tgt["torso"] = [Vector3(rear, 0, 0), Vector3(0, 0.03 * up - 0.03 * u, -0.02 * up)]
	_jit["torso"] = [Vector3(n3 * shake * 0.2, 0, n1 * shake * 0.25), Vector3.ZERO]
	tgt["leg_r"] = [Vector3(-rear + 0.08 * up, 0, -0.16 * up), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(-rear - 0.1 * up, 0, 0.16 * up), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(0.18 * up, 0, 0.14 * up), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(0.24 * up, 0, -0.14 * up), Vector3.ZERO]
	tgt["head"] = [Vector3(0.12 * up, 0, 0), Vector3.ZERO]
	_jit["head"] = [Vector3(n2 * shake * 0.3, n1 * shake * 0.3, 0), Vector3.ZERO]
	# bras levés, coudes pliés : les deux poings se rejoignent au-dessus de la tête
	# bras retournés (demi-tour sur leur axe) : les poings américains regardent vers l'avant et le haut
	tgt["arm_r"] = [Vector3(-3.3 * up, PI * up, 0.0), Vector3.ZERO]
	tgt["arm_l"] = [Vector3(-3.3 * up, -PI * up, 0.0), Vector3.ZERO]
	tgt["fore_r"] = [Vector3(-0.35 - 0.45 * up, 0, 0), Vector3.ZERO]
	tgt["fore_l"] = [Vector3(-0.35 - 0.45 * up, 0, 0), Vector3.ZERO]
	_jit["arm_r"] = [Vector3(n1 * shake, 0, n2 * shake * 0.5), Vector3.ZERO]
	_jit["arm_l"] = [Vector3(n3 * shake, 0, -n1 * shake * 0.5), Vector3.ZERO]


## Frappe : il plonge, s'accroupit et abat les deux poings au sol devant lui (impact à SLAM_T), puis se
## redresse à moitié pendant que l'onde part (dessinée par le jeu).
func _anim_ring(tgt: Dictionary, u: float) -> void:
	var rec := smoothstep(SLAM_T + 0.1, RING_TIME, u) * 0.35
	var bend := 0.55 * (1.0 - rec)
	var drop := -0.16 * (1.0 - rec)
	tgt["torso"] = [Vector3(bend, 0, 0), Vector3(0, drop, 0.05)]
	tgt["leg_r"] = [Vector3(-bend - 0.75 * (1.0 - rec), 0, -0.22), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(-bend - 0.75 * (1.0 - rec), 0, 0.22), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(1.0 * (1.0 - rec), 0, 0.12), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(1.0 * (1.0 - rec), 0, -0.12), Vector3.ZERO]
	tgt["head"] = [Vector3(-0.35, 0, 0), Vector3.ZERO]
	tgt["arm_r"] = [Vector3(-0.85 + 0.2 * rec, 0, 0.12), Vector3.ZERO]
	tgt["arm_l"] = [Vector3(-0.85 + 0.2 * rec, 0, -0.12), Vector3.ZERO]
	tgt["fore_r"] = [Vector3(-0.05, 0, 0), Vector3.ZERO]
	tgt["fore_l"] = [Vector3(-0.05, 0, 0), Vector3.ZERO]
	if u >= SLAM_T:
		var hk := 1.0 - clampf((u - SLAM_T) / 0.12, 0.0, 1.0)
		_jit["torso"] = [Vector3(0.04 * hk, 0, 0), Vector3(0, -0.02 * hk, 0)]
		_jit["head"] = [Vector3(0.12 * hk, 0, 0), Vector3.ZERO]


## Mort : chancelle, bascule à la renverse d'un bloc (pivot aux talons), bras en croix ; les lunettes
## s'envolent en tournoyant et retombent ; les poings et le reflet s'éteignent.
func animate_death(dt_total: float) -> void:
	var dt := dt_total - _die_last
	if dt < 0.0 or dt > 0.25:
		dt = 0.016
	_die_last = dt_total
	var k0 := smoothstep(0.0, 0.15, dt_total)
	var kf := clampf((dt_total - 0.1) / 0.42, 0.0, 1.0)
	var fall := kf * kf  # accélère comme un arbre qui tombe
	var tgt := {}
	tgt["torso"] = [Vector3(-0.12 * k0, 0.15 * k0, 0.06 * k0), Vector3.ZERO]
	tgt["head"] = [Vector3(-0.3 * fall + 0.2 * k0 * (1.0 - fall), 0.2 * k0, 0), Vector3.ZERO]
	tgt["arm_r"] = [Vector3(-0.4 * fall, 0, -0.3 * k0 - 1.0 * fall), Vector3.ZERO]
	tgt["arm_l"] = [Vector3(-0.4 * fall, 0, 0.3 * k0 + 1.0 * fall), Vector3.ZERO]
	tgt["fore_r"] = [Vector3(-0.2, 0, 0), Vector3.ZERO]
	tgt["fore_l"] = [Vector3(-0.2, 0, 0), Vector3.ZERO]
	tgt["leg_r"] = [Vector3(-0.15 * fall, 0, -0.08), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(-0.3 * fall, 0, 0.08), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(0.1, 0, 0), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(0.3 * fall, 0, 0), Vector3.ZERO]
	# lunettes : s'envolent vers le haut et l'avant, tournoient, retombent (dans le repère de la tête)
	# (repère de la tête : quand il est couché, +Z regarde le ciel ; elles finissent sur son torse)
	var ss := clampf((dt_total - 0.05) / 0.6, 0.0, 1.0)
	var se := smoothstep(0.0, 1.0, ss)
	var arc := sin(PI * ss)
	tgt["shades"] = [Vector3(-TAU * se, 0.6 * arc, 0.3 * arc), Vector3(0.04 * arc, 0.32 * arc - 0.42 * se, 0.2 * arc + 0.14 * se)]
	_apply(tgt, dt, 20.0)
	_pose("shades", tgt["shades"][0], tgt["shades"][1])  # sans lissage : trajectoire exacte
	# bascule à la renverse autour des talons, rebond à l'impact
	var bounce := sin(clampf((dt_total - 0.52) / 0.14, 0.0, 1.0) * PI) * 0.05
	model.rotation = Vector3(-1.42 * fall + bounce, 0, 0.08 * k0)
	model.position = Vector3(0, 0.22 * fall + bounce * 0.4, -0.12 * fall)
	model.scale = Vector3.ONE
	var fade := 1.0 - smoothstep(0.2, 0.6, dt_total)
	var flick := 1.0 if fmod(dt_total * 23.0, 1.0) < 0.6 else 0.4
	_energy(_knuck_mat, KNUCK_E * (0.15 + 0.85 * fade * flick))
	_energy(_shade_mat, SHADE_E * (0.2 + 0.8 * fade))


func revive() -> void:
	super.revive()
	_die_last = 0.0
	model.scale = Vector3.ONE
