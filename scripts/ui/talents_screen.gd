extends Control
## Écran TALENTS du Relais : l'arbre des talents permanents (talents.gd), cinq branches qui poussent depuis
## leur socle. Nœuds ronds à pictogramme, liens qui s'allument, défilement au doigt (glisser, élan, butée
## élastique). Toucher un nœud ouvre sa fiche (effet actuel → suivant, coût, AMÉLIORER). L'achat : tickets qui
## volent du compteur vers le nœud, compteur qui défile, éclat, gerbe d'étoiles, liens suivants qui s'allument.
## Tout est dessiné en code dans deux passes (arbre, effets) ; quelques pictogrammes et la fiche sont des nœuds.
## L'arbre est découpé en calques (fond, liens, socles, deux par nœud) redessinés seulement quand ce qu'ils
## montrent change : le fond une fois, un nœud figé jamais, un nœud animé (halo, couronne) à chaque image.

const UI = preload("res://scripts/ui.gd")
const Fx = preload("res://scripts/ui/fx.gd")
const Icon = preload("res://scripts/icon.gd")
const Talents = preload("res://scripts/talents.gd")
const Save = preload("res://scripts/save.gd")
const CardScript = preload("res://scripts/ui/card.gd")

const R := 40.0  # rayon d'un nœud (80 px du viewport = 120 px en 1080p)
const RK := 48.0  # nœud clé (dernier rang de chaque branche)
const GY := 146.0  # écart entre deux rangs
const ROW4_Y := 132.0  # rang du haut, sous le bandeau
const HEAD_H := 78.0
const FICHE_W := 384.0
const DRAG_START := 14.0

var main: Node
var profile: Dictionary
var _view: Control  # zone tactile plein écran
var _canvas: Control  # l'arbre, déplacé par le défilement
var _fx: Control  # effets additifs (écran)
var _fx_txt: Control  # textes flottants (écran)
var _fiche: PanelContainer
var _fiche_box: VBoxContainer
var _fiche_open := false
var _tk_chip: PanelContainer
var _tk_label: Label
var _sh_chip: PanelContainer
var _prog: Label
var _icons := {}  # id -> Icon
var _pos := {}  # id -> centre dans l'arbre
var _links := []  # {from, to, pts, col, need, id}
var _plates := []  # {pos, branch}
var _canvas_size := Vector2.ZERO
var _bg: Control  # calques de l'arbre, dans l'ordre de dessin (enfants de _canvas, sous les pictogrammes)
var _plates_l: Control
var _layer_a := {}  # id -> calque du dessous (halo, anneau d'achat, ombre, couronne, sélection)
var _layer_b := {}  # id -> calque du nœud (corps, niveaux, pastille, nom)
var _sig_a := {}
var _sig_b := {}
var _info := {}  # id -> {st, lv, buyable, col} : recalculé quand le profil change (_profile_fp)
var _fp := []
var _fx_n := 0
var _band := 260.0  # largeur d'une branche : plus large sur les écrans allongés
var _sel := ""
var _t := 0.0
var _pan := Vector2.ZERO
var _vel := Vector2.ZERO
var _press := false
var _drag := false
var _press_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _last_t := 0.0
var _goto := Vector2.INF  # cible de défilement automatique (nœud choisi)
var _shake := 0.0
var _pop := {}  # id -> 1 au moment de l'achat, décroît
var _flash := {}
var _wake := {}  # id -> 1 quand le nœud se déverrouille
var _deny := {}  # id -> 1 quand l'achat est refusé (le nœud tremble)
var _parts := []  # particules (écran)
var _texts := []  # textes flottants (écran)
var _shown_tickets := 0

func build(m: Node, fresh: bool = true) -> void:
	UI.load_fonts()
	main = m
	profile = m.profile
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.dim(0.93))
	_build_tree()
	_build_header()
	_build_fiche()
	_fx = Control.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_fx.material = add
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_fx_txt = Control.new()
	_fx_txt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_txt.draw.connect(_draw_texts)
	add_child(_fx_txt)
	_shown_tickets = int(profile["tickets"])
	_refresh_header()
	# départ : arbre centré, en haut (les nœuds clés sous le bandeau)
	var vs := _vs()
	_pan = Vector2((vs.x - _canvas_size.x) * 0.5, 0.0)
	_pan = _clamped(_pan)
	_canvas.position = _pan
	if fresh:
		Fx.screen_in(self)
		_canvas.modulate.a = 0.0
		var tw := Fx._tw(_canvas)
		tw.tween_property(_canvas, "modulate:a", 1.0, 0.35)
		# les nœuds s'allument du bas vers le haut
		for id in _pos.keys():
			var row := float(Talents.talent(id)["pos"].y)
			_wake[id] = 1.0 + row * 0.18

func _vs() -> Vector2:
	return get_viewport().get_visible_rect().size

# ---------------------------------------------------------------- construction
func _node_r(id: String) -> float:
	return RK if float(Talents.talent(id)["pos"].y) >= 4.0 else R

