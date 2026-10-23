extends Node2D
## Projectile : sprite de tir teinté + halo additif. Déplacé ici, collisions gérées par l'arène.

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

func _ready() -> void:
	_glow = Art.sprite(Art.GLOW, radius * 0.11, true)
	_glow.modulate = Color(color, 0.8)
	add_child(_glow)
	_spr = Art.sprite(Art.BOLT, radius * 0.13)
	_spr.modulate = color
	_spr.position = Vector2(-radius * 3.0, 0)
	add_child(_spr)
	rotation = vel.angle()

func _process(dt: float) -> void:
	position += vel * dt
	life -= dt
	rotation = vel.angle()
