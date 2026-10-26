extends Control
## Écran POUVOIRS du Relais (ancien ARSENAL) : les pouvoirs qu'on peut obtenir en partie, à lire (rien à acheter).
## Bandeau (RETOUR, titre, phrase, monnaies), une rangée de grands onglets (cinq branches + ÉVOLUTIONS), puis
## les pouvoirs de la branche choisie en grandes tuiles, rangées par palier avec une phrase qui dit quand le
## palier s'ouvre. Toucher un pouvoir ouvre son panneau de détail (effet par niveau, évolution associée).
## L'onglet ÉVOLUTIONS montre chaque recette : pictogrammes des deux pouvoirs, puis le résultat.
## Ouvert par main.show_arsenal() ; l'onglet choisi est gardé dans main._ars_tab ("evo" ou id de branche).
## Options de capture (avec --autoplay) : --branch=<id> ouvre une branche, --power=<id> ouvre un détail.

const UI = preload("res://scripts/ui.gd")
const Fx = preload("res://scripts/ui/fx.gd")
const Icon = preload("res://scripts/icon.gd")
const Data = preload("res://scripts/data.gd")
const Talents = preload("res://scripts/talents.gd")
const TouchScroll = preload("res://scripts/ui/touch_scroll.gd")

const HEAD_H := 112.0  # hauteur du bandeau
const TAB_H := 84.0
const GAP := 12
const TILE_MIN_W := 280.0
const TILE_H := 92.0
const SOFT := Color("#C4D2E4")  # texte secondaire, encore bien lisible sur fond sombre

var main: Node
var profile: Dictionary
var _tab := "canon"
var _tabs: HBoxContainer
var _body: Control
var _detail: Control = null
var _ins := {}

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
	_ins = UI.safe_insets(get_viewport())
	_tab = String(m.get("_ars_tab")) if m.get("_ars_tab") != null else ""
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--branch="):
			_tab = a.trim_prefix("--branch=")
	if _tab != "evo" and not Data.BRANCHES.has(_tab):
		_tab = String(Data.BRANCH_ORDER[0])
	bandeau(self, "POUVOIRS", "Les cartes d'une branche débloquent de nouveaux pouvoirs.", UI.ORANGE, func(): main.show_base(), profile)
	_build_tabs()
	_body = Control.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.offset_left = float(_ins["left"])
	_body.offset_right = -float(_ins["right"])
	_body.offset_top = HEAD_H + 10.0 + TAB_H + 12.0
	_body.offset_bottom = -float(_ins["bottom"])
	add_child(_body)
	_fill(fresh)
	if fresh:
		Fx.screen_in(self)
		Fx.slide_in(_tabs, Vector2(0, -40), 0.0, 0.3)
	if "--autoplay" in args:
		for a in args:
			if a.begins_with("--power="):
				var p := Data.power(a.trim_prefix("--power="))
				if not p.is_empty():
					if _tab != String(p["b"]):
						_select_tab(String(p["b"]))
					open_power(String(p["id"]))

func _vs() -> Vector2:
	return get_viewport().get_visible_rect().size

