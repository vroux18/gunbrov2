extends Button
## Carte à jouer (pouvoir, objet trouvé) : distribuée en éventail face cachée, se retourne, rebondit.
## La rareté se lit à la couleur (bordure, bandeau, halo), à la lueur qui pulse et aux étincelles qui montent.
## Carte de pouvoir (`setup_power`) : couleur et pictogramme de sa branche, palier (éclat qui monte avec lui),
## niveau en chiffres romains ; carte d'évolution : légendaire dorée, ruban ÉVOLUTION, recette, liseré qui court.
## Tout est dessiné en code (styleboxes, polygones, quelques labels) ; aucune particule 2D, aucun nœud par frame.

const UI = preload("res://scripts/ui.gd")
const Icon = preload("res://scripts/icon.gd")
const Fx = preload("res://scripts/ui/fx.gd")

## Couleurs de rareté : mêmes que les objets (data.gd), du commun au culte.
const TIER_COLORS := [Color("#9FB3C8"), Color("#3CF2D8"), Color("#C77DFF"), Color("#FFB347")]
const POWER_TIER_NAMES := ["COMMUN", "RARE", "ÉPIQUE", "LÉGENDAIRE"]
const Data = preload("res://scripts/data.gd")
const SPARKS := [0, 7, 12, 18]

var tier := 0
var accent := Color.WHITE
var face_up := false
var face: Control
var back: Control
var _halo: TextureRect
var _sparks: Control
var _flash: Panel
var _t := 0.0
var _burst := 0.0  # 1 au retournement, décroît
var _name_label: Label
var evo := false  # carte d'évolution : liseré doré qui court autour

## Carte de pouvoir : `p` est une entrée de Data.POWERS (ou Data.EVOLUTIONS si `is_evo`), `level` le niveau
## qu'elle donne.
func setup_power(p: Dictionary, level: int, is_evo: bool, card_size: Vector2) -> void:
	if is_evo:
		evo = true
		var need: Array = p["need"]
		var recipe := "%s + %s" % [Data.power(String(need[0]))["name"], Data.power(String(need[1]))["name"]]
		setup(String(p["icon"]), String(p["name"]), String(p["desc"]), 3, "LÉGENDAIRE", "", card_size, Data.EVO_COL, {"recipe": recipe, "branch_icon": "star"})
		return
	var br := Data.branch(String(p["b"]))
	var palier := int(p["tier"])
	var info := {"branch_icon": String(br["icon"]), "pips": palier}
	setup(String(p["id"]), String(p["name"]), Data.power_text(p, level), palier - 1,
		"%s · PALIER %s" % [String(br["name"]).to_upper(), Data.roman(palier)],
		"NIV. " + Data.roman(level), card_size, br["col"], info)

func setup(icon_kind: String, title_text: String, body_text: String, tier_i: int, tier_name: String, badge: String = "", card_size: Vector2 = Vector2(264, 356), col: Color = Color(0, 0, 0, 0), info: Dictionary = {}) -> void:
	UI.load_fonts()
	tier = clampi(tier_i, 0, 3)
	accent = TIER_COLORS[tier] if col.a == 0.0 else col
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = card_size
	size = card_size
	pivot_offset = card_size * 0.5
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, empty)
	# halo derrière la carte (rare et plus)
	_halo = Fx.halo(Color(accent, 0.0), card_size * Vector2(1.9, 1.6))
	_halo.position = (card_size - _halo.size) * 0.5
	_halo.show_behind_parent = true
	add_child(_halo)
	back = _build_back(card_size)
	add_child(back)
	face = _build_face(card_size, icon_kind, title_text, body_text, tier_name, badge, info)
	face.visible = false
	add_child(face)
	_flash = Panel.new()
	_flash.size = card_size
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.add_theme_stylebox_override("panel", UI.flat(Color(1, 1, 1, 1), Color(0, 0, 0, 0), 22, 0))
	_flash.modulate.a = 0.0
	add_child(_flash)
	_sparks = Control.new()
	_sparks.size = card_size
	_sparks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sparks.material = add
	_sparks.draw.connect(_draw_sparks)
	add_child(_sparks)
	Fx.press(self, 0.95)

func _process(dt: float) -> void:
	_t += dt
	_burst = maxf(0.0, _burst - dt * 2.4)
	if face_up or _burst > 0.0:
		_sparks.queue_redraw()
	if face_up and tier > 0:
		(face.get_meta("art") as Control).queue_redraw()

