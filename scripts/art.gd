extends RefCounted
## Textures du jeu (SVG dessinés à la main dans assets/), chargées une fois.

const JO := preload("res://assets/sprites/jo.svg")
const DRONE := preload("res://assets/sprites/drone.svg")
const GARDE := preload("res://assets/sprites/garde.svg")
const COLOSSE := preload("res://assets/sprites/colosse.svg")
const PORTIQUE := preload("res://assets/sprites/portique.svg")
const FLOOR := preload("res://assets/env/floor.svg")
const CRATE := preload("res://assets/env/crate.svg")
const SHIP := preload("res://assets/env/ship.svg")
const PAD := preload("res://assets/env/pad.svg")
const CHEST := preload("res://assets/env/chest.svg")
const GLOW := preload("res://assets/fx/glow.svg")
const BOLT := preload("res://assets/fx/bolt.svg")
const FLASH := preload("res://assets/fx/flash.svg")

static func additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m

## Sprite centré, à l'échelle donnée, avec ou sans matériau additif.
static func sprite(tex: Texture2D, scale_f: float, add: bool = false) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2(scale_f, scale_f)
	if add:
		s.material = additive()
	return s
