extends Node3D
## Personnage sculpté (tools/sculpt.py) animé en code : pièces séparées (torse, tête, bras, jambes, arme)
## articulées à leurs pivots. Marche, course, visée à deux mains, recul, respiration, coup reçu, chute.
## Jo (animation par défaut) : jambes qui suivent le déplacement et buste qui suit la visée, inertie au départ
## et à l'arrêt, penché dans les virages, victoire, regard et gestes au repos. Les mobs ont leur animate().
## Couleurs par sommet ; les pièces « *_glow » sont lumineuses.

const Models = preload("res://scripts/models.gd")

var model: Node3D
var parts := {}  # nom -> Node3D
var rest := {}  # nom -> Transform3D
var meshes: Array = []
var speed := 0.0
var shooting := 0.0
var dead := false
var phase := 0.0
var t := 0.0
var recoil := 0.0
var _flash_t := 0.0
var _flash_mat: StandardMaterial3D
var _die_t := 0.0
var walk_amp := 1.0  # amplitude de la foulée (les lourds marchent plus raide)
var glow_color := Color(1, 1, 1)
## Pour les mobs : état de l'IA (« move », « aim », « tell », « charge », « ring ») et temps passé dedans.
var state := "move"
var state_t := 0.0
var elite := false

static var _body_mats := {}
static var _glow_mats := {}

static func body_mat(tint: Color) -> StandardMaterial3D:
	var key := tint.to_html()
	if _body_mats.has(key):
		return _body_mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = tint
	m.roughness = 0.62
	m.metallic_specular = 0.35
	m.rim_enabled = true
	m.rim = 0.45
	m.rim_tint = 0.35
	_body_mats[key] = m
	return m

static func glow_mat(energy: float) -> StandardMaterial3D:
	var key := "%.2f" % energy
	if _glow_mats.has(key):
		return _glow_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(energy, energy, energy)
	_glow_mats[key] = m
	return m

func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	model = Models.scene(path).instantiate()
	add_child(model)
	for n in model.find_children("*", "Node3D", true, false):
		var nd: Node3D = n
		parts[String(nd.name)] = nd
		rest[String(nd.name)] = nd.transform
	for mi in Models.meshes(model):
		var m: MeshInstance3D = mi
		var nm := String(m.name) + String(m.get_parent().name)
		m.material_override = glow_mat(glow_energy) if "_glow" in nm else body_mat(tint)
	meshes = Models.meshes(model)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1, 1, 1, 0)

## Lumière teintée (équipement : couleur de rareté) — les pièces lumineuses de l'équipement sont blanches.
static func tint_glow_mat(col: Color, energy: float) -> StandardMaterial3D:
	var key := col.to_html() + "%.2f" % energy
	if _glow_mats.has(key):
		return _glow_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(col.r * energy, col.g * energy, col.b * energy)
	_glow_mats[key] = m
	return m

# ---------------------------------------------------------------- équipement (Jo)
const RARITY_GLOW := [Color("#9FB3C8"), Color("#3CF2D8"), Color("#C77DFF"), Color("#FFB347")]
## Bout du canon dans le repère de la part « gun », selon l'arme portée.
const MUZZLE := {"": Vector3(0, -0.225, 0.058), "blaster_garde": Vector3(0, -0.26, 0.06), "fusil_impulsion": Vector3(0, -0.3, 0.056)}
var _gear: Array = []
var _gun_id := ""
var _gun_meshes := {}  # MeshInstance3D -> Mesh d'origine (blaster de base)
## Parts de Jo masquées par un objet (le casque remplace les lunettes relevées sur le crâne).
const HIDES := {"casque_garde": ["goggles"]}