# ---------------------------------------------------------------- construction
func _build_back(sz: Vector2) -> Control:
	var c := Control.new()
	c.size = sz
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := Panel.new()
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := UI.chunky(Color("#1B2C57"), Color("#0A1430"), false, 22)
	s.border_width_top = 4
	s.border_width_left = 4
	s.border_width_right = 4
	s.border_color = Color("#2E4A86")
	p.add_theme_stylebox_override("panel", s)
	c.add_child(p)
	var deco := Control.new()
	deco.size = sz
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(func():
		var ctr := sz * 0.5 - Vector2(0, 4)
		# losanges en filigrane
		for i in range(-3, 4):
			for j in range(-4, 5):
				var p0 := ctr + Vector2(i * 46 + (j % 2) * 23, j * 40)
				if absf(p0.x - ctr.x) > sz.x * 0.5 - 22 or absf(p0.y - ctr.y) > sz.y * 0.5 - 26:
					continue
				deco.draw_colored_polygon(PackedVector2Array([p0 + Vector2(0, -7), p0 + Vector2(6, 0), p0 + Vector2(0, 7), p0 + Vector2(-6, 0)]), Color(0.3, 0.5, 0.9, 0.12))
		deco.draw_circle(ctr, 74, Color("#0E1B3A"))
		deco.draw_arc(ctr, 74, 0, TAU, 48, Color(UI.ACCENT, 0.55), 5.0, true)
		deco.draw_arc(ctr, 50, 0, TAU, 40, Color(UI.ACCENT, 0.35), 3.0, true)
		deco.draw_arc(ctr, 26, 0, TAU, 32, Color(UI.ORANGE, 0.8), 6.0, true)
		deco.draw_string(UI.TITLE, Vector2(0, sz.y - 30), "PASSEURS", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 18, Color(UI.ACCENT, 0.5)))
	c.add_child(deco)
	return c

