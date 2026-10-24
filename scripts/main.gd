extends Node2D
## Chef d'orchestre : le Relais (base), la Loge (équipement), l'Arsenal (pouvoirs de la partie),
## la partie dans l'arène et ses overlays (choix de pouvoir, objet trouvé, portails, pause, fin).

const Data = preload("res://scripts/data.gd")
const Save = preload("res://scripts/save.gd")
const UI = preload("res://scripts/ui.gd")
const HeroScript = preload("res://scripts/hero.gd")
const ArenaScript = preload("res://scripts/arena.gd")
const HudScript = preload("res://scripts/hud.gd")
const JoyScript = preload("res://scripts/joystick.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const Art = preload("res://scripts/art.gd")
const View3D = preload("res://scripts/view3d.gd")
const Fx = preload("res://scripts/ui/fx.gd")
const CardScript = preload("res://scripts/ui/card.gd")
const EnemyCardScript = preload("res://scripts/ui/enemy_card.gd")
const TutorialScript = preload("res://scripts/ui/tutorial.gd")
const EndScreenScript = preload("res://scripts/ui/end_screen.gd")
const DuoScript = preload("res://scripts/net/duo.gd")

var profile: Dictionary
var sfx: Node
var arena: Node2D
var hero: Node2D
var hud: CanvasLayer
var joy: Control
var ui_layer: CanvasLayer
var state := "base"
var screen: Control = null
var overlay: Control = null
var preview_hero: Node2D = null
var version := ""
var view: Node3D
var enemy_card: Control  # « NOUVEL ENNEMI », dans le HUD
var tutorial: Control = null
var run_items: Array = []  # objets trouvés pendant la partie (écran de fin)
var _shown := {}  # valeurs affichées au Relais la dernière fois (compteurs qui défilent au retour)
var duo: Node  # mode duo (scripts/net/duo.gd) : salon, réseau, partie à deux

func _ready() -> void:
	randomize()
	UI.load_fonts()
	version = String(ProjectSettings.get_setting("application/config/version", "dev"))
	profile = Save.load_profile()
	sfx = SfxScript.new()
	add_child(sfx)
	hero = HeroScript.new()
	arena = ArenaScript.new()
	add_child(arena)
	arena.build(sfx, hero)
	arena.visible = false
	var ctl := CanvasLayer.new()
	ctl.layer = 4
	add_child(ctl)
	joy = JoyScript.new()
	joy.enabled = false
	ctl.add_child(joy)
	arena.joy = joy
	# rendu 3D : la simulation 2D reste invisible, la 3D la met en scène
	view = View3D.new()
	add_child(view)
	move_child(view, 0)
	view.build(arena, hero, joy)
	view.set_hero_items(Save.equipped_items(profile))
	hud = HudScript.new()
	hud.visible = false
	hud.pause_pressed.connect(_show_pause)
	hero.damaged.connect(func(): hud.hurt = 1.0)
	add_child(hud)
	enemy_card = EnemyCardScript.new()
	enemy_card.slowmo = func(): view.hit_stop(0.45, 0.3)
	hud.add_child(enemy_card)
	arena.enemy_spawned.connect(_on_enemy_spawned)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	arena.energy_full.connect(_show_power_choice)
	arena.room_cleared.connect(_on_room_cleared)
	arena.door_taken.connect(_on_door_taken)
	arena.item_found.connect(_show_item)
	arena.hero_died.connect(_on_hero_died)
	arena.wave_changed.connect(func():
		if arena.room >= Data.ROOMS:
			hud.flash(_boss_title(), 2.2, UI.DANGER)
		else:
			hud.flash("VAGUE %d" % (arena.wave_i + 1), 1.3, UI.ACCENT))
	_apply_profile_to_hero()
	duo = DuoScript.new()
	duo.main = self
	add_child(duo)
	show_base()
	if "--autoplay" in OS.get_cmdline_user_args():
		var bot = load("res://scripts/bot.gd").new()
		bot.main = self
		add_child(bot)

func _apply_profile_to_hero() -> void:
	hero.items = Save.equipped_items(profile)
	hero.recalc()
	if view != null:
		view.set_hero_items(hero.items)

func _process(_dt: float) -> void:
	if state == "arena":
		hud.hp = hero.hp / hero.hp_max
		hud.hp_text = "%d / %d" % [int(ceil(hero.hp)), int(hero.hp_max)]
		hud.hp_max = hero.hp_max
		hud.shield = hero.shield_max > 0 and hero.shield_ready
		hud.energy = arena.energy / arena.energy_need
		hud.room = arena.room
		hud.rooms = Data.ROOMS
		hud.wave = maxi(1, arena.wave_i + 1)
		hud.waves = arena.waves.size()
		hud.tickets = int(profile["tickets"]) + arena.tickets
		hud.enemies_left = arena.enemies_left()
		if arena.boss != null:
			hud.boss_hp = arena.boss.hp / arena.boss.hp_max
			hud.boss_name = arena.boss.display_name
		else:
			hud.boss_hp = -1.0

# ---------------------------------------------------------------- écrans
## `animated` : l'écran sortant s'efface en fondu (changement d'écran) ; sinon il disparaît net (rafraîchissement).
func _clear_screen(animated: bool = true) -> void:
	if screen != null:
		if animated:
			Fx.screen_out(screen)
		else:
			screen.queue_free()
		screen = null
	if preview_hero != null:
		preview_hero.queue_free()
		preview_hero = null

func _clear_overlay() -> void:
	if overlay != null:
		Fx.screen_out(overlay, 0.14)
		overlay = null

func _full(bg: bool = true) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if bg:
		var c := ColorRect.new()
		c.color = UI.BG
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(c)
		var floor_tex := TextureRect.new()
		floor_tex.texture = Art.FLOOR
		floor_tex.stretch_mode = TextureRect.STRETCH_TILE
		floor_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		floor_tex.modulate = Color(0.55, 0.6, 0.7, 1.0)
		floor_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(floor_tex)
		var shade := ColorRect.new()
		shade.color = Color(UI.BG, 0.45)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(shade)
	return root

## Voile sombre en dégradé sur la droite de l'écran : le Relais 3D reste visible à gauche, le texte reste lisible.
func _side_shade(from_x: float) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(UI.BG, 0.0))
	g.set_color(1, Color(UI.BG, 0.92))
	g.add_point(0.35, Color(UI.BG, 0.75))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.anchor_left = from_x
	tr.anchor_right = 1.0
	tr.anchor_top = 0.0
	tr.anchor_bottom = 1.0
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _add_preview_hero(pos: Vector2, scale_f: float) -> void:
	preview_hero = HeroScript.new()
	preview_hero.preview = true
	preview_hero.items = hero.items
	preview_hero.position = pos
	preview_hero.scale = Vector2(scale_f, scale_f)
	preview_hero.rotation = 0.0
	ui_layer.add_child(preview_hero)
	preview_hero.z_index = 1

