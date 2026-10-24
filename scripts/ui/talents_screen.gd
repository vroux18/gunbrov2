extends Control
## Écran TALENTS du Relais : les talents permanents (talents.gd), une branche à la fois.
## Bandeau (RETOUR, titre, phrase, monnaies) ; à gauche cinq grands onglets de branche (SURVIE, PUISSANCE,
## POUVOIRS, FORTUNE, MOUVEMENT) avec leur progression ; au centre l'arbre de la branche choisie, gros nœuds
## ronds à pictogramme, niveau et nom lisibles ; à droite la fiche du talent choisi, toujours ouverte : effet
## actuel → suivant, prix en gros, ACHETER, et en clair pourquoi l'achat est bloqué. Glisser l'arbre de côté
## change de branche. L'achat : tickets qui volent du compteur vers le nœud, compteur qui défile, éclat,
## gerbe d'étoiles, liens suivants qui s'allument.
## L'arbre est découpé en calques (fond, liens, deux par nœud) redessinés seulement quand ce qu'ils montrent
## change : le fond une fois par branche, un nœud figé jamais, un nœud animé (halo, couronne) à chaque image.

const UI = preload("res://scripts/ui.gd")
const Fx = preload("res://scripts/ui/fx.gd")
const Icon = preload("res://scripts/icon.gd")
const Talents = preload("res://scripts/talents.gd")
const Save = preload("res://scripts/save.gd")
const CardScript = preload("res://scripts/ui/card.gd")
const Screen = preload("res://scripts/ui/powers_screen.gd")  # bandeau d'écran (en attendant celui de ui.gd)

const R := 42.0  # rayon d'un nœud
const RK := 50.0  # nœud clé (dernier rang de chaque branche)
const HEAD_H := Screen.HEAD_H
const TAB_W := 252.0
const DRAG_START := 14.0
const SWIPE := 90.0  # glissé horizontal qui change de branche
const SOFT := Color("#C4D2E4")
const BAD := Color("#FF8FA8")
const BRANCH_ICON := {"survie": "heart", "puissance": "dmg", "pouvoirs": "bolt", "fortune": "coins", "mouvement": "speed"}

var main: Node
var profile: Dictionary
var _branch := "survie"
var _view: Control  # zone tactile plein écran (sous les onglets et la fiche)
var _canvas: Control  # l'arbre de la branche choisie
var _fx: Control  # effets additifs (écran)
var _fx_txt: Control  # textes flottants (écran)
var _tabs: VBoxContainer
var _fiche: PanelContainer
var _fiche_box: VBoxContainer
var _tk_chip: PanelContainer
var _tk_label: Label
var _sh_chip: PanelContainer
var _icons := {}  # id -> Icon (branche affichée)
var _pos := {}  # id -> centre dans l'arbre (branche affichée)
var _links := []  # {from, to, pts, col, need, lit, line_l, dots_l}
var _canvas_size := Vector2.ZERO
var _tree_x0 := 0.0
var _spread := 260.0  # écart entre les deux nœuds d'un même rang
var _key_y := 0.0
var _row1_y := 0.0
var _bg: Control
var _layer_a := {}  # id -> calque du dessous (halo, anneau d'achat, ombre, couronne, sélection)
var _layer_b := {}  # id -> calque du nœud (corps, niveaux, pastille, nom)
var _sig_a := {}
var _sig_b := {}
var _info := {}  # id -> {st, lv, buyable, col} : recalculé quand le profil change (_profile_fp)
var _fp := []
var _fx_n := 0
var _sel := ""
var _t := 0.0
var _pan := Vector2.ZERO  # position de l'arbre à l'écran (glissé compris)
var _swipe := 0.0  # décalage horizontal pendant un glissé, revient à 0
var _press := false
var _drag := false
var _press_pos := Vector2.ZERO
var _shake := 0.0
var _pop := {}  # id -> 1 au moment de l'achat, décroît
var _flash := {}
var _wake := {}  # id -> 1 quand le nœud se déverrouille
var _deny := {}  # id -> 1 quand l'achat est refusé (le nœud tremble)
var _parts := []  # particules (écran)
var _texts := []  # textes flottants (écran)

