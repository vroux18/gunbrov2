extends Node3D
## Rendu des pouvoirs de Jo (simulés par arena.gd) : tirs en feu, en glace ou électriques, arcs de foudre,
## nuages toxiques, flaques de feu, ennemis qui brûlent ou gelés dans la glace, lames orbitales, missiles à
## traînée, mines, scies, mini-drones, ondes de choc, météores, foudre du ciel, ruée de Jo.
## Tout passe par des réserves MultiMesh (fx_pool.gd) et quelques MultiMesh réécrits à chaque image : aucun nœud
## par tir ni par effet. Seule l'aura glaciale a son nœud (un disque au sol, un seul).

const FxPool = preload("res://scripts/fx/fx_pool.gd")
const Models = preload("res://scripts/models.gd")
const K := 1.0 / 64.0
const UP := Vector3.UP
const FIRE := Color("#FF8A3C")
const ICE := Color("#9FDCFF")
const SHOCK := Color("#FFE45C")
const VENOM := Color("#8BE05A")
const MACH := Color("#9BE15D")
const GOLD := Color("#FFB347")
const SHIELD := Color("#5AA8FF")
const MAX_EMIT := 70  # bouffées d'état par image, au plus (parties denses)

var view: Node3D
var arena: Node
var hero2d: Node2D
var now := 1.0
var glow: FxPool  # additif rond : étincelles, braises, éclats de givre, bulles
var fire: FxPool  # bouffées de feu
var smoke: FxPool  # bouffées opaques : poison, fumée des missiles
var decal: FxPool  # au sol : nuages, flaques, ondes, cibles des météores
var seg: FxPool  # par image : segments lumineux pleins (foudre)
var tail: FxPool  # par image : traînées qui s'effacent (missiles, lames, scies, ruée, météores)
var dot: FxPool  # par image : points lumineux (têtes de missile, voyants, cœurs)
var _seg_n := 0
var _tail_n := 0
var _dot_n := 0
var _emit := 0
var _arcs: Array = []  # {pts: Array[Vector3], t, life, col}
var _strikes: Array = []  # {pos, t}
var _meteors: Array = []  # {pos, t, delay}
var _dash := {}  # {from, end_t}
var _mm := {}  # nom -> MultiMesh réécrit à chaque image
var _aura: MeshInstance3D
var _aura_mat: ShaderMaterial

func setup(v: Node3D, a: Node, h: Node2D) -> void:
	view = v
	arena = a
	hero2d = h
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var radial: Texture2D = Models.radial()
	var puff: Texture2D = load("res://assets/fx/puff.png")
	var add_sh: Shader = load("res://shaders/fx_add.gdshader")
	var mix_sh: Shader = load("res://shaders/fx_mix.gdshader")
	decal = FxPool.new(self, quad, load("res://shaders/fx_decal.gdshader"), 96, {"energy": 1.0}, -3)
	smoke = FxPool.new(self, quad, mix_sh, 192, {"tex": puff, "fade_in": 0.15, "fade_pow": 1.2, "rise": 0.6, "spin": 1.0, "shade": 0.7}, 0)
	fire = FxPool.new(self, quad, mix_sh, 256, {"tex": puff, "fade_pow": 1.6, "spin": 2.0, "energy": 1.0, "shade": 0.5, "rise": 2.2}, 1)
	glow = FxPool.new(self, quad, add_sh, 512, {"tex": radial, "energy": 1.0, "fade_pow": 1.2}, 2)
	seg = FxPool.new(self, quad, add_sh, 360, {"tex": radial, "energy": 1.0, "streak": 0.0}, 2, true)
	tail = FxPool.new(self, quad, add_sh, 160, {"tex": radial, "energy": 1.0}, 1, true)
	dot = FxPool.new(self, quad, add_sh, 160, {"tex": radial, "energy": 1.0}, 3, true)
	_mm["blade"] = _make_mm(_blade_mesh(), 24, _solid_mat(1.5, true))
	_mm["missile"] = _make_mm(_capsule(0.065, 0.36), 48, _solid_mat(1.2))
	_mm["mine"] = _make_mm(_disc_mesh(0.2, 0.08, 10), 12, _solid_mat(1.0))
	_mm["saw"] = _make_mm(_saw_mesh(), 8, _solid_mat(1.3, true))
	_mm["mini"] = _make_mm(_sphere(0.11), 20, _solid_mat(1.2))
	_mm["ice"] = _make_mm(_sphere(1.0, 7, 3), 64, _ice_mat())
	# aura glaciale : un disque au sol qui suit Jo
	_aura = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	_aura.mesh = pm
	_aura_mat = ShaderMaterial.new()
	_aura_mat.shader = load("res://shaders/ground_ring.gdshader")
	_aura_mat.set_shader_parameter("color", Color(ICE, 0.55))
	_aura_mat.set_shader_parameter("width", 0.035)
	_aura_mat.set_shader_parameter("fill", 0.06)
	_aura_mat.render_priority = 3
	_aura.material_override = _aura_mat
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.visible = false
	add_child(_aura)
	arena.power_event.connect(_on_event)