func show_base() -> void:
	state = "base"
	get_tree().paused = false
	_clear_overlay()
	_clear_screen()
	arena.visible = false
	arena.cam.enabled = false
	arena.running = false
	view.show_relais(Save.equipped_items(profile))
	Music.play("relais")
	view.set_shards(int(profile["shards"]))
	hud.visible = false
	joy.enabled = false
	screen = _full(false)
	ui_layer.add_child(screen)
	_build_relais_panel()

## Panneau du Relais (droite) : titre PASSEURS en relief qui brille, compteurs qui défilent depuis la dernière
## visite, PARTIR énorme (halo qui pulse, reflet, chevrons qui filent), LOGE et ARSENAL avec leurs pastilles.
func _build_relais_panel() -> void:
	var ins := UI.safe_insets(get_viewport())
	screen.add_child(_side_shade(0.4))
	var right := UI.vbox(14)
	right.anchor_left = 0.53
	right.anchor_right = 1.0
	right.offset_right = -float(ins["right"]) - 24.0
	right.anchor_top = 0.07
	right.anchor_bottom = 0.95
	var vs := get_viewport().get_visible_rect().size
	if vs.x / vs.y < 1.6:
		right.alignment = BoxContainer.ALIGNMENT_CENTER  # tablette : panneau centré en hauteur
	screen.add_child(right)
	# titre : couche orange décalée derrière, face claire, reflet qui balaie, filet lumineux dessous
	var tbox := Control.new()
	tbox.custom_minimum_size = Vector2(0, 104)
	tbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(tbox)
	var t_back := UI.title("PASSEURS", 92, UI.ORANGE, UI.ORANGE)
	t_back.add_theme_color_override("font_outline_color", Color("#7A2A08"))
	t_back.add_theme_constant_override("shadow_offset_y", 0)
	t_back.position = Vector2(6, 7)
	tbox.add_child(t_back)
	var t_front := UI.title("PASSEURS", 92, UI.TEXT, UI.ACCENT)
	t_front.add_theme_constant_override("shadow_offset_y", 0)
	tbox.add_child(t_front)
	Fx.shine(t_front, 480.0, 3.0, 0.75)
	var rule := Control.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.position = Vector2(4, 100)
	rule.size = Vector2(440, 6)
	var rt := {"t": 0.0}
	rule.draw.connect(func():
		rule.draw_rect(Rect2(0, 0, rule.size.x, 4), Color(UI.ACCENT, 0.25))
		rule.draw_rect(Rect2(0, 0, 120, 4), UI.ACCENT)
		var x := fmod(float(rt["t"]) * 160.0, rule.size.x + 120.0) - 60.0
		rule.draw_rect(Rect2(x, -1, 60, 6), Color(1, 1, 1, 0.8)))
	rule.set_process(true)
	tbox.add_child(rule)
	var tw_rule := rule.create_tween().set_loops()
	tw_rule.tween_method(func(v: float):
		rt["t"] = v
		rule.queue_redraw(), 0.0, 4.0, 4.0)
	right.add_child(_world_selector())
	# compteurs : défilent depuis les valeurs vues à la dernière visite
	var chips := UI.hbox(10)
	right.add_child(chips)
	var shards := int(profile["shards"])
	var tk := int(profile["tickets"])
	var best := int(profile["best_room"])
	var c1 := UI.chip("shard", "", UI.ACCENT)
	var c2 := UI.chip("coin", "", UI.GOLD)
	var c3 := UI.chip("room", "", UI.DANGER)
	for c in [c1, c2, c3]:
		var cl: Label = c.get_meta("label")
		cl.add_theme_font_override("font", UI.TITLE)
		cl.add_theme_font_size_override("font_size", 21)
		chips.add_child(c)
	Fx.count(c1.get_meta("label"), int(_shown.get("shards", shards)), shards, 0.7, 0.35, "%d / 10")
	Fx.count(c2.get_meta("label"), int(_shown.get("tickets", tk)), tk, 1.0, 0.35, "%d")
	Fx.count(c3.get_meta("label"), int(_shown.get("best", best)), best, 0.6, 0.35, "record %d")
	if int(_shown.get("tickets", tk)) != tk:
		var tbump := c2.create_tween()
		tbump.tween_interval(1.35)
		tbump.tween_callback(func(): Fx.bump(c2, 0.15))
	_shown = {"shards": shards, "tickets": tk, "best": best}
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 12)
	right.add_child(sp)
	# PARTIR : le bouton qu'on a envie de toucher
	var go := UI.primary("PARTIR", 54)
	go.custom_minimum_size = Vector2(0, 112)
	go.add_theme_stylebox_override("normal", _go_style(false))
	go.add_theme_stylebox_override("hover", _go_style(false))
	go.add_theme_stylebox_override("pressed", _go_style(true))
	go.add_theme_stylebox_override("hover_pressed", _go_style(true))
	go.pressed.connect(_depart)
	_go_button = go
	_refresh_world()
	right.add_child(go)
	var halo := Fx.halo(Color(UI.ORANGE, 0.5), Vector2(10, 10))
	halo.show_behind_parent = true
	go.add_child(halo)
	go.resized.connect(func():
		halo.size = go.size * Vector2(1.3, 3.0)
		halo.position = (go.size - halo.size) * 0.5)
	Fx.pulse(halo, 0.55, 1.0, 1.4)
	Fx.shine(go, 560.0, 2.4, 0.45)
	var chev := Control.new()
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chev.anchor_left = 1.0
	chev.anchor_right = 1.0
	chev.anchor_top = 0.5
	chev.anchor_bottom = 0.5
	chev.offset_left = -96
	chev.offset_right = -24
	chev.offset_top = -22
	chev.offset_bottom = 18
	var ct := {"t": 0.0}
	chev.draw.connect(func():
		for k in range(3):
			var ph := fmod(float(ct["t"]) * 1.6 - k * 0.22, 1.0)
			var x := 6.0 + k * 22.0
			var a := 0.25 + 0.75 * clampf(1.0 - absf(ph - 0.5) * 2.0, 0.0, 1.0)
			chev.draw_polyline(PackedVector2Array([Vector2(x, 4), Vector2(x + 14, 20), Vector2(x, 36)]), Color(UI.INK, a), 7.0, true))
	go.add_child(chev)
	var tw_chev := chev.create_tween().set_loops()
	tw_chev.tween_method(func(v: float):
		ct["t"] = v
		chev.queue_redraw(), 0.0, 1.0, 0.625)
	var picon := UI.Icon.new("play", UI.INK, 40.0)
	picon.anchor_top = 0.5
	picon.anchor_bottom = 0.5
	picon.offset_left = 30
	picon.offset_top = -24
	go.add_child(picon)
	# LOGE et ARSENAL : pictogramme, pastille de compte
	var row := UI.hbox(14)
	right.add_child(row)
	var inv_n: int = profile["inventory"].size()
	var loge := _side_button("LOGE", "torse", UI.ACCENT, str(inv_n) if inv_n > 0 else "")
	loge.pressed.connect(show_loge)
	row.add_child(loge)
	var ars := _side_button("ARSENAL", "bolt", UI.ORANGE, "%d/%d" % [profile["arsenal"].size(), Data.ARSENAL_SIZE])
	ars.pressed.connect(show_arsenal)
	row.add_child(ars)
	var duo_b := _side_button("DUO", "portal", UI.GOLD, "")
	duo_b.pressed.connect(func(): duo.open_lobby())
	row.add_child(duo_b)
	var equipped := Save.equipped_items(profile)
	var eq_txt := "Rien d'équipé. Les objets trouvés en partie restent à toi."
	if not equipped.is_empty():
		var names := []
		for it in equipped:
			names.append(Data.item_label(it))
		eq_txt = "Équipé : " + ", ".join(names)
	var eq := UI.label(eq_txt, 20, UI.MUTED)
	eq.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(eq)
	var ver := UI.label("V0 · " + version, 14, UI.LINE)
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_top = -30
	ver.offset_left = 16 + float(ins["left"])
	screen.add_child(ver)
	# entrée : le panneau glisse depuis la droite, les éléments arrivent l'un après l'autre
	Fx.slide_in(right, Vector2(160, 0), 0.0, 0.45)
	Fx.slam(tbox, 0.08, 1.5)
	Fx.rise_in(chips, 0.22)
	Fx.rise_in(go, 0.3, 0.42, 0.6)
	Fx.rise_in(row, 0.42)
	var tw_go := go.create_tween()
	tw_go.tween_interval(0.8)
	tw_go.tween_callback(func(): Fx.breathe(go, 0.03, 1.3))

