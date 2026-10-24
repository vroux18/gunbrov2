extends Control
## Ouverture d'une box (ou d'une série) : la box 3D tombe et rebondit, on la touche pour la secouer (elle se
## charge de lumière), elle s'ouvre dans un éclair (rayons, colonne de lumière, gerbe d'étincelles, onde),
## puis les récompenses jaillissent une par une en cartes (couleur, halo et son selon la rareté) et finissent
## en petites vignettes ; un récapitulatif clôt la série.
## Rapide : un toucher termine l'animation en cours, PASSER saute au récapitulatif. En série (TOUT OUVRIR),
## les box s'enchaînent toutes seules, plus vite. Le butin est donné au profil dès qu'une box s'ouvre.

signal finished

const UI = preload("res://scripts/ui.gd")
const Fx = preload("res://scripts/ui/fx.gd")
const Save = preload("res://scripts/save.gd")
const Loot = preload("res://scripts/loot.gd")
const Stage = preload("res://scripts/ui/boxes_stage.gd")
const Card = preload("res://scripts/ui/boxes_card.gd")

var main: Node
var queue: Array = []  # box encore à ouvrir dans cette série
var fast := false
var all_rewards: Array = []
var rewards: Array = []
var rarity := ""
var phase := ""
var phase_t := 0.0
var taps := 0
var need := 1
var card_i := -1
var cur_card: Control = null
var _card_tw: Tween = null
var minis: Array = []
var vs := Vector2(1280, 720)
var t := 0.0

var content: Control  # tout ce qui tremble
var stage: Stage
var bg_halo: TextureRect
var rays: Control
var fx: Control
var flash: ColorRect
var title: Label
var hint: Label
var pips: Control
var left_l: Label
var skip_b: Button
var recap: Control = null
var parts: Array = []  # étincelles {p, v, life, max, col, s, star}
var rings: Array = []  # ondes {p, r, life, max, col}
var rays_k := 0.0
var beam_k := 0.0
var shake := 0.0
var _auto := 0.0
var _pending := false  # box suivante attendue (série)

## `boxes` : raretés à ouvrir, dans l'ordre ; `serial` : enchaînement rapide.
func start(m: Node, boxes: Array, serial: bool) -> void:
	main = m
	queue = boxes.duplicate()
	fast = serial
	UI.load_fonts()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	vs = get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = Color("#050A16")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size = vs
	add_child(content)
	bg_halo = Fx.halo(Color(1, 1, 1, 0.5), Vector2(vs.y * 1.7, vs.y * 1.7))
	content.add_child(bg_halo)
	Fx.pulse(bg_halo, 0.7, 1.0, 1.6)
	rays = _additive()
	rays.draw.connect(_draw_rays)
	content.add_child(rays)
	var s := minf(vs.y * 0.76, 560.0)
	stage = Stage.new()
	stage.setup("or", Vector2(s, s))
	stage.position = Vector2((vs.x - s) * 0.5, vs.y * 0.55 - s * 0.5)
	stage.yaw = 0.0
	stage.landed.connect(_on_landed)
	content.add_child(stage)
	bg_halo.position = _mouth() - bg_halo.size * 0.5
	fx = _additive()
	fx.draw.connect(_draw_fx)
	content.add_child(fx)
	pips = Control.new()
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.size = Vector2(vs.x, 30)
	pips.position = Vector2(0, minf(stage.position.y + s * 0.8, vs.y - 100.0))
	pips.draw.connect(_draw_pips)
	content.add_child(pips)
	title = UI.title("", 50, UI.TEXT, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, clampf(vs.y * 0.05, 16.0, 50.0))
	title.size = Vector2(vs.x, 60)
	content.add_child(title)
	hint = UI.title("", 40, UI.TEXT, UI.INK, HORIZONTAL_ALIGNMENT_CENTER)
	hint.size = Vector2(vs.x, 52)
	hint.position = Vector2(0, pips.position.y + 30.0)
	hint.add_theme_color_override("font_outline_color", UI.INK)
	hint.add_theme_constant_override("outline_size", 10)
	content.add_child(hint)
	left_l = UI.title("", 34, UI.TEXT, UI.INK, HORIZONTAL_ALIGNMENT_CENTER)
	left_l.size = Vector2(120, 50)
	left_l.position = _mouth() + Vector2(s * 0.22, -s * 0.2)
	left_l.add_theme_color_override("font_outline_color", UI.INK)
	left_l.add_theme_constant_override("outline_size", 10)
	content.add_child(left_l)
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var ins := UI.safe_insets(get_viewport())
	skip_b = UI.button("PASSER", 22, UI.MUTED, 150)
	skip_b.custom_minimum_size = Vector2(150, 64)
	skip_b.position = Vector2(vs.x - 150 - 20 - float(ins["right"]), 18)
	skip_b.size = Vector2(150, 64)
	skip_b.pressed.connect(_skip_all)
	add_child(skip_b)
	gui_input.connect(_on_input)
	# le Relais 3D est entièrement caché : on ne le dessine plus pendant l'ouverture (après le fondu)
	var tw := create_tween()
	tw.tween_interval(0.2)
	tw.tween_callback(func(): main.view.visible = false)
	_next_box()

