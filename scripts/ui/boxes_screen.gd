extends Control
## Écran COFFRES du Relais, deux onglets. Jo reste visible à gauche (gros plan du Relais 3D).
## COFFRES : la box choisie en 3D qui se balance, ses quatre raretés avec leur nombre, OUVRIR, TOUT OUVRIR.
## COLLECTION : apparences de Jo et traînées de tir, obtenues ou verrouillées (silhouette, rareté),
## compteur « 12 / 30 » ; toucher une apparence obtenue l'équipe (Jo change aussitôt au Relais et en jeu).

const UI = preload("res://scripts/ui.gd")
const Fx = preload("res://scripts/ui/fx.gd")
const Save = preload("res://scripts/save.gd")
const Loot = preload("res://scripts/loot.gd")
const Art = preload("res://scripts/ui/boxes_art.gd")
const Stage = preload("res://scripts/ui/boxes_stage.gd")
const Opener = preload("res://scripts/ui/boxes_open.gd")

var main: Node
var tab := "coffres"
var sel := ""  # rareté choisie
var body: Control  # contenu de l'onglet
var stage: Stage = null
var opener: Control = null
var toast: Label
var vs := Vector2(1280, 720)
var t := 0.0
var _anim: Array = []  # vignettes animées (traînées, prisme)

func build(m: Node, which: String, fresh: bool) -> void:
	main = m
	tab = which
	UI.load_fonts()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	vs = get_viewport().get_visible_rect().size
	add_child(main._side_shade(0.2))
	if fresh:
		Fx.screen_in(self)
	_refresh(fresh)

func _left() -> float:
	return 0.33