static func p3(v: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(v.x * K, h, v.y * K)

## Changement de salle : tout ce qui est en cours s'éteint.
func clear() -> void:
	now += 1000.0
	_arcs.clear()
	_strikes.clear()
	_meteors.clear()
	_dash = {}
	_sync_time()
	for k in _mm:
		(_mm[k] as MultiMesh).visible_instance_count = 0
	for p in [seg, tail, dot]:
		(p as FxPool).show(0)

func _sync_time() -> void:
	for p in [glow, fire, smoke, decal, seg, tail, dot]:
		(p as FxPool).set_time(now)

# ---------------------------------------------------------------- maillages et matériaux
func _make_mm(mesh: Mesh, cap: int, mat: Material) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 200.0
	add_child(mi)
	return mm

## Matériau plein et sans ombrage, teinté par la couleur d'instance ; `rim` : bord plus clair (lames, scies).
func _solid_mat(energy: float, rim: bool = false) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform float energy = 1.0;
uniform float rim = 0.0;
void fragment() {
	float f = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	vec3 c = COLOR.rgb * (0.55 + 0.45 * clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0));
	ALBEDO = mix(c, vec3(1.0), f * rim) * energy;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("rim", 0.8 if rim else 0.25)
	return m

## Glace : coque translucide, bord blanc, reflets ; l'ennemi gelé se voit dedans.
func _ice_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;
void fragment() {
	// facettes nettes (normale de la face), bleu glacier, arêtes claires
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	float f = 1.0 - clamp(abs(dot(n, VIEW)), 0.0, 1.0);
	float lit = clamp(dot(n, normalize(vec3(0.35, 0.85, 0.4))), 0.0, 1.0);
	vec3 c = mix(vec3(0.25, 0.62, 1.0), vec3(0.8, 0.96, 1.0), lit * lit);
	c = mix(c, vec3(1.0), f * 0.7);
	ALBEDO = c * 1.3;
	ALPHA = clamp(0.4 + 0.4 * f + 0.2 * lit, 0.0, 0.9);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = 2
	return m

func _capsule(r: float, h: float) -> Mesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 2
	return c

func _sphere(r: float, seg_n: int = 8, rings: int = 4) -> Mesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg_n
	s.rings = rings
	return s

func _disc_mesh(r: float, h: float, n: int) -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = r * 0.8
	c.bottom_radius = r
	c.height = h
	c.radial_segments = n
	c.rings = 1
	return c

## Lame orbitale : losange plat effilé (pointe vers +z), deux faces.
func _blade_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0, 0, 0.42)
	var back := Vector3(0, 0, -0.2)
	var l := Vector3(-0.1, 0.0, 0.02)
	var r := Vector3(0.1, 0.0, 0.08)
	var top := Vector3(0, 0.05, 0.04)
	for tri in [[tip, l, top], [tip, top, r], [back, top, l], [back, r, top], [tip, r, l], [back, l, r]]:
		for v in tri:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()

## Scie : étoile plate à 8 dents.
func _saw_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	for i in range(n):
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var r0 := 0.3 if i % 2 == 0 else 0.2
		var r1 := 0.3 if (i + 1) % 2 == 0 else 0.2
		var p0 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var p1 := Vector3(cos(a1) * r1, 0.0, sin(a1) * r1)
		st.add_vertex(Vector3(0, 0.03, 0))
		st.add_vertex(p1)
		st.add_vertex(p0)
	st.generate_normals()
	return st.commit()

# ---------------------------------------------------------------- briques
static func _c4(c: Color, a: float = -1.0) -> Color:
	return Color(c.r * 0.25, c.g * 0.25, c.b * 0.25, c.a if a < 0.0 else a)

func _p(pool: FxPool, pos: Vector3, vel: Vector3, life: float, grav: float, s0: float, s1: float, drag: float, col: Color, endc: Color, prm: float = 0.0, delay: float = 0.0) -> void:
	if prm == 0.0:
		prm = -randf_range(0.001, 1.0)
	var e := _c4(endc)
	pool.put(pos, vel, Vector3(now + delay, life, grav), Vector3(s0, s1, drag), _c4(col), Color(e.r, e.g, e.b, prm))

func _wave(pos: Vector3, col: Color, s0: float, s1: float, life: float, width: float = 0.12, style: int = 0, fill: float = 0.0, delay: float = 0.0, spin: float = 0.0) -> void:
	decal.put(Vector3(pos.x, 0.06, pos.z), UP, Vector3(now + delay, life, float(style)), Vector3(s0, s1, width), _c4(col), Color(fill, spin, randf(), 0.0))

## Segment lumineux plein de `a` à `b` (par image).
func _seg(a: Vector3, b: Vector3, col: Color, w: float) -> void:
	if _seg_n >= seg.cap:
		return
	seg.put_at(_seg_n, b, b - a, Vector3(now, 1.0, 0.0), Vector3(w, w, 0.0), _c4(col), Color(0, 0, 0, 1.0))
	_seg_n += 1

## Traînée de `pos` vers l'arrière, longueur `vel` × `len_s` (par image).
func _tail(pos: Vector3, vel: Vector3, col: Color, w: float, len_s: float, endc: Color = Color(-1, 0, 0)) -> void:
	if _tail_n >= tail.cap:
		return
	if endc.r < 0.0:
		endc = col
	var e := _c4(endc)
	tail.put_at(_tail_n, pos, vel, Vector3(now, 1.0, 0.0), Vector3(w, w, 0.0), _c4(col), Color(e.r, e.g, e.b, maxf(len_s, 0.001)))
	_tail_n += 1

## Point lumineux (par image).
func _dot(pos: Vector3, col: Color, size: float) -> void:
	if _dot_n >= dot.cap:
		return
	dot.put_at(_dot_n, pos, Vector3.ZERO, Vector3(now, 1.0, 0.0), Vector3(size, size, 0.0), _c4(col), Color(0, 0, 0, -0.5))
	_dot_n += 1

func _sparks(pos: Vector3, dir: Vector3, n: int, spd: float, spread: float, col: Color, endc: Color, life: float, grav: float = 9.0, size: float = 0.07) -> void:
	for i in range(n):
		var r := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		var v := (dir + r * spread).normalized() * spd * randf_range(0.45, 1.0)
		_p(glow, pos, v, life * randf_range(0.55, 1.0), grav, size, size * 0.4, 2.5, col, endc, 0.035)

## Ligne brisée de foudre entre deux points (re-tirée à chaque image : elle crépite).
func _bolt(a: Vector3, b: Vector3, col: Color, w: float, parts: int = 5, amp: float = 0.22) -> void:
	var d := b - a
	var side := d.cross(UP).normalized()
	if side.length() < 0.01:
		side = Vector3.RIGHT
	var prev := a
	for i in range(1, parts + 1):
		var f := float(i) / parts
		var q := a + d * f
		if i < parts:
			q += side * randf_range(-amp, amp) + UP * randf_range(-amp, amp) * 0.4
		_seg(prev, q, col, w)
		_seg(prev, q, Color(1, 1, 1), w * 0.35)
		prev = q

# ---------------------------------------------------------------- image
func tick(dt: float) -> void:
	if arena.room != _room or arena.elapsed < _el:
		clear()
	_room = arena.room
	_el = arena.elapsed
	now += dt
	_sync_time()
	_seg_n = 0
	_tail_n = 0
	_dot_n = 0
	_emit = 0
	_tick_status(dt)
	_tick_bullets(dt)
	_tick_ground(dt)
	_tick_machines(dt)
	_tick_sky(dt)
	_tick_dash()
	_tick_aura()
	seg.show(_seg_n)
	tail.show(_tail_n)
	dot.show(_dot_n)

var _room := -1
var _el := 0.0
var _idle := false

## Hors partie (Relais) : rien ne reste affiché.
func _process(_dt: float) -> void:
	if view != null and not view.active:
		if not _idle:
			_idle = true
			clear()
			_aura.visible = false
	else:
		_idle = false

## Ennemis en feu, givrés, gelés, empoisonnés.
func _tick_status(dt: float) -> void:
	var ice: MultiMesh = _mm["ice"]
	var ni := 0
	# les flammes et bulles partent du devant du modèle (côté caméra), sinon la coque les cache
	var cf := Vector3(0, -0.83, -0.56)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		cf = -cam.global_transform.basis.z
	for e in arena.enemies:
		if e.dead:
			continue
		var r: float = e.radius * K
		var top := (0.3 + r * 2.0) * 1.5  # haut du modèle, à peu près
		var p := p3(e.position) - cf * (r + 0.2)
		var h := top * 0.55
		if e.burn_t > 0.0:
			# halo orange qui vacille : on lit « en feu » même de loin
			_dot(p + UP * h * 1.2, Color(1.0, 0.42, 0.1) * (0.75 + 0.2 * sin(now * 23.0 + r * 40.0)), 1.5 + r * 3.0)
		if e.burn_t > 0.0 and _emit < MAX_EMIT and randf() < dt * 26.0:
			_emit += 1
			var off := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * r * 0.6
			var hot := Color(2.0, 1.15, 0.4).lerp(Color(1.6, 0.5, 0.15), randf())
			_p(fire, p + off + UP * h * randf_range(0.6, 1.6), Vector3(randf_range(-0.2, 0.2), randf_range(0.6, 1.2), randf_range(-0.2, 0.2)), randf_range(0.35, 0.55), 0.0, 0.38 + r * 1.1, 0.08, 1.0, Color(hot, 0.95), Color(0.6, 0.12, 0.04))
			if randf() < 0.4:
				_p(glow, p + off + UP * h, Vector3(randf_range(-0.4, 0.4), randf_range(1.0, 2.0), randf_range(-0.4, 0.4)), 0.6, -0.5, 0.07, 0.02, 1.0, Color(1.0, 0.7, 0.3), Color(0.9, 0.2, 0.05), 0.02)
		if e.freeze_t > 0.0:
			if ni < ice.instance_count:
				# bloc de glace à la taille du modèle (les gros ennemis sont plus hauts que leur rayon)
				var s := 0.12 + r * 1.8
				var hh := 0.3 + r * 2.0
				var bs := Basis.from_euler(Vector3(0.0, float(e.get_instance_id() % 7), 0.0)).scaled(Vector3(s, hh, s))
				ice.set_instance_transform(ni, Transform3D(bs, p3(e.position) + UP * hh * 0.82))
				ice.set_instance_color(ni, Color(1, 1, 1, clampf(e.freeze_t * 3.0, 0.0, 1.0)))
				ni += 1
			if _emit < MAX_EMIT and randf() < dt * 4.0:
				_emit += 1
				_p(glow, p + Vector3(randf_range(-1, 1), randf_range(0.3, 1.2), randf_range(-1, 1)) * r, Vector3.ZERO, 0.35, 0.0, 0.05, 0.3, 0.0, Color(0.9, 1.0, 1.0), ICE)
		elif e.chill_t > 0.0 and _emit < MAX_EMIT and randf() < dt * 6.0:
			_emit += 1
			_p(glow, p + Vector3(randf_range(-1, 1), randf_range(0.2, 1.1), randf_range(-1, 1)) * r, Vector3(0, -0.3, 0), 0.5, 0.0, 0.1, 0.03, 0.5, Color(0.85, 0.97, 1.0), ICE, 0.02)
		if e.poison_t > 0.0:
			_dot(p + UP * h, Color(0.45, 1.0, 0.25) * 0.35, 0.9 + r * 1.8)
		if e.poison_t > 0.0 and _emit < MAX_EMIT and randf() < dt * 8.0:
			_emit += 1
			_p(glow, p + Vector3(randf_range(-0.7, 0.7) * r, h, randf_range(-0.7, 0.7) * r), Vector3(0, 0.9, 0), 0.6, 0.0, 0.08, 0.14, 0.5, Color(0.7, 1.0, 0.4), VENOM)
	ice.visible_instance_count = ni

## Tirs élémentaires : braises derrière les tirs de feu, givre des tirs de glace, crépitement de la foudre.
func _tick_bullets(dt: float) -> void:
	for b in arena.bullets:
		if b.look == 0 or not b.hero_shot:
			continue
		var p := p3(b.position, 0.55)
		var v := Vector3(b.vel.x, 0.0, b.vel.y) * K
		match b.look:
			1:
				if _emit < MAX_EMIT * 2 and randf() < dt * 30.0:
					_emit += 1
					_p(fire, p - v * 0.02, -v * 0.08 + UP * 0.6, 0.22, 0.0, 0.16 * b.radius / 5.0, 0.05, 2.0, Color(2.0, 1.1, 0.35, 0.9), Color(0.7, 0.15, 0.04))
				_tail(p, v, Color(1.0, 0.5, 0.15), 0.16 * b.radius / 5.0, 0.07, Color(0.6, 0.1, 0.02))
			2:
				if _emit < MAX_EMIT * 2 and randf() < dt * 22.0:
					_emit += 1
					_p(glow, p, -v * 0.05 + Vector3(randf_range(-0.5, 0.5), randf_range(-0.2, 0.4), randf_range(-0.5, 0.5)), 0.35, 1.0, 0.06, 0.02, 2.0, Color(0.95, 1.0, 1.0), ICE, -randf())
			4:
				var n := v.normalized()
				var side := n.cross(UP)
				var q := p - n * randf_range(0.05, 0.3)
				_seg(q, q + side * randf_range(-0.25, 0.25) + n * 0.12, SHOCK, 0.05)

## Nuages toxiques, flaques de feu, mines.
func _tick_ground(dt: float) -> void:
	for c in arena.clouds:
		var r: float = c["r"] * K
		var life: float = c["life"]
		var fade := clampf((life - float(c["t"])) / 0.6, 0.0, 1.0)
		if _emit < MAX_EMIT and randf() < dt * (6.0 + r * 3.0) * fade:
			_emit += 1
			var off := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).limit_length(1.0) * r * 0.8
			_p(smoke, p3(c["pos"], 0.15) + off, Vector3(randf_range(-0.15, 0.15), 0.25, randf_range(-0.15, 0.15)), randf_range(0.9, 1.3), 0.0, r * 0.4, r * 0.9, 1.0, Color(0.5, 0.95, 0.3, 0.55), Color(0.25, 0.45, 0.2))
	for f in arena.fires:
		var r2: float = f["r"] * K
		var left: float = float(f["life"]) - float(f["t"])
		if _emit < MAX_EMIT and randf() < dt * 9.0 * clampf(left / 0.6, 0.2, 1.0):
			_emit += 1
			var off2 := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).limit_length(1.0) * r2 * 0.7
			var hot := Color(2.0, 1.2, 0.4).lerp(Color(1.7, 0.55, 0.15), randf())
			_p(fire, p3(f["pos"], 0.1) + off2, Vector3(0, randf_range(0.4, 0.9), 0), randf_range(0.4, 0.65), 0.0, r2 * 0.5, r2 * 0.12, 1.0, Color(hot, 0.95), Color(0.6, 0.12, 0.04))
	var mm: MultiMesh = _mm["mine"]
	var n := 0
	for m in arena.mines:
		if n >= mm.instance_count:
			break
		var p := p3(m["pos"], 0.04)
		mm.set_instance_transform(n, Transform3D(Basis(UP, float(m["t"]) * 0.6), p))
		mm.set_instance_color(n, Color("#3A4466"))
		n += 1
		var armed: bool = m["t"] > 0.4
		var blink := fmod(float(m["t"]), 0.6) < 0.18
		_dot(p + UP * 0.1, Color(1.0, 0.35, 0.2) if armed else Color(1.0, 0.8, 0.3), 0.42 if (armed and blink) else 0.22)
	mm.visible_instance_count = n