func _exit_tree() -> void:
	if main != null and is_instance_valid(main.view):
		main.view.visible = true

func _additive() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = vs
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	c.material = m
	return c

## Bouche de la box à l'écran (d'où sortent la lumière et les cartes).
func _mouth() -> Vector2:
	return stage.position + stage.size * Vector2(0.5, 0.5)

func _col() -> Color:
	return Loot.BOX_COLORS.get(rarity, UI.GOLD)

# ---------------------------------------------------------------- déroulé
func _next_box() -> void:
	if queue.is_empty():
		_show_recap()
		return
	rarity = String(queue.pop_front())
	rewards = Loot.open_box(main.profile, rarity)
	Save.save_profile(main.profile)
	all_rewards.append_array(rewards)
	for mc in minis:
		Fx.screen_out(mc, 0.15)
	minis.clear()
	stage.set_rarity(rarity)
	stage.reset_box()
	stage.visible = true
	stage.drop()
	main.sfx.play("portal", 1.4, -8.0)
	need = int(Loot.BOX_TAPS[rarity])
	taps = 0
	card_i = -1
	rays_k = 0.0
	beam_k = 0.0
	bg_halo.modulate = Color(_col(), 0.32)
	title.text = "BOX " + String(Loot.BOX_NAMES[rarity]).to_upper()
	title.add_theme_color_override("font_shadow_color", _col().darkened(0.4))
	title.add_theme_color_override("font_color", _col().lightened(0.35))
	Fx.slam(title, 0.05, 1.8)
	hint.text = ""
	left_l.text = ""
	_set_phase("drop")

func _set_phase(p: String) -> void:
	phase = p
	phase_t = 0.0
	_auto = 0.0
	pips.queue_redraw()

func _on_landed() -> void:
	main.sfx.play("drop", 0.7, 0.0)
	main.sfx.play("hit", 0.6, -4.0)
	shake = maxf(shake, 0.5)
	_ring(_mouth() + Vector2(0, stage.size.y * 0.16), Color(1, 1, 1, 0.6), 0.5, 0.9)
	_burst(_mouth() + Vector2(0, stage.size.y * 0.16), Color("#B8C8E8"), 14, 260.0, false, 0.6)
	if phase == "drop":
		_to_wait()

func _to_wait() -> void:
	_set_phase("wait")
	hint.text = "TOUCHE !" if need > 1 else "TOUCHE POUR OUVRIR !"
	hint.add_theme_color_override("font_color", _col().lightened(0.45))
	Fx.rise_in(hint, 0.0, 0.25, 0.7)
	left_l.text = "×%d" % rewards.size()
	Fx.slam(left_l, 0.05, 1.6)

