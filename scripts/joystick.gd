extends Control
## Deux sticks fixes, toujours visibles : gauche = déplacement, droit = visée et tir.
## Chaque stick a sa zone (moitié d'écran sous le HUD). Un pouce posé près de la base prend la base
## comme origine ; posé plus loin, l'origine est le point de contact (le stick glisse sous le pouce).
## Le tir ne part que quand le stick droit est poussé. Clavier en secours (ZQSD / WASD / flèches,
## espace ou clic droit pour tirer vers la souris) sur la version web.
## Un robot (bot.gd) peut piloter les deux sticks en posant bot = true.

var move := Vector2.ZERO
var aim := Vector2.ZERO
var aim_active := false
var enabled := true
var bot := false
var bot_move := Vector2.ZERO
var bot_aim := Vector2.ZERO
var bot_aim_active := false

const RADIUS := 92.0
const KNOB := 40.0
const DEAD := 0.16
const TOP_RESERVED := 100.0  # bandeau du HUD : un appui là-haut n'ouvre pas de stick
const GRAB := 1.7  # un pouce posé à moins de GRAB × RADIUS de la base prend la base comme origine

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

func _vp() -> Vector2:
	return get_viewport_rect().size

func left_base() -> Vector2:
	var v := _vp()
	return Vector2(190.0, v.y - 170.0)

func right_base() -> Vector2:
	var v := _vp()
	return Vector2(v.x - 190.0, v.y - 170.0)

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
		var half := _vp().x * 0.5
		if event.pressed:
			if event.position.y < TOP_RESERVED:
				return
			if event.position.x < half and _l_id == -1:
				_l_id = event.index
				var base := left_base()
				_l_org = base if (event.position - base).length() < RADIUS * GRAB else event.position
				_l_pos = event.position
			elif event.position.x >= half and _r_id == -1:
				_r_id = event.index
				var base := right_base()
				_r_org = base if (event.position - base).length() < RADIUS * GRAB else event.position
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
		aim = _key_aim()
		aim_active = aim.length() > DEAD
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

## Clavier : flèches I J K L ou pavé numérique pour viser ; espace = tirer dans la direction du déplacement.
func _key_aim() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_J) or Input.is_key_pressed(KEY_KP_4):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_L) or Input.is_key_pressed(KEY_KP_6):
		v.x += 1.0
	if Input.is_key_pressed(KEY_I) or Input.is_key_pressed(KEY_KP_8):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_K) or Input.is_key_pressed(KEY_KP_2):
		v.y += 1.0
	if v == Vector2.ZERO and Input.is_key_pressed(KEY_SPACE):
		v = move if move != Vector2.ZERO else Vector2.UP
	return v.normalized()

func _draw() -> void:
	if not enabled or bot:
		return
	# stick gauche : base fixe, ou base glissée sous le pouce
	var lo := left_base()
	var lcol := Color("#F4F1EA")
	if _l_id == -1:
		_base(lo, lcol, 0.35)
		_knob(lo, lcol, 0.5)
	else:
		if _l_org != lo:
			_base(lo, lcol, 0.15)
		_base(_l_org, lcol, 0.7)
		_knob(_l_org + _clamped(_l_org, _l_pos), lcol, 1.0)
	# stick droit : orange, l'anneau s'allume quand on tire
	var ro := right_base()
	var rcol := Color("#FF7A2F")
	if _r_id == -1:
		_base(ro, rcol, 0.35)
		_knob(ro, rcol, 0.5)
	else:
		if _r_org != ro:
			_base(ro, rcol, 0.15)
		_base(_r_org, rcol, 0.7 if not aim_active else 1.0)
		_knob(_r_org + _clamped(_r_org, _r_pos), rcol, 1.0)

func _clamped(org: Vector2, pos: Vector2) -> Vector2:
	var d := pos - org
	if d.length() > RADIUS:
		d = d.normalized() * RADIUS
	return d

func _base(c: Vector2, col: Color, a: float) -> void:
	draw_circle(c, RADIUS, Color(0, 0, 0, 0.22 * a))
	draw_arc(c, RADIUS, 0.0, TAU, 64, Color(col, 0.8 * a), 4.0, true)
	draw_arc(c, RADIUS * 0.55, 0.0, TAU, 48, Color(col, 0.25 * a), 2.0, true)
	for i in range(4):
		var ang := TAU * i / 4.0
		var p := c + Vector2.RIGHT.rotated(ang) * (RADIUS - 14.0)
		draw_line(p, c + Vector2.RIGHT.rotated(ang) * (RADIUS - 4.0), Color(col, 0.8 * a), 4.0)

func _knob(c: Vector2, col: Color, a: float) -> void:
	draw_circle(c, KNOB + 4.0, Color(0, 0, 0, 0.35 * a))
	draw_circle(c, KNOB, Color(col, 0.85 * a))
	draw_circle(c + Vector2(-8, -10), KNOB * 0.35, Color(1, 1, 1, 0.35 * a))
