extends RefCounted
## Fabrique d'interface : boutons en relief, cartes, panneaux, étiquettes, tous construits en code, un seul style.
## Polices : Russo One pour les titres et les chiffres, Rajdhani pour le texte (SIL OFL).

const Icon = preload("res://scripts/icon.gd")

const BG := Color("#0E1B33")
const PANEL := Color("#16254A")
const PANEL_DARK := Color("#0B1529")
const LINE := Color("#2A3F6E")
const TEXT := Color("#F4F1EA")
const MUTED := Color("#9FB3C8")
const ACCENT := Color("#3CF2D8")
const ORANGE := Color("#FF7A2F")
const DANGER := Color("#F23CB8")
const GOLD := Color("#FFB347")
const INK := Color("#070C18")

static var TITLE: Font = null
static var BODY: Font = null

static func load_fonts() -> void:
	if TITLE != null:
		return
	TITLE = load("res://assets/fonts/RussoOne-Regular.ttf")
	BODY = load("res://assets/fonts/Rajdhani-Bold.ttf")
	ThemeDB.fallback_font = BODY

static func flat(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 14, border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border_w)
	s.border_color = border
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 10
	s.content_margin_bottom = 12
	s.anti_aliasing = true
	return s

## Style « en relief » : face colorée, tranche plus sombre en bas, ombre portée.
static func chunky(face: Color, edge: Color, pressed: bool = false, radius: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = face
	s.set_corner_radius_all(radius)
	s.border_color = edge
	s.border_width_bottom = 2 if pressed else 7
	s.border_width_left = 0
	s.border_width_right = 0
	s.border_width_top = 0
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 0 if pressed else 6
	s.shadow_offset = Vector2(0, 4)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 14 if pressed else 9
	s.content_margin_bottom = 9 if pressed else 14
	s.expand_margin_top = -3.0 if pressed else 0.0
	s.anti_aliasing = true
	return s

static func _style_button(b: Button, face: Color, edge: Color, text_col: Color, size: int, title_font: bool) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", TITLE if title_font else BODY)
	b.add_theme_font_size_override("font_size", size)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(st, text_col)
	b.add_theme_color_override("font_disabled_color", MUTED)
	b.add_theme_stylebox_override("normal", chunky(face, edge))
	b.add_theme_stylebox_override("hover", chunky(face.lightened(0.08), edge))
	b.add_theme_stylebox_override("pressed", chunky(face.darkened(0.08), edge, true))
	b.add_theme_stylebox_override("hover_pressed", chunky(face.darkened(0.08), edge, true))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", chunky(PANEL_DARK, INK))
	b.add_theme_constant_override("outline_size", 0)

static func button(text: String, size: int = 26, accent: Color = ACCENT, min_w: float = 0.0) -> Button:
	load_fonts()
	var b := Button.new()
	b.text = text
	_style_button(b, PANEL, accent.darkened(0.45), TEXT, size, false)
	# liseré d'accent en haut : on reconnaît la couleur du bouton
	var st: StyleBoxFlat = b.get_theme_stylebox("normal")
	st.border_width_top = 3
	st.border_color = accent.darkened(0.35)
	if min_w > 0:
		b.custom_minimum_size = Vector2(min_w, 0)
	return b

static func primary(text: String, size: int = 30, min_w: float = 0.0) -> Button:
	load_fonts()
	var b := Button.new()
	b.text = text
	_style_button(b, ORANGE, Color("#B4461A"), INK, size, true)
	if min_w > 0:
		b.custom_minimum_size = Vector2(min_w, 0)
	return b

static func label(text: String, size: int = 22, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	load_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", BODY)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

## Titre : Russo One, contour sombre et ombre colorée.
static func title(text: String, size: int = 44, color: Color = TEXT, glow: Color = ACCENT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	load_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", TITLE)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(4, size / 7))
	l.add_theme_color_override("font_shadow_color", Color(glow, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(3, size / 12))
	l.horizontal_alignment = align
	return l

static func panel(bg: Color = PANEL, border: Color = LINE, radius: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	var s := flat(bg, border, radius, 2)
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 22
	s.content_margin_bottom = 22
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 10
	p.add_theme_stylebox_override("panel", s)
	return p

## Pastille d'information (icône + texte), pour les compteurs du Relais.
static func chip(icon_kind: String, text: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := flat(Color(INK, 0.72), Color(col, 0.6), 22, 2)
	s.content_margin_left = 12
	s.content_margin_right = 16
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", s)
	var h := hbox(8)
	p.add_child(h)
	var ic := Icon.new(icon_kind, col, 26.0)
	h.add_child(ic)
	var l := label(text, 20, TEXT)
	h.add_child(l)
	return p

## Carte cliquable (pouvoir, portail, objet) : pictogramme, titre, texte. Les enfants laissent passer le clic.
static func card(icon_kind: String, title_text: String, body_text: String, accent: Color, size: Vector2 = Vector2(250, 290), badge: String = "") -> Button:
	load_fonts()
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = size
	var normal := chunky(PANEL, accent.darkened(0.5), false, 22)
	normal.border_width_top = 4
	normal.border_color = accent.darkened(0.2)
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = PANEL.lightened(0.06)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := chunky(PANEL.darkened(0.1), accent.darkened(0.5), true, 22)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var v := vbox(8)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 18
	v.offset_right = -18
	v.offset_top = 22
	v.offset_bottom = -20
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var disc := CenterContainer.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(disc)
	var ring := Panel.new()
	ring.custom_minimum_size = Vector2(104, 104)
	var rs := flat(Color(accent, 0.14), Color(accent, 0.8), 52, 3)
	ring.add_theme_stylebox_override("panel", rs)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(ring)
	var ic := Icon.new(icon_kind, accent, 64.0)
	ic.position = Vector2(20, 20)
	ring.add_child(ic)
	if badge != "":
		var bl := title(badge, 20, INK, accent)
		bl.add_theme_constant_override("outline_size", 0)
		bl.add_theme_constant_override("shadow_offset_y", 0)
		var bp := PanelContainer.new()
		var bs := flat(accent, accent, 12, 0)
		bs.content_margin_left = 8
		bs.content_margin_right = 8
		bs.content_margin_top = 0
		bs.content_margin_bottom = 2
		bp.add_theme_stylebox_override("panel", bs)
		bp.add_child(bl)
		bp.position = Vector2(70, 72)
		bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.add_child(bp)
	var t := title(title_text, 24, TEXT, accent, HORIZONTAL_ALIGNMENT_CENTER)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var d := label(body_text, 19, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	return b

## Tuile compacte cliquable : pictogramme à gauche, titre et texte à droite (arsenal, inventaire, Loge).
static func tile(icon_kind: String, title_text: String, body_text: String, accent: Color, selected: bool = false, h: float = 92.0) -> Button:
	load_fonts()
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	var face := PANEL.lightened(0.05) if selected else Color(PANEL, 0.92)
	var normal := chunky(face, accent.darkened(0.45) if selected else INK, false, 16)
	normal.border_width_left = 5 if selected else 0
	normal.border_color = accent if selected else INK
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = face.lightened(0.06)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := chunky(face.darkened(0.1), INK, true, 16)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", normal)
	var hb := hbox(14)
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 16
	hb.offset_right = -12
	hb.offset_top = 8
	hb.offset_bottom = -12
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var ring := Panel.new()
	var rs := h * 0.62
	ring.custom_minimum_size = Vector2(rs, rs)
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ring.add_theme_stylebox_override("panel", flat(Color(accent, 0.16 if selected else 0.08), Color(accent, 0.9 if selected else 0.4), int(rs * 0.5), 2))
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ring)
	var ic := Icon.new(icon_kind, accent if selected else Color(accent, 0.7), rs * 0.62)
	ic.position = Vector2(rs * 0.19, rs * 0.19)
	ring.add_child(ic)
	var v := vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(v)
	var t := title(title_text, 20, TEXT if selected else MUTED, accent)
	t.add_theme_constant_override("shadow_offset_y", 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	if body_text != "":
		var d := label(body_text, 17, MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(d)
	return b

## Fond plein écran semi-opaque (overlays de choix, pause, fin de partie).
static func dim(alpha: float = 0.72) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(INK.r, INK.g, INK.b, alpha)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c

static func vbox(gap: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v

static func hbox(gap: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h

static func center(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(child)
	return c

## Apparition d'un nœud d'interface : grossit depuis 85 % et s'éclaircit (fonctionne pendant la pause).
static func pop_in(n: Control, delay: float = 0.0) -> void:
	n.modulate.a = 0.0
	n.pivot_offset = n.custom_minimum_size * 0.5
	n.scale = Vector2(0.85, 0.85)
	var tw := n.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(n, "modulate:a", 1.0, 0.18)
	tw.tween_property(n, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