func _build_face(sz: Vector2, icon_kind: String, title_text: String, body_text: String, tier_name: String, badge: String, info: Dictionary = {}) -> Control:
	var c := Control.new()
	c.size = sz
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := Panel.new()
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := UI.chunky(Color("#15234A"), accent.darkened(0.55), false, 22)
	s.border_width_top = 4
	s.border_width_left = 4
	s.border_width_right = 4
	s.border_width_bottom = 9
	s.border_color = accent.darkened(0.15) if tier > 0 or not info.is_empty() else Color("#4A5E86")
	p.add_theme_stylebox_override("panel", s)
	c.add_child(p)
	var art_h := sz.y * 0.47
	var art := Control.new()
	art.size = sz
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(func():
		# zone d'illustration : dégradé de la couleur de rareté, rayons qui tournent lentement
		var top := Color(accent.darkened(0.35), 0.95)
		var bot := Color(accent.darkened(0.75), 0.0)
		var x0 := 4.0
		var x1 := sz.x - 4.0
		art.draw_polygon(PackedVector2Array([Vector2(x0 + 10, 4), Vector2(x1 - 10, 4), Vector2(x1, 18), Vector2(x1, art_h), Vector2(x0, art_h), Vector2(x0, 18)]),
			PackedColorArray([top, top, top, bot, bot, top]))
		var ctr := Vector2(sz.x * 0.5, art_h * 0.56)
		if tier > 0:
			for k in range(12):
				var a := TAU * k / 12.0 + _t * 0.25
				var d1 := Vector2(cos(a - 0.09), sin(a - 0.09)) * 140.0
				var d2 := Vector2(cos(a + 0.09), sin(a + 0.09)) * 140.0
				var pts := PackedVector2Array([ctr, ctr + d1, ctr + d2])
				for i in range(pts.size()):
					pts[i] = Vector2(clampf(pts[i].x, x0, x1), clampf(pts[i].y, 6.0, art_h))
				art.draw_colored_polygon(pts, Color(accent.lightened(0.3), 0.08 + 0.03 * tier))
		art.draw_circle(ctr, 64, Color(UI.INK, 0.55))
		art.draw_circle(ctr, 58, accent.darkened(0.6))
		art.draw_arc(ctr, 58, 0, TAU, 48, accent, 5.0, true)
		art.draw_arc(ctr, 46, -2.4, -0.9, 16, Color(1, 1, 1, 0.35), 4.0, true))
	c.add_child(art)
	c.set_meta("art", art)
	var ic := Icon.new(icon_kind, accent.lightened(0.25), 78.0)
	ic.position = Vector2(sz.x * 0.5 - 39, art_h * 0.56 - 39)
	c.add_child(ic)
	if badge != "":
		var bt := UI.tag(badge, UI.ORANGE if info.is_empty() else accent.lightened(0.1), UI.INK, 18)
		c.add_child(bt)
		bt.reset_size()
		bt.position = Vector2(sz.x - bt.size.x - 14, 14)
	if info.has("branch_icon"):
		# pastille de la branche (coin haut gauche) et pips du palier dessous
		var chip := Panel.new()
		chip.size = Vector2(44, 44)
		chip.position = Vector2(12, 12)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_stylebox_override("panel", UI.flat(Color(UI.INK, 0.75), accent, 22, 3))
		c.add_child(chip)
		var bi := Icon.new(String(info["branch_icon"]), accent.lightened(0.2), 30.0)
		bi.position = Vector2(7, 7)
		chip.add_child(bi)
		var pips := int(info.get("pips", 0))
		if pips > 0:
			var pp := Control.new()
			pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pp.position = Vector2(12, 60)
			pp.size = Vector2(44, 12)
			pp.draw.connect(func():
				for k in range(3):
					var q := Vector2(8 + k * 14, 6)
					var on := k < pips
					pp.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -6), q + Vector2(5, 0), q + Vector2(0, 6), q + Vector2(-5, 0)]), accent.lightened(0.2) if on else Color(1, 1, 1, 0.18)))
			c.add_child(pp)
	if evo:
		# ruban ÉVOLUTION en travers du haut de la carte
		var rib := UI.tag("ÉVOLUTION", accent, UI.INK, 20)
		c.add_child(rib)
		rib.reset_size()
		rib.position = Vector2((sz.x - rib.size.x) * 0.5, -14)
	var name_l := UI.title(title_text, 27 if title_text.length() < 17 else 23, UI.TEXT, accent, HORIZONTAL_ALIGNMENT_CENTER)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size = Vector2(sz.x - 24, 0)
	name_l.position = Vector2(12, art_h + 6)
	name_l.size = Vector2(sz.x - 24, 40)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(name_l)
	_name_label = name_l
	if tier >= 2:
		Fx.shine(name_l, sz.x, 2.2 if tier == 3 else 3.2, 0.7)
	if info.has("recipe"):
		body_text += "\n" + String(info["recipe"])
	var d := UI.label(body_text, 21 if body_text.length() < 70 else 19, Color("#C4D2E4"), HORIZONTAL_ALIGNMENT_CENTER)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(sz.x - 36, 0)
	d.position = Vector2(18, art_h + 50)
	d.size = Vector2(sz.x - 36, sz.y - art_h - 100)
	d.add_theme_constant_override("line_spacing", -3)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(d)
	if tier_name != "":
		var rt := UI.tag(tier_name, accent, UI.INK, 17)
		c.add_child(rt)
		rt.reset_size()
		rt.position = Vector2((sz.x - rt.size.x) * 0.5, sz.y - 46)
		c.set_meta("tier_tag", rt)
	return c

