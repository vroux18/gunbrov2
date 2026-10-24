extends "res://scripts/rig3d.gd"
## Gyro (« copter ») : drone de police volant. Modèle : assets/chars3d/copter.glb (ou copter_elite.glb),
## sculpté par tools/chars/copter.py.
## Parts : body (racine, centre du corps à y = 0,9) > face_glow (yeux), siren_r_glow / siren_b_glow
## (gyrophares), rotor_fr/fl/br/bl (hélices, tournent autour de Y), lamp (cardan) > lamp_glow,
## gun > muzzle_glow.
## États : « move » flotte, penche dans le sens de son déplacement réel (il tourne autour de Jo), rotors,
## gyrophares rouge et bleu en double éclat alterné, projecteur orienté comme le faisceau dessiné par mob3d ;
## « aim » (rafale de 4 tirs, 0,1 s puis toutes les 0,11 s) : nez qui plonge, yeux plissés, gyrophares
## affolés, recul du canon et du corps à chaque tir (cadencé sur state_t, fire() marque le dernier).
## Mort (~0,7 s) : sursaut, chute en vrille jusqu'au sol, rebond, lumières qui grésillent puis s'éteignent.

const SHOTS := [0.1, 0.21, 0.32, 0.43]  # instants des tirs de la rafale (enemy.gd : _copter)
const BURST_CYCLE := 0.8  # banc d'essai : la rafale se répète (state_t n'y revient jamais à 0)
const BODY_Y := 0.9
const DROP := 0.6  # chute du corps à la mort (le projecteur touche le sol)
## Énergie des lueurs : vers 1, les couleurs du GLB sont fidèles ; au-delà de ~1,6 elles pâlissent.
const EYE_E := 1.0
const SIREN_ON := 1.6
const SIREN_OFF := 0.6
const LAMP_E := 1.25

var _eye_mat: StandardMaterial3D
var _red_mat: StandardMaterial3D
var _blue_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _muzzle_mat: StandardMaterial3D
var _seed := -1.0
var _vel := Vector3.ZERO  # vitesse lissée dans le repère du modèle
var _last_pos := Vector3.ZERO
var _has_last := false
var _spin := [0.0, 0.0, 0.0, 0.0]
var _spin_v := 30.0
var _kick := 0.0  # recul du dernier tir (1 -> 0)
var _since_shot := 10.0
var _prev_u := 0.0
var _aim_k := 0.0  # 0 croisière -> 1 rafale
var _lamp_yaw := 0.0
var _blink := 10.0
var _die_last := 0.0
var _die_spin := 0.0
var _drift := Vector3.ZERO

const ROTORS := ["rotor_fr", "rotor_fl", "rotor_br", "rotor_bl"]
const ROTOR_DIR := [1.0, -1.0, -1.0, 1.0]


func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	super.setup(path, tint, glow_energy)
	_eye_mat = _own_glow("face_glow", EYE_E)
	_red_mat = _own_glow("siren_r_glow", SIREN_OFF)
	_blue_mat = _own_glow("siren_b_glow", SIREN_OFF)
	_lamp_mat = _own_glow("lamp_glow", LAMP_E)
	_muzzle_mat = _own_glow("muzzle_glow", 0.25)


## Matériau lumineux propre à cette instance (clignotements indépendants d'un Gyro à l'autre).
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


func _scaled(name: String, rot: Vector3, off: Vector3, s: Vector3) -> void:
	var n := p(name)
	if n == null:
		return
	var r: Transform3D = rest[name]
	n.transform = Transform3D(r.basis * Basis.from_euler(rot) * Basis.from_scale(s), r.origin + off)


## Visuel de l'ennemi (mob3d.gd) : le rig est sous body, lui-même sous le nœud de l'ennemi. Absent au banc.
func _mob() -> Node:
	var b := get_parent()
	return b.get_parent() if b != null else null


func muzzle_position() -> Vector3:
	var m := p("muzzle_glow")
	return m.global_transform.origin if m != null else super.muzzle_position()


func _shoot() -> void:
	_kick = 1.0
	_since_shot = 0.0


## Le jeu appelle fire() en sortie de rafale : c'est le dernier tir (les trois premiers sont cadencés).
func fire() -> void:
	if _since_shot > 0.07:
		_shoot()


## Double éclat : deux flashs brefs puis une pause, décalés d'une demi-période entre rouge et bleu.
func _flash_on(ph: float) -> float:
	var f := fmod(ph, 1.0)
	return 1.0 if (f < 0.18 or (f > 0.26 and f < 0.44)) else 0.0


