extends Node
## Icônes des objets, rendues une fois pour toutes depuis leurs modèles 3D (assets/chars3d/gear_<id>.glb,
## tools/blender/gear.py) : vue de trois quarts, même rendu « bande dessinée » que Jo en partie
## (shaders/jo_comic.gdshader : aplats, deux paliers de lumière, ombre froide tramée ; encre jo_ink.gdshader),
## une seule lumière de clé, fond transparent. Le jeu les affiche telles quelles (scripts/item_icon.gd), sans rendu 3D.
## Pour chaque objet :
##   assets/icons/items/<id>.png       l'objet, ses parts lumineuses en blanc neutre ;
##   assets/icons/items/<id>_glow.png  les parts lumineuses seules (blanc + halo), que le jeu teinte à la
##                                     couleur de rareté (comme Rig3D.apply_items en partie).
## Plus l'icône des tickets (pile de pièces, mêmes pièces trouées qu'en partie) : assets/icons/items/tickets.png.
## Les objets qui ne se lisent pas seuls se montrent sur une partie de Jo en mannequin gris (« ctx »).
## Un objet sans modèle est signalé et garde son pictogramme en jeu.
##
## xvfb-run -a -s "-screen 0 1600x900x24" $G --path . --rendering-driver opengl3 res://tools/item_icons.tscn \
##     -- [--only=veste,bottes,tickets] [--planche=/chemin/planche.png]
## puis `$G --headless --path . --import` pour que le jeu voie les nouvelles images.
## --planche écrit aussi une planche de toutes les icônes sur des fonds de carte, en 256 px et à 96 px.
## --jo=/chemin/jo.png écrit une planche de Jo portant chaque objet, vue de jeu (caméra haute à 56°, Jo ×1,15,
## même lumière et même liseré qu'en partie), de face en visant et de dos en courant, pixels du jeu agrandis ×2
## (--only=none pour ne faire que cette planche, --only=a,b pour quelques objets).

const Models = preload("res://scripts/models.gd")
const Data = preload("res://scripts/data.gd")

const OUT := "res://assets/icons/items/"
const SIZE := 256
const RENDER := 1024
const MARGIN := 0.07  # marge autour de l'objet, en fraction du côté
const JO := "res://assets/chars3d/jo.glb"
const COIN_LAYER := 1 << 1  # pièces des tickets : éclairées aussi par le débouchage et le contre-jour

## Arme : canon (−Y au repos) vers la droite, dessus (+Z) vers le haut.
const GUN_BASIS := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))

## Cadrage de chaque objet : orbite de la caméra (yaw : 0 = de face, 180 = de dos ; pitch : vue d'en haut),
## rotation du modèle (« gun » : arme posée de profil, « roll » : penchée de tant de degrés pour remplir le carré),
## parts de Jo montrées en mannequin (« ctx »). La selle des modules d'épaule (part « *_selle » : plaque et sangle
## autour du bras) n'apparaît pas dans l'icône : sans le bras, la sangle ferait un anneau vide.
const VIEWS := {
	"blaster_garde": {"yaw": -28.0, "pitch": 16.0, "basis": "gun", "roll": 14.0},
	"fusil_impulsion": {"yaw": -28.0, "pitch": 16.0, "basis": "gun", "roll": 34.0},
	"riveteuse": {"yaw": -28.0, "pitch": 20.0, "basis": "gun", "roll": 14.0},
	"pistolet_neon": {"yaw": -28.0, "pitch": 18.0, "basis": "gun", "roll": 14.0},
	"module_canon": {"yaw": 38.0, "pitch": 22.0},
	"cellule": {"yaw": 34.0, "pitch": 14.0},
	"pince": {"yaw": 62.0, "pitch": 16.0},
	"antenne": {"yaw": 80.0, "pitch": 22.0},
	"visiere": {"yaw": -30.0, "pitch": 8.0, "ctx": ["head"]},
	"casque_garde": {"yaw": 30.0, "pitch": 16.0},
	"casque_docker": {"yaw": 30.0, "pitch": 16.0},
	"oreilles_chat": {"yaw": 22.0, "pitch": 10.0},
	"plastron": {"yaw": 26.0, "pitch": 14.0},
	"veste": {"yaw": 16.0, "pitch": 8.0},
	"gilet_fret": {"yaw": 22.0, "pitch": 14.0, "ctx": ["arm_l", "arm_r"]},
	"echarpe": {"yaw": 28.0, "pitch": 12.0},
	"bottes": {"yaw": 34.0, "pitch": 16.0},
	"jambieres": {"yaw": 48.0, "pitch": 12.0, "ctx": ["shin_l", "shin_r"]},
	"amortisseurs": {"yaw": 50.0, "pitch": 14.0, "ctx": ["shin_l", "shin_r"]},
	"patins": {"yaw": 36.0, "pitch": 22.0},
	"pile": {"yaw": 200.0, "pitch": 16.0},
	"aimant": {"yaw": 196.0, "pitch": 14.0},
	"reservoir": {"yaw": 204.0, "pitch": 18.0},
	"ailes": {"yaw": 192.0, "pitch": 24.0},
}