## Équipe les objets {id, rarity} : chaque objet est un GLB sculpté (tools/chars/gear.py) dont les parts
## « cible__id » se rangent dans la part cible de Jo. Une arme remplace le blaster de base.
func apply_items(items: Array) -> void:
	for g in _gear:
		if is_instance_valid(g):
			(g as Node).get_parent().remove_child(g)
			(g as Node).queue_free()
	_gear.clear()
	var gun_id := ""
	var hidden := {}
	for it in items:
		var id := String(it["id"])
		var path := "res://assets/chars3d/gear_%s.glb" % id
		if not ResourceLoader.exists(path):
			continue
		var glow: Color = RARITY_GLOW[clampi(int(it["rarity"]), 0, 3)]
		var inst: Node3D = Models.scene(path).instantiate()
		for n in inst.find_children("*__*", "Node3D", true, false):
			var nd: Node3D = n
			var target := p(String(nd.name).get_slice("__", 0))
			if target == null:
				continue
			nd.get_parent().remove_child(nd)
			nd.owner = null
			target.add_child(nd)
			nd.transform = Transform3D.IDENTITY
			_gear.append(nd)
			for mi in Models.meshes(nd):
				(mi as MeshInstance3D).material_override = tint_glow_mat(glow, 1.5) if "_glow" in String(mi.name) + String(mi.get_parent().name) else (_hero_mat if _hero_mat != null else body_mat(Color(1, 1, 1)))
		inst.queue_free()
		for nm in HIDES.get(id, []):
			hidden[nm] = true
		if id in MUZZLE:
			gun_id = id
	# arme de base masquée quand une arme est équipée
	if _gun_meshes.is_empty():
		for nm in ["gun", "gun_glow"]:
			var gn := p(nm)
			if gn is MeshInstance3D:
				_gun_meshes[gn] = (gn as MeshInstance3D).mesh
	for mi in _gun_meshes:
		(mi as MeshInstance3D).mesh = _gun_meshes[mi] if gun_id == "" else null
	_gun_id = gun_id
	for names in HIDES.values():
		for nm in names:
			if p(nm) != null:
				p(nm).visible = not hidden.has(nm)
	meshes = Models.meshes(model)
	apply_skin()

func p(name: String) -> Node3D:
	return parts.get(name)

func set_motion(spd: float, shoot_amount: float) -> void:
	speed = lerpf(speed, spd, 0.2)
	shooting = lerpf(shooting, shoot_amount, 0.35)

func fire() -> void:
	recoil = 1.0

func flash(dur: float = 0.09) -> void:
	_flash_t = maxf(_flash_t, dur)
	for mi in meshes:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = _flash_mat

func die() -> void:
	dead = true
	_die_t = 0.0

func revive() -> void:
	dead = false
	_die_t = 0.0
	model.rotation = Vector3.ZERO
	model.position = Vector3.ZERO
	_jo_reset()
	for nm in rest:
		(parts[nm] as Node3D).transform = rest[nm]

func muzzle_position() -> Vector3:
	var g := p("gun")
	if g == null:
		return global_position + Vector3(0, 0.5, 0)
	return g.global_transform * (MUZZLE[_gun_id] as Vector3)

func _pose(name: String, rot: Vector3, off: Vector3 = Vector3.ZERO) -> void:
	var n := p(name)
	if n == null:
		return
	var r: Transform3D = rest[name]
	n.transform = Transform3D(r.basis * Basis.from_euler(rot), r.origin + off)

func _process(dt: float) -> void:
	t += dt
	if _flash_t > 0.0:
		_flash_t -= dt
		_flash_mat.albedo_color = Color(flash_color.r, flash_color.g, flash_color.b, clampf(_flash_t * 10.0, 0.0, 0.85))
		if _flash_t <= 0.0:
			_overlay(null)
			_veiled = false
	if _flash_t <= 0.0 and (invuln > 0.0 or _veiled):
		_veil(dt)
	if dead:
		_die_t += dt
		animate_death(_die_t)
		return
	recoil = maxf(0.0, recoil - dt * 9.0)
	animate(dt)

func _overlay(m: Material) -> void:
	for mi in meshes:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = m

## Invulnérable après un coup : voile clair pulsé, plutôt qu'un clignotement qui ferait disparaître Jo.
var _veil_mat: StandardMaterial3D = null
var _veiled := false
func _veil(dt: float) -> void:
	invuln = maxf(0.0, invuln - dt)
	if invuln <= 0.0 or dead:
		_overlay(null)
		_veiled = false
		return
	if _veil_mat == null:
		_veil_mat = _flash_mat.duplicate()
		_veil_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if not _veiled:
		_overlay(_veil_mat)
		_veiled = true
	_veil_mat.albedo_color = Color(0.9, 0.85, 0.8, 0.14 if int(invuln * 12.0) % 2 == 0 else 0.03)


