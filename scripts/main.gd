extends Node2D
## Chef d'orchestre : le Relais (base), la Loge (équipement), l'Arsenal (arbre des pouvoirs de partie),
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
const Mob3D = preload("res://scripts/mob3d.gd")
const Fx = preload("res://scripts/ui/fx.gd")
const CardScript = preload("res://scripts/ui/card.gd")
const EnemyCardScript = preload("res://scripts/ui/enemy_card.gd")
const TutorialScript = preload("res://scripts/ui/tutorial.gd")
const EndScreenScript = preload("res://scripts/ui/end_screen.gd")
const TalentsScreenScript = preload("res://scripts/ui/talents_screen.gd")
const Talents = preload("res://scripts/talents.gd")
const DuoScript = preload("res://scripts/net/duo.gd")
const Loot = preload("res://scripts/loot.gd")
const BoxesScreen = preload("res://scripts/ui/boxes_screen.gd")
const BoxArt = preload("res://scripts/ui/boxes_art.gd")

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
	Mob3D.warm_start()  # modèles d'ennemis chargés en tâche de fond pendant le Relais
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
	_hook_boxes()
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
	view.hero.follow_skin()  # apparence équipée (scripts/loot.gd)
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
	arena.bonus_choice.connect(_on_bonus_choice)
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
	hero.profile = profile
	hero.set_meta("profile", profile)  # talents permanents (talents.gd, lus dans hero.recalc())
	hero.recalc()
	if view != null:
		view.set_hero_items(hero.items)

var _warm_done := false
func _process(_dt: float) -> void:
	if not _warm_done:
		_warm_done = Mob3D.warm_poll()
	if state == "arena":
		hud.hp = hero.hp / hero.hp_max
		hud.hp_text = "%d / %d" % [int(ceil(hero.hp)), int(hero.hp_max)]
		hud.hp_max = hero.hp_max
		hud.shield = hero.shield_max > 0 and hero.shield_ready
		hud.energy = arena.energy / arena.energy_need
		joy.dash_max = hero.dash_max
		joy.dash_charges = int(floorf(hero.dash_stock + 0.0001))
		joy.dash_ratio = hero.dash_stock - floorf(hero.dash_stock)
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
	view.relais.get_meta("hero").follow_skin()
	Music.play("relais")
	view.set_shards(int(profile["shards"]))
	hud.visible = false
	joy.enabled = false
	screen = _full(false)
	ui_layer.add_child(screen)
	_build_relais_panel()

## Panneau du Relais (droite) : titre PASSEURS en relief qui brille, compteurs qui défilent depuis la dernière
## visite, PARTIR énorme (halo qui pulse, reflet, chevrons qui filent), puis les six écrans du Relais (ÉQUIPEMENT,
## POUVOIRS, TALENTS, DUO, COFFRES, APPARENCES), chacun avec une ligne qui dit ce qu'on y trouve.
func _build_relais_panel() -> void:
	var ins := UI.safe_insets(get_viewport())
	screen.add_child(_side_shade(0.4))
	var right := UI.vbox(10)
	right.anchor_left = 0.53
	right.anchor_right = 1.0
	right.offset_right = -float(ins["right"]) - 24.0
	right.anchor_top = 0.045
	right.anchor_bottom = 0.98
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
		cl.add_theme_font_size_override("font_size", 24)
		chips.add_child(c)
	Fx.count(c1.get_meta("label"), int(_shown.get("shards", shards)), shards, 0.7, 0.35, "%d / 10")
	Fx.count(c2.get_meta("label"), int(_shown.get("tickets", tk)), tk, 1.0, 0.35, "%d")
	Fx.count(c3.get_meta("label"), int(_shown.get("best", best)), best, 0.6, 0.35, "record %d")
	if int(_shown.get("tickets", tk)) != tk:
		var tbump := c2.create_tween()
		tbump.tween_interval(1.35)
		tbump.tween_callback(func(): Fx.bump(c2, 0.15))
	_shown = {"shards": shards, "tickets": tk, "best": best}
	# PARTIR : le bouton qu'on a envie de toucher
	var go := UI.primary("PARTIR", 54)
	go.custom_minimum_size = Vector2(0, 104)
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
	# les six écrans du Relais, deux par ligne : nom en gros, et dessous ce qu'on y trouve
	var inv_n: int = profile["inventory"].size()
	var buyable := 0
	for t in Talents.TALENTS:
		if Talents.block_reason(profile, String(t["id"])) == "":
			buyable += 1
	var row1 := UI.hbox(12)
	right.add_child(row1)
	var equ := _side_button("ÉQUIPEMENT", "torse", UI.ACCENT, ("%d objets à porter" % inv_n) if inv_n > 1 else "Ce que porte Jo")
	equ.pressed.connect(show_loge)
	row1.add_child(equ)
	var ars := _side_button("POUVOIRS", "bolt", UI.ORANGE, "Ce qui sort en partie")
	ars.pressed.connect(show_arsenal)
	row1.add_child(ars)
	var row2 := UI.hbox(12)
	right.add_child(row2)
	# TALENTS : la ligne dit combien d'améliorations s'achètent tout de suite (en doré)
	var tal := _side_button("TALENTS", "tree", UI.GOLD, ("%d achat%s possible%s" % [buyable, "s" if buyable > 1 else "", "s" if buyable > 1 else ""]) if buyable > 0 else "Bonus permanents", buyable > 0)
	tal.pressed.connect(show_talents)
	row2.add_child(tal)
	# DUO : partie à deux téléphones (scripts/net/duo.gd)
	var duo_b := _side_button("DUO", "portal", Color("#B36BFF"), "Jouer à deux")
	duo_b.pressed.connect(func(): duo.open_lobby())
	row2.add_child(duo_b)
	var row3 := _boxes_row()
	right.add_child(row3)
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
	Fx.rise_in(row1, 0.42)
	Fx.rise_in(row2, 0.47)
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