func _go_style(pressed: bool) -> StyleBoxFlat:
	var s := UI.chunky(Color("#FF8A3D") if not pressed else Color("#F0702A"), Color("#A83E12"), pressed, 26)
	s.border_width_bottom = 3 if pressed else 10
	s.border_width_top = 0 if pressed else 3
	s.border_color = Color("#A83E12")
	s.shadow_color = Color(0.35, 0.1, 0.0, 0.55)
	s.shadow_size = 2 if pressed else 12
	s.shadow_offset = Vector2(0, 6)
	return s

func _side_button(text: String, icon: String, col: Color, badge: String) -> Button:
	var b := UI.button(text, 30, col)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 86)
	b.add_theme_font_override("font", UI.TITLE)
	b.add_theme_font_size_override("font_size", 28)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var st: StyleBoxFlat = b.get_theme_stylebox("normal")
	st.content_margin_left = 60
	var ic := UI.Icon.new(icon, col, 36.0)
	ic.anchor_top = 0.5
	ic.anchor_bottom = 0.5
	ic.offset_left = 18
	ic.offset_top = -22
	b.add_child(ic)
	if badge != "":
		var tg := UI.tag(badge, col, UI.INK, 18)
		tg.anchor_left = 1.0
		tg.anchor_right = 1.0
		tg.offset_left = -64
		tg.offset_top = -12
		b.add_child(tg)
	return b

