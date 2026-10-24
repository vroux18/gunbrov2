extends Control
## Tutoriel discret de la toute première partie : deux pouces animés au-dessus des sticks.
## Gauche : le pouce tourne autour de la base (« DÉPLACE-TOI »). Droite : le pouce pousse et des tirs
## partent (« VISE ET TIRE »). Chaque indication s'efface dès que le joueur a fait le geste.

signal finished

const UI = preload("res://scripts/ui.gd")

var joy: Node = null
var _t := 0.0
var _left := 1.0  # opacité de l'indication gauche (0 = faite)
var _right := 1.0
var _left_acc := 0.0
var _right_acc := 0.0
var _left_done := false
var _right_done := false
var _in := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(dt: float) -> void:
	_t += dt
	_in = minf(1.0, _in + dt * 2.5)
	if joy != null:
		if joy.move.length() > 0.35:
			_left_acc += dt
		if joy.aim_active:
			_right_acc += dt
	if _left_acc > 0.3:
		_left_done = true
	if _right_acc > 0.3:
		_right_done = true
	if _left_done:
		_left = maxf(0.0, _left - dt * 3.0)
	if _right_done:
		_right = maxf(0.0, _right - dt * 3.0)
	if _left <= 0.0 and _right <= 0.0:
		finished.emit()
		queue_free()
		return
	queue_redraw()

func _thumb(tip: Vector2, from_dir: Vector2, a: float, press: float) -> void:
	# pouce stylisé : phalange en capsule venant du bord, ongle clair, ombre portée
	var base := tip + from_dir * 120.0
	var w := 50.0 - press * 4.0
	draw_line(tip + Vector2(6, 10), base + Vector2(6, 10), Color(0, 0, 0, 0.3 * a), w + 6.0)
	draw_circle(tip + Vector2(6, 10), (w + 6.0) * 0.5, Color(0, 0, 0, 0.3 * a))
	draw_line(tip, base, Color(UI.INK, a), w + 8.0)
	draw_circle(tip, (w + 8.0) * 0.5, Color(UI.INK, a))
	draw_line(tip, base, Color(Color("#F4E3D3"), a), w)
	draw_circle(tip, w * 0.5, Color(Color("#F4E3D3"), a))
	var nail := tip + from_dir * 12.0
	draw_circle(nail, w * 0.27, Color(1, 1, 1, 0.9 * a))
	draw_line(tip + from_dir * 44.0 + from_dir.orthogonal() * w * 0.32, tip + from_dir * 44.0 - from_dir.orthogonal() * w * 0.32, Color(0.8, 0.62, 0.55, 0.6 * a), 3.0)

func _label(pos: Vector2, text: String, col: Color, a: float) -> void:
	var fs := 30
	var w := 400.0
	draw_string_outline(UI.TITLE, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 10, Color(UI.INK, a))
	draw_string(UI.TITLE, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(col, a))

func _draw() -> void:
	if joy == null:
		return
	var e := _in * _in * (3.0 - 2.0 * _in)
	var lb: Vector2 = joy.left_base()
	var rb: Vector2 = joy.right_base()
	# ---------------- gauche : le pouce décrit une boucle, quatre flèches autour de la base
	if _left > 0.0:
		var a := _left * e
		var ang := _t * 2.6
		var tip := lb + Vector2(cos(ang), sin(ang) * 0.75) * 62.0
		for i in range(4):
			var d := Vector2.RIGHT.rotated(TAU * i / 4.0)
			var p := lb + d * (118.0 + 6.0 * sin(_t * 5.0 + i))
			var o := d.orthogonal()
			draw_colored_polygon(PackedVector2Array([p + d * 16.0, p - d * 6.0 + o * 15.0, p - d * 6.0 - o * 15.0]), Color(UI.TEXT, 0.9 * a))
		# traînée de la boucle
		for k in range(10):
			var ak := ang - 0.12 * (k + 1)
			draw_circle(lb + Vector2(cos(ak), sin(ak) * 0.75) * 62.0, 12.0 - k, Color(UI.TEXT, 0.22 * a * (1.0 - k / 10.0)))
		_thumb(tip, Vector2(-0.45, 1.0).normalized(), a, 0.0)
		_label(lb + Vector2(0, -150 - 4.0 * sin(_t * 3.0)), "DÉPLACE-TOI", UI.TEXT, a)
	# ---------------- droite : le pouce pousse vers le haut à droite, des tirs partent
	if _right > 0.0:
		var a2 := _right * e
		var cyc := fmod(_t, 1.6) / 1.6
		var push := clampf(cyc / 0.35, 0.0, 1.0)
		push = push * push * (3.0 - 2.0 * push)
		if cyc > 0.85:
			push = 1.0 - (cyc - 0.85) / 0.15
		var dir := Vector2(0.62, -0.78).normalized()
		var tip2 := rb + dir * 70.0 * push
		draw_circle(rb, 92.0, Color(UI.ORANGE, 0.12 * a2 * push))
		draw_arc(rb, 92.0, 0, TAU, 48, Color(UI.ORANGE, 0.75 * a2 * push), 4.0, true)
		if push > 0.9:
			# trois tirs turquoise qui partent dans la direction visée
			for k in range(3):
				var f := fmod(_t * 3.0 + k / 3.0, 1.0)
				var bp := rb + dir * (110.0 + f * 220.0)
				draw_line(bp, bp + dir * 22.0, Color(UI.ACCENT, a2 * (1.0 - f)), 8.0)
				draw_circle(bp + dir * 22.0, 4.0, Color(1, 1, 1, a2 * (1.0 - f)))
		_thumb(tip2, Vector2(0.45, 1.0).normalized(), a2, push)
		_label(rb + Vector2(0, -150 - 4.0 * sin(_t * 3.0 + 1.0)), "VISE ET TIRE", UI.ORANGE, a2)
