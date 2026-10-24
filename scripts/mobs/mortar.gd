extends "res://scripts/rig3d.gd"
## Mortier (« mortar ») : petit robot d'artillerie à quatre pattes et gros tube dorsal. Modèle :
## assets/chars3d/mortar.glb (ou mortar_elite.glb), sculpté par tools/chars/mortar.py.
## Parts : body (racine) > head > head_glow, body_glow, tube > muzzle_glow, leg_fr/fl/br/bl.
## États : « move » trot en diagonale, tube couché en arrière qui ballotte (ressort amorti) ;
## « tell » (0,9 s) se plante (pattes écartées, châssis bas), tube levé à ~60° vers l'avant, bouche qui
## s'illumine de plus en plus ; fire() : gros recul, châssis écrasé, tube qui rebondit.
## Mort : les pattes s'écartent, le châssis s'affaisse au sol, le tube retombe en arrière.

const TELL_TIME := 0.9
const TUBE_CARRY := -0.7  # tube couché en arrière (~40° sous la verticale)
const TUBE_FIRE := 0.52  # tube levé : ~60° au-dessus de l'horizontale, vers l'avant
const LEGS := {"fr": Vector2(-1, 1), "fl": Vector2(1, 1), "br": Vector2(-1, -1), "bl": Vector2(1, -1)}
## Énergie des lueurs : vers 1, le vert du GLB rend #9BE15D ; au-delà de ~1,6 il vire au jaune pâle.
const MOUTH_E := 1.0
const EYE_E := 1.0

var _eye_mat: StandardMaterial3D
var _mouth_mat: StandardMaterial3D
var _led_mat: StandardMaterial3D
var _ta := TUBE_CARRY  # angle du tube (ressort amorti)
var _tv := 0.0
var _tr := 0.0  # roulis du tube
var _trv := 0.0
var _fire_t := 10.0  # temps depuis le dernier tir
var _plant := 0.0  # 0 trot -> 1 planté
var _seed := -1.0
var _die_last := 0.0
var _beat_ph := 0.0  # phase de la pulsation (accumulée : sa fréquence monte pendant la préparation)


func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	super.setup(path, tint, glow_energy)
	_eye_mat = _own_glow("head_glow", EYE_E)
	_mouth_mat = _own_glow("muzzle_glow", MOUTH_E)
	_led_mat = _own_glow("body_glow", EYE_E)


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


## Bouche du tube (les obus partent d'ici).
func muzzle_position() -> Vector3:
	var m := p("muzzle_glow")
	if m == null:
		return super.muzzle_position()
	return m.global_transform.origin


func fire() -> void:
	super.fire()
	_fire_t = 0.0
	_tv -= 7.0  # le tube se cabre en arrière puis revient


func revive() -> void:
	super.revive()
	_die_last = 0.0
	_ta = TUBE_CARRY
	_tv = 0.0
	_fire_t = 10.0
	_plant = 0.0


## Ressort amorti du tube (angle et roulis) vers les cibles.
func _spring(dt: float, target: float, roll_target: float, k: float, damp: float) -> void:
	var st := minf(dt, 0.05)
	_tv += ((target - _ta) * k - _tv * damp) * st
	_ta += _tv * st
	_trv += ((roll_target - _tr) * k * 0.8 - _trv * damp) * st
	_tr += _trv * st


## Pose d'une patte : balancier avant/arrière (autour de X), écart vers l'extérieur (autour de Z).
func _leg(nm: String, swing: float, spread: float) -> void:
	var sd: Vector2 = LEGS[nm]
	_pose("leg_" + nm, Vector3(swing, 0, sd.x * spread))


