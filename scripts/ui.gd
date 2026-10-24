extends RefCounted
## Fabrique d'interface : boutons en relief, cartes, panneaux, étiquettes, tous construits en code, un seul style.
## Polices : Russo One pour les titres et les chiffres, Rajdhani pour le texte (SIL OFL).
##
## ---------------------------------------------------------------- écrans du Relais : règles communes
## Vue de base 1280 × 720 (largeur 1280 à 1600 selon le téléphone). Sur un écran de 6,5 pouces, 720 px font
## environ 6,5 cm : un texte de 20 px fait à peine 2 mm. D'où les tailles minimales ci-dessous (en px de la vue) :
##   FS_SCREEN_TITLE (44) titre d'écran · FS_BODY (24) texte courant · FS_SMALL (20) texte secondaire, le plus
##   petit autorisé, chiffres compris · TOUCH_H (72) hauteur minimale d'une cible tactile.
## Texte important en TEXT (jamais en MUTED) sur fond sombre opaque.
##
## Bandeau commun : UI.screen_header(vp, titre, phrase, accent, on_back, tickets, éclats) -> Control
##   Même bandeau en haut de tous les écrans du Relais (ÉQUIPEMENT, POUVOIRS, TALENTS, COFFRES, APPARENCES) :
##   - fond sombre presque opaque sur toute la largeur, filet de la couleur `accent` en bas ;
##   - à gauche, RETOUR (bouton orange, 30 px, 200 × 76, flèche) : appelle `on_back` (en général main.show_base) ;
##     le texte reste exactement « RETOUR » (le robot de test, scripts/bot.gd, le cherche par son texte) ;
##   - au milieu, le titre (44 px, Russo One) et dessous une phrase de 24 px qui dit ce qu'on fait ici ;
##   - à droite, les monnaies : tickets (pièce dorée) et éclats du Cœur à dépenser (cristal turquoise), 26 px.
##   Conventions des valeurs : tickets = profile["tickets"] ; éclats = Talents.shards_free(profile)
##   (UI.header_money(profile) les calcule). Le nœud rendu est ancré en haut, pleine largeur ; il tient compte
##   des marges de sécurité (encoche). Sa hauteur : UI.header_height(vp) ; le contenu de l'écran commence dessous.
##   Exemple :
##       var m := UI.header_money(main.profile)
##       add_child(UI.screen_header(get_viewport(), "TALENTS", "Améliorations permanentes…", UI.GOLD,
##           main.show_base, m[0], m[1]))
##       var top := UI.header_height(get_viewport()) + 12.0
##   Les étiquettes des monnaies sont en meta "tickets_label" et "shards_label" (pour les mettre à jour après un
##   achat sans reconstruire le bandeau : UI.header_set_money(header, tickets, éclats)).
## Listes qui défilent : UI.scroll() (défilement au doigt branché, scripts/ui/touch_scroll.gd).

const Icon = preload("res://scripts/icon.gd")
const Fx = preload("res://scripts/ui/fx.gd")
const TouchScroll = preload("res://scripts/ui/touch_scroll.gd")

