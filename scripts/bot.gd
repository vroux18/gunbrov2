extends Node
## Robot testeur (--autoplay) : lance une partie depuis le Relais, bouge en fuyant l'ennemi le plus proche,
## va chercher le coffre, clique sur un bouton de chaque écran. Sert au CI à détecter les erreurs de script.

var main: Node
var t := 0.0
var think := 0.0
var dir := Vector2.RIGHT
var click_t := 0.0

var _room_jump_done := false
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
	main._apply_profile_to_hero()

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

## Options de capture : --screen=loge|arsenal|talents ouvre l'écran et ne touche à rien ; --stuff équipe des objets d'essai.
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
			"arsenal":
				main.show_arsenal()
			"talents":
				main.show_talents()
			"power", "item", "victory", "defeat", "enemy", "tuto", "pause", "hud", "dev":
				# écrans de partie : on entre directement dans l'arène, Jo reste immobile
				main.start_run()
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
		return
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
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--room="):
				var n := int(a.trim_prefix("--room="))
				arena.start_room(n, "elite" if n == 5 else "combat")
				main.view.start_room()
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
		return
	think -= dt
	if think <= 0.0:
		think = 0.35
		var away := Vector2.ZERO
		var e: Node2D = arena.nearest_enemy(hero.position, 320.0)
		if e != null:
			away = (hero.position - e.position).normalized() * 1.3
		var pull := (Vector2(arena.W * 0.5, (arena.TOP + arena.H) * 0.5) - hero.position).normalized() * 0.4
		dir = (away + pull + Vector2(randf_range(-1, 1), randf_range(-1, 1))).normalized()
		if arena.cleared and not arena.chest.is_empty() and not arena.chest["open"]:
			dir = (arena.chest["pos"] - hero.position).normalized()
		if not arena.doors.is_empty():
			dir = (arena.doors[_door_pick % arena.doors.size()]["pos"] - hero.position).normalized()
			dir = arena.steer(hero.position, dir, hero.radius)
	main.joy.bot_move = dir
	var target: Node2D = arena.nearest_enemy(hero.position, hero.rng)
	if target != null:
		main.joy.bot_aim = (target.position - hero.position).normalized()
		main.joy.bot_aim_active = true
	else:
		main.joy.bot_aim_active = false
	if int(t) % 10 == 0 and fmod(t, 1.0) < dt:
		print("PERF : appels de dessin %d, objets %d, primitives %d, nœuds %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		print("BOT : salle %d, vague %d, PV %d, kills %d, ennemis %d" % [arena.room, arena.wave_i + 1, int(hero.hp), arena.kills, arena.enemies.size()])

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
	print("BOT : clic « %s »" % pick.text)
	pick.pressed.emit()
