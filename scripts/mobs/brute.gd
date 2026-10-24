extends "res://scripts/rig3d.gd"
## Colosse (« brute ») : gros marcheur blindé à bras-marteaux. Modèle : assets/chars3d/brute.glb
## (ou brute_elite.glb), sculpté par tools/chars/brute.py.
## Parts : torso, core_glow, back_glow, head, head_glow, arm_r/l + fore_r/l (poing), pad_r/l (épaulières,
## enfants du torse : elles suivent le bras à moitié et se haussent quand il se lève), leg_r/l + shin_r/l (pied).
## États : « move » marche lourde (rebond, balancement des épaules, bras qui ballottent) ;
## « tell » (0,7 s) bras-marteaux levés au-dessus de la tête qui tremblent, buste cabré, réacteur qui chauffe ;
## « charge » (0,45 s) penché en avant, foulée rapide, poings en bélier. Mort : à genoux puis affaissé.

const TELL_TIME := 0.7
## La couleur du GLB est multipliée par cette énergie : à 3, les yeux rouges viraient au rose et le réacteur au blanc.
const GLOW_SCALE := 0.55
const GLOW_SCALE_GOLD := 0.42

var _cur := {}  # nom -> [rotation, décalage] lissés
var _jit := {}  # nom -> [rotation, décalage] ajoutés après lissage (tremblements, chocs)
var _glow_base := 3.0
var _core_mat: StandardMaterial3D
var _back_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _heat := 0.0  # chauffe lissée du réacteur (0 repos, 1 prêt à charger)
var _die_last := 0.0

const PARTS := ["torso", "head", "arm_r", "arm_l", "pad_r", "pad_l", "fore_r", "fore_l", "leg_r", "leg_l", "shin_r", "shin_l", "core_glow"]


func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	super.setup(path, tint, glow_energy)
	_glow_base = glow_energy * (GLOW_SCALE_GOLD if elite else GLOW_SCALE)
	_core_mat = _own_glow("core_glow")
	_back_mat = _own_glow("back_glow")
	_eye_mat = _own_glow("head_glow")
	for n in PARTS:
		_cur[n] = [Vector3.ZERO, Vector3.ZERO]


## Matériau lumineux propre à cette instance (pour faire pulser le réacteur sans toucher les autres).
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


## Cibles lissées puis appliquées (les changements d'état se fondent au lieu de sauter).
func _apply(tgt: Dictionary, dt: float, rate: float) -> void:
	var k := 1.0 - exp(-dt * rate)
	for side in ["r", "l"]:
		var pn: String = "pad_" + side
		if tgt.has(pn):
			continue
		var ar: Vector3 = (tgt.get("arm_" + side, [Vector3.ZERO, Vector3.ZERO]) as Array)[0]
		var raise := clampf(-ar.x / 2.5, 0.0, 1.0)
		var out := -1.0 if side == "r" else 1.0
		tgt[pn] = [Vector3(ar.x * 0.12, 0, ar.z * 0.2 + out * 0.22 * raise), Vector3(0, 0.06 * raise, 0)]
	for n in PARTS:
		var c: Array = _cur.get(n, [Vector3.ZERO, Vector3.ZERO])
		var g: Array = tgt.get(n, [Vector3.ZERO, Vector3.ZERO])
		c[0] = (c[0] as Vector3).lerp(g[0], k)
		c[1] = (c[1] as Vector3).lerp(g[1], k)
		_cur[n] = c
		var j: Array = _jit.get(n, [Vector3.ZERO, Vector3.ZERO])
		_pose(n, c[0] + j[0], c[1] + j[1])
	_jit.clear()


func animate(dt: float) -> void:
	var tgt := {}
	var rate := 11.0
	var heat_goal := 0.0
	var core_scale := 1.0
	if state == "tell":
		heat_goal = _anim_tell(tgt)
		rate = 16.0
		var u := clampf(state_t / TELL_TIME, 0.0, 1.0)
		core_scale = 1.0 + 0.28 * u + 0.07 * u * sin(t * (14.0 + 30.0 * u))
	elif state == "charge":
		_anim_charge(tgt, dt)
		heat_goal = 0.9
		rate = 20.0
		core_scale = 1.15
	else:
		_anim_walk(tgt, dt)
		core_scale = 1.0 + 0.04 * sin(t * 3.0)
	_apply(tgt, dt, rate)
	var c := p("core_glow")
	if c != null:
		c.scale = Vector3.ONE * core_scale
	# réacteur : respiration lente au repos, pulsations de plus en plus rapides et fortes en « tell »
	_heat = lerpf(_heat, heat_goal, 1.0 - exp(-dt * 12.0))
	var pulse := 0.12 * sin(t * 3.0) * (1.0 - _heat)
	if state == "tell":
		var u := clampf(state_t / TELL_TIME, 0.0, 1.0)
		pulse = 0.9 * u * (0.5 + 0.5 * sin(t * (10.0 + 34.0 * u)))
	_set_energy(_core_mat, _glow_base * (1.0 + pulse + 1.8 * _heat))
	_set_energy(_back_mat, _glow_base * (1.0 + pulse * 0.8 + 1.2 * _heat))
	_set_energy(_eye_mat, _glow_base * (1.0 + 0.8 * _heat))