func build(m: Node, fresh: bool = true) -> void:
	UI.load_fonts()
	main = m
	profile = m.profile
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.dim(1.0))  # fond opaque : le Relais 3D derrière ne gêne plus la lecture
	var tint := ColorRect.new()
	tint.color = Color(UI.BG, 0.55)
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)
	_layout()
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_on_input)
	add_child(_view)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.size = _canvas_size
	_view.add_child(_canvas)
	var hd := Screen.bandeau(self, "TALENTS", "Améliorations permanentes, achetées avec tes tickets et tes éclats.", UI.GOLD, func(): main.show_base(), profile)
	_tk_chip = hd["tk_chip"]
	_tk_label = hd["tk_label"]
	_sh_chip = hd["sh_chip"]
	_build_tabs()
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
	_refresh_info()
	# branche de départ : la première où un achat est possible
	_branch = String(Talents.BRANCHES[0]["id"])
	for b in Talents.BRANCHES:
		if _buyable_in(String(b["id"])) > 0:
			_branch = String(b["id"])
			break
	_show_branch(fresh)
	_refresh_header()
	if fresh:
		Fx.screen_in(self)
		Fx.slide_in(_tabs, Vector2(-80, 0), 0.0, 0.34)
		Fx.slide_in(_fiche, Vector2(120, 0), 0.05, 0.36)

func _vs() -> Vector2:
	return get_viewport().get_visible_rect().size

## Zones de l'écran : onglets à gauche, fiche à droite, l'arbre entre les deux, rangs répartis en hauteur.
var _fiche_w := 448.0
func _layout() -> void:
	var ins := UI.safe_insets(get_viewport())
	var vs := _vs()
	_fiche_w = clampf(vs.x * 0.35, 440.0, 520.0)
	_tree_x0 = float(ins["left"]) + TAB_W + 12.0
	var tree_w := vs.x - float(ins["right"]) - _fiche_w - 12.0 - _tree_x0
	_canvas_size = Vector2(tree_w, vs.y)
	_spread = clampf(tree_w * 0.5, 220.0, 300.0)
	_key_y = HEAD_H + 70.0
	_row1_y = vs.y - float(ins["bottom"]) - 94.0
	_pan = Vector2(_tree_x0, 0)

# ---------------------------------------------------------------- onglets de branche
func _build_tabs() -> void:
	var ins := UI.safe_insets(get_viewport())
	_tabs = UI.vbox(10)
	_tabs.anchor_bottom = 1.0
	_tabs.offset_left = float(ins["left"])
	_tabs.offset_right = float(ins["left"]) + TAB_W
	_tabs.offset_top = HEAD_H + 12.0
	_tabs.offset_bottom = -float(ins["bottom"])
	add_child(_tabs)

func _buyable_in(bid: String) -> int:
	var n := 0
	for t in Talents.TALENTS:
		if String(t["branch"]) == bid and bool(_info.get(String(t["id"]), {}).get("buyable", false)):
			n += 1
	return n

func _refresh_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	for b in Talents.BRANCHES:
		_tabs.add_child(_tab_button(b))