## Lames orbitales, missiles, scies, mini-drones.
func _tick_machines(dt: float) -> void:
	var bm: MultiMesh = _mm["blade"]
	var nb := 0
	var hp := p3(hero2d.position)
	for q in arena.blade_pos:
		if nb >= bm.instance_count:
			break
		var p := p3(q, 0.55)
		var rad := (p - hp)
		rad.y = 0.0
		var tang := rad.normalized().cross(UP)
		var yaw := atan2(tang.x, tang.z)
		var bs := Basis(UP, yaw) * Basis(Vector3.RIGHT, 0.25)
		bm.set_instance_transform(nb, Transform3D(bs.scaled(Vector3.ONE * 1.25), p))
		bm.set_instance_color(nb, Color(0.85, 1.0, 0.9))
		nb += 1
		_dot(p, Color(MACH, 0.9), 0.55)
		_tail(p, tang * 6.0, Color(0.7, 1.0, 0.6), 0.16, 0.07, Color(0.2, 0.6, 0.3))
	bm.visible_instance_count = nb
	var mm: MultiMesh = _mm["missile"]
	var n := 0
	for m in arena.missiles:
		if n >= mm.instance_count:
			break
		var p := p3(m["pos"], 0.75)
		var v := Vector3(m["vel"].x, 0.0, m["vel"].y) * K
		var d := v.normalized() if v.length() > 0.01 else Vector3.FORWARD
		var bs := Basis.looking_at(d, UP) * Basis(Vector3.RIGHT, PI * 0.5)
		mm.set_instance_transform(n, Transform3D(bs, p))
		mm.set_instance_color(n, Color(0.95, 0.95, 1.0))
		n += 1
		_dot(p - d * 0.2, Color(1.0, 0.6, 0.2), 0.45)
		_tail(p - d * 0.2, v, Color(1.0, 0.55, 0.2), 0.14, 0.12, Color(0.5, 0.15, 0.05))
		if _emit < MAX_EMIT * 2 and randf() < dt * 25.0:
			_emit += 1
			_p(smoke, p - d * 0.25, Vector3(randf_range(-0.2, 0.2), 0.3, randf_range(-0.2, 0.2)), 0.6, 0.0, 0.08, 0.28, 1.0, Color(0.75, 0.72, 0.7, 0.6), Color(0.45, 0.45, 0.55))
	mm.visible_instance_count = n
	var sm: MultiMesh = _mm["saw"]
	n = 0
	for s in arena.saws:
		if n >= sm.instance_count:
			break
		var p := p3(s["pos"], 0.5)
		sm.set_instance_transform(n, Transform3D(Basis(UP, float(s["t"]) * 22.0).scaled(Vector3.ONE * 1.2), p))
		sm.set_instance_color(n, Color(0.86, 0.9, 0.98))
		n += 1
		_dot(p, Color(MACH, 0.8), 0.8)
		_tail(p, Vector3(s["vel"].x, 0.0, s["vel"].y) * K, Color(0.6, 1.0, 0.5), 0.3, 0.06, Color(0.1, 0.4, 0.2))
	sm.visible_instance_count = n
	var mi: MultiMesh = _mm["mini"]
	n = 0
	for m in arena.minis:
		if n >= mi.instance_count:
			break
		var p := p3(m["pos"], 0.7 + sin(float(m["t"]) * 12.0) * 0.05)
		mi.set_instance_transform(n, Transform3D(Basis(), p))
		mi.set_instance_color(n, Color(0.92, 0.95, 1.0))
		n += 1
		_dot(p, Color(VENOM, 0.9), 0.4)
		_tail(p, Vector3(m["vel"].x, 0.0, m["vel"].y) * K, Color(0.6, 1.0, 0.4), 0.1, 0.08)
	mi.visible_instance_count = n