## Marche lourde : foulée raide, genou qui plie en avançant, choc au contact, buste qui roule et tourne,
## bras qui ballottent en retard sur le pas.
func _anim_walk(tgt: Dictionary, dt: float) -> void:
	var go := clampf(speed * 2.0, 0.0, 1.0)
	phase += dt * (4.2 + 2.6 * speed) * go
	var amp := clampf(speed * 1.4, 0.0, 1.0)
	var s := sin(phase)
	var c := cos(phase)
	var a := 0.46 * amp
	var lr := -s * a
	var ll := s * a
	tgt["leg_r"] = [Vector3(lr, 0, 0), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(ll, 0, 0), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(maxf(0.0, c) * 0.85 * amp, 0, 0), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(maxf(0.0, -c) * 0.85 * amp, 0, 0), Vector3.ZERO]
	# hauteur : le pied d'appui reste au sol (compense l'écart des jambes), choc au contact
	var spread := 0.5 * (1.0 - cos(a * s))
	var stomp := pow(absf(s), 6.0) * 0.025 * amp
	var lift := (1.0 - absf(s)) * 0.022 * amp
	var breathe := sin(t * 2.0) * 0.012 * (1.0 - amp)
	tgt["torso"] = [Vector3(0.07 + 0.07 * amp, -s * 0.13 * amp, s * 0.06 * amp), Vector3(0, -spread - stomp + lift + breathe, 0)]
	tgt["head"] = [Vector3(-0.05 - 0.04 * amp + sin(phase * 2.0 - 0.8) * 0.04 * amp, s * 0.09 * amp, -s * 0.04 * amp), Vector3.ZERO]
	var sw := sin(phase - 0.55)
	var sw2 := sin(phase - 1.2)
	var idle := sin(t * 1.6) * 0.04 * (1.0 - amp)
	tgt["arm_r"] = [Vector3(sw * 0.34 * amp + idle, 0, -0.06 - 0.05 * absf(s) * amp), Vector3.ZERO]
	tgt["arm_l"] = [Vector3(-sw * 0.34 * amp + idle, 0, 0.06 + 0.05 * absf(s) * amp), Vector3.ZERO]
	tgt["fore_r"] = [Vector3(-0.22 - 0.12 * amp + sw2 * 0.22 * amp, 0, 0), Vector3.ZERO]
	tgt["fore_l"] = [Vector3(-0.22 - 0.12 * amp - sw2 * 0.22 * amp, 0, 0), Vector3.ZERO]


## Préparation de la charge : se cabre, bras-marteaux au-dessus de la tête qui tremblent de plus en plus.
func _anim_tell(tgt: Dictionary) -> float:
	var u := clampf(state_t / TELL_TIME, 0.0, 1.0)
	var up := smoothstep(0.0, 0.32, u)
	var shake := (0.015 + 0.07 * u * u) * up
	var n1 := _noise(t)
	var n2 := _noise(t + 4.7)
	var n3 := _noise(t + 9.1)
	var rear := -0.34 * up
	tgt["torso"] = [Vector3(rear, 0, 0), Vector3(0, 0.035 * up, -0.03 * up)]
	_jit["torso"] = [Vector3(n3 * shake * 0.25, 0, n1 * shake * 0.3), Vector3(n2 * shake * 0.12, 0, 0)]
	# jambes écartées et campées (compensent le buste cabré pour rester d'aplomb)
	tgt["leg_r"] = [Vector3(-rear + 0.12 * up, 0, -0.1 * up), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(-rear - 0.22 * up, 0, 0.1 * up), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(0.22 * up, 0, 0), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(0.3 * up, 0, 0), Vector3.ZERO]
	tgt["head"] = [Vector3(0.22 * up, 0, 0), Vector3.ZERO]
	_jit["head"] = [Vector3(n2 * shake * 0.4, n1 * shake * 0.4, 0), Vector3.ZERO]
	# bras levés, coudes pliés : les deux masses se rejoignent au-dessus de la tête
	tgt["arm_r"] = [Vector3(-2.55 * up, 0, 0.3 * up), Vector3.ZERO]
	tgt["arm_l"] = [Vector3(-2.55 * up, 0, -0.3 * up), Vector3.ZERO]
	tgt["fore_r"] = [Vector3(-0.22 - 0.5 * up, 0, 0), Vector3.ZERO]
	tgt["fore_l"] = [Vector3(-0.22 - 0.5 * up, 0, 0), Vector3.ZERO]
	_jit["arm_r"] = [Vector3(n1 * shake, 0, n2 * shake * 0.6), Vector3.ZERO]
	_jit["arm_l"] = [Vector3(n3 * shake, 0, -n1 * shake * 0.6), Vector3.ZERO]
	_jit["core_glow"] = [Vector3.ZERO, Vector3(0, 0, 0.012 * u * (0.5 + 0.5 * sin(t * 40.0)))]
	return 0.25 + 0.75 * u


