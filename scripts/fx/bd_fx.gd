extends Node3D
## Effets BD des impacts (réglage Dev « bd_fx », bouton EFFETS BD du mode développeur), pilotés par view3d.gd :
## onomatopées très brèves (« POW », « BAM »…) sur un coup critique et à la mort d'une élite ou d'un boss, traits
## de vitesse derrière Jo pendant sa ruée. Animés « en deux » (12 i/s), comme Jo. Discrets : au plus une
## onomatopée de critique par WORD_GAP, trois à l'écran au plus (pool fixe), aucune pendant les rafales normales.
## Coût : rien hors effet ; une onomatopée = un quad (éclat à pointes, shaders/jo_backdrop.gdshader) et deux
## Label3D ; la ruée = un quad (shaders/bd_speed.gdshader).

const WORDS_CRIT := ["POW", "BAM", "PAF", "ZAP"]
const WORDS_KILL := ["BOUM", "KRAK", "BAM"]
const WORD_BOSS := "KABOUM"
const WORD_LIFE := 0.42  # durée d'une onomatopée (s)
const WORD_GAP := 1.3  # au moins ce délai entre deux onomatopées de critique (s)
const WORD_N := 3
const WORD_H := 0.75  # hauteur au-dessus de l'ennemi (m)
const WORD_SIDE := 0.95  # décalage de côté (m), à gauche ou à droite au hasard : à côté du chiffre de dégâts, pas dessus
const WORD_PX := 0.0038  # taille du texte (pixel_size des Label3D)
const SPEED_LEN := 2.2  # longueur de la traînée (m)
const SPEED_W := 1.1
const SPEED_H := 0.42
const SPEED_ALPHA := 0.85

var _words: Array = []  # {node, label, shade, burst, mat, t, life, base}
var _gap := 0.0
var _speed: MeshInstance3D
var _speed_mat: ShaderMaterial
var _speed_t := -1.0
var _speed_life := 0.0
var _speed_dir := Vector3.FORWARD
var _hero: Node3D = null

func setup(font: Font) -> void:
	top_level = true
	var bs: Shader = load("res://shaders/jo_backdrop.gdshader")
	for i in range(WORD_N):
		var n := Node3D.new()
		n.visible = false
		add_child(n)
		var burst := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		burst.mesh = q
		var m := ShaderMaterial.new()
		m.shader = bs
		m.set_shader_parameter("spikes", 11.0)
		m.set_shader_parameter("dots", 9.0)
		m.render_priority = 11
		burst.material_override = m
		burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(burst)
		var shade := _label(font, 12)
		shade.modulate = Color(0.2, 0.85, 1.0, 0.9)
		shade.outline_size = 0
		shade.offset = Vector2(7, -6)  # cran cyan décalé (impression mal calée)
		n.add_child(shade)
		var l := _label(font, 14)
		l.outline_size = 30
		l.outline_modulate = Color(0.03, 0.02, 0.06, 1.0)
		n.add_child(l)
		_words.append({"node": n, "label": l, "shade": shade, "burst": burst, "mat": m, "t": 0.0, "life": WORD_LIFE, "base": Vector3.ZERO, "s": 1.0})
	_speed = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SPEED_LEN, SPEED_W)
	_speed.mesh = pm
	_speed_mat = ShaderMaterial.new()
	_speed_mat.shader = load("res://shaders/bd_speed.gdshader")
	_speed.material_override = _speed_mat
	_speed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_speed.visible = false
	add_child(_speed)

func _label(font: Font, prio: int) -> Label3D:
	var l := Label3D.new()
	l.font = font
	l.font_size = 120
	l.pixel_size = WORD_PX
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = prio
	l.outline_render_priority = prio - 1
	return l

func enabled() -> bool:
	return bool(Dev.v.get("bd_fx", true))

## Coup critique sur un ennemi en `pos` (au sol).
func crit(pos: Vector3) -> void:
	if not enabled() or _gap > 0.0:
		return
	_gap = WORD_GAP
	_word(pos, WORDS_CRIT.pick_random(), Color("#FFE04A"), Color(1.0, 0.24, 0.42), 1.0)

## Mort d'une élite ou d'un boss en `pos`.
func kill(pos: Vector3, boss: bool) -> void:
	if not enabled():
		return
	_gap = WORD_GAP
	_word(pos, WORD_BOSS if boss else WORDS_KILL.pick_random(), Color("#FFFFFF") if boss else Color("#FFB347"), Color(1.0, 0.3, 0.2), 1.7 if boss else 1.25)

