extends Control
## Carte « NOUVEL ENNEMI » : la première fois qu'un genre apparaît (une fois par joueur, voir save.gd),
## un bandeau glisse depuis la gauche avec le portrait 3D du genre (rendu en direct dans un petit
## SubViewport, seulement pendant l'affichage), son nom et une phrase de contre-jeu. ~2,6 s, ne bloque rien :
## aucun clic n'est capté. Plusieurs nouveaux genres d'un coup passent l'un après l'autre.

const UI = preload("res://scripts/ui.gd")
const Fx = preload("res://scripts/ui/fx.gd")
const Data = preload("res://scripts/data.gd")
const Models = preload("res://scripts/models.gd")

const TIPS := {
	"drone": "Elle fonce : recule en tirant.",
	"trooper": "Il s'arrête pour viser : bouge au bon moment.",
	"brute": "Bras levés = charge. Écarte-toi.",
	"bomber": "Il gonfle puis explose. Abats-le de loin.",
	"shield": "Son bouclier bloque tout. Contourne-le.",
	"sniper": "Laser violet = tir imminent. Sors de la ligne.",
	"mortar": "Cercle rouge au sol = obus. Bouge.",
}
## Pose de démonstration du portrait : l'état d'IA rejoué en boucle (le télégraphe qu'annonce la phrase).
const DEMO := {"brute": "tell", "bomber": "tell", "sniper": "aim", "mortar": "tell", "shield": "tell"}
const RED := Color("#FF4D6D")
const HOLD := 2.3
const CARD_W := 520.0
const CARD_H := 132.0
const PORTRAIT := 168.0

var queue: Array = []
var busy := false
var slowmo: Callable  # appelé à l'entrée de chaque carte (ralenti bref)
var _card: Control = null
var _vp: SubViewport = null
var _rig: Node3D = null
var _kind := ""
var _t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func push(kind: String) -> void:
	if not TIPS.has(kind) or kind in queue or kind == _kind:
		return
	queue.append(kind)
	if not busy:
		_next()

func clear() -> void:
	queue.clear()
	_drop()
	busy = false

func _next() -> void:
	if queue.is_empty():
		busy = false
		return
	busy = true
	_show(String(queue.pop_front()))

func _process(dt: float) -> void:
	_t += dt
	if _rig != null and is_instance_valid(_rig):
		# lente rotation de présentation, pose de télégraphe une seconde sur deux
		_rig.rotation.y = sin(_t * 1.3) * 0.45 + 0.25
		var demo := String(DEMO.get(_kind, ""))
		if demo != "":
			var cyc := fmod(_t, 1.6)
			var st := demo if cyc > 0.7 else "move"
			if _rig.get("state") != st:
				_rig.set("state", st)
				_rig.set("state_t", 0.0)
			_rig.set("state_t", float(_rig.get("state_t")) + dt)

func _drop() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = null
	_vp = null
	_rig = null
	_kind = ""

