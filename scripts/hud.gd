extends CanvasLayer
## HUD de combat, dans les marges de sécurité (encoches) : vie en haut à gauche (tremble au coup reçu),
## énergie au centre (pulse quand elle est presque pleine) et piste des 10 salles, tickets qui défilent et
## pause à droite, barre de boss en bas, bandeau d'annonce au milieu, voile rouge quand Jo est touchée.
## Tout est dessiné dans un seul Control (pas de nœuds par frame) ; styleboxes réutilisés.

const UI = preload("res://scripts/ui.gd")
const Icon = preload("res://scripts/icon.gd")
const Fx = preload("res://scripts/ui/fx.gd")

signal pause_pressed

var hp := 1.0
var hp_text := "100"
var hp_max := 100.0
var shield := false
var energy := 0.0
var room := 1
var rooms := 10
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
var _hp_last := 1.0
var _shake := 0.0
var _boss_ghost := 1.0
var _ticket_pop := 0.0
var _tk_shown := 0.0
var _tk_int := 0
var _energy_last := 0.0
var _energy_pop := 0.0
var _t := 0.0
var _intro := 0.0  # 1 au début d'une partie : le HUD glisse depuis le haut
var _c: Control
var _pause: Button
var _ins := {"left": 24.0, "right": 24.0, "top": 14.0, "bottom": 12.0}
var _ins_t := 0.0
var _sb := StyleBoxFlat.new()
var _rng := RandomNumberGenerator.new()

const RED := Color("#FF4D6D")
const HP_COL := Color("#FF7A2F")
const TRACK := Color("#16213F")

func _ready() -> void:
	layer = 5
	UI.load_fonts()
	_sb.anti_aliasing = true
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
	# pause : zone de toucher de 84 px (≈ 126 px en 1080p), pictogramme au centre
	_pause = UI.button("", 24, UI.MUTED)
	var ps: StyleBoxFlat = UI.chunky(Color("#1B2A52", 0.92), Color("#0A1430"), false, 20)
	_pause.add_theme_stylebox_override("normal", ps)
	_pause.add_theme_stylebox_override("hover", ps)
	_pause.add_theme_stylebox_override("pressed", UI.chunky(Color("#14213F"), Color("#0A1430"), true, 20))
	_pause.add_theme_stylebox_override("hover_pressed", UI.chunky(Color("#14213F"), Color("#0A1430"), true, 20))
	_pause.anchor_left = 1.0
	_pause.anchor_right = 1.0
	_pause.custom_minimum_size = Vector2(76, 76)
	var pic := Icon.new("pause", UI.TEXT, 34.0)
	pic.position = Vector2(21, 17)
	pic.size = Vector2(34, 34)
	_pause.add_child(pic)
	_pause.pressed.connect(func(): pause_pressed.emit())
	add_child(_pause)
	_place()

func _place() -> void:
	_ins = UI.safe_insets(_c.get_viewport())
	_pause.offset_right = -float(_ins["right"])
	_pause.offset_left = _pause.offset_right - 76.0
	_pause.offset_top = float(_ins["top"])
	_pause.offset_bottom = _pause.offset_top + 76.0

func flash(text: String, t: float = 2.2, col: Color = Color.WHITE) -> void:
	message = text
	message_col = col
	_message_t = t
	_message_life = t

func _process(dt: float) -> void:
	_t += dt
	_intro = maxf(0.0, _intro - dt * 2.2)
	_ins_t -= dt
	if _ins_t <= 0.0:
		_ins_t = 1.0
		_place()
	if _message_t > 0.0:
		_message_t -= dt
	# coup reçu : la barre de vie tremble
	if hp < _hp_last - 0.001:
		_shake = 1.0
	_hp_last = hp
	_shake = maxf(0.0, _shake - dt * 3.0)
	hurt = maxf(0.0, hurt - dt * 2.2)
	fade = maxf(0.0, fade - dt * 1.8)
	_hp_ghost = move_toward(_hp_ghost, hp, dt * 0.45) if _hp_ghost > hp else hp
	if boss_hp >= 0.0:
		_boss_ghost = move_toward(_boss_ghost, boss_hp, dt * 0.35) if _boss_ghost > boss_hp else boss_hp
	else:
		_boss_ghost = 1.0
	# tickets : le compteur défile jusqu'à la valeur, petit saut à chaque changement
	if absf(tickets - _tk_shown) > 0.01:
		var step := maxf(12.0 * dt, absf(tickets - _tk_shown) * dt * 7.0)
		_tk_shown = move_toward(_tk_shown, float(tickets), step)
	if int(round(_tk_shown)) != _tk_int:
		_tk_int = int(round(_tk_shown))
		_ticket_pop = 1.0
	_ticket_pop = maxf(0.0, _ticket_pop - dt * 4.5)
	if energy > _energy_last + 0.001:
		_energy_pop = 1.0
	_energy_last = energy
	_energy_pop = maxf(0.0, _energy_pop - dt * 4.0)
	_c.queue_redraw()

