extends Node2D
## Projectile : trait lumineux à cœur blanc. Déplacé ici, collisions gérées par l'arène.

var vel := Vector2.ZERO
var dmg := 10.0
var life := 1.2
var hero_shot := true
var pierce := 0
var bounce := 0
var radius := 5.0
var color := Color("#3CF2D8")
var hits: Array = []  # ennemis déjà traversés (perforant)

func _process(dt: float) -> void:
	position += vel * dt
	life -= dt
	rotation = vel.angle()
	queue_redraw()

func _draw() -> void:
	var l := radius * 4.0
	draw_line(Vector2(-l, 0), Vector2(l * 0.3, 0), Color(color, 0.3), radius * 2.8)
	draw_line(Vector2(-l, 0), Vector2(l * 0.3, 0), color, radius * 1.5)
	draw_line(Vector2(-l * 0.45, 0), Vector2(l * 0.3, 0), Color.WHITE, radius * 0.6)
	draw_circle(Vector2(l * 0.3, 0), radius * 0.95, Color.WHITE)