func _build_tree() -> void:
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_on_input)
	add_child(_view)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_canvas)
	_band = clampf((_vs().x - 200.0) / 4.5, 250.0, 300.0)
	var half := 2.25 * _band + 90.0
	var cx := half
	var row1_y := ROW4_Y + 3.0 * GY + 12.0
	_canvas_size = Vector2(half * 2.0, row1_y + 128.0)
	_canvas.size = _canvas_size
	for t in Talents.TALENTS:
		var id := String(t["id"])
		var b := Talents.branch(String(t["branch"]))
		var row := float(t["pos"].y)
		var y := row1_y - (row - 1.0) * GY - (12.0 if row >= 4.0 else 0.0)
		_pos[id] = Vector2(cx + (float(b["x"]) + float(t["pos"].x) * 0.5) * _band, y)
	# socles des branches, sous le premier rang
	for b in Talents.BRANCHES:
		_plates.append({"pos": Vector2(cx + float(b["x"]) * _band, row1_y + 100.0), "branch": b})
	# liens : prérequis → talent ; socle → premier talent
	for t in Talents.TALENTS:
		var id := String(t["id"])
		var col := Talents.color(id)
		var req: Dictionary = t["req"]
		if req.is_empty():
			for pl in _plates:
				if pl["branch"]["id"] == t["branch"]:
					_links.append({"from": "", "to": id, "need": 0, "col": col, "pts": _curve(pl["pos"] + Vector2(0, -20), _pos[id])})
		for r in req.keys():
			_links.append({"from": String(r), "to": id, "need": int(req[r]), "col": col, "pts": _curve(_pos[String(r)], _pos[id])})
	# calques de l'arbre (sous les pictogrammes)
	_bg = _layer(func(cv): _draw_bg(cv))
	for l in _links:
		# chaque lien : tracé (figé) puis énergie qui y monte (animée), dans l'ordre des liens
		l["lit"] = false
		l["line_l"] = _layer(func(cv): _draw_link(cv, l))
		l["dots_l"] = _layer(func(cv): _draw_link_dots(cv, l))
	_plates_l = _layer(func(cv): _draw_plates(cv))
	for t in Talents.TALENTS:
		var id := String(t["id"])
		_layer_a[id] = _layer(func(cv): _draw_node_a(cv, id))
		_layer_b[id] = _layer(func(cv): _draw_node_b(cv, id))
	_refresh_info()
	# pictogrammes
	for t in Talents.TALENTS:
		var id := String(t["id"])
		var s := 54.0 if _node_r(id) > R else 46.0
		var ic := Icon.new(String(t["icon"]), Talents.color(id), s)
		ic.size = Vector2(s, s)
		ic.position = _pos[id] - Vector2(s, s) * 0.5
		ic.pivot_offset = Vector2(s, s) * 0.5
		_canvas.add_child(ic)
		_icons[id] = ic

func _layer(fn: Callable) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = _canvas_size
	c.draw.connect(fn.bind(c))
	_canvas.add_child(c)
	return c

