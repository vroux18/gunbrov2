extends Node
## Banc d'effets : met en scène une situation de combat reproductible pour filmer les effets.
## Lancement : $G --path . res://scripts/fx/fx_stage.tscn -- --stage=<nom>
## Scènes : mix, crit, bomber, brute, shield, drone, mortar, pickup, hurt, boss, wave, sniper.

const MainScene = preload("res://scenes/main.tscn")
const Enemy = preload("res://scripts/enemy.gd")

var main: Node
var stage := "mix"
var t := 0.0
var _frame := 0
var _done := {}
var _ens: Array = []
var _shoot := false
var _aim_at: Node2D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage = a.trim_prefix("--stage=")
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
	# un objet ramassé ouvre un écran qui met le jeu en pause : on le referme aussitôt
	# (sauf pour filmer l'écran de choix de pouvoir)
	if main.overlay != null and stage != "power":
		main._resume()
	t += dt
	var arena: Node = main.arena
	var hero: Node2D = main.hero
	hero.hp = hero.hp_max
	if stage != "wave":
		arena.wave_gap = 99.0
		arena.spawn_queue.clear()
	main.joy.bot = true
	main.joy.bot_move = Vector2.ZERO
	var target: Node2D = _aim_at
	if target == null or not is_instance_valid(target) or target.dead:
		target = arena.nearest_enemy(hero.position, 700.0)
	if _shoot and target != null:
		main.joy.bot_aim = (target.position - hero.position).normalized()
		main.joy.bot_aim_active = true
	else:
		main.joy.bot_aim_active = false
	_script(arena, hero)

func _spawn(kind: String, off: Vector2, elite: bool = false, speed_k: float = 0.0) -> Node2D:
	var arena: Node = main.arena
	var e := Enemy.new()
	e.arena = arena
	e.hero = main.hero
	e.setup(kind, elite, 1.0)
	e.speed *= speed_k
	e.position = main.hero.position + off
	e.facing = -off.normalized()
	arena.ents.add_child(e)
	arena.enemies.append(e)
	arena.enemy_spawned.emit(e)
	_ens.append(e)
	return e

func _once(key: String, at: float) -> bool:
	if t >= at and not _done.has(key):
		_done[key] = true
		return true
	return false

func _kill(e: Node2D) -> void:
	if e != null and is_instance_valid(e) and not e.dead:
		e.hit(999999.0)

func _setup() -> void:
	var arena: Node = main.arena
	var hero: Node2D = main.hero
	arena.energy_need = 1e9
	var room := 3
	if stage == "boss":
		room = 10
	arena.start_room(room, "combat")
	main.view.start_room()
	main.hud.flash("", 0.0)
	main.hud.fade = 0.0
	hero.position = Vector2(1200, 820)
	match stage:
		"mix":
			hero.crit = 0.25
			_shoot = true
			_spawn("trooper", Vector2(260, -60), false, 0.2)
			_spawn("drone", Vector2(330, 90), false, 0.15)
			_spawn("shield", Vector2(-280, -40), false, 0.2)
			_spawn("sniper", Vector2(-120, -220), false, 0.0)
			_spawn("mortar", Vector2(180, -230), false, 0.0)
			_spawn("bomber", Vector2(-330, 120), false, 0.1)
			_spawn("brute", Vector2(60, 230), false, 0.15)
		"crit":
			hero.crit = 0.6
			_shoot = true
			_spawn("brute", Vector2(240, -20), true, 0.0)
		"bomber":
			_spawn("bomber", Vector2(230, -30), false, 0.0)
		"brute":
			_spawn("brute", Vector2(240, -30), false, 0.0)
		"shield":
			_shoot = true
			_aim_at = _spawn("shield", Vector2(250, -10), false, 0.0)
		"drone":
			_spawn("drone", Vector2(220, -60), false, 0.0)
			_spawn("drone", Vector2(300, 60), false, 0.0)
			_spawn("drone", Vector2(-240, 20), false, 0.0)
		"mortar":
			_spawn("mortar", Vector2(330, -200), false, 0.0)
		"pickup":
			for i in range(5):
				_spawn("trooper" if i % 2 == 0 else "shield", Vector2(-300 + i * 150, -170 + (i % 2) * 330), false, 0.0)
		"hurt":
			_spawn("trooper", Vector2(300, -40), false, 0.0)
		"boss":
			hero.position = Vector2(1200, 1000)
			arena.boss = _spawn("boss", Vector2(0, -170), false, 0.0)
		"sniper":
			_spawn("sniper", Vector2(300, -120), false, 0.3)
		"wave":
			hero.position = Vector2(1200, 1120)
		"fxbench":
			_bench()
		"dense":
			# 25 ennemis de tous genres qui attaquent pour de bon : mesure du coût des effets
			hero.crit = 0.2
			_shoot = true
			var kinds := ["drone", "trooper", "bomber", "sniper", "shield", "mortar", "drone", "trooper", "brute"]
			for i in range(25):
				var a := TAU * i / 25.0
				_spawn(kinds[i % kinds.size()], Vector2(cos(a), sin(a) * 0.6) * randf_range(250, 520), false, 1.0)