## Bandeau d'écran du Relais : RETOUR (gros, à gauche), titre et phrase qui dit ce qu'on fait ici, monnaies à
## droite (éclats libres, tickets). Local à cet écran et à TALENTS en attendant le bandeau commun de ui.gd.
## Renvoie {tk_chip, tk_label, sh_chip, sh_label, back}.
static func bandeau(root: Control, title_text: String, phrase: String, accent: Color, on_back: Callable, prof: Dictionary) -> Dictionary:
	UI.load_fonts()
	var ins := UI.safe_insets(root.get_viewport())
	var bar := Panel.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = HEAD_H
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(UI.INK, 0.95)
	bs.border_width_bottom = 3
	bs.border_color = Color(accent, 0.5)
	bs.shadow_color = Color(0, 0, 0, 0.45)
	bs.shadow_size = 12
	bar.add_theme_stylebox_override("panel", bs)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	var row := UI.hbox(22)
	row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	row.offset_left = float(ins["left"])
	row.offset_right = -float(ins["right"])
	row.offset_top = 10.0
	row.offset_bottom = HEAD_H - 12.0
	root.add_child(row)
	var back := UI.primary("RETOUR", 28)
	back.custom_minimum_size = Vector2(180, 80)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(on_back)
	row.add_child(back)
	var tv := UI.vbox(-2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tv)
	var t := UI.title(title_text, 44, UI.TEXT, accent)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(t)
	var ph := UI.label(phrase, 24, SOFT)
	ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(ph)
	var money := UI.hbox(12)
	money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(money)
	var free := Talents.shards_free(prof)
	var sh := UI.chip("shard", "%d éclat%s" % [free, "s" if free > 1 else ""], UI.ACCENT)
	var tk := UI.chip("coin", "%d" % int(prof.get("tickets", 0)), UI.GOLD)
	for c in [sh, tk]:
		var cl: Label = c.get_meta("label")
		cl.add_theme_font_override("font", UI.TITLE)
		cl.add_theme_font_size_override("font_size", 24)
		money.add_child(c)
	(tk.get_meta("label") as Label).custom_minimum_size = Vector2(64, 0)
	return {"tk_chip": tk, "tk_label": tk.get_meta("label"), "sh_chip": sh, "sh_label": sh.get_meta("label"), "back": back}

# ---------------------------------------------------------------- onglets
func _build_tabs() -> void:
	_tabs = UI.hbox(GAP)
	_tabs.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_tabs.offset_left = float(_ins["left"])
	_tabs.offset_right = -float(_ins["right"])
	_tabs.offset_top = HEAD_H + 10.0
	_tabs.offset_bottom = HEAD_H + 10.0 + TAB_H
	add_child(_tabs)
	_refresh_tabs()

func _refresh_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	for bid in Data.BRANCH_ORDER:
		var br := Data.branch(String(bid))
		_tabs.add_child(_tab_button(String(bid), String(br["icon"]), String(br["name"]).to_upper(), br["col"]))
	_tabs.add_child(_tab_button("evo", "star", "ÉVOLUTIONS", Data.EVO_COL))