var vp: SubViewport
var cam: Camera3D
var stage: Node3D
var body_mat: ShaderMaterial
var ctx_mat: ShaderMaterial
var glow_mat: StandardMaterial3D
var black_mat: StandardMaterial3D
var white_mat: StandardMaterial3D
var outline_mat: ShaderMaterial
var only: Array = []
var planche := ""
var jo_planche := ""
var _rigs: Array = []  # Jo de la planche « vue de jeu » : {rig, speed, shoot, move}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = Array(a.trim_prefix("--only=").split(","))
		elif a.begins_with("--planche="):
			planche = a.trim_prefix("--planche=")
		elif a.begins_with("--jo="):
			jo_planche = a.trim_prefix("--jo=")
	_build()
	_run.call_deferred()

# ---------------------------------------------------------------- scène de studio
func _build() -> void:
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(RENDER, RENDER)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.74, 0.9)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	we.environment = env
	vp.add_child(we)
	# clé chaude douce en haut à gauche, débouchage froid à droite, contre-jour qui détache le bord
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.97, 0.92)
	key.light_energy = 1.25
	vp.add_child(key)
	key.set_meta("dir", Vector3(-35, -40, 0))
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.72, 0.82, 1.0)
	fill.light_energy = 0.45
	fill.light_cull_mask = COIN_LAYER  # le matériau BD des objets n'a qu'une lumière (la clé)
	vp.add_child(fill)
	fill.set_meta("dir", Vector3(-10, 60, 0))
	var back := DirectionalLight3D.new()
	back.light_color = Color(0.8, 0.9, 1.0)
	back.light_energy = 0.9
	back.light_cull_mask = COIN_LAYER
	vp.add_child(back)
	back.set_meta("dir", Vector3(-25, 165, 0))
	cam = Camera3D.new()
	cam.fov = 22.0
	cam.near = 0.01
	cam.far = 50.0
	vp.add_child(cam)
	cam.make_current()
	stage = Node3D.new()
	vp.add_child(stage)
	# contour des pièces de monnaie (tickets, matériau standard)
	outline_mat = ShaderMaterial.new()
	outline_mat.shader = load("res://shaders/character_outline.gdshader")
	outline_mat.set_shader_parameter("width", 7.0)  # en px d'un écran de 720 px : ~4 px dans l'icône de 256
	outline_mat.set_shader_parameter("ink", Color(0.03, 0.035, 0.07))
	# objets : le matériau de Jo (jo_comic + encre), trame plus grosse (l'image est réduite 4 fois)
	var ink := ShaderMaterial.new()
	ink.shader = load("res://shaders/jo_ink.gdshader")
	ink.set_shader_parameter("world", 1.0)
	ink.set_shader_parameter("min_px", 8.5)  # px d'un écran de 720 px : ~3 px dans l'icône de 256
	ink.set_shader_parameter("max_px", 8.5)
	body_mat = ShaderMaterial.new()
	body_mat.shader = load("res://shaders/jo_comic.gdshader")
	body_mat.set_shader_parameter("dot_cell", 9.0)
	body_mat.set_shader_parameter("dot_size", 0.36)
	body_mat.set_shader_parameter("chroma", 0.35)
	body_mat.set_shader_parameter("saturation", 1.12)
	body_mat.set_shader_parameter("step_at", 0.0)
	body_mat.next_pass = ink
	# mannequin : Jo en ardoise mate, pour situer l'objet sans lui voler la vedette
	ctx_mat = body_mat.duplicate()
	ctx_mat.set_shader_parameter("saturation", 0.0)
	ctx_mat.set_shader_parameter("tint", Color(0.62, 0.66, 0.8))
	ctx_mat.set_shader_parameter("exposure", 0.85)
	ctx_mat.set_shader_parameter("chroma", 0.0)
	ctx_mat.set_shader_parameter("spec_amt", 0.0)
	ctx_mat.next_pass = ink
	glow_mat = StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color = Color(0.86, 0.92, 1.0)
	black_mat = StandardMaterial3D.new()
	black_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black_mat.albedo_color = Color.BLACK
	white_mat = StandardMaterial3D.new()
	white_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white_mat.albedo_color = Color.WHITE

