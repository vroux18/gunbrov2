extends RefCounted
## Lecture du build en cours, pour l'interface de partie. Principe : peu de choses, en gros, en images ; une
## seule information par endroit. Ne change aucune règle : lit hero.powers, hero.evo, hero.branch_count() et
## Data.TIER_NEED (nouveaux pouvoirs d'une branche après 2 puis 4 cartes prises dedans).
## Sert à l'écran de choix (au plus une ligne dorée par carte, scripts/main.gd et scripts/ui/card.gd), aux
## bandeaux de déblocage (scripts/hud.gd) et à la pause (grille TES POUVOIRS, évolution la plus proche).
## Marche pour l'hôte comme pour l'invité du duo : tout part du `hero` passé (main.hero, le Jo du joueur).

const Data = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const Icon = preload("res://scripts/icon.gd")
const TouchScroll = preload("res://scripts/ui/touch_scroll.gd")

const SOFT := Color("#C4D2E4")
const PANEL_BG := Color("#0A1328")  # fond opaque des panneaux de la pause
const PAD := 20.0
const TEXT_UNLOCK := "Débloque de nouveaux pouvoirs"
const TEXT_EVO := "Prépare une évolution"

# ---------------------------------------------------------------- calculs
## Palier ouvert (1, 2 ou 3) pour `count` cartes prises dans la branche.
static func open_tier(count: int) -> int:
	var t := 1
	for k in [2, 3]:
		if count >= int(Data.TIER_NEED[k]):
			t = k
	return t

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

## Ce qu'une carte de pouvoir apporte en plus de son effet, seulement si ça compte : au plus une ligne
## {text, col, strong}, toujours dorée.
##   « Débloque de nouveaux pouvoirs » : ce choix ouvre le palier suivant de la branche ;
##   « Prépare une évolution » : l'autre pouvoir de la recette est déjà pris, et ce choix met celui-ci au
##   maximum ou l'autre y est déjà (la recette avance pour de bon).
static func card_gain(hero: Node, p: Dictionary, level: int) -> Array:
	var id := String(p["id"])
	var c: int = hero.branch_count(String(p["b"]))
	if open_tier(c + 1) > open_tier(c):
		return [{"text": TEXT_UNLOCK, "col": UI.GOLD, "strong": true}]
	for ev in Data.EVOLUTIONS:
		if not (ev["need"] as Array).has(id) or hero.has_evo(String(ev["id"])):
			continue
		for other in ev["need"]:
			var o := String(other)
			if o == id or hero.lv(o) <= 0:
				continue
			if level >= _max(id) or hero.lv(o) >= _max(o):
				return [{"text": TEXT_EVO, "col": UI.GOLD, "strong": true}]
	return []

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

## Évolution la plus proche, pas encore prise, dont un pouvoir de la recette au moins est pris : {ev, k}, ou
## {} s'il n'y en a pas. La plus avancée : recettes au maximum d'abord, puis niveaux cumulés.
static func next_evo(hero: Node) -> Dictionary:
	var best := {}
	var best_score := -1
	for ev in Data.EVOLUTIONS:
		if hero.has_evo(String(ev["id"])):
			continue
		var lv := 0
		var started := false
		for id in ev["need"]:
			lv += mini(hero.lv(String(id)), _max(String(id)))
			started = started or hero.lv(String(id)) > 0
		if not started:
			continue
		var k := evo_count(hero, ev)
		var score := k * 100 + lv
		if score > best_score:
			best_score = score
			best = {"ev": ev, "k": k}
	return best

# ---------------------------------------------------------------- dessin
## Panneau de la pause : fond sombre opaque, liseré fin, un trait de couleur en haut.
static func _side_panel(col: Color) -> PanelContainer:
	var pan := PanelContainer.new()
	var st := UI.flat(PANEL_BG, Color(col, 0.35), 20, 2)
	st.border_width_top = 4
	st.content_margin_left = PAD
	st.content_margin_right = PAD
	st.content_margin_top = 14
	st.content_margin_bottom = PAD
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 14
	pan.add_theme_stylebox_override("panel", st)
	pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pan

