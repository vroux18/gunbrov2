extends Control
## Écrans COFFRES et APPARENCES du Relais (identifiants internes : « coffres », « collection »), sous le bandeau
## commun (UI.screen_header). Jo reste visible à gauche (gros plan du Relais 3D).
## COFFRES : le coffre choisi en 3D qui se balance, ce qu'il contient en clair, OUVRIR, TOUT ; à droite les
## quatre raretés avec leur nombre.
## APPARENCES : on choisit en regardant la grande Jo 3D. Vignettes de Jo en 3D dans chaque apparence (rendues une
## fois, scripts/ui/boxes_thumbs.gd), aussi pour celles pas encore obtenues (assombries, cadenas) ; toucher une
## vignette l'essaie sur Jo, la fiche sous Jo dit PORTER ou dans quels coffres la gagner. Onglet des traînées de
## tir : Jo tire, les tirs prennent la traînée touchée.

const UI = preload("res://scripts/ui.gd")
const Fx = preload("res://scripts/ui/fx.gd")
const Save = preload("res://scripts/save.gd")
const Loot = preload("res://scripts/loot.gd")
const Art = preload("res://scripts/ui/boxes_art.gd")
const Stage = preload("res://scripts/ui/boxes_stage.gd")
const Opener = preload("res://scripts/ui/boxes_open.gd")
const Thumbs = preload("res://scripts/ui/boxes_thumbs.gd")
const Rig3D = preload("res://scripts/rig3d.gd")

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
	process_priority = 100  # après le Relais 3D : l'aperçu des tirs oriente Jo
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
		head = UI.screen_header(get_viewport(), "APPARENCES", "Touche une vignette pour l'essayer sur Jo, puis PORTER pour la garder.", UI.ACCENT, func():
			_restore_try()
			main.show_base(), m[0], m[1])
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

# ---------------------------------------------------------------- APPARENCES (identifiant interne : collection)
## Choisir en regardant la grande Jo 3D du Relais : toucher une vignette l'essaie aussitôt sur elle (même non
## obtenue), la fiche en bas à gauche dit son nom, sa rareté, et PORTER (obtenue) ou les coffres où la gagner.
## En quittant l'écran, Jo reprend l'apparence portée. Onglet TRAÎNÉES : Jo vise et tire, les tirs prennent la
## traînée essayée.
const CARD_H := 174.0
const AIM_YAW := 1.2  # Jo de trois quarts, tournée vers la droite : elle tire vers les vignettes
const SHOT_EVERY := 0.16
const SHOT_SPEED := 7.0  # m/s dans le Relais 3D
const SHOT_LIFE := 0.6
const SHOT_LEN := 1.2  # longueur de la traînée (m)
const SHOT_W := 80.0  # épaisseur à l'écran, divisée par la distance à la caméra

var ctab := "skin"  # onglet : skin (apparences) | trail (traînées)
var try_id := {"skin": "", "trail": ""}  # essayé ("" : celui qui est porté)
var _tiles := {}  # id d'apparence -> TextureRect de sa vignette
var _thumbs: Thumbs = null
var _shots: Array = []  # tirs de l'aperçu : {p, d, age, col}
var _shot_cv: Control = null
var _shot_cd := 0.0
var _shot_i := 0
var _aim_k := 0.0

func _hero_rig() -> Rig3D:
	if main == null or not is_instance_valid(main.view) or main.view.relais == null:
		return null
	return main.view.relais.get_meta("hero") as Rig3D

func _shown(kind: String) -> String:
	var id := String(try_id[kind])
	return id if id != "" else String(main.profile[kind])

## Jo reprend ce qu'elle porte vraiment (apparence, bras baissés).
func _restore_try() -> void:
	if main == null or not is_instance_valid(main):
		return
	Loot.apply_skin(main.profile)
	var rh := _hero_rig()
	if rh != null:
		rh.shooting = 0.0
	try_id = {"skin": "", "trail": ""}

func _exit_tree() -> void:
	if tab == "collection":
		_restore_try()