## Bouton d'un écran du Relais : pictogramme à gauche, nom en gros (25 px), et dessous ce qu'on y trouve
## (20 px ; en doré quand il y a quelque chose à faire tout de suite). Deux boutons par ligne.
func _side_button(text: String, icon: String, col: Color, desc: String, hot: bool = false) -> Button:
	var b := UI.button("", 26, col)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 84)
	b.set_meta("name", text)
	var ic := UI.Icon.new(icon, col, 40.0)
	ic.anchor_top = 0.5
	ic.anchor_bottom = 0.5
	ic.offset_left = 14
	ic.offset_top = -24
	b.add_child(ic)
	var v := UI.vbox(0)
	v.anchor_right = 1.0
	v.anchor_bottom = 1.0
	v.offset_left = 64
	v.offset_right = -8
	v.offset_top = 4
	v.offset_bottom = -8
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var nm := UI.label(text, 25, UI.TEXT)
	nm.add_theme_font_override("font", UI.TITLE)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(nm)
	if desc != "":
		var d := UI.label(desc, UI.FS_SMALL, UI.GOLD if hot else UI.SOFT)
		d.clip_text = true
		d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(d)
		b.set_meta("desc", d)
	return b

func show_talents() -> void:
	var fresh := state != "talents"
	_clear_screen(fresh)
	state = "talents"
	screen = TalentsScreenScript.new()
	ui_layer.add_child(screen)
	screen.build(self, fresh)

## ÉQUIPEMENT (identifiant interne : loge) : ce que Jo porte, et de quoi le changer. Après Jo, les six
## emplacements ; en toucher un montre à côté les objets possibles pour cet emplacement, en grandes lignes, avec
## ce que chacun change par rapport à l'objet porté (« +5 % » en vert, « −3 % » en rouge). Toucher un objet
## ouvre sa fiche (ÉQUIPER, RETIRER). Les objets identiques (même modèle, même rareté) sont regroupés (« ×3 »).
var _equip_slot := "arme"
var _equip_list: ScrollContainer = null

func show_loge() -> void:
	var fresh := state != "loge"
	var keep_scroll := 0
	if not fresh and _equip_list != null and is_instance_valid(_equip_list):
		keep_scroll = _equip_list.scroll_vertical
	_clear_screen(fresh)
	state = "loge"
	screen = _full(false)
	ui_layer.add_child(screen)
	screen.add_child(_side_shade(0.22))
	view.relais_focus = 1.0
	if fresh:
		Fx.screen_in(screen)
	var vp := get_viewport()
	var vs := vp.get_visible_rect().size
	var ins := UI.safe_insets(vp)
	var m := UI.header_money(profile)
	var head := UI.screen_header(vp, "ÉQUIPEMENT", "Choisis ce que Jo porte. Touche un objet pour voir ce qu'il change.", UI.ACCENT, show_base, m[0], m[1])
	screen.add_child(head)
	var top := UI.header_height(vp) + 14.0
	var bottom := vs.y - float(ins["bottom"]) - 6.0
	var x0 := vs.x * 0.335
	var x2 := vs.x - float(ins["right"]) - 16.0
	var gap := 20.0
	var w1 := (x2 - x0 - gap) * 0.43
	# ---- colonne 1 : les six emplacements (ce que Jo porte)
	var left := UI.vbox(8)
	left.position = Vector2(x0, top)
	left.size = Vector2(w1, bottom - top)
	screen.add_child(left)
	left.add_child(UI.title("JO PORTE", 28, UI.TEXT, UI.ACCENT))
	var th := floorf(minf(88.0, (bottom - top - 44.0 - 5.0 * 8.0) / 6.0))
	for slot in Data.SLOTS:
		var uid := String(profile["equipped"].get(slot, ""))
		var it := Save.find_item(profile, uid) if uid != "" else {}
		var on: bool = slot == _equip_slot
		var b: Button
		if it.is_empty():
			var n := _slot_choices(slot).size()
			b = UI.big_tile(slot, String(Data.SLOT_NAMES[slot]) + " : rien", ("%d objet%s possible%s" % [n, "s" if n > 1 else "", "s" if n > 1 else ""]) if n > 0 else "aucun objet", UI.MUTED, UI.SOFT, on, th)
		else:
			var rc: Color = Data.RARITY_COLORS[int(it["rarity"])]
			b = UI.big_tile(slot, Data.item_label(it), Data.item_stat_text(it), rc, rc.lightened(0.25), on, th)
		var sl: String = slot
		b.pressed.connect(func():
			if _equip_slot == sl and not it.is_empty():
				_equip_detail(it, 1, it)
				return
			_equip_slot = sl
			sfx.play("click", 1.1, -6.0)
			show_loge())
		left.add_child(b)
	if fresh:
		Fx.slide_in(left, Vector2(-120, 0), 0.0, 0.4)
	# ---- colonne 2 : les objets possibles pour l'emplacement choisi, comparés à celui porté
	var rx := x0 + w1 + gap
	var right := UI.vbox(8)
	right.position = Vector2(rx, top)
	right.size = Vector2(x2 - rx, bottom - top)
	screen.add_child(right)
	var worn := Save.find_item(profile, String(profile["equipped"].get(_equip_slot, "")))
	var groups := _slot_choices(_equip_slot)
	var total := 0
	for g in groups:
		total += int(g["n"])
	right.add_child(UI.title("%s : %d OBJET%s" % [String(Data.SLOT_NAMES[_equip_slot]).to_upper(), total, "S" if total > 1 else ""], 28, UI.TEXT, UI.GOLD))
	if fresh:
		Fx.slide_in(right, Vector2(140, 0), 0.08, 0.42)
	if groups.is_empty():
		var e := UI.label("Aucun objet pour cet emplacement. Tu en trouves dans les coffres de fin de salle, sur les élites et dans les COFFRES du Relais.", UI.FS_BODY, UI.TEXT)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(e)
		return
	# liste qui défile : rectangle fixe sous le titre (dans un conteneur, elle s'allongerait à son contenu)
	var scroll := UI.scroll()
	scroll.position = Vector2(rx, top + 46.0)
	scroll.size = Vector2(x2 - rx, bottom - top - 46.0)
	screen.add_child(scroll)
	if fresh:
		Fx.slide_in(scroll, Vector2(140, 0), 0.08, 0.42)
	_equip_list = scroll
	var list := UI.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for g in groups:
		var it: Dictionary = g["item"]
		var n: int = g["n"]
		var is_worn: bool = g["worn"]
		var rc: Color = Data.RARITY_COLORS[int(it["rarity"])]
		var b := UI.big_tile(_equip_slot, Data.item_label(it) + ("  ×%d" % n if n > 1 else ""), Data.item_stat_text(it), rc, rc.lightened(0.25), is_worn, 96)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var rz: HBoxContainer = b.get_meta("right")
		if is_worn:
			rz.add_child(UI.tag("PORTÉ", UI.ACCENT, UI.INK, 20))
		else:
			rz.add_child(_delta_badge(it, worn))
		b.pressed.connect(func(): _equip_detail(it, n, worn))
		list.add_child(b)
	if groups.size() == 1 and bool(groups[0]["worn"]):
		var e2 := UI.label("Pas d'autre objet pour cet emplacement. Les coffres en donnent.", UI.FS_BODY, UI.SOFT)
		e2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(e2)
	if keep_scroll > 0:
		scroll.set_deferred("scroll_vertical", keep_scroll)

