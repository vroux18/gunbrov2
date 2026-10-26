extends CanvasLayer
## HUD de combat, dans les marges de sécurité (encoches) : vie en haut à gauche (tremble au coup reçu),
## énergie au centre (pulse quand elle est presque pleine) et piste des 10 salles, tickets qui défilent et
## pause à droite, barre de boss en bas, bandeau d'annonce au milieu, voile rouge quand Jo est touchée.
## Tout est dessiné en code (pas de nœuds par frame) ; styleboxes réutilisés. Chaque bloc a son calque,
## redessiné seulement quand ce qu'il montre change (une barre figée ne coûte rien) ; l'ordre de dessin est
## celui d'un seul passage : voile, vie, bouclier, énergie, étincelle, tickets, boss, bandeau.

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
var _cv: Control  # calque en cours de dessin (les primitives dessinent dedans)
var _ly := {}  # nom -> calque
var _sig := {}  # nom -> entrées du dernier dessin
var _sh := Vector2.ZERO  # tremblement de la barre de vie, tiré une fois par image
var _W := 0.0
var _H := 0.0
var _L := 0.0
var _R := 0.0
var _T := 0.0

const LAYERS := ["veil", "health", "shield", "energy", "spark", "right", "boss", "message"]

const RED := Color("#FF4D6D")
const HP_COL := Color("#FF7A2F")
const TRACK := Color("#16213F")

func _ready() -> void:
	layer = 5
	UI.load_fonts()
	_sb.anti_aliasing = true
	# vignettage léger : bords assombris, centre net
	var vig := Control.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.draw.connect(_draw_vignette.bind(vig))
	add_child(vig)
	_c = Control.new()
	_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_c)
	for k in LAYERS:
		var ly := Control.new()
		ly.set_anchors_preset(Control.PRESET_FULL_RECT)
		ly.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ly.draw.connect(_draw_layer.bind(k, ly))
		_c.add_child(ly)
		_ly[k] = ly
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