## Courbe en S, du parent (en bas) vers l'enfant (en haut).
func _curve(a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var dy := (a.y - b.y) * 0.55
	var c1 := a + Vector2(0, -dy)
	var c2 := b + Vector2(0, dy)
	for i in range(25):
		var k := i / 24.0
		var u := 1.0 - k
		pts.append(a * u * u * u + c1 * 3.0 * u * u * k + c2 * 3.0 * u * k * k + b * k * k * k)
	return pts

func _build_header() -> void:
	var ins := UI.safe_insets(get_viewport())
	var vs := _vs()
	var shade := Control.new()
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_preset(Control.PRESET_TOP_WIDE)
	shade.size = Vector2(vs.x, HEAD_H + 30)
	shade.draw.connect(func():
		var w := shade.size.x
		var c0 := Color(UI.INK, 0.94)
		var c1 := Color(UI.INK, 0.0)
		shade.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, HEAD_H - 6), Vector2(0, HEAD_H - 6)]), PackedColorArray([c0, c0, c0, c0]))
		shade.draw_polygon(PackedVector2Array([Vector2(0, HEAD_H - 6), Vector2(w, HEAD_H - 6), Vector2(w, HEAD_H + 30), Vector2(0, HEAD_H + 30)]), PackedColorArray([c0, c0, c1, c1]))
		shade.draw_rect(Rect2(0, HEAD_H - 7, w, 2), Color(UI.GOLD, 0.25)))
	add_child(shade)
	var left := UI.hbox(16)
	left.position = Vector2(float(ins["left"]) + 4.0, 8.0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	var ic := Icon.new("tree", UI.GOLD, 44.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(ic)
	var tv := UI.vbox(-6)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(tv)
	var title := UI.title("TALENTS", 40, UI.TEXT, UI.GOLD)
	tv.add_child(title)
	_prog = UI.label("", 18, UI.MUTED)
	tv.add_child(_prog)
	Fx.shine(title, 300.0, 3.2, 0.5)
	var right := UI.hbox(12)
	right.alignment = BoxContainer.ALIGNMENT_END
	right.anchor_left = 0.4
	right.anchor_right = 1.0
	right.offset_right = -float(ins["right"])
	right.offset_top = 8.0
	right.offset_bottom = 72.0
	add_child(right)
	_sh_chip = UI.chip("shard", "", UI.ACCENT)
	_sh_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(_sh_chip)
	_tk_chip = UI.chip("coin", "", UI.GOLD)
	_tk_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tk_label = _tk_chip.get_meta("label")
	_tk_label.add_theme_font_override("font", UI.TITLE)
	_tk_label.add_theme_font_size_override("font_size", 24)
	_tk_label.custom_minimum_size = Vector2(70, 0)
	right.add_child(_tk_chip)
	var back := UI.primary("RETOUR", 24)
	back.custom_minimum_size = Vector2(150, 64)
	back.pressed.connect(func(): main.show_base())
	right.add_child(back)

func _build_fiche() -> void:
	var ins := UI.safe_insets(get_viewport())
	_fiche = PanelContainer.new()
	_fiche.anchor_left = 1.0
	_fiche.anchor_right = 1.0
	_fiche.anchor_bottom = 1.0
	_fiche.offset_left = -FICHE_W - float(ins["right"])
	_fiche.offset_right = -float(ins["right"])
	_fiche.offset_top = HEAD_H + 6.0
	_fiche.offset_bottom = -float(ins["bottom"]) - 6.0
	_fiche.mouse_filter = Control.MOUSE_FILTER_STOP
	_fiche.visible = false
	add_child(_fiche)
	_fiche_box = UI.vbox(10)
	_fiche.add_child(_fiche_box)

# ---------------------------------------------------------------- état
## Empreinte du profil (tickets, éclats, niveaux) : l'état des nœuds n'est recalculé que si elle change.
func _profile_fp() -> Array:
	return [int(profile.get("tickets", 0)), int(profile.get("shards", 0)), Talents.levels(profile).hash()]

func _refresh_info() -> void:
	_fp = _profile_fp()
	for t in Talents.TALENTS:
		var id := String(t["id"])
		_info[id] = {"st": _state(id), "lv": Talents.level(profile, id), "buyable": Talents.block_reason(profile, id) == "", "col": Talents.color(id)}
	for l in _links:
		var from := String(l["from"])
		l["lit"] = from == "" or Talents.level(profile, from) >= int(l["need"])
		(l["line_l"] as Control).queue_redraw()
		(l["dots_l"] as Control).queue_redraw()
	_plates_l.queue_redraw()

func _state(id: String) -> String:
	var lv := Talents.level(profile, id)
	if lv >= int(Talents.talent(id)["max"]):
		return "max"
	if lv > 0:
		return "owned"
	if Talents.unlocked(profile, id):
		return "open"
	return "locked"

func _refresh_header() -> void:
	_prog.text = "%d / %d niveaux  ·  progression permanente" % [Talents.owned_levels(profile), Talents.total_levels()]
	var sl: Label = _sh_chip.get_meta("label")
	var free := Talents.shards_free(profile)
	sl.text = "%d éclat%s" % [free, "s" if free > 1 else ""]
	_tk_label.text = "%d" % int(profile["tickets"])

# ---------------------------------------------------------------- fiche
## Sélectionne un talent : fiche à droite, l'arbre glisse pour garder le nœud visible.
func select(id: String) -> void:
	if Talents.talent(id).is_empty():
		return
	_sel = id
	if main != null and main.get("sfx") != null:
		main.sfx.play("click", 1.15, -6.0)
	_fill_fiche()
	if not _fiche_open:
		_fiche_open = true
		_fiche.visible = true
		Fx.slide_in(_fiche, Vector2(FICHE_W * 0.6, 0), 0.0, 0.32)
	_bump_icon(id, 0.12)
	_follow(id)

func close_fiche() -> void:
	_sel = ""
	if not _fiche_open:
		return
	_fiche_open = false
	var tw := Fx._tw(_fiche)
	tw.tween_property(_fiche, "modulate:a", 0.0, 0.14)
	tw.tween_callback(func():
		if not _fiche_open:
			_fiche.visible = false)
	_goto = _clamped(_pan)

func _follow(id: String) -> void:
	var vs := _vs()
	var p: Vector2 = _pos[id] + _pan
	var target := _pan
	var right_edge := vs.x - (FICHE_W + 60.0 if _fiche_open else 40.0)
	if p.x > right_edge - 70.0:
		target.x -= p.x - (right_edge - 90.0)
	if p.x < 100.0:
		target.x += 120.0 - p.x
	if p.y < HEAD_H + 70.0:
		target.y += HEAD_H + 80.0 - p.y
	_goto = _clamped(target)

func _fill_fiche() -> void:
	for c in _fiche_box.get_children():
		_fiche_box.remove_child(c)
		c.queue_free()
	var id := _sel
	var t := Talents.talent(id)
	var col := Talents.color(id)
	var lv := Talents.level(profile, id)
	var mx := int(t["max"])
	var st := _state(id)
	var s := UI.flat(Color("#122042"), col.darkened(0.35), 22, 3)
	s.border_width_top = 6
	s.border_color = col
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 14
	_fiche.add_theme_stylebox_override("panel", s)
	# tête : pastille, nom, branche et niveau
	var head := UI.hbox(14)
	_fiche_box.add_child(head)
	var ring := Panel.new()
	ring.custom_minimum_size = Vector2(84, 84)
	ring.add_theme_stylebox_override("panel", UI.flat(col.darkened(0.6) if st != "max" else col, col, 42, 4))
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(ring)
	var ic := Icon.new(String(t["icon"]), UI.INK if st == "max" else col.lightened(0.2), 54.0)
	ic.position = Vector2(15, 15)
	ring.add_child(ic)
	var hv := UI.vbox(4)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(hv)
	var name_l := UI.title(String(t["name"]), 26 if String(t["name"]).length() < 13 else 22, UI.TEXT, col)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(name_l)
	var tags := UI.hbox(6)
	hv.add_child(tags)
	tags.add_child(UI.tag(String(Talents.branch(String(t["branch"]))["name"]), col.darkened(0.15), UI.INK, 15))
	tags.add_child(UI.tag("MAX" if st == "max" else "NIV. %d / %d" % [lv, mx], UI.GOLD if st == "max" else Color("#2A3F6E"), UI.INK if st == "max" else UI.TEXT, 15))
	var close := UI.button("✕", 20, UI.MUTED)
	close.custom_minimum_size = Vector2(52, 52)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var cs: StyleBoxFlat = close.get_theme_stylebox("normal")
	cs.content_margin_left = 0
	cs.content_margin_right = 0
	close.pressed.connect(close_fiche)
	head.add_child(close)
	var d := UI.label(String(t["desc"]), 20, Color("#C4D2E4"))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fiche_box.add_child(d)
	# effet actuel → suivant
	var eff := PanelContainer.new()
	var es := UI.flat(Color(UI.INK, 0.55), Color(col, 0.25), 14, 2)
	es.content_margin_top = 10
	es.content_margin_bottom = 10
	es.content_margin_left = 14
	es.content_margin_right = 14
	eff.add_theme_stylebox_override("panel", es)
	_fiche_box.add_child(eff)
	var ev := UI.vbox(2)
	eff.add_child(ev)
	ev.add_child(UI.label("ACTUEL", 15, UI.MUTED))
	var now_l := UI.label(Talents.effect_text(id, lv) if lv > 0 else "Rien pour l'instant", 21, UI.TEXT if lv > 0 else UI.MUTED)
	now_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ev.add_child(now_l)
	if st != "max":
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(0, 4)
		ev.add_child(sp)
		ev.add_child(UI.label("NIVEAU %d  →" % (lv + 1), 15, col))
		var nx := UI.title(Talents.effect_text(id, lv + 1), 19, col.lightened(0.25), col)
		nx.add_theme_constant_override("shadow_offset_y", 0)
		nx.add_theme_constant_override("outline_size", 3)
		nx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ev.add_child(nx)
	else:
		ev.add_child(UI.label("Talent au maximum.", 18, UI.GOLD))
	var miss := Talents.missing(profile, id)
	if st == "locked" and not miss.is_empty():
		var ml := UI.label("Requiert : " + ", ".join(miss), 19, Color("#FF7A9A"))
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_fiche_box.add_child(ml)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fiche_box.add_child(grow)
	if st == "max":
		var done := UI.title("★  AU MAXIMUM  ★", 24, UI.GOLD, UI.ORANGE, HORIZONTAL_ALIGNMENT_CENTER)
		_fiche_box.add_child(done)
		return
	# coût et bouton
	var c := Talents.cost(id, lv)
	var reason := Talents.block_reason(profile, id)
	var cost_row := UI.hbox(10)
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_fiche_box.add_child(cost_row)
	cost_row.add_child(UI.label("COÛT", 17, UI.MUTED))
	cost_row.add_child(Icon.new("coin", UI.GOLD, 30.0))
	var cl := UI.title("%d" % int(c["tickets"]), 30, UI.GOLD if reason != "tickets" else Color("#FF6A80"), UI.ORANGE)
	cl.add_theme_constant_override("shadow_offset_y", 2)
	cost_row.add_child(cl)
	if int(c["shards"]) > 0:
		cost_row.add_child(UI.label("+", 24, UI.MUTED))
		cost_row.add_child(Icon.new("shard", UI.ACCENT, 30.0))
		var sl := UI.title("%d" % int(c["shards"]), 30, UI.ACCENT if reason != "shards" else Color("#FF6A80"), UI.ACCENT)
		sl.add_theme_constant_override("shadow_offset_y", 2)
		cost_row.add_child(sl)
	var txt := "AMÉLIORER" if lv > 0 else "DÉBLOQUER"
	match reason:
		"locked":
			txt = "VERROUILLÉ"
		"tickets":
			txt = "IL MANQUE %d" % (int(c["tickets"]) - int(profile["tickets"]))
		"shards":
			txt = "FINIS UN MONDE"
	var up := UI.primary(txt, 28)
	up.custom_minimum_size = Vector2(0, 78)
	up.disabled = reason != ""
	up.pressed.connect(buy_selected)
	_fiche_box.add_child(up)
	if reason == "shards":
		var hint := UI.label("Un éclat du Cœur par monde terminé.", 17, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		_fiche_box.add_child(hint)
	elif reason == "":
		var halo := Fx.halo(Color(UI.ORANGE, 0.4), Vector2(10, 10))
		halo.show_behind_parent = true
		up.add_child(halo)
		up.resized.connect(func():
			halo.size = up.size * Vector2(1.2, 2.4)
			halo.position = (up.size - halo.size) * 0.5)
		Fx.pulse(halo, 0.4, 0.9, 1.3)
		Fx.shine(up, 360.0, 2.2, 0.45)

# ---------------------------------------------------------------- achat
func buy_selected() -> void:
	var id := _sel
	if id == "":
		return
	var reason := Talents.block_reason(profile, id)
	if reason != "":
		_deny[id] = 1.0
		main.sfx.play("click", 0.6, -4.0)
		if reason == "tickets":
			Fx.bump(_tk_chip, 0.12)
		return
	var before := {}
	for t in Talents.TALENTS:
		before[String(t["id"])] = Talents.unlocked(profile, String(t["id"]))
	var old_tk := int(profile["tickets"])
	Talents.buy(profile, id)
	Save.save_profile(profile)
	main._apply_profile_to_hero()
	var maxed := _state(id) == "max"
	main.sfx.play("pick", 1.2, -4.0)
	# compteur qui défile, tickets qui volent du compteur vers le nœud
	Fx.count(_tk_label, old_tk, int(profile["tickets"]), 0.7, 0.0)
	Fx.bump(_tk_chip, 0.18)
	var from := _tk_chip.get_global_rect().get_center() - get_global_rect().position
	var to: Vector2 = _pos[id] + _pan
	var n := clampi(int(float(old_tk - int(profile["tickets"])) / 12.0) + 5, 6, 16)
	for i in range(n):
		_parts.append({"kind": "coin", "a": from + Vector2(randf_range(-20, 20), randf_range(-8, 8)), "b": to, "t": -0.025 * i, "dur": 0.36, "arc": randf_range(-140.0, 140.0)})
	var tw := create_tween()
	tw.tween_interval(0.36 + 0.025 * n * 0.5)
	tw.tween_callback(func(): _impact(id, maxed, before))
	_refresh_header()
	_tk_label.text = "%d" % old_tk  # le compteur part de l'ancienne valeur (Fx.count)
	_fill_fiche()

func _impact(id: String, maxed: bool, before: Dictionary) -> void:
	var col := Talents.color(id)
	var c: Vector2 = _pos[id] + _pan
	_pop[id] = 1.0
	_flash[id] = 1.0
	_shake = 0.35 if not maxed else 0.6
	main.sfx.play("chest" if maxed else "level", 1.25 if not maxed else 1.0, -3.0)
	var m := 22 if not maxed else 40
	for i in range(m):
		var a := TAU * i / m + randf() * 0.3
		var sp := randf_range(240.0, 520.0) * (1.3 if maxed else 1.0)
		_parts.append({"kind": "star", "p": c, "v": Vector2(cos(a), sin(a)) * sp, "life": 0.0, "max": randf_range(0.45, 0.8), "r": randf_range(7.0, 14.0), "col": col.lightened(0.35) if i % 3 else Color(1, 0.95, 0.75)})
	_parts.append({"kind": "ring", "p": c, "life": 0.0, "max": 0.5, "r0": _node_r(id), "r1": _node_r(id) + 120.0, "col": col.lightened(0.3)})
	if maxed:
		_parts.append({"kind": "ring", "p": c, "life": -0.1, "max": 0.7, "r0": _node_r(id), "r1": _node_r(id) + 220.0, "col": UI.GOLD})
	var lv := Talents.level(profile, id)
	_texts.append({"text": "MAX !" if maxed else "NIV. %d" % lv, "p": c + Vector2(0, -_node_r(id) - 18.0), "life": 0.0, "max": 1.1, "col": UI.GOLD if maxed else col.lightened(0.3), "size": 34 if maxed else 28})
	# liens qui s'allument vers les talents qui viennent de s'ouvrir
	var delay := 0.0
	for l in _links:
		if l["from"] == id and Talents.level(profile, id) == int(l["need"]):
			_parts.append({"kind": "comet", "pts": l["pts"], "t": -delay, "dur": 0.5, "col": col.lightened(0.4)})
			var to := String(l["to"])
			if not bool(before.get(to, false)) and Talents.unlocked(profile, to):
				var tw := create_tween()
				tw.tween_interval(0.5 + delay)
				tw.tween_callback(func():
					_wake[to] = 1.0
					main.sfx.play("pick", 1.5, -10.0)
					_parts.append({"kind": "ring", "p": _pos[to] + _pan, "life": 0.0, "max": 0.45, "r0": _node_r(to), "r1": _node_r(to) + 70.0, "col": Talents.color(to)}))
			delay += 0.12
	_refresh_header()
	if _sel == id:
		_fill_fiche()

func _bump_icon(id: String, amount: float) -> void:
	var ic: Control = _icons.get(id)
	if ic == null:
		return
	var tw := Fx._tw(ic)
	tw.tween_property(ic, "scale", Vector2.ONE * (1.0 + amount), 0.07)
	tw.tween_property(ic, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ---------------------------------------------------------------- défilement au doigt
func _bounds() -> Rect2:
	var vs := _vs()
	var room_w := vs.x - (FICHE_W + 30.0 if _fiche_open else 0.0)
	var min_x := room_w - _canvas_size.x - 30.0
	var max_x := 30.0
	if _canvas_size.x + 60.0 < room_w:
		min_x = (room_w - _canvas_size.x) * 0.5
		max_x = min_x
	var min_y := vs.y - _canvas_size.y - 10.0
	var max_y := 10.0
	if min_y > max_y:
		min_y = (vs.y - _canvas_size.y) * 0.5
		max_y = min_y
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

func _clamped(p: Vector2) -> Vector2:
	var b := _bounds()
	return Vector2(clampf(p.x, b.position.x, b.end.x), clampf(p.y, b.position.y, b.end.y))

## Au-delà des bords, le défilement résiste (élastique).
func _rubber(p: Vector2) -> Vector2:
	var c := _clamped(p)
	return c + (p - c) * 0.35

func _on_input(ev: InputEvent) -> void:
	var pos := Vector2.INF
	var pressed := false
	var released := false
	if ev is InputEventScreenTouch:
		if (ev as InputEventScreenTouch).index != 0:
			return
		pos = (ev as InputEventScreenTouch).position
		pressed = (ev as InputEventScreenTouch).pressed
		released = not pressed
	elif ev is InputEventScreenDrag:
		if (ev as InputEventScreenDrag).index != 0:
			return
		pos = (ev as InputEventScreenDrag).position
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			var d := Vector2.ZERO
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					d = Vector2(0, 60)
				MOUSE_BUTTON_WHEEL_DOWN:
					d = Vector2(0, -60)
				MOUSE_BUTTON_WHEEL_LEFT:
					d = Vector2(60, 0)
				MOUSE_BUTTON_WHEEL_RIGHT:
					d = Vector2(-60, 0)
			if mb.shift_pressed:
				d = Vector2(d.y, d.x)
			_goto = _clamped((_goto if _goto != Vector2.INF else _pan) + d)
		return
	else:
		return
	if pressed:
		_press = true
		_drag = false
		_press_pos = pos
		_last_pos = pos
		_last_t = _t
		_vel = Vector2.ZERO
		_goto = Vector2.INF
	elif released:
		if not _press:
			return
		_press = false
		if not _drag:
			_tap(pos)
		_drag = false
	elif _press:
		if not _drag and pos.distance_to(_press_pos) > DRAG_START:
			_drag = true
			_last_pos = pos
		if _drag:
			var dt := maxf(0.001, _t - _last_t)
			var d := pos - _last_pos
			_pan = _rubber(_pan + d)
			_vel = _vel.lerp(d / dt, 0.5)
			_last_pos = pos
			_last_t = _t

func _tap(pos: Vector2) -> void:
	var best := ""
	var best_d := 1e9
	for id in _pos.keys():
		var d: float = (_pos[id] + _pan).distance_to(pos)
		if d < _node_r(id) + 16.0 and d < best_d:
			best = id
			best_d = d
	if best != "":
		select(best)
	elif _fiche_open:
		close_fiche()

# ---------------------------------------------------------------- boucle
func _process(dt: float) -> void:
	_t += dt
	if not _press:
		if _goto != Vector2.INF:
			_pan = _pan.lerp(_goto, minf(1.0, dt * 10.0))
			if _pan.distance_to(_goto) < 0.5:
				_pan = _goto
				_goto = Vector2.INF
		elif _vel.length() > 5.0:
			_pan = _rubber(_pan + _vel * dt)
			_vel *= exp(-dt * 4.5)
			if _clamped(_pan) != _pan:
				_vel *= exp(-dt * 12.0)
		else:
			_vel = Vector2.ZERO
			var c := _clamped(_pan)
			_pan = _pan.lerp(c, minf(1.0, dt * 12.0))
	_shake = maxf(0.0, _shake - dt * 1.6)
	var sh := Vector2.ZERO
	if _shake > 0.0:
		sh = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 10.0
	_canvas.position = (_pan + sh).round()
	# animations des nœuds : retirées une fois finies (une valeur absente vaut 0)
	for dict in [_pop, _flash, _deny]:
		for k in dict.keys():
			dict[k] = maxf(0.0, float(dict[k]) - dt * 2.2)
			if dict[k] <= 0.0:
				dict.erase(k)
	for k in _wake.keys():
		_wake[k] = maxf(0.0, float(_wake[k]) - dt * 1.8)
		if _wake[k] <= 0.0:
			_wake.erase(k)
	_update_parts(dt)
	if _profile_fp() != _fp:
		_refresh_info()
	_update_layers()
	# effets : redessinés tant qu'il y en a, une dernière fois pour les effacer
	var n := _parts.size() + _texts.size()
	if n > 0 or _fx_n > 0:
		_fx.queue_redraw()
		_fx_txt.queue_redraw()
	_fx_n = n

## Calques des nœuds : un calque animé est redessiné à chaque image, un calque figé quand son état change.
func _update_layers() -> void:
	for l in _links:
		if l["lit"]:
			(l["dots_l"] as Control).queue_redraw()  # énergie qui monte le long des liens allumés
	for id in _layer_a.keys():
		var inf: Dictionary = _info[id]
		var st := String(inf["st"])
		var pop := float(_pop.get(id, 0.0))
		var dn := float(_deny.get(id, 0.0))
		var anim: bool = st == "max" or st == "owned" or bool(inf["buyable"]) or id == _sel or (_node_r(id) > R and st != "locked")
		var sa := [st, inf["buyable"], pop, dn, id == _sel, _t if anim else 0.0]
		if sa != _sig_a.get(id):
			_sig_a[id] = sa
			(_layer_a[id] as Control).queue_redraw()
		var w := float(_wake.get(id, 0.0))
		var sb := [st, inf["lv"], pop, dn, w if w <= 1.0 else 0.0, float(_flash.get(id, 0.0))]
		if sb != _sig_b.get(id):
			_sig_b[id] = sb
			(_layer_b[id] as Control).queue_redraw()
			_update_icon(id)

## Pictogramme d'un nœud : couleur de l'état, éclat au réveil, gonfle à l'achat, tremble au refus
## (mêmes entrées que le calque du nœud : mis à jour quand elles changent).
func _update_icon(id: String) -> void:
	var ic: Control = _icons[id]
	var st := String(_info[id]["st"])
	var col: Color = _info[id]["col"]
	var c: Color
	match st:
		"max":
			c = UI.INK
		"owned":
			c = col.lightened(0.45)
		"open":
			c = col
		_:
			c = Color(col.lerp(UI.MUTED, 0.5), 0.36)
	var w := float(_wake.get(id, 0.0))
	if w > 0.0 and w <= 1.0 and st != "locked":
		c = c.lerp(Color.WHITE, w * 0.7)
	if ic.get("color") != c:
		ic.set("color", c)
		ic.queue_redraw()
	var s := 1.0 + 0.3 * sin(float(_pop.get(id, 0.0)) * PI)
	var dn := float(_deny.get(id, 0.0))
	ic.scale = Vector2.ONE * s
	var s0: float = ic.size.x
	ic.position = _pos[id] - Vector2(s0, s0) * 0.5 + Vector2(sin(dn * 40.0) * 8.0 * dn, 0)

func _update_parts(dt: float) -> void:
	var keep := []
	for p in _parts:
		match String(p["kind"]):
			"coin", "comet":
				p["t"] += dt
				if p["t"] < p["dur"]:
					keep.append(p)
			_:
				p["life"] += dt
				if p["life"] < p["max"]:
					if p.has("v"):
						p["p"] += p["v"] * dt
						p["v"] *= exp(-dt * 4.0)
					keep.append(p)
	_parts = keep
	var keep_t := []
	for tx in _texts:
		tx["life"] += dt
		if tx["life"] < tx["max"]:
			keep_t.append(tx)
	_texts = keep_t

# ---------------------------------------------------------------- dessin de l'arbre
## Fond : pointillés et colonnes de couleur des branches (dessiné une fois).
func _draw_bg(cv: Control) -> void:
	var sz := _canvas_size
	for gx in range(0, int(sz.x) + 1, 40):
		for gy in range(0, int(sz.y) + 1, 40):
			cv.draw_rect(Rect2(gx - 1, gy - 1, 2, 2), Color(0.5, 0.65, 1.0, 0.07))
	for pl in _plates:
		var col: Color = pl["branch"]["col"]
		var x: float = pl["pos"].x
		var top := ROW4_Y - RK - 30.0
		var bot: float = pl["pos"].y
		cv.draw_polygon(PackedVector2Array([Vector2(x - _band * 0.47, top), Vector2(x + _band * 0.47, top), Vector2(x + _band * 0.47, bot), Vector2(x - _band * 0.47, bot)]),
			PackedColorArray([Color(col, 0.0), Color(col, 0.0), Color(col, 0.07), Color(col, 0.07)]))

func _draw_link(cv: Control, l: Dictionary) -> void:
	var pts: PackedVector2Array = l["pts"]
	var col: Color = l["col"]
	var from := String(l["from"])
	var lit: bool = l["lit"]
	var part := from != "" and not lit and Talents.level(profile, from) > 0
	cv.draw_polyline(pts, Color(UI.INK, 0.9), 12.0, true)
	if lit:
		cv.draw_polyline(pts, Color(col, 0.16), 22.0, true)
		cv.draw_polyline(pts, col.darkened(0.1), 7.0, true)
		cv.draw_polyline(pts, Color(col.lightened(0.5), 0.7), 2.5, true)
	elif part:
		cv.draw_polyline(pts, Color(col, 0.38), 6.0, true)
		var lv := Talents.level(profile, from)
		var f2 := float(lv) / float(maxi(1, int(l["need"])))
		var sub := PackedVector2Array()
		for i in range(int(round(f2 * (pts.size() - 1))) + 1):
			sub.append(pts[i])
		if sub.size() > 1:
			cv.draw_polyline(sub, col.darkened(0.1), 7.0, true)
	else:
		cv.draw_polyline(pts, Color("#1E2E52"), 6.0, true)
		cv.draw_polyline(pts, Color(col, 0.16), 4.0, true)

## Énergie qui monte le long d'un lien allumé.
func _draw_link_dots(cv: Control, l: Dictionary) -> void:
	if not l["lit"]:
		return
	var pts: PackedVector2Array = l["pts"]
	var col: Color = l["col"]
	for k in range(3):
		var f := fmod(_t * 0.55 + k / 3.0 + pts[0].x * 0.0013, 1.0)
		var q := _along(pts, f)
		cv.draw_circle(q, 5.0, Color(col.lightened(0.6), 0.85 * sin(f * PI)))

## Socles des branches : nom et niveaux pris sur le total de la branche.
func _draw_plates(cv: Control) -> void:
	var font := UI.TITLE
	for pl in _plates:
		var b: Dictionary = pl["branch"]
		var col: Color = b["col"]
		var p: Vector2 = pl["pos"]
		var own := 0
		var tot := 0
		for t in Talents.TALENTS:
			if t["branch"] == b["id"]:
				own += Talents.level(profile, String(t["id"]))
				tot += int(t["max"])
		var w := 196.0
		var r := Rect2(p.x - w * 0.5, p.y - 22.0, w, 44.0)
		_round_rect(cv, Rect2(r.position + Vector2(0, 5), r.size), 18.0, Color(0, 0, 0, 0.45))
		_round_rect(cv, r, 18.0, col.darkened(0.55))
		_round_rect(cv, Rect2(r.position + Vector2(3, 3), r.size - Vector2(6, 9)), 15.0, Color("#101C38"))
		cv.draw_rect(Rect2(r.position.x + 18, r.position.y + 3, w - 36, 3), Color(col, 0.8))
		cv.draw_string(font, Vector2(r.position.x, p.y + 6.0), String(b["name"]), HORIZONTAL_ALIGNMENT_CENTER, w - 54.0, 18, col.lightened(0.15))
		cv.draw_string(UI.BODY, Vector2(r.position.x + w - 62.0, p.y + 6.0), "%d/%d" % [own, tot], HORIZONTAL_ALIGNMENT_RIGHT, 50.0, 18, UI.MUTED if own < tot else UI.GOLD)

## Centre (le nœud tremble quand l'achat est refusé) et rayon (il gonfle à l'achat) d'un nœud.
func _node_c(id: String) -> Vector2:
	var dn := float(_deny.get(id, 0.0))
	return _pos[id] + Vector2(sin(dn * 40.0) * 8.0 * dn, 0)

func _node_rr(id: String) -> float:
	return _node_r(id) * (1.0 + 0.22 * sin(float(_pop.get(id, 0.0)) * PI))

## Dessous d'un nœud : halo, anneau d'achat possible, ombre, couronne crantée, tirets de sélection.
func _draw_node_a(cv: Control, id: String) -> void:
	var inf: Dictionary = _info[id]
	var col: Color = inf["col"]
	var st := String(inf["st"])
	var key := _node_r(id) > R
	var r := _node_rr(id)
	var c := _node_c(id)
	var buyable: bool = inf["buyable"]
	# halo
	if st == "max" or st == "owned":
		var hs := r * (3.4 if st == "max" else 2.4)
		var ha := (0.42 if st == "max" else 0.2) + 0.08 * sin(_t * 2.4 + c.x * 0.01)
		cv.draw_texture_rect(Fx.halo_texture(), Rect2(c - Vector2(hs, hs) * 0.5, Vector2(hs, hs)), false, Color(col, ha))
	if buyable:
		var pa := 0.35 + 0.35 * sin(_t * 4.0)
		cv.draw_arc(c, r + 17.0 + 2.0 * sin(_t * 4.0), 0.0, TAU, 48, Color(UI.GOLD, pa), 3.0, true)
	# ombre, tranche, face
	cv.draw_circle(c + Vector2(0, 6), r + 6.0, Color(0, 0, 0, 0.5))
	var rim := _rim(st, col)
	if key:
		# nœud clé : couronne crantée
		for k in range(12):
			var a := TAU * k / 12.0 + _t * (0.25 if st != "locked" else 0.0)
			var p0 := c + Vector2(cos(a), sin(a)) * (r + 8.0)
			cv.draw_colored_polygon(PackedVector2Array([p0 + Vector2(cos(a), sin(a)) * 9.0, p0 + Vector2(cos(a + 1.5708), sin(a + 1.5708)) * 7.0, p0 - Vector2(cos(a), sin(a)) * 3.0, p0 - Vector2(cos(a + 1.5708), sin(a + 1.5708)) * 7.0]), rim if st != "locked" else Color("#1C2A4A"))
	# sélection : tirets qui tournent (au-delà de la tranche et des niveaux, rien ne les recouvre)
	if id == _sel:
		for k in range(16):
			var a := TAU * k / 16.0 + _t * 0.9
			cv.draw_arc(c, r + (30.0 if key else 24.0), a, a + 0.22, 6, Color(1, 1, 1, 0.9), 3.0, true)

func _rim(st: String, col: Color) -> Color:
	match st:
		"max":
			return col.lightened(0.35)
		"owned":
			return col
		"open":
			return col.darkened(0.2)
	return col.darkened(0.72)

## Nœud : tranche, face, niveaux, éclat à dépenser, cadenas, pastille de niveau, nom.
func _draw_node_b(cv: Control, id: String) -> void:
	var t := Talents.talent(id)
	var inf: Dictionary = _info[id]
	var col: Color = inf["col"]
	var st := String(inf["st"])
	var lv := int(inf["lv"])
	var mx := int(t["max"])
	var r := _node_rr(id)
	var c := _node_c(id)
	var w := float(_wake.get(id, 0.0))
	if w > 1.0:
		# entrée de l'écran : pas encore allumé
		w = 0.0
	var rim := _rim(st, col)
	var face: Color
	match st:
		"max":
			face = col
		"owned":
			face = col.darkened(0.55)
		"open":
			face = col.darkened(0.8)
		_:
			face = Color("#0C152C")
	cv.draw_circle(c, r + 5.0, rim)
	cv.draw_circle(c, r, face)
	cv.draw_arc(c, r - 6.0, -2.6, -0.6, 20, Color(1, 1, 1, 0.3 if st == "max" else 0.12), 4.0, true)
	cv.draw_arc(c, r - 3.0, 0.5, 2.64, 20, Color(0, 0, 0, 0.22), 5.0, true)
	if w > 0.0 and st != "locked":
		cv.draw_circle(c, r, Color(1, 1, 1, w * 0.5))
	var fl := float(_flash.get(id, 0.0))
	if fl > 0.0:
		cv.draw_circle(c, r + 5.0, Color(1, 1, 1, fl * 0.9))
	# niveaux : segments autour du nœud
	if mx > 1:
		var gap := 0.16
		var seg := TAU / mx
		for i in range(mx):
			var a0 := -PI * 0.5 + seg * i + gap * 0.5
			var on := i < lv
			cv.draw_arc(c, r + 11.0, a0, a0 + seg - gap, 12, (col.lightened(0.3) if st != "max" else UI.GOLD) if on else Color("#2A3F6E"), 5.0, true)
	# éclat du Cœur à dépenser
	if int(t.get("shards", 0)) > 0:
		var sp := c + Vector2(r * 0.72, -r * 0.72)
		cv.draw_circle(sp, 16.0, UI.INK)
		var sc := UI.ACCENT if st == "locked" or st == "open" else Color(UI.ACCENT, 0.5)
		cv.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -11), sp + Vector2(8, -2), sp + Vector2(0, 12), sp + Vector2(-8, -2)]), sc)
	# cadenas
	if st == "locked":
		var lp := c + Vector2(r * 0.7, r * 0.62)
		cv.draw_circle(lp, 14.0, UI.INK)
		cv.draw_arc(lp + Vector2(0, -3), 5.5, PI, TAU, 10, UI.MUTED, 2.5, true)
		cv.draw_rect(Rect2(lp + Vector2(-7, -3), Vector2(14, 10)), UI.MUTED)
	# pastille de niveau sur la tranche basse
	var pill_txt := "MAX" if st == "max" else "%d/%d" % [lv, mx]
	var pw := 48.0 if st == "max" else 40.0
	var pr := Rect2(c.x - pw * 0.5, c.y + r - 6.0, pw, 22.0)
	var pill_bg := UI.GOLD if st == "max" else (col if lv > 0 else Color("#1A2A4E"))
	_round_rect(cv, Rect2(pr.position + Vector2(-2, -2), pr.size + Vector2(4, 4)), 11.0, UI.INK)
	_round_rect(cv, pr, 9.0, pill_bg)
	cv.draw_string(UI.TITLE, Vector2(pr.position.x, pr.position.y + 17.0), pill_txt, HORIZONTAL_ALIGNMENT_CENTER, pw, 14, UI.INK if lv > 0 else UI.MUTED)
	# nom
	var name_t := String(t["name"])
	var fs := 15
	var nw := UI.TITLE.get_string_size(name_t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if nw > 128.0:
		fs = 13
	var ncol := UI.TEXT if lv > 0 else (Color("#B8C8DC") if st == "open" else Color(UI.MUTED, 0.55))
	var np := Vector2(c.x - 90.0, c.y + r + 34.0)
	cv.draw_string_outline(UI.TITLE, np, name_t, HORIZONTAL_ALIGNMENT_CENTER, 180.0, fs, 5, UI.INK)
	cv.draw_string(UI.TITLE, np, name_t, HORIZONTAL_ALIGNMENT_CENTER, 180.0, fs, ncol)

func _along(pts: PackedVector2Array, f: float) -> Vector2:
	var x := clampf(f, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(int(x), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], x - i)

static var _rr_sb: StyleBoxFlat = null

## Rectangle arrondi. Opaque : un seul polygone (StyleBoxFlat, 1 appel de dessin au lieu de 5). Translucide
## (ombres) : deux rectangles et quatre disques qui se recouvrent, comme toujours (les recouvrements foncent).
static func _round_rect(ci: CanvasItem, r: Rect2, rad: float, col: Color) -> void:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	if col.a >= 1.0 and rad == roundf(rad):
		if _rr_sb == null:
			_rr_sb = StyleBoxFlat.new()
			_rr_sb.corner_detail = 16
			_rr_sb.anti_aliasing = false  # bords nets, comme draw_circle
		_rr_sb.bg_color = col
		_rr_sb.set_corner_radius_all(int(rad))
		_rr_sb.draw(ci.get_canvas_item(), r)
		return
	ci.draw_rect(Rect2(r.position.x + rad, r.position.y, r.size.x - rad * 2.0, r.size.y), col)
	ci.draw_rect(Rect2(r.position.x, r.position.y + rad, r.size.x, r.size.y - rad * 2.0), col)
	for p in [r.position + Vector2(rad, rad), Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.position.x + rad, r.end.y - rad), r.end - Vector2(rad, rad)]:
		ci.draw_circle(p, rad, col)

