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

# ---------------------------------------------------------------- style BD (tous les personnages)
## Réglage Dev « comic » (bouton STYLE BD du mode développeur) : ennemis, élites, boss et robots du Relais
## prennent le rendu de Jo (shaders/jo_comic.gdshader : deux paliers nets, trame de points dans l'ombre, bords
## décalés ; encre noire jo_ink.gdshader), réglé plus sobre (COMIC_MOB). Les élites restent dorées (couleurs
## par sommet de <genre>_elite.glb), les pièces « _glow », l'éclat de coup (hit_flash : material_overlay), la
## chaleur du Pétard (« heat ») et la teinte (« tint ») marchent pareil. Un matériau par teinte, partagé ;
## une seule encre en next_pass. Désactivé : l'ancien rendu doux (body_mat).
const COMIC_MOB := {"saturation": 1.3, "step_at": 0.2, "shade_col": Color(0.4, 0.37, 0.76), "dot_col": Color(0.2, 0.16, 0.48), "chroma": 0.4, "chroma_width": 0.26, "spec_amt": 0.28, "omni_gain": 0.45,
	"rim_amt": 0.32, "rim_width": 0.22, "dot_size": 0.4}
## Encre des ennemis : plus épaisse que celle de Jo en jeu (ils sont vus de plus loin, en plus gros).
const COMIC_INK := {"uv_normal": false, "world": 0.02, "min_px": 1.6, "max_px": 3.6}
static var _comic_mats := {}
static var _comic_ink: ShaderMaterial = null

static func comic_on() -> bool:
	return bool(Dev.v.get("comic", true))

## Matériau des personnages autres que Jo : style BD si le réglage est actif, sinon l'ancien rendu.
static func char_mat(tint: Color) -> ShaderMaterial:
	return comic_mat(tint) if comic_on() else body_mat(tint)

static func comic_mat(tint: Color) -> ShaderMaterial:
	var key := tint.to_html()
	if _comic_mats.has(key):
		return _comic_mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/jo_comic.gdshader")
	m.set_shader_parameter("tint", tint)
	for k in COMIC_MOB:
		m.set_shader_parameter(k, COMIC_MOB[k])
	if outline_enabled:
		if _comic_ink == null:
			_comic_ink = ShaderMaterial.new()
			_comic_ink.shader = load("res://shaders/jo_ink.gdshader")
			for k in COMIC_INK:
				_comic_ink.set_shader_parameter(k, COMIC_INK[k])
		m.next_pass = _comic_ink
	_comic_mats[key] = m
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
var _tint := Color(1, 1, 1)
var _base_path := ""  # modèle passé à setup (Jo : jo.glb) ; une apparence peut en charger un autre
var _model_path := ""

func setup(path: String, tint: Color = Color(1, 1, 1), glow_energy: float = 3.0) -> void:
	_glow_energy = glow_energy
	_tint = tint
	_base_path = path
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1, 1, 1, 0)
	_load_model(path)