## Onglet de branche : pictogramme, nom, niveaux pris / total ; une pièce dorée si un achat y est possible.
func _tab_button(b: Dictionary) -> Button:
	var bid := String(b["id"])
	var col: Color = b["col"]
	var on := bid == _branch
	var bt := Button.new()
	bt.focus_mode = Control.FOCUS_NONE
	bt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bt.custom_minimum_size = Vector2(TAB_W, 76)
	var face := col.darkened(0.64) if on else Color(UI.PANEL, 0.95)
	var st := UI.chunky(face, col.darkened(0.3) if on else UI.INK, false, 16)
	st.border_width_left = 6
	st.border_color = col if on else col.darkened(0.5)
	bt.add_theme_stylebox_override("normal", st)
	var hv := st.duplicate()
	hv.bg_color = face.lightened(0.07)
	bt.add_theme_stylebox_override("hover", hv)
	var pr := UI.chunky(face.darkened(0.1), UI.INK, true, 16)
	pr.border_width_left = 6
	pr.border_color = col
	bt.add_theme_stylebox_override("pressed", pr)
	bt.add_theme_stylebox_override("hover_pressed", pr)
	bt.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var h := UI.hbox(12)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 16
	h.offset_right = -10
	h.offset_top = 4
	h.offset_bottom = -10
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bt.add_child(h)
	var ic := Icon.new(String(BRANCH_ICON.get(bid, "star")), col if on else col.darkened(0.1), 44.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := UI.vbox(-2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var nl := UI.title(String(b["name"]), 24, UI.TEXT if on else SOFT, col)
	nl.add_theme_constant_override("shadow_offset_y", 3 if on else 0)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	var own := 0
	var tot := 0
	for t in Talents.TALENTS:
		if String(t["branch"]) == bid:
			own += Talents.level(profile, String(t["id"]))
			tot += int(t["max"])
	var ph := UI.hbox(8)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ph)
	var pl := UI.label("%d / %d niv." % [own, tot], 24, UI.GOLD if own >= tot else (UI.TEXT if on else SOFT))
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph.add_child(pl)
	if _buyable_in(bid) > 0:
		var ci := Icon.new("coin", UI.GOLD, 26.0)
		ci.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ph.add_child(ci)
		Fx.pulse(ci, 0.55, 1.0, 1.1)
	Fx.press(bt, 0.95)
	bt.pressed.connect(func(): set_branch(bid))
	return bt

## Change de branche : l'arbre glisse depuis le côté (dir : -1 depuis la gauche, 1 depuis la droite).
func set_branch(bid: String, dir: int = 0) -> void:
	if bid == _branch:
		return
	if dir == 0:
		dir = 1 if _branch_index(bid) > _branch_index(_branch) else -1
	_branch = bid
	if main != null and main.get("sfx") != null:
		main.sfx.play("click", 1.1, -6.0)
	_show_branch(true)
	_swipe = 160.0 * dir

func _branch_index(bid: String) -> int:
	for i in range(Talents.BRANCHES.size()):
		if String(Talents.BRANCHES[i]["id"]) == bid:
			return i
	return 0

# ---------------------------------------------------------------- arbre de la branche
func _show_branch(anim: bool) -> void:
	for c in _canvas.get_children():
		_canvas.remove_child(c)
		c.queue_free()
	_pos.clear()
	_links.clear()
	_icons.clear()
	_layer_a.clear()
	_layer_b.clear()
	_sig_a.clear()
	_sig_b.clear()
	var cx := _canvas_size.x * 0.5
	var gy := (_row1_y - _key_y) / 3.0
	var ids := []
	for t in Talents.TALENTS:
		if String(t["branch"]) != _branch:
			continue
		var id := String(t["id"])
		ids.append(id)
		var row := float(t["pos"].y)
		_pos[id] = Vector2(cx + float(t["pos"].x) * _spread, _row1_y - (row - 1.0) * gy)
	for id in ids:
		var t := Talents.talent(id)
		var req: Dictionary = t["req"]
		for r in req.keys():
			_links.append({"from": String(r), "to": id, "need": int(req[r]), "col": Talents.color(id), "pts": _curve(_pos[String(r)], _pos[id])})
	_bg = _layer(func(cv): _draw_bg(cv))
	for l in _links:
		# chaque lien : tracé (figé) puis énergie qui y monte (animée)
		l["lit"] = false
		l["line_l"] = _layer(func(cv): _draw_link(cv, l))
		l["dots_l"] = _layer(func(cv): _draw_link_dots(cv, l))
	for id in ids:
		_layer_a[id] = _layer(func(cv): _draw_node_a(cv, id))
		_layer_b[id] = _layer(func(cv): _draw_node_b(cv, id))
	for id in ids:
		var t := Talents.talent(id)
		var s := 60.0 if _node_r(id) > R else 50.0
		var ic := Icon.new(String(t["icon"]), Talents.color(id), s)
		ic.size = Vector2(s, s)
		ic.position = _pos[id] - Vector2(s, s) * 0.5
		ic.pivot_offset = Vector2(s, s) * 0.5
		_canvas.add_child(ic)
		_icons[id] = ic
	_refresh_info()
	_refresh_tabs()
	if anim:
		# les nœuds s'allument du bas vers le haut
		for id in ids:
			_wake[id] = 1.0 + float(Talents.talent(id)["pos"].y) * 0.14
	# talent choisi : le premier achetable, sinon le premier ouvert, sinon le premier de la branche
	var pick := ""
	for id in ids:
		if bool(_info[id]["buyable"]):
			pick = id
			break
	if pick == "":
		for id in ids:
			if String(_info[id]["st"]) == "open" or String(_info[id]["st"]) == "owned":
				pick = id
				break
	if pick == "":
		pick = String(ids[0])
	_sel = pick
	_fill_fiche()

func _node_r(id: String) -> float:
	return RK if float(Talents.talent(id)["pos"].y) >= 4.0 else R

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

# ---------------------------------------------------------------- fiche
func _build_fiche() -> void:
	var ins := UI.safe_insets(get_viewport())
	_fiche = PanelContainer.new()
	_fiche.anchor_left = 1.0
	_fiche.anchor_right = 1.0
	_fiche.anchor_bottom = 1.0
	_fiche.offset_left = -_fiche_w - float(ins["right"])
	_fiche.offset_right = -float(ins["right"])
	_fiche.offset_top = HEAD_H + 12.0
	_fiche.offset_bottom = -float(ins["bottom"])
	_fiche.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_fiche)
	_fiche_box = UI.vbox(12)
	_fiche.add_child(_fiche_box)

