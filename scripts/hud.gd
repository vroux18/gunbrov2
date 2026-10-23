extends CanvasLayer
## HUD de combat : vie en haut à gauche, énergie et salle au centre, tickets et pause à droite,
## barre de boss en bas, bandeau d'annonce au milieu, voile rouge quand Jo est touchée.
## Tout est dessiné dans un seul Control (un seul appel de dessin par élément, pas de nœuds par frame).

const UI = preload("res://scripts/ui.gd")
const Icon = preload("res://scripts/icon.gd")

signal pause_pressed

var hp := 1.0
var hp_text := "100"
var hp_max := 100.0
var shield := false
var energy := 0.0
var room := 1
var wave := 1
var waves := 3
var world := ""
var tickets := 0
var enemies_left := 0
var boss_hp := -1.0
var boss_name := ""
var hurt := 0.0  # 0..1, posé par main au moment d'un coup
var fade := 0.0  # 1 : éclair de portail plein écran au début d'une salle
var message := ""
var message_col := Color.WHITE
var _message_t := 0.0
var _message_life := 1.0
var _hp_ghost := 1.0
var _boss_ghost := 1.0
var _ticket_pop := 0.0
var _last_tickets := 0
var _t := 0.0
var _c: Control
var _pause: Button

func _ready() -> void:
	layer = 5
	UI.load_fonts()
	# vignettage léger : bords assombris, centre net
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0.0, 0.01, 0.04, 0.5))
	g.add_point(0.62, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 256
	gt.height = 144
	var vig := TextureRect.new()
	vig.texture = gt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)
	_c = Control.new()
	_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.draw.connect(_draw_hud)
	add_child(_c)
	_pause = UI.button("II", 24, UI.MUTED)
	_pause.anchor_left = 1.0
	_pause.anchor_right = 1.0
	_pause.offset_left = -84
	_pause.offset_right = -20
	_pause.offset_top = 16
	_pause.offset_bottom = 74
	_pause.add_theme_font_override("font", UI.TITLE)
	_pause.pressed.connect(func(): pause_pressed.emit())
	add_child(_pause)

func flash(text: String, t: float = 2.2, col: Color = Color.WHITE) -> void:
	message = text
	message_col = col
	_message_t = t
	_message_life = t

func _process(dt: float) -> void:
	_t += dt
	if _message_t > 0.0:
		_message_t -= dt
	hurt = maxf(0.0, hurt - dt * 2.2)
	fade = maxf(0.0, fade - dt * 1.8)
	_hp_ghost = move_toward(_hp_ghost, hp, dt * 0.5) if _hp_ghost > hp else hp
	if boss_hp >= 0.0:
		_boss_ghost = move_toward(_boss_ghost, boss_hp, dt * 0.35) if _boss_ghost > boss_hp else boss_hp
	else:
		_boss_ghost = 1.0
	if tickets != _last_tickets:
		_ticket_pop = 1.0
		_last_tickets = tickets
	_ticket_pop = maxf(0.0, _ticket_pop - dt * 4.0)
	_c.queue_redraw()

func _rr(r: Rect2, col: Color, radius: float) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(int(radius))
	s.anti_aliasing = true
	_c.draw_style_box(s, r)

func _bar(r: Rect2, ratio: float, col: Color, ghost: float = -1.0, segments: int = 0) -> void:
	_rr(r.grow(3.0), UI.INK, r.size.y * 0.5 + 3.0)
	_rr(r, Color("#1A2546"), r.size.y * 0.5)
	if ghost > ratio:
		_rr(Rect2(r.position, Vector2(r.size.x * clampf(ghost, 0.0, 1.0), r.size.y)), Color(1, 1, 1, 0.55), r.size.y * 0.5)
	if ratio > 0.0:
		var w := maxf(r.size.y, r.size.x * clampf(ratio, 0.0, 1.0))
		_rr(Rect2(r.position, Vector2(w, r.size.y)), col, r.size.y * 0.5)
		_rr(Rect2(r.position + Vector2(4, 3), Vector2(maxf(0.0, w - 8.0), r.size.y * 0.32)), Color(1, 1, 1, 0.28), r.size.y * 0.2)
	for k in range(1, segments):
		var x := r.position.x + r.size.x * k / segments
		_c.draw_line(Vector2(x, r.position.y + 3), Vector2(x, r.end.y - 3), Color(UI.INK, 0.55), 2.0)

