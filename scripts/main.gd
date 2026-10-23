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
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	arena.energy_full.connect(_show_power_choice)
	arena.room_cleared.connect(_on_room_cleared)
	arena.item_found.connect(_show_item)
	arena.hero_died.connect(_on_hero_died)
	arena.wave_changed.connect(func():
		if arena.room >= Data.ROOMS:
			hud.flash("LE PORTIQUE", 2.2, UI.DANGER)
		else:
			hud.flash("VAGUE %d" % (arena.wave_i + 1), 1.3, UI.ACCENT))
	_apply_profile_to_hero()
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
func _clear_screen() -> void:
	if screen != null:
		screen.queue_free()
		screen = null
	if preview_hero != null:
		preview_hero.queue_free()
		preview_hero = null

func _clear_overlay() -> void:
	if overlay != null:
		overlay.queue_free()
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
	view.set_shards(int(profile["shards"]))
	hud.visible = false
	joy.enabled = false
	screen = _full(false)
	ui_layer.add_child(screen)
	screen.add_child(_side_shade(0.42))
	var right := UI.vbox(16)
	right.anchor_left = 0.53
	right.anchor_right = 0.96
	right.anchor_top = 0.07
	right.anchor_bottom = 0.95
	screen.add_child(right)
	right.add_child(UI.title("PASSEURS", 86, UI.TEXT, UI.ACCENT))
	right.add_child(UI.label("LE RELAIS  ·  MONDE 1 : " + Data.WORLD_NAME.to_upper(), 22, UI.MUTED))
	var chips := UI.hbox(10)
	right.add_child(chips)
	chips.add_child(UI.chip("portal", "%d / 10 éclats" % int(profile["shards"]), UI.ACCENT))
	chips.add_child(UI.chip("coin", str(int(profile["tickets"])), UI.GOLD))
	chips.add_child(UI.chip("skull", "salle %d" % int(profile["best_room"]), UI.DANGER))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 10)
	right.add_child(sp)
	var go := UI.primary("PARTIR", 40)
	go.custom_minimum_size = Vector2(0, 86)
	go.pressed.connect(_depart)
	right.add_child(go)
	var row := UI.hbox(12)
	right.add_child(row)
	var loge := UI.button("LOGE", 26, UI.ACCENT)
	loge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loge.custom_minimum_size = Vector2(0, 64)
	loge.pressed.connect(show_loge)
	row.add_child(loge)
	var ars := UI.button("ARSENAL", 26, UI.ORANGE)
	ars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ars.custom_minimum_size = Vector2(0, 64)
	ars.pressed.connect(show_arsenal)
	row.add_child(ars)
	var equipped := Save.equipped_items(profile)
	var eq_txt := "Rien d'équipé. Les objets trouvés en partie restent à toi."
	if not equipped.is_empty():
		var names := []
		for it in equipped:
			names.append(Data.item_label(it))
		eq_txt = "Équipé : " + ", ".join(names)
	var eq := UI.label(eq_txt, 18, UI.MUTED)
	eq.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(eq)
	var ver := UI.label("V0 · " + version, 14, UI.LINE)
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_top = -30
	ver.offset_left = 16
	screen.add_child(ver)
	UI.pop_in(go, 0.1)

func show_loge() -> void:
	_clear_screen()
	state = "loge"
	screen = _full(false)
	ui_layer.add_child(screen)
	screen.add_child(_side_shade(0.22))
	view.relais_focus = 1.0
	var left := UI.vbox(8)
	left.anchor_left = 0.33
	left.anchor_right = 0.62
	left.anchor_top = 0.05
	left.anchor_bottom = 0.96
	screen.add_child(left)
	var head := UI.hbox(14)
	left.add_child(head)
	head.add_child(UI.title("LOGE", 44, UI.TEXT, UI.ACCENT))
	var back := UI.primary("RETOUR", 22)
	back.pressed.connect(show_base)
	head.add_child(back)
	left.add_child(UI.label("Touche un emplacement pour le vider.", 17, UI.MUTED))
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
	_clear_screen()
	state = "arsenal"
	screen = _full(false)
	ui_layer.add_child(screen)
	screen.add_child(UI.dim(0.8))
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
	var back := UI.primary("RETOUR", 22)
	back.pressed.connect(show_base)
	head.add_child(back)
	col.add_child(UI.label("Les pouvoirs allumés peuvent t'être proposés quand ta barre d'énergie est pleine. Trois sont tirés à chaque fois.", 18, UI.MUTED))
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

# ---------------------------------------------------------------- partie
## PARTIR : l'interface s'efface, Jo court dans le portail, puis la partie commence.
func _depart() -> void:
	if state != "base":
		return
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
	hud.world = Data.WORLD_NAME
	joy.enabled = true
	joy.reset()
	arena.start_room(1, "combat")
	view.start_room()
	hud.fade = 1.0
	hud.flash(Data.WORLD_NAME.to_upper(), 2.0, UI.ACCENT)
	sfx.play("portal")

