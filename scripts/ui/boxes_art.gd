extends RefCounted
## Dessins 2D des box et de la collection (en code, comme scripts/icon.gd) : petite box de butin aux couleurs
## de sa rareté (récapitulatif de fin, pastilles), buste de Jo dans une apparence (verrouillée : silhouette),
## traînée de tir animée.

const UI = preload("res://scripts/ui.gd")
const Loot = preload("res://scripts/loot.gd")

## Couleurs des box sculptées (tools/chars/box_loot.py) : corps, ombre du corps, sangles, lumière.
const BOX_ART := {
	"bronze": [Color("#C98446"), Color("#A9652E"), Color("#6A4126"), Color("#FFB45E")],
	"argent": [Color("#DCE6F2"), Color("#B6C4D8"), Color("#4A6290"), Color("#5CF0FF")],
	"or": [Color("#FFC63D"), Color("#F0A21E"), Color("#C2561A"), Color("#FFF2A0")],
	"legendaire": [Color("#8A52F0"), Color("#6A36CC"), Color("#FFC23D"), Color("#FF8AF2")],
}
const HAIR := Color("#1C2456")
const SKIN := Color("#F5BE98")
const SHADOW := Color("#0B1529")

static func _rr(ci: CanvasItem, r: Rect2, col: Color, rad: float, border: Color = Color(0, 0, 0, 0), bw: float = 0.0) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(int(rad))
	s.anti_aliasing = true
	if bw > 0.0:
		s.border_color = border
		s.set_border_width_all(int(bw))
	ci.draw_style_box(s, r)

## Petite box de butin vue de trois quarts face : caisse, couvercle bombé, sangles, voyant.
static func draw_box(ci: CanvasItem, c: Vector2, w: float, rarity: String, dim: bool = false) -> void:
	var a: Array = BOX_ART.get(rarity, BOX_ART["or"])
	var body: Color = a[0]
	var body_d: Color = a[1]
	var band: Color = a[2]
	var glow: Color = a[3]
	if dim:
		body = body.darkened(0.6)
		body_d = body_d.darkened(0.6)
		band = band.darkened(0.6)
		glow = glow.darkened(0.5)
	var h := w * 0.8
	var x0 := c.x - w * 0.5
	var y0 := c.y - h * 0.5
	var ol := maxf(2.0, w * 0.05)
	# contour sombre, caisse, couvercle en tonneau
	var lid_o := PackedVector2Array()
	var lid := PackedVector2Array()
	for k in range(17):
		var t := PI + PI * k / 16.0
		lid_o.append(Vector2(c.x + cos(t) * (w * 0.5 + ol), y0 + h * 0.4 + sin(t) * (h * 0.3 + ol)))
		lid.append(Vector2(c.x + cos(t) * w * 0.5, y0 + h * 0.4 + sin(t) * h * 0.3))
	ci.draw_colored_polygon(lid_o, UI.INK)
	_rr(ci, Rect2(x0 - ol, y0 + h * 0.36 - ol, w + ol * 2, h * 0.64 + ol * 2), UI.INK, w * 0.16)
	_rr(ci, Rect2(x0, y0 + h * 0.36, w, h * 0.64), body_d, w * 0.14)
	_rr(ci, Rect2(x0, y0 + h * 0.36, w, h * 0.46), body, w * 0.14)
	ci.draw_colored_polygon(lid, body)
	# sangles
	for sx in [-1.0, 1.0]:
		var bx: float = c.x + sx * w * 0.27
		ci.draw_rect(Rect2(bx - w * 0.07, y0 + h * 0.14, w * 0.14, h * 0.86), band)
	ci.draw_rect(Rect2(x0, y0 + h * 0.36, w, h * 0.07), band)
	# serrure et voyant
	_rr(ci, Rect2(c.x - w * 0.12, y0 + h * 0.3, w * 0.24, h * 0.24), band.darkened(0.45), w * 0.05)
	_rr(ci, Rect2(c.x - w * 0.045, y0 + h * 0.35, w * 0.09, h * 0.12), glow, w * 0.03)
	# reflet du couvercle
	ci.draw_line(Vector2(c.x - w * 0.42, y0 + h * 0.3), Vector2(c.x - w * 0.36, y0 + h * 0.2), Color(1, 1, 1, 0.5 if not dim else 0.1), maxf(1.5, w * 0.045), true)

