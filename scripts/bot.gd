extends Node
## Robot testeur (--autoplay) : lance une partie depuis le Relais, bouge en fuyant l'ennemi le plus proche
## (et va le chercher quand plus rien n'est à portée), esquive d'une ruée les tirs et les contacts de temps en
## temps, va chercher le coffre, clique sur un bouton de chaque écran. Sert au CI à détecter les erreurs de script
## et à mesurer l'équilibrage (« BOT : fin de partie, salle N »).
## `--powers=id,id:2,…` donne des pouvoirs dès le début (captures en partie dense) ; `--allpowers` les donne tous.

var main: Node
var t := 0.0
var think := 0.0
var dir := Vector2.RIGHT
var click_t := 0.0

var _room_jump_done := false
var _dash_t := 0.0  # délai entre deux ruées du robot
var _look_t := 0.0
var _orbit := 1.0
var _dash_tested := false
var _dash_reported := false
var _dash_before := 0.0
var _stall_sig := ""
var _stall_n := 0
var _proc_sum := 0.0  # temps de traitement par image (mesure de performance)
var _proc_n := 0.0
var _proc_max := 0.0
var _chest_done := false
var _door_pick := randi() % 3
var touch_test := false  # --touchtest : simule de vrais doigts sur les sticks au lieu de piloter le joystick
var _touch_t := 0.0
var _touch_started := false
var _start_pos := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	touch_test = "--touchtest" in OS.get_cmdline_user_args()
	main.joy.bot = not touch_test
	_give_loot()
	print("BOT : démarrage" + (" (test tactile)" if touch_test else ""))
	_test_profile()

## Options d'essai : --winsize=LxH (fenêtre, pour filmer en 16:9 ou 20:9), --tickets=N (tickets donnés),
## --talents=half|full (talents déjà achetés ; full donne aussi les deux éclats).
func _test_profile() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--winsize="):
			var wh := a.trim_prefix("--winsize=").split("x")
			get_window().size = Vector2i(int(wh[0]), int(wh[1]))
		elif a.begins_with("--tickets="):
			main.profile["tickets"] = int(a.trim_prefix("--tickets="))
		elif a.begins_with("--talents="):
			var Talents = load("res://scripts/talents.gd")
			var mode := a.trim_prefix("--talents=")
			var lv := {}
			if mode == "full":
				main.profile["worlds_done"] = [0, 1]
				main.profile["shards"] = 2
			for t in Talents.TALENTS:
				var mx := int(t["max"])
				if mode == "full":
					lv[t["id"]] = mx
				elif mode == "half" and float(t["pos"].y) <= 3.0 and String(t["branch"]) != "fortune":
					lv[t["id"]] = mini(mx, int(ceil(mx * 0.5)) + (1 if float(t["pos"].y) <= 1.0 else 0))
			if mode == "half":
				lv["butin"] = 3
				lv["aimant"] = 1
				lv["chance"] = 1
			main.profile["talents"] = lv
		elif a.begins_with("--items="):
			_give_items(a.trim_prefix("--items="))
	main._apply_profile_to_hero()

## --items=id,id:rareté,... (captures) : donne et équipe ces objets (rareté 2 par défaut ; un par emplacement, le
## dernier l'emporte). Marche en partie comme sur les écrans (avec --stuff, --stuff passe après).
func _give_items(spec: String) -> void:
	var Save = load("res://scripts/save.gd")
	for tok in spec.split(","):
		var id := tok.get_slice(":", 0)
		var r := int(tok.get_slice(":", 1)) if ":" in tok else 2
		var it := {"id": id, "rarity": clampi(r, 0, 3), "uid": "cap_" + id}
		if Save.find_item(main.profile, it["uid"]).is_empty():
			main.profile["inventory"].append(it)
		Save.equip(main.profile, it["uid"])