# ---------------------------------------------------------------- animations
## Arrivée : part de `from` (bas de l'écran), file vers `to` en tournant jusqu'à `rot` (éventail).
func deal(from: Vector2, to: Vector2, rot: float, delay: float) -> void:
	position = from
	rotation = 0.0
	scale = Vector2.ONE * 0.55
	modulate.a = 0.0
	var tw := Fx._tw(self)
	tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.12)
	tw.tween_property(self, "position", to, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation", rot, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Retournement : la carte s'écrase sur sa tranche, montre sa face, rebondit ; éclair et gerbe d'étincelles.
func reveal(delay: float) -> void:
	var tw := Fx._tw(self)
	tw.tween_interval(delay)
	tw.tween_property(self, "scale", Vector2(0.0, 1.06), 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		back.visible = false
		face.visible = true
		face_up = true
		_burst = 1.0
		_flash.modulate.a = 0.85)
	tw.tween_property(self, "scale", Vector2(1.12, 1.12), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tf := Fx._tw(_flash)
	tf.tween_interval(delay + 0.11)
	tf.tween_property(_flash, "modulate:a", 0.0, 0.35).set_delay(0.02)
	if tier > 0:
		var th := Fx._tw(_halo)
		th.tween_interval(delay + 0.11)
		th.tween_property(_halo, "modulate:a", 0.5 + 0.12 * tier, 0.2)
		th.tween_callback(func(): Fx.pulse(_halo, 0.28 + 0.08 * tier, 0.55 + 0.12 * tier, 1.3))

## Montre la face tout de suite (sans retournement).
func show_face() -> void:
	back.visible = false
	face.visible = true
	face_up = true
	if tier > 0:
		_halo.modulate.a = 0.45
		Fx.pulse(_halo, 0.28 + 0.08 * tier, 0.55 + 0.12 * tier, 1.3)

## Carte choisie : se redresse, grossit vers `center`, éclair.
func pick(center: Vector2) -> void:
	z_index = 2
	if not face_up:
		back.visible = false
		face.visible = true
		face_up = true
	_burst = 1.0
	_flash.modulate.a = 0.9
	var tw := Fx._tw(self)
	tw.set_parallel(true)
	tw.tween_property(self, "rotation", 0.0, 0.2)
	tw.tween_property(self, "position", center - size * 0.5, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE * 1.18, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_flash, "modulate:a", 0.0, 0.3)
	tw.chain().tween_property(self, "scale", Vector2.ONE * 1.3, 0.16)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.16)

## Carte écartée : tombe en tournant et s'efface.
func discard(side: float) -> void:
	var tw := Fx._tw(self)
	tw.set_parallel(true)
	tw.tween_property(self, "position", position + Vector2(side * 120.0, 520.0), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "rotation", rotation + side * 0.6, 0.4)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)

# ---------------------------------------------------------------- étincelles (une seule passe de dessin)
## Point du bord de la carte (rectangle) à la fraction `u` du tour.
static func _perimeter(sz: Vector2, u: float) -> Vector2:
	var w := sz.x - 8.0
	var h := sz.y - 8.0
	var d := u * 2.0 * (w + h)
	if d < w:
		return Vector2(4.0 + d, 4.0)
	d -= w
	if d < h:
		return Vector2(4.0 + w, 4.0 + d)
	d -= h
	if d < w:
		return Vector2(4.0 + w - d, 4.0 + h)
	d -= w
	return Vector2(4.0, 4.0 + h - d)

static func _star(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.22, 0), p + Vector2(0, r), p + Vector2(-r * 0.22, 0)]), col)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-r, 0), p + Vector2(0, r * 0.22), p + Vector2(r, 0), p + Vector2(0, -r * 0.22)]), col)

func _draw_sparks() -> void:
	var sz := _sparks.size
	var n: int = SPARKS[tier]
	if evo and face_up:
		# liseré qui court autour de la carte : deux comètes dorées sur le bord
		for k in range(2):
			var u := fmod(_t * 0.32 + k * 0.5, 1.0)
			for j in range(10):
				var uu := fmod(u - j * 0.008 + 1.0, 1.0)
				var q := _perimeter(sz, uu)
				_sparks.draw_circle(q, 7.0 - j * 0.55, Color(accent.lightened(0.5), (1.0 - j / 10.0) * 0.9))
	if face_up:
		for i in range(n):
			var h := fmod(float(i) * 0.6180339 + 0.13, 1.0)
			var life := fmod(_t * (0.35 + 0.1 * h) + h * 3.7, 1.0)
			var side := -1.0 if i % 2 == 0 else 1.0
			var x := sz.x * 0.5 + side * (sz.x * 0.36 + 26.0 * h) + sin(_t * 2.0 + i) * 8.0
			var y := sz.y * (1.0 - life * 1.25) + 30.0
			var a := sin(life * PI)
			var r := (5.0 + 6.0 * h) * (0.6 + 0.4 * a)
			_star(_sparks, Vector2(x, y), r, Color(accent.lightened(0.4), 0.85 * a))
	if _burst > 0.0:
		var ctr := sz * 0.5
		var k := 1.0 - _burst
		var m := 6 + 5 * tier
		for i in range(m):
			var ang := TAU * i / m + 0.3
			var p := ctr + Vector2(cos(ang), sin(ang) * 1.3) * (sz.x * 0.45 + k * (150.0 + 30.0 * tier))
			_star(_sparks, p, 12.0 * _burst + 2.0, Color(accent.lightened(0.5), _burst))
		if _burst > 0.45:
			var rk := (1.0 - _burst) / 0.55
			_sparks.draw_arc(ctr, sz.y * 0.5 + rk * 120.0, 0.0, TAU, 48, Color(accent.lightened(0.3), (1.0 - rk) * 0.6), 5.0 * (1.0 - rk) + 1.0, true)
