extends RefCounted
## Lecture du build en cours, pour l'interface de partie : où en est chaque branche (paliers), ce qu'une carte
## apporte en plus de son effet, évolutions en préparation. Ne change aucune règle : lit hero.powers, hero.evo,
## hero.branch_count() et Data.TIER_NEED (palier II après 2 cartes prises dans la branche, III après 4).
## Sert à l'écran de choix (barre des branches, ligne « ce que ça débloque » des cartes, scripts/main.gd et
## scripts/ui/card.gd), aux bandeaux de déblocage (scripts/hud.gd) et au rappel du build dans la pause.
## Marche pour l'hôte comme pour l'invité du duo : tout part du `hero` passé (main.hero, le Jo du joueur).

const Data = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const Icon = preload("res://scripts/icon.gd")
const TouchScroll = preload("res://scripts/ui/touch_scroll.gd")

const SOFT := Color("#C4D2E4")

# ---------------------------------------------------------------- calculs
## Palier ouvert (1, 2 ou 3) pour `count` cartes prises dans la branche.
static func open_tier(count: int) -> int:
	var t := 1
	for k in [2, 3]:
		if count >= int(Data.TIER_NEED[k]):
			t = k
	return t

## Progression vers le prochain palier : {target (0 : tout est ouvert), have, need} en cartes depuis le palier
## précédent (deux cartes par palier).
static func next_step(count: int) -> Dictionary:
	var t := open_tier(count)
	if t >= 3:
		return {"target": 0, "have": 0, "need": 0}
	var base := int(Data.TIER_NEED[t])
	return {"target": t + 1, "have": count - base, "need": int(Data.TIER_NEED[t + 1]) - base}

static func _max(id: String) -> int:
	return int(Data.power(id).get("max", 1))

## Pouvoirs de la recette d'une évolution au maximum ; `plus` : ce pouvoir compte un niveau de plus.
static func evo_count(hero: Node, ev: Dictionary, plus: String = "") -> int:
	var k := 0
	for id in ev["need"]:
		var l: int = hero.lv(String(id)) + (1 if String(id) == plus else 0)
		if l >= _max(String(id)):
			k += 1
	return k

## Ce qu'une carte de pouvoir apporte en plus de son effet : lignes {text, col, strong}.
##   « +1 vers le palier II de MOUVEMENT » ; « Débloque le palier III » (doré) ;
##   « Vers ÉVOLUTION : Comète (1/2) » (pouvoirs de la recette au maximum après ce choix, dès que la recette
##   est commencée) ; « Ouvre l'ÉVOLUTION Comète » (doré, la recette sera complète).
static func card_gain(hero: Node, p: Dictionary, level: int) -> Array:
	var out := []
	var id := String(p["id"])
	var bid := String(p["b"])
	var br := Data.branch(bid)
	var c: int = hero.branch_count(bid)
	var t0 := open_tier(c)
	var t1 := open_tier(c + 1)
	if t1 > t0:
		out.append({"text": "Débloque le palier %s" % Data.roman(t1), "col": UI.GOLD, "strong": true})
	elif t0 < 3:
		out.append({"text": "+1 vers le palier %s de %s" % [Data.roman(t0 + 1), String(br["name"]).to_upper()], "col": (br["col"] as Color).lightened(0.35), "strong": false})
	for ev in Data.EVOLUTIONS:
		if not (ev["need"] as Array).has(id) or hero.has_evo(String(ev["id"])):
			continue
		var k := evo_count(hero, ev, id)
		# pas de ligne pour un tout premier pouvoir dont la recette n'est pas commencée : moins de bruit au début
		var engaged := k > 0 or level >= 2
		for other in ev["need"]:
			if String(other) != id and hero.lv(String(other)) > 0:
				engaged = true
		if not engaged:
			break
		if k >= 2:
			out.append({"text": "Ouvre l'ÉVOLUTION %s" % String(ev["name"]), "col": UI.GOLD, "strong": true})
		else:
			out.append({"text": "Vers ÉVOLUTION : %s (%d/2)" % [String(ev["name"]), k], "col": Data.EVO_COL.lightened(0.2), "strong": false})
		break
	if out.is_empty() and level >= int(p["max"]):
		out.append({"text": "Dernier niveau", "col": SOFT, "strong": false})
	return out

## État à comparer avant / après un choix : cartes par branche, évolutions prêtes.
static func snapshot(hero: Node) -> Dictionary:
	var counts := {}
	for bid in Data.BRANCH_ORDER:
		counts[bid] = hero.branch_count(String(bid))
	var ready := []
	for ev in Data.EVOLUTIONS:
		if not hero.has_evo(String(ev["id"])) and evo_count(hero, ev) >= 2:
			ready.append(String(ev["id"]))
	return {"counts": counts, "ready": ready}

