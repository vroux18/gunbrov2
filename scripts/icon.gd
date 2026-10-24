extends Control
## Pictogrammes dessinés en code (pouvoirs, emplacements d'objet, portails, HUD) : traits épais arrondis,
## une couleur, lisibles à 32 px comme à 96 px.

var kind := "dmg"
var color := Color("#3CF2D8")
var thickness := 0.09  # en fraction de la taille

func _init(k: String = "dmg", c: Color = Color("#3CF2D8"), size_px: float = 64.0) -> void:
	kind = k
	color = c
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _l(a: Vector2, b: Vector2, w: float = -1.0) -> void:
	var s := minf(size.x, size.y)
	var lw := (thickness if w < 0.0 else w) * s
	var o := (size - Vector2(s, s)) * 0.5
	draw_line(o + a * s, o + b * s, color, lw, true)
	draw_circle(o + a * s, lw * 0.5, color)
	draw_circle(o + b * s, lw * 0.5, color)

func _c(c: Vector2, r: float, filled: bool = false, w: float = -1.0) -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	if filled:
		draw_circle(o + c * s, r * s, color)
	else:
		draw_arc(o + c * s, r * s, 0.0, TAU, 40, color, (thickness if w < 0.0 else w) * s, true)

func _arc(c: Vector2, r: float, a0: float, a1: float) -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	draw_arc(o + c * s, r * s, a0, a1, 32, color, thickness * s, true)

func _poly(pts: Array) -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var p := PackedVector2Array()
	for v in pts:
		p.append(o + (v as Vector2) * s)
	draw_colored_polygon(p, color)