## Remet les compteurs animés à la valeur courante (nouvelle partie).
func snap() -> void:
	_tk_shown = float(tickets)
	_tk_int = tickets
	_hp_ghost = hp
	_hp_last = hp
	_energy_last = energy
	_intro = 1.0

# ---------------------------------------------------------------- primitives
func _rr(r: Rect2, col: Color, radius: float, border: float = 0.0, border_col: Color = Color.BLACK) -> void:
	_sb.bg_color = col
	_sb.set_corner_radius_all(int(radius))
	_sb.set_border_width_all(int(border))
	_sb.border_color = border_col
	_c.draw_style_box(_sb, r)

func _bar(r: Rect2, ratio: float, col: Color, ghost: float = -1.0, segments: int = 0, flash_k: float = 0.0) -> void:
	var rad := r.size.y * 0.5
	_rr(Rect2(r.position + Vector2(0, 4), r.size).grow(3.0), Color(0, 0, 0, 0.35), rad + 3.0)
	_rr(r.grow(3.0), UI.INK, rad + 3.0)
	_rr(r, TRACK, rad)
	if ghost > ratio:
		_rr(Rect2(r.position, Vector2(maxf(r.size.y, r.size.x * clampf(ghost, 0.0, 1.0)), r.size.y)), Color(1, 1, 1, 0.75), rad)
	if ratio > 0.0:
		var w := maxf(r.size.y, r.size.x * clampf(ratio, 0.0, 1.0))
		var fc := col.lerp(Color.WHITE, flash_k)
		_rr(Rect2(r.position, Vector2(w, r.size.y)), fc.darkened(0.25), rad)
		_rr(Rect2(r.position, Vector2(w, r.size.y * 0.72)), fc, rad)
		_rr(Rect2(r.position + Vector2(rad * 0.6, 3), Vector2(maxf(0.0, w - rad * 1.2), r.size.y * 0.24)), Color(1, 1, 1, 0.35), r.size.y * 0.12)
	for k in range(1, segments):
		var x := r.position.x + r.size.x * k / segments
		_c.draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2), Color(UI.INK, 0.7), 3.0)

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
			_c.draw_circle(pos + Vector2(-size * 0.2, -size * 0.16), size * 0.07, Color(1, 1, 1, 0.55))
		"bolt":
			var pts := [Vector2(0.08, -0.44), Vector2(-0.28, 0.06), Vector2(-0.02, 0.06), Vector2(-0.1, 0.44), Vector2(0.28, -0.08), Vector2(0.02, -0.08)]
			var p := PackedVector2Array()
			for v in pts:
				p.append(pos + (v as Vector2) * size)
			_c.draw_colored_polygon(p, col)
		"coin":
			_c.draw_circle(pos, size * 0.46, UI.INK)
			_c.draw_circle(pos, size * 0.39, col.darkened(0.25))
			_c.draw_circle(pos + Vector2(0, -size * 0.04), size * 0.33, col)
			_c.draw_arc(pos, size * 0.2, 0, TAU, 20, col.darkened(0.3), size * 0.07, true)
			_c.draw_circle(pos + Vector2(-size * 0.13, -size * 0.15), size * 0.08, Color(1, 1, 1, 0.7))
		"skull":
			_c.draw_circle(pos + Vector2(0, -size * 0.06), size * 0.34, col)
			_c.draw_rect(Rect2(pos + Vector2(-size * 0.2, size * 0.12), Vector2(size * 0.4, size * 0.22)), col)
			_c.draw_circle(pos + Vector2(-size * 0.13, -size * 0.06), size * 0.09, UI.INK)
			_c.draw_circle(pos + Vector2(size * 0.13, -size * 0.06), size * 0.09, UI.INK)
		"shield":
			var sp := PackedVector2Array()
			for v in [Vector2(0, -0.42), Vector2(0.36, -0.28), Vector2(0.3, 0.14), Vector2(0, 0.42), Vector2(-0.3, 0.14), Vector2(-0.36, -0.28)]:
				sp.append(pos + (v as Vector2) * size)
			_c.draw_colored_polygon(sp, col)