func _clear_stage() -> void:
	for c in stage.get_children():
		stage.remove_child(c)
		c.queue_free()
	stage.transform = Transform3D.IDENTITY

## Pose les lumières par rapport à la caméra (le studio tourne avec elle : même éclairage pour tous).
func _place(view: Dictionary, ab: AABB) -> void:
	var yaw := deg_to_rad(float(view.get("yaw", 30.0)))
	var pitch := deg_to_rad(float(view.get("pitch", 15.0)))
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var c := ab.get_center()
	var r := ab.size.length() * 0.5
	var dist := r / sin(deg_to_rad(cam.fov * 0.5)) * 1.02
	cam.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), c + dir * dist)
	for l in vp.get_children():
		if l is DirectionalLight3D:
			var d: Vector3 = l.get_meta("dir")
			l.basis = cam.basis * Basis.from_euler(Vector3(deg_to_rad(d.x), deg_to_rad(d.y), 0.0))

func _aabb(nodes: Array) -> AABB:
	var ab := AABB()
	var first := true
	for mi in nodes:
		var m: MeshInstance3D = mi
		var a: AABB = m.global_transform * m.get_aabb()
		ab = a if first else ab.merge(a)
		first = false
	return ab

static func _is_glow(m: MeshInstance3D) -> bool:
	return "_glow" in String(m.name) + String(m.get_parent().name)

# ---------------------------------------------------------------- rendu
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var done := []
	for tpl in Data.ITEMS:
		var id := String(tpl["id"])
		if not only.is_empty() and not only.has(id):
			continue
		var path := "res://assets/chars3d/gear_%s.glb" % id
		if not ResourceLoader.exists(path):
			print("ICONES : pas de modèle pour « %s » (%s)" % [id, path])
			continue
		await _render_item(id, path)
		done.append(id)
	if only.is_empty() or only.has("tickets"):
		await _render_tickets()
		done.append("tickets")
	print("ICONES : %d icônes écrites dans %s" % [done.size(), OUT])
	if planche != "":
		_planche(planche)
	if jo_planche != "":
		await _jo_board(jo_planche)
	get_tree().quit()

func _render_item(id: String, path: String) -> void:
	_clear_stage()
	var view: Dictionary = VIEWS.get(id, {})
	var inst: Node3D = Models.scene(path).instantiate()
	stage.add_child(inst)
	if String(view.get("basis", "")) == "gun":
		stage.basis = Basis(Vector3(0, 0, 1), deg_to_rad(float(view.get("roll", 0.0)))) * GUN_BASIS
	var item_meshes := []
	for mi in Models.meshes(inst):
		if "_selle" in String((mi as Node).name) + String((mi as Node).get_parent().name):
			(mi as MeshInstance3D).mesh = null
		else:
			item_meshes.append(mi)
	var ctx_meshes := []
	var want: Array = view.get("ctx", [])
	if not want.is_empty():
		var jo: Node3D = Models.scene(JO).instantiate()
		stage.add_child(jo)
		for mi in Models.meshes(jo):
			var m: MeshInstance3D = mi
			if want.has(String(m.name)):
				ctx_meshes.append(m)
			else:
				m.mesh = null  # les autres parts (et leurs lumières) disparaissent, la hiérarchie reste
	_place(view, _aabb(item_meshes + ctx_meshes))
	var img := await _shoot(item_meshes, ctx_meshes, false)
	var mask := await _shoot(item_meshes, ctx_meshes, true)
	_save(id, img, mask, _aabb_rect(img))