## Charge (ou remplace) le modèle : parts, poses de repos, matériaux. Jo change de modèle avec son apparence
## (apply_skin) : l'équipement est alors reposé sur les nouvelles parts.
func _load_model(path: String) -> void:
	if model != null:
		remove_child(model)
		model.queue_free()
	_model_path = path
	model = Models.scene(path).instantiate()
	add_child(model)
	parts.clear()
	rest.clear()
	for n in model.find_children("*", "Node3D", true, false):
		var nd: Node3D = n
		parts[String(nd.name)] = nd
		rest[String(nd.name)] = nd.transform
	for mi in Models.meshes(model):
		var m: MeshInstance3D = mi
		var nm := String(m.name) + String(m.get_parent().name)
		m.material_override = glow_mat(_glow_energy) if "_glow" in nm else char_mat(_tint)
	meshes = Models.meshes(model)
	_flow_scan()

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
var _gun_meshes := {}  # MeshInstance3D -> Mesh d'origine (blaster du modèle)
var _items: Array = []  # équipement porté (reposé quand le modèle change avec l'apparence)
## L'équipement est sculpté pour l'ancienne Jo (tools/chars/gear.py : coordonnées de l'ancien tools/chars/jo.py, tête ronde,
## jambe d'une pièce) : sur la nouvelle Jo (genoux « shin_* »), chaque cible est ajustée : cible -> [part
## d'accueil, Transform3D dans son repère]. L'arme garde son repère (MUZZLE inchangé).
static var GEAR_FIT := {
	"head": ["head", Transform3D(Basis.from_scale(Vector3(0.47, 0.47, 0.47)), Vector3(0, 0.037, 0.0))],
	"torso": ["torso", Transform3D(Basis.from_scale(Vector3(0.94, 1.1, 0.74)), Vector3(0, 0.109, 0.0))],
	"arm_r": ["arm_r", Transform3D(Basis.from_scale(Vector3(0.78, 1.3, 0.85)), Vector3(0, -0.015, 0))],
	"arm_l": ["arm_l", Transform3D(Basis.from_scale(Vector3(0.78, 1.3, 0.85)), Vector3(0, -0.015, 0))],
	"leg_r": ["shin_r", Transform3D(Basis.from_scale(Vector3(0.82, 0.98, 0.82)), Vector3.ZERO)],
	"leg_l": ["shin_l", Transform3D(Basis.from_scale(Vector3(0.82, 0.98, 0.82)), Vector3.ZERO)],
}

## Équipe les objets {id, rarity} : chaque objet est un GLB sculpté (tools/chars/gear.py) dont les parts
## « cible__id » se rangent dans la part cible de Jo (ajustées par GEAR_FIT). Une arme remplace le blaster.
func apply_items(items: Array) -> void:
	_items = items.duplicate()
	for g in _gear:
		if is_instance_valid(g):
			(g as Node).get_parent().remove_child(g)
			(g as Node).queue_free()
	_gear.clear()
	var gun_id := ""
	var fit := p("shin_r") != null
	for it in items:
		var id := String(it["id"])
		var path := "res://assets/chars3d/gear_%s.glb" % id
		if not ResourceLoader.exists(path):
			continue
		var glow: Color = RARITY_GLOW[clampi(int(it["rarity"]), 0, 3)]
		var inst: Node3D = Models.scene(path).instantiate()
		for n in inst.find_children("*__*", "Node3D", true, false):
			var nd: Node3D = n
			var tname := String(nd.name).get_slice("__", 0)
			var xf := Transform3D.IDENTITY
			if fit and GEAR_FIT.has(tname):
				xf = GEAR_FIT[tname][1]
				tname = GEAR_FIT[tname][0]
			var target := p(tname)
			if target == null:
				continue
			nd.get_parent().remove_child(nd)
			nd.owner = null
			target.add_child(nd)
			nd.transform = xf
			_gear.append(nd)
			for mi in Models.meshes(nd):
				if _hero_mat != null:
					(mi as MeshInstance3D).layers |= HERO_LAYER
				(mi as MeshInstance3D).material_override = tint_glow_mat(glow, 1.5) if "_glow" in String(mi.name) + String(mi.get_parent().name) else (_hero_mat if _hero_mat != null else body_mat(Color(1, 1, 1)))
		inst.queue_free()
		if id in MUZZLE:
			gun_id = id
	# arme du modèle masquée quand une arme est équipée
	if _gun_meshes.is_empty():
		for nm in ["gun", "gun_glow"]:
			var gn := p(nm)
			if gn is MeshInstance3D:
				_gun_meshes[gn] = (gn as MeshInstance3D).mesh
	for mi in _gun_meshes:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).mesh = _gun_meshes[mi] if gun_id == "" else null
	_gun_id = gun_id
	meshes = Models.meshes(model)
	if not _swapping:
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