# ---------------------------------------------------------------- état
## Empreinte du profil (tickets, éclats, niveaux) : l'état des nœuds n'est recalculé que si elle change.
func _profile_fp() -> Array:
	return [int(profile.get("tickets", 0)), int(profile.get("shards", 0)), Talents.levels(profile).hash()]

func _refresh_info() -> void:
	var old := {}
	for id in _info.keys():
		old[id] = _info[id]["buyable"]
	_fp = _profile_fp()
	for t in Talents.TALENTS:
		var id := String(t["id"])
		_info[id] = {"st": _state(id), "lv": Talents.level(profile, id), "buyable": Talents.block_reason(profile, id) == "", "col": Talents.color(id)}
	for l in _links:
		var from := String(l["from"])
		l["lit"] = from == "" or Talents.level(profile, from) >= int(l["need"])
		(l["line_l"] as Control).queue_redraw()
		(l["dots_l"] as Control).queue_redraw()
	# pièces des onglets : à refaire si un talent devient achetable ou ne l'est plus
	if _tabs != null and not old.is_empty():
		for id in old.keys():
			if old[id] != _info[id]["buyable"]:
				_refresh_tabs()
				break

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
	var sl: Label = _sh_chip.get_meta("label")
	var free := Talents.shards_free(profile)
	sl.text = "%d éclat%s" % [free, "s" if free > 1 else ""]
	_tk_label.text = "%d" % int(profile["tickets"])

## Sélectionne un talent (change de branche au besoin) : sa fiche s'affiche à droite.
func select(id: String) -> void:
	if Talents.talent(id).is_empty():
		return
	var bid := String(Talents.talent(id)["branch"])
	if bid != _branch:
		set_branch(bid)
	_sel = id
	if main != null and main.get("sfx") != null:
		main.sfx.play("click", 1.15, -6.0)
	_fill_fiche()
	_bump_icon(id, 0.12)