func _word(pos: Vector3, text: String, fill: Color, burst: Color, s: float) -> void:
	var best: Dictionary = _words[0]
	for w in _words:
		if not (w["node"] as Node3D).visible:
			best = w
			break
		if float(w["t"]) > float(best["t"]):
			best = w
	var side := WORD_SIDE * (1.0 if randf() < 0.5 else -1.0)
	best["base"] = pos + Vector3(side, WORD_H * minf(s, 1.4), randf_range(-0.2, 0.1))
	best["t"] = 0.0
	best["life"] = WORD_LIFE * (1.4 if s > 1.5 else 1.0)
	best["s"] = s
	var l: Label3D = best["label"]
	var sh: Label3D = best["shade"]
	l.text = text
	sh.text = text
	l.modulate = fill
	var m: ShaderMaterial = best["mat"]
	m.set_shader_parameter("col_a", burst)
	m.set_shader_parameter("col_b", burst.lerp(Color(1.0, 0.85, 0.3), 0.5))
	m.set_shader_parameter("spin", randf() * TAU)
	(best["node"] as Node3D).visible = true
	_place(best)

## Pose de l'image (par crans de 1/12 s) : éclat qui jaillit en gros, se pose, puis s'efface en gonflant un peu.
func _place(w: Dictionary) -> void:
	var tq := floorf(float(w["t"]) * 12.0) / 12.0
	var p := tq / float(w["life"])
	var k := 1.35 if tq < 0.08 else 1.0 + 0.12 * p
	var a := 1.0 - smoothstep(0.65, 1.0, p)
	var s: float = w["s"] * k
	var n: Node3D = w["node"]
	n.position = (w["base"] as Vector3) + Vector3(0, 0.25 * p, 0)
	var l: Label3D = w["label"]
	var sh: Label3D = w["shade"]
	l.pixel_size = WORD_PX * s
	sh.pixel_size = WORD_PX * s
	l.modulate.a = a
	l.outline_modulate.a = a
	sh.modulate.a = 0.9 * a
	(w["burst"] as MeshInstance3D).scale = Vector3.ONE * 1.05 * s * (1.1 if tq < 0.08 else 1.0)
	(w["mat"] as ShaderMaterial).set_shader_parameter("opacity", 0.9 * a)

## Ruée de Jo (`hero` : son nœud 3D) dans la direction `dir` (au sol), pendant `life` secondes.
func dash(hero: Node3D, dir: Vector3, life: float) -> void:
	if not enabled() or dir.length_squared() < 0.0001:
		return
	_hero = hero
	_speed_dir = dir.normalized()
	_speed_t = 0.0
	_speed_life = life + 0.08
	_speed.visible = true
	_place_speed()

func _place_speed() -> void:
	if _hero == null or not is_instance_valid(_hero):
		_speed.visible = false
		return
	var tq := floorf(_speed_t * 12.0) / 12.0
	var p := clampf(tq / _speed_life, 0.0, 1.0)
	# plan horizontal : X local vers l'arrière (UV.x de 0 contre Jo à 1 au bout), Y vers le haut
	var x := -_speed_dir
	var b := Basis(x, Vector3.UP, x.cross(Vector3.UP))
	_speed.global_transform = Transform3D(b, _hero.global_position + Vector3(0, SPEED_H, 0) + x * (SPEED_LEN * 0.5 + 0.15))
	_speed_mat.set_shader_parameter("alpha", SPEED_ALPHA * (1.0 - smoothstep(0.55, 1.0, p)))
	_speed_mat.set_shader_parameter("seed", floorf(_speed_t * 12.0))

func tick(dt: float) -> void:
	_gap = maxf(0.0, _gap - dt)
	for w in _words:
		var n: Node3D = w["node"]
		if not n.visible:
			continue
		w["t"] = float(w["t"]) + dt
		if float(w["t"]) >= float(w["life"]):
			n.visible = false
			continue
		_place(w)
	if _speed_t >= 0.0:
		_speed_t += dt
		if _speed_t >= _speed_life:
			_speed_t = -1.0
			_speed.visible = false
		else:
			_place_speed()

func clear() -> void:
	for w in _words:
		(w["node"] as Node3D).visible = false
	_speed_t = -1.0
	_speed.visible = false
	_gap = 0.0