# ---------------------------------------------------------------- coups reçus (mobs seulement ; Jo a hit())
## Mob touché (scripts/mob3d.gd) : éclat blanc net et court, tête qui part en arrière dans le sens de la balle
## puis revient sur un ressort (elle dépasse un peu), pièces qui vibrent un instant. Réglages :
const HR_HEAD := 0.45  # bascule max de la tête (rad) pour un coup plein
const HR_ROOT := 0.08  # bascule de la pièce principale (le corps entier bascule déjà dans mob3d)
const HR_SPRING := 30.0  # raideur du ressort (rad/s) : plus haut, retour plus sec
const HR_DAMP := 0.35  # amortissement : sous 1, la tête dépasse sa pose et rebondit
const HR_VIB := 0.14  # vibration des pièces (rad)
const HR_VIB_T := 0.16  # durée de la vibration (s)
const HF_HOLD := 0.034  # éclat : plein blanc tenu ~2 images, puis chute rapide
const HF_GAP := 0.03  # sous un feu nourri, noir minimal entre deux éclats (le modèle reste lisible)
var _hr_x := Vector3.ZERO  # déplacement du ressort (repère du modèle, horizontal)
var _hr_v := Vector3.ZERO
var _hr_vib := 0.0
var _hr_ready := false
var _hr_head: Node3D = null
var _hr_root: Array = []
var _hr_loose: Array = []
var _hr_saved: Array = []  # [nœud, transform] d'avant la réaction : rendus avant la pose suivante
var _hf_dur := 0.0
var _hf_peak := 0.0

## Éclat de coup : `peak` (0..1) tenu HF_HOLD puis éteint en `dur` ; `force` (critique) passe outre le noir.
func hit_flash(dur: float, peak: float, force: bool = false) -> void:
	if _hf_dur > 0.0 and _flash_t > 0.0 and not force and (_hf_dur - _flash_t) < HF_HOLD + HF_GAP:
		return
	_hf_dur = dur
	_hf_peak = peak
	_flash_t = 0.0
	flash(dur)

## Coup reçu : `dir` sens de la balle dans le repère du modèle, `amount` ~0..1,5 (dégâts, masse, critique).
func hit_react(dir: Vector3, amount: float) -> void:
	if dead:
		return
	if not _hr_ready:
		_hr_ready = true
		for nm in parts:
			var n: Node3D = parts[nm]
			if "_glow" in String(nm):
				continue
			if n.get_parent() == model:
				_hr_root.append(n)
			elif String(nm) == "head":
				_hr_head = n
			else:
				_hr_loose.append(n)
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001:
		d = Vector3(0, 0, -1)
	_hr_v += d.normalized() * amount * HR_SPRING * 1.3
	_hr_vib = maxf(_hr_vib, minf(amount * 1.3, 1.0))

func _hr_restore() -> void:
	for s in _hr_saved:
		if is_instance_valid(s[0]):
			(s[0] as Node3D).transform = s[1]
	_hr_saved.clear()

func _hr_turn(n: Node3D, b: Basis) -> void:
	_hr_saved.append([n, n.transform])
	n.transform.basis = b * n.transform.basis