func show_loge() -> void:
	var fresh := state != "loge"
	_clear_screen(fresh)
	state = "loge"
	screen = _full(false)
	ui_layer.add_child(screen)
	screen.add_child(_side_shade(0.22))
	view.relais_focus = 1.0
	if fresh:
		Fx.screen_in(screen)
	var left := UI.vbox(8)
	left.anchor_left = 0.33
	left.anchor_right = 0.62
	left.anchor_top = 0.05
	left.anchor_bottom = 0.96
	screen.add_child(left)
	var head := UI.hbox(14)
	left.add_child(head)
	head.add_child(UI.title("LOGE", 44, UI.TEXT, UI.ACCENT))
	var back := UI.primary("RETOUR", 24)
	back.custom_minimum_size = Vector2(150, 80)
	back.pressed.connect(show_base)
	head.add_child(back)
	if fresh:
		Fx.slide_in(left, Vector2(-120, 0), 0.0, 0.4)
	left.add_child(UI.label("Touche un emplacement pour le vider.", 20, UI.MUTED))
	for slot in Data.SLOTS:
		var uid := String(profile["equipped"].get(slot, ""))
		var it := Save.find_item(profile, uid) if uid != "" else {}
		var b: Button
		if it.is_empty():
			b = UI.tile(slot, Data.SLOT_NAMES[slot].to_upper(), "vide", UI.LINE, false, 74)
			b.disabled = true
		else:
			b = UI.tile(slot, Data.item_label(it), Data.item_stat_text(it), Data.RARITY_COLORS[int(it["rarity"])], true, 74)
		b.pressed.connect(func():
			Save.unequip(profile, slot)
			Save.save_profile(profile)
			_apply_profile_to_hero()
			show_loge())
		left.add_child(b)
	var right := UI.vbox(8)
	right.anchor_left = 0.645
	right.anchor_right = 0.975
	right.anchor_top = 0.05
	right.anchor_bottom = 0.96
	screen.add_child(right)
	right.add_child(UI.title("INVENTAIRE  %d" % profile["inventory"].size(), 30, UI.TEXT, UI.GOLD))
	if fresh:
		Fx.slide_in(right, Vector2(140, 0), 0.08, 0.42)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var list := UI.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var inv: Array = profile["inventory"].duplicate()
	inv.sort_custom(func(a, b): return int(a["rarity"]) > int(b["rarity"]))
	if inv.is_empty():
		var e := UI.label("Vide. Les coffres de fin de salle et les élites lâchent des objets.", 18, UI.MUTED)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(e)
	for it in inv:
		var equipped_here := false
		for sl in profile["equipped"].keys():
			if String(profile["equipped"][sl]) == String(it["uid"]):
				equipped_here = true
		var tpl := Data.item_template(String(it["id"]))
		var b := UI.tile(String(tpl["slot"]), ("✓ " if equipped_here else "") + Data.item_label(it), Data.SLOT_NAMES[tpl["slot"]] + "  ·  " + Data.item_stat_text(it), Data.RARITY_COLORS[int(it["rarity"])], equipped_here, 78)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			Save.equip(profile, String(it["uid"]))
			Save.save_profile(profile)
			_apply_profile_to_hero()
			sfx.play("pick", 1.0, -8.0)
			show_loge())
		list.add_child(b)

func show_arsenal() -> void:
	var fresh := state != "arsenal"
	_clear_screen(fresh)
	state = "arsenal"
	screen = _full(false)
	ui_layer.add_child(screen)
	screen.add_child(UI.dim(0.8))
	if fresh:
		Fx.screen_in(screen)
	var col := UI.vbox(12)
	col.anchor_left = 0.04
	col.anchor_right = 0.96
	col.anchor_top = 0.05
	col.anchor_bottom = 0.96
	screen.add_child(col)
	var head := UI.hbox(20)
	col.add_child(head)
	head.add_child(UI.title("ARSENAL", 44, UI.TEXT, UI.ORANGE))
	head.add_child(UI.title("%d / %d" % [profile["arsenal"].size(), Data.ARSENAL_SIZE], 32, UI.ORANGE, UI.ORANGE))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var back := UI.primary("RETOUR", 24)
	back.custom_minimum_size = Vector2(150, 80)
	back.pressed.connect(show_base)
	head.add_child(back)
	col.add_child(UI.label("Les pouvoirs allumés peuvent t'être proposés quand ta barre d'énergie est pleine. Trois sont tirés à chaque fois.", 20, UI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grid)
	for p in Data.POWERS:
		var id := String(p["id"])
		var on: bool = id in profile["arsenal"]
		var b := UI.tile(id, String(p["name"]), String(p["desc"]), UI.ORANGE if on else UI.MUTED, on, 104)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			if id in profile["arsenal"]:
				if profile["arsenal"].size() > 3:
					profile["arsenal"].erase(id)
			elif profile["arsenal"].size() < Data.ARSENAL_SIZE:
				profile["arsenal"].append(id)
			Save.save_profile(profile)
			show_arsenal())
		grid.add_child(b)
		if fresh:
			Fx.rise_in(b, 0.06 + 0.025 * grid.get_child_count(), 0.3, 0.85)

# ---------------------------------------------------------------- partie
# ---------------------------------------------------------------- mondes
var _go_button: Button = null
var _world_title: Label = null
var _world_sub: Label = null

func _boss_title() -> String:
	return String(Data.ENEMIES[Data.boss_kind()]["name"]).to_upper()

## Monde ouvert : le premier, ou le suivant d'un monde terminé.
func _world_open(i: int) -> bool:
	return i == 0 or (profile["worlds_done"] as Array).has(i - 1)

## Monde de la prochaine partie : celui choisi au Relais s'il est ouvert et livré, sinon Nébuleuse 7.
## `--world=N` (essais, captures) force un monde livré.
func _chosen_world() -> int:
	if duo != null and duo.world_override >= 0:
		return duo.world_override  # duo : le monde de l'hôte
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--world="):
			# « --world=2! » force un monde même sans boss livré (essais pendant la construction)
			var n := clampi(int(a.trim_prefix("--world=").trim_suffix("!")) - 1, 0, Data.WORLDS.size() - 1)
			if Data.world_ready(n) or a.ends_with("!"):
				return n
	var w := clampi(int(profile.get("world", 0)), 0, Data.WORLDS.size() - 1)
	return w if _world_open(w) and Data.world_ready(w) else 0

