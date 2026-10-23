extends Node
## Robot testeur (--autoplay) : lance une partie depuis le Relais, bouge en fuyant l'ennemi le plus proche,
## va chercher le coffre, clique sur un bouton de chaque écran. Sert au CI à détecter les erreurs de script.

var main: Node
var t := 0.0
var think := 0.0
var dir := Vector2.RIGHT
var click_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main.joy.bot = true
	print("BOT : démarrage")

func _process(dt: float) -> void:
	t += dt
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
	think -= dt
	if think <= 0.0:
		think = 0.35
		var away := Vector2.ZERO
		var e: Node2D = arena.nearest_enemy(hero.position, 320.0)
		if e != null:
			away = (hero.position - e.position).normalized() * 1.3
		var pull := (Vector2(arena.W * 0.5, arena.H * 0.5) - hero.position).normalized() * 0.4
		dir = (away + pull + Vector2(randf_range(-1, 1), randf_range(-1, 1))).normalized()
		if arena.cleared and not arena.chest.is_empty() and not arena.chest["open"]:
			dir = (arena.chest["pos"] - hero.position).normalized()
	main.joy.bot_move = dir
	main.joy.bot_aim_active = false
	if int(t) % 10 == 0 and fmod(t, 1.0) < dt:
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
