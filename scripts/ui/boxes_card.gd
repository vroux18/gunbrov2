extends Control
## Carte de récompense sortie d'une box : fond à la couleur de la rareté, halo qui pulse (rayons tournants pour
## l'épique et le légendaire), pictogramme (tickets, objet, buste de Jo, traînée de tir), nom, rareté.
## « NOUVEAU » sur un cosmétique gagné, « DOUBLON » quand il devient des tickets.

const UI = preload("res://scripts/ui.gd")
const Fx = preload("res://scripts/ui/fx.gd")
const Icon = preload("res://scripts/icon.gd")
const Data = preload("res://scripts/data.gd")
const Loot = preload("res://scripts/loot.gd")
const Art = preload("res://scripts/ui/boxes_art.gd")

var reward: Dictionary
var col := Color.WHITE
var tier := 0
var t := 0.0
var _halo: TextureRect
var _rays: Control
var _art: Control
var mini := false  # récapitulatif : sans halo ni rayons
var back: Control = null  # dos de la carte (avant le retournement)

func setup(r: Dictionary, sz: Vector2, small: bool = false) -> void:
	reward = r
	mini = small
	size = sz
	custom_minimum_size = sz
	pivot_offset = sz * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := Loot.describe(r)
	col = d[3]
	tier = int(r.get("tier", 0))
	if String(r["kind"]) == "tickets":
		tier = 0
	# halo et rayons derrière la carte
	if not mini:
		_rays = Control.new()
		_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rays.show_behind_parent = true
		_rays.size = sz
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_rays.material = add
		_rays.draw.connect(_draw_rays)
		add_child(_rays)
		_halo = Fx.halo(Color(col, 0.55 + 0.12 * tier), sz * (1.9 + 0.25 * tier))
		_halo.position = (sz - _halo.size) * 0.5
		_halo.show_behind_parent = true
		add_child(_halo)
		Fx.pulse(_halo, 0.65, 1.0, 1.1)
	# pictogramme
	var art_r := Rect2(sz.x * 0.2, sz.y * 0.1, sz.x * 0.6, sz.y * 0.4)
	match String(r["kind"]):
		"tickets":
			var ic := Icon.new("coin", UI.GOLD, art_r.size.y * 0.8)
			ic.position = art_r.position + (art_r.size - Vector2.ONE * art_r.size.y * 0.8) * 0.5
			ic.size = Vector2.ONE * art_r.size.y * 0.8
			add_child(ic)
		"item":
			var tpl := Data.item_template(String(r["item"]["id"]))
			var ic2 := Icon.new(String(tpl["slot"]), col, art_r.size.y * 0.78)
			ic2.position = art_r.position + (art_r.size - Vector2.ONE * art_r.size.y * 0.78) * 0.5
			ic2.size = Vector2.ONE * art_r.size.y * 0.78
			add_child(ic2)
		_:
			_art = Control.new()
			_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_art.position = art_r.position
			_art.size = art_r.size
			var c := Loot.cosmetic(String(r["kind"]), String(r["id"]))
			var is_skin: bool = r["kind"] == "skin"
			_art.draw.connect(func():
				if is_skin:
					Art.draw_skin(_art, Rect2(Vector2.ZERO, _art.size), c, false, t)
				else:
					Art.draw_trail(_art, Rect2(Vector2(0, _art.size.y * 0.1), _art.size * Vector2(1, 0.8)), c, false, t))
			add_child(_art)
	# textes : lisibles sur téléphone (20 px au moins), même sur les cartes du récapitulatif (200 px de large)
	var fs := clampf(sz.x / 250.0, 0.8, 1.0)
	var title := UI.title(String(d[0]), int(32 * fs) if String(r["kind"]) == "tickets" else maxi(22, int(26 * fs)), UI.TEXT, col.darkened(0.5), HORIZONTAL_ALIGNMENT_CENTER)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # avant la taille : sinon la ligne entière l'élargit
	title.position = Vector2(6, sz.y * 0.52)
	title.size = Vector2(sz.x - 12, sz.y * 0.17)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("line_spacing", -6)
	add_child(title)
	var sub := UI.label(String(d[1]), UI.FS_SMALL, Color("#DCE5F0"), HORIZONTAL_ALIGNMENT_CENTER)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.position = Vector2(8, sz.y * 0.69)
	sub.size = Vector2(sz.x - 16, sz.y * 0.17)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.add_theme_constant_override("line_spacing", -4)
	add_child(sub)
	if not mini or sz.y > 150:
		var tg := UI.tag(String(d[2]), col, UI.INK, 18)
		tg.position = Vector2(sz.x * 0.5, sz.y * 0.88)
		add_child(tg)
		tg.resized.connect(func(): tg.position = Vector2((sz.x - tg.size.x) * 0.5, sz.y - tg.size.y - 10.0 * fs))
	if String(r["kind"]) in ["skin", "trail"]:
		var dup := bool(r.get("dup", false))
		var nt := UI.tag("DOUBLON" if dup else "NOUVEAU", UI.MUTED if dup else UI.ORANGE, UI.INK, 18)
		nt.position = Vector2(8, 8)
		nt.rotation = -0.08
		add_child(nt)
		if not dup and not mini:
			Fx.breathe(nt, 0.08, 0.8)