func _refresh(anim: bool = false) -> void:
	if body != null:
		body.queue_free()
	stage = null
	_anim.clear()
	body = Control.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	var ins := UI.safe_insets(get_viewport())
	var x0 := vs.x * _left()
	var x1 := vs.x - 24.0 - float(ins["right"])
	# ---------------- en-tête : onglets, RETOUR
	var head := UI.hbox(12)
	head.position = Vector2(x0, clampf(vs.y * 0.04, 14.0, 36.0))
	head.size = Vector2(x1 - x0, 78)
	body.add_child(head)
	var nb := (main.profile["boxes"] as Array).size()
	var tb1 := _tab_button("COFFRES", "coffres", str(nb) if nb > 0 else "", UI.GOLD)
	head.add_child(tb1)
	var tb2 := _tab_button("COLLECTION", "collection", "%d/%d" % [Loot.owned_count(main.profile), Loot.total_count()], UI.ACCENT)
	head.add_child(tb2)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var back := UI.primary("RETOUR", 24)
	back.custom_minimum_size = Vector2(150, 74)
	back.pressed.connect(main.show_base)
	head.add_child(back)
	var area := Rect2(x0, head.position.y + 96.0, x1 - x0, vs.y - head.position.y - 96.0 - 18.0 - float(ins["bottom"]))
	if tab == "coffres":
		_build_coffres(area, anim)
	else:
		_build_collection(area, anim)
	toast = UI.label("", 22, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	toast.position = Vector2(x0, vs.y - 54.0)
	toast.size = Vector2(x1 - x0, 30)
	toast.add_theme_color_override("font_outline_color", UI.INK)
	toast.add_theme_constant_override("outline_size", 6)
	toast.modulate.a = 0.0
	body.add_child(toast)
	if anim:
		Fx.slide_in(head, Vector2(120, 0), 0.0, 0.35)

func _tab_button(text: String, which: String, badge: String, col: Color) -> Button:
	var on := tab == which
	var b := UI.button(text, 26, col if on else UI.MUTED, 0.0)
	b.custom_minimum_size = Vector2(0, 74)
	b.add_theme_font_override("font", UI.TITLE)
	if on:
		b.add_theme_stylebox_override("normal", UI.chunky(col.darkened(0.55), col.darkened(0.2)))
		b.add_theme_stylebox_override("hover", UI.chunky(col.darkened(0.55), col.darkened(0.2)))
		b.add_theme_color_override("font_color", UI.TEXT)
	if badge != "":
		# pastille en haut à droite, comme LOGE et ARSENAL
		var tg := UI.tag(badge, col, UI.INK, 18)
		tg.anchor_left = 1.0
		tg.anchor_right = 1.0
		tg.offset_left = -20.0 - 11.0 * badge.length()
		tg.offset_top = -14
		b.add_child(tg)
	b.pressed.connect(func():
		if tab != which:
			tab = which
			main.sfx.play("click", 1.0, -6.0)
			_refresh(true))
	return b

# ---------------------------------------------------------------- COFFRES
func _build_coffres(area: Rect2, anim: bool) -> void:
	var p: Dictionary = main.profile
	var total := (p["boxes"] as Array).size()
	if sel == "" or Loot.count(p, sel) == 0:
		sel = ""
		# la plus belle box disponible d'abord
		for r in ["legendaire", "or", "argent", "bronze"]:
			if Loot.count(p, r) > 0:
				sel = r
				break
	var shown := sel if sel != "" else "or"
	var col: Color = Loot.BOX_COLORS[shown]
	# ---- à gauche : la box en 3D, son nom, OUVRIR
	var lw := area.size.x * 0.52
	var s := minf(lw, area.size.y - 190.0)
	# vitrine : panneau sombre, halo de la rareté, socle lumineux sous la box
	var pane := Panel.new()
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.position = area.position + Vector2(0, -6)
	pane.size = Vector2(lw, area.size.y + 6)
	pane.add_theme_stylebox_override("panel", UI.flat(Color("#0A1430", 0.82), Color(col, 0.3), 22, 2))
	body.add_child(pane)
	var halo := Fx.halo(Color(col, 0.4 if sel != "" else 0.12), Vector2(s * 1.2, s * 1.0))
	halo.position = area.position + Vector2((lw - s * 1.2) * 0.5, s * -0.05)
	body.add_child(halo)
	var base := Control.new()
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.position = area.position + Vector2(lw * 0.5, s * 0.66)
	base.draw.connect(func():
		base.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.25))
		for k in range(5):
			base.draw_circle(Vector2.ZERO, s * (0.36 - k * 0.05), Color(col, 0.06 + 0.03 * k if sel != "" else 0.03)))
	body.add_child(base)
	Fx.pulse(halo, 0.6, 1.0, 1.6)
	stage = Stage.new()
	stage.setup(shown, Vector2(s, s))
	stage.position = area.position + Vector2((lw - s) * 0.5, -s * 0.06)
	stage.yaw = -0.45
	body.add_child(stage)
	if sel == "":
		stage.modulate = Color(0.45, 0.5, 0.6, 0.8)
	var name_y := stage.position.y + s * 0.86
	var nm := UI.title(("BOX " + String(Loot.BOX_NAMES[shown]).to_upper()) if sel != "" else "AUCUNE BOX", 34, col.lightened(0.3) if sel != "" else UI.MUTED, col.darkened(0.5), HORIZONTAL_ALIGNMENT_CENTER)
	nm.position = Vector2(area.position.x, name_y)
	nm.size = Vector2(lw, 44)
	body.add_child(nm)
	var hint := UI.label(Loot.BOX_HINT[shown] if sel != "" else "Bats le boss d'un monde : une box Or, et une Légendaire la première fois. Les élites et la route Trésor en donnent aussi.", 18, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	hint.position = Vector2(area.position.x + 10, name_y + 44)
	hint.size = Vector2(lw - 20, 48)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_outline_color", UI.INK)
	hint.add_theme_constant_override("outline_size", 4)
	body.add_child(hint)
	if sel != "":
		var row := UI.hbox(12)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.position = Vector2(area.position.x, minf(name_y + 96.0, area.end.y - 84.0))
		row.size = Vector2(lw, 84)
		body.add_child(row)
		var ob := UI.primary("OUVRIR", 34, 210)
		ob.custom_minimum_size = Vector2(210, 84)
		ob.pressed.connect(func(): open([sel], false))
		row.add_child(ob)
		Fx.shine(ob, 260.0, 2.2, 0.5)
		if total > 1:
			var ab := UI.button("TOUT  ×%d" % total, 24, UI.ORANGE, 170)
			ab.custom_minimum_size = Vector2(170, 84)
			ab.pressed.connect(func(): open((p["boxes"] as Array).duplicate(), true))
			row.add_child(ab)
		if anim:
			Fx.rise_in(row, 0.2, 0.34, 0.7)
	# ---- à droite : les quatre raretés
	var rx := area.position.x + lw + 16.0
	var rw := area.end.x - rx
	var th := minf(112.0, (area.size.y - 30.0) / 4.0 - 10.0)
	var i := 0
	for r in ["legendaire", "or", "argent", "bronze"]:
		var b := _box_tile(r, Vector2(rw, th))
		b.position = Vector2(rx, area.position.y + 4.0 + i * (th + 10.0))
		body.add_child(b)
		if anim:
			Fx.slide_in(b, Vector2(90, 0), 0.06 + 0.05 * i, 0.32)
		i += 1

func _box_tile(r: String, sz: Vector2) -> Button:
	var n := Loot.count(main.profile, r)
	var col: Color = Loot.BOX_COLORS[r]
	var on := r == sel
	var b := Button.new()
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	var st := UI.flat(Color("#15234A", 0.94) if not on else Color("#1E2F5E", 0.97), col if on else Color(col, 0.35), 18, 4 if on else 2)
	st.border_width_left = 8
	for k in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(k, st)
	var art := Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size = sz
	art.draw.connect(func():
		Art.draw_box(art, Vector2(20 + sz.y * 0.5, sz.y * 0.52), sz.y * 0.7, r, n == 0))
	b.add_child(art)
	var nm := UI.title(String(Loot.BOX_NAMES[r]).to_upper(), 24, UI.TEXT if n > 0 else UI.MUTED, col.darkened(0.55))
	nm.position = Vector2(30 + sz.y, sz.y * 0.5 - 30)
	nm.size = Vector2(sz.x - sz.y - 120, 34)
	b.add_child(nm)
	var tp := UI.label("%d coup%s pour l'ouvrir" % [Loot.BOX_TAPS[r], "s" if int(Loot.BOX_TAPS[r]) > 1 else ""], 16, UI.MUTED)
	tp.position = Vector2(30 + sz.y, sz.y * 0.5 + 4)
	tp.size = Vector2(sz.x - sz.y - 120, 24)
	b.add_child(tp)
	var cnt := UI.title("×%d" % n, 34, col.lightened(0.25) if n > 0 else UI.LINE, UI.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	cnt.position = Vector2(sz.x - 110, 0)
	cnt.size = Vector2(92, sz.y)
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(cnt)
	b.pressed.connect(func():
		if n > 0 and sel != r:
			sel = r
			main.sfx.play("click", 1.1, -6.0)
			_refresh()
		elif n == 0:
			_toast("Aucune box %s pour l'instant" % String(Loot.BOX_NAMES[r]), col))
	return b

## Ouvre une série de box (plein écran) ; à la fin, retour à l'écran à jour.
func open(boxes: Array, serial: bool) -> void:
	if opener != null or boxes.is_empty():
		return
	main.sfx.play("click", 0.9, -4.0)
	opener = Opener.new()
	add_child(opener)
	opener.start(main, boxes, serial)
	Fx.screen_in(opener, 0.15)
	opener.finished.connect(func():
		Fx.screen_out(opener, 0.18)
		opener = null
		main.on_boxes_changed()
		_refresh(true))

# ---------------------------------------------------------------- COLLECTION
func _build_collection(area: Rect2, anim: bool) -> void:
	var p: Dictionary = main.profile
	var head := UI.hbox(14)
	head.position = area.position
	head.size = Vector2(area.size.x, 46)
	body.add_child(head)
	var big := UI.title("%d / %d" % [Loot.owned_count(p), Loot.total_count()], 36, UI.ACCENT, UI.INK)
	head.add_child(big)
	var sub := UI.label("Touche un cosmétique obtenu pour l'équiper. Les autres sortent des box.", 19, UI.MUTED)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.position = area.position + Vector2(0, 54)
	scroll.size = area.size - Vector2(0, 54)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list := UI.vbox(10)
	list.custom_minimum_size = Vector2(area.size.x - 14.0, 0)
	scroll.add_child(list)
	var cols := clampi(int((area.size.x - 14.0 + 10.0) / 150.0), 3, 8)
	var tw := (area.size.x - 14.0 - (cols - 1) * 10.0) / cols
	for sec in [["skin", "APPARENCES DE JO", Loot.SKINS, "skins", "skin"], ["trail", "TRAÎNÉES DE TIR", Loot.TRAILS, "trails", "trail"]]:
		var owned: Array = p[sec[3]]
		var h := UI.hbox(10)
		list.add_child(h)
		h.add_child(UI.title(String(sec[1]), 24, UI.TEXT, UI.INK))
		h.add_child(UI.title("%d / %d" % [owned.size(), (sec[2] as Array).size()], 24, UI.MUTED, UI.INK))
		var grid := GridContainer.new()
		grid.columns = cols
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		list.add_child(grid)
		for c in sec[2]:
			var b := _cosmetic_tile(String(sec[0]), c, owned.has(c["id"]), String(p[sec[4]]) == String(c["id"]), Vector2(tw, tw * 1.12))
			grid.add_child(b)
			if anim:
				Fx.rise_in(b, 0.04 + 0.012 * grid.get_child_count(), 0.26, 0.8)

func _cosmetic_tile(kind: String, c: Dictionary, owned: bool, equipped: bool, sz: Vector2) -> Button:
	var tier := int(c["tier"])
	var col: Color = Loot.TIER_COLORS[tier]
	var b := Button.new()
	b.custom_minimum_size = sz
	b.focus_mode = Control.FOCUS_NONE
	var st := UI.flat(Color("#15234A", 0.94) if owned else Color("#0D1730", 0.94), col if equipped else Color(col, 0.55 if owned else 0.22), 16, 4 if equipped else 2)
	st.border_width_bottom = 7
	for k in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(k, st)
	var art := Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2(sz.x * 0.14, 10)
	art.size = Vector2(sz.x * 0.72, sz.y * 0.6)
	var animated := kind == "trail" or bool(c.get("rainbow", false))
	art.draw.connect(func():
		if kind == "skin":
			Art.draw_skin(art, Rect2(Vector2.ZERO, art.size), c, not owned, t)
		else:
			Art.draw_trail(art, Rect2(Vector2(0, art.size.y * 0.15), art.size * Vector2(1, 0.7)), c, not owned, t))
	b.add_child(art)
	if animated and owned:
		_anim.append(art)
	var nm := UI.label(String(c["name"]) if owned else "???", 19, UI.TEXT if owned else UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	nm.position = Vector2(4, sz.y * 0.64)
	nm.size = Vector2(sz.x - 8, 24)
	nm.clip_text = true
	b.add_child(nm)
	var tl := UI.label(Loot.TIER_NAMES[tier], 14, col if owned else Color(col, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	tl.position = Vector2(4, sz.y * 0.64 + 22)
	tl.size = Vector2(sz.x - 8, 20)
	b.add_child(tl)
	if equipped:
		var tg := UI.tag("ÉQUIPÉ", col, UI.INK, 14)
		tg.position = Vector2(6, 6)
		b.add_child(tg)
	b.pressed.connect(func():
		if not owned:
			_toast("%s %s : à gagner dans les box" % ["Apparence" if kind == "skin" else "Traînée", Loot.TIER_NAMES[tier].to_lower()], col)
			main.sfx.play("click", 0.7, -8.0)
			return
		if equipped:
			return
		main.profile[kind] = String(c["id"])
		Save.save_profile(main.profile)
		main.on_boxes_changed()
		main.sfx.play("pick", 1.1, -4.0)
		var keep := _scroll_pos()
		_refresh()
		_set_scroll(keep)
		_toast("%s équipée : %s" % ["Apparence" if kind == "skin" else "Traînée", String(c["name"])], col))
	return b

func _scroll_pos() -> int:
	for s in body.find_children("*", "ScrollContainer", true, false):
		return (s as ScrollContainer).scroll_vertical
	return 0

func _set_scroll(v: int) -> void:
	for s in body.find_children("*", "ScrollContainer", true, false):
		(s as ScrollContainer).set_deferred("scroll_vertical", v)

func _toast(text: String, col: Color) -> void:
	toast.text = text
	toast.add_theme_color_override("font_color", col.lightened(0.3))
	toast.modulate.a = 1.0
	var tw := Fx._tw(toast)
	tw.tween_interval(1.6)
	tw.tween_property(toast, "modulate:a", 0.0, 0.4)

func _process(dt: float) -> void:
	t += dt
	for a in _anim:
		if is_instance_valid(a):
			(a as Control).queue_redraw()