## Arcs de foudre, foudre du ciel, météores qui tombent.
func _tick_sky(dt: float) -> void:
	var i := 0
	while i < _arcs.size():
		var a: Dictionary = _arcs[i]
		a["t"] += dt
		if a["t"] >= a["life"]:
			_arcs.remove_at(i)
			continue
		var pts: Array = a["pts"]
		var k: float = 1.0 - a["t"] / a["life"]
		var col: Color = a["col"]
		for j in range(pts.size() - 1):
			_bolt(pts[j], pts[j + 1], Color(col, 1.0) * (0.7 + 0.6 * k), 0.2 * (0.5 + 0.5 * k), 5, 0.22)
		i += 1
	i = 0
	while i < _strikes.size():
		var s: Dictionary = _strikes[i]
		s["t"] += dt
		if s["t"] >= 0.22:
			_strikes.remove_at(i)
			continue
		var g: Vector3 = s["pos"]
		_bolt(g + Vector3(-1.2, 9.0, -2.5), g + UP * 0.3, SHOCK, 0.22, 9, 0.5)
		_dot(g + UP * 0.3, Color(1.0, 1.0, 0.8), 2.2)
		i += 1
	i = 0
	while i < _meteors.size():
		var m: Dictionary = _meteors[i]
		m["t"] += dt
		var f: float = m["t"] / m["delay"]
		if f >= 1.0:
			_meteors.remove_at(i)
			continue
		var g2: Vector3 = m["pos"]
		var from := g2 + Vector3(-3.5, 11.0, -4.0)
		var p := from.lerp(g2 + UP * 0.3, f * f)
		var v: Vector3 = (g2 - from) * 2.0 * f / float(m["delay"])
		_dot(p, Color(1.0, 0.7, 0.3), 1.1)
		_dot(p, Color(1.0, 1.0, 0.85), 0.5)
		_tail(p, v, Color(1.0, 0.5, 0.15), 0.6, 0.12, Color(0.6, 0.1, 0.02))
		if _emit < MAX_EMIT and randf() < 0.7:
			_emit += 1
			_p(fire, p, -v * 0.05, 0.3, 0.0, 0.5, 0.2, 2.0, Color(2.0, 1.1, 0.35, 0.9), Color(0.6, 0.12, 0.04))
		i += 1