## Une prise : couleurs (mask = false) ou masque des parts lumineuses (blanc sur noir).
func _shoot(item_meshes: Array, ctx_meshes: Array, mask: bool) -> Image:
	for mi in item_meshes:
		var m: MeshInstance3D = mi
		if _is_glow(m):
			m.material_override = white_mat if mask else glow_mat
		else:
			m.material_override = black_mat if mask else body_mat
	for mi in ctx_meshes:
		(mi as MeshInstance3D).material_override = black_mat if mask else ctx_mat
	for i in range(4):
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img

## Carré englobant les pixels visibles, avec une marge.
func _aabb_rect(img: Image) -> Rect2i:
	var u := img.get_used_rect()
	var side := int(maxf(u.size.x, u.size.y) * (1.0 + 2.0 * MARGIN))
	var c := u.get_center()
	return Rect2i(c.x - side / 2, c.y - side / 2, side, side)

static func _crop(img: Image, r: Rect2i) -> Image:
	var out := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var src := r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	out.blit_rect(img, src, src.position - r.position)
	return out

## Réduction propre (moyenne des pixels, couleurs prémultipliées : pas de liseré sombre sur les bords).
static func _shrink(img: Image, side: int) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		var a := data[i + 3]
		if a < 255:
			data[i] = data[i] * a / 255
			data[i + 1] = data[i + 1] * a / 255
			data[i + 2] = data[i + 2] * a / 255
	var pm := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	pm.generate_mipmaps()
	pm.resize(side, side, Image.INTERPOLATE_TRILINEAR)
	pm.clear_mipmaps()
	var d2 := pm.get_data()
	for i in range(0, d2.size(), 4):
		var a := d2[i + 3]
		if a > 0 and a < 255:
			d2[i] = mini(255, d2[i] * 255 / a)
			d2[i + 1] = mini(255, d2[i + 1] * 255 / a)
			d2[i + 2] = mini(255, d2[i + 2] * 255 / a)
	return Image.create_from_data(side, side, false, Image.FORMAT_RGBA8, d2)

## Couche lumineuse : blanc, opacité = masque (cœur net) + halo doux autour.
static func _glow_layer(mask: Image) -> Image:
	var side := mask.get_width()
	var core := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var md := mask.get_data()
	var cd := PackedByteArray()
	cd.resize(md.size())
	var any := false
	for i in range(0, md.size(), 4):
		var v := md[i] * md[i + 3] / 255
		cd[i] = 255
		cd[i + 1] = 255
		cd[i + 2] = 255
		cd[i + 3] = v
		if v > 40:
			any = true
	if not any:
		return null
	core = Image.create_from_data(side, side, false, Image.FORMAT_RGBA8, cd)
	# halo : réduction moyennée (mipmaps) puis agrandissement doux, deux rayons
	var hd := []
	for div in [24, 10]:
		var halo := core.duplicate() as Image
		halo.generate_mipmaps()
		halo.resize(side / div, side / div, Image.INTERPOLATE_TRILINEAR)
		halo.clear_mipmaps()
		halo.resize(side, side, Image.INTERPOLATE_CUBIC)
		hd.append(halo.get_data())
	for i in range(0, cd.size(), 4):
		var h := mini(255, hd[0][i + 3] * 2) * 0.32 + mini(255, hd[1][i + 3] * 2) * 0.3
		cd[i + 3] = maxi(cd[i + 3], int(h))
	return Image.create_from_data(side, side, false, Image.FORMAT_RGBA8, cd)

func _save(id: String, img: Image, mask: Image, r: Rect2i) -> void:
	var base := _shrink(_crop(img, r), SIZE)
	base.save_png(ProjectSettings.globalize_path(OUT + id + ".png"))
	var glow_path := ProjectSettings.globalize_path(OUT + id + "_glow.png")
	var g := _glow_layer(_shrink(_crop(mask, r), SIZE))
	if g != null:
		g.save_png(glow_path)
	elif FileAccess.file_exists(glow_path):
		DirAccess.remove_absolute(glow_path)
	print("ICONES : %s%s" % [id, "  (+ lumière)" if g != null else ""])

