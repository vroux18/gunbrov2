extends "res://scripts/rig3d.gd"
## Garde du Portique (tools/chars/trooper.py) : marche martiale, fusil tenu à deux mains en garde basse,
## épaulé net quand il vise (léger tremblement de charge, visière qui pulse), recul au tir,
## mort : tombe à genoux puis s'effondre vers l'avant.

const SC := 1.06  # échelle du sculpt (tools/chars/trooper.py : SCALE)
const FOREGRIP := Vector3(0.0, -0.17, 0.035) * SC  # point du fusil saisi par la main gauche (repère de l'arme)

## Rouge profond : la couleur du GLB est multipliée par cette énergie (au-delà de ~2, le rouge vire au rose pâle).
const GLOW_SCALE := 0.4

var _visor_mat: StandardMaterial3D
var _gun_mat: StandardMaterial3D
var _band_mat: StandardMaterial3D
var _glow_base := 3.0
var _aim := 0.0  # 0 garde basse -> 1 épaulé

func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	super.setup(path, tint, glow_energy)
	walk_amp = 0.8
	_glow_base = glow_energy * GLOW_SCALE
	# matériaux propres à ce garde : la visière et le canon pulsent quand il vise
	_visor_mat = _new_glow()
	_gun_mat = _new_glow()
	_band_mat = _new_glow()
	for mi in meshes:
		var m: MeshInstance3D = mi
		var owner_name := String(m.get_parent().name) + String(m.name)
		if "head_glow" in owner_name:
			m.material_override = _visor_mat
		elif "gun_glow" in owner_name:
			m.material_override = _gun_mat
		elif "_glow" in owner_name:
			m.material_override = _band_mat

func _new_glow() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(_glow_base, _glow_base, _glow_base)
	return m

## Bras rigide orienté pour que la main vise `target` (repère du parent).
func _reach(name: String, target: Vector3, twist: float = 0.0) -> void:
	var n := p(name)
	if n == null:
		return
	var r: Transform3D = rest[name]
	var hand_rest := Vector3(signf(r.origin.x) * 0.02, -0.285, 0.02) * SC
	var d := target - r.origin
	if d.length() < 0.01:
		return
	var q := Quaternion(hand_rest.normalized(), d.normalized())
	n.transform = Transform3D(Basis(q) * Basis(Vector3.UP, twist), r.origin)

func animate(dt: float) -> void:
	phase += dt * (5.2 + 5.0 * speed) * clampf(speed * 2.0, 0.0, 1.0)
	var s := sin(phase)
	var c := cos(phase)
	var amp := clampf(speed * 1.4, 0.0, 1.0) * walk_amp
	var aiming := state == "aim" or shooting > 0.5
	_aim = move_toward(_aim, 1.0 if aiming else 0.0, dt * 7.0)
	var a := smoothstep(0.0, 1.0, _aim)
	var charge := clampf(state_t / 0.38, 0.0, 1.0) * a if state == "aim" else 0.0
	var breathe := sin(t * 2.2) * 0.01 * (1.0 - amp)
	# jambes : foulée raide, genou peu fléchi (pièce rigide), pas martelé
	var kick := s * 0.62 * amp
	_pose("leg_r", Vector3(kick, 0, 0))
	_pose("leg_l", Vector3(-kick, 0, 0))
	# torse : rebond sec, peu de roulis ; s'efface d'un quart de tour pour épauler
	var bob := pow(absf(c), 0.6) * 0.03 * amp
	var shake := Vector3(sin(t * 61.0), sin(t * 47.0 + 1.3), 0) * 0.012 * charge
	_pose("torso", Vector3(0.05 * amp - 0.04 * recoil, s * 0.05 * amp * (1.0 - a) - 0.28 * a, c * 0.025 * amp), Vector3(0, bob + breathe - 0.015 * a, -0.02 * recoil))
	# tête : regard fixe, compense la torsion du torse, se penche sur la visée
	_pose("head", Vector3(-c * 0.03 * amp + 0.1 * a, -s * 0.04 * amp + 0.26 * a, -0.06 * a))
	# main droite : garde basse (devant la hanche) -> épaulé (sous le menton)
	var hand_low := Vector3(-0.1, 0.13, 0.21) + Vector3(0, -absf(s) * 0.012 * amp, s * 0.015 * amp)
	var hand_aim := Vector3(-0.07, 0.24, 0.21) + Vector3(0, 0, -0.05 * recoil)
	_reach("arm_r", (hand_low.lerp(hand_aim, a) + shake * 0.5) * SC, 0.0)
	# fusil : canon pointé vers l'avant, incliné vers le sol en garde basse ; relevé par le recul
	var arm_r := p("arm_r")
	var gun := p("gun")
	if arm_r != null and gun != null:
		var pitch := lerpf(0.14, 0.0, a) - recoil * 0.3
		var yaw := lerpf(0.1, 0.28, a)  # compense la torsion du torse : vise droit devant
		var want := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5 + pitch)
		var shake_b := Basis.from_euler(shake * 1.5)
		gun.transform = Transform3D(arm_r.transform.basis.inverse() * want * shake_b, rest["gun"].origin)
		# main gauche : sur le garde-main
		var grip := arm_r.transform * gun.transform * FOREGRIP
		_reach("arm_l", grip, 0.0)
	# lueurs : la visière et le canon se chargent pendant la visée
	if _visor_mat != null:
		var pulse := 0.5 + 0.5 * sin(t * 22.0)
		var e := _glow_base * (1.0 + charge * (0.12 + 0.3 * pulse) + recoil * 0.25)
		_visor_mat.albedo_color = Color(e, e, e)
		var ge := _glow_base * (1.0 + charge * 0.8 + recoil * 1.2)
		_gun_mat.albedo_color = Color(ge, ge, ge)

## Mort : genoux qui lâchent, buste qui s'affaisse, puis chute face contre terre (~0,6 s).
func animate_death(dt_total: float) -> void:
	var k1 := clampf(dt_total / 0.22, 0.0, 1.0)  # à genoux
	var k2 := clampf((dt_total - 0.18) / 0.42, 0.0, 1.0)  # bascule vers l'avant
	var e1 := 1.0 - pow(1.0 - k1, 3.0)
	var e2 := k2 * k2
	var knee := e1 * (1.0 - 0.8 * e2)  # à genoux, puis les jambes s'allongent dans la chute
	_pose("leg_r", Vector3(1.25 * knee, 0, 0.06 * e1))
	_pose("leg_l", Vector3(1.1 * knee, 0, -0.06 * e1))
	_pose("torso", Vector3(0.25 * e1, 0, 0.05 * e1), Vector3(0, -0.02 * e1, 0))
	_pose("head", Vector3(0.35 * e1 - 0.3 * e2, 0.15 * e1, 0))
	_pose("arm_r", Vector3(-0.4 * e1 - 2.2 * e2, 0, 0.2))
	_pose("arm_l", Vector3(-0.3 * e1 - 2.4 * e2, 0, -0.25))
	_pose("gun", Vector3(-0.6 * e1, 0, 0.5 * e1))
	model.rotation.x = 1.42 * e2
	model.position = Vector3(0, -0.2 * e1 + 0.32 * e2, 0.12 * e2)
	if _visor_mat != null:
		var e := _glow_base * maxf(0.0, 1.0 - dt_total * 1.6)
		_visor_mat.albedo_color = Color(e, e, e)