## Objets de l'inventaire pour un emplacement, regroupés (même modèle, même rareté) :
## [{item, n, worn}], l'objet porté d'abord, puis du plus rare au moins rare, puis du plus fort au moins fort.
func _slot_choices(slot: String) -> Array:
	var worn_uid := String(profile["equipped"].get(slot, ""))
	var by_key := {}
	var out := []
	for it in profile["inventory"]:
		if String(Data.item_template(String(it["id"]))["slot"]) != slot:
			continue
		var is_worn := String(it["uid"]) == worn_uid
		var key := "%s_%d%s" % [String(it["id"]), int(it["rarity"]), "_w" if is_worn else ""]
		if by_key.has(key):
			by_key[key]["n"] += 1
		else:
			by_key[key] = {"item": it, "n": 1, "worn": is_worn}
			out.append(by_key[key])
	out.sort_custom(func(a, b):
		if bool(a["worn"]) != bool(b["worn"]):
			return bool(a["worn"])
		if int(a["item"]["rarity"]) != int(b["item"]["rarity"]):
			return int(a["item"]["rarity"]) > int(b["item"]["rarity"])
		return Data.item_value(a["item"]) > Data.item_value(b["item"]))
	return out

const _STAT_NAMES := {"crit": "critique", "dmg": "dégâts", "rate": "cadence", "speed": "vitesse", "range": "portée", "energy": "énergie par kill", "pickup": "rayon de ramassage"}

## « +12 % cadence », « −8 PV max » (signe affiché ; `short` : sans le nom de la stat, « +12 % »).
func _stat_txt(stat: String, v: float, short: bool = false) -> String:
	var sgn := "+" if v >= 0.0 else "−"
	if stat == "hp":
		return "%s%d PV%s" % [sgn, int(round(absf(v))), "" if short else " max"]
	var pct := "%s%d %%" % [sgn, int(round(absf(v) * 100.0))]
	return pct if short else pct + " " + String(_STAT_NAMES.get(stat, stat))

## Ce que change `it` par rapport à l'objet porté `worn` (vide : emplacement libre) :
## [[texte, couleur], ...] ; même stat : l'écart ; stat différente : ce qu'on gagne puis ce qu'on perd.
func _item_delta(it: Dictionary, worn: Dictionary) -> Array:
	var st := String(Data.item_template(String(it["id"]))["stat"])
	var v := Data.item_value(it)
	if worn.is_empty():
		return [[_stat_txt(st, v), UI.GOOD]]
	var ws := String(Data.item_template(String(worn["id"]))["stat"])
	var wv := Data.item_value(worn)
	if ws == st:
		var d := v - wv
		if _stat_txt(st, d, true) in ["+0 %", "−0 %", "+0 PV", "−0 PV"]:
			return [["Pareil", UI.SOFT]]
		return [[_stat_txt(st, d), UI.GOOD if d > 0.0 else UI.BAD]]
	return [[_stat_txt(st, v), UI.GOOD], [_stat_txt(ws, -wv), UI.BAD]]