func _build_collection(area: Rect2, anim: bool) -> void:
	var p: Dictionary = main.profile
	var ins := UI.safe_insets(get_viewport())
	if _thumbs == null:
		_thumbs = Thumbs.new()
		add_child(_thumbs)
		_thumbs.rendered.connect(_on_thumb)
		for a in OS.get_cmdline_user_args():  # captures : --ctab=trail, --try=<id>
			if a.begins_with("--ctab="):
				ctab = a.trim_prefix("--ctab=")
			elif a.begins_with("--try="):
				try_id[ctab] = a.trim_prefix("--try=")
		Rig3D.set_hero_skin(Loot.skin_palette(_shown("skin")))
	# tirs de l'aperçu, sous les panneaux
	_shot_cv = Control.new()
	_shot_cv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shot_cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shot_cv.draw.connect(_draw_shots)
	body.add_child(_shot_cv)
	body.move_child(_shot_cv, 0)
	# ---- à gauche, sous Jo : la fiche de ce qu'elle essaie
	var lx := 16.0 + float(ins["left"])
	var card := Rect2(lx, vs.y - 10.0 - float(ins["bottom"]) - CARD_H, area.position.x - 18.0 - lx, CARD_H)
	_build_detail(card, anim)
	# ---- à droite : deux onglets, puis les vignettes qui défilent
	var tabs_h := 76.0
	var tw2 := (area.size.x - 12.0) * 0.5
	var k := 0
	for tdef in [["skin", "APPARENCES", Loot.SKINS, "skins"], ["trail", "TRAÎNÉES DE TIR", Loot.TRAILS, "trails"]]:
		var on: bool = ctab == tdef[0]
		var b := UI.button("%s   %d/%d" % [tdef[1], (p[tdef[3]] as Array).size(), (tdef[2] as Array).size()], 26, UI.ACCENT)
		b.position = Vector2(area.position.x + k * (tw2 + 12.0), area.position.y)
		b.size = Vector2(tw2, tabs_h)
		b.clip_text = true
		if on:
			for st in ["normal", "hover", "pressed", "hover_pressed"]:
				b.add_theme_stylebox_override(st, UI.chunky(UI.ACCENT, UI.ACCENT.darkened(0.5), st.contains("pressed")))
			for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
				b.add_theme_color_override(fc, UI.INK)
		else:
			for fc in ["font_color", "font_hover_color"]:
				b.add_theme_color_override(fc, UI.SOFT)
		var kind: String = tdef[0]
		b.pressed.connect(func():
			if ctab != kind:
				ctab = kind
				main.sfx.play("click", 1.1, -6.0)
				_refresh())
		body.add_child(b)
		k += 1
	var top := area.position.y + tabs_h + 10.0
	# traînées : la grille laisse un couloir de tir entre Jo et les vignettes
	var lane := clampf(area.size.x * 0.16, 110.0, 170.0) if ctab == "trail" else 0.0
	var pane := Panel.new()
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.position = Vector2(area.position.x + lane, top)
	pane.size = Vector2(area.size.x - lane, area.end.y - top)
	pane.add_theme_stylebox_override("panel", UI.flat(Color("#0A1430", 0.9), Color(UI.ACCENT, 0.25), 20, 2))
	body.add_child(pane)
	var scroll := UI.scroll()
	scroll.position = pane.position + Vector2(8, 8)
	scroll.size = pane.size - Vector2(12, 16)
	body.add_child(scroll)
	var sw := scroll.size.x - 14.0
	var cols := clampi(int((sw + 12.0) / 190.0), 3, 6)
	var tw := (sw - (cols - 1) * 12.0) / cols
	var tsz := Vector2(tw, roundf(tw * 0.92 + 66.0))
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.custom_minimum_size = Vector2(sw, 0)
	scroll.add_child(grid)
	_tiles.clear()
	var list: Array = Loot.SKINS if ctab == "skin" else Loot.TRAILS
	var owned: Array = p["skins" if ctab == "skin" else "trails"]
	for c in list:
		var id := String(c["id"])
		var b := _cosmetic_tile(ctab, c, owned.has(id), String(p[ctab]) == id, id == _shown(ctab), tsz)
		grid.add_child(b)
		if anim:
			Fx.rise_in(b, 0.04 + 0.015 * grid.get_child_count(), 0.26, 0.85)
	# la vignette regardée (au départ : celle qui est portée) est visible sans chercher
	var vi := 0
	for i in range(list.size()):
		if String(list[i]["id"]) == _shown(ctab):
			vi = i
	scroll.set_deferred("scroll_vertical", int(maxf(0.0, floorf(vi / float(cols)) * (tsz.y + 12.0) + tsz.y * 0.5 - scroll.size.y * 0.5)))
	# vignettes 3D : celle qu'on regarde d'abord, puis les obtenues, puis les autres
	var ids := [_shown("skin")]
	for c in Loot.SKINS:
		if (p["skins"] as Array).has(c["id"]):
			ids.append(c["id"])
	for c in Loot.SKINS:
		ids.append(c["id"])
	_thumbs.start(ids)

