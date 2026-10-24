extends Control
## Écran de fin de partie (victoire, K.O., abandon) : grand titre tamponné sur un ruban, rayons qui tournent,
## récapitulatif qui défile ligne par ligne (salles, ennemis abattus, tickets, objets trouvés, éclat),
## puis REJOUER et RELAIS. Les chiffres comptent jusqu'à leur valeur.

signal replay
signal relais

const UI = preload("res://scripts/ui.gd")
const Fx = preload("res://scripts/ui/fx.gd")
const Icon = preload("res://scripts/icon.gd")
const Data = preload("res://scripts/data.gd")
const BoxArt = preload("res://scripts/ui/boxes_art.gd")

var won := false
var _t := 0.0
var _rays: Control
var _col := UI.GOLD

## info : {room, rooms, kills, tickets, items: [instances], boxes: [raretés], shard: bool, record: bool, title, subtitle}
func build(info: Dictionary) -> void:
	UI.load_fonts()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	won = bool(info.get("shard", false))
	_col = UI.GOLD if won else Color("#FF4D6D")
	var vs := get_viewport().get_visible_rect().size
	var ins := UI.safe_insets(get_viewport())
	add_child(UI.dim(0.84))
	_rays = Control.new()
	_rays.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_rays.material = add
	_rays.draw.connect(_draw_rays)
	add_child(_rays)
	# ---------------- titre sur ruban
	var top := clampf((vs.y - 600.0) * 0.5, 24.0, 220.0)
	var ribbon := Control.new()
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.position = Vector2(0, top + 6)
	ribbon.size = Vector2(vs.x, 96)
	var tsize := 64 if vs.x > 1100 else 52
	var tw: float = UI.TITLE.get_string_size(String(info.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, tsize).x
	ribbon.draw.connect(func():
		var w := minf(vs.x - 120.0, maxf(520.0, tw + 180.0))
		var x0 := (vs.x - w) * 0.5
		var h := 84.0
		var c_top := Color("#FFC24A") if won else Color("#E8435E")
		var c_bot := Color("#E0761F") if won else Color("#A21F3C")
		# queues du ruban, repliées derrière
		for s: float in [-1.0, 1.0]:
			var ex := x0 - 46.0 if s < 0 else x0 + w + 46.0
			var ix := x0 + 18.0 if s < 0 else x0 + w - 18.0
			ribbon.draw_colored_polygon(PackedVector2Array([Vector2(ix, 18), Vector2(ex, 18), Vector2(ex - s * 24.0, 18 + h * 0.5), Vector2(ex, 18 + h), Vector2(ix, 18 + h)]), c_bot.darkened(0.45))
			var fx := x0 if s < 0 else x0 + w
			ribbon.draw_colored_polygon(PackedVector2Array([Vector2(fx, h), Vector2(fx + s * 18.0, 18 + h), Vector2(fx, 18 + h)]), c_bot.darkened(0.65))
		ribbon.draw_rect(Rect2(x0, 7, w, h), Color(0, 0, 0, 0.35))
		ribbon.draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x0 + w, 0), Vector2(x0 + w, h), Vector2(x0, h)]),
			PackedColorArray([c_top, c_top, c_bot, c_bot]))
		ribbon.draw_rect(Rect2(x0, 0, w, 6), Color(1, 1, 1, 0.35))
		ribbon.draw_rect(Rect2(x0, h - 7, w, 7), Color(0, 0, 0, 0.25)))
	add_child(ribbon)
	Fx.rise_in(ribbon, 0.05, 0.3, 0.6)
	var title := UI.title(String(info.get("title", "")), tsize, UI.TEXT, _col.darkened(0.6), HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, top + 2)
	title.size = Vector2(vs.x, 90)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	Fx.slam(title, 0.12, 2.4)
	if won:
		Fx.shine(title, vs.x * 0.5, 2.4, 0.6)
	var sub := UI.label(String(info.get("subtitle", "")), 24, Color("#D5DEEA"), HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0, top + 112)
	sub.size = Vector2(vs.x, 30)
	sub.add_theme_color_override("font_outline_color", UI.INK)
	sub.add_theme_constant_override("outline_size", 5)
	add_child(sub)
	Fx.rise_in(sub, 0.35)
	# ---------------- récapitulatif
	var pw := minf(640.0, vs.x - ins["left"] - ins["right"] - 40.0)
	var rows := [
		["room", "Salles", int(info.get("room", 1)), "%d / " + str(int(info.get("rooms", 10))), UI.ACCENT],
		["skull", "Ennemis abattus", int(info.get("kills", 0)), "%d", Color("#FF4D6D")],
		["coin", "Tickets", int(info.get("tickets", 0)), "+%d", UI.GOLD],
		["chest", "Objets trouvés", (info.get("items", []) as Array).size(), "%d", Color("#C77DFF")],
		["box", "Box gagnées", (info.get("boxes", []) as Array).size(), "+%d", UI.GOLD],
		["shard", "Éclat du Cœur", 1 if won else 0, "+%d" if won else "%d", UI.ACCENT if won else UI.MUTED],
	]
	var row_h := 58.0
	var py := top + 160.0
	var avail: float = vs.y - py - 130.0 - float(ins["bottom"])
	if avail < rows.size() * row_h:
		row_h = maxf(48.0, avail / rows.size())
	var px := (vs.x - pw) * 0.5
	var i := 0
	for r in rows:
		var row := _row(r[0], r[1], int(r[2]), String(r[3]), r[4], Vector2(pw, row_h - 8.0), i == 0 and bool(info.get("record", false)), info.get("items", []) if r[0] == "chest" else (info.get("boxes", []) if r[0] == "box" else []))
		row.position = Vector2(px, py + i * row_h)
		add_child(row)
		Fx.slide_in(row, Vector2(80, 0), 0.45 + 0.1 * i, 0.32)
		var vl: Label = row.get_meta("value")
		Fx.count(vl, 0, int(r[2]), 0.55, 0.55 + 0.1 * i, String(r[3]))
		i += 1
	# ---------------- boutons
	var by := minf(py + rows.size() * row_h + 18.0, vs.y - 100.0 - ins["bottom"])
	var bar := UI.hbox(22)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.position = Vector2(0, by)
	bar.size = Vector2(vs.x, 88)
	add_child(bar)
	var again := UI.primary("REJOUER", 34, 300)
	again.custom_minimum_size = Vector2(300, 86)
	again.pressed.connect(func(): replay.emit())
	bar.add_child(again)
	var home := UI.button("RELAIS", 30, UI.ACCENT, 240)
	home.custom_minimum_size = Vector2(240, 86)
	home.pressed.connect(func(): relais.emit())
	bar.add_child(home)
	Fx.rise_in(again, 1.15, 0.36, 0.5)
	Fx.rise_in(home, 1.25, 0.36, 0.5)
	Fx.shine(again, 300.0, 2.2, 0.5)