## Comparaison à droite d'une ligne d'objet : « +5 % » en vert / « −3 % » en rouge (même stat), ou ce qu'on
## perdrait en rouge (« à la place de +12 % cadence ») quand la stat change.
func _delta_badge(it: Dictionary, worn: Dictionary) -> Control:
	var st := String(Data.item_template(String(it["id"]))["stat"])
	var ws := "" if worn.is_empty() else String(Data.item_template(String(worn["id"]))["stat"])
	var v := UI.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if worn.is_empty() or ws == st:
		var d := Data.item_value(it) - (0.0 if worn.is_empty() else Data.item_value(worn))
		var dl: Array = _item_delta(it, worn)[0]
		if String(dl[0]) == "Pareil":
			v.add_child(UI.label("pareil", 24, UI.SOFT, HORIZONTAL_ALIGNMENT_RIGHT))
		else:
			var l := UI.title(_stat_txt(st, d, true), 28, dl[1], UI.INK, HORIZONTAL_ALIGNMENT_RIGHT)
			l.add_theme_constant_override("shadow_offset_y", 0)
			v.add_child(l)
	else:
		v.add_child(UI.label("à la place de", UI.FS_SMALL, UI.SOFT, HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(UI.label(Data.item_stat_text(worn), 22, UI.BAD, HORIZONTAL_ALIGNMENT_RIGHT))
	return v

## Fiche d'un objet (toucher une ligne) : ce qu'il donne, ce que Jo porte, ce qui change ; ÉQUIPER ou RETIRER.
func _equip_detail(it: Dictionary, n: int, worn: Dictionary) -> void:
	if screen == null:
		return
	sfx.play("click", 1.0, -6.0)
	var tpl := Data.item_template(String(it["id"]))
	var slot := String(tpl["slot"])
	var rc: Color = Data.RARITY_COLORS[int(it["rarity"])]
	var is_worn := not worn.is_empty() and String(worn["uid"]) == String(it["uid"])
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(layer)
	var dim := UI.dim(0.78)
	layer.add_child(dim)
	dim.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			layer.queue_free())
	var p := UI.panel(UI.PANEL, rc.darkened(0.2), 22)
	p.custom_minimum_size = Vector2(660, 0)
	var c := UI.center(p)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(c)
	var v := UI.vbox(14)
	p.add_child(v)
	var top := UI.hbox(18)
	v.add_child(top)
	var ring := Panel.new()
	ring.custom_minimum_size = Vector2(96, 96)
	ring.add_theme_stylebox_override("panel", UI.flat(Color(rc, 0.18), rc, 48, 3))
	top.add_child(ring)
	var ic := UI.Icon.new(slot, rc, 60.0)
	ic.position = Vector2(18, 18)
	ring.add_child(ic)
	var tv := UI.vbox(4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(tv)
	var nm := UI.title(Data.item_label(it), 34, UI.TEXT, rc)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(nm)
	var tr := UI.hbox(10)
	tv.add_child(tr)
	tr.add_child(UI.tag(String(Data.RARITY_NAMES[int(it["rarity"])]).to_upper(), rc, UI.INK, 20))
	tr.add_child(UI.label(String(Data.SLOT_NAMES[slot]) + (("  ·  ×%d" % n) if n > 1 else ""), 24, UI.SOFT))
	var eff := UI.label("Effet : " + Data.item_stat_text(it), 30, rc.lightened(0.3))
	eff.add_theme_font_override("font", UI.TITLE)
	v.add_child(eff)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.flat(Color(UI.PANEL_DARK, 0.9), UI.LINE, 14, 2))
	v.add_child(box)
	var bv := UI.vbox(6)
	box.add_child(bv)
	if is_worn:
		bv.add_child(UI.label("Jo le porte en ce moment.", UI.FS_BODY, UI.TEXT))
		bv.add_child(UI.label("RETIRER libère l'emplacement.", UI.FS_BODY, UI.SOFT))
	else:
		if worn.is_empty():
			bv.add_child(UI.label("Emplacement libre : rien à perdre.", UI.FS_BODY, UI.TEXT))
		else:
			var wl := UI.label("Jo porte : %s (%s)" % [Data.item_label(worn), Data.item_stat_text(worn)], UI.FS_BODY, UI.SOFT)
			wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			bv.add_child(wl)
		bv.add_child(UI.label("Si tu l'équipes :", UI.FS_BODY, UI.TEXT))
		for dl in _item_delta(it, worn):
			var l := UI.label(String(dl[0]), 30, dl[1])
			l.add_theme_font_override("font", UI.TITLE)
			bv.add_child(l)
	var row := UI.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var go: Button
	if is_worn:
		go = UI.button("RETIRER", 28, UI.DANGER, 240)
		go.pressed.connect(func():
			Save.unequip(profile, slot)
			Save.save_profile(profile)
			_apply_profile_to_hero()
			sfx.play("click", 0.8, -4.0)
			show_loge())
	else:
		go = UI.primary("ÉQUIPER", 32, 260)
		go.pressed.connect(func():
			Save.equip(profile, String(it["uid"]))
			Save.save_profile(profile)
			_apply_profile_to_hero()
			sfx.play("pick", 1.0, -6.0)
			show_loge())
	go.custom_minimum_size.y = 80
	row.add_child(go)
	var close := UI.button("FERMER", 26, UI.MUTED, 200)
	close.custom_minimum_size.y = 80
	close.pressed.connect(func(): layer.queue_free())
	row.add_child(close)
	Fx.rise_in(p, 0.0, 0.22, 0.9)

## Arsenal : l'arbre des pouvoirs de partie, à lire (rien à composer). Cinq colonnes, une par branche, rangées
## par palier ; un onglet pour les évolutions et leurs recettes. Toucher un pouvoir l'explique en bas.
var _ars_tab := "branches"
var _ars_detail: Label = null

func show_arsenal() -> void:
	var fresh := state != "arsenal"
	_clear_screen(fresh)
	state = "arsenal"
	screen = _full(false)
	ui_layer.add_child(screen)
	screen.add_child(UI.dim(0.86))
	if fresh:
		Fx.screen_in(screen)
	var ins := UI.safe_insets(get_viewport())
	var col := UI.vbox(8)
	col.anchor_left = 0.0
	col.anchor_right = 1.0
	col.offset_left = float(ins["left"]) + 22.0
	col.offset_right = -float(ins["right"]) - 22.0
	col.anchor_top = 0.025
	col.anchor_bottom = 0.975
	screen.add_child(col)
	var head := UI.hbox(14)
	col.add_child(head)
	head.add_child(UI.title("ARSENAL", 40, UI.TEXT, UI.ORANGE))
	for tab in [["branches", "BRANCHES"], ["evo", "ÉVOLUTIONS"]]:
		var on: bool = _ars_tab == tab[0]
		var tb := UI.button(String(tab[1]), 20, UI.GOLD if tab[0] == "evo" else UI.ACCENT, 170)
		tb.custom_minimum_size = Vector2(170, 58)
		tb.modulate = Color(1, 1, 1, 1.0 if on else 0.55)
		var key: String = tab[0]
		tb.pressed.connect(func():
			_ars_tab = key
			sfx.play("click", 1.1, -6.0)
			show_arsenal())
		head.add_child(tb)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var back := UI.primary("RETOUR", 24)
	back.custom_minimum_size = Vector2(150, 64)
	back.pressed.connect(show_base)
	head.add_child(back)
	var ex := UI.label("Tous les pouvoirs peuvent sortir en partie. Palier II : après 2 choix dans la branche ; palier III : après 4. Deux pouvoirs au maximum ouvrent leur évolution.", 17, UI.MUTED)
	ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(ex)
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	if _ars_tab == "evo":
		_ars_evolutions(body)
	else:
		_ars_branches(body, fresh)
	var dp := PanelContainer.new()
	dp.add_theme_stylebox_override("panel", UI.flat(Color(UI.PANEL_DARK, 0.9), UI.LINE, 14, 2))
	dp.custom_minimum_size = Vector2(0, 64)
	col.add_child(dp)
	_ars_detail = UI.label("Touche un pouvoir pour le lire en entier.", 18, UI.TEXT)
	_ars_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ars_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dp.add_child(_ars_detail)

func _ars_branches(body: Control, fresh: bool) -> void:
	var row := UI.hbox(10)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_child(row)
	var k := 0
	for bid in Data.BRANCH_ORDER:
		var br := Data.branch(bid)
		var bc: Color = br["col"]
		var v := UI.vbox(3)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		var bh := UI.hbox(6)
		var bi := UI.Icon.new(String(br["icon"]), bc, 30.0)
		bh.add_child(bi)
		var bl := UI.title(String(br["name"]).to_upper(), 21, bc, bc)
		bl.add_theme_constant_override("shadow_offset_y", 0)
		bh.add_child(bl)
		v.add_child(bh)
		for tier in [1, 2, 3]:
			var tl := UI.label("PALIER %s%s" % [Data.roman(tier), "" if tier == 1 else "  ·  %d choix" % Data.TIER_NEED[tier]], 13, Color(bc, 0.75))
			tl.add_theme_font_override("font", UI.TITLE)
			v.add_child(tl)
			for p in Data.POWERS:
				if String(p["b"]) != bid or int(p["tier"]) != tier:
					continue
				var b := _ars_tile(p, bc)
				v.add_child(b)
		if fresh:
			Fx.rise_in(v, 0.05 + 0.05 * k, 0.3, 0.85)
		k += 1

func _ars_tile(p: Dictionary, bc: Color) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	var st := UI.flat(Color(UI.PANEL, 0.85), Color(bc, 0.35), 10, 1)
	b.add_theme_stylebox_override("normal", st)
	var hv := UI.flat(Color(UI.PANEL.lightened(0.08), 0.95), bc, 10, 2)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var hb := UI.hbox(6)
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 6
	hb.offset_right = -6
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var ic := UI.Icon.new(String(p["id"]), bc.lightened(0.15), 24.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ic)
	var nl := UI.label(String(p["name"]), 15, UI.TEXT)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.clip_text = true
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(nl)
	var ml := UI.label(Data.roman(int(p["max"])), 13, Color(bc, 0.8))
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ml)
	b.pressed.connect(func():
		sfx.play("click", 1.2, -8.0)
		var br := Data.branch(String(p["b"]))
		var txt := "%s  ·  %s, palier %s, jusqu'au niveau %s.  " % [String(p["name"]).to_upper(), String(br["name"]), Data.roman(int(p["tier"])), Data.roman(int(p["max"]))]
		if p.has("lv"):
			var parts := []
			var i := 1
			for t in p["lv"]:
				parts.append("%s : %s" % [Data.roman(i), String(t)])
				i += 1
			txt += "  ".join(parts)
		else:
			txt += String(p["desc"])
		for ev in Data.EVOLUTIONS:
			if String(p["id"]) in ev["need"]:
				txt += "  Évolution : " + String(ev["name"]) + "."
		if _ars_detail != null and is_instance_valid(_ars_detail):
			_ars_detail.text = txt)
	return b