# ---------------------------------------------------------------- Jo : apparence (scripts/loot.gd)
## Apparence équipée : palette {suit, accent, light, rainbow} remappée par shaders/skin_remap.* ;
## vide = couleurs et matériaux d'origine. Les modèles de Jo du joueur (Relais, partie) suivent, inscrits par
## follow_skin() ; la Jo d'un partenaire en duo garde les siennes.
static var hero_skin: Dictionary = {}
static var _skin_rigs: Array = []  # WeakRef des modèles de Jo
static var _skin_mats := {}
var _skin_orig := {}  # MeshInstance3D -> matériau d'origine

static func set_hero_skin(pal: Dictionary) -> void:
	hero_skin = pal
	for w in _skin_rigs.duplicate():
		var r = (w as WeakRef).get_ref()
		if r == null:
			_skin_rigs.erase(w)
		else:
			r.apply_skin()

func follow_skin() -> void:
	if not _skin_rigs.any(func(w): return (w as WeakRef).get_ref() == self):
		_skin_rigs.append(weakref(self))
	apply_skin()

func apply_skin() -> void:
	if model == null or not _skin_rigs.any(func(w): return (w as WeakRef).get_ref() == self):
		return
	var keep := {}
	for mi in Models.meshes(model):
		var m: MeshInstance3D = mi
		if not (m.material_override is ShaderMaterial and m.material_override.has_meta("skin")):
			_skin_orig[m] = m.material_override
		keep[m] = _skin_orig.get(m)
		var orig = keep[m]
		if hero_skin.is_empty() or not (orig is StandardMaterial3D):
			m.material_override = orig
			continue
		var glow := (orig as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = _skin_mat(orig, glow, String(m.name) == "head")
	_skin_orig = keep

static func _skin_mat(orig: StandardMaterial3D, glow: bool, head: bool) -> ShaderMaterial:
	var key := "%s|%d|%d|%d" % [String(hero_skin.get("id", "")), int(glow), int(head), orig.get_instance_id()]
	if _skin_mats.has(key):
		return _skin_mats[key]
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/skin_remap_glow.gdshader") if glow else preload("res://shaders/skin_remap.gdshader")
	sm.set_meta("skin", true)
	for k in [["suit", "suit"], ["accent", "accent"], ["light", "lit_col"]]:
		var c: Color = hero_skin[k[0]]
		sm.set_shader_parameter(k[1], Vector3(c.r, c.g, c.b))
	sm.set_shader_parameter("rainbow", 1.0 if bool(hero_skin.get("rainbow", false)) else 0.0)
	sm.set_shader_parameter("suit_on", 0.0 if (glow or head) else 1.0)
	if glow:
		var a := orig.albedo_color  # en Compatibility, la teinte passe telle quelle (sortie sRGB)
		sm.set_shader_parameter("tint", Vector3(a.r, a.g, a.b))
	sm.next_pass = orig.next_pass  # liseré de Jo en jeu
	_skin_mats[key] = sm
	return sm

# ---------------------------------------------------------------- Jo : locomotion, coup reçu, victoire, repos
## Déplacement voulu dans le monde (longueur 0..1). Les jambes le suivent, le buste suit la visée (orientation
## du rig) : Jo peut tirer en reculant ou en pas chassés. Sans appel, les jambes suivent l'orientation.
var move_vel := Vector3.ZERO
var flash_color := Color(1.6, 1.6, 1.6)
var invuln := 0.0  # > 0 : invulnérable après un coup (voile pulsé, la silhouette reste visible)
var _jo_vel := Vector3.ZERO  # déplacement lissé (inertie)
var _jo_acc := Vector3.ZERO  # accélération lissée : penché au départ, à l'arrêt, dans les virages
var _jo_hips := 0.0  # orientation des hanches par rapport à la visée
var _jo_back := false  # recule face à la visée
var _jo_step := Vector2(0, 1)  # sens des foulées dans le repère des hanches
var _jo_hit_t := 0.0
var _jo_hit_side := 0.0
var _jo_cheer_t := -1.0
var _jo_idle_t := 0.0
var _jo_look := Vector2.ZERO
var _jo_look_to := Vector2.ZERO
var _jo_look_cd := 1.2
var _jo_gest := -1
var _jo_gest_t := 0.0
var _jo_gest_cd := 2.0
var _jo_gest_n := 0
const GEST_T := 2.0

func set_move(v: Vector3) -> void:
	move_vel = v

## Coup reçu : le buste part en arrière, la tête claque, le corps s'écrase un instant.
func hit(side: float = 0.0) -> void:
	_jo_hit_t = 1.0
	_jo_hit_side = side if side != 0.0 else (1.0 if randf() < 0.5 else -1.0)
	_jo_gest = -1

## Petite pose de victoire (salle vidée) : arme levée, poing serré, petit saut.
func cheer() -> void:
	_jo_cheer_t = 0.0
	_jo_gest = -1

## Geste de repos : 0 regarde son blaster, 1 salue, 2 écoute la radio (main à l'oreillette), 3 s'étire.
func gesture(i: int) -> void:
	_jo_gest = i
	_jo_gest_t = 0.0

## Réglages propres à l'héroïne en jeu : matériau à elle avec un liseré (coque inversée), silhouette « rayons X »
## quand un ennemi ou une caisse passe devant elle (tampon de stencil, sur les masses seulement : tête, torse,
## jambes), voile de coup teinté.
const XRAY_PARTS := ["torso", "head", "leg_r", "leg_l"]
var _hero_mat: StandardMaterial3D = null
func make_hero(outline: Color, width: float, hurt: Color) -> void:
	_hero_mat = (body_mat(Color(1, 1, 1)).duplicate() as StandardMaterial3D)
	var xray_mat := _hero_mat
	if width > 0.0:
		var ol := StandardMaterial3D.new()
		ol.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ol.cull_mode = BaseMaterial3D.CULL_FRONT
		ol.grow = true
		ol.grow_amount = width
		ol.albedo_color = outline
		ol.disable_receive_shadows = true
		_hero_mat.next_pass = ol
		# silhouette « rayons X » (STENCIL_MODE_XRAY) retirée : sur le sol du hangar elle teintait Jo en
		# permanence, même à découvert, et lui ôtait ses couleurs
	for mi in Models.meshes(model):
		var m: MeshInstance3D = mi
		if not ("_glow" in String(m.name) + String(m.get_parent().name)):
			m.material_override = xray_mat if String(m.name) in XRAY_PARTS else _hero_mat
	flash_color = hurt
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	apply_skin()

func _jo_reset() -> void:
	_jo_vel = Vector3.ZERO
	_jo_acc = Vector3.ZERO
	_jo_hips = 0.0
	_jo_hit_t = 0.0
	_jo_cheer_t = -1.0
	_jo_gest = -1
	model.scale = Vector3.ONE

## Chute de Jo : bascule en arrière, bras levés.
func animate_death(dt_total: float) -> void:
	var k := clampf(dt_total / 0.45, 0.0, 1.0)
	model.rotation = Vector3(lerpf(0.0, -1.45, k * k), 0, 0)
	model.position = Vector3(0, lerpf(0.0, 0.08, k), 0)
	model.scale = Vector3.ONE
	_pose("arm_r", Vector3(-2.6 * k, 0, 0.4 * k))
	_pose("arm_l", Vector3(-2.6 * k, 0, -0.4 * k))

## Animation bipède par défaut (Jo ; les mobs ont chacun la leur dans scripts/mobs/).
func animate(dt: float) -> void:
	# --- inertie : le corps rattrape le déplacement voulu, l'accélération le fait pencher
	var prev := _jo_vel
	_jo_vel = _jo_vel.lerp(move_vel, clampf(dt * 8.0, 0.0, 1.0))
	_jo_acc = _jo_acc.lerp((_jo_vel - prev) / maxf(dt, 0.001), clampf(dt * 12.0, 0.0, 1.0))
	var inv := global_transform.basis.orthonormalized().inverse()
	var lv := inv * _jo_vel
	var la := inv * _jo_acc
	var mv := Vector2(lv.x, lv.z)
	var driven := mv.length() > 0.12
	# --- hanches : suivent la marche jusqu'à 60° de la visée ; au-delà de ~110°, Jo recule face à la visée
	var hips_to := 0.0
	var step_to := Vector2(0, 1)
	if driven:
		var rel := atan2(mv.x, mv.y)
		if absf(rel) > 1.95:
			_jo_back = true
		elif absf(rel) < 1.55:
			_jo_back = false
		hips_to = clampf(wrapf(rel - PI, -PI, PI) if _jo_back else rel, -1.05, 1.05)
		step_to = Vector2(sin(rel - _jo_hips), cos(rel - _jo_hips))
	_jo_hips = lerp_angle(_jo_hips, hips_to, clampf(dt * 9.0, 0.0, 1.0))
	_jo_step = _jo_step.lerp(step_to, clampf(dt * 10.0, 0.0, 1.0))
	var mdir := mv.normalized() if driven else Vector2(0, 1)
	# --- foulée
	phase += dt * (6.0 + 6.0 * speed) * clampf(speed * 2.0, 0.0, 1.0)
	var s := sin(phase)
	var c := cos(phase)
	var amp := clampf(speed * 1.4, 0.0, 1.0) * walk_amp
	var run := speed * speed
	var back := maxf(0.0, -_jo_step.y)
	var stride := 0.75 * amp * (1.0 - 0.3 * back)
	var breathe := sin(t * 2.4) * 0.012 * (1.0 - amp)
	# --- états : coup reçu, victoire, repos (regard, gestes)
	_jo_hit_t = maxf(0.0, _jo_hit_t - dt / 0.42)
	var hk := smoothstep(0.0, 0.6, _jo_hit_t)
	var ck := 0.0
	if _jo_cheer_t >= 0.0:
		_jo_cheer_t += dt
		ck = smoothstep(0.0, 0.16, _jo_cheer_t) * (1.0 - smoothstep(1.55, 1.95, _jo_cheer_t))
		if _jo_cheer_t > 1.95:
			_jo_cheer_t = -1.0
	var still := speed < 0.08 and shooting < 0.08 and _jo_cheer_t < 0.0 and _jo_hit_t <= 0.0
	_jo_idle_t = _jo_idle_t + dt if still else 0.0
	var idle_k := smoothstep(0.3, 1.2, _jo_idle_t)
	_jo_look_cd -= dt
	if _jo_look_cd <= 0.0:
		_jo_look_cd = randf_range(1.5, 3.4)
		_jo_look_to = Vector2(randf_range(-0.6, 0.6), randf_range(-0.14, 0.1)) if randf() < 0.75 else Vector2.ZERO
	_jo_look = _jo_look.lerp(_jo_look_to * idle_k, clampf(dt * 3.5, 0.0, 1.0))
	if _jo_gest >= 0:
		_jo_gest_t += dt
		if _jo_gest_t >= GEST_T or speed > 0.15 or shooting > 0.2:
			_jo_gest = -1
			_jo_gest_cd = randf_range(2.5, 5.0)
	elif _jo_idle_t > 1.4:
		_jo_gest_cd -= dt
		if _jo_gest_cd <= 0.0:
			gesture(_jo_gest_n % 4)
			_jo_gest_n += 1
	var ge := 0.0
	if _jo_gest >= 0:
		ge = smoothstep(0.0, 0.35, _jo_gest_t) * (1.0 - smoothstep(GEST_T - 0.45, GEST_T, _jo_gest_t))
	var gt := _jo_gest_t
	# --- corps entier : penché par l'accélération (autour des pieds), petit saut de victoire, recul du coup
	var tilt := Vector3(clampf(la.z * 0.035, -0.17, 0.17), 0, clampf(-la.x * 0.035, -0.17, 0.17))
	model.rotation = tilt * (1.0 - hk)
	# victoire : saut avec une pirouette (lisible d'en haut), puis la pose
	if _jo_cheer_t >= 0.0:
		var u := clampf((_jo_cheer_t - 0.04) / 0.5, 0.0, 1.0)
		model.rotation.y = TAU * smoothstep(0.0, 1.0, u) * (1.0 - amp)
	var hop := 0.1 * sin(clampf((_jo_cheer_t - 0.04) / 0.5, 0.0, 1.0) * PI) * (1.0 - amp) if _jo_cheer_t >= 0.0 else 0.0
	model.position = Vector3(0, hop, -0.07 * hk)
	model.scale = Vector3(1.0 + 0.09 * hk, 1.0 - 0.11 * hk, 1.0 + 0.09 * hk)
	# --- torse : penché dans le sens de la course, torsion de la marche, respiration et appui au repos
	var twist := _jo_hips * 0.3 + s * 0.12 * amp * (1.0 - shooting * 0.7)
	var sway := sin(t * 0.9) * idle_k
	var t_rot := Vector3(0.17 * run * mdir.y - 0.38 * hk - 0.1 * ck, twist + 0.22 * hk * _jo_hit_side, -0.1 * run * mdir.x + c * 0.04 * amp + 0.03 * sway + 0.18 * hk * _jo_hit_side)
	var t_off := Vector3(0.006 * sway, absf(c) * 0.035 * amp + breathe - 0.025 * hk, -0.02 * hk)
	if _jo_gest == 3:
		t_rot.x -= 0.14 * ge
	_pose("torso", t_rot, t_off)
	# --- jambes : orientées comme les hanches (le buste peut viser ailleurs), restent d'aplomb
	var tb: Basis = (rest["torso"] as Transform3D).basis * Basis.from_euler(t_rot)
	var tinv := tb.inverse()
	var hb := Basis(Vector3.UP, _jo_hips)
	var lx := s * stride * _jo_step.y
	var lz := -s * stride * _jo_step.x
	for side in [["leg_r", 1.0], ["leg_l", -1.0]]:
		var n := p(side[0])
		if n == null:
			continue
		var r: Transform3D = rest[side[0]]
		var sg: float = side[1]
		var spread := 0.05 * hk * sg
		n.transform = Transform3D(tinv * hb * r.basis * Basis.from_euler(Vector3(lx * sg, 0, lz * sg - spread)), tinv * (hb * r.origin))
	# --- tête : regarde la visée malgré la torsion, hochement, regard qui flâne au repos
	var h_rot := Vector3(-c * 0.05 * amp - 0.1 * run + _jo_look.y - 0.32 * hk - 0.22 * ck, -s * 0.1 * amp - twist + _jo_look.x, -0.15 * hk * _jo_hit_side + 0.12 * ck * sin(_jo_cheer_t * 6.0))
	# --- bras : balancier en course, visée à deux mains quand on tire
	var aim_r := Vector3(-PI * 0.5 + recoil * 0.35, -twist, 0.05)
	var aim_l := Vector3(-PI * 0.44, -0.55 - twist, -0.35)
	var sw := s * 0.7 * amp * _jo_step.y
	var swing_r := Vector3(-sw + 0.05 * sway, 0, 0.08 + 0.12 * run)
	var swing_l := Vector3(sw - 0.05 * sway, 0, -0.08 - 0.12 * run)
	var arm_r := swing_r.lerp(aim_r, shooting)
	var arm_l := swing_l.lerp(aim_l, shooting)
	var gun_rot := Vector3.ZERO
	match _jo_gest:
		0:  # regarde son blaster, le fait pivoter
			arm_r = arm_r.lerp(Vector3(-1.35, 0.75, 0.25), ge)
			gun_rot = Vector3(0, 0.9 * sin(gt * 4.0) * ge, 0)
			h_rot += Vector3(0.28, -0.55, 0.08) * ge
		1:  # salue de la main gauche
			arm_l = arm_l.lerp(Vector3(-2.85, 0.2, 0.62 + 0.32 * sin(gt * 11.0)), ge)
			h_rot += Vector3(-0.08, 0.15, -0.12) * ge
		2:  # main à l'oreillette : écoute la radio du Relais
			arm_r = arm_r.lerp(Vector3(-2.95, 0.15, -0.32), ge)
			h_rot += Vector3(0.05, -0.2, 0.2 + 0.04 * sin(gt * 7.0)) * ge
		3:  # s'étire, bras au ciel
			var k := sin(clampf(gt / GEST_T, 0.0, 1.0) * PI)
			arm_r = arm_r.lerp(Vector3(-2.9, 0, -0.42 - 0.12 * k), ge)
			arm_l = arm_l.lerp(Vector3(-2.9, 0, 0.42 + 0.12 * k), ge)
			h_rot += Vector3(-0.22, 0, 0.1 * sin(gt * 2.0)) * ge
	if ck > 0.0:
		var pump := maxf(0.0, sin((_jo_cheer_t - 0.5) * 12.0)) * smoothstep(0.5, 0.6, _jo_cheer_t) * (1.0 - smoothstep(1.2, 1.45, _jo_cheer_t))
		arm_r = arm_r.lerp(Vector3(-2.9, 0.1, -0.6), ck)
		arm_l = arm_l.lerp(Vector3(-2.5 - 0.35 * pump, 0.2, 0.5 + 0.2 * pump), ck)
	if hk > 0.0:
		arm_r = arm_r + Vector3(0.55, 0, -0.35) * hk
		arm_l = arm_l.lerp(Vector3(-0.9, 0, 0.9), hk)
	_pose("head", h_rot)
	_pose("arm_r", arm_r)
	_pose("arm_l", arm_l)
	_pose("gun", gun_rot)