func _draw() -> void:
	var V := func(x: float, y: float) -> Vector2: return Vector2(x, y)
	match kind:
		"turret":
			_c(V.call(0.5, 0.6), 0.2)
			_l(V.call(0.5, 0.6), V.call(0.82, 0.3))
			_l(V.call(0.25, 0.88), V.call(0.75, 0.88))
		"rate":
			for k in range(3):
				var x := 0.22 + k * 0.2
				_l(V.call(x, 0.25), V.call(x + 0.18, 0.5))
				_l(V.call(x + 0.18, 0.5), V.call(x, 0.75))
		"dmg":
			for k in range(8):
				var a := TAU * k / 8.0
				var r1 := 0.18 if k % 2 == 0 else 0.12
				_l(V.call(0.5, 0.5) + Vector2(cos(a), sin(a)) * r1, V.call(0.5, 0.5) + Vector2(cos(a), sin(a)) * (0.4 if k % 2 == 0 else 0.3))
			_c(V.call(0.5, 0.5), 0.1, true)
		"speed":
			_poly([V.call(0.58, 0.1), V.call(0.24, 0.55), V.call(0.48, 0.55), V.call(0.4, 0.9), V.call(0.76, 0.42), V.call(0.52, 0.42)])
		"double":
			for x in [0.36, 0.64]:
				_l(V.call(x, 0.25), V.call(x, 0.75), 0.13)
				_c(V.call(x, 0.22), 0.07, true)
		"bounce":
			_l(V.call(0.12, 0.3), V.call(0.38, 0.75))
			_l(V.call(0.38, 0.75), V.call(0.62, 0.3))
			_l(V.call(0.62, 0.3), V.call(0.88, 0.75))
			_l(V.call(0.1, 0.86), V.call(0.9, 0.86), 0.05)
		"pierce":
			_l(V.call(0.12, 0.5), V.call(0.88, 0.5))
			_l(V.call(0.88, 0.5), V.call(0.7, 0.32))
			_l(V.call(0.88, 0.5), V.call(0.7, 0.68))
			_c(V.call(0.48, 0.5), 0.16)
		"heal":
			_l(V.call(0.5, 0.2), V.call(0.5, 0.8), 0.16)
			_l(V.call(0.2, 0.5), V.call(0.8, 0.5), 0.16)
		"shield":
			_poly([V.call(0.5, 0.1), V.call(0.84, 0.24), V.call(0.78, 0.6), V.call(0.5, 0.9), V.call(0.22, 0.6), V.call(0.16, 0.24)])
		"magnet":
			_arc(V.call(0.5, 0.45), 0.24, 0.0, PI)
			_l(V.call(0.26, 0.45), V.call(0.26, 0.18))
			_l(V.call(0.74, 0.45), V.call(0.74, 0.18))
		"boom":
			_c(V.call(0.5, 0.55), 0.22, true)
			for k in range(6):
				var a := -PI * 0.5 + (k - 2.5) * 0.4
				_l(V.call(0.5, 0.55) + Vector2(cos(a), sin(a)) * 0.3, V.call(0.5, 0.55) + Vector2(cos(a), sin(a)) * 0.44, 0.06)
		"ally":
			_c(V.call(0.5, 0.5), 0.18, true)
			_arc(V.call(0.5, 0.5), 0.34, -2.6, -0.5)
			_arc(V.call(0.5, 0.5), 0.34, 0.5, 2.6)
		"slow":
			for k in range(3):
				var a := PI * k / 3.0
				_l(V.call(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.36, V.call(0.5, 0.5) - Vector2(cos(a), sin(a)) * 0.36)
		"crit":
			_c(V.call(0.5, 0.5), 0.3)
			_c(V.call(0.5, 0.5), 0.08, true)
			_l(V.call(0.5, 0.06), V.call(0.5, 0.24), 0.07)
			_l(V.call(0.5, 0.76), V.call(0.5, 0.94), 0.07)
			_l(V.call(0.06, 0.5), V.call(0.24, 0.5), 0.07)
			_l(V.call(0.76, 0.5), V.call(0.94, 0.5), 0.07)
		"range":
			_l(V.call(0.12, 0.5), V.call(0.88, 0.5))
			_l(V.call(0.88, 0.5), V.call(0.72, 0.36))
			_l(V.call(0.88, 0.5), V.call(0.72, 0.64))
			_l(V.call(0.12, 0.34), V.call(0.12, 0.66))
		"vamp":
			_poly([V.call(0.5, 0.12), V.call(0.74, 0.52), V.call(0.68, 0.76), V.call(0.5, 0.88), V.call(0.32, 0.76), V.call(0.26, 0.52)])
		# emplacements d'objet
		"arme":
			_l(V.call(0.18, 0.42), V.call(0.82, 0.42), 0.14)
			_l(V.call(0.34, 0.42), V.call(0.3, 0.78), 0.12)
		"arme2":
			_c(V.call(0.5, 0.5), 0.26)
			_l(V.call(0.5, 0.24), V.call(0.5, 0.76), 0.06)
			_l(V.call(0.24, 0.5), V.call(0.76, 0.5), 0.06)
		"tete":
			_arc(V.call(0.5, 0.58), 0.3, PI, TAU)
			_l(V.call(0.2, 0.58), V.call(0.8, 0.58))
			_l(V.call(0.3, 0.46), V.call(0.7, 0.46), 0.06)
		"torse":
			_poly([V.call(0.22, 0.2), V.call(0.78, 0.2), V.call(0.72, 0.84), V.call(0.28, 0.84)])
		"jambes":
			_l(V.call(0.36, 0.18), V.call(0.34, 0.82), 0.14)
			_l(V.call(0.64, 0.18), V.call(0.66, 0.82), 0.14)
		"gadget":
			_c(V.call(0.5, 0.5), 0.28)
			_c(V.call(0.5, 0.5), 0.1, true)
		# HUD et portails
		"heart":
			_c(V.call(0.34, 0.38), 0.18, true)
			_c(V.call(0.66, 0.38), 0.18, true)
			_poly([V.call(0.17, 0.44), V.call(0.83, 0.44), V.call(0.5, 0.86)])
		"bolt":
			_poly([V.call(0.58, 0.06), V.call(0.22, 0.56), V.call(0.48, 0.56), V.call(0.4, 0.94), V.call(0.78, 0.42), V.call(0.52, 0.42)])
		"coin":
			_c(V.call(0.5, 0.5), 0.38, true)
		"portal":
			_c(V.call(0.5, 0.5), 0.34)
			_c(V.call(0.5, 0.5), 0.18)
		"skull":
			_c(V.call(0.5, 0.42), 0.32, true)
			_poly([V.call(0.3, 0.56), V.call(0.7, 0.56), V.call(0.64, 0.86), V.call(0.36, 0.86)])
			var keep := color
			color = Color(0.03, 0.05, 0.1, 0.9)
			_c(V.call(0.38, 0.44), 0.09, true)
			_c(V.call(0.62, 0.44), 0.09, true)
			_poly([V.call(0.5, 0.58), V.call(0.45, 0.68), V.call(0.55, 0.68)])
			color = keep
		"chest":
			_poly([V.call(0.14, 0.4), V.call(0.86, 0.4), V.call(0.86, 0.82), V.call(0.14, 0.82)])
			_arc(V.call(0.5, 0.42), 0.36, PI, TAU)
		"shard":
			# éclat du Cœur : cristal taillé, facette claire
			_poly([V.call(0.5, 0.06), V.call(0.8, 0.38), V.call(0.5, 0.94), V.call(0.2, 0.38)])
			var keep2 := color
			color = Color(1, 1, 1, 0.45)
			_poly([V.call(0.5, 0.06), V.call(0.62, 0.38), V.call(0.5, 0.72), V.call(0.38, 0.38)])
			color = keep2
		"room":
			# porte de salle : arche et seuil
			_arc(V.call(0.5, 0.5), 0.3, PI, TAU)
			_l(V.call(0.2, 0.5), V.call(0.2, 0.86))
			_l(V.call(0.8, 0.5), V.call(0.8, 0.86))
			_l(V.call(0.1, 0.86), V.call(0.9, 0.86))
		"play":
			_poly([V.call(0.3, 0.18), V.call(0.84, 0.5), V.call(0.3, 0.82)])
		"home":
			_poly([V.call(0.5, 0.12), V.call(0.88, 0.46), V.call(0.12, 0.46)])
			_poly([V.call(0.22, 0.44), V.call(0.78, 0.44), V.call(0.78, 0.86), V.call(0.22, 0.86)])
		"pause":
			_l(V.call(0.36, 0.24), V.call(0.36, 0.76), 0.16)
			_l(V.call(0.64, 0.24), V.call(0.64, 0.76), 0.16)
		"gear":
			_c(V.call(0.5, 0.5), 0.2)
			for k in range(8):
				var a := TAU * k / 8.0
				_l(V.call(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.28, V.call(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.4, 0.12)
		_:
			_c(V.call(0.5, 0.5), 0.3, true)