## Buste de Jo dans une apparence (verrouillée : silhouette sombre et point d'interrogation).
static func draw_skin(ci: CanvasItem, r: Rect2, sk: Dictionary, locked: bool, t: float = 0.0) -> void:
	var s := minf(r.size.x, r.size.y)
	var o := r.position + (r.size - Vector2(s, s)) * 0.5
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var suit: Color = sk["suit"]
	var acc: Color = sk["accent"]
	var lit: Color = sk["light"]
	if bool(sk.get("rainbow", false)):
		lit = Color.from_hsv(fmod(t * 0.25, 1.0), 0.7, 1.0)
	var hair := HAIR
	var skin_c := SKIN
	var ink := UI.INK
	if locked:
		suit = SHADOW
		acc = SHADOW
		lit = SHADOW
		hair = SHADOW
		skin_c = SHADOW
		ink = UI.LINE
	var ow := s * 0.03
	# torse et épaulières
	_rr(ci, Rect2(P.call(0.26, 0.6) - Vector2(ow, ow), Vector2(0.48 * s + ow * 2, 0.42 * s)), ink, s * 0.14)
	for x in [0.26, 0.74]:
		ci.draw_circle(P.call(x, 0.68), s * 0.1 + ow, ink)
	_rr(ci, Rect2(P.call(0.26, 0.6), Vector2(0.48 * s, 0.4 * s)), suit, s * 0.13)
	_rr(ci, Rect2(P.call(0.39, 0.7), Vector2(0.22 * s, 0.13 * s)), acc, s * 0.04)
	_rr(ci, Rect2(P.call(0.45, 0.725), Vector2(0.1 * s, 0.03 * s)), lit, s * 0.01)
	for x in [0.26, 0.74]:
		ci.draw_circle(P.call(x, 0.68), s * 0.1, acc)
	# tête : cheveux, visage, frange
	ci.draw_circle(P.call(0.5, 0.38), s * 0.255 + ow, ink)
	ci.draw_circle(P.call(0.5, 0.38), s * 0.255, hair)
	ci.draw_circle(P.call(0.5, 0.45), s * 0.185, skin_c)
	var fringe := PackedVector2Array()
	for k in range(13):
		var a := PI * 1.02 + PI * 0.96 * k / 12.0
		fringe.append(P.call(0.5, 0.42) + Vector2(cos(a), sin(a) * 0.72) * s * 0.215)
	fringe.append(P.call(0.62, 0.39))
	fringe.append(P.call(0.38, 0.38))
	ci.draw_colored_polygon(fringe, hair)
	if not locked:
		ci.draw_circle(P.call(0.43, 0.47), s * 0.03, Color("#141828"))
		ci.draw_circle(P.call(0.57, 0.47), s * 0.03, Color("#141828"))
		ci.draw_circle(P.call(0.44, 0.46), s * 0.01, Color.WHITE)
		ci.draw_circle(P.call(0.58, 0.46), s * 0.01, Color.WHITE)
	# mèche lumineuse et lunettes relevées
	ci.draw_arc(P.call(0.5, 0.38), s * 0.2, PI * 1.55, PI * 1.95, 10, lit, s * 0.045, true)
	for x in [0.41, 0.59]:
		ci.draw_circle(P.call(x, 0.2), s * 0.065, acc)
		ci.draw_circle(P.call(x, 0.2), s * 0.04, lit)
	if locked:
		var f: Font = UI.TITLE
		var fs := int(s * 0.36)
		var tw := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(f, P.call(0.5, 0.56) - Vector2(tw * 0.5, -fs * 0.35), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.MUTED)

## Traînée de tir : trois projectiles qui filent à gauche vers la droite avec leur traînée.
static func draw_trail(ci: CanvasItem, r: Rect2, tr: Dictionary, locked: bool, t: float) -> void:
	var n := 3
	for k in range(n):
		var ph := fmod(t * 0.8 + k / float(n), 1.0)
		var y := r.position.y + r.size.y * (0.3 + 0.2 * k)
		var hx := r.position.x + r.size.x * (0.1 + 0.85 * ph)
		var col := Loot.trail_color(String(tr["id"]), k + int(t * 4.0)) if not locked else UI.LINE
		var ln := r.size.x * 0.42
		var w := r.size.y * 0.075
		var a := clampf(minf(ph, 1.0 - ph) * 8.0, 0.0, 1.0)
		var seg := 8
		for i in range(seg):
			var u0 := float(i) / seg
			var u1 := float(i + 1) / seg
			var x0 := hx - ln * (1.0 - u0)
			var x1 := hx - ln * (1.0 - u1)
			ci.draw_line(Vector2(maxf(x0, r.position.x), y), Vector2(maxf(x1, r.position.x), y), Color(col, a * u1 * 0.8), w * (0.3 + 0.7 * u1), true)
		ci.draw_circle(Vector2(hx, y), w * 1.1, Color(col, a))
		ci.draw_circle(Vector2(hx, y), w * 0.55, Color(1, 1, 1, a * (0.9 if not locked else 0.2)))