## Bandeau de déblocage, sous l'annonce du pouvoir pris : « NOUVEAUX POUVOIRS · MOUVEMENT » et les grands
## pictogrammes des nouveaux pouvoirs, ou « ÉVOLUTION PRÊTE ! » et le sien, en doré. Pas de phrase. Un seul à la
## fois : `slot` (rang quand plusieurs s'ouvrent d'un coup) le fait attendre la fin du précédent ; chacun reste
## 2 s. Quelques nœuds créés une fois, effacés ensuite. Appelé par main.gd.
const BANNER_LIFE := 2.0
func unlock_banner(text: String, col: Color, icons: Array, gold: bool = false, slot: int = 0) -> void:
	var pan := PanelContainer.new()
	var st := UI.flat(Color("#1E1405") if gold else Color("#0A1328"), col, 20, 3)
	st.content_margin_left = 24
	st.content_margin_right = 20
	st.content_margin_top = 10
	st.content_margin_bottom = 12
	st.shadow_color = Color(col, 0.4) if gold else Color(0, 0, 0, 0.5)
	st.shadow_size = 16 if gold else 10
	pan.add_theme_stylebox_override("panel", st)
	pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UI.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pan.add_child(h)
	var t := UI.title(text, 30, UI.GOLD.lightened(0.2) if gold else UI.TEXT, UI.ORANGE if gold else Color(col, 0.7))
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(t)
	for id in icons:
		var ring := Panel.new()
		ring.custom_minimum_size = Vector2(64, 64)
		ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ring.add_theme_stylebox_override("panel", UI.flat(col.darkened(0.66), col, 32, 3))
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Icon.new(String(id), col.lightened(0.2), 40.0)
		ic.position = Vector2(12, 12)
		ring.add_child(ic)
		h.add_child(ring)
	add_child(pan)
	pan.reset_size()
	var vs := _c.size
	pan.position = Vector2((vs.x - pan.size.x) * 0.5, vs.y * 0.3 + 46.0)
	pan.pivot_offset = pan.size * 0.5
	pan.modulate.a = 0.0
	pan.scale = Vector2.ONE * 0.7
	var tw := pan.create_tween()
	tw.tween_interval(0.2 + (BANNER_LIFE + 0.3) * slot)  # attend la fin du bandeau précédent
	tw.tween_property(pan, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(pan, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(BANNER_LIFE - 0.3)
	tw.tween_property(pan, "modulate:a", 0.0, 0.25)
	tw.tween_callback(pan.queue_free)

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
	# en fin d'image (comme un redessin) : voit aussi ce qui est réglé après le HUD dans l'image, même si
	# le jeu vient d'être mis en pause (bandeau effacé par un overlay)
	_update_layers.call_deferred()

## Entrées de chaque calque : s'il y en a une qui change (ou s'il est animé : _t), il est redessiné.
func _update_layers() -> void:
	_W = _c.size.x
	_H = _c.size.y
	_L = _ins["left"]
	_R = _W - float(_ins["right"])
	_T = float(_ins["top"]) - 120.0 * _intro * _intro  # entrée : le bandeau descend
	_sh = Vector2.ZERO
	if _shake > 0.0:
		var a := 9.0 * _shake * _shake
		_sh = Vector2(_rng.randf_range(-a, a), _rng.randf_range(-a * 0.6, a * 0.6))
	var low := hp < 0.3
	var pulsing := energy > 0.75  # presque pleine : tout le bloc énergie pulse
	_set_sig("veil", [_W, _H, hurt, _t if low else 0.0, fade])
	_set_sig("health", [_L, _T, _sh, _shake, hp, _hp_ghost, hp_max, hp_text, _t if low else 0.0])
	_set_sig("shield", [shield, _L, _T, _sh, _t if shield else 0.0])
	_set_sig("energy", [_W, _T, energy, _t if pulsing else 0.0, _energy_pop, room, rooms, wave, waves, boss_hp < 0.0])
	_set_sig("spark", [_t])
	_set_sig("right", [_R, _T, _tk_int, _ticket_pop, enemies_left, boss_hp < 0.0])
	_set_sig("boss", [boss_hp, _boss_ghost, boss_name, _W, _H, _ins["bottom"]] if boss_hp >= 0.0 else [])
	_set_sig("message", [_message_t, message, message_col, _W, _H] if _message_t > 0.0 and message != "" else [])

func _set_sig(k: String, sig: Array) -> void:
	if sig != _sig.get(k):
		_sig[k] = sig
		(_ly[k] as Control).queue_redraw()

## Vignettage : dégradé radial (transparent jusqu'à 62 % du rayon, puis vers un bleu nuit à 50 % dans les
## coins), en coordonnées normalisées de l'écran. Dessiné en anneau de triangles (couleurs aux sommets) qui ne
## couvre que le bord : le centre de l'écran (60 % de sa surface) n'est plus mélangé à chaque image.
## Le long d'un rayon, la couleur varie linéairement : l'interpolation des sommets y est exacte.
func _draw_vignette(vig: Control) -> void:
	const SEG := 256  # rayons (multiple de 8 : les coins de l'écran sont des rayons)
	const T0 := 0.62
	const EDGE := Color(0.0, 0.01, 0.04, 0.5)
	var sz := vig.size
	var k := Vector2(0.5, 0.5).length()  # rayon du dégradé (centre -> coin), en coordonnées normalisées
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in range(SEG + 1):
		var a := TAU * i / SEG
		var d := Vector2(cos(a), sin(a))
		var s_out := minf(0.5 / maxf(absf(d.x), 1e-6), 0.5 / maxf(absf(d.y), 1e-6))
		var t_out := minf(s_out / k, 1.0)
		pts.append((Vector2(0.5, 0.5) + d * (T0 * k)) * sz)
		pts.append((Vector2(0.5, 0.5) + d * s_out) * sz)
		cols.append(Color(0, 0, 0, 0))
		cols.append(Color(0, 0, 0, 0).lerp(EDGE, clampf((t_out - T0) / (1.0 - T0), 0.0, 1.0)))
		if i > 0:
			var b := 2 * i
			idx.append_array([b - 2, b - 1, b + 1, b - 2, b + 1, b])
	RenderingServer.canvas_item_add_triangle_array(vig.get_canvas_item(), idx, pts, cols)

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
	_cv.draw_style_box(_sb, r)

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
		_cv.draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2), Color(UI.INK, 0.7), 3.0)

func _txt(pos: Vector2, s: String, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0, font: Font = null, outline: int = 6) -> void:
	var f: Font = font if font != null else UI.TITLE
	if outline > 0:
		_cv.draw_string_outline(f, pos, s, align, w, size, outline, UI.INK)
	_cv.draw_string(f, pos, s, align, w, size, col)