## Dos de la carte : liseré et lueur à la couleur de la rareté (on devine avant de voir), gros « ? ».
func add_back() -> void:
	back = Control.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.size = size
	back.draw.connect(func():
		var r := Rect2(Vector2.ZERO, back.size)
		var st := StyleBoxFlat.new()
		st.bg_color = Color("#101C3C")
		st.set_corner_radius_all(22)
		st.border_color = col
		st.set_border_width_all(6)
		st.anti_aliasing = true
		back.draw_style_box(st, r)
		var c := back.size * 0.5
		for k in range(6):
			back.draw_circle(c, back.size.x * (0.42 - k * 0.06), Color(col, 0.05 + 0.04 * k))
		var f: Font = UI.TITLE
		var fs := int(back.size.y * 0.32)
		var tw := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		back.draw_string_outline(f, c + Vector2(-tw * 0.5, fs * 0.36), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, UI.INK)
		back.draw_string(f, c + Vector2(-tw * 0.5, fs * 0.36), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lightened(0.4)))
	add_child(back)

## Retournement terminé : la face apparaît.
func show_face() -> void:
	if back != null:
		back.queue_free()
		back = null

func _process(dt: float) -> void:
	t += dt
	if _art != null:
		_art.queue_redraw()
	if _rays != null and tier >= 2:
		_rays.queue_redraw()

func _draw() -> void:
	var sz := size
	var r := Rect2(Vector2.ZERO, sz)
	# tranche sombre, face dégradée, liseré clair
	var edge := StyleBoxFlat.new()
	edge.bg_color = col.darkened(0.55)
	edge.set_corner_radius_all(22)
	edge.anti_aliasing = true
	edge.shadow_color = Color(0, 0, 0, 0.45)
	edge.shadow_size = 10
	edge.shadow_offset = Vector2(0, 6)
	draw_style_box(edge, Rect2(0, 0, sz.x, sz.y + 7))
	var face := StyleBoxFlat.new()
	face.bg_color = Color("#16254A").lerp(col, 0.18)
	face.set_corner_radius_all(22)
	face.border_color = col
	face.set_border_width_all(4)
	face.anti_aliasing = true
	draw_style_box(face, r)
	# fond du pictogramme : disque rayonnant à la couleur de la rareté
	var c := Vector2(sz.x * 0.5, sz.y * 0.3)
	for k in range(5):
		draw_circle(c, sz.x * (0.36 - k * 0.05), Color(col, 0.07 + 0.03 * k))
	# reflet en haut
	draw_rect(Rect2(14, 8, sz.x - 28, 3), Color(1, 1, 1, 0.25))

func _draw_rays() -> void:
	if tier < 2 or back != null:
		return
	var c := size * 0.5
	var n := 12
	var rr := size.y * 1.25
	for k in range(n):
		var a := TAU * k / n + t * (0.5 if tier == 3 else 0.3)
		var d1 := Vector2(cos(a - 0.08), sin(a - 0.08)) * rr
		var d2 := Vector2(cos(a + 0.08), sin(a + 0.08)) * rr
		_rays.draw_polygon(PackedVector2Array([c, c + d1, c + d2]), PackedColorArray([Color(col, 0.35), Color(col, 0.0), Color(col, 0.0)]))
