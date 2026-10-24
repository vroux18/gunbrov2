extends "res://scripts/rig3d.gd"
## Sentinelle (drone) : flotte en se dandinant, pique du nez et s'incline quand elle fonce, anneau de
## propulsion qui tourne plus vite avec la vitesse, œil qui pulse, antennes et ailerons qui traînent.
## Mort : vrille sur elle-même et tombe au sol en ~0,25 s, l'œil s'éteint.

var _spin := 0.0
var _seed := -1.0
var _bank := 0.0

func _phase() -> float:
	if _seed < 0.0:
		_seed = randf() * TAU  # chaque drone de l'essaim flotte à son rythme
	return _seed

func _scale_part(name: String, s: float) -> void:
	var n := p(name)
	if n == null:
		return
	var r: Transform3D = rest[name]
	n.transform = Transform3D(r.basis.scaled_local(Vector3.ONE * s), r.origin)

func animate(dt: float) -> void:
	var ph := _phase()
	var sp := clampf(speed, 0.0, 1.0)
	var tt := t + ph
	# flottement : grande ondulation lente + petit frémissement, plus serré en vitesse
	var bob := sin(tt * 3.1) * 0.028 * (1.0 - 0.4 * sp) + sin(tt * 8.3) * 0.005
	# tangage : nez vers le bas en fonçant (+X incline l'avant vers le bas), roulis : louvoie en essaim
	var pitch := 0.22 * sp + sin(tt * 2.3) * 0.05 + sin(tt * 3.1 + 0.6) * 0.04 * (1.0 - sp)
	var target_bank := sin(tt * 2.7) * (0.06 + 0.22 * sp)
	_bank = lerpf(_bank, target_bank, clampf(dt * 8.0, 0.0, 1.0))
	var yaw := sin(tt * 1.7) * 0.08 * (1.0 - sp)
	_pose("body", Vector3(pitch, yaw, _bank), Vector3(0, bob, 0))
	# anneau : rotation continue, s'emballe en vitesse ; léger contre-balancement
	_spin = fmod(_spin + dt * (5.0 + 13.0 * sp), TAU)
	var n := p("ring")
	if n != null:
		var r: Transform3D = rest["ring"]
		var tilt := Basis.from_euler(Vector3(-pitch * 0.35 + sin(tt * 4.0) * 0.03, 0, -_bank * 0.4))
		n.transform = Transform3D(r.basis * tilt * Basis(Vector3.UP, _spin), r.origin + Vector3(0, sin(tt * 3.1 - 0.9) * 0.008, 0))
	# œil : pulsation (plus rapide quand elle fonce ou tire)
	var beat := 4.0 + 6.0 * maxf(sp, shooting)
	_scale_part("eye_glow", 1.0 + 0.07 * sin(t * beat) + 0.05 * recoil)
	_scale_part("jet_glow", 0.85 + 0.35 * sp + 0.12 * sin(t * 23.0 + ph))
	# antennes : traînent vers l'arrière en vitesse, rebondissent avec le flottement
	var wob := sin(tt * 6.2) * 0.12
	_pose("antenna_l", Vector3(-0.45 * sp + wob - bob * 3.0, 0, -0.1 * sin(tt * 5.0)))
	_pose("antenna_r", Vector3(-0.45 * sp - wob * 0.8 - bob * 3.0, 0, 0.1 * sin(tt * 5.0 + 1.0)))
	# ailerons : petits battements, se couchent vers l'arrière en vitesse
	var flap := sin(tt * (7.0 + 9.0 * sp)) * (0.18 + 0.12 * sp)
	_pose("fin_l", Vector3(0, -0.5 * sp, flap))
	_pose("fin_r", Vector3(0, 0.5 * sp, -flap))

func animate_death(dt_total: float) -> void:
	var k := clampf(dt_total / 0.25, 0.0, 1.0)
	# vrille autour de son centre (rapide puis freinée), bascule sur le flanc, chute jusqu'à poser
	# la coque et le bord de l'anneau au sol (centre du corps de 0,5 à ~0,23)
	_pose("body", Vector3(0.35 * k, 9.0 * k * (2.0 - k), 0.6 * k))
	model.position.y = lerpf(0.0, -0.27, k * k)
	_scale_part("eye_glow", lerpf(1.0, 0.35, k))
	_scale_part("jet_glow", lerpf(1.0, 0.02, minf(k * 2.0, 1.0)))
	_pose("antenna_l", Vector3(0.6 * k, 0, 0.5 * k))
	_pose("antenna_r", Vector3(0.6 * k, 0, -0.5 * k))
	_pose("fin_l", Vector3(0, 0, -0.5 * k))
	_pose("fin_r", Vector3(0, 0, 0.5 * k))
