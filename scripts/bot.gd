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
var touch_test := false  # --touchtest : simule de vrais doigts sur les sticks au lieu de piloter le joystick
var _touch_t := 0.0
var _touch_started := false
var _start_pos := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	touch_test = "--touchtest" in OS.get_cmdline_user_args()
	main.joy.bot = not touch_test
	print("BOT : démarrage" + (" (test tactile)" if touch_test else ""))

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

## Options de capture : --screen=loge|arsenal ouvre l'écran et ne touche à rien ; --stuff équipe des objets d'essai.
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
			_:
				main.show_base()
	return true

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
		if String(b.text).begins_with("PARTIR") or String(b.text).begins_with("RETOUR") or String(b.text).begins_with("REPRENDRE"):
			pick = b
			break
	print("BOT : clic « %s »" % pick.text)
	pick.pressed.emit()
