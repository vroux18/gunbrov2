extends Node
## Vignettes de l'écran APPARENCES : Jo en 3D (de la tête aux genoux) (scripts/rig3d.gd) dans chaque apparence, rendue une seule fois
## puis gardée en texture (cache partagé, `cache`). Un seul SubViewport, créé à l'ouverture de l'écran : une
## apparence par image (la palette change, le viewport rend une fois, l'image est copiée), puis le viewport et
## le modèle sont libérés. Rien ne reste à rendre en continu. Sans rendu (--headless), rien n'est produit et
## l'écran garde ses dessins 2D.
## Usage : var th := Thumbs.new(); add_child(th); th.rendered.connect(f); th.start(ids)

const Rig3D = preload("res://scripts/rig3d.gd")
const Models = preload("res://scripts/models.gd")
const Loot = preload("res://scripts/loot.gd")

const JO_MODEL := "res://assets/chars3d/jo.glb"
const SIZE := Vector2i(256, 256)
const WARM := 4  # images d'attente avant la première prise (pose de repos posée, ressources chargées)

static var cache := {}  # id d'apparence -> Texture2D

signal rendered(id: String, tex: Texture2D)

var _todo: Array = []
var _vp: SubViewport = null
var _rig: Rig3D = null
var _cur := ""
var _warm := 0

static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"

func start(ids: Array) -> void:
	for id in ids:
		if not cache.has(String(id)) and not _todo.has(String(id)):
			_todo.append(String(id))
	if _todo.is_empty() or not can_render():
		_todo.clear()
		return
	if _vp == null:
		_build()

func _build() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.size = SIZE
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.95)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.2
	key.rotation_degrees = Vector3(-38, 24, 0)
	_vp.add_child(key)
	# liseré froid par derrière : lumière ponctuelle (Jo n'a qu'un soleil : ses deux paliers de BD)
	var back := OmniLight3D.new()
	back.light_color = Color(0.65, 0.78, 1.0)
	back.light_energy = 1.2
	back.omni_range = 6.0
	back.position = Vector3(-1.5, 2.0, -2.5)
	_vp.add_child(back)
	_rig = Rig3D.new()
	_vp.add_child(_rig)
	_rig.setup(JO_MODEL, Color(1, 1, 1), 1.7)
	_rig.make_hero(Color(0, 0, 0), 0.0, Color(1.0, 0.22, 0.28))  # matériau BD de Jo
	_rig.rotation.y = 0.42
	# cadrage en pied d'après la boîte englobante du modèle
	var ab := AABB()
	var first := true
	for mi in Models.meshes(_rig.model):
		var m: MeshInstance3D = mi
		var a: AABB = m.global_transform * m.get_aabb()
		ab = a if first else ab.merge(a)
		first = false
	# de la tête aux genoux, avec de la place au-dessus de la tête de Jo (cadrage commun, pris sur jo.glb) pour
	# les grands couvre-chefs des tenues (chapeau pointu, couronne, tuba, bord de chapeau de paille)
	var h := maxf(ab.size.y, 0.5)
	var c := Vector3(ab.get_center().x, ab.end.y - h * 0.35, ab.get_center().z)
	var cam := Camera3D.new()
	cam.fov = 24.0
	var dist := h * 0.48 / tan(deg_to_rad(cam.fov * 0.5))
	var cp := c + Vector3(0, h * 0.14, dist)
	cam.transform = Transform3D(Basis.looking_at(c - cp, Vector3.UP), cp)
	_vp.add_child(cam)
	_warm = 0
	_cur = ""

func _process(_dt: float) -> void:
	if _vp == null:
		return
	if _warm < WARM:
		_warm += 1
		if _warm == WARM:
			_rig.process_mode = Node.PROCESS_MODE_DISABLED  # pose figée : toutes les vignettes pareilles
		return
	if _cur != "":
		var img := _vp.get_texture().get_image()
		if img == null or img.is_empty():
			_finish()
			return
		var tex := ImageTexture.create_from_image(img)
		cache[_cur] = tex
		rendered.emit(_cur, tex)
		_cur = ""
	if _todo.is_empty():
		_finish()
		return
	_cur = String(_todo.pop_front())
	_rig.show_palette(Loot.skin_palette(_cur))
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

func _finish() -> void:
	_todo.clear()
	_cur = ""
	if _vp != null:
		_vp.queue_free()
	_vp = null
	_rig = null

# ---------------------------------------------------------------- petits dessins de l'écran
## Cadenas (apparence pas encore obtenue), centré sur `c`, de hauteur `s`.
static func draw_lock(ci: CanvasItem, c: Vector2, s: float, col: Color, ink: Color) -> void:
	var w := s * 0.78
	var body := Rect2(c + Vector2(-w * 0.5, -s * 0.08), Vector2(w, s * 0.58))
	var arc_r := w * 0.3
	var arc_c := c + Vector2(0, -s * 0.08)
	ci.draw_arc(arc_c, arc_r, PI, TAU, 16, ink, s * 0.2, true)
	ci.draw_arc(arc_c, arc_r, PI, TAU, 16, col, s * 0.11, true)
	for x in [-arc_r, arc_r]:
		ci.draw_line(arc_c + Vector2(x, 0), arc_c + Vector2(x, s * 0.06), col, s * 0.11)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(s * 0.12))
	sb.border_color = ink
	sb.set_border_width_all(maxi(2, int(s * 0.05)))
	sb.expand_margin_left = s * 0.04
	sb.expand_margin_right = s * 0.04
	sb.expand_margin_top = s * 0.04
	sb.expand_margin_bottom = s * 0.04
	sb.anti_aliasing = true
	ci.draw_style_box(sb, body)
	ci.draw_circle(body.get_center() + Vector2(0, -s * 0.05), s * 0.08, ink)
	ci.draw_line(body.get_center() + Vector2(0, -s * 0.03), body.get_center() + Vector2(0, s * 0.13), ink, s * 0.07)

## Tir de Jo en vol (aperçu des traînées) : traînée qui s'affine, halo, cœur blanc. `d` : direction unitaire.
static func draw_bolt(ci: CanvasItem, head: Vector2, d: Vector2, ln: float, w: float, col: Color, a: float) -> void:
	var seg := 7
	for i in range(seg):
		var u0 := float(i) / seg
		var u1 := float(i + 1) / seg
		ci.draw_line(head - d * ln * (1.0 - u0), head - d * ln * (1.0 - u1), Color(col, a * u1 * 0.75), w * (0.25 + 0.75 * u1), true)
	ci.draw_circle(head, w * 1.6, Color(col, a * 0.35))
	ci.draw_circle(head, w * 0.95, Color(col, a))
	ci.draw_circle(head, w * 0.5, Color(1, 1, 1, a * 0.95))
