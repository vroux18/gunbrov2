extends Node
## Défilement au doigt d'un ScrollContainer. Le projet ne convertit pas le toucher en souris
## (pointing/emulate_mouse_from_touch = false, pour les deux sticks en multitouch) : le ScrollContainer de Godot
## ne voit alors jamais le glissé, car les boutons de la liste prennent le toucher. Ce nœud écoute le doigt
## avant l'interface : au-delà de DEADZONE px de glissé, il fait défiler la liste (avec élan au lâcher) et
## annule l'appui du bouton touché au départ (pas de clic involontaire). Un simple toucher reste un clic.
## Usage : TouchScroll.attach(scroll_container).

const DEADZONE := 14.0
const FRICTION := 5.0  # ralentissement de l'élan (par seconde)
const FAR := Vector2(-100000, -100000)  # hors de tout contrôle : le bouton relâché là ne se déclenche pas

var sc: ScrollContainer
var _idx := -1
var _start := Vector2.ZERO
var _from := Vector2.ZERO  # défilement au début du glissé
var _drag := false
var _vel := Vector2.ZERO
var _last := Vector2.ZERO
var _last_t := 0
var _faking := false

static func attach(s: ScrollContainer) -> Node:
	var n: Node = (load("res://scripts/ui/touch_scroll.gd") as GDScript).new()
	n.sc = s
	s.add_child(n, false, Node.INTERNAL_MODE_BACK)
	return n

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func _scroll_by(d: Vector2) -> void:
	if sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		sc.scroll_horizontal = int(_from.x - d.x)
	if sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		sc.scroll_vertical = int(_from.y - d.y)

func _input(ev: InputEvent) -> void:
	if _faking or not sc.is_visible_in_tree():
		return
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed:
			if _idx == -1 and sc.get_global_rect().has_point(t.position):
				_idx = t.index
				_start = t.position
				_from = Vector2(sc.scroll_horizontal, sc.scroll_vertical)
				_drag = false
				_vel = Vector2.ZERO
				_last = t.position
				_last_t = Time.get_ticks_msec()
				set_process(false)
		elif t.index == _idx:
			_idx = -1
			if _drag:
				_drag = false
				get_viewport().set_input_as_handled()
				_fake_release(t.index)
				set_process(_vel.length() > 60.0)
	elif ev is InputEventScreenDrag:
		var g := ev as InputEventScreenDrag
		if g.index != _idx:
			return
		var d := g.position - _start
		if not _drag and d.length() > DEADZONE:
			_drag = true
			_fake_move(g.index)  # le bouton touché au départ n'est plus « appuyé dedans »
		if _drag:
			var now := Time.get_ticks_msec()
			var dt := maxf(0.001, (now - _last_t) / 1000.0)
			_vel = _vel.lerp((g.position - _last) / dt, 0.5)
			_last = g.position
			_last_t = now
			_scroll_by(d)
			get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	# élan après le lâcher
	_from = Vector2(sc.scroll_horizontal, sc.scroll_vertical)
	_scroll_by(_vel * dt)
	_vel *= maxf(0.0, 1.0 - FRICTION * dt)
	if _vel.length() < 30.0:
		set_process(false)

func _fake_move(i: int) -> void:
	var m := InputEventScreenDrag.new()
	m.index = i
	m.position = FAR
	_push(m)

func _fake_release(i: int) -> void:
	var r := InputEventScreenTouch.new()
	r.index = i
	r.position = FAR
	r.pressed = false
	_push(r)

func _push(e: InputEvent) -> void:
	_faking = true
	get_viewport().push_input(e)
	_faking = false