## Après la pose de l'image : ressort de la tête et du corps, vibration des pièces.
func _hr_apply(dt: float) -> void:
	if _hr_vib <= 0.0 and _hr_x.length_squared() < 0.000001 and _hr_v.length_squared() < 0.0001:
		return
	var sd := minf(dt, 0.05) * 0.5
	for i in range(2):
		_hr_v += (-HR_SPRING * HR_SPRING * _hr_x - 2.0 * HR_DAMP * HR_SPRING * _hr_v) * sd
		_hr_x += _hr_v * sd
	_hr_vib = maxf(0.0, _hr_vib - dt / HR_VIB_T)
	var xl := _hr_x.length()
	if xl > 0.0005:
		var ax := Vector3.UP.cross(_hr_x / xl)
		if _hr_head != null:
			_hr_turn(_hr_head, Basis(ax, minf(xl, 1.5) * HR_HEAD))
		for n in _hr_root:
			_hr_turn(n, Basis(ax, minf(xl, 1.5) * HR_ROOT))
	if _hr_vib > 0.0:
		var a := HR_VIB * _hr_vib * _hr_vib
		var i := 0
		for n in _hr_loose:
			var ph := t * 70.0 + i * 1.7
			_hr_turn(n, Basis.from_euler(Vector3(sin(ph), sin(ph * 1.3 + 0.5), sin(ph * 0.7 + 1.1)) * a))
			i += 1

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
	if _flash_t > 0.0:
		_flash_t -= dt
		var fa := clampf(_flash_t * 10.0, 0.0, 0.85)
		if _hf_dur > 0.0:  # coup reçu par un mob (hit_flash) : plein blanc bref, puis chute rapide
			fa = _hf_peak if _hf_dur - _flash_t < HF_HOLD else _hf_peak * clampf(_flash_t / maxf(_hf_dur - HF_HOLD, 0.001), 0.0, 1.0)
		_flash_mat.albedo_color = Color(flash_color.r, flash_color.g, flash_color.b, fa)
		if _flash_t <= 0.0:
			_overlay(null)
			_veiled = false
			_hf_dur = 0.0
	if _flash_t <= 0.0 and (invuln > 0.0 or _veiled):
		_veil(dt)
	if not _hr_saved.is_empty():
		_hr_restore()
	if dead:
		_die_t += dt
		animate_death(_die_t)
		return
	recoil = maxf(0.0, recoil - dt * 9.0)
	if _is_jo and bool(Dev.v.get("jo_twos", false)):  # animation « en deux » (Spider-Verse) : pose changée 12 fois par seconde
		_twos_acc += dt
		if _twos_acc < 1.0 / 12.0 and not _twos_now:
			return
		dt = _twos_acc
		_twos_acc = 0.0
		_twos_now = false
	animate(dt)
	if _hr_ready:
		_hr_apply(dt)

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
## Une apparence est une tenue complète : un modèle entier (« model » : assets/chars3d/<model>.glb, sculpté par
## tools/blender/jo_skins.py) avec les mêmes parts que jo.glb, chargé à la place du modèle de base. En attendant sa
## tenue, une apparence peut n'être qu'une palette (« colors » : couleur de jo.glb -> couleur), appliquée aux
## couleurs par sommet (maillages recolorés une fois et gardés en cache) : toujours le même matériau.
## Les modèles de Jo du joueur (Relais, partie) suivent l'apparence équipée, inscrits par follow_skin() ; la Jo
## d'un partenaire en duo et les vignettes portent la leur (set_own_skin, show_palette).
static var hero_skin: Dictionary = {}
static var _skin_rigs: Array = []  # WeakRef des modèles de Jo
static var _recolor_cache := {}  # "apparence|maillage" -> ArrayMesh recoloré
## Apparence propre à ce modèle (Jo du partenaire en duo, vignette) : remplace l'apparence équipée.
var own_skin = null
var _swapping := false
var _orig_mesh := {}  # MeshInstance3D -> maillage du GLB (avant palette)

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
## (vide : Jo de base), sans suivre l'apparence équipée ni toucher aux autres Jo.
func show_palette(pal: Dictionary) -> void:
	set_own_skin(pal)

func apply_skin() -> void:
	if model == null or _swapping:
		return
	if own_skin == null and not _skin_rigs.any(func(w): return (w as WeakRef).get_ref() == self):
		_apply_zones()
		return
	var pal: Dictionary = own_skin if own_skin != null else hero_skin
	var path := _base_path
	if String(pal.get("model", "")) != "":
		var mp := "res://assets/chars3d/%s.glb" % String(pal["model"])
		if ResourceLoader.exists(mp):
			path = mp
	if path != _model_path:
		_swap_model(path)
	_recolor(pal)
	_apply_zones()