func _icon(kind: String, pos: Vector2, size: float, col: Color) -> void:
	# pictogrammes du HUD dessinés directement (pas de nœud) : mêmes formes que icon.gd, version simplifiée
	match kind:
		"heart":
			_cv.draw_circle(pos + Vector2(-size * 0.17, -size * 0.1), size * 0.2, col)
			_cv.draw_circle(pos + Vector2(size * 0.17, -size * 0.1), size * 0.2, col)
			_cv.draw_colored_polygon(PackedVector2Array([pos + Vector2(-size * 0.36, -size * 0.04), pos + Vector2(size * 0.36, -size * 0.04), pos + Vector2(0, size * 0.36)]), col)
			_cv.draw_circle(pos + Vector2(-size * 0.2, -size * 0.16), size * 0.07, Color(1, 1, 1, 0.55))
		"bolt":
			var pts := [Vector2(0.08, -0.44), Vector2(-0.28, 0.06), Vector2(-0.02, 0.06), Vector2(-0.1, 0.44), Vector2(0.28, -0.08), Vector2(0.02, -0.08)]
			var p := PackedVector2Array()
			for v in pts:
				p.append(pos + (v as Vector2) * size)
			_cv.draw_colored_polygon(p, col)
		"coin":
			_cv.draw_circle(pos, size * 0.46, UI.INK)
			_cv.draw_circle(pos, size * 0.39, col.darkened(0.25))
			_cv.draw_circle(pos + Vector2(0, -size * 0.04), size * 0.33, col)
			_cv.draw_arc(pos, size * 0.2, 0, TAU, 20, col.darkened(0.3), size * 0.07, true)
			_cv.draw_circle(pos + Vector2(-size * 0.13, -size * 0.15), size * 0.08, Color(1, 1, 1, 0.7))
		"skull":
			_cv.draw_circle(pos + Vector2(0, -size * 0.06), size * 0.34, col)
			_cv.draw_rect(Rect2(pos + Vector2(-size * 0.2, size * 0.12), Vector2(size * 0.4, size * 0.22)), col)
			_cv.draw_circle(pos + Vector2(-size * 0.13, -size * 0.06), size * 0.09, UI.INK)
			_cv.draw_circle(pos + Vector2(size * 0.13, -size * 0.06), size * 0.09, UI.INK)
		"shield":
			var sp := PackedVector2Array()
			for v in [Vector2(0, -0.42), Vector2(0.36, -0.28), Vector2(0.3, 0.14), Vector2(0, 0.42), Vector2(-0.3, 0.14), Vector2(-0.36, -0.28)]:
				sp.append(pos + (v as Vector2) * size)
			_cv.draw_colored_polygon(sp, col)

func _badge(c: Vector2, r: float, inner: Color, ring: Color) -> void:
	_cv.draw_circle(c + Vector2(0, 4), r + 3.0, Color(0, 0, 0, 0.35))
	_cv.draw_circle(c, r + 3.0, UI.INK)
	_cv.draw_circle(c, r, inner)
	_cv.draw_arc(c, r - 1.5, 0, TAU, 40, ring, 3.0, true)
	_cv.draw_arc(c, r - 7.0, -2.5, -0.9, 16, Color(1, 1, 1, 0.22), 3.0, true)

# ---------------------------------------------------------------- dessin
func _draw_layer(k: String, ly: Control) -> void:
	_cv = ly
	match k:
		"veil":
			_draw_veil(_W, _H)
		"health":
			_draw_health(_L, _T)
		"shield":
			_draw_shield(_L, _T)
		"energy":
			_draw_energy(_W, _T)
		"spark":
			_draw_spark(_W, _T)
		"right":
			_draw_right(_R, _T)
		"boss":
			if boss_hp >= 0.0:
				_draw_boss(_W, _H)
		"message":
			_draw_message(_W, _H)

## Voile rouge (coup reçu, vie basse) et éclair de portail (début de salle).
func _draw_veil(W: float, H: float) -> void:
	var low := hp < 0.3
	var v := hurt
	if low:
		v = maxf(v, 0.25 + 0.15 * sin(_t * 6.0))
	if v > 0.01:
		for k in range(8):
			var a := v * 0.1 * (1.0 - k / 8.0)
			var g := 10.0 + k * 11.0
			_cv.draw_rect(Rect2(0, 0, W, H).grow(-g * 0.5), Color(1.0, 0.1, 0.25, a), false, g)
	# éclair de portail (début de salle)
	if fade > 0.0:
		_cv.draw_rect(Rect2(0, 0, W, H), Color(0.75, 1.0, 0.97, fade * fade * 0.85))

func _draw_health(L: float, T: float) -> void:
	var low := hp < 0.3
	var o := Vector2(L, T) + _sh
	var bc := o + Vector2(40, 40)
	var beat := 1.0 + (0.14 * maxf(0.0, sin(_t * 9.0)) if low else 0.0) + _shake * 0.2
	_badge(bc, 36.0, Color("#3A1426"), RED.lerp(Color.WHITE, _shake * 0.6))
	_icon("heart", bc + Vector2(0, 2), 46.0 * beat, RED.lerp(Color.WHITE, _shake * 0.5))
	var bw := 300.0
	var r := Rect2(o + Vector2(84, 22), Vector2(bw, 34))
	var segs := clampi(int(hp_max / 25.0), 2, 12)
	_bar(r, hp, RED if low else HP_COL, _hp_ghost, segs, _shake * 0.55)
	_txt(Vector2(r.position.x, r.position.y + 26), hp_text, 22, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, null, 6)