## Fiche sous Jo : nom, rareté, état, et l'action (PORTER, PORTÉE, ou les coffres où la gagner).
func _build_detail(r: Rect2, anim: bool) -> void:
	var kind := ctab
	var id := _shown(kind)
	var c := Loot.cosmetic(kind, id)
	var tier := int(c["tier"])
	var col: Color = Loot.TIER_COLORS[tier]
	var owned := (main.profile["skins" if kind == "skin" else "trails"] as Array).has(id)
	var equipped := String(main.profile[kind]) == id
	var pane := Panel.new()
	pane.mouse_filter = Control.MOUSE_FILTER_STOP
	pane.position = r.position
	pane.size = r.size
	var st := UI.flat(Color("#0A1430", 0.94), Color(col, 0.8), 20, 3)
	st.border_width_top = 6
	pane.add_theme_stylebox_override("panel", st)
	body.add_child(pane)
	var v := UI.vbox(4)
	v.position = Vector2(16, 10)
	v.size = Vector2(r.size.x - 32, r.size.y - 20)
	pane.add_child(v)
	var nm := UI.title(String(c["name"]).to_upper(), 34, col.lightened(0.45), col.darkened(0.55))
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(nm)
	var row := UI.hbox(10)
	row.add_child(UI.tag(Loot.TIER_NAMES[tier], col, UI.INK, 20))
	var sl := UI.label("Apparence de Jo" if kind == "skin" else "Traînée de tir", 22, UI.SOFT)
	sl.clip_text = true
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sl)
	v.add_child(row)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 2)
	v.add_child(gap)
	var act_h := 74.0
	if owned and not equipped:
		var b := UI.primary("PORTER", 34)
		b.custom_minimum_size = Vector2(0, act_h)
		b.pressed.connect(func(): _equip(kind, id))
		v.add_child(b)
		Fx.shine(b, 260.0, 2.2, 0.5)
		if anim:
			Fx.rise_in(b, 0.2, 0.3, 0.8)
	else:
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(0, act_h)
		var bs := UI.flat(Color("#13203F", 1.0), Color(col, 0.45) if owned else Color(UI.LINE, 1.0), 16, 2)
		bs.content_margin_left = 12
		bs.content_margin_right = 12
		bs.content_margin_top = 4
		bs.content_margin_bottom = 4
		box.add_theme_stylebox_override("panel", bs)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(box)
		var h := UI.hbox(12)
		h.alignment = BoxContainer.ALIGNMENT_CENTER if owned else BoxContainer.ALIGNMENT_BEGIN
		box.add_child(h)
		if owned:
			h.add_child(UI.title("PORTÉE", 30, col.lightened(0.3), UI.INK))
		else:
			var lock := Control.new()
			lock.custom_minimum_size = Vector2(40, 52)
			lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lock.draw.connect(func(): Thumbs.draw_lock(lock, Vector2(20, 28), 40.0, UI.SOFT, UI.INK))
			h.add_child(lock)
			var tv := UI.vbox(0)
			tv.alignment = BoxContainer.ALIGNMENT_CENTER
			tv.add_child(UI.label("Dans les coffres", 22, UI.SOFT))
			var names := HFlowContainer.new()
			names.add_theme_constant_override("h_separation", 14)
			for bx in Loot.TIER_BOXES[tier]:
				names.add_child(UI.title(String(Loot.BOX_NAMES[bx]).to_upper(), 24, (Loot.BOX_COLORS[bx] as Color).lightened(0.15), UI.INK))
			tv.add_child(names)
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(tv)
	if anim:
		Fx.slide_in(pane, Vector2(0, 60), 0.05, 0.3)