## Change de modèle (tenue) en gardant tout le reste : matériau de Jo, calque, équipement, pose courante.
func _swap_model(path: String) -> void:
	_swapping = true
	var keep_rot := model.rotation
	var keep_pos := model.position
	var keep_scale := model.scale
	_load_model(path)
	model.rotation = keep_rot
	model.position = keep_pos
	model.scale = keep_scale
	_gun_meshes.clear()
	_orig_mesh.clear()
	_gear.clear()
	_hr_ready = false
	_hr_saved.clear()
	if _hero_mat != null:
		_hero_material()
	apply_items(_items)
	_swapping = false

## Palette d'une apparence sans tenue : couleurs par sommet remplacées (tolérance : couleurs en aplats exacts).
func _recolor(pal: Dictionary) -> void:
	var cols: Dictionary = pal.get("colors", {})
	var key0 := String(pal.get("id", ""))
	for mi in Models.meshes(model):
		var m: MeshInstance3D = mi
		if _gear.has(m) or _gear.has(m.get_parent()):
			continue
		if not _orig_mesh.has(m):
			if m.mesh == null:
				continue
			_orig_mesh[m] = m.mesh
		var src: Mesh = _orig_mesh[m]
		var dst: Mesh = src
		if not cols.is_empty() and src is ArrayMesh:
			var k := key0 + "|" + str(src.get_instance_id())
			if not _recolor_cache.has(k):
				_recolor_cache[k] = _recolored(src as ArrayMesh, cols)
			dst = _recolor_cache[k]
		if _gun_meshes.has(m):
			_gun_meshes[m] = dst
			if m.mesh == null:
				continue
		m.mesh = dst

static func _recolored(src: ArrayMesh, cols: Dictionary) -> ArrayMesh:
	var pairs := []
	for k in cols:
		pairs.append([Color(k), cols[k] as Color])
	var out := ArrayMesh.new()
	for si in range(src.get_surface_count()):
		var arr := src.surface_get_arrays(si)
		var c = arr[Mesh.ARRAY_COLOR]
		if c is PackedColorArray:
			var pc: PackedColorArray = c
			for i in range(pc.size()):
				var v := pc[i]
				for pr in pairs:
					var a: Color = pr[0]
					if absf(v.r - a.r) + absf(v.g - a.g) + absf(v.b - a.b) < 0.02:
						pc[i] = pr[1]
						break
			arr[Mesh.ARRAY_COLOR] = pc
		out.add_surface_from_arrays(src.surface_get_primitive_type(si), arr)
	return out

# ---------------------------------------------------------------- Jo : tenue et équipement porté
## Les pièces de la tenue que l'équipement peut remplacer sont des parts du modèle nommées par zone
## (tools/blender/jo.py) : « coiffe… », « visage… », « col… », « dos… », « epaule_r… », « epaule_l… »,
## « jambe_r… », « jambe_l… » (avec leurs « _glow » et leurs pans flottants « _f1 »…).
## Règle : l'objet porté l'emporte. Il masque les pièces de tenue de sa zone (_gear_zones, d'après la forme de
## l'objet dans le repère de l'ancienne Jo, donc valable pour les objets à venir) :
##   tête    couvre-chef (casque, serre-tête : monte au-dessus du crâne) -> coiffe et visage ; visière -> visage
##   bras    objet posé sur l'épaule (module, antenne, pince) -> épaulette de ce bras ; une manche ne masque rien
##   torse   devant ou autour du cou (plastron, veste, gilet, écharpe) -> col ; dans le dos (gadget) -> dos (cape,
##           sacoche)
##   jambes  objet qui descend jusqu'au pied (bottes, patins) -> chaussures de cette jambe (jambe_*)
## Le reste de la tenue (torse, manches, jambes, logo imprimé) ne bouge jamais : c'est la silhouette de l'apparence.
const OUTFIT_ZONES := ["coiffe", "visage", "col", "dos", "epaule_r", "epaule_l", "jambe_r", "jambe_l"]

static func zone_of(part_name: String) -> String:
	for z in OUTFIT_ZONES:
		if part_name == z or part_name.begins_with(z + "_"):
			return z
	return ""