func animate(dt: float) -> void:
	if _seed < 0.0:
		_seed = randf() * TAU
	var tt := t + _seed
	var aiming := state == "aim"
	_aim_k = lerpf(_aim_k, 1.0 if aiming else 0.0, 1.0 - exp(-dt * 12.0))
	# --- rafale : tirs cadencés sur le temps passé dans « aim »
	_since_shot += dt
	if aiming:
		var u := fmod(state_t, BURST_CYCLE)
		if u < _prev_u:
			_prev_u = 0.0
		for s in SHOTS:
			if _prev_u < s and u >= s:
				_shoot()
		_prev_u = u
	else:
		_prev_u = 0.0
	_kick = maxf(0.0, _kick - dt * 11.0)
	var kick := _kick * _kick
	# --- vitesse réelle dans le repère du modèle (il orbite autour de Jo), sinon mouvement simulé au banc
	var gp := global_position
	var lv := Vector3.ZERO
	if _has_last and dt > 0.0:
		lv = global_transform.basis.inverse() * ((gp - _last_pos) / dt)
	_last_pos = gp
	_has_last = true
	if lv.length() < 0.05:
		lv = Vector3(sin(tt * 0.9) * 0.9, 0, 0.5) * speed
	_vel = _vel.lerp(lv, 1.0 - exp(-dt * 5.0))
	# --- assiette : penche vers son déplacement, plonge du nez en rafale, se cabre à chaque tir
	var pitch := clampf(_vel.z * 0.2, -0.3, 0.3) + 0.2 * _aim_k - 0.2 * kick + sin(tt * 2.3) * 0.03
	var roll := clampf(-_vel.x * 0.24, -0.34, 0.34) + sin(tt * 1.7) * 0.04
	var bob := sin(tt * 3.2) * 0.022 + sin(tt * 7.9) * 0.004
	var shake := Vector3(sin(t * 63.0), 0, cos(t * 71.0)) * 0.004 * _aim_k
	_pose("body", Vector3(pitch, sin(tt * 1.3) * 0.05 * (1.0 - _aim_k), roll), Vector3(0, bob, -0.03 * kick) + shake)
	# --- hélices : rapides, s'emballent en rafale
	_spin_v = lerpf(_spin_v, 34.0 + 10.0 * clampf(_vel.length(), 0.0, 1.5) + 12.0 * _aim_k, 1.0 - exp(-dt * 4.0))
	for i in range(4):
		_spin[i] = fmod(_spin[i] + dt * _spin_v * (1.0 + 0.07 * i) * ROTOR_DIR[i], TAU)
		_pose(ROTORS[i], Vector3(0, _spin[i], 0))
	# --- gyrophares : double éclat alterné, affolés en rafale
	var freq := 1.7 + 2.3 * _aim_k
	var ph := tt * freq
	_energy(_red_mat, lerpf(SIREN_OFF, SIREN_ON, _flash_on(ph)))
	_energy(_blue_mat, lerpf(SIREN_OFF, SIREN_ON, _flash_on(ph + 0.5)))
	_scaled("siren_r_glow", Vector3.ZERO, Vector3.ZERO, Vector3.ONE * (1.0 + 0.12 * _flash_on(ph)))
	_scaled("siren_b_glow", Vector3.ZERO, Vector3.ZERO, Vector3.ONE * (1.0 + 0.12 * _flash_on(ph + 0.5)))
	# --- yeux : clignent de temps en temps, se plissent en rafale
	_blink += dt
	if _blink > 2.6 + fmod(_seed * 7.0, 1.6):
		_blink = 0.0
	var close := 1.0 - 0.9 * (1.0 - smoothstep(0.0, 0.09, absf(_blink - 0.09))) if _blink < 0.18 else 1.0
	_scaled("face_glow", Vector3(0, 0, 0), Vector3(0, -0.006 * _aim_k, 0), Vector3(1.0 + 0.08 * _aim_k, close * (1.0 - 0.45 * _aim_k), 1.0))
	_energy(_eye_mat, EYE_E * (1.0 + 0.25 * _aim_k))
	# --- projecteur : suit le faisceau du jeu (axe aim_dir) ; au banc, balaie doucement
	var goal := sin(tt * 0.8) * 0.7
	var mob := _mob()
	var beam = mob.get("_beam") if mob != null else null
	var bnode := p("body")
	if beam is Node3D and bnode != null:
		var wd: Vector3 = (beam as Node3D).global_transform.basis.z
		var ld := bnode.global_transform.basis.inverse() * wd
		goal = atan2(ld.x, ld.z)
	_lamp_yaw = lerp_angle(_lamp_yaw, goal, 1.0 - exp(-dt * 14.0))
	_pose("lamp", Vector3(0, _lamp_yaw, 0))
	var strobe := (1.0 if int(t * 24.0) % 2 == 0 else 0.55) if aiming else 1.0
	_energy(_lamp_mat, LAMP_E * (0.9 + 0.1 * sin(tt * 9.0)) * lerpf(1.0, 1.5 * strobe, _aim_k))
	# --- canon : sort un peu en rafale, recule à chaque tir ; bouche qui s'allume
	_pose("gun", Vector3(0.12 * _aim_k - 0.35 * kick, 0, 0), Vector3(0, -0.008 * _aim_k, -0.035 * kick))
	_scaled("muzzle_glow", Vector3.ZERO, Vector3.ZERO, Vector3.ONE * (1.0 + 2.2 * kick))
	_energy(_muzzle_mat, 0.25 + 0.5 * _aim_k + 1.8 * kick)