# ---------------------------------------------------------------- carte
func _show(kind: String) -> void:
	_drop()
	_kind = kind
	_t = 0.0
	var ins := UI.safe_insets(get_viewport())
	var vs := get_viewport_rect().size
	var x0: float = ins["left"] + 8.0
	var y0 := clampf(vs.y * 0.2, 118.0, 200.0)
	var card := Control.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.position = Vector2(x0, y0)
	card.size = Vector2(CARD_W, CARD_H)
	add_child(card)
	_card = card
	# fond : bande inclinée sombre, liseré rouge, flèche d'accroche
	var bg := Control.new()
	bg.size = card.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sweep := {"k": 0.0}
	bg.draw.connect(func():
		var w := CARD_W
		var h := CARD_H
		var sk := 22.0
		var poly := PackedVector2Array([Vector2(60, 0), Vector2(w, 0), Vector2(w - sk, h), Vector2(60, h)])
		bg.draw_colored_polygon(PackedVector2Array([poly[0] + Vector2(6, 8), poly[1] + Vector2(6, 8), poly[2] + Vector2(6, 8), poly[3] + Vector2(6, 8)]), Color(0, 0, 0, 0.35))
		bg.draw_colored_polygon(poly, Color("#101A36"))
		bg.draw_polygon(PackedVector2Array([Vector2(60, 0), Vector2(w * 0.75, 0), Vector2(w * 0.75 - sk * 0.7, h * 0.7), Vector2(60, h * 0.7)]),
			PackedColorArray([Color(RED, 0.32), Color(RED, 0.0), Color(RED, 0.0), Color(RED, 0.1)]))
		bg.draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3]]), Color(RED, 0.9), 3.0, true)
		bg.draw_rect(Rect2(60, h - 6, w - 60 - sk, 6), RED)
		# reflet qui traverse à l'entrée
		var k: float = sweep["k"]
		if k > 0.0 and k < 1.0:
			var sx := 60.0 + (w + 80.0) * k - 40.0
			bg.draw_colored_polygon(PackedVector2Array([Vector2(sx, 0), Vector2(sx + 40, 0), Vector2(sx + 10, h), Vector2(sx - 30, h)]), Color(1, 1, 1, 0.25)))
	card.add_child(bg)
	# portrait : disque, anneau rouge, rendu 3D par-dessus
	var pr := Control.new()
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pr.size = Vector2(PORTRAIT, PORTRAIT)
	pr.position = Vector2(-28, (CARD_H - PORTRAIT) * 0.5 - 4)
	pr.draw.connect(func():
		var c := pr.size * 0.5
		pr.draw_circle(c + Vector2(4, 6), PORTRAIT * 0.5, Color(0, 0, 0, 0.4))
		pr.draw_circle(c, PORTRAIT * 0.5, Color("#2A0F22"))
		pr.draw_circle(c, PORTRAIT * 0.42, Color("#3A1430"))
		pr.draw_arc(c, PORTRAIT * 0.5 - 3, 0, TAU, 56, RED, 6.0, true)
		pr.draw_arc(c, PORTRAIT * 0.5 - 12, -2.5, -0.6, 24, Color(1, 1, 1, 0.25), 3.0, true))
	card.add_child(pr)
	var tex := TextureRect.new()
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.size = Vector2(PORTRAIT, PORTRAIT)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	pr.add_child(tex)
	if not _build_portrait(kind, tex):
		var Icon = load("res://scripts/icon.gd")
		var ic: Control = Icon.new("skull", RED, PORTRAIT * 0.5)
		ic.position = Vector2(PORTRAIT * 0.25, PORTRAIT * 0.25)
		pr.add_child(ic)
	# textes
	var tg := UI.tag("NOUVEL ENNEMI", RED, Color.WHITE, 18)
	tg.position = Vector2(PORTRAIT - 14, -16)
	card.add_child(tg)
	var nm := UI.title(String(Data.ENEMIES[kind]["name"]).to_upper(), 36, UI.TEXT, RED)
	nm.position = Vector2(PORTRAIT - 10, 16)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(nm)
	var tip := UI.label(String(TIPS[kind]), 23, Color("#E6ECF5"))
	tip.position = Vector2(PORTRAIT - 10, 66)
	tip.size = Vector2(CARD_W - PORTRAIT - 20, 56)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_constant_override("line_spacing", -4)
	tip.add_theme_color_override("font_outline_color", UI.INK)
	tip.add_theme_constant_override("outline_size", 4)
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(tip)
	# animation : glisse depuis la gauche, reflet, tient, repart
	var tw := Fx._tw(card)
	card.position.x = -CARD_W - 60.0
	card.modulate.a = 1.0
	tw.tween_property(card, "position:x", x0, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float):
		sweep["k"] = v
		bg.queue_redraw(), 0.0, 1.0, 0.45)
	tw.tween_interval(HOLD - 0.45)
	tw.tween_property(card, "position:x", -CARD_W - 60.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_drop()
		_next())
	Fx.bump(pr, 0.18)
	if slowmo.is_valid():
		slowmo.call()

## Portrait 3D : le modèle sculpté du genre, dans son propre monde, rendu seulement pendant l'affichage.
func _build_portrait(kind: String, tex: TextureRect) -> bool:
	var scr := "res://scripts/mobs/%s.gd" % kind
	var glb := "res://assets/chars3d/%s.glb" % kind
	if not (ResourceLoader.exists(scr) and ResourceLoader.exists(glb)):
		return false
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_card.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.95)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -30, 0)
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.95, 0.9)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 160, 0)
	rim.light_energy = 1.1
	rim.light_color = RED.lightened(0.45)
	vp.add_child(rim)
	var holder := Node3D.new()
	vp.add_child(holder)
	var rig: Node3D = load(scr).new()
	holder.add_child(rig)
	rig.call("setup", glb)
	rig.call("set_motion", 0.6 if kind == "drone" else 0.0, 1.0 if kind == "trooper" else 0.0)
	_rig = rig
	var bb: AABB = Models.aabb(rig)
	var ctr := bb.get_center()
	var rad := maxf(bb.size.length() * 0.5, 0.2)
	var cam := Camera3D.new()
	cam.fov = 30.0
	var dir := Vector3(0.0, 0.38, 1.0).normalized()
	cam.position = ctr + dir * rad / tan(deg_to_rad(cam.fov * 0.5)) * 1.0
	vp.add_child(cam)
	cam.look_at(ctr + Vector3(0, rad * 0.04, 0), Vector3.UP)
	cam.current = true
	tex.texture = vp.get_texture()
	_vp = vp
	return true
