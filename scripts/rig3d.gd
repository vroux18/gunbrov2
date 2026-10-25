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
static var _char_shader: Shader = null
static var _outline_mat: ShaderMaterial = null
## Contour des personnages (coque inversée) : une passe de plus par pièce ; « --no-outline » le coupe.
static var outline_enabled := not ("--no-outline" in OS.get_cmdline_user_args())

## Matériau des pièces sculptées : shaders/character.gdshader (rampe douce, liseré, reflet net) et
## son contour en deuxième passe. Paramètres : « tint » (couleur multipliée), « heat » (lueur ajoutée).
static func body_mat(tint: Color) -> ShaderMaterial:
	var key := tint.to_html()
	if _body_mats.has(key):
		return _body_mats[key]
	if _char_shader == null:
		_char_shader = load("res://shaders/character.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _char_shader
	m.set_shader_parameter("tint", tint)
	if outline_enabled:
		if _outline_mat == null:
			_outline_mat = ShaderMaterial.new()
			_outline_mat.shader = load("res://shaders/character_outline.gdshader")
		m.next_pass = _outline_mat
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

var _glow_energy := 3.0

func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	_glow_energy = glow_energy
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
const MUZZLE := {"": Vector3(0, -0.225, 0.058), "blaster_garde": Vector3(0, -0.26, 0.06), "fusil_impulsion": Vector3(0, -0.3, 0.056),
	"riveteuse": Vector3(0, -0.265, 0.061), "pistolet_neon": Vector3(0, -0.268, 0.058)}
var _gear: Array = []
var _gun_id := ""
var _gun_meshes := {}  # MeshInstance3D -> Mesh d'origine (blaster de base)
## Parts de Jo masquées par un objet (le casque remplace les lunettes relevées sur le crâne).
const HIDES := {"casque_garde": ["goggles"], "casque_docker": ["goggles"]}

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
				if _hero_mat != null:
					(mi as MeshInstance3D).layers |= HERO_LAYER
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
	# masqué (Jo du Relais pendant la partie, Jo de la partie au Relais) : rien à animer
	if not is_visible_in_tree():
		return
	t += dt
	for n in _outfit_spin:  # halo de la tenue : tourne lentement et flotte
		(n as Node3D).rotation.y = t * 0.8
		(n as Node3D).position.y = 0.012 * sin(t * 2.2)
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
## Apparence équipée : palette {suit, accent, light, rainbow, hair?} remappée par shaders/skin_remap.*, et tenue
## {outfit, hides} (pièces sculptées, voir _apply_outfit) ; vide = couleurs et matériaux d'origine, sans tenue.
## Les modèles de Jo du joueur (Relais, partie) suivent, inscrits par follow_skin() ; la Jo d'un partenaire en
## duo porte la sienne (set_own_skin).
static var hero_skin: Dictionary = {}
static var _skin_rigs: Array = []  # WeakRef des modèles de Jo
static var _skin_mats := {}
var _skin_orig := {}  # MeshInstance3D -> matériau d'origine
## Apparence propre à ce modèle (Jo du partenaire en duo) : remplace l'apparence équipée, sans inscription.
var own_skin = null

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

func set_own_skin(pal: Dictionary) -> void:
	own_skin = pal
	apply_skin()

## Vignette d'apparence (écran APPARENCES, scripts/ui/boxes_thumbs.gd) : ce modèle seul prend l'apparence `pal`
## (vide : couleurs d'origine), tenue comprise, sans suivre l'apparence équipée ni toucher aux autres Jo.
func show_palette(pal: Dictionary) -> void:
	set_own_skin(pal)

func apply_skin() -> void:
	if model == null:
		return
	if own_skin == null and not _skin_rigs.any(func(w): return (w as WeakRef).get_ref() == self):
		return
	var pal: Dictionary = own_skin if own_skin != null else hero_skin
	_apply_outfit(pal)
	var keep := {}
	for mi in Models.meshes(model):
		var m: MeshInstance3D = mi
		if not (m.material_override is ShaderMaterial and m.material_override.has_meta("skin")):
			_skin_orig[m] = m.material_override
		keep[m] = _skin_orig.get(m)
		var orig = keep[m]
		var nm := String(m.name)
		var hair := nm == "hair" or "_hair" in nm
		if not pal.is_empty() and orig is ShaderMaterial and (orig as ShaderMaterial).shader == _char_shader:
			m.material_override = _skin_body_mat(pal, orig, nm == "head", hair)
			continue
		if pal.is_empty() or not (orig is StandardMaterial3D):
			m.material_override = orig
			continue
		var glow := (orig as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = _skin_mat(pal, orig, glow, nm == "head")
	_skin_orig = keep

static func _set_skin_params(sm: ShaderMaterial, pal: Dictionary, suit_on: bool, hair: bool) -> void:
	sm.set_meta("skin", true)
	for k in [["suit", "suit"], ["accent", "accent"], ["light", "lit_col"]]:
		var c: Color = pal[k[0]]
		sm.set_shader_parameter(k[1], Vector3(c.r, c.g, c.b))
	sm.set_shader_parameter("rainbow", 1.0 if bool(pal.get("rainbow", false)) else 0.0)
	sm.set_shader_parameter("suit_on", 1.0 if suit_on else 0.0)
	var hc = pal.get("hair")
	sm.set_shader_parameter("hair_on", 1.0 if hair and hc is Color else 0.0)
	if hair and hc is Color:
		sm.set_shader_parameter("hair_col", Vector3(hc.r, hc.g, hc.b))

## Corps au rendu premium (shaders/character.gdshader) : même matériau, remappage des couleurs activé. Un
## matériau par apparence et par matériau d'origine (partagé entre les pièces), plus un pour la tête (reflets des
## yeux gardés blancs) et un pour les cheveux.
static func _skin_body_mat(pal: Dictionary, orig: ShaderMaterial, head: bool, hair: bool) -> ShaderMaterial:
	var key := "body|%s|%d|%d|%d" % [String(pal.get("id", "")), int(head), int(hair), orig.get_instance_id()]
	if _skin_mats.has(key):
		return _skin_mats[key]
	var sm := orig.duplicate() as ShaderMaterial
	sm.set_shader_parameter("skin_on", 1.0)
	_set_skin_params(sm, pal, not head, hair)
	_skin_mats[key] = sm
	return sm

static func _skin_mat(pal: Dictionary, orig: StandardMaterial3D, glow: bool, head: bool) -> ShaderMaterial:
	var key := "%s|%d|%d|%d" % [String(pal.get("id", "")), int(glow), int(head), orig.get_instance_id()]
	if _skin_mats.has(key):
		return _skin_mats[key]
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/skin_remap_glow.gdshader") if glow else preload("res://shaders/skin_remap.gdshader")
	_set_skin_params(sm, pal, not (glow or head), false)
	if glow:
		var a := orig.albedo_color  # en Compatibility, la teinte passe telle quelle (sortie sRGB)
		sm.set_shader_parameter("tint", Vector3(a.r, a.g, a.b))
	sm.next_pass = orig.next_pass  # liseré de Jo en jeu
	_skin_mats[key] = sm
	return sm

# ---------------------------------------------------------------- Jo : tenue de l'apparence
## Pièces sculptées de la tenue (tools/chars/tenues.py -> assets/chars3d/tenue_<id>.glb) : parts
## « cible__zone[_suffixe] » rangées dans la part cible de Jo, comme l'équipement, avec le matériau de Jo
## (_hero_mat, calque HERO_LAYER en partie) remappé par l'apparence. « _glow » : lumineux ; « _hair » : cheveux ;
## « _spin » : tourne (halo).
## Règle avec l'équipement : l'objet porté l'emporte. Il masque, sur la part où il se pose, les pièces de tenue de
## sa zone (_gear_zones, d'après la forme de l'objet, donc valable pour les objets à venir) :
##   tête    couvre-chef (casque, serre-tête : masque les lunettes ou monte au-dessus du crâne) -> coiffe et visière ;
##           autre objet de tête (visière) -> visière seulement
##   bras    objet posé sur l'épaule (module, antenne, pince) -> épaulette de ce bras ; une manche ne masque rien
##   torse   devant ou autour du cou (plastron, veste, gilet, écharpe) -> col ; dans le dos (gadget) -> ce qui couvre
##           le sac (cape) ; gadget large (petites ailes) -> aussi les ailes de la tenue
##   jambes  -> pièces des jambes
## Les autres zones (dessus du sac, halo) restent toujours.
## La palette « hides » liste les parts de Jo que la coiffe recouvre (cheveux, lunettes) : masquées seulement
## quand la coiffe est portée (sous un casque, les cheveux et le casque reprennent leur place).
## Couleurs : les pièces de tenue suivent la palette de l'apparence (sculptées aux couleurs de Jo). L'équipement
## aussi, par le même remappage (apply_skin) : ses parties blanches, orange et turquoise prennent les couleurs de
## l'apparence pour aller avec la tenue ; ses métaux, ses sombres et sa lumière de rareté ne bougent pas.
var _outfit_id := ""
var _outfit: Array = []
var _outfit_spin: Array = []
const BASE_HIDEABLE := ["hair", "goggles"]

func _apply_outfit(pal: Dictionary) -> void:
	var id := String(pal.get("outfit", ""))
	if id != _outfit_id:
		for n in _outfit:
			if is_instance_valid(n):
				(n as Node).get_parent().remove_child(n)
				(n as Node).queue_free()
		_outfit.clear()
		_outfit_spin.clear()
		_outfit_id = id
		var path := "res://assets/chars3d/tenue_%s.glb" % id
		if id != "" and ResourceLoader.exists(path):
			var inst: Node3D = Models.scene(path).instantiate()
			for n in inst.find_children("*__*", "Node3D", true, false):
				var nd: Node3D = n
				var target := p(String(nd.name).get_slice("__", 0))
				if target == null:
					continue
				var orig := String(nd.name)
				nd.get_parent().remove_child(nd)
				nd.owner = null
				# zone notée à part, nom préfixé : un objet porté peut avoir le même nom (« torso__ailes »)
				nd.set_meta("zone", orig.get_slice("__", 0) + "__" + orig.get_slice("__", 1).get_slice("_", 0))
				nd.name = "tenue_" + orig
				target.add_child(nd)
				nd.transform = Transform3D.IDENTITY
				_outfit.append(nd)
				if "_spin" in orig:
					_outfit_spin.append(nd)
				for mi in Models.meshes(nd):
					var m: MeshInstance3D = mi
					if _hero_mat != null:
						m.layers |= HERO_LAYER
					var glow := "_glow" in String(m.name) + String(m.get_parent().name)
					m.material_override = glow_mat(_glow_energy) if glow else (_hero_mat if _hero_mat != null else body_mat(Color(1, 1, 1)))
			inst.queue_free()
	var blocked := _gear_zones()
	var coiffe := false
	for n in _outfit:
		var key := String((n as Node).get_meta("zone", ""))
		(n as Node3D).visible = not blocked.has(key)
		if key == "head__coiffe" and (n as Node3D).visible:
			coiffe = true
	# parts de Jo masquées : par l'équipement (HIDES) ou par la coiffe de la tenue
	var hidden := {}
	if coiffe:
		for nm in pal.get("hides", []):
			hidden[String(nm)] = true
	for g in _gear:
		if is_instance_valid(g):
			for nm in HIDES.get(_gear_name(g).get_slice("__", 1).trim_suffix("_glow"), []):
				hidden[nm] = true
	var names := BASE_HIDEABLE.duplicate()
	for v in HIDES.values():
		names.append_array(v)
	for nm in names:
		if p(nm) != null:
			p(nm).visible = not hidden.has(nm)
	meshes = Models.meshes(model)

## Nom « cible__id » d'une part d'objet porté (sans le « @…@n » qu'ajoute Godot à un nom en double).
static func _gear_name(g: Node) -> String:
	return String(g.name).trim_prefix("@").get_slice("@", 0)

## Zones de tenue occupées par l'équipement porté : « part__zone » -> true (voir la règle plus haut). Les
## boîtes sont dans le repère de la part cible (origine au pivot : cou, épaule, hanches).
func _gear_zones() -> Dictionary:
	var out := {}
	for g in _gear:
		if not is_instance_valid(g) or not (g is MeshInstance3D) or (g as MeshInstance3D).mesh == null:
			continue
		var nm := _gear_name(g)
		var tgt := nm.get_slice("__", 0)
		var gid := nm.get_slice("__", 1).trim_suffix("_glow")
		var box: AABB = (g as MeshInstance3D).get_aabb()
		match tgt:
			"head":
				out["head__visage"] = true
				if "goggles" in HIDES.get(gid, []) or box.end.y > 0.4:  # couvre-chef
					out["head__coiffe"] = true
			"torso":
				if box.get_center().z < -0.2:  # gadget posé sur le sac
					out["torso__dos"] = true
					if box.size.x > 0.4:
						out["torso__ailes"] = true
				else:
					out["torso__torse"] = true
			"arm_l", "arm_r":
				if box.end.y > 0.07:  # sur l'épaule (une manche de veste reste plus bas)
					out[tgt + "__epaule"] = true
			"leg_l", "leg_r":
				out[tgt + "__jambes"] = true
	return out

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

# ---------------------------------------------------------------- Jo : recul du tir
## Ressenti du tir par arme portée (clé : id d'arme de MUZZLE). Le recul est un ressort : coup sec (pic en
## ~0,04 s) puis retour souple avec un léger rebond. Champs : « arm » bras et canon qui se cabrent (rad),
## « push » arme qui recule dans la main (m), « torso » buste qui part en arrière (rad), « w » raideur du
## ressort (rad/s, plus bas = retour plus lent, arme lourde), « fx » style de flamme (fx3d.shot_muzzle),
## « slide » tout le corps glisse en arrière (m), « cam » recul de caméra (× view3d.CAM_KICK), « heavy »
## tremblement directionnel bref de la caméra. Caméra haute : ce qui se lit le mieux est ce qui recule dans le
## plan du sol (arme, buste, corps) ; le bras qui se cabre se voit surtout de profil.
const GUN_FEEL := {
	"": {"arm": 0.2, "push": 0.07, "torso": 0.07, "slide": 0.02, "w": 32.0, "fx": "blaster", "cam": 1.0, "heavy": 0.0},
	"blaster_garde": {"arm": 0.24, "push": 0.08, "torso": 0.09, "slide": 0.025, "w": 29.0, "fx": "garde", "cam": 1.15, "heavy": 0.0},
	"fusil_impulsion": {"arm": 0.14, "push": 0.1, "torso": 0.12, "slide": 0.035, "w": 26.0, "fx": "impulsion", "cam": 1.25, "heavy": 0.04},
	"riveteuse": {"arm": 0.3, "push": 0.11, "torso": 0.17, "slide": 0.05, "w": 21.0, "fx": "rivet", "cam": 1.5, "heavy": 0.07},
	"pistolet_neon": {"arm": 0.18, "push": 0.055, "torso": 0.05, "slide": 0.012, "w": 36.0, "fx": "rayon", "cam": 0.8, "heavy": 0.0},
}
const KICK_GAIN := 1.0   # force globale du recul de Jo (bras, arme, buste)
const KICK_DAMP := 0.5   # amortissement du ressort (0,3 : rebondit ; 0,8 : mou, sans rebond)
const KICK_MAX := 1.35   # le recul cumulé d'une rafale ne dépasse pas ce multiple d'un tir seul
const HEAT_PER_SHOT := 0.12  # chauffe du canon par tir (fumée en rafale continue au-delà de 0,5)
const HEAT_COOL := 0.7       # refroidissement par seconde
var _jo_kick := 0.0  # recul courant (1 = pic d'un tir seul)
var _jo_kick_v := 0.0
var _jo_shot_frame := -1
var jo_heat := 0.0  # chauffe du canon (0 à 1,5)

func gun_feel() -> Dictionary:
	return GUN_FEEL.get(_gun_id, GUN_FEEL[""])

## Tir de Jo : un coup de recul par salve (les tirs d'une même image n'en donnent qu'un). Vrai pour le premier
## tir de la salve (flamme complète, douille), faux pour les suivants (flamme seule).
func shot(strength: float = 1.0) -> bool:
	var f := Engine.get_process_frames()
	if f == _jo_shot_frame:
		return false
	_jo_shot_frame = f
	var w: float = gun_feel()["w"]
	# impulsion qui donne un pic de 1 (ressort amorti), réduite quand le bras est déjà relevé : une rafale
	# reste bornée au lieu de cumuler
	var z := KICK_DAMP
	var s := sqrt(1.0 - z * z)
	var peak := exp(-z / s * atan2(s, z))
	_jo_kick_v += w / peak * strength * clampf(1.0 - 0.6 * _jo_kick, 0.25, 1.0)
	jo_heat = minf(1.5, jo_heat + HEAT_PER_SHOT)
	return true

func _jo_tick_kick(dt: float) -> void:
	jo_heat = maxf(0.0, jo_heat - dt * HEAT_COOL)
	if _jo_kick == 0.0 and _jo_kick_v == 0.0:
		return
	var w: float = gun_feel()["w"]
	# pas fixes (stable même à 30 i/s avec un ressort raide)
	var n := maxi(1, ceili(dt / 0.008))
	var h := dt / n
	for i in range(n):
		_jo_kick_v += (-w * w * _jo_kick - 2.0 * KICK_DAMP * w * _jo_kick_v) * h
		_jo_kick += _jo_kick_v * h
	_jo_kick = clampf(_jo_kick, -0.4, KICK_MAX)
	if absf(_jo_kick) < 0.001 and absf(_jo_kick_v) < 0.01:
		_jo_kick = 0.0
		_jo_kick_v = 0.0

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
## Le matériau de Jo est une copie de body_mat() (shaders/character.gdshader) ; son liseré turquoise
## remplace le contour sombre commun (next_pass) : un seul contour, pas deux.
var _hero_mat: ShaderMaterial = null
## Calque de rendu propre à Jo : sa lumière d'appoint (view3d.gd) n'éclaire qu'elle.
const HERO_LAYER := 1 << 19
func make_hero(outline: Color, width: float, hurt: Color) -> void:
	_hero_mat = body_mat(Color(1, 1, 1)).duplicate() as ShaderMaterial
	# Jo ressort de la mêlée : couleurs plus vives et plus claires que les ennemis, côté ombre moins sombre
	_hero_mat.set_shader_parameter("exposure", 1.0)
	_hero_mat.set_shader_parameter("saturation", 1.12)
	_hero_mat.set_shader_parameter("white_cap", 0.9)
	_hero_mat.set_shader_parameter("shade_amt", 0.5)
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
		m.layers |= HERO_LAYER
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
	_jo_kick = 0.0
	_jo_kick_v = 0.0
	jo_heat = 0.0
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
	# --- recul du tir (ressort), réglages de l'arme portée
	_jo_tick_kick(dt)
	var gf := gun_feel()
	var kk := _jo_kick * KICK_GAIN * shooting
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
	model.position = Vector3(0, hop, -0.07 * hk - float(gf["slide"]) * kk)
	model.scale = Vector3(1.0 + 0.09 * hk, 1.0 - 0.11 * hk, 1.0 + 0.09 * hk)
	# --- torse : penché dans le sens de la course, torsion de la marche, respiration et appui au repos
	var twist := _jo_hips * 0.3 + s * 0.12 * amp * (1.0 - shooting * 0.7)
	var sway := sin(t * 0.9) * idle_k
	var t_rot := Vector3(0.17 * run * mdir.y - 0.38 * hk - 0.1 * ck, twist + 0.22 * hk * _jo_hit_side, -0.1 * run * mdir.x + c * 0.04 * amp + 0.03 * sway + 0.18 * hk * _jo_hit_side)
	var t_off := Vector3(0.006 * sway, absf(c) * 0.035 * amp + breathe - 0.025 * hk, -0.02 * hk)
	if _jo_gest == 3:
		t_rot.x -= 0.14 * ge
	# recul : le buste part en arrière et l'épaule de l'arme recule (armes lourdes surtout)
	t_rot.x -= float(gf["torso"]) * kk
	t_rot.y += float(gf["torso"]) * 0.6 * kk
	t_off.z -= 0.012 * kk
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
	# visée : le recul cabre le bras de l'arme (canon qui monte), la main d'appui suit un peu
	var aim_r := Vector3(-PI * 0.5 + recoil * 0.35 - float(gf["arm"]) * kk, -twist, 0.05)
	var aim_l := Vector3(-PI * 0.44 - float(gf["arm"]) * 0.6 * kk, -0.55 - twist, -0.35)
	var sw := s * 0.7 * amp * _jo_step.y
	var swing_r := Vector3(-sw + 0.05 * sway, 0, 0.08 + 0.12 * run)
	var swing_l := Vector3(sw - 0.05 * sway, 0, -0.08 - 0.12 * run)
	var arm_r := swing_r.lerp(aim_r, shooting)
	var arm_l := swing_l.lerp(aim_l, shooting)
	# l'arme se cabre encore un peu dans la main et recule vers l'épaule (+y du bras : vers l'arrière)
	var gun_rot := Vector3(-float(gf["arm"]) * 0.45 * kk, 0, 0)
	var gun_off := Vector3(0, float(gf["push"]) * kk, 0)
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
	_pose("gun", gun_rot, gun_off)