func _row(icon: String, label_text: String, _value: int, _fmt: String, col: Color, sz: Vector2, record: bool, items: Array) -> Control:
	var c := Control.new()
	c.size = sz
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Panel.new()
	bg.size = sz
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UI.flat(Color("#15234A", 0.92), Color(col, 0.35), 14, 2)
	st.border_width_left = 6
	st.border_color = col
	bg.add_theme_stylebox_override("panel", st)
	c.add_child(bg)
	if icon == "box":
		# box de butin : petites box sculptées en dessin, une par box gagnée, à la couleur de leur rareté
		var bi := Control.new()
		bi.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bi.size = sz
		bi.draw.connect(func():
			BoxArt.draw_box(bi, Vector2(18 + sz.y * 0.31, sz.y * 0.5), sz.y * 0.62, String(items[0]) if not items.is_empty() else "or", items.is_empty())
			for k in range(mini(items.size(), 8)):
				BoxArt.draw_box(bi, Vector2(266 + k * 44, sz.y * 0.5), 36.0, String(items[k])))
		c.add_child(bi)
		items = []
	else:
		var ic := Icon.new(icon, col, sz.y * 0.62)
		ic.position = Vector2(18, sz.y * 0.19)
		c.add_child(ic)
	var l := UI.label(label_text, 24, UI.TEXT)
	l.position = Vector2(30 + sz.y * 0.62, 0)
	l.size = Vector2(300, sz.y)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(l)
	var v := UI.title("0", 30, col.lightened(0.15) if col != UI.MUTED else UI.MUTED, col.darkened(0.4), HORIZONTAL_ALIGNMENT_RIGHT)
	v.position = Vector2(sz.x - 220, 0)
	v.size = Vector2(200, sz.y)
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_theme_constant_override("shadow_offset_y", 2)
	c.add_child(v)
	c.set_meta("value", v)
	if record:
		var tg := UI.tag("RECORD", UI.ORANGE, UI.INK, 18)
		tg.position = Vector2(250, sz.y * 0.5 - 14)
		c.add_child(tg)
		Fx.breathe(tg, 0.08, 0.9)
	if not items.is_empty():
		# un losange par objet, à la couleur de sa rareté
		var dots := Control.new()
		dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots.position = Vector2(250, 0)
		dots.size = Vector2(sz.x - 250 - 100, sz.y)
		dots.draw.connect(func():
			var n := mini(items.size(), 9)
			for k in range(n):
				var it: Dictionary = items[k]
				var p := Vector2(14 + k * 30, sz.y * 0.5)
				var rc: Color = Data.RARITY_COLORS[clampi(int(it["rarity"]), 0, 3)]
				dots.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -13), p + Vector2(11, 0), p + Vector2(0, 13), p + Vector2(-11, 0)]), UI.INK)
				dots.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -10), p + Vector2(8, 0), p + Vector2(0, 10), p + Vector2(-8, 0)]), rc))
		c.add_child(dots)
	return c