## Ligne du Relais : ◀ MONDE n · NOM ▶ et l'univers ; un monde fermé ou en construction bloque PARTIR.
func _world_selector() -> Control:
	var box := UI.vbox(2)
	var row := UI.hbox(10)
	box.add_child(row)
	var prev := UI.button("◀", 22, UI.MUTED, 56)
	prev.custom_minimum_size = Vector2(56, 48)
	prev.pressed.connect(func(): _shift_world(-1))
	row.add_child(prev)
	_world_title = UI.label("", 24, UI.TEXT)
	_world_title.add_theme_font_override("font", UI.TITLE)
	_world_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_world_title)
	var nxt := UI.button("▶", 22, UI.MUTED, 56)
	nxt.custom_minimum_size = Vector2(56, 48)
	nxt.pressed.connect(func(): _shift_world(1))
	row.add_child(nxt)
	_world_sub = UI.label("", 19, UI.MUTED)
	box.add_child(_world_sub)
	return box

func _shift_world(d: int) -> void:
	var w := clampi(int(profile.get("world", 0)) + d, 0, Data.WORLDS.size() - 1)
	profile["world"] = w
	Save.save_profile(profile)
	sfx.play("click", 1.1 + 0.1 * d, -6.0)
	_refresh_world()

func _refresh_world() -> void:
	if _world_title == null or not is_instance_valid(_world_title):
		return
	var w := clampi(int(profile.get("world", 0)), 0, Data.WORLDS.size() - 1)
	var wd: Dictionary = Data.WORLDS[w]
	var done := (profile["worlds_done"] as Array).has(w)
	_world_title.text = "MONDE %d  ·  %s%s" % [w + 1, String(wd["name"]).to_upper(), "  ✓" if done else ""]
	_world_title.add_theme_color_override("font_color", wd["accent"])
	var ok := _world_open(w) and Data.world_ready(w)
	if not Data.world_ready(w):
		_world_sub.text = String(wd["genre"]) + "  ·  en construction"
	elif not _world_open(w):
		_world_sub.text = "Verrouillé : récupère d'abord l'éclat de " + String(Data.WORLDS[w - 1]["name"])
	else:
		_world_sub.text = String(wd["genre"]) + ("  ·  éclat récupéré" if done else "  ·  éclat à récupérer")
	if _go_button != null and is_instance_valid(_go_button):
		_go_button.disabled = not ok
		_go_button.modulate = Color(1, 1, 1, 1.0 if ok else 0.45)

## PARTIR : l'interface s'efface, Jo court dans le portail, puis la partie commence.
func _depart() -> void:
	if state != "base":
		return
	if duo != null and duo.intercept_depart():
		return  # duo : l'invité attend que l'hôte lance
	state = "depart"
	sfx.play("portal", 0.8)
	var tw := screen.create_tween()
	tw.tween_property(screen, "modulate:a", 0.0, 0.25)
	view.launch(func():
		hud.fade = 1.0
		start_run())

func start_run() -> void:
	profile["runs"] = int(profile["runs"]) + 1
	Save.save_profile(profile)
	_clear_screen()
	_clear_overlay()
	state = "arena"
	hero.reset_run()
	arena.reset_run()
	arena.visible = false
	arena.cam.enabled = false
	hud.visible = true
	Data.world = _chosen_world()
	arena.set_world()
	view.set_world()
	hud.world = Data.world_name()
	joy.enabled = true
	joy.reset()
	arena.start_room(1, "combat")
	view.start_room()
	hud.fade = 1.0
	hud.flash(Data.world_name().to_upper(), 2.0, Data.WORLDS[Data.world]["accent"])
	sfx.play("portal")
	_start_run_ui()
	if duo != null:
		duo.on_run_started()

## Interface d'une nouvelle partie : compteurs remis à zéro, cartes « nouvel ennemi » vidées,
## tutoriel des deux pouces à la toute première partie (tant qu'il n'a pas été fait).
func _start_run_ui() -> void:
	run_items = []
	hud.tickets = int(profile["tickets"])
	hud.hp = 1.0
	hud.energy = 0.0
	hud.snap()
	enemy_card.clear()
	if tutorial != null and is_instance_valid(tutorial):
		tutorial.queue_free()
	tutorial = null
	if not bool(profile.get("tutorial_done", false)):
		tutorial = TutorialScript.new()
		tutorial.joy = joy
		tutorial.finished.connect(func():
			profile["tutorial_done"] = true
			Save.save_profile(profile)
			tutorial = null)
		hud.add_child(tutorial)

## Premier passage d'un genre d'ennemi pour ce joueur : carte « NOUVEL ENNEMI » (mémorisée dans la sauvegarde).
func _on_enemy_spawned(e: Node2D) -> void:
	if state != "arena":
		return
	var kind := String(e.kind)
	if not EnemyCardScript.TIPS.has(kind):
		return
	var seen: Array = profile.get("seen_enemies", [])
	if kind in seen:
		return
	seen.append(kind)
	profile["seen_enemies"] = seen
	Save.save_profile(profile)
	enemy_card.push(kind)

func _pause_for_overlay() -> void:
	hud.flash("", 0.0)
	if duo != null and duo.in_run():
		# duo : la partie continue pour l'autre ; on est invulnérable pendant son choix (duo_host.gd)
		joy.enabled = false
		joy.reset()
		return
	get_tree().paused = true
	joy.enabled = false
	joy.reset()

func _resume() -> void:
	_clear_overlay()
	get_tree().paused = false
	joy.enabled = true