## Ce qui vient de s'ouvrir entre deux états : [{kind: "tier", b, tier} | {kind: "evo", id}].
static func unlocks(before: Dictionary, after: Dictionary) -> Array:
	var out := []
	for bid in Data.BRANCH_ORDER:
		var t0 := open_tier(int(before["counts"][bid]))
		var t1 := open_tier(int(after["counts"][bid]))
		if t1 > t0:
			out.append({"kind": "tier", "b": bid, "tier": t1})
	for id in after["ready"]:
		if not (before["ready"] as Array).has(id):
			out.append({"kind": "evo", "id": id})
	return out

## Pictogrammes des pouvoirs que le palier `tier` de la branche ajoute au tirage (au plus `n`).
static func tier_icons(bid: String, tier: int, n: int = 3) -> Array:
	var out := []
	for p in Data.POWERS:
		if String(p["b"]) == bid and int(p["tier"]) == tier and out.size() < n:
			out.append(String(p["id"]))
	return out

## Évolutions en préparation (un pouvoir de la recette au moins pris) ou prises : [{ev, k, taken}], les plus
## avancées d'abord.
static func evo_progress(hero: Node) -> Array:
	var out := []
	for ev in Data.EVOLUTIONS:
		var taken: bool = hero.has_evo(String(ev["id"]))
		var started := false
		for id in ev["need"]:
			if hero.lv(String(id)) > 0:
				started = true
		if taken or started:
			var lv := 0
			for id in ev["need"]:
				lv += mini(hero.lv(String(id)), _max(String(id)))
			out.append({"ev": ev, "k": evo_count(hero, ev), "taken": taken, "lv": lv})
	out.sort_custom(func(a, b):
		if a["taken"] != b["taken"]:
			return not a["taken"]
		if a["k"] != b["k"]:
			return a["k"] > b["k"]
		return a["lv"] > b["lv"])
	return out

# ---------------------------------------------------------------- dessin
## Pastilles de progression (rondes) : `have` pleines sur `need`.
static func _draw_pips(ci: CanvasItem, pos: Vector2, have: int, need: int, col: Color, r: float = 7.0) -> void:
	for i in range(need):
		var c := pos + Vector2(i * (r * 2.0 + 6.0) + r, 0)
		ci.draw_circle(c, r + 2.0, UI.INK)
		if i < have:
			ci.draw_circle(c, r, col)
			ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.3, Color(1, 1, 1, 0.45))
		else:
			ci.draw_arc(c, r - 1.0, 0, TAU, 20, Color(col, 0.75), 2.5, true)