func animate(dt: float) -> void:
	if _seed < 0.0:
		_seed = randf() * TAU
	_fire_t += dt
	var telling := state == "tell"
	var u := clampf(state_t / TELL_TIME, 0.0, 1.0) if telling else 0.0
	_plant = move_toward(_plant, 1.0 if telling else 0.0, dt * (7.0 if telling else 2.5))
	var pl := smoothstep(0.0, 1.0, _plant)
	var go := clampf(speed * 2.0, 0.0, 1.0) * (1.0 - pl)
	phase += dt * (9.0 + 7.0 * speed) * go
	var s := sin(phase)
	var c := cos(phase)
	var amp := clampf(speed * 1.4, 0.0, 1.0) * (1.0 - pl)
	# choc du tir : écrasement puis rebond
	var ft := _fire_t
	var squash := exp(-ft * 9.0) * cos(ft * 24.0) if ft < 0.7 else 0.0
	var kick := exp(-ft * 8.0) if ft < 0.9 else 0.0
	# --- pattes : trot en diagonale (fr+bl / fl+br), patte levée en avançant ; écartées quand il se plante
	var spread := 0.32 * pl + 0.16 * kick + 0.1 * maxf(squash, 0.0)
	for nm in LEGS:
		var sd: Vector2 = LEGS[nm]
		var ph := phase if (nm == "fr" or nm == "bl") else phase + PI
		var sw := -sin(ph) * 0.42 * amp
		var lift := maxf(0.0, cos(ph)) * 0.34 * amp
		_leg(nm, sw + sd.y * 0.06 * pl, spread + lift)
	# --- châssis : rebond du trot, roulis et tangage ; bas quand il se plante ; écrasé au tir
	var bob := absf(c) * 0.028 * amp - 0.008 * amp
	var low := -0.045 * pl - 0.035 * kick
	var breathe := sin(t * 2.6 + _seed) * 0.006 * (1.0 - amp)
	var body := p("body")
	if body != null:
		var r: Transform3D = rest["body"]
		var rot := Vector3(0.05 * amp - 0.06 * pl + 0.12 * kick, sin(phase * 0.5) * 0.04 * amp, s * 0.07 * amp)
		var sq := 1.0 - 0.24 * squash
		var b := Basis.from_euler(rot) * Basis().scaled(Vector3(1.0 + 0.1 * squash, sq, 1.0 + 0.1 * squash))
		body.transform = Transform3D(r.basis * b, r.origin + Vector3(0, bob + low + breathe - 0.06 * maxf(squash, 0.0), -0.06 * kick))
	# --- tête : regarde autour en trottant, se lève vers la cible pendant la préparation
	var look := sin(t * 1.3 + _seed) * 0.25 * (1.0 - pl)
	_pose("head", Vector3(-c * 0.05 * amp - 0.22 * pl + 0.15 * kick, look, s * 0.06 * amp))
	# --- tube : ressort vers sa cible (couché / levé), ballotte au trot, recule le long de son axe au tir
	var target := TUBE_CARRY + sin(phase * 2.0 - 0.9) * 0.09 * amp
	var k := 170.0
	if telling:
		target = lerpf(TUBE_CARRY, TUBE_FIRE, smoothstep(0.0, 0.38, u))
		k = 260.0
	elif ft < 0.9:
		target = TUBE_FIRE * (1.0 - smoothstep(0.35, 0.9, ft)) + TUBE_CARRY * smoothstep(0.35, 0.9, ft)
	var shiver := sin(t * 47.0) * 0.012 * u * u
	_spring(dt, target + shiver, s * 0.1 * amp, k, 13.0)
	var tube := p("tube")
	if tube != null:
		var tr: Transform3D = rest["tube"]
		var tb := Basis.from_euler(Vector3(_ta, 0, _tr))
		tube.transform = Transform3D(tr.basis * tb, tr.origin + tb * Vector3(0, -0.1 * kick, 0))
	# --- lueurs : la bouche se charge pendant la préparation, éclair au tir
	_beat_ph = fmod(_beat_ph + dt * (8.0 + 30.0 * u), TAU)
	var beat := 0.5 + 0.5 * sin(_beat_ph)
	var me := MOUTH_E * (1.0 + 0.05 * sin(t * 3.0 + _seed) + u * u * 0.6 + u * 0.25 * beat + 1.4 * kick)
	_energy(_mouth_mat, me)
	var mg := p("muzzle_glow")
	if mg != null:
		mg.scale = Vector3.ONE * (1.0 + 0.2 * u * u + 0.06 * u * beat + 0.35 * kick)
	_energy(_eye_mat, EYE_E * (1.0 + 0.25 * u + 0.3 * kick))
	_energy(_led_mat, EYE_E * (0.85 + 0.15 * sin(t * 4.0 + _seed) + 0.5 * u * beat))


func animate_death(dt_total: float) -> void:
	var dt := dt_total - _die_last
	if dt < 0.0 or dt > 0.25:
		dt = 0.016
	_die_last = dt_total
	var k1 := smoothstep(0.0, 0.3, dt_total)  # les pattes lâchent
	var k2 := smoothstep(0.05, 0.4, dt_total)
	for nm in LEGS:
		var sd: Vector2 = LEGS[nm]
		_leg(nm, sd.y * -0.25 * k1, 1.0 * k1)
	var bounce := sin(clampf((dt_total - 0.3) / 0.15, 0.0, 1.0) * PI) * 0.025
	var body := p("body")
	if body != null:
		var r: Transform3D = rest["body"]
		body.transform = Transform3D(r.basis * Basis.from_euler(Vector3(0.12 * k2, 0, 0.1 * k2)), r.origin + Vector3(0, -0.16 * k1 + bounce, 0))
	_pose("head", Vector3(0.35 * k2, 0.2 * k2, 0.15 * k2))
	# le tube retombe en arrière avec un rebond, un peu de travers
	_spring(dt, -1.55, 0.35, 150.0, 9.0)
	var tube := p("tube")
	if tube != null:
		tube.transform = Transform3D(rest["tube"].basis * Basis.from_euler(Vector3(_ta, 0, _tr)), rest["tube"].origin)
	var fade := 1.0 - smoothstep(0.1, 0.5, dt_total)
	_energy(_eye_mat, EYE_E * (0.08 + 0.92 * fade))
	_energy(_mouth_mat, MOUTH_E * (0.05 + 0.95 * fade))
	_energy(_led_mat, EYE_E * (0.05 + 0.95 * fade))
	var mg := p("muzzle_glow")
	if mg != null:
		mg.scale = Vector3.ONE * (0.6 + 0.4 * fade)
