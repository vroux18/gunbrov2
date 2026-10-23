extends RefCounted
## Fabrique d'interface : boutons, panneaux, étiquettes, tous construits en code, un seul style.

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

static func flat(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 14, border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border_w)
	s.border_color = border
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

static func button(text: String, size: int = 26, accent: Color = ACCENT, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", BG)
	b.add_theme_stylebox_override("normal", flat(PANEL, accent, 14, 2))
	b.add_theme_stylebox_override("hover", flat(PANEL.lightened(0.08), accent, 14, 2))
	b.add_theme_stylebox_override("pressed", flat(accent, accent, 14, 2))
	b.add_theme_stylebox_override("focus", flat(PANEL, accent, 14, 2))
	b.add_theme_stylebox_override("disabled", flat(PANEL_DARK, LINE, 14, 2))
	b.add_theme_color_override("font_disabled_color", MUTED)
	if min_w > 0:
		b.custom_minimum_size = Vector2(min_w, 0)
	return b

static func primary(text: String, size: int = 30, min_w: float = 0.0) -> Button:
	var b := button(text, size, ORANGE, min_w)
	b.add_theme_stylebox_override("normal", flat(ORANGE, ORANGE, 16, 0))
	b.add_theme_stylebox_override("hover", flat(ORANGE.lightened(0.1), ORANGE, 16, 0))
	b.add_theme_stylebox_override("pressed", flat(TEXT, TEXT, 16, 0))
	b.add_theme_color_override("font_color", BG)
	b.add_theme_color_override("font_hover_color", BG)
	return b

static func label(text: String, size: int = 22, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

static func panel(bg: Color = PANEL, border: Color = LINE, radius: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	var s := flat(bg, border, radius, 2)
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 22
	s.content_margin_bottom = 22
	p.add_theme_stylebox_override("panel", s)
	return p

## Fond plein écran semi-opaque (overlays de choix, pause, fin de partie).
static func dim(alpha: float = 0.72) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(BG.r, BG.g, BG.b, alpha)
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