## Fiche du talent choisi : nom, branche, niveau ; ce qu'il fait ; effet maintenant → après achat ; pourquoi
## l'achat est bloqué ; prix et ACHETER.
func _fill_fiche() -> void:
	for c in _fiche_box.get_children():
		_fiche_box.remove_child(c)
		c.queue_free()
	var id := _sel
	var t := Talents.talent(id)
	if t.is_empty():
		return
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
	s.content_margin_bottom = 18
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 14
	_fiche.add_theme_stylebox_override("panel", s)
	# tête : pastille, nom, branche et niveau
	var head := UI.hbox(14)
	_fiche_box.add_child(head)
	var ring := Panel.new()
	ring.custom_minimum_size = Vector2(84, 84)
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ring.add_theme_stylebox_override("panel", UI.flat(col.darkened(0.6) if st != "max" else col, col, 42, 4))
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(ring)
	var ic := Icon.new(String(t["icon"]), UI.INK if st == "max" else col.lightened(0.2), 54.0)
	ic.position = Vector2(15, 15)
	ring.add_child(ic)
	var hv := UI.vbox(6)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(hv)
	var name_l := UI.title(String(t["name"]), 30 if String(t["name"]).length() < 13 else 26, UI.TEXT, col)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(name_l)
	var tags := UI.hbox(8)
	hv.add_child(tags)
	tags.add_child(UI.tag(String(Talents.branch(String(t["branch"]))["name"]), col, UI.INK, 20))
	tags.add_child(UI.tag("MAX" if st == "max" else "NIVEAU %d / %d" % [lv, mx], UI.GOLD if st == "max" else Color("#2A3F6E"), UI.INK if st == "max" else UI.TEXT, 20))
	var d := UI.label(String(t["desc"]), 24, SOFT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fiche_box.add_child(d)
	# effet maintenant → après achat
	var eff := PanelContainer.new()
	var es := UI.flat(Color(UI.INK, 0.6), Color(col, 0.3), 14, 2)
	es.content_margin_top = 12
	es.content_margin_bottom = 12
	es.content_margin_left = 16
	es.content_margin_right = 16
	eff.add_theme_stylebox_override("panel", es)
	_fiche_box.add_child(eff)
	var ev := UI.vbox(2)
	eff.add_child(ev)
	ev.add_child(UI.label("MAINTENANT", 20, SOFT))
	var now_l := UI.label(Talents.effect_text(id, lv) if lv > 0 else "Rien pour l'instant", 24, UI.TEXT if lv > 0 else SOFT)
	now_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ev.add_child(now_l)
	if st != "max":
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(0, 6)
		ev.add_child(sp)
		ev.add_child(UI.label("APRÈS ACHAT  (NIVEAU %d)" % (lv + 1), 20, col.lightened(0.2)))
		var nx := UI.label(Talents.effect_text(id, lv + 1), 26, col.lightened(0.35))
		nx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ev.add_child(nx)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fiche_box.add_child(grow)
	if st == "max":
		_fiche_box.add_child(UI.title("★  AU MAXIMUM  ★", 28, UI.GOLD, UI.ORANGE, HORIZONTAL_ALIGNMENT_CENTER))
		_fiche_box.add_child(UI.label("Touche un autre talent dans l'arbre.", 24, SOFT, HORIZONTAL_ALIGNMENT_CENTER))
		return
	# pourquoi c'est bloqué, en clair
	var c := Talents.cost(id, lv)
	var reason := Talents.block_reason(profile, id)
	var why := ""
	match reason:
		"locked":
			why = "Bloqué : monte d'abord " + " et ".join(Talents.missing(profile, id)) + "."
		"tickets":
			why = "Il te manque %d tickets." % (int(c["tickets"]) - int(profile["tickets"]))
		"shards":
			why = "Il faut un éclat : termine un monde."
	if why != "":
		var wl := UI.label(why, 24, BAD)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_fiche_box.add_child(wl)
	# prix et bouton, côte à côte
	var row := UI.hbox(14)
	_fiche_box.add_child(row)
	var cost_v := UI.vbox(-4)
	cost_v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cost_v)
	cost_v.add_child(UI.label("PRIX", 20, SOFT))
	var cost_row := UI.hbox(6)
	cost_v.add_child(cost_row)
	var coin := Icon.new("coin", UI.GOLD, 34.0)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost_row.add_child(coin)
	var cl := UI.title("%d" % int(c["tickets"]), 34, UI.GOLD if reason != "tickets" else BAD, UI.ORANGE)
	cl.add_theme_constant_override("shadow_offset_y", 2)
	cost_row.add_child(cl)
	if int(c["shards"]) > 0:
		cost_row.add_child(UI.label("+", 26, SOFT))
		var sh := Icon.new("shard", UI.ACCENT, 34.0)
		sh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cost_row.add_child(sh)
		var sl := UI.title("%d" % int(c["shards"]), 34, UI.ACCENT if reason != "shards" else BAD, UI.ACCENT)
		sl.add_theme_constant_override("shadow_offset_y", 2)
		cost_row.add_child(sl)
	var up := UI.primary("ACHETER", 30)
	up.custom_minimum_size = Vector2(0, 84)
	up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up.disabled = reason != ""
	up.pressed.connect(buy_selected)
	row.add_child(up)
	if reason == "":
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
	if not _pos.has(id):
		return  # branche changée entre-temps
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
	_texts.append({"text": "MAX !" if maxed else "NIV. %d" % lv, "p": c + Vector2(0, -_node_r(id) - 18.0), "life": 0.0, "max": 1.1, "col": UI.GOLD if maxed else col.lightened(0.3), "size": 36 if maxed else 32})
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
					if not _pos.has(to):
						return
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