## Les événements injectés sont en coordonnées de fenêtre ; le moteur les ramène dans le viewport 1280×720.
func _win(pos: Vector2) -> Vector2:
	var w := Vector2(get_window().size)
	var vp := get_viewport().get_visible_rect().size
	return pos * (w / vp)

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = _win(pos)
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _drag(index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = _win(pos)
	Input.parse_input_event(ev)

var _screen_done := false

## Options de capture : --screen=loge|arsenal|talents ouvre l'écran et ne touche à rien ; --stuff équipe des objets d'essai ;
## --detail (avec loge) ouvre la fiche de l'objet porté.
func _capture_screen() -> bool:
	var mode := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screen="):
			mode = a.trim_prefix("--screen=")
	if mode == "":
		return false
	if not _screen_done:
		_screen_done = true
		if "--stuff" in OS.get_cmdline_user_args():
			_give_stuff()
		match mode:
			"loge":
				main.show_loge()
				# --detail : fiche de l'objet porté dans l'emplacement affiché (arme)
				if "--detail" in OS.get_cmdline_user_args():
					var worn: Dictionary = load("res://scripts/save.gd").find_item(main.profile, String(main.profile["equipped"].get(main._equip_slot, "")))
					if not worn.is_empty():
						main._equip_detail(worn, 1, worn)
			"coffres", "collection":
				main.show_coffres(mode)
			"arsenal":
				if "--tab=evo" in OS.get_cmdline_user_args():
					main._ars_tab = "evo"
				main.show_arsenal()
			"talents":
				main.show_talents()
			"cards":
				_card_board()
			"power", "item", "victory", "defeat", "enemy", "tuto", "pause", "hud", "dev":
				# écrans de partie : on entre directement dans l'arène, Jo reste immobile
				main.start_run()
				_give_powers()
				if mode == "tuto":
					main.joy.bot = false  # sticks dessinés, aucun doigt
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--room="):
						main.arena.start_room(int(a.trim_prefix("--room=")), "combat")
						main.view.start_room()
			_:
				main.show_base()
	_capture_events(mode)
	return true

## Écrans de partie à filmer : l'overlay s'ouvre à 1 s ; `--clickat=S` touche la première carte à S secondes.
var _shot_done := false
var _click_done := false
var _buys := 0
var _drag_step := -1
func _capture_events(mode: String) -> void:
	if mode == "talents":
		_capture_talents()
		return
	if not _shot_done and t > 1.0:
		_shot_done = true
		match mode:
			"power":
				main.arena.energy = main.arena.energy_need
				main._show_power_choice()
			"item":
				var r := 2
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--rarity="):
						r = int(a.trim_prefix("--rarity="))
				main._show_item({"id": "fusil_impulsion", "rarity": r, "uid": "test_capture"})
			"victory", "defeat":
				main.arena.room = 10 if mode == "victory" else 6
				main.arena.kills = 214 if mode == "victory" else 96
				main.arena.tickets = 388 if mode == "victory" else 141
				main.run_items = [{"id": "plastron", "rarity": 1}, {"id": "bottes", "rarity": 0}, {"id": "pile", "rarity": 2}, {"id": "visiere", "rarity": 3}]
				if mode == "victory":
					main._victory()
				else:
					main._pause_for_overlay()
					main._show_end(false, "RAPPEL AU RELAIS", "Le butin reste, les pouvoirs partent.")
			"pause":
				main._show_pause()
			"coffres":
				# --open=or[,legendaire...] ouvre ces box (--serial : à la suite, comme TOUT OUVRIR)
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--open="):
						main.screen.open(Array(a.trim_prefix("--open=").split(",")), "--serial" in OS.get_cmdline_user_args())
			"dev":
				main._show_pause()
				main._show_dev()
			"hud":
				# HUD sous tension : énergie presque pleine, coup reçu, tickets qui tombent
				main.arena.energy = main.arena.energy_need * 0.93
				main.arena.tickets += 37
				main.hero.hp = main.hero.hp_max * 0.55
				main.hud.hurt = 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clickat=") and not _click_done and t > float(a.trim_prefix("--clickat=")):
			_click_done = true
			if main.overlay != null:
				for b in main.overlay.find_children("*", "Button", true, false):
					if not b.disabled:
						b.pressed.emit()
						break

## Écran Talents : --select=ID ouvre la fiche à 1 s, --buy=N achète N niveaux (un toutes les 0,9 s dès 1,6 s),
## --dragtest glisse au doigt sur l'arbre (vrais événements tactiles) et affiche le déplacement.
func _capture_talents() -> void:
	var sc: Control = main.screen
	if sc == null or not sc.has_method("select"):
		return
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--select=") and not _shot_done and t > 1.0:
			_shot_done = true
			sc.select(a.trim_prefix("--select="))
		elif a.begins_with("--buy=") and _buys < int(a.trim_prefix("--buy=")) and t > 1.6 + 0.9 * _buys:
			_buys += 1
			sc.buy_selected()
	if "--dragtest" in args:
		var step := int((t - 1.0) / 0.1)
		if t > 1.0 and step != _drag_step and step <= 8:
			_drag_step = step
			var p := Vector2(760, 420) + Vector2(-260, -60) * (step / 7.0)
			if step == 0:
				set_meta("pan0", sc.get("_pan"))
				_touch(0, p, true)
			elif step < 8:
				_drag(0, p)
			else:
				_touch(0, p, false)
				print("TALENTS : glisser ok=%s (défilement %s)" % [str((sc.get("_pan") - get_meta("pan0")).length() > 100.0), str(sc.get("_pan") - get_meta("pan0"))])
## Options de capture des box : --boxes=N (N box de test, raretés en alternance) ou --boxes=or,legendaire ;
## --skin=<id> et --trail=<id> donnent et équipent un cosmétique (scripts/loot.gd) ;
## --tapevery=S touche l'écran d'ouverture toutes les S secondes (après --open).
func _give_loot() -> void:
	var Loot = load("res://scripts/loot.gd")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--boxes="):
			var v := a.trim_prefix("--boxes=")
			if v.is_valid_int():
				for i in range(int(v)):
					Loot.add_box(main.profile, Loot.BOXES[(Loot.BOXES.size() - 1 - i % Loot.BOXES.size())])
			else:
				for b in v.split(","):
					if b in Loot.BOXES:
						Loot.add_box(main.profile, b)
		for k in ["skin", "trail"]:
			if a.begins_with("--%s=" % k):
				var id := a.trim_prefix("--%s=" % k)
				if not (main.profile[k + "s"] as Array).has(id):
					main.profile[k + "s"].append(id)
				main.profile[k] = id
	main.on_boxes_changed()

var _tap_t := 0.0
func _tap_opener(dt: float) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tapevery=") and main.screen != null and main.screen.get("opener") != null:
			_tap_t += dt
			if _tap_t >= float(a.trim_prefix("--tapevery=")):
				_tap_t = 0.0
				main.screen.opener.tap()

## --screen=cards --page=N : planche des cartes de pouvoir (24 par page, faces visibles), évolutions en dernier.
func _card_board() -> void:
	var Data = load("res://scripts/data.gd")
	var CardScript = load("res://scripts/ui/card.gd")
	var page := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--page="):
			page = int(a.trim_prefix("--page="))
	var all := []
	for bid in Data.BRANCH_ORDER:
		for p in Data.POWERS:
			if String(p["b"]) == bid:
				all.append([p, false])
	for ev in Data.EVOLUTIONS:
		all.append([ev, true])
	var root := ColorRect.new()
	root.color = Color("#0E1B33")
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.ui_layer.add_child(root)
	var cs := Vector2(264, 356)
	var k := 0.5
	for i in range(24):
		var idx := page * 24 + i
		if idx >= all.size():
			break
		var entry: Array = all[idx]
		var c: Button = CardScript.new()
		var p: Dictionary = entry[0]
		c.setup_power(p, 1 if entry[1] else mini(2, int(p["max"])), entry[1], cs)
		c.show_face()
		c.scale = Vector2(k, k)
		c.pivot_offset = Vector2.ZERO
		c.position = Vector2(14 + (i % 8) * (cs.x * k + 25), 14 + (i / 8) * (cs.y * k + 46))
		root.add_child(c)

func _give_stuff() -> void:
	var Data = load("res://scripts/data.gd")
	var Save = load("res://scripts/save.gd")
	var picks := [["casque_garde", 2], ["plastron", 1], ["bottes", 3], ["pile", 1], ["fusil_impulsion", 2], ["module_canon", 0], ["visiere", 0], ["aimant", 1]]
	for pr in picks:
		var it := {"id": pr[0], "rarity": pr[1], "uid": "test_" + String(pr[0])}
		if Save.find_item(main.profile, it["uid"]).is_empty():
			main.profile["inventory"].append(it)
	for pr in picks.slice(0, 6):
		Save.equip(main.profile, "test_" + String(pr[0]))
	main._apply_profile_to_hero()

func _process(dt: float) -> void:
	t += dt
	if _capture_screen():
		_tap_opener(dt)
		return
	if (main.state == "duo" or main.state == "depart") and main.overlay == null:
		return  # salon duo : la session (scripts/net/duo.gd) se connecte et lance d'elle-même
	if main.overlay != null or main.screen != null:
		click_t += dt
		if click_t > 0.6:
			click_t = 0.0
			_click_something()
		return
	click_t = 0.0
	if main.state != "arena":
		return
	var arena: Node = main.arena
	var hero: Node2D = main.hero
	# options de capture : --room=N démarre à la salle N, --god rend Jo invulnérable
	if not _room_jump_done:
		_room_jump_done = true
		_give_powers()
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--room="):
				var n := int(a.trim_prefix("--room="))
				arena.start_room(n, "elite" if n == 5 else "combat")
				main.view.start_room()
	# --status=gel|feu|mix (captures) : les ennemis gelés, en feu (et empoisonnés), ou un sur deux
	for a3 in OS.get_cmdline_user_args():
		if a3.begins_with("--status="):
			var mode := a3.trim_prefix("--status=")
			var k := 0
			for e in arena.enemies:
				var gel := mode == "gel" or (mode == "mix" and k % 2 == 0)
				if gel:
					if e.freeze_t <= 0.0:
						arena.freeze(e, 2.0)
				else:
					arena.ignite(e, 0.0, 1.0)
					e.poison_t = 0.5
				k += 1
	if "--god" in OS.get_cmdline_user_args():
		hero.hp = hero.hp_max
	# --hero=x,y : place Jo (px) et la laisse immobile, pour filmer un coin du décor
	for a2 in OS.get_cmdline_user_args():
		if a2.begins_with("--hero="):
			var xy := a2.trim_prefix("--hero=").split(",")
			hero.position = Vector2(float(xy[0]), float(xy[1]))
			main.joy.bot_move = Vector2.ZERO
			main.joy.bot_aim_active = false
			return
	# --chest : vide la salle d'un coup pour filmer le coffre, l'objet et les portails
	if "--chest" in OS.get_cmdline_user_args() and not _chest_done and t > 3.0:
		_chest_done = true
		arena.spawn_queue.clear()
		arena.wave_i = arena.waves.size() - 1
		for e in arena.enemies.duplicate():
			e.hit(99999.0)
	if touch_test:
		_touch_t += dt
		if not _touch_started:
			_touch_started = true
			_start_pos = hero.position
			_touch(0, Vector2(200, 560), true)
			_touch(1, Vector2(1080, 560), true)
		elif _touch_t < 2.0:
			_drag(0, Vector2(200 + 90, 560))
			_drag(1, Vector2(1080, 560 - 90))
		elif _touch_t < 2.1:
			_touch(0, Vector2(290, 560), false)
			_touch(1, Vector2(1080, 470), false)
			print("TOUCH : stick gauche ok=%s (déplacement %.0f px), stick droit tirs=%d" % [str(hero.position.x - _start_pos.x > 200.0), hero.position.x - _start_pos.x, arena.bullets.size() + arena.kills])
		elif _touch_t > 2.6 and not _dash_tested:
			# bouton d'esquive : un appui au doigt doit consommer une charge
			_dash_tested = true
			_dash_before = hero.dash_stock
			var db: Vector2 = main.joy.dash_base()
			_touch(2, db, true)
			_touch(2, db, false)
		elif _dash_tested and not _dash_reported and _touch_t > 2.8:
			_dash_reported = true
			print("TOUCH : esquive ok=%s (charges %.2f -> %.2f)" % [str(hero.dash_stock < _dash_before - 0.5), _dash_before, hero.dash_stock])
		return
	think -= dt
	if think <= 0.0:
		think = 0.35
		var away := Vector2.ZERO
		var e: Node2D = arena.nearest_enemy(hero.position, 320.0)
		if e != null:
			away = (hero.position - e.position).normalized() * 1.3
		var pull := (Vector2(arena.W * 0.5, (arena.TOP + arena.H) * 0.5) - hero.position).normalized() * 0.4
		# rien à portée : va chercher l'ennemi le plus proche (sinon la salle ne finit jamais)
		if arena.nearest_enemy(hero.position, hero.rng * 0.85) == null:
			var far: Node2D = arena.nearest_enemy(hero.position, 99999.0)
			if far != null:
				pull = (far.position - hero.position).normalized() * 1.2
		# peu d'ennemis : tourner autour du plus proche (un Rempart se contourne, il ne se perce pas de face)
		var tgt: Node2D = arena.nearest_enemy(hero.position, 99999.0)
		if tgt != null and (arena.enemies.size() <= 3 or tgt.kind == "shield"):
			var to: Vector2 = tgt.position - hero.position
			var want := 150.0 if tgt.kind == "shield" else 260.0
			pull = to.normalized().orthogonal() * 1.4 * _orbit + to.normalized() * clampf((to.length() - want) / 150.0, -1.0, 1.0)
			if tgt.kind == "shield":
				away = Vector2.ZERO
				# le bouclier suit Jo : une ruée de côté pour passer derrière
				if hero.dash_stock >= 1.0 and randf() < 0.25:
					main.joy.bot_dash = true
					_dashes += 1
			if randf() < 0.05:
				_orbit = -_orbit
		dir = (away + pull + Vector2(randf_range(-1, 1), randf_range(-1, 1))).normalized()
		dir = arena.steer(hero.position, dir, hero.radius)
		if arena.cleared and not arena.chest.is_empty() and not arena.chest["open"]:
			dir = arena.steer(hero.position, (arena.chest["pos"] - hero.position).normalized(), hero.radius)
		if not arena.doors.is_empty():
			dir = (arena.doors[_door_pick % arena.doors.size()]["pos"] - hero.position).normalized()
			dir = arena.steer(hero.position, dir, hero.radius)
		# duo : relever la partenaire à terre, rester à portée d'elle
		if main.duo != null and main.duo.in_run():
			var goal: Vector2 = main.duo.bot_goal(hero)
			if goal != Vector2.INF:
				dir = arena.steer(hero.position, (goal - hero.position).normalized(), hero.radius)
				if hero.position.distance_to(goal) < 50.0:
					dir = Vector2.ZERO
	main.joy.bot_move = dir
	var pt := Performance.get_monitor(Performance.TIME_PROCESS)
	_proc_sum += pt
	_proc_n += 1.0
	_proc_max = maxf(_proc_max, pt)
	_bot_dash(dt, arena, hero)
	var target: Node2D = arena.nearest_enemy(hero.position, hero.rng)
	if target != null:
		main.joy.bot_aim = (target.position - hero.position).normalized()
		main.joy.bot_aim_active = true
	else:
		main.joy.bot_aim_active = false
	if int(t) % 10 == 0 and fmod(t, 1.0) < dt:
		print("PERF : appels de dessin %d, objets %d, primitives %d, nœuds %d, script %.1f ms (max %.1f), tirs %d, ennemis %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), _proc_sum * 1000.0 / maxf(1.0, _proc_n), _proc_max * 1000.0, arena.bullets.size(), arena.enemies.size()])
		_proc_sum = 0.0
		_proc_n = 0.0
		_proc_max = 0.0
		print("BOT : salle %d, vague %d, PV %d, kills %d, ennemis %d, pouvoirs %d, ruées %d" % [arena.room, arena.wave_i + 1, int(hero.hp), arena.kills, arena.enemies.size(), arena.energy_level, _dashes])
		# robot bloqué (rien ne bouge depuis 30 s) : on dit où, pour corriger le robot ou l'arène
		var sig := "%d/%d/%d" % [arena.room, arena.kills, arena.enemies.size()]
		if sig == _stall_sig:
			_stall_n += 1
			if _stall_n >= 3:
				var what := []
				for e in arena.enemies:
					what.append("%s@%d,%d" % [e.kind, int(e.position.x), int(e.position.y)])
				print("BOT : bloqué, Jo @%d,%d, ennemis %s, file %d, vidée %s, coffre %s, portails %d, pause %s" % [int(hero.position.x), int(hero.position.y), " ".join(what), arena.spawn_queue.size(), str(arena.cleared), str(arena.chest), arena.doors.size(), str(get_tree().paused)])
		else:
			_stall_sig = sig
			_stall_n = 0

## Ruée du robot : un tir ennemi qui arrive droit sur Jo, un ennemi au contact, ou de temps en temps.
func _bot_dash(dt: float, arena: Node, hero: Node2D) -> void:
	_dash_t -= dt
	_look_t -= dt
	if _dash_t > 0.0 or _look_t > 0.0 or hero.dash_stock < 1.0:
		return
	_look_t = 0.1
	var why := ""
	for b in arena.bullets:
		if b.hero_shot:
			continue
		var to: Vector2 = hero.position - b.position
		if to.length() < 140.0 and b.vel.normalized().dot(to.normalized()) > 0.85:
			why = "tir"
			break
	if why == "" and arena.nearest_enemy(hero.position, 26.0) != null:
		why = "contact"
	if why == "" and randf() < 0.02:
		why = "envie"
	if why != "":
		main.joy.bot_dash = true
		_dash_t = 0.6
		_dashes += 1

var _dashes := 0

## --powers=id,id:2 (niveau) : pouvoirs donnés au départ ; --allpowers : tous, au maximum, et les évolutions.
func _give_powers() -> void:
	var Data = load("res://scripts/data.gd")
	var hero: Node2D = main.hero
	for a in OS.get_cmdline_user_args():
		if a == "--allpowers":
			for p in Data.POWERS:
				for k in range(int(p["max"])):
					hero.add_power(String(p["id"]))
			for ev in Data.EVOLUTIONS:
				hero.add_power(String(ev["id"]))
		elif a.begins_with("--powers="):
			for tok in a.trim_prefix("--powers=").split(","):
				var parts := tok.split(":")
				var n := int(parts[1]) if parts.size() > 1 else 1
				for k in range(n):
					hero.add_power(String(parts[0]))
	main.arena.sync_machines()

func _click_something() -> void:
	var root: Control = main.overlay if main.overlay != null else main.screen
	if root == null:
		return
	var buttons: Array = root.find_children("*", "Button", true, false)
	var candidates := []
	for b in buttons:
		if b is Button and not b.disabled and b.visible:
			candidates.append(b)
	if candidates.is_empty():
		return
	# depuis le Relais, on préfère partir ; ailleurs, un bouton au hasard
	var pick: Button = candidates[randi() % candidates.size()]
	for b in candidates:
		if String(b.text).begins_with("PARTIR") or String(b.text).begins_with("RETOUR") or String(b.text).begins_with("REPRENDRE") or String(b.text).begins_with("REJOUER"):
			pick = b
			break
	if String(pick.text).begins_with("REJOUER"):
		var build := []
		for id in main.hero.powers:
			build.append("%s%d" % [id, main.hero.powers[id]])
		for id in main.hero.evo:
			build.append("*" + String(id))
		var won: bool = main.arena.room >= 10 and main.arena.cleared
		print("BOT : fin de partie, salle %d%s, kills %d, t=%.0f s, build %s" % [main.arena.room, " VICTOIRE" if won else "", main.arena.kills, main.arena.elapsed, " ".join(build)])
	print("BOT : clic « %s »" % pick.text)
	pick.pressed.emit()