## Coche dessinée (les polices n'ont pas le caractère).
static func _draw_check(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_polyline(PackedVector2Array([c + Vector2(-0.45, 0.0) * s, c + Vector2(-0.12, 0.35) * s, c + Vector2(0.5, -0.4) * s]), col, s * 0.22, true)

## Barre compacte des cinq branches (écran de choix) : « PROCHAIN PALIER », puis par branche son pictogramme,
## deux pastilles (cartes prises vers le prochain palier) et le palier visé ; tout ouvert : « III » et une coche.
static func branch_bar(hero: Node) -> Control:
	UI.load_fonts()
	const CH := 46.0
	const CW := 142.0
	const GAP := 10.0
	var cap := "PROCHAIN PALIER"
	var cap_w := UI.BODY.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 14.0
	var bar := Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size = Vector2(cap_w + (CW + GAP) * Data.BRANCH_ORDER.size() - GAP, CH)
	bar.custom_minimum_size = bar.size
	var draw := Control.new()
	draw.size = bar.size
	draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(draw)
	var chips := []
	for i in range(Data.BRANCH_ORDER.size()):
		var bid := String(Data.BRANCH_ORDER[i])
		var br := Data.branch(bid)
		var x := cap_w + i * (CW + GAP)
		chips.append({"x": x, "b": bid, "col": br["col"], "step": next_step(hero.branch_count(bid))})
		var ic := Icon.new(String(br["icon"]), (br["col"] as Color).lightened(0.15), 28.0)
		ic.position = Vector2(x + 10, (CH - 28.0) * 0.5)
		bar.add_child(ic)
	draw.draw.connect(func():
		draw.draw_string(UI.BODY, Vector2(0, CH * 0.5 + 7), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, SOFT)
		for ch in chips:
			var x: float = ch["x"]
			var col: Color = ch["col"]
			var st: Dictionary = ch["step"]
			var r := Rect2(x, 0, CW, CH)
			var sb := UI.flat(Color(UI.INK, 0.78), Color(col, 0.85), 23, 2)
			draw.draw_style_box(sb, r)
			var tgt: int = st["target"]
			if tgt == 0:
				_draw_pips(draw, Vector2(x + 46, CH * 0.5), 2, 2, col)
				draw.draw_string(UI.TITLE, Vector2(x + 86, CH * 0.5 + 8), "III", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.GOLD)
				_draw_check(draw, Vector2(x + CW - 15, CH * 0.5 - 1), 13.0, UI.GOLD)
			else:
				_draw_pips(draw, Vector2(x + 46, CH * 0.5), int(st["have"]), int(st["need"]), col)
				draw.draw_string(UI.TITLE, Vector2(x + 86, CH * 0.5 + 8), Data.roman(tgt), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UI.TEXT))
	return bar

## Rappel du build dans la pause, à gauche : un bloc par branche commencée (palier ouvert et pastilles vers le
## suivant, pouvoirs pris avec leur niveau « II/III »). Largeur `w` ; au-delà de `max_h`, les niveaux se
## raccourcissent (« II ») puis la liste défile.
static func build_panel(hero: Node, w: float, max_h: float) -> PanelContainer:
	UI.load_fonts()
	var pan := _side_panel(Color("#5AA8FF"))
	pan.custom_minimum_size = Vector2(w, 0)
	var outer := UI.vbox(8)
	pan.add_child(outer)
	outer.add_child(UI.title("TON BUILD", 26, UI.TEXT, UI.ACCENT))
	var groups := []
	for bid in Data.BRANCH_ORDER:
		var c: int = hero.branch_count(String(bid))
		if c <= 0:
			continue
		var ids := []
		for p in Data.POWERS:
			if String(p["b"]) == String(bid) and hero.lv(String(p["id"])) > 0:
				ids.append(String(p["id"]))
		groups.append({"b": String(bid), "c": c, "ids": ids})
	if groups.is_empty():
		var e := UI.label("Aucun pouvoir pour l'instant. Remplis la barre d'énergie pour en choisir un.", 22, SOFT)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.custom_minimum_size = Vector2(w - 36, 0)
		outer.add_child(e)
		return pan
	var inner_w := w - 36.0
	var avail := max_h - 30.0 - 42.0
	var short := _groups_h(hero, groups, inner_w, false) > avail
	var v := UI.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _groups_h(hero, groups, inner_w, short) > avail:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.custom_minimum_size = Vector2(inner_w, avail)
		outer.add_child(sc)
		sc.add_child(v)
		TouchScroll.attach(sc)
	else:
		outer.add_child(v)
	for g in groups:
		var br := Data.branch(String(g["b"]))
		var col: Color = br["col"]
		var c: int = g["c"]
		var head := UI.hbox(8)
		v.add_child(head)
		var bi := Icon.new(String(br["icon"]), col, 26.0)
		bi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(bi)
		var hl := UI.label("%s · PALIER %s" % [String(br["name"]).to_upper(), Data.roman(open_tier(c))], 20, col.lightened(0.3))
		hl.add_theme_font_override("font", UI.TITLE)
		head.add_child(hl)
		var st := next_step(c)
		if int(st["target"]) > 0:
			var pip := Control.new()
			pip.custom_minimum_size = Vector2(40, 24)
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pip.draw.connect(func(): _draw_pips(pip, Vector2(4, 12), int(st["have"]), int(st["need"]), col, 6.0))
			head.add_child(pip)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 6)
		v.add_child(flow)
		for id in g["ids"]:
			flow.add_child(_power_chip(String(id), col, hero.lv(String(id)), int(Data.power(String(id))["max"]), false, short))
	return pan