## Tuile d'évolution : pictogramme doré, nom, recette, effet (deux lignes au plus).
func _ars_evo_tile(ev: Dictionary, recipe: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 84)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := UI.chunky(UI.PANEL.lightened(0.05), UI.GOLD.darkened(0.45), false, 16)
	st.border_width_left = 5
	st.border_color = UI.GOLD
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var hb := UI.hbox(12)
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 14
	hb.offset_right = -10
	hb.offset_top = 4
	hb.offset_bottom = -8
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var ic := UI.Icon.new(String(ev["icon"]), UI.GOLD, 40.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ic)
	var v := UI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(v)
	var n := UI.title(String(ev["name"]), 19, UI.TEXT, UI.GOLD)
	n.add_theme_constant_override("shadow_offset_y", 0)
	v.add_child(n)
	var r := UI.label(recipe, 15, UI.GOLD.lightened(0.15))
	r.add_theme_font_override("font", UI.TITLE)
	v.add_child(r)
	var d := UI.label(String(ev["desc"]), 15, UI.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.add_theme_constant_override("line_spacing", -4)
	v.add_child(d)
	for c in v.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

func _ars_evolutions(body: Control) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	var i := 0
	for ev in Data.EVOLUTIONS:
		var need: Array = ev["need"]
		var a := Data.power(String(need[0]))
		var b := Data.power(String(need[1]))
		var recipe := "%s %s  +  %s %s" % [String(a["name"]), Data.roman(int(a["max"])), String(b["name"]), Data.roman(int(b["max"]))]
		var t := _ars_evo_tile(ev, recipe)
		t.pressed.connect(func():
			if _ars_detail != null and is_instance_valid(_ars_detail):
				_ars_detail.text = "%s  ·  %s  ·  %s" % [String(ev["name"]).to_upper(), recipe, String(ev["desc"])])
		grid.add_child(t)
		Fx.rise_in(t, 0.04 + 0.03 * i, 0.3, 0.85)
		i += 1

# ---------------------------------------------------------------- partie
# ---------------------------------------------------------------- mondes
var _go_button: Button = null
var _world_title: Label = null
var _world_sub: Label = null

func _boss_title() -> String:
	return String(Data.ENEMIES[Data.boss_kind()]["name"]).to_upper()

## Monde ouvert : le premier, ou le suivant d'un monde terminé.
func _world_open(i: int) -> bool:
	return i == 0 or bool(Dev.v["all_worlds"]) or (profile["worlds_done"] as Array).has(i - 1)

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
	var prev := UI.button("◀", 24, UI.MUTED, 72)
	prev.custom_minimum_size = Vector2(72, 58)
	prev.pressed.connect(func(): _shift_world(-1))
	row.add_child(prev)
	_world_title = UI.label("", 26, UI.TEXT)
	_world_title.add_theme_font_override("font", UI.TITLE)
	_world_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_world_title)
	var nxt := UI.button("▶", 24, UI.MUTED, 72)
	nxt.custom_minimum_size = Vector2(72, 58)
	nxt.pressed.connect(func(): _shift_world(1))
	row.add_child(nxt)
	_world_sub = UI.label("", UI.FS_SMALL, UI.SOFT)
	_world_sub.clip_text = true
	_world_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	hero.profile = profile
	hero.reset_run()
	arena.reset_run()
	_pending_bonus = 0
	_rerolls = int(Data.talent(profile, "reroll"))
	# talent « départ » : un ou plusieurs pouvoirs du palier I au hasard
	var starts: Array = []
	for k in range(int(Data.talent(profile, "start_power"))):
		var firsts := _power_pool().filter(func(q): return int(q["tier"]) == 1)
		if firsts.is_empty():
			break
		var sp: Dictionary = firsts.pick_random()
		hero.add_power(String(sp["id"]))
		starts.append(String(sp["name"]).to_upper())
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
	hud.flash(Data.world_name().to_upper() if starts.is_empty() else "DÉPART : " + ", ".join(starts), 2.0, Data.WORLDS[Data.world]["accent"])
	sfx.play("portal")
	_start_run_ui()
	if duo != null:
		duo.on_run_started()