func _badge(c: Vector2, r: float, inner: Color, ring: Color) -> void:
	_c.draw_circle(c + Vector2(0, 4), r + 3.0, Color(0, 0, 0, 0.35))
	_c.draw_circle(c, r + 3.0, UI.INK)
	_c.draw_circle(c, r, inner)
	_c.draw_arc(c, r - 1.5, 0, TAU, 40, ring, 3.0, true)
	_c.draw_arc(c, r - 7.0, -2.5, -0.9, 16, Color(1, 1, 1, 0.22), 3.0, true)

# ---------------------------------------------------------------- dessin
func _draw_hud() -> void:
	var W := _c.size.x
	var H := _c.size.y
	var L: float = _ins["left"]
	var R: float = W - float(_ins["right"])
	var T: float = float(_ins["top"]) - 120.0 * _intro * _intro  # entrée : le bandeau descend
	# voile rouge (coup reçu, vie basse)
	var low := hp < 0.3
	var v := hurt
	if low:
		v = maxf(v, 0.25 + 0.15 * sin(_t * 6.0))
	if v > 0.01:
		for k in range(8):
			var a := v * 0.1 * (1.0 - k / 8.0)
			var g := 10.0 + k * 11.0
			_c.draw_rect(Rect2(0, 0, W, H).grow(-g * 0.5), Color(1.0, 0.1, 0.25, a), false, g)
	# éclair de portail (début de salle)
	if fade > 0.0:
		_c.draw_rect(Rect2(0, 0, W, H), Color(0.75, 1.0, 0.97, fade * fade * 0.85))
	_draw_health(L, T)
	_draw_energy(W, T)
	_draw_right(R, T)
	if boss_hp >= 0.0:
		_draw_boss(W, H)
	_draw_message(W, H)

func _draw_health(L: float, T: float) -> void:
	var low := hp < 0.3
	var sh := Vector2.ZERO
	if _shake > 0.0:
		var a := 9.0 * _shake * _shake
		sh = Vector2(_rng.randf_range(-a, a), _rng.randf_range(-a * 0.6, a * 0.6))
	var o := Vector2(L, T) + sh
	var bc := o + Vector2(40, 40)
	var beat := 1.0 + (0.14 * maxf(0.0, sin(_t * 9.0)) if low else 0.0) + _shake * 0.2
	_badge(bc, 36.0, Color("#3A1426"), RED.lerp(Color.WHITE, _shake * 0.6))
	_icon("heart", bc + Vector2(0, 2), 46.0 * beat, RED.lerp(Color.WHITE, _shake * 0.5))
	var bw := 300.0
	var r := Rect2(o + Vector2(84, 22), Vector2(bw, 34))
	var segs := clampi(int(hp_max / 25.0), 2, 12)
	_bar(r, hp, RED if low else HP_COL, _hp_ghost, segs, _shake * 0.55)
	_txt(Vector2(r.position.x, r.position.y + 26), hp_text, 22, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, null, 6)
	if shield:
		var sc := Vector2(r.end.x + 26, r.position.y + 17)
		_c.draw_circle(sc, 19, UI.INK)
		_c.draw_circle(sc, 15, Color("#103A44"))
		_icon("shield", sc, 22.0 + 2.0 * sin(_t * 4.0), UI.ACCENT)