## Hauteur estimée des blocs de branche (pour choisir niveaux courts / défilement).
static func _groups_h(hero: Node, groups: Array, inner_w: float, short: bool) -> float:
	var h := 0.0
	for g in groups:
		var rows := 1
		var x := 0.0
		for id in g["ids"]:
			var cw := 42.0 + UI.BODY.get_string_size(_lv_text(hero.lv(String(id)), int(Data.power(String(id))["max"]), short), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			if x > 0.0 and x + cw > inner_w:
				rows += 1
				x = 0.0
			x += cw + 10.0
		h += 28.0 + 8.0 + rows * 38.0 + (rows - 1) * 6.0 + 8.0
	return h

static func _lv_text(l: int, mx: int, short: bool) -> String:
	if short:
		return Data.roman(l) if l > 0 else "0"
	return ("%s/%s" % [Data.roman(l), Data.roman(mx)]) if l > 0 else "0/%s" % Data.roman(mx)

## Évolutions en préparation, à droite de la pause : nom, avancement « 1/2 » (pouvoirs de la recette au
## maximum), PRÊTE ou PRISE ; dessous la recette, pictogrammes et niveaux. Autant de lignes que `max_h` permet.
static func evo_panel(hero: Node, w: float, max_h: float) -> PanelContainer:
	UI.load_fonts()
	var gold: Color = Data.EVO_COL
	var pan := _side_panel(gold)
	pan.custom_minimum_size = Vector2(w, 0)
	var v := UI.vbox(10)
	pan.add_child(v)
	v.add_child(UI.title("ÉVOLUTIONS", 26, gold.lightened(0.15), UI.ORANGE))
	var list := evo_progress(hero)
	if list.is_empty():
		var e := UI.label("Deux pouvoirs précis au maximum ouvrent une évolution : voir POUVOIRS au Relais.", 22, SOFT)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.custom_minimum_size = Vector2(w - 36, 0)
		v.add_child(e)
		return pan
	v.add_child(UI.label("1/2 : pouvoirs de la recette au maximum", 20, SOFT))
	var used := 30.0 + 42.0 + 34.0
	var shown := 0
	for it in list:
		var ev: Dictionary = it["ev"]
		# hauteur de la ligne : nom, puis recette sur une ou deux lignes
		var need: Array = ev["need"]
		var rw := 0.0
		for id in need:
			rw += 42.0 + 14.0 + UI.BODY.get_string_size(String(Data.power(String(id))["name"]) + " " + _lv_text(hero.lv(String(id)), int(Data.power(String(id))["max"]), false), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var rh := 28.0 + 4.0 + (38.0 if rw <= w - 36.0 else 80.0) + 10.0
		if used + rh > max_h - 30.0 and shown > 0:
			break
		used += rh
		shown += 1
		var row := UI.vbox(4)
		v.add_child(row)
		var h1 := UI.hbox(8)
		row.add_child(h1)
		var nm := UI.label(String(ev["name"]).to_upper(), 20, gold.lightened(0.2))
		nm.add_theme_font_override("font", UI.TITLE)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h1.add_child(nm)
		var state := "%d/2" % int(it["k"])
		var scol := Color("#2A3F6E")
		var fcol := UI.TEXT
		if it["taken"]:
			state = "PRISE"
			scol = gold
			fcol = UI.INK
		elif int(it["k"]) >= 2:
			state = "PRÊTE"
			scol = gold
			fcol = UI.INK
		h1.add_child(UI.tag(state, scol, fcol, 20))
		var h2 := HFlowContainer.new()
		h2.add_theme_constant_override("h_separation", 14)
		h2.add_theme_constant_override("v_separation", 4)
		row.add_child(h2)
		for id in need:
			var p := Data.power(String(id))
			h2.add_child(_power_chip(String(id), Data.branch(String(p["b"]))["col"], hero.lv(String(id)), int(p["max"]), true))
	if list.size() > shown:
		var more := list.size() - shown
		v.add_child(UI.label("+ %d autre%s en préparation" % [more, "s" if more > 1 else ""], 20, SOFT))
	return pan

static func _side_panel(col: Color) -> PanelContainer:
	var pan := PanelContainer.new()
	var st := UI.flat(Color("#0D1830", 0.94), Color(col, 0.45), 18, 2)
	st.border_width_top = 5
	st.border_color = col
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 14
	st.content_margin_bottom = 16
	pan.add_theme_stylebox_override("panel", st)
	pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pan

## Pouvoir pris : pictogramme dans un anneau, niveau « II/III » à côté (doré au maximum). `wide` : nom
## complet en plus (recettes d'évolution).
static func _power_chip(id: String, col: Color, l: int, mx: int, wide: bool = false, short: bool = false) -> HBoxContainer:
	var h := UI.hbox(4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := Panel.new()
	ring.custom_minimum_size = Vector2(38, 38)
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ring.add_theme_stylebox_override("panel", UI.flat(Color(col, 0.16 if l > 0 else 0.05), Color(col, 0.9 if l > 0 else 0.35), 19, 2))
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ring)
	var ic := Icon.new(id, col.lightened(0.15) if l > 0 else Color(col, 0.45), 26.0)
	ic.position = Vector2(6, 6)
	ring.add_child(ic)
	var full := l >= mx
	var txt := _lv_text(l, mx, short)
	if wide:
		txt = String(Data.power(id)["name"]) + " " + txt
	var lb := UI.label(txt, 20, UI.GOLD if full else UI.TEXT)
	lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(lb)
	return h