## Coût CPU des effets (µs par appel), mesuré dans la vraie scène.
func _bench() -> void:
	var fx = main.view.fxs
	var p := Vector3(18, 0, 12)
	var cases := {
		"muzzle": func(): fx.muzzle(p + Vector3(0, 0.6, 0), Vector3(1, 0, 0), Color("#3CF2D8"), false),
		"hit": func(): fx.hit(p, Vector3(1, 0, 0), Color("#3CF2D8"), false),
		"hit crit": func(): fx.hit(p, Vector3(1, 0, 0), Color("#3CF2D8"), true),
		"explosion": func(): fx.explosion(p, 1.2, Color("#FF9A3C")),
		"mort garde": func(): fx.death("trooper", p, Vector3(1, 0, 0), false),
		"mort colosse": func(): fx.death("brute", p, Vector3(1, 0, 0), false),
		"cratère": func(): fx.crater(p, 1.0),
		"traînée": func(): fx.trail_add(p, Vector3(10, 0, 0), Color.WHITE, 0.2, 0.07),
	}
	for k in cases:
		var cb: Callable = cases[k]
		var n := 200
		var t0 := Time.get_ticks_usec()
		for i in range(n):
			cb.call()
		print("FXBENCH %s : %.1f µs" % [k, float(Time.get_ticks_usec() - t0) / n])
		fx.trail_begin()
	var t1 := Time.get_ticks_usec()
	for i in range(100):
		fx.tick(0.016)
	print("FXBENCH tick : %.1f µs" % (float(Time.get_ticks_usec() - t1) / 100.0))

var _perf_acc := 0.0
var _perf_n := 0
var _perf_max := 0.0
var _perf_t := 0.0

func _script(arena: Node, hero: Node2D) -> void:
	if stage == "dense":
		var pt := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_perf_acc += pt
		_perf_n += 1
		_perf_max = maxf(_perf_max, pt)
		_perf_t += get_process_delta_time()
		if _perf_t >= 2.0:
			print("FXPERF t=%.0f process moy %.2f ms max %.2f ms, appels %d, ennemis %d, nœuds %d" % [t, _perf_acc / _perf_n, _perf_max, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), arena.enemies.size(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
			_perf_acc = 0.0
			_perf_n = 0
			_perf_max = 0.0
			_perf_t = 0.0
		# la mêlée se renouvelle : on remet des ennemis quand il en manque
		if arena.enemies.size() < 20 and int(t * 10.0) % 5 == 0:
			var kinds := ["drone", "trooper", "bomber", "shield", "mortar"]
			var a := randf() * TAU
			_spawn(kinds[randi() % kinds.size()], Vector2(cos(a), sin(a) * 0.6) * 480.0, false, 1.0)
	match stage:
		"bomber", "brute":
			if _once("k", 0.8):
				_kill(_ens[0])
		"drone":
			if _once("k1", 0.6):
				_kill(_ens[0])
			if _once("k2", 0.9):
				_kill(_ens[1])
			if _once("k3", 1.2):
				_kill(_ens[2])
		"mortar":
			if _once("l1", 0.4):
				arena.lob(_ens[0].position, hero.position + Vector2(-120, 40), 1.1, 62.0, 0.0)
			if _once("l2", 0.9):
				arena.lob(_ens[0].position, hero.position + Vector2(140, 90), 1.1, 62.0, 0.0)
		"pickup":
			if _once("k", 0.5):
				for e in _ens:
					_kill(e)
			if _once("c", 1.3):
				arena.cleared = true
		"hurt":
			for k in range(4):
				if _once("b%d" % k, 0.5 + k * 0.6):
					var from: Vector2 = _ens[0].position
					arena.spawn_bullet(from, (hero.position - from).normalized() * 600.0, 5.0, false, 0, 0, Color("#FF4D6D"), 4.5)
		"boss":
			if _once("k", 1.6):
				_kill(_ens[0])
		"power":
			if _once("e", 0.6):
				arena.energy_full.emit()
			if _once("c", 1.4) and main.overlay != null:
				var bs: Array = main.overlay.find_children("*", "Button", true, false)
				if not bs.is_empty():
					(bs[0] as Button).pressed.emit()
		"chest":
			if _once("r", 0.3):
				arena._room_done()
			if _once("m", 1.2):
				hero.position = arena.chest["pos"]