## Charge : penché fort en avant, foulée rapide et haute, poings tendus en bélier.
func _anim_charge(tgt: Dictionary, dt: float) -> void:
	phase += dt * 16.0
	var s := sin(phase)
	var c := cos(phase)
	var a := 0.62
	var lean := 0.52
	tgt["torso"] = [Vector3(lean, -s * 0.08, s * 0.05), Vector3(0, -0.06 + absf(c) * 0.04, 0.05)]
	tgt["leg_r"] = [Vector3(-s * a - 0.38, 0, 0), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(s * a - 0.38, 0, 0), Vector3.ZERO]
	tgt["shin_r"] = [Vector3(0.25 + maxf(0.0, c) * 1.1, 0, 0), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(0.25 + maxf(0.0, -c) * 1.1, 0, 0), Vector3.ZERO]
	tgt["head"] = [Vector3(-0.42, 0, 0), Vector3.ZERO]
	tgt["arm_r"] = [Vector3(-1.5 + s * 0.08, 0, 0.12), Vector3.ZERO]
	tgt["arm_l"] = [Vector3(-1.5 - s * 0.08, 0, -0.12), Vector3.ZERO]
	tgt["fore_r"] = [Vector3(-0.4, 0, 0), Vector3.ZERO]
	tgt["fore_l"] = [Vector3(-0.4, 0, 0), Vector3.ZERO]


## Mort : les genoux lâchent (il tombe à genoux), puis le buste s'affaisse en avant, bras ballants ;
## les lumières s'éteignent.
func animate_death(dt_total: float) -> void:
	var dt := dt_total - _die_last
	if dt < 0.0 or dt > 0.25:
		dt = 0.016
	_die_last = dt_total
	var k1 := smoothstep(0.0, 0.24, dt_total)
	var k2 := smoothstep(0.18, 0.5, dt_total)
	var tgt := {}
	tgt["shin_r"] = [Vector3(1.45 * k1, 0, 0), Vector3.ZERO]
	tgt["shin_l"] = [Vector3(1.45 * k1, 0, 0), Vector3.ZERO]
	tgt["leg_r"] = [Vector3(-0.2 * k1 - 0.5 * k2, 0, -0.12 * k1), Vector3.ZERO]
	tgt["leg_l"] = [Vector3(-0.2 * k1 - 0.5 * k2, 0, 0.12 * k1), Vector3.ZERO]
	tgt["torso"] = [Vector3(0.12 * k1 + 0.5 * k2, 0, 0.06 * k2), Vector3(0, 0, 0)]
	tgt["head"] = [Vector3(0.45 * k2, 0, 0.15 * k2), Vector3.ZERO]
	tgt["arm_r"] = [Vector3(-0.25 * k1 - 0.2 * k2, 0, -0.25 * k2), Vector3.ZERO]
	tgt["arm_l"] = [Vector3(-0.25 * k1 - 0.2 * k2, 0, 0.25 * k2), Vector3.ZERO]
	tgt["fore_r"] = [Vector3(-0.1 - 0.3 * k2, 0, 0), Vector3.ZERO]
	tgt["fore_l"] = [Vector3(-0.1 - 0.3 * k2, 0, 0), Vector3.ZERO]
	_apply(tgt, dt, 22.0)
	# le corps descend jusqu'aux genoux (petit rebond à l'impact), puis s'écrase un peu plus
	var bounce := sin(clampf((dt_total - 0.24) / 0.16, 0.0, 1.0) * PI) * 0.03
	model.position.y = -0.2 * k1 - 0.05 * k2 + bounce
	model.position.z = 0.04 * k2
	var fade := 1.0 - smoothstep(0.15, 0.5, dt_total)
	_set_energy(_core_mat, _glow_base * (0.15 + 0.85 * fade + 1.5 * (1.0 - k1) * 0.5))
	_set_energy(_back_mat, _glow_base * (0.15 + 0.85 * fade))
	_set_energy(_eye_mat, _glow_base * (0.1 + 0.9 * fade))


func revive() -> void:
	super.revive()
	_die_last = 0.0