func _txt(pos: Vector2, s: String, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0, font: Font = null, outline: int = 6) -> void:
	var f: Font = font if font != null else UI.TITLE
	if outline > 0:
		_c.draw_string_outline(f, pos, s, align, w, size, outline, UI.INK)
	_c.draw_string(f, pos, s, align, w, size, col)

func _icon(kind: String, pos: Vector2, size: float, col: Color) -> void:
	# pictogrammes du HUD dessinés directement (pas de nœud) : mêmes formes que icon.gd, version simplifiée
	match kind:
		"heart":
			_c.draw_circle(pos + Vector2(-size * 0.17, -size * 0.1), size * 0.2, col)
			_c.draw_circle(pos + Vector2(size * 0.17, -size * 0.1), size * 0.2, col)
			_c.draw_colored_polygon(PackedVector2Array([pos + Vector2(-size * 0.36, -size * 0.04), pos + Vector2(size * 0.36, -size * 0.04), pos + Vector2(0, size * 0.36)]), col)
		"bolt":
			var pts := [Vector2(0.08, -0.44), Vector2(-0.28, 0.06), Vector2(-0.02, 0.06), Vector2(-0.1, 0.44), Vector2(0.28, -0.08), Vector2(0.02, -0.08)]
			var p := PackedVector2Array()
			for v in pts:
				p.append(pos + (v as Vector2) * size)
			_c.draw_colored_polygon(p, col)
		"coin":
			_c.draw_circle(pos, size * 0.42, UI.INK)
			_c.draw_circle(pos, size * 0.36, col)
			_c.draw_circle(pos + Vector2(-size * 0.1, -size * 0.1), size * 0.11, Color(1, 1, 1, 0.6))
		"skull":
			_c.draw_circle(pos + Vector2(0, -size * 0.06), size * 0.34, col)
			_c.draw_rect(Rect2(pos + Vector2(-size * 0.2, size * 0.12), Vector2(size * 0.4, size * 0.22)), col)
			_c.draw_circle(pos + Vector2(-size * 0.13, -size * 0.06), size * 0.09, UI.INK)
			_c.draw_circle(pos + Vector2(size * 0.13, -size * 0.06), size * 0.09, UI.INK)