func _process(dt: float) -> void:
	_t += dt
	_rays.queue_redraw()

func _draw_rays() -> void:
	var vs := _rays.size
	var ctr := Vector2(vs.x * 0.5, clampf((vs.y - 600.0) * 0.5, 24.0, 220.0) + 48.0)
	var n := 16
	var a0 := 0.06 if won else 0.03
	var col := _col.lightened(0.2) if won else _col
	for k in range(n):
		var a := TAU * k / n + _t * (0.18 if won else 0.06)
		var d1 := Vector2(cos(a - 0.07), sin(a - 0.07)) * vs.x
		var d2 := Vector2(cos(a + 0.07), sin(a + 0.07)) * vs.x
		_rays.draw_polygon(PackedVector2Array([ctr, ctr + d1, ctr + d2]), PackedColorArray([Color(col, a0 * 2.0), Color(col, 0.0), Color(col, 0.0)]))
	if won:
		# paillettes d'or qui tombent en tournoyant
		for i in range(28):
			var h := fmod(i * 0.6180339 + 0.21, 1.0)
			var y := fmod(_t * (60.0 + 50.0 * h) + h * vs.y * 1.3, vs.y + 40.0) - 20.0
			var x := vs.x * fmod(h * 7.31, 1.0) + sin(_t * 1.5 + i) * 24.0
			var s := 4.0 + 5.0 * h
			var r := _t * (2.0 + h * 3.0) + i
			var dx := Vector2(cos(r), sin(r)) * s
			var dy := Vector2(-sin(r), cos(r)) * s * 0.45 * absf(sin(_t * 3.0 + i))
			var c := UI.GOLD if i % 3 else UI.ACCENT
			_rays.draw_colored_polygon(PackedVector2Array([Vector2(x, y) - dx - dy, Vector2(x, y) + dx - dy, Vector2(x, y) + dx + dy, Vector2(x, y) - dx + dy]), Color(c, 0.6))