func _apply_zones() -> void:
	if model == null:
		return
	var blocked := _gear_zones()
	for nm in parts:
		var z := zone_of(String(nm))
		if z != "":
			(parts[nm] as Node3D).visible = not blocked.has(z)
	meshes = Models.meshes(model)

## Nom « cible__id » d'une part d'objet porté (sans le « @…@n » qu'ajoute Godot à un nom en double).
static func _gear_name(g: Node) -> String:
	return String(g.name).trim_prefix("@").get_slice("@", 0)

## Zones de tenue occupées par l'équipement porté (voir la règle plus haut). Les boîtes sont celles du maillage
## de l'objet, dans le repère de la part cible de l'ancienne Jo (origine au pivot : cou, épaule, hanches).
func _gear_zones() -> Dictionary:
	var out := {}
	for g in _gear:
		if not is_instance_valid(g) or not (g is MeshInstance3D) or (g as MeshInstance3D).mesh == null:
			continue
		var nm := _gear_name(g)
		var tgt := nm.get_slice("__", 0)
		var box: AABB = (g as MeshInstance3D).get_aabb()
		match tgt:
			"head":
				out["visage"] = true
				if box.end.y > 0.38:  # couvre-chef
					out["coiffe"] = true
			"torso":
				if box.get_center().z < -0.2:  # gadget dans le dos
					out["dos"] = true
				else:
					out["col"] = true
			"arm_l", "arm_r":
				if box.end.y > 0.07:  # sur l'épaule (une manche de veste reste plus bas)
					out["epaule_" + tgt.right(1)] = true
			"leg_l", "leg_r":
				if box.position.y < -0.27:  # descend jusqu'au pied
					out["jambe_" + tgt.right(1)] = true
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
	_twos_now = true  # animation en deux : le recul part tout de suite
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

## Réglages propres à l'héroïne (partie, Relais, vignettes) : matériau BD partagé (jo_mat), calque HERO_LAYER,
## voile de coup teinté.
var _hero_mat: ShaderMaterial = null
## Jo de l'invité en duo : partner3d.recolor() lui donne jo_mat(true) ; make_hero rend le matériau normal.
var _guest := false
## Calque de rendu propre à Jo : sa lumière d'appoint (view3d.gd) n'éclaire qu'elle.
const HERO_LAYER := 1 << 19
## Matériau « bande dessinée » de Jo (shaders/jo_comic.gdshader + contour d'encre jo_ink.gdshader) : un seul,
## partagé par toutes les Jo et toutes leurs tenues ; un second pour la Jo de l'invité en duo (teintes tournées).
static var _jo_mats := {}
static func jo_mat(guest: bool = false) -> ShaderMaterial:
	if _jo_mats.has(guest):
		return _jo_mats[guest]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/jo_comic.gdshader")
	m.set_shader_parameter("guest", 1.0 if guest else 0.0)
	var ink := ShaderMaterial.new()
	ink.shader = load("res://shaders/jo_ink.gdshader")
	m.next_pass = ink
	_jo_mats[guest] = m
	return m

## `outline` et `width` : gardés pour les appelants, le contour est désormais l'encre noire du matériau de Jo.
func make_hero(_outline: Color, _width: float, hurt: Color) -> void:
	_hero_mat = jo_mat(_guest)
	_is_jo = true
	_hero_material()
	flash_color = hurt
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	apply_skin()

func _hero_material() -> void:
	for mi in Models.meshes(model):
		var m: MeshInstance3D = mi
		m.layers |= HERO_LAYER
		if not ("_glow" in String(m.name) + String(m.get_parent().name)):
			m.material_override = _hero_mat

## Animation « en deux » (Jo à 12 i/s dans un jeu à 60, comme le film) : réglage Dev « jo_twos ».
var _is_jo := false
var _twos_acc := 0.0
var _twos_now := false