func _draw_energy(W: float, T: float) -> void:
	var ew := clampf(W * 0.3, 320.0, 440.0)
	var ex := W * 0.5 - ew * 0.5 + 30.0
	var near := clampf((energy - 0.75) / 0.25, 0.0, 1.0)
	var full := energy >= 1.0
	var puls := 0.5 + 0.5 * sin(_t * (9.0 + 5.0 * near))
	var r := Rect2(ex, T + 18, ew, 24)
	# presque pleine : halo qui pulse autour de la barre, la barre grossit un peu
	if near > 0.0:
		for k in range(4):
			var gk := 4.0 + k * 5.0
			_rr(r.grow(gk), Color(UI.ACCENT, (0.3 - k * 0.065) * near * (0.4 + 0.6 * puls)), r.size.y * 0.5 + gk)
		var grow := 1.5 * near * puls
		r = r.grow_individual(0, grow, 0, grow)
	var ecol := UI.ACCENT.lerp(Color.WHITE, (0.25 + 0.35 * puls) * near if not full else 0.5 + 0.4 * puls)
	_bar(r, energy, ecol, -1.0, 10, _energy_pop * 0.4)
	# étincelle au bout du remplissage
	if energy > 0.02:
		var tip := Vector2(r.position.x + r.size.x * clampf(energy, 0.0, 1.0) - 6.0, r.position.y + r.size.y * 0.5)
		_c.draw_circle(tip, 5.0 + 3.0 * puls * (0.4 + near), Color(1, 1, 1, 0.55 + 0.35 * near))
	var bc := Vector2(ex - 30, T + 30)
	var bs := 1.0 + 0.18 * near * puls + _energy_pop * 0.15
	_badge(bc, 28.0 * (1.0 + 0.06 * near * puls), Color("#0E3640"), UI.ACCENT.lerp(Color.WHITE, near * puls * 0.6))
	_icon("bolt", bc, 40.0 * bs, UI.ACCENT.lerp(Color.WHITE, near * puls * 0.5))
	# piste des salles : SALLE n · 10 jalons (le dernier = boss) · VAGUE w/n
	var y := T + 70.0
	var pip := 22.0
	var track_w := pip * (rooms - 1)
	var cx := W * 0.5
	var pill := Rect2(cx - track_w * 0.5 - 132, y - 17, track_w + 264, 34)
	_rr(pill, Color(UI.INK, 0.62), 17)
	_txt(Vector2(pill.position.x + 14, y + 8), "SALLE %d" % room, 20, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, null, 0)
	var wave_txt := ("VAGUE %d/%d" % [wave, waves]) if boss_hp < 0.0 else "BOSS"
	_txt(Vector2(pill.end.x - 124, y + 8), wave_txt, 20, UI.MUTED if boss_hp < 0.0 else Color("#F23CB8"), HORIZONTAL_ALIGNMENT_RIGHT, 110, null, 0)
	var x0 := cx - track_w * 0.5
	_c.draw_line(Vector2(x0, y), Vector2(x0 + track_w, y), Color(UI.LINE, 0.9), 3.0)
	_c.draw_line(Vector2(x0, y), Vector2(x0 + pip * (room - 1), y), Color(UI.ACCENT, 0.9), 3.0)
	for i in range(rooms):
		var p := Vector2(x0 + i * pip, y)
		var n := i + 1
		if n == rooms:
			var col := Color("#F23CB8") if n <= room else Color("#7A3A66")
			_c.draw_circle(p, 10.0, UI.INK)
			_icon("skull", p + Vector2(0, 1), 17.0, col)
		elif n < room:
			_c.draw_circle(p, 6.0, UI.ACCENT)
		elif n == room:
			_c.draw_circle(p, 10.0 + 1.5 * sin(_t * 5.0), Color(UI.ORANGE, 0.35))
			_c.draw_circle(p, 7.5, UI.ORANGE)
			_c.draw_circle(p + Vector2(-2, -2), 2.5, Color(1, 1, 1, 0.7))
		else:
			_c.draw_circle(p, 5.5, UI.INK)
			_c.draw_arc(p, 5.0, 0, TAU, 16, Color(UI.MUTED, 0.6), 2.0, true)