# ---------------------------------------------------------------- tickets
## Pièces des tickets (comme en partie : disque doré troué) : deux à plat, une debout devant.
func _coin(pos: Vector3, rot: Vector3, gold: Material, dark: Material, rim: Material) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = rot
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 0.13
	cm.radial_segments = 48
	cm.rings = 1
	disc.mesh = cm
	disc.material_override = gold
	disc.layers = 1 | COIN_LAYER
	n.add_child(disc)
	for s in [-1.0, 1.0]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.37
		tm.outer_radius = 0.47
		tm.rings = 48
		tm.ring_segments = 12
		ring.mesh = tm
		ring.scale = Vector3(1, 0.5, 1)
		ring.position.y = s * 0.065
		ring.material_override = rim
		ring.layers = 1 | COIN_LAYER
		n.add_child(ring)
	var hole := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.14
	hm.bottom_radius = 0.14
	hm.height = 0.135
	hm.radial_segments = 32
	hm.rings = 1
	hole.mesh = hm
	hole.material_override = dark
	hole.layers = 1 | COIN_LAYER
	n.add_child(hole)
	stage.add_child(n)
	return n

func _render_tickets() -> void:
	_clear_stage()
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("#FFC23D")
	gold.metallic = 0.55
	gold.roughness = 0.32
	gold.rim_enabled = true
	gold.rim = 0.5
	gold.rim_tint = 0.4
	gold.emission_enabled = true
	gold.emission = Color("#FF9A1F")
	gold.emission_energy_multiplier = 0.18
	gold.next_pass = outline_mat
	var rim := gold.duplicate() as StandardMaterial3D
	rim.albedo_color = Color("#FFE08A")
	rim.next_pass = null
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#8A5410")
	dark.roughness = 0.7
	# pile de trois pièces à plat, une quatrième debout devant, appuyée sur la pile
	var coins := [
		_coin(Vector3(0.0, 0.0, 0.0), Vector3(0, 0, 0), gold, dark, rim),
		_coin(Vector3(0.07, 0.14, -0.05), Vector3(0, 20, 3), gold, dark, rim),
		_coin(Vector3(-0.03, 0.28, 0.02), Vector3(0, 40, -2), gold, dark, rim),
		_coin(Vector3(0.62, 0.36, 0.42), Vector3(68, 24, 0), gold, dark, rim),
	]
	var ms := []
	for c in coins:
		ms.append_array(Models.meshes(c))
	_place({"yaw": 24.0, "pitch": 26.0}, _aabb(ms))
	for i in range(4):
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var base := _shrink(_crop(img, _aabb_rect(img)), SIZE)
	base.save_png(ProjectSettings.globalize_path(OUT + "tickets.png"))
	print("ICONES : tickets")

# ---------------------------------------------------------------- planche
## Toutes les icônes sur des cartes aux couleurs des raretés : en grand (256 px) et à taille téléphone (96 px).
func _planche(path: String) -> void:
	var ids := ["tickets"]
	for tpl in Data.ITEMS:
		ids.append(String(tpl["id"]))
	var cell := 280
	var W := 40 + cell * 7
	var rows_big := int(ceil(ids.size() / 7.0))
	var per_row := int((W - 20) / 106)
	var rows_small := int(ceil(ids.size() / float(per_row)))
	var H := 40 + rows_big * (cell + 10) + 4 * rows_small * 130 + 40
	var out := Image.create(W, H, false, Image.FORMAT_RGBA8)
	out.fill(Color("#0B1530"))
	var y := 20
	for i in range(ids.size()):
		var id: String = ids[i]
		var x := 20 + (i % 7) * cell
		var yy := y + int(i / 7) * (cell + 10)
		var rc: Color = Data.RARITY_COLORS[i % 4] if id != "tickets" else Color("#FFB347")
		_card(out, Rect2i(x + 6, yy + 6, cell - 12, cell - 12), rc)
		_stamp(out, id, Rect2i(x + 12, yy + 12, 256, 256), rc)
	y += rows_big * (cell + 10) + 10
	# taille téléphone : chaque icône à 96 px, dans les quatre raretés
	for rr in range(4):
		var rc: Color = Data.RARITY_COLORS[rr]
		for i in range(ids.size()):
			var x := 20 + (i % per_row) * 106
			var yy := y + int(i / per_row) * 130
			_card(out, Rect2i(x, yy, 100, 120), rc)
			_stamp(out, ids[i], Rect2i(x + 2, yy + 12, 96, 96), Color("#FFB347") if ids[i] == "tickets" else rc)
		y += rows_small * 130
	out.save_png(path)
	print("ICONES : planche %s" % path)