## Interface d'une nouvelle partie : compteurs remis à zéro, cartes « nouvel ennemi » vidées,
## tutoriel des deux pouces à la toute première partie (tant qu'il n'a pas été fait).
func _start_run_ui() -> void:
	run_items = []
	run_boxes = []
	hud.tickets = int(profile["tickets"])
	hud.hp = 1.0
	hud.energy = 0.0
	hud.snap()
	enemy_card.clear()
	if tutorial != null and is_instance_valid(tutorial):
		tutorial.queue_free()
	tutorial = null
	# premières parties : rappel de l'esquive, une fois les deux pouces en place
	if int(profile["runs"]) <= 3:
		var run_n := int(profile["runs"])
		get_tree().create_timer(9.0 if bool(profile.get("tutorial_done", false)) else 16.0, false).timeout.connect(func():
			if state == "arena" and int(profile["runs"]) == run_n:
				hud.flash("ESQUIVE : BOUTON » AU-DESSUS DU TIR", 2.4, UI.ACCENT))
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
	_maybe_more_choices.call_deferred()
	_flush_box_toast()

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

## Choix d'un pouvoir : barre d'énergie pleine, ou élite abattue (choix en prime, mis en attente si un autre écran
## est ouvert). Cartes tirées dans l'arbre (paliers ouverts selon les choix faits dans chaque branche) ; une
## évolution prête prend la carte du milieu. Talents du Relais : carte de plus, relances.
var _pending_bonus := 0
var _rerolls := 0

func _on_bonus_choice() -> void:
	_pending_bonus += 1
	_show_power_choice.call_deferred()

## Rouvre un choix en attente (élite, ou énergie encore pleine) dès que le jeu reprend.
func _maybe_more_choices() -> void:
	if state != "arena" or get_tree().paused or overlay != null or hero.dead:
		return
	if _pending_bonus > 0 or arena.energy >= arena.energy_need:
		_show_power_choice()

## Pouvoirs proposables : pas encore au maximum, palier ouvert dans leur branche.
func _power_pool() -> Array:
	var pool := []
	for p in Data.POWERS:
		if hero.lv(String(p["id"])) >= int(p["max"]):
			continue
		if hero.branch_count(String(p["b"])) < int(Data.TIER_NEED[int(p["tier"])]):
			continue
		pool.append(p)
	return pool

## Évolutions prêtes : les deux pouvoirs de la recette au maximum, pas encore prise.
func _evo_pool() -> Array:
	var out := []
	for ev in Data.EVOLUTIONS:
		if hero.has_evo(String(ev["id"])):
			continue
		var ok := true
		for id in ev["need"]:
			if hero.lv(String(id)) < int(Data.power(String(id))["max"]):
				ok = false
		if ok:
			out.append(ev)
	return out

## Tirage de `n` cartes différentes : un pouvoir déjà commencé ou d'un palier haut sort un peu plus souvent.
func _deal_powers(n: int) -> Array:
	var out := []
	var pool := _power_pool()
	var evos := _evo_pool()
	var with_evo := not evos.is_empty() and randf() < 0.75
	while out.size() < n - (1 if with_evo else 0) and not pool.is_empty():
		var total := 0.0
		for p in pool:
			total += _deal_weight(p)
		var r := randf() * total
		var pick: Dictionary = pool[pool.size() - 1]
		for p in pool:
			r -= _deal_weight(p)
			if r <= 0.0:
				pick = p
				break
		pool.erase(pick)
		out.append({"p": pick, "evo": false})
	if with_evo:
		out.insert(out.size() / 2, {"p": evos.pick_random(), "evo": true})
	return out