func _pause_for_overlay() -> void:
	hud.flash("", 0.0)
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
	if get_tree().paused:
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
	var box := _card_overlay("ÉNERGIE PLEINE", "Choisis un pouvoir pour cette partie")
	var row := UI.hbox(22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	for i in range(mini(3, pool.size())):
		var p: Dictionary = pool[i]
		var have: int = hero.power_count(String(p["id"]))
		var b := UI.card(String(p["id"]), String(p["name"]), String(p["desc"]), UI.ACCENT, Vector2(250, 300), ("NIV. %d" % (have + 1)) if have > 0 else "")
		UI.pop_in(b, 0.06 * i)
		b.pressed.connect(func():
			hero.add_power(String(p["id"]))
			arena.consume_energy()
			if String(p["id"]) == "turret":
				arena.turrets.append({"pos": hero.position + Vector2.RIGHT.rotated(randf() * TAU) * 100.0, "cd": 0.0, "ang": 0.0})
			if String(p["id"]) == "ally":
				arena.allies.append({"ang": randf() * TAU, "cd": 0.0})
			hud.flash(String(p["name"]).to_upper(), 1.4, UI.ORANGE)
			_resume()
			view.power_fx())
		row.add_child(b)

func _show_item(item: Dictionary) -> void:
	_pause_for_overlay()
	profile["inventory"].append(item)
	Save.save_profile(profile)
	var tpl := Data.item_template(String(item["id"]))
	var rarity := int(item["rarity"])
	var box := _card_overlay("OBJET TROUVÉ", Data.RARITY_NAMES[rarity].to_upper())
	var rc: Color = Data.RARITY_COLORS[rarity]
	var c := UI.card(String(tpl["slot"]), Data.item_label(item), Data.SLOT_NAMES[tpl["slot"]] + "\n" + Data.item_stat_text(item), rc, Vector2(330, 300))
	c.disabled = false
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cc := CenterContainer.new()
	cc.add_child(c)
	box.add_child(cc)
	UI.pop_in(c)
	var cur_uid := String(profile["equipped"].get(tpl["slot"], ""))
	var cur := Save.find_item(profile, cur_uid) if cur_uid != "" else {}
	if not cur.is_empty():
		box.add_child(UI.label("Équipé actuellement : " + Data.item_label(cur) + " (" + Data.item_stat_text(cur) + ")", 19, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var row := UI.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var eq := UI.primary("ÉQUIPER", 24)
	eq.pressed.connect(func():
		Save.equip(profile, String(item["uid"]))
		Save.save_profile(profile)
		_apply_profile_to_hero()
		_after_item())
	row.add_child(eq)
	var keep := UI.button("GARDER", 24, UI.MUTED)
	keep.pressed.connect(_after_item)
	row.add_child(keep)

func _after_item() -> void:
	_resume()
	if arena.cleared and not arena.chest.is_empty() and arena.chest["open"]:
		if arena.room >= Data.ROOMS:
			_victory()
		else:
			_show_doors()

func _on_room_cleared() -> void:
	hud.flash("SALLE %d TERMINÉE" % arena.room, 2.2, UI.GOLD)

func _show_doors() -> void:
	_pause_for_overlay()
	var next: int = arena.room + 1
	var box := _card_overlay("TROIS PORTAILS", "Salle %d · choisis ta route" % next)
	var row := UI.hbox(22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var doors := [
		["COMBAT", "Vagues normales, coffre normal.", "combat", UI.ACCENT, "portal"],
		["ÉLITE", "Une élite dorée en fin de salle. Meilleur coffre.", "elite", UI.DANGER, "skull"],
		["TRÉSOR", "Moins d'ennemis, meilleur coffre, moins d'énergie.", "tresor", UI.GOLD, "chest"],
	]
	if next >= Data.ROOMS:
		doors = [["LE PORTIQUE", "Le gardien de l'éclat du Cœur.", "combat", UI.DANGER, "skull"]]
	var i := 0
	for d in doors:
		var b := UI.card(String(d[4]), String(d[0]), String(d[1]), d[3], Vector2(250, 300))
		UI.pop_in(b, 0.06 * i)
		i += 1
		b.pressed.connect(func():
			_resume()
			arena.start_room(next, String(d[2]))
			view.start_room()
			hud.fade = 1.0
			hud.flash(("SALLE %d" % next) if next < Data.ROOMS else "LE PORTIQUE", 1.8, UI.DANGER if next >= Data.ROOMS else UI.TEXT)
			sfx.play("portal"))
		row.add_child(b)

func _show_pause() -> void:
	if state != "arena" or get_tree().paused:
		return
	_pause_for_overlay()
	var box := _card_overlay("PAUSE", "Salle %d · %d ennemis tués" % [arena.room, arena.kills])
	var r := UI.primary("REPRENDRE", 30, 360)
	r.pressed.connect(_resume)
	box.add_child(r)
	var q := UI.button("ABANDONNER  ·  le butin reste", 22, UI.MUTED, 360)
	q.pressed.connect(func(): _end_run(false))
	box.add_child(q)

func _on_hero_died() -> void:
	if get_tree().paused:
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
	var box := _card_overlay("RAPPEL AU RELAIS", "Salle %d  ·  %d ennemis  ·  %d tickets\nLe butin reste, les pouvoirs partent." % [arena.room, arena.kills, arena.tickets])
	var b := UI.primary("RETOUR AU RELAIS", 30, 400)
	b.pressed.connect(func(): _end_run(false))
	box.add_child(b)

func _victory() -> void:
	_pause_for_overlay()
	profile["shards"] = int(profile["shards"]) + 1
	var box := _card_overlay("ÉCLAT DU CŒUR RÉCUPÉRÉ", "Le Relais se rallume.  %d ennemis  ·  %d tickets" % [arena.kills, arena.tickets])
	var b := UI.primary("RETOUR AU RELAIS", 30, 400)
	b.pressed.connect(func(): _end_run(true))
	box.add_child(b)

func _end_run(_won: bool) -> void:
	profile["tickets"] = int(profile["tickets"]) + arena.tickets
	profile["kills"] = int(profile["kills"]) + arena.kills
	profile["best_room"] = maxi(int(profile["best_room"]), arena.room)
	Save.save_profile(profile)
	arena.stop()
	view.stop()
	show_base()