## Un toucher : termine l'animation en cours ou fait avancer.
func tap() -> void:
	match phase:
		"drop":
			stage.skip()
			_to_wait()
		"wait":
			taps += 1
			stage.charge = float(taps) / need
			stage.shake(0.55 + 0.45 * float(taps) / need)
			shake = maxf(shake, 0.35 + 0.2 * taps)
			main.sfx.play("hit", 0.75 + 0.22 * taps, -2.0)
			main.sfx.play("click", 0.8 + 0.2 * taps, -6.0)
			_burst(_mouth(), _col().lightened(0.3), 8 + 6 * taps, 340.0, true, 0.5)
			_ring(_mouth(), Color(_col(), 0.5), 0.35, 0.6)
			pips.queue_redraw()
			if taps >= need:
				_open()
		"open":
			if phase_t > 0.12:
				_next_card()
		"card_in":
			if _card_tw != null and _card_tw.is_valid():
				_card_tw.custom_step(10.0)
		"card":
			_next_card()

func _on_input(ev: InputEvent) -> void:
	var down := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
	if down:
		tap()
		accept_event()

func _open() -> void:
	_set_phase("open")
	hint.text = ""
	stage.open()
	bg_halo.modulate = Color(_col(), 0.7)
	rays_k = 1.0
	beam_k = 1.0
	shake = 1.0
	var big := rarity in ["or", "legendaire"]
	flash.color = Color(_col().lightened(0.6), 0.85 if big else 0.7)
	var tw := Fx._tw(flash)
	tw.tween_property(flash, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	main.sfx.play("boom", 0.85, -2.0)
	main.sfx.play("level", 0.9 if not big else 0.75, 0.0)
	main.sfx.play("chest", 0.9, 0.0)
	_burst(_mouth(), _col().lightened(0.25), 60 if big else 40, 760.0, true, 1.0)
	_burst(_mouth(), Color(1, 1, 1), 18, 520.0, false, 0.8)
	_ring(_mouth(), Color(_col(), 0.9), 0.55, 1.6)
	_ring(_mouth(), Color(1, 1, 1, 0.6), 0.4, 1.0)

func _next_card() -> void:
	# carte précédente : se range en vignette sous la box
	if cur_card != null:
		_to_mini(cur_card)
		cur_card = null
	card_i += 1
	if card_i >= rewards.size():
		if not queue.is_empty():
			_set_phase("next")
			var tw := create_tween()
			tw.tween_interval(0.35 if fast else 0.5)
			tw.tween_callback(_next_box)
		else:
			_set_phase("next")
			var tw2 := create_tween()
			tw2.tween_interval(0.3)
			tw2.tween_callback(_show_recap)
		return
	var r: Dictionary = rewards[card_i]
	var cs := Vector2(250, 330) if vs.y >= 700.0 else Vector2(226, 300)
	var c: Card = Card.new()
	c.setup(r, cs)
	content.add_child(c)
	cur_card = c
	var to := Vector2(vs.x * 0.5, vs.y * 0.52) - cs * 0.5
	c.position = _mouth() - cs * 0.5
	c.scale = Vector2.ONE * 0.15
	c.rotation = randf_range(-0.6, 0.6)
	c.modulate.a = 0.0
	left_l.text = "×%d" % (rewards.size() - card_i - 1) if card_i < rewards.size() - 1 else ""
	_set_phase("card_in")
	main.sfx.play("pick", 0.9 + 0.1 * card_i, -6.0)
	_card_tw = create_tween()
	_card_tw.set_parallel(true)
	var dur := 0.2 if fast else 0.32
	_card_tw.tween_property(c, "modulate:a", 1.0, dur * 0.4)
	_card_tw.tween_property(c, "position", to, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_card_tw.tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_card_tw.tween_property(c, "rotation", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_card_tw.chain().tween_callback(func(): _card_landed(c))

## La carte est posée : éclat à la couleur de la rareté, son selon la rareté.
func _card_landed(c: Card) -> void:
	if c != cur_card:
		return
	_set_phase("card")
	var ctr := c.position + c.size * 0.5
	var tier := c.tier
	_burst(ctr, c.col.lightened(0.2), 14 + 10 * tier, 420.0 + 120.0 * tier, true, 0.7)
	_ring(ctr, Color(c.col, 0.7), 0.4, 0.9 + 0.3 * tier)
	Fx.bump(c, 0.06 + 0.03 * tier)
	match tier:
		0:
			main.sfx.play("pick", 1.2, -2.0)
		1:
			main.sfx.play("chest", 1.15, -2.0)
		2:
			main.sfx.play("chest", 1.0, 0.0)
			main.sfx.play("level", 1.1, -2.0)
		_:
			main.sfx.play("level", 0.85, 0.0)
			main.sfx.play("boom", 1.3, -6.0)
			flash.color = Color(c.col.lightened(0.5), 0.55)
			var tw := Fx._tw(flash)
			tw.tween_property(flash, "color:a", 0.0, 0.35)
	if tier >= 2:
		shake = maxf(shake, 0.25 * tier)

func _to_mini(c: Card) -> void:
	var n := rewards.size()
	var ms := Vector2(66, 87)
	var gap := 10.0
	var w := n * ms.x + (n - 1) * gap
	var i := minis.size()
	var to := Vector2((vs.x - w) * 0.5 + i * (ms.x + gap), vs.y - ms.y - 14.0)
	minis.append(c)
	var k := ms.x / c.size.x
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "position", to - c.size * 0.5 + ms * 0.5, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE * k, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# halo et rayons s'éteignent en vignette
	for ch in c.get_children():
		if ch is TextureRect or (ch is Control and (ch as Control).show_behind_parent):
			tw.tween_property(ch, "modulate:a", 0.0, 0.2)

## PASSER : ouvre d'un coup le reste de la série, puis le récapitulatif.
func _skip_all() -> void:
	if phase == "recap":
		return
	if phase == "drop" or phase == "wait":
		# la box en cours est déjà donnée au profil : on n'ouvre que la suite
		pass
	while not queue.is_empty():
		var r := String(queue.pop_front())
		var rw := Loot.open_box(main.profile, r)
		all_rewards.append_array(rw)
	Save.save_profile(main.profile)
	main.sfx.play("chest", 1.0, -2.0)
	_show_recap()

# ---------------------------------------------------------------- récapitulatif
func _show_recap() -> void:
	if recap != null:
		return
	_set_phase("recap")
	hint.text = ""
	left_l.text = ""
	skip_b.visible = false
	if cur_card != null:
		cur_card.queue_free()
		cur_card = null
	for mc in minis:
		Fx.screen_out(mc, 0.12)
	minis.clear()
	stage.visible = false
	rays_k = maxf(rays_k, 0.5)
	recap = Control.new()
	recap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recap.size = vs
	add_child(recap)
	var ttl := UI.title("BUTIN", 50, UI.TEXT, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	ttl.position = Vector2(0, clampf(vs.y * 0.04, 12.0, 40.0))
	ttl.size = Vector2(vs.x, 60)
	recap.add_child(ttl)
	Fx.slam(ttl, 0.0, 1.8)
	title.text = ""
	# tickets regroupés en une carte, le reste une carte chacun, du meilleur au moins bon
	var tk := 0
	var cards := []
	for r in all_rewards:
		if r["kind"] == "tickets":
			tk += int(r["n"])
		else:
			cards.append(r)
	cards.sort_custom(func(a, b): return Loot._rank(a) > Loot._rank(b))
	if tk > 0:
		cards.push_front({"kind": "tickets", "tier": 0, "n": tk})
	var n := cards.size()
	var top := ttl.position.y + 74.0
	var avail := Vector2(vs.x - 80.0, vs.y - top - 120.0)
	var cs := Vector2(214, 282)
	var gap := 16.0
	var cols := n
	for _k in range(8):
		cols = mini(n, maxi(1, int((avail.x + gap) / (cs.x + gap))))
		var rows := int(ceil(float(n) / cols))
		if rows * (cs.y + gap) - gap <= avail.y:
			break
		cs *= 0.86
	var rows2 := int(ceil(float(n) / maxi(cols, 1)))
	var gh := rows2 * (cs.y + gap) - gap
	var y0 := top + maxf(0.0, (avail.y - gh) * 0.5)
	for i in range(n):
		var row := i / cols
		var in_row := mini(cols, n - row * cols)
		var x0 := (vs.x - (in_row * (cs.x + gap) - gap)) * 0.5
		var c: Card = Card.new()
		c.setup(cards[i], cs, true)
		c.position = Vector2(x0 + (i % cols) * (cs.x + gap), y0 + row * (cs.y + gap))
		recap.add_child(c)
		Fx.rise_in(c, 0.05 + 0.04 * i, 0.3, 0.6)
	# boutons : suivante, tout ouvrir, OK
	var bar := UI.hbox(18)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.position = Vector2(0, vs.y - 100.0)
	bar.size = Vector2(vs.x, 84)
	recap.add_child(bar)
	var left := (main.profile["boxes"] as Array).size()
	if left > 0:
		var nb := UI.button("SUIVANTE", 26, UI.GOLD, 230)
		nb.custom_minimum_size = Vector2(230, 80)
		nb.pressed.connect(func(): _restart([String(main.profile["boxes"][0])], false))
		bar.add_child(nb)
		if left > 1:
			var ab := UI.button("TOUT OUVRIR  ×%d" % left, 26, UI.ORANGE, 290)
			ab.custom_minimum_size = Vector2(290, 80)
			ab.pressed.connect(func(): _restart((main.profile["boxes"] as Array).duplicate(), true))
			bar.add_child(ab)
	var ok := UI.primary("OK", 32, 200)
	ok.custom_minimum_size = Vector2(200, 80)
	ok.pressed.connect(func(): finished.emit())
	bar.add_child(ok)
	Fx.rise_in(bar, 0.25 + 0.04 * n, 0.3, 0.7)

## Nouvelle série depuis le récapitulatif.
func _restart(boxes: Array, serial: bool) -> void:
	if recap != null:
		recap.queue_free()
		recap = null
	all_rewards.clear()
	queue = boxes.duplicate()
	fast = serial
	skip_b.visible = true
	_next_box()

# ---------------------------------------------------------------- effets
func _burst(p: Vector2, col: Color, n: int, spd: float, stars: bool, life: float) -> void:
	for i in range(n):
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * spd * randf_range(0.35, 1.0)
		v.y -= spd * 0.35
		parts.append({"p": p, "v": v, "life": life * randf_range(0.6, 1.0), "max": life, "col": col, "s": randf_range(3.0, 7.0), "star": stars and i % 3 == 0})
	if parts.size() > 220:
		parts = parts.slice(parts.size() - 220)

func _ring(p: Vector2, col: Color, life: float, size_k: float) -> void:
	rings.append({"p": p, "life": life, "max": life, "col": col, "k": size_k})

func _process(dt: float) -> void:
	t += dt
	phase_t += dt
	# série rapide : la box se touche toute seule, les cartes défilent
	if fast:
		_auto += dt
		if phase == "wait" and _auto > 0.16:
			_auto = 0.0
			tap()
		elif phase == "card" and _auto > 0.34:
			tap()
		elif phase == "open" and phase_t > 0.45:
			_next_card()
	elif phase == "open" and phase_t > 0.85:
		_next_card()
	if phase == "wait" and hint.text != "":
		hint.modulate.a = 0.6 + 0.4 * sin(t * 5.0)
	shake = maxf(0.0, shake - dt * 2.2)
	var sh := shake * shake * 14.0
	content.position = Vector2(randf_range(-sh, sh), randf_range(-sh, sh))
	rays_k = maxf(0.0, rays_k - dt * (0.12 if phase != "recap" else 0.0))
	beam_k = maxf(0.0, beam_k - dt * 0.9)
	var i := 0
	while i < parts.size():
		var pa: Dictionary = parts[i]
		pa["life"] -= dt
		if pa["life"] <= 0.0:
			parts.remove_at(i)
			continue
		pa["v"] = (pa["v"] as Vector2) * (1.0 - dt * 1.6) + Vector2(0, 520.0 * dt)
		pa["p"] = (pa["p"] as Vector2) + (pa["v"] as Vector2) * dt
		i += 1
	var j := 0
	while j < rings.size():
		rings[j]["life"] -= dt
		if rings[j]["life"] <= 0.0:
			rings.remove_at(j)
			continue
		j += 1
	fx.queue_redraw()
	rays.queue_redraw()

func _draw_rays() -> void:
	if phase != "recap" and stage.visible:
		# socle : ovale de lumière sous la box
		var base := _mouth() + Vector2(0, stage.size.y * 0.17)
		var col0 := _col()
		rays.draw_set_transform(base, 0.0, Vector2(1.0, 0.26))
		for k in range(6):
			rays.draw_circle(Vector2.ZERO, stage.size.x * (0.42 - k * 0.05), Color(col0, 0.05 + 0.02 * k + 0.1 * rays_k))
		rays.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if rays_k <= 0.01:
		return
	var c := _mouth() if phase != "recap" else Vector2(vs.x * 0.5, vs.y * 0.5)
	var n := 18
	var col := _col().lightened(0.2)
	var rr := vs.x * 1.2
	for k in range(n):
		var a := TAU * k / n + t * 0.25
		var w := 0.06 + 0.03 * sin(k * 2.3)
		var d1 := Vector2(cos(a - w), sin(a - w)) * rr
		var d2 := Vector2(cos(a + w), sin(a + w)) * rr
		rays.draw_polygon(PackedVector2Array([c, c + d1, c + d2]), PackedColorArray([Color(col, 0.22 * rays_k), Color(col, 0.0), Color(col, 0.0)]))

func _draw_fx() -> void:
	# colonne de lumière qui sort de la box
	if beam_k > 0.01:
		var m := _mouth()
		var w := stage.size.x * 0.34 * (0.6 + 0.4 * beam_k)
		var col := _col().lightened(0.4)
		fx.draw_polygon(PackedVector2Array([m + Vector2(-w * 0.35, 0), m + Vector2(w * 0.35, 0), Vector2(m.x + w, -40.0), Vector2(m.x - w, -40.0)]),
			PackedColorArray([Color(col, 0.75 * beam_k), Color(col, 0.75 * beam_k), Color(col, 0.0), Color(col, 0.0)]))
		fx.draw_circle(m, w * 0.5 * beam_k, Color(1, 1, 1, 0.5 * beam_k))
	for rg in rings:
		var k: float = 1.0 - float(rg["life"]) / float(rg["max"])
		var rad: float = 60.0 + 260.0 * float(rg["k"]) * (1.0 - pow(1.0 - k, 3.0))
		var c: Color = rg["col"]
		fx.draw_arc(rg["p"], rad, 0.0, TAU, 48, Color(c, c.a * (1.0 - k)), 10.0 * (1.0 - k) + 2.0, true)
	for pa in parts:
		var a: float = clampf(float(pa["life"]) / float(pa["max"]) * 1.5, 0.0, 1.0)
		var c2: Color = pa["col"]
		var p: Vector2 = pa["p"]
		var s: float = pa["s"]
		if bool(pa["star"]):
			var r := t * 4.0 + s
			var d1 := Vector2(cos(r), sin(r)) * s * 2.2
			var d2 := Vector2(-sin(r), cos(r)) * s * 0.5
			var d3 := Vector2(cos(r), sin(r)) * s * 0.5
			var d4 := Vector2(-sin(r), cos(r)) * s * 2.2
			fx.draw_colored_polygon(PackedVector2Array([p - d1, p - d2, p + d1, p + d2]), Color(c2, a))
			fx.draw_colored_polygon(PackedVector2Array([p - d4, p - d3, p + d4, p + d3]), Color(c2, a))
		else:
			var v: Vector2 = pa["v"]
			fx.draw_line(p, p - v * 0.03, Color(c2, a), s * 0.7, true)

func _draw_pips() -> void:
	if phase != "wait" and phase != "drop":
		return
	var c := Vector2(vs.x * 0.5, 15.0)
	var gap := 34.0
	for i in range(need):
		var p := c + Vector2((i - (need - 1) * 0.5) * gap, 0)
		pips.draw_circle(p, 11.0, UI.INK)
		pips.draw_circle(p, 8.0, _col() if i < taps else Color(_col(), 0.25))