static func _card(out: Image, r: Rect2i, rc: Color) -> void:
	out.fill_rect(r, Color("#16254A").lerp(rc, 0.18))
	out.fill_rect(Rect2i(r.position, Vector2i(r.size.x, 4)), rc)
	out.fill_rect(Rect2i(r.position + Vector2i(0, r.size.y - 4), Vector2i(r.size.x, 4)), rc)

static func _stamp(out: Image, id: String, r: Rect2i, glow_col: Color) -> void:
	var p := ProjectSettings.globalize_path(OUT + id + ".png")
	if not FileAccess.file_exists(p):
		return
	var img := Image.load_from_file(p)
	img.convert(Image.FORMAT_RGBA8)
	if r.size.x != img.get_width():
		img = _shrink(img, r.size.x)
	out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), r.position)
	var gp := ProjectSettings.globalize_path(OUT + id + "_glow.png")
	if FileAccess.file_exists(gp):
		var g := Image.load_from_file(gp)
		g.convert(Image.FORMAT_RGBA8)
		if r.size.x != g.get_width():
			g = _shrink(g, r.size.x)
		var gd := g.get_data()
		for i in range(0, gd.size(), 4):
			gd[i] = int(glow_col.r8)
			gd[i + 1] = int(glow_col.g8)
			gd[i + 2] = int(glow_col.b8)
		out.blend_rect(Image.create_from_data(g.get_width(), g.get_height(), false, Image.FORMAT_RGBA8, gd), Rect2i(Vector2i.ZERO, g.get_size()), r.position)

# ---------------------------------------------------------------- Jo équipée, vue de jeu
const Rig3D = preload("res://scripts/rig3d.gd")
const GAME_SIZE := Vector2i(1280, 720)
const CROP := 150  # côté du recadrage autour de Jo, en pixels d'un écran de 720 px
const ZOOM := 2
const WORLD_NAMES := {"n7": "Nébuleuse 7", "neon": "Cité Néon"}

func _process(_dt: float) -> void:
	for c in _rigs:
		var r: Node3D = c["rig"]
		r.set_motion(float(c["speed"]), float(c["shoot"]))
		r.set_move(c["move"])
		if float(c["shoot"]) > 0.5 and Engine.get_process_frames() % 10 == 0:
			r.fire()