func _draw_hud() -> void:
	var W := _c.size.x
	var H := _c.size.y
	# voile rouge (coup reçu, vie basse)
	var low := hp < 0.3
	var v := hurt
	if low:
		v = maxf(v, 0.25 + 0.15 * sin(_t * 6.0))
	if v > 0.01:
		for k in range(10):
			var a := v * 0.09 * (1.0 - k / 10.0)
			var g := 8.0 + k * 9.0
			_c.draw_rect(Rect2(0, 0, W, H).grow(-g * 0.5), Color(1.0, 0.1, 0.25, a), false, g)
	# éclair de portail (début de salle)
	if fade > 0.0:
		_c.draw_rect(Rect2(0, 0, W, H), Color(0.75, 1.0, 0.97, fade * fade * 0.85))
	# vie
	var hp_rect := Rect2(78, 26, 300, 26)
	_c.draw_circle(Vector2(50, 39), 30, UI.INK)
	_c.draw_circle(Vector2(50, 39), 25, Color("#2A1830"))
	_icon("heart", Vector2(50, 40), 34 * (1.0 + (0.12 * sin(_t * 10.0) if low else 0.0)), Color("#FF4D6D"))
	var segs := clampi(int(hp_max / 25.0), 2, 12)
	_bar(hp_rect, hp, Color("#FF4D6D") if low else UI.ORANGE, _hp_ghost, segs)
	_txt(Vector2(90, 47), hp_text, 18, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, null, 5)
	if shield:
		_c.draw_circle(Vector2(398, 39), 13, UI.INK)
		_c.draw_circle(Vector2(398, 39), 9, UI.ACCENT)
	# énergie
	var ew := 420.0
	var ex := W * 0.5 - ew * 0.5
	var full := energy >= 1.0
	var ecol := UI.ACCENT if not full else UI.ACCENT.lerp(Color.WHITE, 0.4 + 0.4 * sin(_t * 10.0))
	_bar(Rect2(ex, 26, ew, 18), energy, ecol)
	_c.draw_circle(Vector2(ex - 4, 35), 22, UI.INK)
	_c.draw_circle(Vector2(ex - 4, 35), 18, Color("#123A44"))
	_icon("bolt", Vector2(ex - 4, 35), 30, UI.ACCENT)
	var wave_txt := "SALLE %d  ·  VAGUE %d/%d" % [room, wave, waves]
	if boss_hp >= 0.0:
		wave_txt = "SALLE %d  ·  BOSS" % room
	var pill := Rect2(W * 0.5 - 150, 54, 300, 30)
	_rr(pill, Color(UI.INK, 0.75), 15)
	_txt(Vector2(pill.position.x, pill.position.y + 22), wave_txt, 16, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, pill.size.x, null, 0)
	# tickets
	var tp := 1.0 + _ticket_pop * 0.35
	_icon("coin", Vector2(W - 168, 44), 30 * tp, UI.GOLD)
	_txt(Vector2(W - 148, 53), str(tickets), int(24 * (1.0 + _ticket_pop * 0.15)), UI.TEXT)
	if enemies_left > 0 and boss_hp < 0.0:
		_txt(Vector2(W - 190, 96), ("%d ennemi" if enemies_left == 1 else "%d ennemis") % enemies_left, 15, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.BODY, 4)
	# boss
	if boss_hp >= 0.0:
		var bw := minf(720.0, W - 120.0)
		var br := Rect2((W - bw) * 0.5, H - 46, bw, 22)
		_bar(br, boss_hp, Color("#F23CB8"), _boss_ghost, 4)
		_c.draw_circle(Vector2(br.position.x - 6, br.position.y + 11), 24, UI.INK)
		_icon("skull", Vector2(br.position.x - 6, br.position.y + 12), 34, Color("#F23CB8"))
		_txt(Vector2(br.position.x, br.position.y - 10), boss_name.to_upper(), 22, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, bw)
	# bandeau d'annonce : arrive par le haut, s'efface
	if _message_t > 0.0 and message != "":
		var age := _message_life - _message_t
		var a := clampf(_message_t * 2.5, 0.0, 1.0) * clampf(age * 6.0, 0.0, 1.0)
		var s := 1.0 + maxf(0.0, 0.25 - age) * 1.6
		var y := H * 0.3
		var band := Rect2(0, y - 46 * s, W, 70 * s)
		_c.draw_rect(band, Color(UI.INK, 0.45 * a))
		_c.draw_rect(Rect2(band.position, Vector2(W, 3)), Color(message_col, 0.7 * a))
		_c.draw_rect(Rect2(Vector2(0, band.end.y - 3), Vector2(W, 3)), Color(message_col, 0.7 * a))
		var fs := int(42 * s)
		_c.draw_string_outline(UI.TITLE, Vector2(0, y + fs * 0.3), message, HORIZONTAL_ALIGNMENT_CENTER, W, fs, 10, Color(UI.INK, a))
		_c.draw_string(UI.TITLE, Vector2(0, y + fs * 0.3), message, HORIZONTAL_ALIGNMENT_CENTER, W, fs, Color(message_col, a))