const FS_SCREEN_TITLE := 44
const FS_BODY := 24
const FS_SMALL := 20
const TOUCH_H := 72.0
const GOOD := Color("#5DFF9B")  # gain (comparaison d'objets)
const BAD := Color("#FF5C6E")  # perte
const SOFT := Color("#C9D6E8")  # texte secondaire lisible (plus clair que MUTED)

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
	Fx.press(b)

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
	p.set_meta("label", l)
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
	Fx.press(b, 0.95)
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
	var t := title(title_text, 21, TEXT if selected else MUTED, accent)
	t.add_theme_constant_override("shadow_offset_y", 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	if body_text != "":
		var d := label(body_text, 19, MUTED)
		d.add_theme_constant_override("line_spacing", -3)
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

## Marges de sécurité (encoches, coins arrondis, barre de gestes), en unités du viewport.
## Sur téléphone : zone sûre du système ; partout : un minimum, plus large sur les écrans très allongés
## (20:9 et plus), où l'encoche peut se trouver d'un côté comme de l'autre en paysage.
static func safe_insets(vp: Viewport) -> Dictionary:
	var vs := vp.get_visible_rect().size
	var side := 24.0
	if vs.x / maxf(1.0, vs.y) > 1.95:
		side = 56.0
	var out := {"left": side, "right": side, "top": 14.0, "bottom": 12.0}
	if OS.has_feature("mobile"):
		var scr := Vector2(DisplayServer.screen_get_size())
		var safe := DisplayServer.get_display_safe_area()
		if scr.x > 0.0 and safe.size.x > 0:
			var k := vs.x / scr.x
			out["left"] = maxf(out["left"], safe.position.x * k + 8.0)
			out["right"] = maxf(out["right"], (scr.x - safe.end.x) * k + 8.0)
			out["top"] = maxf(out["top"], safe.position.y * k + 6.0)
			out["bottom"] = maxf(out["bottom"], (scr.y - safe.end.y) * k + 6.0)
	return out

## Petite étiquette pleine (« RARE », « NIV. 2 », « NOUVEL ENNEMI »).
static func tag(text: String, bg: Color, fg: Color = INK, size: int = 18) -> PanelContainer:
	load_fonts()
	var p := PanelContainer.new()
	var s := flat(bg, bg, 10, 0)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 1
	s.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", s)
	var l := title(text, size, fg, bg)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

# ---------------------------------------------------------------- écrans du Relais (voir l'en-tête du fichier)
## Hauteur du bandeau commun (marge de sécurité du haut comprise).
static func header_height(vp: Viewport) -> float:
	return float(safe_insets(vp)["top"]) + 100.0

## Monnaies affichées dans le bandeau : [tickets, éclats du Cœur à dépenser].
static func header_money(profile: Dictionary) -> Array:
	var talents = load("res://scripts/talents.gd")
	return [int(profile.get("tickets", 0)), int(talents.shards_free(profile))]

## Bandeau commun des écrans du Relais : RETOUR, titre et phrase d'explication, monnaies.
static func screen_header(vp: Viewport, title_text: String, sentence: String, accent: Color, on_back: Callable, tickets: int, shards: int) -> Control:
	load_fonts()
	var ins := safe_insets(vp)
	var hh := header_height(vp)
	var root := Control.new()
	root.anchor_left = 0.0
	root.anchor_right = 1.0
	root.offset_bottom = hh
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(PANEL_DARK, 0.95)
	st.border_color = Color(accent, 0.7)
	st.border_width_bottom = 3
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.shadow_size = 14
	st.shadow_offset = Vector2(0, 4)
	bg.add_theme_stylebox_override("panel", st)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)
	var row := hbox(22)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = float(ins["left"]) + 8.0
	row.offset_right = -float(ins["right"]) - 8.0
	row.offset_top = float(ins["top"]) + 2.0
	row.offset_bottom = -10.0
	root.add_child(row)
	# RETOUR : gros, orange, flèche vers la gauche
	var back := primary("RETOUR", 30)
	back.custom_minimum_size = Vector2(206, 76)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for stn in ["normal", "hover", "pressed", "hover_pressed"]:
		var bs: StyleBoxFlat = back.get_theme_stylebox(stn)
		bs.content_margin_left = 58
		bs.content_margin_right = 22
	var arrow := Icon.new("play", INK, 30.0)
	arrow.anchor_top = 0.5
	arrow.anchor_bottom = 0.5
	arrow.offset_left = 20
	arrow.offset_top = -19
	arrow.offset_right = 50
	arrow.offset_bottom = 11
	arrow.pivot_offset = Vector2(15, 15)
	arrow.scale = Vector2(-1, 1)
	back.add_child(arrow)
	back.pressed.connect(on_back)
	row.add_child(back)
	root.set_meta("back", back)
	# titre et phrase
	var tv := vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tv)
	var t := title(title_text, FS_SCREEN_TITLE, TEXT, accent)
	t.add_theme_constant_override("shadow_offset_y", 3)
	t.clip_text = true
	tv.add_child(t)
	var s := label(sentence, FS_BODY, TEXT)
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	s.clip_text = true
	tv.add_child(s)
	root.set_meta("sentence", s)
	# monnaies
	var mon := hbox(10)
	mon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mon)
	for m in [["coin", tickets, GOLD, "tickets_label"], ["shard", shards, ACCENT, "shards_label"]]:
		var c := chip(String(m[0]), str(int(m[1])), m[2])
		var cl: Label = c.get_meta("label")
		cl.add_theme_font_override("font", TITLE)
		cl.add_theme_font_size_override("font_size", 26)
		var cs: StyleBoxFlat = c.get_theme_stylebox("panel")
		cs.content_margin_top = 8
		cs.content_margin_bottom = 8
		mon.add_child(c)
		root.set_meta(String(m[3]), cl)
		root.set_meta(String(m[3]) + "_chip", c)
	return root

## Met à jour les monnaies du bandeau (après un achat).
static func header_set_money(header: Control, tickets: int, shards: int) -> void:
	if header.has_meta("tickets_label"):
		(header.get_meta("tickets_label") as Label).text = str(tickets)
	if header.has_meta("shards_label"):
		(header.get_meta("shards_label") as Label).text = str(shards)

## Liste qui défile verticalement, au doigt comme à la souris (scripts/ui/touch_scroll.gd branché).
static func scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	TouchScroll.attach(sc)
	return sc

## Grande ligne cliquable des écrans du Relais : pictogramme dans un disque, nom (26 px), ligne d'effet (22 px)
## colorée, et à droite une zone libre (meta "right", HBox) pour un badge ou une comparaison.
static func big_tile(icon_kind: String, title_text: String, body_text: String, accent: Color, body_col: Color, selected: bool = false, h: float = 92.0) -> Button:
	load_fonts()
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	var face := Color("#1E2F5E") if selected else Color(PANEL, 0.97)
	var normal := chunky(face, INK, false, 16)
	normal.border_width_left = 6
	normal.border_color = accent if selected else Color(accent, 0.55)
	if selected:
		normal.set_border_width_all(3)
		normal.border_width_left = 8
		normal.border_width_bottom = 7
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = face.lightened(0.06)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = face.darkened(0.12)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", normal)
	Fx.press(b, 0.97)
	var hb := hbox(14)
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 18
	hb.offset_right = -14
	hb.offset_top = 6
	hb.offset_bottom = -12
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var rs := minf(64.0, h * 0.66)
	var ring := Panel.new()
	ring.custom_minimum_size = Vector2(rs, rs)
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ring.add_theme_stylebox_override("panel", flat(Color(accent, 0.18), Color(accent, 0.9), int(rs * 0.5), 3))
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ring)
	var ic := Icon.new(icon_kind, accent, rs * 0.62)
	ic.position = Vector2(rs * 0.19, rs * 0.19)
	ring.add_child(ic)
	var v := vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(v)
	var t := label(title_text, 26, TEXT)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.clip_text = true
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	if body_text != "":
		var d := label(body_text, 22, body_col)
		d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		d.clip_text = true
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(d)
	var right := hbox(8)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(right)
	b.set_meta("right", right)
	return b