func _draw_right(R: float, T: float) -> void:
	# tickets : pastille à gauche du bouton pause, chiffre qui défile
	var pr := Rect2(R - 76 - 14 - 150, T + 10, 150, 50)
	_rr(pr, Color(UI.INK, 0.62), 25)
	var tp := 1.0 + _ticket_pop * 0.3
	_icon("coin", Vector2(pr.position.x + 26, pr.position.y + 25), 34.0 * tp, UI.GOLD)
	var fs := int(28 * (1.0 + _ticket_pop * 0.18))
	_txt(Vector2(pr.position.x + 48, pr.position.y + 36), str(_tk_int), fs, UI.GOLD.lerp(Color.WHITE, 0.6 + 0.4 * _ticket_pop), HORIZONTAL_ALIGNMENT_LEFT, -1, null, 6)
	if enemies_left > 0 and boss_hp < 0.0:
		var ey := pr.end.y + 28
		_icon("skull", Vector2(pr.position.x + 26, ey - 7), 22.0, Color(RED, 0.95))
		_txt(Vector2(pr.position.x + 44, ey), ("%d ennemi" if enemies_left == 1 else "%d ennemis") % enemies_left, 21, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.BODY, 5)

func _draw_boss(W: float, H: float) -> void:
	var bw := clampf(W - 640.0, 380.0, 700.0)
	var br := Rect2((W - bw) * 0.5, H - 44 - float(_ins["bottom"]), bw, 24)
	_bar(br, boss_hp, Color("#F23CB8"), _boss_ghost, 4)
	var bc := Vector2(br.position.x - 8, br.position.y + 12)
	_badge(bc, 26.0, Color("#3A0F33"), Color("#F23CB8"))
	_icon("skull", bc + Vector2(0, 1), 34, Color("#F23CB8"))
	_txt(Vector2(br.position.x, br.position.y - 12), boss_name.to_upper(), 26, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, bw, null, 7)

## Bandeau d'annonce : ruban incliné qui claque à l'écran, texte qui arrive gros et se pose.
func _draw_message(W: float, H: float) -> void:
	if _message_t <= 0.0 or message == "":
		return
	var age := _message_life - _message_t
	var a := clampf(_message_t * 3.0, 0.0, 1.0) * clampf(age * 8.0, 0.0, 1.0)
	var s := 1.0 + maxf(0.0, 0.2 - age) * 2.5
	var y := H * 0.3
	var fs := int(46 * s)
	var tw := UI.TITLE.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var open := clampf(age * 5.0, 0.0, 1.0)
	var bw := (tw + 140.0) * (0.3 + 0.7 * open)
	var bh := 66.0
	var sk := 26.0
	var cx := W * 0.5
	var p := PackedVector2Array([Vector2(cx - bw * 0.5 + sk, y - bh * 0.5), Vector2(cx + bw * 0.5 + sk, y - bh * 0.5), Vector2(cx + bw * 0.5 - sk, y + bh * 0.5), Vector2(cx - bw * 0.5 - sk, y + bh * 0.5)])
	var shadow := PackedVector2Array()
	for q in p:
		shadow.append(q + Vector2(6, 7))
	_c.draw_colored_polygon(shadow, Color(0, 0, 0, 0.35 * a))
	_c.draw_colored_polygon(p, Color(UI.INK, 0.82 * a))
	_c.draw_polyline(PackedVector2Array([p[0], p[1], p[2], p[3], p[0]]), Color(message_col, 0.9 * a), 3.0, true)
	# chevrons de part et d'autre
	for sd: float in [-1.0, 1.0]:
		for k in range(2):
			var x := cx + sd * (bw * 0.5 + 34.0 + k * 22.0)
			var c := Color(message_col, a * (0.9 - 0.4 * k))
			_c.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 14), Vector2(x + sd * 12, y), Vector2(x, y + 14), Vector2(x - sd * 6, y + 14), Vector2(x + sd * 6, y), Vector2(x - sd * 6, y - 14)]), c)
	var ty := y + fs * 0.34
	_c.draw_string_outline(UI.TITLE, Vector2(0, ty), message, HORIZONTAL_ALIGNMENT_CENTER, W, fs, 10, Color(UI.INK, a))
	_c.draw_string(UI.TITLE, Vector2(0, ty), message, HORIZONTAL_ALIGNMENT_CENTER, W, fs, Color(message_col.lerp(Color.WHITE, 0.15), a))
