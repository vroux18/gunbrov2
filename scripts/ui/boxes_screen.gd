extends Control
## Écrans COFFRES et APPARENCES du Relais (identifiants internes : « coffres », « collection »), sous le bandeau
## commun (UI.screen_header). Jo reste visible à gauche (gros plan du Relais 3D).
## COFFRES : le coffre choisi en 3D qui se balance, ce qu'il contient en clair, OUVRIR, TOUT ; à droite les
## quatre raretés avec leur nombre.
## APPARENCES : apparences de Jo et traînées de tir, obtenues ou verrouillées (silhouette, rareté), en grandes
## tuiles qui défilent ; toucher une apparence obtenue l'équipe (Jo change aussitôt au Relais et en jeu).

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
	return 0.335

## Ce que contient chaque coffre, en clair (tirage : scripts/loot.gd, Loot.roll).
const CONTENTS := {
	"bronze": ["25 à 75 tickets", "1 objet, le plus souvent", "Parfois une apparence"],
	"argent": ["60 à 100 tickets", "1 ou 2 objets", "Souvent une apparence"],
	"or": ["140 à 220 tickets", "1 ou 2 objets, dont un rare", "1 apparence garantie"],
	"legendaire": ["350 à 500 tickets", "2 objets rares ou mieux", "2 apparences, dont une épique"],
}
const LOOT_SIZE := {"bronze": "Petit butin", "argent": "Butin moyen", "or": "Gros butin", "legendaire": "Énorme butin"}

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
	var x1 := vs.x - 16.0 - float(ins["right"])
	# ---------------- bandeau commun : RETOUR, titre et phrase, monnaies
	var m := UI.header_money(main.profile)
	var head: Control
	if tab == "coffres":
		head = UI.screen_header(get_viewport(), "COFFRES", "Ouvre tes coffres pour gagner tickets, objets et apparences.", UI.GOLD, main.show_base, m[0], m[1])
	else:
		head = UI.screen_header(get_viewport(), "APPARENCES", "Touche une apparence pour l'équiper. Les autres sortent des coffres.", UI.ACCENT, main.show_base, m[0], m[1])
	body.add_child(head)
	var top := UI.header_height(get_viewport()) + 14.0
	var area := Rect2(x0, top, x1 - x0, vs.y - top - 10.0 - float(ins["bottom"]))
	if tab == "coffres":
		_build_coffres(area, anim)
	else:
		_build_collection(area, anim)
	toast = UI.label("", UI.FS_BODY, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	toast.position = Vector2(x0, vs.y - 58.0)
	toast.size = Vector2(x1 - x0, 34)
	toast.add_theme_color_override("font_outline_color", UI.INK)
	toast.add_theme_constant_override("outline_size", 6)
	toast.modulate.a = 0.0
	body.add_child(toast)

# ---------------------------------------------------------------- COFFRES
func _build_coffres(area: Rect2, anim: bool) -> void:
	var p: Dictionary = main.profile
	var total := (p["boxes"] as Array).size()
	if sel == "" or Loot.count(p, sel) == 0:
		sel = ""
		# le plus beau coffre disponible d'abord
		for r in ["legendaire", "or", "argent", "bronze"]:
			if Loot.count(p, r) > 0:
				sel = r
				break
	var shown := sel if sel != "" else "or"
	var col: Color = Loot.BOX_COLORS[shown]
	# ---- à gauche : le coffre en 3D, son nom, ce qu'il contient, OUVRIR
	var lw := area.size.x * 0.5
	var s := clampf(area.size.y - 330.0, 150.0, minf(lw * 0.62, 260.0))
	# vitrine : panneau sombre, halo de la rareté, socle lumineux sous le coffre
	var pane := Panel.new()
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.position = area.position
	pane.size = Vector2(lw, area.size.y)
	pane.add_theme_stylebox_override("panel", UI.flat(Color("#0A1430", 0.9), Color(col, 0.35), 22, 2))
	body.add_child(pane)
	var halo := Fx.halo(Color(col, 0.4 if sel != "" else 0.12), Vector2(s * 1.5, s * 1.2))
	halo.position = area.position + Vector2((lw - s * 1.5) * 0.5, -s * 0.05)
	body.add_child(halo)
	var base := Control.new()
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.position = area.position + Vector2(lw * 0.5, s * 0.7)
	base.draw.connect(func():
		base.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.25))
		for k in range(5):
			base.draw_circle(Vector2.ZERO, s * (0.36 - k * 0.05), Color(col, 0.06 + 0.03 * k if sel != "" else 0.03)))
	body.add_child(base)
	Fx.pulse(halo, 0.6, 1.0, 1.6)
	stage = Stage.new()
	stage.setup(shown, Vector2(s, s))
	stage.position = area.position + Vector2((lw - s) * 0.5, -s * 0.02)
	stage.yaw = -0.45
	body.add_child(stage)
	if sel == "":
		stage.modulate = Color(0.45, 0.5, 0.6, 0.8)
	var info := UI.vbox(2)
	info.position = Vector2(area.position.x + 16.0, stage.position.y + s * 0.84)
	info.size = Vector2(lw - 32.0, 0)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(info)
	var nm := UI.title(("COFFRE " + String(Loot.BOX_NAMES[shown]).to_upper()) if sel != "" else "AUCUN COFFRE", 34, col.lightened(0.3) if sel != "" else UI.TEXT, col.darkened(0.5), HORIZONTAL_ALIGNMENT_CENTER)
	info.add_child(nm)
	if sel != "":
		# contenu, une ligne par récompense
		for line in CONTENTS[shown]:
			info.add_child(UI.label("•  " + String(line), UI.FS_BODY, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		var hint := UI.label("Bats le boss d'un monde pour gagner un coffre Or, et un Légendaire la première fois. Les élites et la route Trésor en donnent aussi.", UI.FS_BODY, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(hint)
	if sel != "":
		var row := UI.hbox(12)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.position = Vector2(area.position.x, area.end.y - 98.0)
		row.size = Vector2(lw, 84)
		body.add_child(row)
		var ob := UI.primary("OUVRIR", 34, 200)
		ob.custom_minimum_size = Vector2(200, 84)
		ob.pressed.connect(func(): open([sel], false))
		row.add_child(ob)
		Fx.shine(ob, 260.0, 2.2, 0.5)
		if total > 1:
			var ab := UI.button("TOUT  ×%d" % total, 26, UI.ORANGE, 170)
			ab.custom_minimum_size = Vector2(170, 84)
			ab.pressed.connect(func(): open((p["boxes"] as Array).duplicate(), true))
			row.add_child(ab)
		if anim:
			Fx.rise_in(row, 0.2, 0.34, 0.7)
	# ---- à droite : les quatre raretés
	var rx := area.position.x + lw + 16.0
	var rw := area.end.x - rx
	var th := minf(118.0, (area.size.y - 30.0) / 4.0)
	var i := 0
	for r in ["legendaire", "or", "argent", "bronze"]:
		var b := _box_tile(r, Vector2(rw, th))
		b.position = Vector2(rx, area.position.y + i * (th + 10.0))
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
	var st := UI.flat(Color("#15234A", 0.96) if not on else Color("#1E2F5E", 0.98), col if on else Color(col, 0.35), 18, 4 if on else 2)
	st.border_width_left = 8
	for k in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(k, st)
	var art := Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size = sz
	var aw := minf(sz.y * 0.62, 66.0)
	art.draw.connect(func():
		Art.draw_box(art, Vector2(16 + aw * 0.55, sz.y * 0.52), aw, r, n == 0))
	b.add_child(art)
	var tx := 28.0 + aw * 1.1
	var nm := UI.title(String(Loot.BOX_NAMES[r]).to_upper(), 26, UI.TEXT if n > 0 else UI.SOFT, col.darkened(0.55))
	nm.position = Vector2(tx, sz.y * 0.5 - 34)
	nm.size = Vector2(sz.x - tx - 72, 36)
	nm.clip_text = true
	b.add_child(nm)
	var tp := UI.label(String(LOOT_SIZE[r]), UI.FS_SMALL, UI.SOFT)
	tp.position = Vector2(tx, sz.y * 0.5 + 4)
	tp.size = Vector2(sz.x - tx - 72, 28)
	tp.clip_text = true
	b.add_child(tp)
	var cnt := UI.title("×%d" % n, 34, col.lightened(0.25) if n > 0 else UI.MUTED, UI.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	cnt.position = Vector2(sz.x - 84, 0)
	cnt.size = Vector2(70, sz.y)
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(cnt)
	b.pressed.connect(func():
		if n > 0 and sel != r:
			sel = r
			main.sfx.play("click", 1.1, -6.0)
			_refresh()
		elif n == 0:
			_toast("Aucun coffre %s pour l'instant" % String(Loot.BOX_NAMES[r]), col))
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
	# fond sombre derrière la grille (le Relais 3D ne gêne pas la lecture)
	var pane := Panel.new()
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.position = area.position - Vector2(10, 4)
	pane.size = area.size + Vector2(20, 8)
	pane.add_theme_stylebox_override("panel", UI.flat(Color("#0A1430", 0.88), Color(UI.ACCENT, 0.25), 20, 2))
	body.add_child(pane)
	var scroll := UI.scroll()
	scroll.position = area.position + Vector2(6, 8)
	scroll.size = area.size - Vector2(12, 12)
	body.add_child(scroll)
	var list := UI.vbox(12)
	list.custom_minimum_size = Vector2(scroll.size.x - 14.0, 0)
	scroll.add_child(list)
	var cols := clampi(int((scroll.size.x - 14.0 + 12.0) / 172.0), 3, 8)
	var tw := (scroll.size.x - 14.0 - (cols - 1) * 12.0) / cols
	for sec in [["skin", "APPARENCES DE JO", Loot.SKINS, "skins", "skin"], ["trail", "TRAÎNÉES DE TIR", Loot.TRAILS, "trails", "trail"]]:
		var owned: Array = p[sec[3]]
		var h := UI.hbox(14)
		list.add_child(h)
		h.add_child(UI.title(String(sec[1]), 28, UI.TEXT, UI.ACCENT))
		h.add_child(UI.title("%d / %d obtenues" % [owned.size(), (sec[2] as Array).size()], 24, UI.SOFT, UI.INK))
		var grid := GridContainer.new()
		grid.columns = cols
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		list.add_child(grid)
		for c in sec[2]:
			var b := _cosmetic_tile(String(sec[0]), c, owned.has(c["id"]), String(p[sec[4]]) == String(c["id"]), Vector2(tw, tw * 1.18))
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
	var nm := UI.label(String(c["name"]) if owned else "À gagner", 24, UI.TEXT if owned else UI.SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	nm.position = Vector2(4, sz.y * 0.62)
	nm.size = Vector2(sz.x - 8, 30)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_child(nm)
	var tl := UI.label(Loot.TIER_NAMES[tier], UI.FS_SMALL, col if owned else col.darkened(0.1), HORIZONTAL_ALIGNMENT_CENTER)
	tl.position = Vector2(4, sz.y * 0.62 + 28)
	tl.size = Vector2(sz.x - 8, 26)
	b.add_child(tl)
	if equipped:
		var tg := UI.tag("PORTÉE", col, UI.INK, 20)
		tg.position = Vector2(6, 6)
		b.add_child(tg)
	b.pressed.connect(func():
		if not owned:
			_toast("%s %s : à gagner dans les coffres" % ["Apparence" if kind == "skin" else "Traînée de tir", Loot.TIER_NAMES[tier].to_lower()], col)
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
		_toast("%s : %s" % ["Apparence de Jo" if kind == "skin" else "Traînée de tir", String(c["name"])], col))
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
