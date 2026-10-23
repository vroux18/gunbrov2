extends Node2D
## Projectile simulé (dessiné en 3D par view3d.gd). Déplacé ici, collisions gérées par l'arène.

const Art = preload("res://scripts/art.gd")

var vel := Vector2.ZERO
var dmg := 10.0
var life := 1.2
var hero_shot := true
var pierce := 0
var bounce := 0
var radius := 5.0
var color := Color("#3CF2D8")
var hits: Array = []  # ennemis déjà traversés (perforant)
var _spr: Sprite2D
var _glow: Sprite2D

func _process(dt: float) -> void:
	position += vel * dt
	life -= dt
	rotation = vel.angle()