## Abattu : sursaut, puis chute en vrille (de plus en plus penché) jusqu'au sol, petit rebond ; les hélices
## ralentissent, les lumières grésillent puis s'éteignent, les yeux se ferment.
func animate_death(dt_total: float) -> void:
	var dt := dt_total - _die_last
	if dt < 0.0 or dt > 0.25:
		dt = 0.016
	_die_last = dt_total
	if _seed < 0.0:
		_seed = randf() * TAU
	var fall_t := 0.3
	var k := clampf(dt_total / fall_t, 0.0, 1.0)
	var y := -DROP * k * k
	# rebond au contact puis immobile
	if dt_total > fall_t:
		y = -DROP + 0.06 * sin(clampf((dt_total - fall_t) / 0.16, 0.0, 1.0) * PI)
	# vrille : vitesse qui monte pendant la chute, s'arrête net au sol
	var spin_rate := 22.0 * (0.3 + k) if dt_total < fall_t else 22.0 * maxf(0.0, 1.0 - (dt_total - fall_t) / 0.1)
	_die_spin += dt * spin_rate
	# dérive dans le sens du coup fatal (posé par view3d sur le visuel)
	var mob := _mob()
	var dd = mob.get("death_dir") if mob != null else null
	if dd is Vector3 and (dd as Vector3).length() > 0.01 and _drift == Vector3.ZERO:
		_drift = global_transform.basis.inverse() * (dd as Vector3).normalized()
		_drift.y = 0.0
	var hop := 0.06 * sin(clampf(dt_total / 0.14, 0.0, 1.0) * PI)
	model.position = _drift.normalized() * 0.35 * smoothstep(0.0, 0.35, dt_total) + Vector3(0, y + hop, 0) if _drift != Vector3.ZERO else Vector3(0, y + hop, 0)
	model.rotation = Vector3(0, _die_spin, 0)
	var tilt := 0.42 * smoothstep(0.0, fall_t, dt_total)
	_pose("body", Vector3(0.3 * tilt, 0, tilt), Vector3.ZERO)
	# hélices qui ralentissent ; l'une se tord au choc
	_spin_v = maxf(0.0, _spin_v - dt * 90.0)
	for i in range(4):
		_spin[i] = fmod(_spin[i] + dt * _spin_v * ROTOR_DIR[i], TAU)
		var bend := 0.5 * smoothstep(fall_t, fall_t + 0.08, dt_total) if i == 1 else 0.0
		_pose(ROTORS[i], Vector3(bend, _spin[i], 0))
	# lumières : grésillent pendant la chute, éteintes au sol
	var fade := 1.0 - smoothstep(fall_t - 0.05, fall_t + 0.1, dt_total)
	var crackle := 1.0 if fmod(dt_total * 31.0 + _seed, 1.0) < 0.5 else 0.2
	_energy(_red_mat, lerpf(0.12, SIREN_ON * crackle, fade))
	_energy(_blue_mat, lerpf(0.12, SIREN_ON * (1.2 - crackle), fade))
	_energy(_lamp_mat, lerpf(0.15, LAMP_E * crackle, fade))
	_energy(_eye_mat, lerpf(0.25, EYE_E, fade))
	_scaled("face_glow", Vector3.ZERO, Vector3.ZERO, Vector3(1.0, lerpf(0.12, 1.0, fade), 1.0))
	_energy(_muzzle_mat, 0.2)


func revive() -> void:
	super.revive()
	_die_last = 0.0
	_die_spin = 0.0
	_drift = Vector3.ZERO
	_spin_v = 30.0
