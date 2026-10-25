extends Node
## Banc du tir de Jo : Jo tire en continu sur une caisse avec l'arme choisie, pour filmer le recul, la flamme,
## les douilles, les tirs et les impacts (marques, étincelles) avec la vraie caméra.
## Lancement : $G --path . res://scripts/fx/shot_stage.tscn -- --gun=<id> --stage=<side|crate|duel>
##   side : Jo de profil (vise à droite) ; crate : vise la face avant d'une caisse ; duel : un garde lui tire
##   dessus pendant qu'elle tire (lisibilité des tirs ennemis). --gun : riveteuse, fusil_impulsion,
##   blaster_garde, pistolet_neon (vide : blaster de base). --burst=<s> : rafales de s secondes coupées par
##   des pauses (sinon tir continu).

const MainScene = preload("res://scenes/main.tscn")
const Enemy = preload("res://scripts/enemy.gd")

var main: Node
var stage := "side"
var gun := ""
var burst := 0.0
var t := 0.0
var _frame := 0
var _aim := Vector2.RIGHT
var _foe: Node2D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage = a.trim_prefix("--stage=")
		elif a.begins_with("--gun="):
			gun = a.trim_prefix("--gun=")
		elif a.begins_with("--burst="):
			burst = float(a.trim_prefix("--burst="))
	main = MainScene.instantiate()
	add_child(main)

func _process(dt: float) -> void:
	_frame += 1
	if _frame == 2:
		seed(1234)
		main.start_run()
		_setup()
		return
	if _frame < 2:
		return
	if main.overlay != null:
		main._resume()
	t += dt
	var arena: Node = main.arena
	var hero: Node2D = main.hero
	hero.hp = hero.hp_max
	arena.wave_gap = 99.0
	arena.spawn_queue.clear()
	main.joy.bot = true
	main.joy.bot_move = Vector2.ZERO
	var on := t > 0.4
	if burst > 0.0:
		on = on and fmod(t, burst * 1.6) < burst
	main.joy.bot_aim = _aim
	main.joy.bot_aim_active = on
	# l'arme choisie (la partie peut réappliquer le profil au démarrage)
	if gun != "" and main.view.hero._gun_id != gun:
		main.view.set_hero_items([{"id": gun, "rarity": 2}])

func _setup() -> void:
	var arena: Node = main.arena
	var hero: Node2D = main.hero
	arena.energy_need = 1e9
	arena.start_room(3, "combat")
	main.view.start_room()
	main.hud.flash("", 0.0)
	main.hud.fade = 0.0
	if gun != "":
		main.view.set_hero_items([{"id": gun, "rarity": 2}])
	# caisse de référence : Rect2(1000, 620, 70, 70) (scripts/arena.gd)
	match stage:
		"crate":
			hero.position = Vector2(880, 880)
			_aim = (Vector2(1035, 690) - hero.position).normalized()
		"duel":
			hero.position = Vector2(880, 880)
			_aim = (Vector2(1035, 690) - hero.position).normalized()
			_foe = _spawn("trooper", Vector2(1250, 760))
		_:
			hero.position = Vector2(840, 655)
			_aim = Vector2.RIGHT
	hero.aim_dir = _aim

func _spawn(kind: String, at: Vector2) -> Node2D:
	var arena: Node = main.arena
	var e := Enemy.new()
	e.arena = arena
	e.hero = main.hero
	e.setup(kind, false, 1.0)
	e.speed = 0.0
	e.position = at
	e.facing = (main.hero.position - at).normalized()
	arena.ents.add_child(e)
	arena.enemies.append(e)
	arena.enemy_spawned.emit(e)
	return e