func _deal_weight(p: Dictionary) -> float:
	var w := 1.0
	if hero.lv(String(p["id"])) > 0:
		w += 0.7  # finir ce qu'on a commencé : les évolutions deviennent possibles
	if int(p["tier"]) >= 2:
		w += 0.3
	return w

func _show_power_choice() -> void:
	# duo : la partie ne se fige pas sous un écran, on n'en empile pas un second
	if get_tree().paused or state != "arena" or hero.dead or (duo != null and duo.in_run() and overlay != null):
		return
	var bonus := _pending_bonus > 0
	if not bonus and arena.energy < arena.energy_need:
		return
	var n := clampi(3 + int(Data.talent(profile, "extra_card")), 1, 5)
	var deal := _deal_powers(n)
	if deal.is_empty():
		if bonus:
			_pending_bonus -= 1
		else:
			arena.consume_energy()
		return
	_pause_for_overlay()
	sfx.play("level")
	_power_cards(deal, bonus, n)

func _power_cards(deal: Array, bonus: bool, n: int) -> void:
	var vs := get_viewport().get_visible_rect().size
	var has_evo := false
	for d in deal:
		if d["evo"]:
			has_evo = true
	var title := "ÉLITE ABATTUE" if bonus else "ÉNERGIE PLEINE"
	var sub := "Pouvoir en prime" if bonus else "Choisis un pouvoir pour cette partie"
	if has_evo:
		sub = "Une évolution est prête !"
	var head := _deal_overlay(title, sub, UI.GOLD if (bonus or has_evo) else UI.ACCENT)
	var gap := 30.0 if deal.size() <= 3 else 18.0
	var cs := Vector2(264, 356)
	if vs.y < 700.0:
		cs = Vector2(240, 324)
	var room_w := (vs.x - 70.0 - gap * (deal.size() - 1)) / deal.size()
	if room_w < cs.x:
		cs = cs * (room_w / cs.x)
	var cy := head + (vs.y - head) * 0.5 - (22.0 if _rerolls > 0 else 6.0)
	var cards: Array = []
	for i in range(deal.size()):
		var entry: Dictionary = deal[i]
		var p: Dictionary = entry["p"]
		var is_evo: bool = entry["evo"]
		var id := String(p["id"])
		var level: int = 1 if is_evo else hero.lv(id) + 1
		var sz := cs * (1.07 if is_evo else 1.0)
		var b: Button = CardScript.new()
		b.setup_power(p, level, is_evo, sz)
		overlay.add_child(b)
		cards.append(b)
		# éventail : les cartes du bord descendent un peu et penchent vers l'extérieur
		var k := i - (deal.size() - 1) * 0.5
		var to := Vector2(vs.x * 0.5 + k * (cs.x + gap) - sz.x * 0.5, cy - sz.y * 0.5 + absf(k) * 18.0)
		b.deal(Vector2(vs.x * 0.5 - sz.x * 0.5, vs.y + 60.0), to, k * 0.075, 0.12 + 0.09 * i)
		b.reveal(0.62 + 0.16 * i)
		b.pressed.connect(func():
			var ov := overlay
			for o in cards:
				(o as Button).disabled = true
			hero.add_power(id)
			if bonus:
				_pending_bonus = maxi(0, _pending_bonus - 1)
			else:
				arena.consume_energy()
			arena.sync_machines()
			sfx.play("chest", 1.1 if not is_evo else 0.8, -4.0)
			b.pick(Vector2(vs.x * 0.5, cy))
			for o in cards:
				if o != b:
					(o as Button).discard(signf((o as Button).position.x - b.position.x))
			var tw := ov.create_tween()
			tw.tween_interval(0.42)
			tw.tween_callback(func():
				if overlay == ov:
					var label := String(p["name"]).to_upper()
					if not is_evo and int(p["max"]) > 1:
						label += " " + Data.roman(level)
					hud.flash(label, 1.6 if is_evo else 1.4, Data.EVO_COL if is_evo else Data.branch(String(p["b"]))["col"])
					_resume()
					view.power_fx()
					if is_evo:
						arena.power_event.emit("evolve", {"pos": hero.position})))
	if _rerolls > 0:
		var rr := UI.button("RELANCER  ·  %d" % _rerolls, 22, UI.GOLD, 260)
		rr.custom_minimum_size = Vector2(260, 60)
		rr.position = Vector2(vs.x * 0.5 - 130.0, minf(vs.y - 72.0, cy + cs.y * 0.5 + 34.0))
		rr.pressed.connect(func():
			_rerolls -= 1
			sfx.play("click", 0.9, -4.0)
			_power_cards(_deal_powers(n), bonus, n))
		overlay.add_child(rr)
		Fx.rise_in(rr, 0.9, 0.3, 0.6)

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
	mu.custom_minimum_size = Vector2(400, 72)
	mu.pressed.connect(func():
		Music.set_enabled(not Music.enabled)
		mu.text = "MUSIQUE : " + ("OUI" if Music.enabled else "NON"))
	box.add_child(mu)
	# qualité : ÉCO chauffe moins (3D plus basse, sans ombres, 30 i/s), MAX pour les téléphones costauds
	var qb := UI.button("QUALITÉ : " + String(Dev.quality()[0]), 24, UI.ACCENT, 400)
	qb.custom_minimum_size = Vector2(400, 72)
	qb.pressed.connect(func():
		Dev.set_value("quality", (int(Dev.v["quality"]) + 1) % Dev.QUALITY.size())
		qb.text = "QUALITÉ : " + String(Dev.quality()[0]))
	box.add_child(qb)
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
	var aw := UI.button("TOUS LES MONDES OUVERTS : " + ("OUI" if bool(Dev.v["all_worlds"]) else "NON"), 20, UI.ACCENT if bool(Dev.v["all_worlds"]) else UI.MUTED, 420)
	aw.custom_minimum_size = Vector2(420, 64)
	aw.pressed.connect(func():
		Dev.set_value("all_worlds", not bool(Dev.v["all_worlds"]))
		_show_dev())
	box.add_child(aw)
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
	_show_end(false, "RAPPEL AU RELAIS", "Tes objets et tickets restent. Les pouvoirs de la partie partent.")

