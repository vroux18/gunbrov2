extends Control
## Deux sticks flottants : moitié gauche de l'écran = déplacement, moitié droite = visée et tir.
## Le stick apparaît là où le pouce se pose. Clavier en secours (ZQSD / WASD / flèches) pour la version web.
## Un robot (bot.gd) peut piloter les deux sticks en posant bot = true.

var move := Vector2.ZERO
var aim := Vector2.ZERO
var aim_active := false
var enabled := true
var bot := false
var bot_move := Vector2.ZERO
var bot_aim := Vector2.ZERO
var bot_aim_active := false

const RADIUS := 84.0
const DEAD := 0.14
const TOP_RESERVED := 96.0  # bandeau du HUD : un appui là-haut n'ouvre pas de stick

var _l_id := -1
var _r_id := -1
var _l_org := Vector2.ZERO
var _l_pos := Vector2.ZERO
var _r_org := Vector2.ZERO
var _r_pos := Vector2.ZERO

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)

func reset() -> void:
	_l_id = -1
	_r_id = -1
	move = Vector2.ZERO
	aim = Vector2.ZERO
	aim_active = false

func _input(event: InputEvent) -> void:
	if not enabled or bot:
		return
	if event is InputEventScreenTouch:
		var half := size.x * 0.5
		if event.pressed:
			if event.position.y < TOP_RESERVED:
				return
			if event.position.x < half and _l_id == -1:
				_l_id = event.index
				_l_org = event.position
				_l_pos = event.position
			elif event.position.x >= half and _r_id == -1:
				_r_id = event.index
				_r_org = event.position
				_r_pos = event.position
		else:
			if event.index == _l_id:
				_l_id = -1
			if event.index == _r_id:
				_r_id = -1
	elif event is InputEventScreenDrag:
		if event.index == _l_id:
			_l_pos = event.position
		elif event.index == _r_id:
			_r_pos = event.position

func _process(_dt: float) -> void:
	if bot:
		move = bot_move
		aim = bot_aim
		aim_active = bot_aim_active
		queue_redraw()
		return
	if _l_id != -1:
		move = _stick(_l_org, _l_pos)
	else:
		move = _keys()
	if _r_id != -1:
		aim = _stick(_r_org, _r_pos)
		aim_active = aim.length() > DEAD
	else:
		aim = Vector2.ZERO
		aim_active = false
	queue_redraw()

func _stick(org: Vector2, pos: Vector2) -> Vector2:
	var d := (pos - org) / RADIUS
	if d.length() > 1.0:
		d = d.normalized()
	if d.length() < DEAD:
		return Vector2.ZERO
	return d

func _keys() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		v.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_W):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		v.y += 1.0
	return v.normalized()

func _draw() -> void:
	if not enabled or bot:
		return
	# repères discrets quand aucun pouce n'est posé
	if _l_id == -1:
		_ring(Vector2(190, size.y - 170), 0.10)
	if _r_id == -1:
		_ring(Vector2(size.x - 190, size.y - 170), 0.10)
	if _l_id != -1:
		_stick_draw(_l_org, _l_pos, Color("#F4F1EA"))
	if _r_id != -1:
		_stick_draw(_r_org, _r_pos, Color("#FF7A2F"))

func _ring(c: Vector2, a: float) -> void:
	draw_arc(c, RADIUS, 0.0, TAU, 48, Color(1, 1, 1, a), 3.0, true)
	draw_circle(c, 22.0, Color(1, 1, 1, a * 0.8))

func _stick_draw(org: Vector2, pos: Vector2, col: Color) -> void:
	var d := pos - org
	if d.length() > RADIUS:
		d = d.normalized() * RADIUS
	draw_circle(org, RADIUS, Color(1, 1, 1, 0.07))
	draw_arc(org, RADIUS, 0.0, TAU, 56, Color(col, 0.55), 3.0, true)
	draw_circle(org + d, 34.0, Color(col, 0.75))
	draw_circle(org + d, 26.0, Color(col, 0.95))