## Grand onglet : pictogramme au-dessus du nom, couleur de la branche ; l'onglet choisi est plein et liseré.
func _tab_button(key: String, icon: String, text: String, col: Color) -> Button:
	var on := key == _tab
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, TAB_H)
	var face := col.darkened(0.62) if on else Color(UI.PANEL, 0.95)
	var st := UI.chunky(face, col.darkened(0.3) if on else UI.INK, false, 16)
	st.border_width_top = 4
	st.border_color = col if on else col.darkened(0.55)
	b.add_theme_stylebox_override("normal", st)
	var hv := st.duplicate()
	hv.bg_color = face.lightened(0.07)
	b.add_theme_stylebox_override("hover", hv)
	var pr := UI.chunky(face.darkened(0.1), UI.INK, true, 16)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var v := UI.vbox(2)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 8
	v.offset_bottom = -12
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := Icon.new(icon, col if on else col.darkened(0.15), 38.0)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := UI.title(text, 24, UI.TEXT if on else SOFT, col, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_constant_override("shadow_offset_y", 0 if not on else 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	Fx.press(b, 0.95)
	b.pressed.connect(func(): _select_tab(key))
	return b

func _select_tab(key: String) -> void:
	if key == _tab:
		return
	_tab = key
	if main != null:
		main.set("_ars_tab", key)
		if main.get("sfx") != null:
			main.sfx.play("click", 1.1, -6.0)
	_refresh_tabs()
	_fill(true)

func _fill(anim: bool) -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if _tab == "evo":
		_fill_evo(anim)
	else:
		_fill_branch(_tab, anim)

func _scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(sc)
	TouchScroll.attach(sc)
	return sc

func _body_w() -> float:
	return _vs().x - float(_ins["left"]) - float(_ins["right"])

# ---------------------------------------------------------------- branche
const TIER_TEXT := ["", "Dès le début de la partie.", "Débloqué après 2 cartes de cette branche.", "Débloqué après 4 cartes de cette branche."]

func _fill_branch(bid: String, anim: bool) -> void:
	var br := Data.branch(bid)
	var bc: Color = br["col"]
	var sc := _scroll()
	var v := UI.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var w := _body_w() - 18.0  # place de la barre de défilement
	# colonnes : autant que la place le permet, sans dépasser le palier le plus fourni (la rangée reste pleine)
	var most := 0
	for tier in [1, 2, 3]:
		var n := 0
		for p in Data.POWERS:
			if String(p["b"]) == bid and int(p["tier"]) == tier:
				n += 1
		most = maxi(most, n)
	var cols := clampi(mini(int((w + GAP) / (TILE_MIN_W + GAP)), most), 2, 5)
	var tile_w := floorf((w - GAP * (cols - 1)) / cols)
	var k := 0
	for tier in [1, 2, 3]:
		var head := UI.hbox(14)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(head)
		var tg := UI.tag("PALIER %d" % tier, bc if tier == 1 else bc.darkened(0.15), UI.INK, 24)
		tg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(tg)
		var tl := UI.label(TIER_TEXT[tier], 24, UI.TEXT)
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(tl)
		var grid := GridContainer.new()
		grid.columns = cols
		grid.add_theme_constant_override("h_separation", GAP)
		grid.add_theme_constant_override("v_separation", GAP)
		v.add_child(grid)
		for p in Data.POWERS:
			if String(p["b"]) != bid or int(p["tier"]) != tier:
				continue
			var t := _power_tile(p, bc, tile_w)
			grid.add_child(t)
			if anim:
				Fx.rise_in(t, 0.03 * k, 0.26, 0.9)
			k += 1

## Grande tuile d'un pouvoir : pictogramme dans un anneau, nom, nombre de niveaux (pastilles).
func _power_tile(p: Dictionary, bc: Color, w: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, TILE_H)
	var st := UI.chunky(Color(UI.PANEL, 0.98), UI.INK, false, 16)
	st.border_width_left = 5
	st.border_color = bc.darkened(0.15)
	b.add_theme_stylebox_override("normal", st)
	var hv := st.duplicate()
	hv.bg_color = UI.PANEL.lightened(0.07)
	b.add_theme_stylebox_override("hover", hv)
	var pr := UI.chunky(UI.PANEL.darkened(0.1), UI.INK, true, 16)
	pr.border_width_left = 5
	pr.border_color = bc
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	Fx.press(b, 0.96)
	var hb := UI.hbox(12)
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 16
	hb.offset_right = -12
	hb.offset_top = 6
	hb.offset_bottom = -12
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var ring := Panel.new()
	ring.custom_minimum_size = Vector2(60, 60)
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ring.add_theme_stylebox_override("panel", UI.flat(Color(bc, 0.16), Color(bc, 0.85), 30, 3))
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ring)
	var ic := Icon.new(String(p["id"]), bc.lightened(0.15), 38.0)
	ic.position = Vector2(11, 11)
	ring.add_child(ic)
	var tv := UI.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tv)
	# nom sur une ligne : 26 px, 24 px s'il est long
	var fs := 26
	if UI.BODY.get_string_size(String(p["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 102.0:
		fs = 24
	var n := UI.label(String(p["name"]), fs, UI.TEXT)
	n.clip_text = true
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(n)
	tv.add_child(_pips(int(p["max"]), bc))
	b.pressed.connect(func(): open_power(String(p["id"])))
	return b

## Niveaux d'un pouvoir : une pastille par niveau, puis « 3 niveaux ».
func _pips(n: int, col: Color) -> HBoxContainer:
	var h := UI.hbox(5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(n):
		var d := Panel.new()
		d.custom_minimum_size = Vector2(16, 16)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		d.add_theme_stylebox_override("panel", UI.flat(col, col.darkened(0.4), 5, 2))
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(d)
	var l := UI.label("  %d niveau%s" % [n, "x" if n > 1 else ""], 22, col.lightened(0.25))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	return h

# ---------------------------------------------------------------- détail d'un pouvoir
## Grand panneau par-dessus l'écran : nom, branche et palier, effet de chaque niveau, évolution associée.
## Toucher à côté ou FERMER le referme.
func open_power(id: String) -> void:
	var p := Data.power(id)
	if p.is_empty():
		return
	close_detail()
	if main != null and main.get("sfx") != null:
		main.sfx.play("click", 1.2, -8.0)
	var br := Data.branch(String(p["b"]))
	var bc: Color = br["col"]
	var vs := _vs()
	_detail = Control.new()
	_detail.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_detail)
	var back := Button.new()  # fond : toucher à côté referme
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.focus_mode = Control.FOCUS_NONE
	var bst := StyleBoxFlat.new()
	bst.bg_color = Color(UI.INK, 0.78)
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		back.add_theme_stylebox_override(s, bst)
	back.pressed.connect(close_detail)
	_detail.add_child(back)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(cc)
	var pan := PanelContainer.new()
	pan.custom_minimum_size = Vector2(minf(860.0, vs.x - float(_ins["left"]) - float(_ins["right"]) - 40.0), 0)
	var ps := UI.flat(Color("#122042"), bc.darkened(0.35), 24, 3)
	ps.border_width_top = 7
	ps.border_color = bc
	ps.content_margin_left = 30
	ps.content_margin_right = 30
	ps.content_margin_top = 22
	ps.content_margin_bottom = 26
	ps.shadow_color = Color(0, 0, 0, 0.55)
	ps.shadow_size = 18
	pan.add_theme_stylebox_override("panel", ps)
	pan.mouse_filter = Control.MOUSE_FILTER_STOP
	cc.add_child(pan)
	var v := UI.vbox(14)
	pan.add_child(v)
	# tête : pictogramme, nom, branche et palier, FERMER
	var head := UI.hbox(18)
	v.add_child(head)
	var ring := Panel.new()
	ring.custom_minimum_size = Vector2(96, 96)
	ring.add_theme_stylebox_override("panel", UI.flat(Color(bc, 0.18), bc, 48, 4))
	head.add_child(ring)
	var ic := Icon.new(id, bc.lightened(0.2), 62.0)
	ic.position = Vector2(17, 17)
	ring.add_child(ic)
	var hv := UI.vbox(6)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(hv)
	var nm := UI.title(String(p["name"]).to_upper(), 36, UI.TEXT, bc)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(nm)
	var tags := UI.hbox(8)
	hv.add_child(tags)
	tags.add_child(UI.tag(String(br["name"]).to_upper(), bc, UI.INK, 22))
	tags.add_child(UI.tag("PALIER %d" % int(p["tier"]), Color("#2A3F6E"), UI.TEXT, 22))
	var close := UI.button("FERMER", 24, UI.MUTED)
	close.custom_minimum_size = Vector2(150, 76)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(close_detail)
	head.add_child(close)
	var tl := UI.label("Palier %d : %s" % [int(p["tier"]), TIER_TEXT[int(p["tier"])].to_lower()], 24, SOFT)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tl)
	# effet par niveau
	var eff := PanelContainer.new()
	var es := UI.flat(Color(UI.INK, 0.6), Color(bc, 0.3), 16, 2)
	es.content_margin_top = 14
	es.content_margin_bottom = 14
	es.content_margin_left = 18
	es.content_margin_right = 18
	eff.add_theme_stylebox_override("panel", es)
	v.add_child(eff)
	var ev := UI.vbox(10)
	eff.add_child(ev)
	var mx := int(p["max"])
	if p.has("lv"):
		for i in range(mx):
			ev.add_child(_level_row("NIV. %d" % (i + 1), Data.power_text(p, i + 1), bc))
	else:
		ev.add_child(_level_row("CHAQUE NIV.", String(p["desc"]), bc))
		var up := UI.label("Se prend jusqu'à %d fois%s." % [mx, " : l'effet se cumule" if mx > 1 else ""], 24, SOFT)
		up.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ev.add_child(up)
	# évolution associée
	for e in Data.EVOLUTIONS:
		var need: Array = e["need"]
		if not need.has(id):
			continue
		v.add_child(_evo_box(e, true))
	Fx.rise_in(pan, 0.0, 0.24, 0.9)

func close_detail() -> void:
	if _detail != null and is_instance_valid(_detail):
		_detail.queue_free()
	_detail = null

func _level_row(tag_text: String, text: String, col: Color) -> HBoxContainer:
	var h := UI.hbox(14)
	var tg := UI.tag(tag_text, col, UI.INK, 20)
	tg.custom_minimum_size = Vector2(112, 0)
	tg.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(tg)
	var l := UI.label(text, 26, UI.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h

# ---------------------------------------------------------------- évolutions
func _fill_evo(anim: bool) -> void:
	var col := UI.vbox(12)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.add_child(col)
	var rule := UI.label("Deux pouvoirs précis au niveau maximum préparent une évolution : elle sort en carte dorée, une fois par partie.", 24, UI.TEXT)
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(rule)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	TouchScroll.attach(sc)
	var list := UI.vbox(GAP)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var i := 0
	for e in Data.EVOLUTIONS:
		var card := _evo_box(e, false)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(card)
		if anim:
			Fx.rise_in(card, 0.03 * i, 0.26, 0.9)
		i += 1

## Recette d'une évolution : [pouvoir A] + [pouvoir B] → [évolution], puis son nom, la recette en mots, son effet.
## `in_detail` : version du panneau de détail d'un pouvoir (titre « ÉVOLUTION » en plus).
func _evo_box(e: Dictionary, in_detail: bool) -> PanelContainer:
	var need: Array = e["need"]
	var a := Data.power(String(need[0]))
	var b := Data.power(String(need[1]))
	var gold: Color = Data.EVO_COL
	var box := PanelContainer.new()
	var st := UI.flat(Color(UI.PANEL, 0.97) if not in_detail else Color(UI.INK, 0.6), gold.darkened(0.45), 18, 2)
	st.border_width_left = 6
	st.border_color = gold
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 14
	st.content_margin_bottom = 16
	box.add_theme_stylebox_override("panel", st)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := UI.hbox(16)
	box.add_child(h)
	var rec := UI.hbox(6)
	rec.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(rec)
	rec.add_child(_disc(String(a["id"]), Data.branch(String(a["b"]))["col"], 60.0))
	rec.add_child(_sign("+"))
	rec.add_child(_disc(String(b["id"]), Data.branch(String(b["b"]))["col"], 60.0))
	rec.add_child(_sign("="))
	rec.add_child(_disc(String(e["icon"]), gold, 74.0))
	var v := UI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var t := UI.title(("ÉVOLUTION : " if in_detail else "") + String(e["name"]).to_upper(), 26, gold.lightened(0.15), UI.ORANGE)
	t.add_theme_constant_override("shadow_offset_y", 2)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var r := UI.label("%s + %s, tous deux au maximum" % [String(a["name"]), String(b["name"])], 24, UI.TEXT)
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(r)
	var d := UI.label(String(e["desc"]), 24, SOFT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	for c in [t, r, d]:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box

func _disc(icon: String, col: Color, s: float) -> Panel:
	var ring := Panel.new()
	ring.custom_minimum_size = Vector2(s, s)
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ring.add_theme_stylebox_override("panel", UI.flat(Color(col, 0.18), col, int(s * 0.5), 3))
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Icon.new(icon, col.lightened(0.15), s * 0.62)
	ic.position = Vector2(s * 0.19, s * 0.19)
	ring.add_child(ic)
	return ring

func _sign(t: String) -> Label:
	var l := UI.title(t, 30, UI.TEXT, UI.INK)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