# ---------------------------------------------------------------- toucher : choisir un nœud, glisser de côté
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
	else:
		return
	if pressed:
		_press = true
		_drag = false
		_press_pos = pos
	elif released:
		if not _press:
			return
		_press = false
		var dx := pos.x - _press_pos.x
		if _drag and absf(dx) > SWIPE:
			# glissé vers la gauche : branche suivante ; vers la droite : précédente
			var i := _branch_index(_branch) + (1 if dx < 0.0 else -1)
			if i >= 0 and i < Talents.BRANCHES.size():
				set_branch(String(Talents.BRANCHES[i]["id"]), 1 if dx < 0.0 else -1)
		elif not _drag:
			_tap(pos)
		_drag = false
	elif _press:
		if not _drag and pos.distance_to(_press_pos) > DRAG_START:
			_drag = true
		if _drag:
			_swipe = (pos.x - _press_pos.x) * 0.6

func _tap(pos: Vector2) -> void:
	var best := ""
	var best_d := 1e9
	for id in _pos.keys():
		var d: float = (_pos[id] + _pan).distance_to(pos)
		if d < _node_r(id) + 22.0 and d < best_d:
			best = id
			best_d = d
	if best != "":
		select(best)

# ---------------------------------------------------------------- boucle
func _process(dt: float) -> void:
	_t += dt
	if not _press or not _drag:
		_swipe = lerpf(_swipe, 0.0, minf(1.0, dt * 12.0))
		if absf(_swipe) < 0.5:
			_swipe = 0.0
	_pan = Vector2(_tree_x0 + _swipe, 0.0)
	_shake = maxf(0.0, _shake - dt * 1.6)
	var sh := Vector2.ZERO
	if _shake > 0.0:
		sh = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 10.0
	_canvas.position = (_pan + sh).round()
	_canvas.modulate.a = clampf(1.0 - absf(_swipe) / 260.0, 0.3, 1.0)
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
		var sb := [st, inf["lv"], pop, dn, w if w <= 1.0 else 0.0, float(_flash.get(id, 0.0)), id == _sel]
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
			c = Color(col.lerp(UI.MUTED, 0.5), 0.45)
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
## Fond : pointillés et colonne de couleur de la branche (dessiné une fois par branche).
func _draw_bg(cv: Control) -> void:
	var sz := _canvas_size
	for gx in range(20, int(sz.x), 40):
		for gy in range(int(HEAD_H) + 20, int(sz.y), 40):
			cv.draw_rect(Rect2(gx - 1, gy - 1, 2, 2), Color(0.5, 0.65, 1.0, 0.07))
	var col: Color = Talents.branch(_branch)["col"]
	var top := _key_y - RK - 30.0
	var bot := sz.y
	var hw := minf(sz.x * 0.5, _spread + 20.0)
	var x := sz.x * 0.5
	cv.draw_polygon(PackedVector2Array([Vector2(x - hw, top), Vector2(x + hw, top), Vector2(x + hw, bot), Vector2(x - hw, bot)]),
		PackedColorArray([Color(col, 0.0), Color(col, 0.0), Color(col, 0.09), Color(col, 0.09)]))