func _card_overlay(title: String, subtitle: String) -> VBoxContainer:
	_clear_overlay()
	overlay = _full(false)
	overlay.add_child(UI.dim())
	ui_layer.add_child(overlay)
	var box := UI.vbox(14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(UI.center(box))
	box.add_child(UI.title(title, 46, UI.TEXT, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	if subtitle != "":
		box.add_child(UI.label(subtitle, 22, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	box.add_child(sp)
	return box

func _show_power_choice() -> void:
	if get_tree().paused or (duo != null and duo.in_run() and overlay != null):
		return
	var pool := []
	for id in profile["arsenal"]:
		var p := Data.power(String(id))
		if not p.is_empty() and hero.power_count(String(id)) < int(p["max"]):
			pool.append(p)
	pool.shuffle()
	if pool.is_empty():
		arena.consume_energy()
		return
	_pause_for_overlay()
	sfx.play("level")
	var vs := get_viewport().get_visible_rect().size
	var head := _deal_overlay("ÉNERGIE PLEINE", "Choisis un pouvoir pour cette partie", UI.ACCENT)
	var n := mini(3, pool.size())
	var cs := Vector2(264, 356)
	if vs.y < 700.0:
		cs = Vector2(240, 324)
	var gap := 34.0
	var cy := head + (vs.y - head) * 0.5 - 6.0
	var cards: Array = []
	for i in range(n):
		var p: Dictionary = pool[i]
		var id := String(p["id"])
		var have: int = hero.power_count(id)
		var tier: int = CardScript.POWER_TIER.get(id, 0)
		var b: Button = CardScript.new()
		b.setup(id, String(p["name"]), String(p["desc"]), tier, CardScript.POWER_TIER_NAMES[tier], ("NIV. %d" % (have + 1)) if have > 0 else "", cs)
		overlay.add_child(b)
		cards.append(b)
		# éventail : les cartes du bord descendent un peu et penchent vers l'extérieur
		var k := i - (n - 1) * 0.5
		var to := Vector2(vs.x * 0.5 + k * (cs.x + gap) - cs.x * 0.5, cy - cs.y * 0.5 + absf(k) * 18.0)
		b.deal(Vector2(vs.x * 0.5 - cs.x * 0.5, vs.y + 60.0), to, k * 0.075, 0.12 + 0.09 * i)
		b.reveal(0.62 + 0.16 * i)
		b.pressed.connect(func():
			var ov := overlay
			for o in cards:
				(o as Button).disabled = true
			hero.add_power(id)
			arena.consume_energy()
			if id == "turret":
				arena.turrets.append({"pos": hero.position + Vector2.RIGHT.rotated(randf() * TAU) * 100.0, "cd": 0.0, "ang": 0.0})
			if id == "ally":
				arena.allies.append({"ang": randf() * TAU, "cd": 0.0})
			sfx.play("chest", 1.1, -4.0)
			b.pick(Vector2(vs.x * 0.5, cy))
			for o in cards:
				if o != b:
					(o as Button).discard(signf((o as Button).position.x - b.position.x))
			var tw := ov.create_tween()
			tw.tween_interval(0.42)
			tw.tween_callback(func():
				if overlay == ov:
					hud.flash(String(p["name"]).to_upper(), 1.4, UI.ORANGE)
					_resume()
					view.power_fx()))

## Fond des overlays à cartes : voile, halo coloré au centre, titre tamponné, sous-titre. Renvoie le bas du titre.
func _deal_overlay(title: String, subtitle: String, col: Color) -> float:
	_clear_overlay()
	var vs := get_viewport().get_visible_rect().size
	overlay = _full(false)
	overlay.add_child(UI.dim(0.8))
	var glow := Fx.halo(Color(col, 0.22), Vector2(vs.x * 1.1, vs.y * 1.2))
	glow.position = Vector2(vs.x * -0.05, vs.y * 0.0)
	overlay.add_child(glow)
	ui_layer.add_child(overlay)
	Fx.screen_in(overlay, 0.15)
	var top := clampf(vs.y * 0.05, 18.0, 70.0)
	var t := UI.title(title, 50, UI.TEXT, col, HORIZONTAL_ALIGNMENT_CENTER)
	t.position = Vector2(0, top)
	t.size = Vector2(vs.x, 62)
	overlay.add_child(t)
	Fx.slam(t, 0.02, 1.8)
	Fx.shine(t, vs.x * 0.5, 2.6, 0.5)
	var s := UI.label(subtitle, 24, Color("#C4D2E4"), HORIZONTAL_ALIGNMENT_CENTER)
	s.position = Vector2(0, top + 62)
	s.size = Vector2(vs.x, 30)
	overlay.add_child(s)
	Fx.rise_in(s, 0.2)
	return top + 96.0

func _show_item(item: Dictionary) -> void:
	if duo != null and duo.defer_item(item):
		return  # duo : un autre écran est ouvert, l'objet attend
	_pause_for_overlay()
	profile["inventory"].append(item)
	Save.save_profile(profile)
	run_items.append(item)
	var vs := get_viewport().get_visible_rect().size
	var tpl := Data.item_template(String(item["id"]))
	var rarity := int(item["rarity"])
	var rc: Color = Data.RARITY_COLORS[rarity]
	var head := _deal_overlay("OBJET TROUVÉ", Data.SLOT_NAMES[tpl["slot"]].to_upper() + "  ·  " + Data.item_stat_text(item), rc)
	var cs := Vector2(300, 356) if vs.y >= 700.0 else Vector2(270, 320)
	var c: Button = CardScript.new()
	c.setup(String(tpl["slot"]), Data.item_label(item), Data.SLOT_NAMES[tpl["slot"]] + "\n" + Data.item_stat_text(item), rarity, Data.RARITY_NAMES[rarity].to_upper(), "", cs)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(c)
	var cy := head + 10.0 + cs.y * 0.5
	c.deal(Vector2(vs.x * 0.5 - cs.x * 0.5, vs.y + 60.0), Vector2(vs.x * 0.5 - cs.x * 0.5, cy - cs.y * 0.5), 0.0, 0.08)
	c.reveal(0.5)
	var by := cy + cs.y * 0.5 + 18.0
	var cur_uid := String(profile["equipped"].get(tpl["slot"], ""))
	var cur := Save.find_item(profile, cur_uid) if cur_uid != "" else {}
	if not cur.is_empty():
		var cl := UI.label("Équipé : " + Data.item_label(cur) + " (" + Data.item_stat_text(cur) + ")", 20, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		cl.position = Vector2(0, by)
		cl.size = Vector2(vs.x, 26)
		overlay.add_child(cl)
		Fx.rise_in(cl, 0.8)
		by += 30.0
	var row := UI.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.position = Vector2(0, minf(by, vs.y - 96.0))
	row.size = Vector2(vs.x, 84)
	overlay.add_child(row)
	var eq := UI.primary("ÉQUIPER", 30, 250)
	eq.custom_minimum_size = Vector2(250, 82)
	eq.pressed.connect(func():
		Save.equip(profile, String(item["uid"]))
		Save.save_profile(profile)
		_apply_profile_to_hero()
		_after_item())
	row.add_child(eq)
	var keep := UI.button("GARDER", 28, UI.MUTED, 210)
	keep.custom_minimum_size = Vector2(210, 82)
	keep.pressed.connect(_after_item)
	row.add_child(keep)
	Fx.rise_in(eq, 0.85, 0.34, 0.6)
	Fx.rise_in(keep, 0.92, 0.34, 0.6)

func _after_item() -> void:
	_resume()
	if duo != null and duo.is_guest():
		return  # duo : les portails viennent de l'hôte
	if arena.cleared and not arena.chest.is_empty() and arena.chest["open"]:
		if arena.room >= Data.ROOMS:
			_victory()
		else:
			_show_doors()

func _on_room_cleared() -> void:
	hud.flash("SALLE %d TERMINÉE" % arena.room, 2.2, UI.GOLD)

## Fin de salle : trois portails s'ouvrent dans l'arène (rendus en 3D par view3d.gd), Jo choisit sa route
## en entrant dans l'un d'eux. Avant le boss, un seul portail.
func _show_doors() -> void:
	var next: int = arena.room + 1
	var doors := [
		{"kind": "combat", "title": "COMBAT", "desc": "Vagues normales · coffre normal", "col": UI.ACCENT},
		{"kind": "elite", "title": "ÉLITE", "desc": "Une élite dorée · meilleur coffre", "col": UI.DANGER},
		{"kind": "tresor", "title": "TRÉSOR", "desc": "Moins d'ennemis · meilleur coffre", "col": UI.GOLD},
	]
	if next >= Data.ROOMS:
		doors = [{"kind": "combat", "title": _boss_title(), "desc": "Le gardien de l'éclat du Cœur", "col": Color("#F23CB8")}]
	_next_room = next
	arena.open_doors(doors)
	hud.flash("CHOISIS TON PORTAIL", 1.1, UI.ACCENT)

var _next_room := 0

func _on_door_taken(d: Dictionary) -> void:
	sfx.play("portal")
	joy.enabled = false
	joy.reset()
	view.door_enter(d)
	await get_tree().create_timer(0.55, false).timeout
	if state != "arena":
		return
	joy.enabled = true
	var next := _next_room
	arena.start_room(next, String(d["kind"]))
	view.start_room()
	hud.fade = 1.0
	hud.flash(("SALLE %d · %s" % [next, String(d["title"])]) if next < Data.ROOMS else _boss_title(), 1.8, d["col"])

func _show_pause() -> void:
	if state != "arena" or get_tree().paused:
		return
	_pause_for_overlay()
	var box := _card_overlay("PAUSE", "Salle %d · %d ennemis abattus" % [arena.room, arena.kills])
	Fx.screen_in(overlay, 0.15)
	var r := UI.primary("REPRENDRE", 34, 400)
	r.custom_minimum_size = Vector2(400, 88)
	r.pressed.connect(_resume)
	box.add_child(r)
	var mu := UI.button("MUSIQUE : " + ("OUI" if Music.enabled else "NON"), 24, UI.ACCENT, 400)
	mu.custom_minimum_size = Vector2(400, 80)
	mu.pressed.connect(func():
		Music.set_enabled(not Music.enabled)
		mu.text = "MUSIQUE : " + ("OUI" if Music.enabled else "NON"))
	box.add_child(mu)
	# caméra : recul et inclinaison, appliqués tout de suite derrière le menu
	var cams := UI.hbox(12)
	cams.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(cams)
	var cz := UI.button("", 22, UI.ACCENT, 194)
	cz.custom_minimum_size = Vector2(194, 80)
	var ca := UI.button("", 22, UI.ACCENT, 194)
	ca.custom_minimum_size = Vector2(194, 80)
	var cam_text := func():
		cz.text = "VUE : " + String(Dev.ZOOMS[Dev.nearest(Dev.ZOOMS, Dev.get_f("cam_dist"))][0])
		ca.text = "ANGLE : " + String(Dev.ANGLES[Dev.nearest(Dev.ANGLES, Dev.get_f("cam_pitch"))][0])
	cam_text.call()
	cz.pressed.connect(func():
		var i := (Dev.nearest(Dev.ZOOMS, Dev.get_f("cam_dist")) + 1) % Dev.ZOOMS.size()
		Dev.set_value("cam_dist", Dev.ZOOMS[i][1])
		view.refresh_cam()
		cam_text.call())
	ca.pressed.connect(func():
		var i := (Dev.nearest(Dev.ANGLES, Dev.get_f("cam_pitch")) + 1) % Dev.ANGLES.size()
		Dev.set_value("cam_pitch", Dev.ANGLES[i][1])
		view.refresh_cam()
		cam_text.call())
	cams.add_child(cz)
	cams.add_child(ca)
	var dv := UI.button("MODE DÉVELOPPEUR", 22, UI.MUTED, 400)
	dv.custom_minimum_size = Vector2(400, 72)
	dv.pressed.connect(_show_dev)
	box.add_child(dv)
	var q := UI.button("ABANDONNER  ·  le butin reste", 24, UI.MUTED, 400)
	q.custom_minimum_size = Vector2(400, 80)
	q.pressed.connect(func(): _show_end(false, "PARTIE ABANDONNÉE", "Le butin reste, les pouvoirs partent."))
	box.add_child(q)
	Fx.rise_in(r, 0.05)
	Fx.rise_in(q, 0.12)

## Mode développeur : panneau à droite, sans voile, la partie reste visible derrière (en pause) pour régler
## la caméra et les tailles à l'œil ; cadence 60 / 120 i/s et compteur. Les valeurs s'affichent pour être notées.
func _show_dev() -> void:
	_clear_overlay()
	overlay = _full(false)
	ui_layer.add_child(overlay)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.12, 0.88)
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.56
	panel.anchor_right = 0.985
	panel.anchor_top = 0.03
	panel.anchor_bottom = 0.97
	overlay.add_child(panel)
	var box := UI.vbox(6)
	panel.add_child(box)
	box.add_child(UI.title("MODE DÉVELOPPEUR", 30, UI.TEXT, UI.ACCENT))
	var summary := UI.label(Dev.summary(), 17, UI.MUTED)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var rows := [["cam_dist", "Recul caméra", 0.1], ["cam_pitch", "Inclinaison", 1.0], ["cam_fov", "Champ de vision", 1.0], ["hero_scale", "Taille de Jo", 0.01], ["mob_scale", "Taille des ennemis (nouveaux)", 0.01]]
	for r in rows:
		var key: String = r[0]
		var head := UI.hbox(8)
		var name_l := UI.label(String(r[1]), 19, UI.TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_l)
		var val_l := UI.label("%.2f" % Dev.get_f(key), 19, UI.ACCENT)
		head.add_child(val_l)
		box.add_child(head)
		var sl := HSlider.new()
		sl.min_value = Dev.RANGES[key][0]
		sl.max_value = Dev.RANGES[key][1]
		sl.step = float(r[2])
		sl.value = Dev.get_f(key)
		sl.custom_minimum_size = Vector2(0, 44)
		sl.value_changed.connect(func(x: float):
			Dev.set_value(key, x)
			val_l.text = "%.2f" % x
			summary.text = Dev.summary()
			view.refresh_cam())
		box.add_child(sl)
	var fps_row := UI.hbox(10)
	box.add_child(fps_row)
	for f in [60, 120]:
		var fb := UI.button("%d i/s" % f, 22, UI.ACCENT if int(Dev.v["fps"]) == f else UI.MUTED, 120)
		fb.custom_minimum_size = Vector2(120, 64)
		fb.pressed.connect(func():
			Dev.set_value("fps", f)
			_show_dev())
		fps_row.add_child(fb)
	var cnt := UI.button("COMPTEUR : " + ("OUI" if bool(Dev.v["show_fps"]) else "NON"), 20, UI.MUTED, 180)
	cnt.custom_minimum_size = Vector2(180, 64)
	cnt.pressed.connect(func():
		Dev.set_value("show_fps", not bool(Dev.v["show_fps"]))
		_show_dev())
	fps_row.add_child(cnt)
	box.add_child(summary)
	var end_row := UI.hbox(10)
	box.add_child(end_row)
	var rs := UI.button("PAR DÉFAUT", 20, UI.MUTED, 170)
	rs.custom_minimum_size = Vector2(170, 64)
	rs.pressed.connect(func():
		Dev.reset()
		view.refresh_cam()
		_show_dev())
	end_row.add_child(rs)
	var back := UI.primary("RETOUR", 24, 170)
	back.custom_minimum_size = Vector2(170, 64)
	back.pressed.connect(func():
		_clear_overlay()
		get_tree().paused = false
		_show_pause())
	end_row.add_child(back)

func _on_hero_died() -> void:
	if get_tree().paused:
		return
	if duo != null and duo.in_run():
		duo.on_local_down()  # duo : la partenaire peut relever ; la partie n'est perdue qu'à deux à terre
		return
	sfx.play("boom", 0.6)
	view.add_shake(0.8)
	hud.flash("K.O.", 1.2, UI.DANGER)
	# l'animation de chute de Jo se voit avant l'écran de fin
	joy.enabled = false
	await get_tree().create_timer(1.1, true, false, true).timeout
	if state != "arena":
		return
	_pause_for_overlay()
	_show_end(false, "RAPPEL AU RELAIS", "Le butin reste, les pouvoirs partent.")

func _victory() -> void:
	_pause_for_overlay()
	var done: Array = profile["worlds_done"]
	var first := not done.has(Data.world)
	if first:
		done.append(Data.world)
	profile["shards"] = done.size()
	var nxt := Data.world + 1
	var sub := "Éclat du Cœur récupéré : le Relais se rallume."
	if not first:
		sub = "Monde déjà rallumé : le butin reste à toi."
	elif nxt < Data.WORLDS.size():
		sub += "  Nouveau monde ouvert : " + String(Data.WORLDS[nxt]["name"]) + "."
		profile["world"] = nxt if Data.world_ready(nxt) else Data.world
	_show_end(true, "VICTOIRE", sub)

## Écran de fin : récapitulatif de la partie, REJOUER (repart aussitôt) ou RELAIS.
func _show_end(won: bool, title: String, subtitle: String) -> void:
	if duo != null:
		duo.on_show_end(won, title, subtitle)
	_clear_overlay()
	var es: Control = EndScreenScript.new()
	overlay = es
	ui_layer.add_child(es)
	es.build({
		"room": arena.room, "rooms": Data.ROOMS, "kills": arena.kills, "tickets": arena.tickets,
		"items": run_items, "shard": won, "record": arena.room > int(profile["best_room"]) and int(profile["runs"]) > 1,
		"title": title, "subtitle": subtitle,
	})
	Fx.screen_in(es, 0.2)
	es.replay.connect(func():
		_end_run(won)
		_depart())
	es.relais.connect(func(): _end_run(won))

func _end_run(_won: bool) -> void:
	profile["tickets"] = int(profile["tickets"]) + arena.tickets
	profile["kills"] = int(profile["kills"]) + arena.kills
	profile["best_room"] = maxi(int(profile["best_room"]), arena.room)
	Save.save_profile(profile)
	enemy_card.clear()
	arena.stop()
	view.stop()
	show_base()
	if duo != null:
		duo.after_run()