## Planche : pour chaque objet, Jo de face qui vise et Jo de dos qui court, sous la caméra de jeu.
func _jo_board(path: String) -> void:
	var gv := SubViewport.new()
	gv.own_world_3d = true
	gv.size = GAME_SIZE
	gv.msaa_3d = Viewport.MSAA_4X
	gv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(gv)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0B1226")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.92)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	we.environment = env
	gv.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 28, 0)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	gv.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor.mesh = pm
	floor.material_override = Models.toon(Color("#2C3050"), 0.0)
	gv.add_child(floor)
	for i in range(-8, 9):
		for j in range(-6, 7):
			if (i + j) % 3 == 0:
				var tile := Models.box(Vector3(1.3, 0.01, 1.3), Models.toon(Color("#262A48"), 0.0))
				tile.position = Vector3(i * 2.0, 0.005, j * 2.0)
				gv.add_child(tile)
	var gcam := Camera3D.new()
	gcam.fov = 38.0
	gv.add_child(gcam)
	var pitch := deg_to_rad(56.0)
	gcam.position = Vector3(0, sin(pitch), cos(pitch)) * 11.5
	gcam.look_at(Vector3.ZERO, Vector3.UP)
	gcam.make_current()
	var holder := Node3D.new()
	gv.add_child(holder)
	var shots := []  # {id, a: Image, b: Image}
	var ids := []
	for tpl in Data.ITEMS:
		var id := String(tpl["id"])
		if only.is_empty() or only.has(id) or only.has("none"):
			ids.append(id)
	for id in ids:
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		_rigs.clear()
		var poses := [
			{"pos": Vector3(-1.4, 0, 0), "yaw": 0.55, "speed": 0.0, "shoot": 1.0},
			{"pos": Vector3(1.4, 0, 0), "yaw": PI + 0.6, "speed": 0.85, "shoot": 0.0},
		]
		for ps in poses:
			var r := Rig3D.new()
			holder.add_child(r)
			r.setup(JO, Color(1, 1, 1), 1.7)
			r.make_hero(Color(0.5, 1.0, 0.94), 0.007, Color(1.0, 0.22, 0.28))
			r.position = ps["pos"]
			r.rotation.y = ps["yaw"]
			r.scale = Vector3.ONE * 1.15
			r.apply_items([{"id": id, "rarity": 2}])
			var key := OmniLight3D.new()
			key.position = ps["pos"] + Vector3(0.0, 2.4, 1.8)
			key.omni_range = 4.5
			key.omni_attenuation = 0.6
			key.light_color = Color(1.0, 0.97, 0.94)
			key.light_cull_mask = Rig3D.HERO_LAYER
			holder.add_child(key)
			var sh := Models.shadow_blob(1.1)
			sh.position = ps["pos"] + Vector3(0, 0.02, 0)
			holder.add_child(sh)
			var fwd := Vector3(sin(ps["yaw"]), 0, cos(ps["yaw"]))
			_rigs.append({"rig": r, "speed": ps["speed"], "shoot": ps["shoot"], "move": fwd * 0.9 if ps["speed"] > 0.0 else Vector3.ZERO})
		for i in range(24):
			await RenderingServer.frame_post_draw
		var img := gv.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var crops := []
		for ps in poses:
			var c2: Vector2 = gcam.unproject_position(ps["pos"] + Vector3(0, 0.62, 0))
			var r2 := Rect2i(int(c2.x) - CROP / 2, int(c2.y) - CROP / 2, CROP, CROP)
			var cr := _crop(img, r2)
			cr.resize(CROP * ZOOM, CROP * ZOOM, Image.INTERPOLATE_NEAREST)
			crops.append(cr)
		shots.append({"id": id, "a": crops[0], "b": crops[1]})
		print("JO : %s" % id)
	_rigs.clear()
	gv.queue_free()
	await _compose_jo(shots, path)

## Assemble la planche (vignettes nommées) dans un viewport 2D et l'enregistre.
func _compose_jo(shots: Array, path: String) -> void:
	var cols := 4
	var side := CROP * ZOOM
	var cw := side * 2 + 30
	var ch := side + 46
	var rows := int(ceil(shots.size() / float(cols)))
	var v2 := SubViewport.new()
	v2.size = Vector2i(cols * cw + 20, rows * ch + 20)
	v2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(v2)
	var bg := ColorRect.new()
	bg.color = Color("#070B18")
	bg.size = Vector2(v2.size)
	v2.add_child(bg)
	for i in range(shots.size()):
		var s: Dictionary = shots[i]
		var tpl := Data.item_template(String(s["id"]))
		var x := 10 + (i % cols) * cw
		var y := 10 + int(i / cols) * ch
		var l := Label.new()
		l.text = "%s  ·  %s  ·  %s" % [String(tpl["name"]), String(Data.SLOT_NAMES[tpl["slot"]]), String(WORLD_NAMES.get(String(tpl.get("world", "")), "garde"))]
		l.add_theme_font_size_override("font_size", 22)
		l.position = Vector2(x + 6, y + 6)
		v2.add_child(l)
	for i in range(4):
		await RenderingServer.frame_post_draw
	# le viewport 2D ne sert qu'aux noms : les vues sont collées telles quelles (relues d'un viewport 2D, elles
	# sortiraient éclaircies une seconde fois)
	var out := v2.get_texture().get_image()
	out.convert(Image.FORMAT_RGBA8)
	for i in range(shots.size()):
		var s: Dictionary = shots[i]
		var x := 10 + (i % cols) * cw
		var y := 10 + int(i / cols) * ch
		for k in range(2):
			var im: Image = s["a" if k == 0 else "b"]
			out.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x + k * (side + 8), y + 40))
	out.save_png(path)
	print("JO : planche %s" % path)
	v2.queue_free()