# ---------------------------------------------------------------- Jo : genoux et pièces qui flottent
## Pans flottants du modèle (parts « <nom>_f1 », « <nom>_f2 »… en chaîne, tools/blender/jo.py chain()) :
## écharpe ou bandeau, cape, plumet, pointe de chapeau. Ils se couchent dans le vent de la course (à
## l'opposé du déplacement), ondulent, et chaque maillon ajoute au précédent.
var _flows := []  # [{nodes: [Node3D], dir: Vector3 (sens de repos du pan, repère du modèle)}]
var _flow_w := Vector3.ZERO  # vent ressenti (repère du modèle), lissé

func _flow_scan() -> void:
	_flows.clear()
	var heads := {}
	for nm in parts:
		var s := String(nm)
		if s.ends_with("_f1"):
			heads[s.trim_suffix("_f1")] = true
	for pre in heads:
		var nodes := []
		var i := 1
		while parts.has("%s_f%d" % [pre, i]):
			nodes.append(parts["%s_f%d" % [pre, i]])
			i += 1
		var d := _model_pos(nodes[nodes.size() - 1]) - _model_pos(nodes[0]) if nodes.size() > 1 else Vector3(0, -1, -0.5)
		if d.length() < 0.001:
			d = Vector3(0, -1, -0.5)
		# une cape (zone dos) est lourde : elle se soulève moins qu'un ruban ou un plumet
		_flows.append({"nodes": nodes, "dir": d.normalized(), "gain": 0.4 if String(pre).begins_with("dos") else 1.0})

func _model_pos(n: Node3D) -> Vector3:
	var xf := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != model:
		xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf.origin

func _jo_flow(dt: float, lv: Vector3, amp: float) -> void:
	# vent : à l'opposé du déplacement, plus un souffle vers l'arrière quand on court
	var wind := Vector3(-lv.x, 0.0, -lv.z) * 1.15 + Vector3(0, 0, -0.25 * amp)
	_flow_w = _flow_w.lerp(wind, clampf(dt * 7.0, 0.0, 1.0))
	for f in _flows:
		var d: Vector3 = f["dir"]
		var nodes: Array = f["nodes"]
		for i in range(nodes.size()):
			var n: Node3D = nodes[i]
			var flutter := Vector3(sin(t * 9.0 + i * 1.4), 0.0, cos(t * 7.0 + i * 1.1) * 0.5) * (0.06 + 0.16 * amp)
			var idle := Vector3(sin(t * 1.3 + i * 0.8), 0.0, 0.0) * 0.05
			var w := _flow_w + flutter + idle
			var ax := d.cross(w)
			var r: Transform3D = rest[String(n.name)]
			if ax.length() < 0.0001:
				n.transform = r
				continue
			var ang := clampf(w.length() * (0.55 + 0.2 * i) * float(f["gain"]), 0.0, 0.85)
			n.transform = Transform3D(Basis(ax.normalized(), ang) * r.basis, r.origin)

## Genoux (parts « shin_* ») : la jambe qui revient vers l'avant plie le genou, celle d'appui reste tendue.
func _jo_knees(c: float, amp: float, run: float) -> void:
	if p("shin_r") == null:
		return
	var bend := 1.15 * amp
	_pose("shin_r", Vector3(maxf(0.0, -c) * bend + 0.12 * run, 0, 0))
	_pose("shin_l", Vector3(maxf(0.0, c) * bend + 0.12 * run, 0, 0))

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
	var t_rot := Vector3(0.26 * run * mdir.y - 0.38 * hk - 0.1 * ck, twist + 0.22 * hk * _jo_hit_side, -0.1 * run * mdir.x + c * 0.04 * amp + 0.03 * sway + 0.18 * hk * _jo_hit_side)
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
			arm_r = arm_r.lerp(Vector3(-2.5, 0.1, -0.78), ge)  # bras long de la nouvelle Jo : main au niveau de la tempe
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
	_jo_knees(c, amp, run)
	_jo_flow(dt, lv, amp)