## Ruée : traînée de lumière de son départ jusqu'à Jo, silhouettes lumineuses le long du trajet.
func _tick_dash() -> void:
	if _dash.is_empty():
		return
	var hp := p3(hero2d.position, 0.6)
	var from: Vector3 = _dash["from"]
	var left := float(_dash["end_t"]) - now if _dash.has("end_t") else 0.2
	if left <= 0.0:
		_dash = {}
		return
	var k := clampf(left / 0.2, 0.0, 1.0)
	var to: Vector3 = _dash.get("to", hp)
	var d := to - from
	var L := d.length()
	if L < 0.05:
		return
	_tail(to, d / 0.1, Color(0.6, 1.0, 0.95) * k, 0.9 * k, 0.1, Color(0.1, 0.4, 0.5))
	_tail(to, d / 0.1, Color(1, 1, 1) * k, 0.3 * k, 0.1)
	var n := int(L / 0.7)
	for j in range(1, n + 1):
		var q := from + d * (float(j) / (n + 1))
		_dot(q, Color(0.4, 1.0, 0.9) * (0.35 + 0.4 * k), 1.0)

func _tick_aura() -> void:
	var au: int = hero2d.lv("aura")
	_aura.visible = au > 0
	if au <= 0:
		return
	var r: float = arena.aura_radius() * K * 2.0
	_aura.position = p3(hero2d.position, 0.05)
	_aura.scale = Vector3(r, 1, r)
	_aura.rotation.y = now * 0.4
	_aura_mat.set_shader_parameter("color", Color(ICE, 0.13 + 0.04 * sin(now * 3.0)))
	if _emit < MAX_EMIT and randf() < 0.5:
		_emit += 1
		var a := randf() * TAU
		var q := p3(hero2d.position) + Vector3(cos(a), 0, sin(a)) * r * 0.5 * sqrt(randf())
		_p(glow, q + UP * 0.1, Vector3(0, 0.5, 0), 0.8, 0.0, 0.08, 0.02, 0.5, Color(0.9, 1.0, 1.0), ICE, 0.02)