# ---------------------------------------------------------------- dessin des effets
func _draw_fx() -> void:
	for p in _parts:
		match String(p["kind"]):
			"coin":
				var k: float = p["t"] / p["dur"]
				if k < 0.0:
					continue
				var e := k * k * (3.0 - 2.0 * k)
				var a: Vector2 = p["a"]
				var b: Vector2 = p["b"]
				var mid := (a + b) * 0.5 + Vector2(float(p["arc"]), -120.0)
				var q := a.lerp(mid, e).lerp(mid.lerp(b, e), e)
				_fx.draw_circle(q, 12.0, Color(UI.GOLD, 0.35))
				_fx.draw_circle(q, 7.0, Color(1.0, 0.85, 0.45))
				_fx.draw_circle(q + Vector2(-2, -2), 2.5, Color(1, 1, 1, 0.9))
			"comet":
				var k2: float = p["t"] / p["dur"]
				if k2 < 0.0:
					continue
				var pts: PackedVector2Array = p["pts"]
				for j in range(8):
					var f := k2 - j * 0.035
					if f < 0.0:
						break
					var q2 := _along(pts, f) + _canvas.position
					_fx.draw_circle(q2, 10.0 - j, Color(p["col"], 0.9 - j * 0.11))
			"star":
				var k3: float = p["life"] / p["max"]
				CardScript._star(_fx, p["p"], float(p["r"]) * (1.0 - k3 * 0.6), Color(p["col"], 1.0 - k3))
			"ring":
				var k4: float = p["life"] / p["max"]
				if k4 < 0.0:
					continue
				var rr: float = lerpf(float(p["r0"]), float(p["r1"]), 1.0 - (1.0 - k4) * (1.0 - k4))
				_fx.draw_arc(p["p"], rr, 0.0, TAU, 64, Color(p["col"], (1.0 - k4) * 0.8), 8.0 * (1.0 - k4) + 1.5, true)

func _draw_texts() -> void:
	for tx in _texts:
		var k: float = tx["life"] / tx["max"]
		var y := -60.0 * (1.0 - (1.0 - k) * (1.0 - k))
		var a := 1.0 if k < 0.7 else (1.0 - k) / 0.3
		var s := int(tx["size"])
		var p: Vector2 = tx["p"] + Vector2(-150.0, y)
		_fx_txt.draw_string_outline(UI.TITLE, p, String(tx["text"]), HORIZONTAL_ALIGNMENT_CENTER, 300.0, s, 8, Color(UI.INK, a))
		_fx_txt.draw_string(UI.TITLE, p, String(tx["text"]), HORIZONTAL_ALIGNMENT_CENTER, 300.0, s, Color(tx["col"], a))