## Bouclier prêt : pastille à droite de la barre de vie (tremble avec elle), pictogramme qui respire.
func _draw_shield(L: float, T: float) -> void:
	if shield:
		var r := Rect2(Vector2(L, T) + _sh + Vector2(84, 22), Vector2(300.0, 34))
		var sc := Vector2(r.end.x + 26, r.position.y + 17)
		_cv.draw_circle(sc, 19, UI.INK)
		_cv.draw_circle(sc, 15, Color("#103A44"))
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
	_cv.draw_line(Vector2(x0, y), Vector2(x0 + track_w, y), Color(UI.LINE, 0.9), 3.0)
	_cv.draw_line(Vector2(x0, y), Vector2(x0 + pip * (room - 1), y), Color(UI.ACCENT, 0.9), 3.0)
	for i in range(rooms):
		var p := Vector2(x0 + i * pip, y)
		var n := i + 1
		if n == rooms:
			var col := Color("#F23CB8") if n <= room else Color("#7A3A66")
			_cv.draw_circle(p, 10.0, UI.INK)
			_icon("skull", p + Vector2(0, 1), 17.0, col)
		elif n < room:
			_cv.draw_circle(p, 6.0, UI.ACCENT)
		elif n == room:
			pass  # salle en cours : pastille qui pulse (_draw_spark)
		else:
			_cv.draw_circle(p, 5.5, UI.INK)
			_cv.draw_arc(p, 5.0, 0, TAU, 16, Color(UI.MUTED, 0.6), 2.0, true)

## Ce qui bouge à chaque image dans le bloc énergie : étincelle au bout du remplissage, pastille de la salle en
## cours sur la piste (rien ne les recouvre : un calque au-dessus suffit).
func _draw_spark(W: float, T: float) -> void:
	var ew := clampf(W * 0.3, 320.0, 440.0)
	var ex := W * 0.5 - ew * 0.5 + 30.0
	var near := clampf((energy - 0.75) / 0.25, 0.0, 1.0)
	var puls := 0.5 + 0.5 * sin(_t * (9.0 + 5.0 * near))
	var r := Rect2(ex, T + 18, ew, 24)
	if near > 0.0:
		var grow := 1.5 * near * puls
		r = r.grow_individual(0, grow, 0, grow)
	if energy > 0.02:
		var tip := Vector2(r.position.x + r.size.x * clampf(energy, 0.0, 1.0) - 6.0, r.position.y + r.size.y * 0.5)
		_cv.draw_circle(tip, 5.0 + 3.0 * puls * (0.4 + near), Color(1, 1, 1, 0.55 + 0.35 * near))
	if room >= 1 and room < rooms:
		var y := T + 70.0
		var pip := 22.0
		var p := Vector2(W * 0.5 - pip * (rooms - 1) * 0.5 + (room - 1) * pip, y)
		_cv.draw_circle(p, 10.0 + 1.5 * sin(_t * 5.0), Color(UI.ORANGE, 0.35))
		_cv.draw_circle(p, 7.5, UI.ORANGE)
		_cv.draw_circle(p + Vector2(-2, -2), 2.5, Color(1, 1, 1, 0.7))

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
	_cv.draw_colored_polygon(shadow, Color(0, 0, 0, 0.35 * a))
	_cv.draw_colored_polygon(p, Color(UI.INK, 0.82 * a))
	_cv.draw_polyline(PackedVector2Array([p[0], p[1], p[2], p[3], p[0]]), Color(message_col, 0.9 * a), 3.0, true)
	# chevrons de part et d'autre
	for sd: float in [-1.0, 1.0]:
		for k in range(2):
			var x := cx + sd * (bw * 0.5 + 34.0 + k * 22.0)
			var c := Color(message_col, a * (0.9 - 0.4 * k))
			_cv.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 14), Vector2(x + sd * 12, y), Vector2(x, y + 14), Vector2(x - sd * 6, y + 14), Vector2(x + sd * 6, y), Vector2(x - sd * 6, y - 14)]), c)
	var ty := y + fs * 0.34
	_cv.draw_string_outline(UI.TITLE, Vector2(0, ty), message, HORIZONTAL_ALIGNMENT_CENTER, W, fs, 10, Color(UI.INK, a))
	_cv.draw_string(UI.TITLE, Vector2(0, ty), message, HORIZONTAL_ALIGNMENT_CENTER, W, fs, Color(message_col.lerp(Color.WHITE, 0.15), a))