func _cosmetic_tile(kind: String, c: Dictionary, owned: bool, equipped: bool, viewed: bool, sz: Vector2) -> Button:
	var tier := int(c["tier"])
	var col: Color = Loot.TIER_COLORS[tier]
	var id := String(c["id"])
	var b := Button.new()
	b.custom_minimum_size = sz
	b.focus_mode = Control.FOCUS_NONE
	var bg := col.darkened(0.78) if owned else Color("#0D1730")
	var st := UI.flat(Color(bg, 0.97), UI.TEXT if viewed else Color(col, 0.7 if owned else 0.35), 16, 4 if viewed else 2)
	st.border_width_bottom = 7
	for k in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(k, st)
	var dim := Color(1, 1, 1) if owned else Color(0.42, 0.45, 0.58)
	var ar := Rect2(Vector2(6, 6), Vector2(sz.x - 12, sz.y - 72))
	var art := Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = ar.position
	art.size = ar.size
	art.clip_contents = true
	b.add_child(art)
	var tex: TextureRect = null
	if kind == "skin":
		tex = TextureRect.new()
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.size = Vector2(ar.size.x, ar.size.y + 6)
		tex.self_modulate = dim
		tex.texture = Thumbs.cache.get(id)
		art.add_child(tex)
		_tiles[id] = tex
	var tex_ref := tex
	art.draw.connect(func():
		# fond : halo de la rareté derrière Jo (ou derrière les tirs)
		var cc := Vector2(art.size.x * 0.5, art.size.y * 0.52)
		var rad := art.size.y * 0.5
		for i in range(6):
			art.draw_circle(cc, rad * (1.0 - i * 0.14), Color(col, (0.05 + 0.025 * i) * (1.0 if owned else 0.45)))
		if kind == "skin":
			if tex_ref.texture == null:
				Art.draw_skin(art, Rect2(Vector2(0, 4), art.size - Vector2(0, 4)), c, false, t)
		else:
			Art.draw_trail(art, Rect2(Vector2(0, art.size.y * 0.12), art.size * Vector2(1, 0.76)), c, false, t))
	if kind == "trail" or tex == null or tex.texture == null:
		art.self_modulate = dim
		_anim.append(art)
	if not owned:
		var lk := Control.new()
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lk.position = Vector2(sz.x - 50, 10)
		lk.size = Vector2(40, 46)
		lk.draw.connect(func(): Thumbs.draw_lock(lk, Vector2(20, 24), 34.0, UI.SOFT, UI.INK))
		b.add_child(lk)
	var nm := UI.label(String(c["name"]), 24, UI.TEXT if owned else UI.SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	nm.position = Vector2(4, sz.y - 64)
	nm.size = Vector2(sz.x - 8, 30)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_child(nm)
	var tl := UI.label(Loot.TIER_NAMES[tier], UI.FS_SMALL, col.lightened(0.1) if owned else col.darkened(0.1), HORIZONTAL_ALIGNMENT_CENTER)
	tl.position = Vector2(4, sz.y - 36)
	tl.size = Vector2(sz.x - 8, 26)
	b.add_child(tl)
	if equipped:
		var tg := UI.tag("PORTÉE", col, UI.INK, 20)
		tg.position = Vector2(8, 8)
		b.add_child(tg)
	b.pressed.connect(func(): _try(kind, id))
	return b

## Toucher une vignette : Jo l'essaie tout de suite (même pas encore obtenue).
func _try(kind: String, id: String) -> void:
	if id == _shown(kind):
		return
	try_id[kind] = id
	if kind == "skin":
		Rig3D.set_hero_skin(Loot.skin_palette(id))
	else:
		_shot_cd = 0.0
	var owned := (main.profile["skins" if kind == "skin" else "trails"] as Array).has(id)
	main.sfx.play("pick" if owned else "click", 1.15, -6.0)
	var keep := _scroll_pos()
	_refresh()
	_set_scroll(keep)

func _equip(kind: String, id: String) -> void:
	main.profile[kind] = id
	Save.save_profile(main.profile)
	main.on_boxes_changed()  # remet l'apparence portée (Loot.apply_skin) : c'est celle qu'on vient de choisir
	try_id[kind] = ""
	main.sfx.play("pick", 1.1, -4.0)
	var keep := _scroll_pos()
	_refresh()
	_set_scroll(keep)
	var c := Loot.cosmetic(kind, id)
	_toast("%s : %s" % ["Jo porte" if kind == "skin" else "Traînée de tir", String(c["name"])], Loot.TIER_COLORS[int(c["tier"])])

func _on_thumb(id: String, tex: Texture2D) -> void:
	var tr = _tiles.get(id)
	if tr == null or not is_instance_valid(tr):
		return
	(tr as TextureRect).texture = tex
	var art := (tr as Control).get_parent() as Control
	_anim.erase(art)
	art.self_modulate = Color(1, 1, 1)
	art.queue_redraw()
	(tr as Control).modulate.a = 0.0
	Fx._tw(tr).tween_property(tr, "modulate:a", 1.0, 0.25)

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

# ---------------------------------------------------------------- aperçu des traînées : Jo tire
func _tick_shots(dt: float) -> void:
	var rh := _hero_rig()
	if rh == null:
		return
	var aiming := ctab == "trail" and opener == null
	_aim_k = move_toward(_aim_k, 1.0 if aiming else 0.0, dt * 3.0)
	if _aim_k > 0.0:
		# après le Relais (process_priority) : Jo se tourne de profil et vise
		var k := smoothstep(0.0, 1.0, _aim_k)
		rh.rotation.y = lerp_angle(rh.rotation.y, AIM_YAW, k)
		rh.set_motion(0.0, 1.0 if aiming else 0.0)
	if aiming and _aim_k > 0.85:
		_shot_cd -= dt
		if _shot_cd <= 0.0:
			_shot_cd = SHOT_EVERY
			_fire(rh)
	for s in _shots:
		s["age"] = float(s["age"]) + dt
	_shots = _shots.filter(func(s): return float(s["age"]) < SHOT_LIFE)
	if _shot_cv != null and is_instance_valid(_shot_cv):
		_shot_cv.queue_redraw()

## Un tir part du canon de Jo, dans l'axe de l'arme ; suivi dans le monde 3D du Relais, dessiné en 2D par-dessus.
func _fire(rh: Rig3D) -> void:
	var gun := rh.p("gun")
	if gun == null:
		return
	var fw := (gun.global_transform.basis * Vector3(0, -1, 0)).normalized()
	_shot_i += 1
	_shots.append({"from": rh.muzzle_position(), "dir": fw, "age": 0.0, "col": Loot.trail_color(_shown("trail"), _shot_i)})
	rh.fire()

func _draw_shots() -> void:
	if _shots.is_empty() or not is_instance_valid(main.view):
		return
	var cam: Camera3D = main.view.cam
	for s in _shots:
		var age := float(s["age"])
		var a := clampf(age / 0.03, 0.0, 1.0) * clampf((SHOT_LIFE - age) / 0.15, 0.0, 1.0)
		if age < 0.08 and not cam.is_position_behind(s["from"]):
			# éclair au canon
			var f2 := cam.unproject_position(s["from"])
			var fk := 1.0 - age / 0.08
			_shot_cv.draw_circle(f2, 6.0 + 16.0 * fk, Color(s["col"], 0.45 * fk))
			_shot_cv.draw_circle(f2, 3.0 + 7.0 * fk, Color(1, 1, 1, 0.85 * fk))
		var dir: Vector3 = s["dir"]
		var head: Vector3 = (s["from"] as Vector3) + dir * SHOT_SPEED * age
		var tail: Vector3 = (s["from"] as Vector3) + dir * maxf(0.0, SHOT_SPEED * age - SHOT_LEN)
		if cam.is_position_behind(head) or cam.is_position_behind(tail):
			continue
		var h2 := cam.unproject_position(head)
		var t2 := cam.unproject_position(tail)
		var ln := h2.distance_to(t2)
		if ln < 1.0:
			continue
		var w := clampf(SHOT_W / maxf(cam.global_position.distance_to(head), 0.5), 3.0, 12.0)
		Thumbs.draw_bolt(_shot_cv, h2, (h2 - t2) / ln, ln, w, s["col"], a)

func _process(dt: float) -> void:
	t += dt
	for a in _anim:
		if is_instance_valid(a):
			(a as Control).queue_redraw()
	if tab == "collection":
		_tick_shots(dt)