# ---------------------------------------------------------------- événements de la simulation
func _on_event(kind: String, info: Dictionary) -> void:
	if not view.active:
		return
	match kind:
		"arc":
			var pts: Array = []
			for q in info["pts"]:
				pts.append(p3(q, 0.75))
			_arcs.append({"pts": pts, "t": 0.0, "life": 0.3, "col": info["col"]})
			for q in pts:
				_p(glow, q, Vector3.ZERO, 0.12, 0.0, 0.7, 1.0, 0.0, Color(1, 1, 0.8), info["col"])
		"strike":
			var g := p3(info["pos"])
			_strikes.append({"pos": g, "t": 0.0})
			_p(glow, g + UP * 0.4, Vector3.ZERO, 0.2, 0.0, 2.5, 3.5, 0.0, Color(1, 1, 0.85), SHOCK)
			_wave(g, SHOCK, 0.4, 3.0, 0.3, 0.15, 0, 0.3)
			_sparks(g + UP * 0.3, UP, 14, 9.0, 0.9, Color(1, 1, 0.9), SHOCK, 0.4)
			view._flash_light(g + UP * 1.5, Color(1.0, 0.95, 0.5), 4.0, 7.0)
			view.add_shake(0.15)
		"blast":
			_blast(info)
		"pulse":
			var g2 := p3(info["pos"])
			var d := float(info["r"]) * K * 2.0
			var col: Color = info["col"]
			_wave(g2, col, 0.4, d, 0.4, 0.1, 0, 0.25)
			_wave(g2, col.lerp(Color.WHITE, 0.4), 0.3, d * 1.05, 0.28, 0.05)
			decal.put(g2 + UP * 0.07, UP, Vector3(now, 0.45, 1.0), Vector3(d * 0.4, d, 0.1), _c4(col), Color(0, 0, randf(), 0))
			_sparks(g2 + UP * 0.4, UP * 0.2, 16, d * 2.5, 1.0, Color(1, 1, 1), col, 0.35, 2.0)
		"meteor_call":
			var g3 := p3(info["pos"])
			var dl: float = info["delay"]
			_meteors.append({"pos": g3, "t": 0.0, "delay": dl})
			_wave(g3, Color(1.0, 0.35, 0.15), 3.9, 3.9, dl, 0.06, 0, 0.18)
			_wave(g3, Color(1.0, 0.5, 0.2), 0.3, 3.9, dl, 0.08)
		"dash":
			var f := p3(info["from"], 0.6)
			_dash = {"from": f, "end_t": now + 10.0}
			var dir := Vector3(info["dir"].x, 0.0, info["dir"].y)
			_wave(f, Color(0.5, 1.0, 0.95), 0.3, 1.8, 0.25, 0.14)
			_sparks(f, -dir + UP * 0.3, 10, 7.0, 0.5, Color(1, 1, 1), Color(0.4, 1.0, 0.9), 0.3)
		"dash_end":
			if not _dash.is_empty():
				_dash["end_t"] = now + 0.2
				_dash["to"] = p3(info["pos"], 0.6)
			var e := p3(info["pos"])
			_wave(e, Color(0.5, 1.0, 0.95), 0.4, 1.6, 0.22, 0.12)
		"freeze":
			var g4 := p3(info["pos"], 0.6)
			var rr: float = float(info["r"]) * K
			_sparks(g4, UP, 8, 4.0, 1.0, Color(1, 1, 1), ICE, 0.35, 4.0, 0.06)
			_wave(g4, ICE, rr, rr * 3.0, 0.3, 0.14)
		"cloud":
			var g5 := p3(info["pos"])
			var d5 := float(info["r"]) * K * 2.0
			_wave(g5, Color(0.45, 0.95, 0.3), d5 * 0.6, d5, info["life"], 0.0, 2, 0.0)
			_wave(g5, VENOM, d5 * 0.3, d5, 0.35, 0.1)
		"fire":
			var g6 := p3(info["pos"])
			var d6 := float(info["r"]) * K * 2.0
			_wave(g6, Color(1.0, 0.45, 0.12), d6 * 0.8, d6, info["life"], 0.0, 2, 0.0)
			view.fxs.burn(g6, d6 * 0.8, float(info["life"]) + 1.0, 1.0, Color(1.0, 0.45, 0.12), 0.0, 0.4)
		"revive":
			var g7 := p3(info["pos"])
			view.fxs.power_burst(g7, GOLD, Color(1.0, 0.95, 0.7))
			view.fxs.column(g7, GOLD, 7.0, 0.9, 2.2)
			view._flash_light(g7 + UP * 1.5, GOLD, 5.0, 8.0)
			view.add_shake(0.5)
		"evolve":
			var g8 := p3(info["pos"])
			view.fxs.power_burst(g8, GOLD, Color(1.0, 0.95, 0.7))
			view.fxs.column(g8, GOLD, 9.0, 1.1, 2.6)
			_wave(g8, GOLD, 0.5, 9.0, 0.7, 0.06)
			_sparks(g8 + UP * 0.5, UP, 30, 10.0, 0.8, Color(1, 1, 0.9), GOLD, 0.8, 6.0, 0.09)
			view._flash_light(g8 + UP * 1.5, GOLD, 5.0, 9.0)
			view.add_shake(0.4)