func _draw_link(cv: Control, l: Dictionary) -> void:
	var pts: PackedVector2Array = l["pts"]
	var col: Color = l["col"]
	var from := String(l["from"])
	var lit: bool = l["lit"]
	var part := from != "" and not lit and Talents.level(profile, from) > 0
	cv.draw_polyline(pts, Color(UI.INK, 0.9), 14.0, true)
	if lit:
		cv.draw_polyline(pts, Color(col, 0.16), 24.0, true)
		cv.draw_polyline(pts, col.darkened(0.1), 8.0, true)
		cv.draw_polyline(pts, Color(col.lightened(0.5), 0.7), 3.0, true)
	elif part:
		cv.draw_polyline(pts, Color(col, 0.38), 7.0, true)
		var lv := Talents.level(profile, from)
		var f2 := float(lv) / float(maxi(1, int(l["need"])))
		var sub := PackedVector2Array()
		for i in range(int(round(f2 * (pts.size() - 1))) + 1):
			sub.append(pts[i])
		if sub.size() > 1:
			cv.draw_polyline(sub, col.darkened(0.1), 8.0, true)
	else:
		cv.draw_polyline(pts, Color("#1E2E52"), 7.0, true)
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
		cv.draw_arc(c, r + 18.0 + 2.0 * sin(_t * 4.0), 0.0, TAU, 48, Color(UI.GOLD, pa), 3.0, true)
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
			cv.draw_arc(c, r + (30.0 if key else 25.0), a, a + 0.22, 6, Color(1, 1, 1, 0.95), 4.0, true)

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
		var sp := c + Vector2(r * 0.74, -r * 0.74)
		cv.draw_circle(sp, 18.0, UI.INK)
		var sc := UI.ACCENT if st == "locked" or st == "open" else Color(UI.ACCENT, 0.5)
		cv.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -12), sp + Vector2(9, -2), sp + Vector2(0, 13), sp + Vector2(-9, -2)]), sc)
	# cadenas
	if st == "locked":
		var lp := c + Vector2(r * 0.72, r * 0.6)
		cv.draw_circle(lp, 16.0, UI.INK)
		cv.draw_arc(lp + Vector2(0, -3), 6.5, PI, TAU, 10, SOFT, 3.0, true)
		cv.draw_rect(Rect2(lp + Vector2(-8, -3), Vector2(16, 12)), SOFT)
	# pastille de niveau sur la tranche basse
	var pill_txt := "MAX" if st == "max" else "%d/%d" % [lv, mx]
	var pw := 66.0 if st == "max" else 58.0
	var pr := Rect2(c.x - pw * 0.5, c.y + r - 8.0, pw, 28.0)
	var pill_bg := UI.GOLD if st == "max" else (col if lv > 0 else Color("#1A2A4E"))
	_round_rect(cv, Rect2(pr.position + Vector2(-2, -2), pr.size + Vector2(4, 4)), 13.0, UI.INK)
	_round_rect(cv, pr, 11.0, pill_bg)
	cv.draw_string(UI.TITLE, Vector2(pr.position.x, pr.position.y + 22.0), pill_txt, HORIZONTAL_ALIGNMENT_CENTER, pw, 20, UI.INK if lv > 0 else SOFT)
	# nom
	var name_t := String(t["name"])
	var room := _spread - 12.0
	var fs := 22
	if UI.TITLE.get_string_size(name_t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs = 20
	var ncol := UI.TEXT if lv > 0 or st == "open" or id == _sel else SOFT
	var np := Vector2(c.x - room * 0.5, c.y + r + 41.0)
	cv.draw_string_outline(UI.TITLE, np, name_t, HORIZONTAL_ALIGNMENT_CENTER, room, fs, 6, UI.INK)
	cv.draw_string(UI.TITLE, np, name_t, HORIZONTAL_ALIGNMENT_CENTER, room, fs, ncol)

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
