extends RefCounted
## Animations d'interface (Tween uniquement) : entrées et sorties d'écran, appui des boutons, compteurs qui
## défilent, secousse, pulsation. Tout tourne aussi pendant la pause (les overlays figent la partie).

const SHINE = preload("res://shaders/ui_shine.gdshader")

static func _tw(n: Node) -> Tween:
	var tw := n.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_ignore_time_scale(true)
	return tw

## Pivot au centre, tenu à jour quand le nœud change de taille (les conteneurs le redimensionnent).
static func center_pivot(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	if not c.resized.is_connected(_on_resized.bind(c)):
		c.resized.connect(_on_resized.bind(c))

static func _on_resized(c: Control) -> void:
	c.pivot_offset = c.size * 0.5

## Bouton qui s'enfonce au toucher et rebondit au relâché.
static func press(b: BaseButton, depth: float = 0.92) -> void:
	center_pivot(b)
	b.button_down.connect(func():
		var tw := _tw(b)
		tw.tween_property(b, "scale", Vector2(depth, depth), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	b.button_up.connect(func():
		var tw := _tw(b)
		tw.tween_property(b, "scale", Vector2.ONE * 1.04, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

## Entrée : glisse depuis `from` (décalage en px), grossit légèrement et apparaît.
static func slide_in(n: Control, from: Vector2, delay: float = 0.0, dur: float = 0.38) -> void:
	var to := n.position
	n.modulate.a = 0.0
	var tw := _tw(n)
	tw.tween_interval(delay)
	tw.tween_callback(func():
		n.position = to + from)
	tw.set_parallel(true)
	tw.tween_property(n, "modulate:a", 1.0, dur * 0.6)
	tw.tween_property(n, "position", to, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Entrée d'un élément placé par un conteneur : on anime un décalage visuel (pas la position, que le
## conteneur impose) via la translation du pivot. Ici : fondu + petite remontée par `scale` et alpha.
static func rise_in(n: Control, delay: float = 0.0, dur: float = 0.34, from_scale: float = 0.8) -> void:
	center_pivot(n)
	n.modulate.a = 0.0
	n.scale = Vector2.ONE * from_scale
	var tw := _tw(n)
	tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(n, "modulate:a", 1.0, dur * 0.5)
	tw.tween_property(n, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Tampon : arrive très gros et s'écrase à sa taille (titres, bandeaux).
static func slam(n: Control, delay: float = 0.0, from_scale: float = 2.2) -> void:
	center_pivot(n)
	n.modulate.a = 0.0
	n.scale = Vector2.ONE * from_scale
	var tw := _tw(n)
	tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(n, "modulate:a", 1.0, 0.12)
	tw.tween_property(n, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Fondu d'entrée d'un écran entier.
static func screen_in(root: Control, dur: float = 0.22) -> void:
	root.modulate.a = 0.0
	var tw := _tw(root)
	tw.tween_property(root, "modulate:a", 1.0, dur)

## Sortie d'un écran : plus de clic possible, fondu, puis libération.
static func screen_out(root: Control, dur: float = 0.16) -> void:
	if root == null or not is_instance_valid(root):
		return
	_mute_input(root)
	var tw := _tw(root)
	tw.tween_property(root, "modulate:a", 0.0, dur)
	tw.tween_callback(root.queue_free)

static func _mute_input(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if n is BaseButton:
		(n as BaseButton).disabled = true
	for c in n.get_children():
		_mute_input(c)

## Compteur qui défile de `from` à `to` (Label) ; `fmt` reçoit l'entier courant.
static func count(l: Label, from: int, to: int, dur: float = 0.8, delay: float = 0.0, fmt: String = "%d") -> Tween:
	l.text = fmt % from
	var tw := _tw(l)
	tw.tween_interval(delay)
	tw.tween_method(func(v: float): l.text = fmt % int(round(v)), float(from), float(to), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw

## Petit saut d'échelle (compteur qui change, gain).
static func bump(n: Control, amount: float = 0.25) -> void:
	center_pivot(n)
	var tw := _tw(n)
	tw.tween_property(n, "scale", Vector2.ONE * (1.0 + amount), 0.07)
	tw.tween_property(n, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Respiration continue (bouton principal).
static func breathe(n: Control, amount: float = 0.035, period: float = 1.4) -> void:
	center_pivot(n)
	var tw := _tw(n)
	tw.set_loops()
	tw.tween_property(n, "scale", Vector2.ONE * (1.0 + amount), period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(n, "scale", Vector2.ONE, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Reflet qui balaie le nœud (texte ou bouton) : shader léger, une bande claire qui passe toutes les `period` s.
static func shine(n: CanvasItem, width_px: float, period: float = 2.6, strength: float = 0.55) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHINE
	m.set_shader_parameter("span", width_px)
	m.set_shader_parameter("period", period)
	m.set_shader_parameter("strength", strength)
	n.material = m
	return m

## Halo radial additif (rareté, bouton principal) : une texture partagée, teintée par modulate.
static var _halo_tex: GradientTexture2D = null

static func halo_texture() -> GradientTexture2D:
	if _halo_tex != null:
		return _halo_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.45))
	_halo_tex = GradientTexture2D.new()
	_halo_tex.gradient = g
	_halo_tex.fill = GradientTexture2D.FILL_RADIAL
	_halo_tex.fill_from = Vector2(0.5, 0.5)
	_halo_tex.fill_to = Vector2(0.5, 0.0)
	_halo_tex.width = 128
	_halo_tex.height = 128
	return _halo_tex

static func halo(col: Color, size: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = halo_texture()
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.size = size
	tr.modulate = col
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	tr.material = mat
	return tr

## Pulsation d'alpha et d'échelle en boucle (halo).
static func pulse(n: CanvasItem, a0: float, a1: float, period: float = 1.2) -> void:
	var tw := _tw(n)
	tw.set_loops()
	tw.tween_property(n, "modulate:a", a1, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(n, "modulate:a", a0, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