## Petit titre discret en haut d'un panneau.
static func _caption(text: String, col: Color) -> Label:
	var l := UI.label(text, 20, col)
	l.add_theme_font_override("font", UI.TITLE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Pictogramme dans un disque sombre cerclé de `col` (taille `s`).
static func _disc(icon: String, col: Color, s: float, ring: float = 3.0) -> Panel:
	var d := Panel.new()
	d.custom_minimum_size = Vector2(s, s)
	d.size = Vector2(s, s)
	d.add_theme_stylebox_override("panel", UI.flat(col.darkened(0.66), col, int(s * 0.5), int(ring)))
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Icon.new(icon, col.lightened(0.2), s * 0.6)
	ic.position = Vector2.ONE * s * 0.2
	d.add_child(ic)
	return d

## Pastilles de niveau : `l` pleines sur `mx` (au plus 5), centrées sur `cx`.
static func _draw_pips(ci: CanvasItem, cx: float, y: float, l: int, mx: int, col: Color, r: float) -> void:
	var n := mini(mx, 5)
	var step := r * 2.0 + 5.0
	var x0 := cx - (n - 1) * step * 0.5
	for i in range(n):
		var c := Vector2(x0 + i * step, y)
		if i < l:
			ci.draw_circle(c, r, col.lightened(0.2))
		else:
			ci.draw_arc(c, r - 1.0, 0, TAU, 16, Color(col, 0.55), 2.0, true)

## Coche dessinée (les polices n'ont pas le caractère), dans une pastille dorée.
static func _draw_check_badge(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r + 2.0, UI.INK)
	ci.draw_circle(c, r, UI.GOLD)
	ci.draw_polyline(PackedVector2Array([c + Vector2(-0.45, 0.02) * r, c + Vector2(-0.1, 0.38) * r, c + Vector2(0.5, -0.36) * r]), UI.INK, r * 0.3, true)

## Pause, à gauche : TES POUVOIRS, une grille de pictogrammes (évolutions prises d'abord, en doré, puis les
## pouvoirs par branche), pastilles de niveau dessous ; aucun nom, aucun chiffre. Toucher un pictogramme montre
## son nom et son effet dans une bulle. Les pictogrammes prennent la plus grande taille (76 à 56 px) qui tient
## dans `max_h` ; au-delà, la grille défile.
static func powers_panel(hero: Node, w: float, max_h: float) -> PanelContainer:
	UI.load_fonts()
	var pan := _side_panel(Color("#8FA6C8"))
	pan.custom_minimum_size = Vector2(w, 0)
	var v := UI.vbox(14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pan.add_child(v)
	v.add_child(_caption("TES POUVOIRS", SOFT))
	var items := []
	for ev in Data.EVOLUTIONS:
		if hero.has_evo(String(ev["id"])):
			items.append({"icon": String(ev["icon"]), "col": Data.EVO_COL, "l": 0, "mx": 0, "name": String(ev["name"]), "text": String(ev["desc"])})
	for bid in Data.BRANCH_ORDER:
		for p in Data.POWERS:
			var id := String(p["id"])
			if String(p["b"]) == String(bid) and hero.lv(id) > 0:
				items.append({"icon": id, "col": Data.branch(String(bid))["col"], "l": hero.lv(id), "mx": int(p["max"]), "name": String(p["name"]), "text": Data.power_text(p, hero.lv(id))})
	if items.is_empty():
		v.add_child(UI.label("Aucun pour l'instant", 22, SOFT))
		return pan
	var inner := w - PAD * 2.0
	var avail := max_h - 14.0 - PAD - 28.0 - 14.0
	var gap := 12.0
	var t := 56.0
	var cols := 1
	var fits := false
	for s in [76.0, 68.0, 62.0, 56.0]:
		var g := 14.0 if s > 62.0 else 10.0
		var c := maxi(1, int((inner + g) / (s + g)))
		var rows := ceili(float(items.size()) / c)
		t = s
		gap = g
		cols = c
		if rows * (s + 18.0) + (rows - 1) * g <= avail:
			fits = true
			break
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", int(gap))
	grid.add_theme_constant_override("v_separation", int(gap))
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fits:
		v.add_child(grid)
	else:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.custom_minimum_size = Vector2(inner, avail)
		sc.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(sc)
		sc.add_child(grid)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		TouchScroll.attach(sc)
	for it in items:
		grid.add_child(_power_tile(pan, it, t))
	return pan

## Un pouvoir pris : grand pictogramme cerclé de sa couleur de branche, pastilles de niveau dessous.
static func _power_tile(pan: Control, it: Dictionary, t: float) -> Control:
	var col: Color = it["col"]
	var is_evo := int(it["mx"]) == 0
	var tile := Control.new()
	tile.custom_minimum_size = Vector2(t, t + 18.0)
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	var d := _disc(String(it["icon"]), col, t, 4.0 if is_evo else 3.0)
	tile.add_child(d)
	if not is_evo:
		var r := clampf(t * 0.075, 4.0, 5.5)
		tile.draw.connect(func(): _draw_pips(tile, t * 0.5, t + 10.0, int(it["l"]), int(it["mx"]), col, r))
	tile.gui_input.connect(func(e: InputEvent):
		var tap: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
		if tap:
			_bubble(pan, tile, it))
	return tile

## Bulle d'un pictogramme touché : nom et effet, 2,5 s, une seule à la fois.
static func _bubble(pan: Control, tile: Control, it: Dictionary) -> void:
	var old = pan.get_meta("bubble") if pan.has_meta("bubble") else null
	if old != null and is_instance_valid(old):
		if old.get_meta("for") == tile:
			return
		old.queue_free()
	var col: Color = it["col"]
	var b := PanelContainer.new()
	var st := UI.flat(Color("#060C1C"), col, 14, 3)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 10
	st.content_margin_bottom = 12
	st.shadow_color = Color(0, 0, 0, 0.6)
	st.shadow_size = 12
	b.add_theme_stylebox_override("panel", st)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.top_level = true
	b.set_meta("for", tile)
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var n := UI.title(String(it["name"]), 24, UI.TEXT, col)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var tx := UI.label(String(it["text"]), 20, SOFT)
	tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tx.custom_minimum_size = Vector2(260, 0)
	tx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tx)
	pan.add_child(b)
	pan.set_meta("bubble", b)
	b.reset_size()
	var vs := pan.get_viewport().get_visible_rect().size
	var p := tile.global_position + Vector2(tile.size.x + 10.0, -6.0)
	b.position = Vector2(clampf(p.x, 8.0, vs.x - b.size.x - 8.0), clampf(p.y, 8.0, vs.y - b.size.y - 8.0))
	b.modulate.a = 0.0
	var tw := b.create_tween()
	tw.tween_property(b, "modulate:a", 1.0, 0.12)
	tw.tween_interval(2.5)
	tw.tween_property(b, "modulate:a", 0.0, 0.25)
	tw.tween_callback(b.queue_free)

## Pause, à droite : l'évolution la plus proche seulement (null si aucune n'est commencée). Grand pictogramme,
## son nom, ses deux ingrédients (coche au maximum, sinon pastilles de niveau) et une phrase courte.
static func evo_panel(hero: Node, w: float) -> PanelContainer:
	var it := next_evo(hero)
	if it.is_empty():
		return null
	UI.load_fonts()
	var gold: Color = Data.EVO_COL
	var ev: Dictionary = it["ev"]
	var ready := int(it["k"]) >= 2
	var pan := _side_panel(gold)
	pan.custom_minimum_size = Vector2(w, 0)
	var v := UI.vbox(10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pan.add_child(v)
	var cap := _caption("ÉVOLUTION PRÊTE" if ready else "PROCHAINE ÉVOLUTION", gold.lightened(0.1) if ready else SOFT)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var big := _disc(String(ev["icon"]), gold, 112.0, 5.0)
	big.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(big)
	var nm := UI.title(String(ev["name"]).to_upper(), 28, UI.TEXT, UI.ORANGE, HORIZONTAL_ALIGNMENT_CENTER)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(w - PAD * 2.0, 0)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)
	# recette : deux ingrédients et un « + »
	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	var missing := []
	var need: Array = ev["need"]
	for j in range(2):
		var id := String(need[j])
		var p := Data.power(id)
		var col: Color = Data.branch(String(p["b"]))["col"]
		var l: int = hero.lv(id)
		var mx := int(p["max"])
		if l < mx:
			missing.append(String(p["name"]))
		const S := 68.0
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(S, S + 20.0)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d := _disc(id, col if l > 0 else col.darkened(0.35), S)
		if l <= 0:
			d.modulate = Color(1, 1, 1, 0.55)
		cell.add_child(d)
		var deco := Control.new()
		deco.size = cell.custom_minimum_size
		deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deco.draw.connect(func():
			if l >= mx:
				_draw_check_badge(deco, Vector2(S - 8.0, S - 8.0), 13.0)
			else:
				_draw_pips(deco, S * 0.5, S + 11.0, l, mx, col, 5.0))
		cell.add_child(deco)
		row.add_child(cell)
		if j == 0:
			var plus := UI.title("+", 34, UI.TEXT, UI.INK)
			plus.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			plus.custom_minimum_size = Vector2(0, S)
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(plus)
	# une phrase de 5 mots au plus
	var say := "Elle sortira au prochain choix"
	if missing.size() == 1:
		say = "Monte %s au max" % String(missing[0])
	elif missing.size() == 2:
		say = "Monte les deux au max"
	var sl := UI.label(say, 22, gold.lightened(0.25) if ready else SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.custom_minimum_size = Vector2(w - PAD * 2.0, 0)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sl)
	return pan