func _victory() -> void:
	_pause_for_overlay()
	var done: Array = profile["worlds_done"]
	var first := not done.has(Data.world)
	for b in Loot.boss_boxes(first):
		_gain_box(b)
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
		"items": run_items, "boxes": run_boxes, "shard": won, "record": arena.room > int(profile["best_room"]) and int(profile["runs"]) > 1,
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

# ---------------------------------------------------------------- box de butin (scripts/loot.gd)
var run_boxes: Array = []  # box gagnées pendant la partie (écran de fin)
var _box_toast := ""
var _shot_i := 0

## Gains : élite (petite chance de Bronze), coffre de la route Trésor (Argent), boss (_victory : Or, et
## Légendaire à la première victoire du monde). Apparence de Jo et traînée de tir appliquées.
func _hook_boxes() -> void:
	Loot.apply_skin(profile)
	arena.elite_killed.connect(func(_e):
		if state == "arena" and randf() < Loot.ELITE_BOX_CHANCE:
			_gain_box("bronze")
			hud.flash("COFFRE BRONZE !", 1.3, Loot.BOX_COLORS["bronze"]))
	arena.chest_opened.connect(func(_p):
		if state == "arena" and arena.modifier == "tresor":
			_gain_box("argent")
			_box_toast = "argent")
	arena.fired.connect(_tint_shot)

func _gain_box(b: String) -> void:
	Loot.add_box(profile, b)
	run_boxes.append(b)
	Save.save_profile(profile)
	sfx.play("chest", 1.25, -4.0)

## Bandeau « COFFRE ARGENT ! » après l'objet du coffre (l'overlay l'aurait caché).
func _flush_box_toast() -> void:
	if _box_toast != "" and state == "arena":
		hud.flash("COFFRE %s !" % String(Loot.BOX_NAMES[_box_toast]).to_upper(), 1.4, Loot.BOX_COLORS[_box_toast])
	_box_toast = ""

## Traînée de tir équipée : recolore le tir de Jo qui vient de partir (les tirs critiques gardent leur jaune).
func _tint_shot(_pos: Vector2, _vel: Vector2, hero_shot: bool, color: Color, _r: float) -> void:
	var tid := String(profile["trail"])
	if not hero_shot or color != HeroScript.VISOR or tid == Loot.DEFAULT_TRAIL or arena.bullets.is_empty():
		return
	_shot_i += 1
	arena.bullets.back().color = Loot.trail_color(tid, _shot_i)

## Relais : COFFRES (nombre à ouvrir, halo qui pulse) et APPARENCES (combien sont obtenues).
func _boxes_row() -> HBoxContainer:
	var row := UI.hbox(12)
	var n: int = (profile["boxes"] as Array).size()
	var cb := _side_button("COFFRES", "chest", UI.GOLD, ("%d à ouvrir" % n) if n > 0 else "Aucun à ouvrir", n > 0)
	cb.pressed.connect(func(): show_coffres("coffres"))
	row.add_child(cb)
	# pictogramme : la plus belle box en attente, qui se trémousse de temps en temps
	for ic in cb.get_children():
		if ic is UI.Icon:
			ic.visible = false
	var best := "or"
	for r in Loot.BOXES:
		if Loot.count(profile, r) > 0:
			best = r
	var glyph := Control.new()
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.anchor_top = 0.5
	glyph.anchor_bottom = 0.5
	glyph.offset_left = 12
	glyph.offset_top = -22
	glyph.size = Vector2(44, 44)
	var gt := {"t": 0.0}
	glyph.draw.connect(func():
		var k := fmod(float(gt["t"]), 2.2)
		var wob := sin(k * 26.0) * 0.16 * maxf(0.0, 1.0 - k / 0.5) if n > 0 else 0.0
		glyph.draw_set_transform(Vector2(22, 24), wob, Vector2.ONE)
		BoxArt.draw_box(glyph, Vector2.ZERO, 40.0, best, n == 0))
	cb.add_child(glyph)
	# la box ne bouge que pendant la première demi-seconde du cycle : redessinée seulement à ce moment-là
	# (plus une fois au repos) ; sans box en attente, elle ne bouge jamais
	if n > 0:
		var tw_g := glyph.create_tween().set_loops()
		tw_g.tween_method(func(v: float):
			var rest := v >= 0.5
			if not (rest and bool(gt.get("rest", false))):
				gt["t"] = v
				glyph.queue_redraw()
			gt["rest"] = rest, 0.0, 2.2, 2.2)
	if n > 0:
		var h := Fx.halo(Color(UI.GOLD, 0.45), Vector2(10, 10))
		h.show_behind_parent = true
		cb.add_child(h)
		cb.resized.connect(func():
			h.size = cb.size * Vector2(1.25, 2.2)
			h.position = (cb.size - h.size) * 0.5)
		Fx.pulse(h, 0.35, 1.0, 1.1)
	var col := _side_button("APPARENCES", "shard", UI.ACCENT, "%d sur %d obtenues" % [Loot.owned_count(profile), Loot.total_count()])
	col.pressed.connect(func(): show_coffres("collection"))
	row.add_child(col)
	Fx.rise_in(row, 0.5)
	return row

func show_coffres(tab: String = "coffres") -> void:
	var fresh := state != "coffres"
	_clear_screen(fresh)
	state = "coffres"
	screen = BoxesScreen.new()
	ui_layer.add_child(screen)
	screen.build(self, tab, fresh)
	view.relais_focus = 1.0

## Après une ouverture ou un changement d'apparence : Jo et l'équipement suivent le profil.
func on_boxes_changed() -> void:
	Loot.apply_skin(profile)
	_apply_profile_to_hero()