## Explosions des pouvoirs : taille de la zone de dégâts, couleur et poids selon la source.
func _blast(info: Dictionary) -> void:
	var g := p3(info["pos"])
	var r: float = float(info["r"]) * K
	var col: Color = info["col"]
	var fx = view.fxs
	match String(info["kind"]):
		"boom":
			fx.explosion(g, r * 0.5, col, false, 0.0, false)
		"pyro":
			fx.explosion(g, r * 0.45, col, true, 0.0, true)
			_wave(g, Color(1.0, 0.5, 0.15), r * 0.4, r * 2.0, 0.35, 0.12, 0, 0.3)
		"meteor", "comete":
			fx.explosion(g, r * 0.6, col, true, 0.0, true)
			_wave(g, Color(1.0, 0.85, 0.5), r * 0.5, r * 2.2, 0.4, 0.08)
			view._flash_light(g + UP * 1.2, Color(1.0, 0.6, 0.3), 4.5, 8.0)
			view.add_shake(0.45)
		"dashboom":
			fx.explosion(g, r * 0.5, col, false, 0.0, true)
			view.add_shake(0.25)
		"missile", "mine", "mini":
			fx.explosion(g, r * 0.45, col, false, 0.0, false, 0.4)
		"shatter":
			fx.flash(g + UP * 0.6, Color(0.9, 1.0, 1.0), r * 1.4, 0.12)
			fx.chunks(g + UP * 0.5, [Color("#E8FBFF"), Color("#9FDCFF"), Color("#5AA8FF")], 12, 6.0, Vector3.ZERO, 0.13, 0.6, 0.0, true)
			_wave(g, ICE, r * 0.4, r * 2.0, 0.35, 0.14, 1)
			_sparks(g + UP * 0.5, UP, 14, 8.0, 1.0, Color(1, 1, 1), ICE, 0.4)
		"thorns":
			_sparks(g + UP * 0.5, UP * 0.3, 8, 6.0, 1.0, Color(0.9, 0.95, 1.0), SHIELD, 0.25)
			_wave(g, SHIELD, 0.2, 1.4, 0.2, 0.15)
		_:
			fx.explosion(g, r * 0.5, col, false, 0.0, false)
