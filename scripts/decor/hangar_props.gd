extends RefCounted
## Nébuleuse 7 — obstacles (fret de la compagnie HÉLIX FRET posé sur les rectangles bloquants de la simulation)
## et accessoires non bloquants au ras des murs ouest, est et sud. Appelé par view3d.gd avec la vue `v`.
## Modèles sculptés en SDF : tools/decor/props.py -> assets/decor/props/*.glb (couleurs par sommet).

const Models = preload("res://scripts/models.gd")
const PR := "res://assets/decor/props/"
const HMAX := 0.85  # hauteur maximale d'un obstacle (Jo doit rester visible derrière, caméra à 56°)

## Modèles : emprise réelle (x, hauteur, z) en mètres, variantes de teinte.
const CATALOG := {
	"caisse_s_a": Vector3(0.6, 0.45, 0.6), "caisse_s_b": Vector3(0.6, 0.45, 0.6), "caisse_s_c": Vector3(0.6, 0.45, 0.6),
	"caisse_m_a": Vector3(1.0, 0.6, 0.75), "caisse_m_b": Vector3(1.0, 0.6, 0.75), "caisse_m_c": Vector3(1.0, 0.6, 0.75),
	"caisse_l_a": Vector3(1.35, 0.7, 0.9), "caisse_l_b": Vector3(1.35, 0.7, 0.9),
	"caisse_t_a": Vector3(1.0, 0.8, 1.0), "caisse_t_b": Vector3(1.0, 0.8, 1.0),
	"caisse_longue_a": Vector3(1.35, 0.5, 0.55), "caisse_longue_b": Vector3(1.35, 0.5, 0.55),
	"bachee_a": Vector3(1.2, 0.78, 1.0), "bachee_b": Vector3(1.2, 0.78, 1.0),
	"danger": Vector3(0.9, 0.8, 0.7),
	"cellule_a": Vector3(0.56, 0.86, 0.56), "cellule_b": Vector3(0.56, 0.86, 0.56),
	"palette_a": Vector3(1.2, 0.6, 0.95), "palette_b": Vector3(1.2, 0.6, 0.95),
	"bobine": Vector3(0.56, 0.8, 0.8), "servante": Vector3(0.72, 0.82, 0.46), "robot": Vector3(0.6, 0.72, 0.6),
	"trappe": Vector3(1.1, 0.03, 0.84), "cables": Vector3(3.0, 0.05, 0.3), "plot": Vector3(0.34, 0.46, 0.34),
}
## Familles utilisables en obstacle : variantes, poids (préférence), forme ronde.
const BLOCK := {
	"caisse_s": [["caisse_s_a", "caisse_s_b", "caisse_s_c"], 0.10],
	"caisse_m": [["caisse_m_a", "caisse_m_b", "caisse_m_c"], 0.0],
	"caisse_l": [["caisse_l_a", "caisse_l_b"], 0.0],
	"caisse_t": [["caisse_t_a", "caisse_t_b"], 0.02],
	"caisse_longue": [["caisse_longue_a", "caisse_longue_b"], 0.06],
	"bachee": [["bachee_a", "bachee_b"], 0.12],
	"danger": [["danger"], 0.08],
	"palette": [["palette_a", "palette_b"], 0.03],
	"cellule": [["cellule_a", "cellule_b"], 0.12],
}

static var _parts := {}
static var _body: ShaderMaterial
static var _glows := {}
static var _decal: StandardMaterial3D
static var tris := 0  # triangles posés (contrôle du budget)

# ---------------------------------------------------------------- matériaux, maillages
## Peinture des objets de fret : couleur par sommet (occlusion et salissure cuites), marbrures et taches
## de salissure en bruit projeté (coordonnées du monde : chaque caisse diffère), éclats de métal nu sur
## les arêtes (alpha des sommets = facteur d'arête, découpé par un bruit fin).
const PROP_SHADER := """
shader_type spatial;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 bare = vec3(0.5, 0.52, 0.55);
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
vec3 tri(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(noise, p.zy).rgb * w.x + texture(noise, p.xz).rgb * w.y + texture(noise, p.xy).rgb * w.z;
}
void fragment() {
	vec3 c = COLOR.rgb;  // le rendu Compatibility éclaire en espace sRGB : couleurs prises telles quelles
	vec3 nf = tri(wp * 1.7, wn);
	vec3 nl = tri(wp * 0.31 + vec3(0.37), wn);
	float e = COLOR.a;
	float chip = smoothstep(0.6, 0.66, nf.r * 0.7 + e * 0.62 + nl.g * 0.12) * step(0.04, e);
	c *= 0.9 + 0.2 * mix(nf.g, nl.g, 0.5);
	float grime = (1.0 - smoothstep(0.0, 0.3, wp.y)) * smoothstep(0.35, 0.7, nl.b);
	c *= 1.0 - 0.28 * grime;
	ALBEDO = mix(c, bare * (0.75 + 0.35 * nf.b), chip);
	ROUGHNESS = mix(0.74, 0.4, chip);
	SPECULAR = mix(0.4, 0.7, chip);
	RIM = 0.22;
	RIM_TINT = 0.4;
}
"""

static func body_mat() -> Material:
	if _body == null:
		var sh := Shader.new()
		sh.code = PROP_SHADER
		_body = ShaderMaterial.new()
		_body.shader = sh
		_body.set_shader_parameter("noise", load(PR + "noise.png"))
	return _body

## Marquages (logo HÉLIX FRET, pochoirs, étiquettes, bandes de danger) : quads texturés par la planche decals.png.
static func decal_mat() -> StandardMaterial3D:
	if _decal == null:
		_decal = StandardMaterial3D.new()
		_decal.albedo_texture = load(PR + "decals.png")
		_decal.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_decal.alpha_scissor_threshold = 0.45
		_decal.roughness = 0.8
		_decal.metallic_specular = 0.3
		_decal.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _decal

static func glow_mat(energy: float) -> StandardMaterial3D:
	var key := "%.2f" % energy
	if not _glows.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.albedo_color = Color(energy, energy, energy)
		_glows[key] = m
	return _glows[key]

## Maillages d'un modèle sculpté, avec le matériau à couleurs par sommet (ou lumineux pour « *_glow »).
static func parts(name: String) -> Array:
	if _parts.has(name):
		return _parts[name]
	var out := []
	var n: Node3D = Models.scene(PR + name + ".glb").instantiate()
	_collect(n, n.transform, out)
	n.free()
	_parts[name] = out
	return out

static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m: Mesh = (n as MeshInstance3D).mesh.duplicate()
		var nm := String(n.name)
		var mat: Material = glow_mat(2.2) if "_glow" in nm else (decal_mat() if "_decal" in nm else body_mat())
		for i in range(m.get_surface_count()):
			m.surface_set_material(i, mat)
		out.append([m, xf])
	for c in n.get_children():
		if c is Node3D:
			_collect(c, xf * (c as Node3D).transform, out)

## Pose un modèle dans le lot statique de la vue (fusionné par matériau, voir view3d._flush_batch).
static func put(v: Node, name: String, pos: Vector3, rot: float, scl: Vector3 = Vector3.ONE) -> void:
	var xf := Transform3D(Basis(Vector3.UP, rot) * Basis.from_scale(scl), pos)
	for part in parts(name):
		var m: Mesh = part[0]
		if not v._batch.has(m):
			v._batch[m] = []
		(v._batch[m] as Array).append(xf * (part[1] as Transform3D))
		for i in range(m.get_surface_count()):
			tris += (m.surface_get_array_index_len(i) / 3) if m.surface_get_format(i) & Mesh.ARRAY_FORMAT_INDEX else 0

# ---------------------------------------------------------------- salle
static func build(v: Node, rng: RandomNumberGenerator) -> void:
	tris = 0
	for o in v.arena.obstacles:
		crate_block(v, o, rng)
	var t_obst := tris
	_wall_props(v, rng)
	if "--props-stats" in OS.get_cmdline_user_args():
		print("hangar_props : obstacles %d triangles, accessoires %d" % [t_obst, tris - t_obst])

## Une caisse de fret de taille donnée (base au sol, rotation) : le modèle sculpté le plus proche, mis
## à l'échelle. Sert au Relais (view3d._crate).
static func crate(v: Node, base: Vector3, size: Vector3, rot: float, rng: RandomNumberGenerator) -> void:
	var best := ""
	var bc := INF
	for fam in ["caisse_s", "caisse_m", "caisse_l", "caisse_t"]:
		var d: Vector3 = CATALOG[BLOCK[fam][0][0]]
		var c := absf(log(size.x / d.x)) + absf(log(size.y / d.y)) + absf(log(size.z / d.z))
		if c < bc:
			bc = c
			best = fam
	var vars: Array = BLOCK[best][0]
	var nm: String = vars[rng.randi() % vars.size()]
	var d: Vector3 = CATALOG[nm]
	put(v, nm, base, rot, Vector3(size.x / d.x, size.y / d.y, size.z / d.z))

# ---------------------------------------------------------------- obstacles
const ITEM := 0.4  # coût d'un objet de plus dans un bloc (moins d'objets, plus grands : triangles, lisibilité)
static var _memo := {}
static var _jit := {}  # préférence aléatoire par famille, tirée pour chaque bloc
static var _last := ""  # dernier modèle posé (variantes alternées)

## Recouvre exactement le rectangle bloquant (px) d'un assemblage de fret : découpe guillotine (au plus
## quatre cellules, choisie par recherche exhaustive) dont chaque cellule reçoit le modèle d'emprise réelle
## la plus proche (légère mise à l'échelle), un fût d'énergie en coin une fois sur deux, une petite caisse
## posée sur les modèles bas ; liseré sombre au sol qui marque l'emprise.
static func crate_block(v: Node, o: Rect2, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = v.p3(o.get_center())
	var sx: float = o.size.x * v.K
	var sz: float = o.size.y * v.K
	_memo.clear()
	for fam in BLOCK.keys():
		_jit[fam] = rng.randf() * 0.14
	var cells := []
	var r := Rect2(-sx * 0.5, -sz * 0.5, sx, sz)
	if maxf(sx, sz) >= 1.55 and minf(sx, sz) >= 1.0 and rng.randf() < 0.45:
		# fût en coin, côté caméra (+z) : bande de la largeur du fût le long du petit côté
		var w := rng.randf_range(0.58, 0.64)
		var at_end := rng.randf() < 0.5
		if sx >= sz:
			var strip := Rect2(r.position.x + (sx - w if at_end else 0.0), r.position.y, w, sz)
			cells.append([Rect2(strip.position.x, strip.end.y - w, w, w), "cellule"])
			_emit(Rect2(strip.position.x, strip.position.y, w, sz - w), _solve(Vector2(w, sz - w), 1)[1], cells, rng)
			var rest := Rect2(r.position.x + (0.0 if at_end else w), r.position.y, sx - w, sz)
			_emit(rest, _solve(rest.size, 2)[1], cells, rng)
		else:
			var strip := Rect2(r.position.x, r.end.y - w, sx, w)
			cells.append([Rect2(strip.position.x + (sx - w if at_end else 0.0), strip.position.y, w, w), "cellule"])
			_emit(Rect2(strip.position.x + (0.0 if at_end else w), strip.position.y, sx - w, w), _solve(Vector2(sx - w, w), 1)[1], cells, rng)
			var rest := Rect2(r.position.x, r.position.y, sx, sz - w)
			_emit(rest, _solve(rest.size, 2)[1], cells, rng)
	else:
		_emit(r, _solve(r.size, 2)[1], cells, rng)
	for cell in cells:
		_place(v, c, cell[0], cell[1], rng)
	if "--props-stats" in OS.get_cmdline_user_args():
		var desc := []
		for cell in cells:
			desc.append("%s %.2fx%.2f" % [cell[1], (cell[0] as Rect2).size.x, (cell[0] as Rect2).size.y])
		print("bloc ", o, " : ", ", ".join(desc))
	# liseré au sol : socle sombre et filet ambre éteint autour de l'emprise
	v._bbox("obst_socle", Models.toon(Color("#1A2034"), 0.0), c + Vector3(0, 0.006, 0), Vector3(sx + 0.1, 0.012, sz + 0.1))
	var line := Models.toon(Color("#B07A3A"), 0.0, Color("#B07A3A"), 0.15)
	for s in [-1.0, 1.0]:
		v._bbox("obst_filet", line, c + Vector3(0, 0.014, s * (sz * 0.5 + 0.035)), Vector3(sx + 0.1, 0.004, 0.022))
		v._bbox("obst_filet", line, c + Vector3(s * (sx * 0.5 + 0.035), 0.014, 0), Vector3(0.022, 0.004, sz + 0.1))

## Meilleure famille pour une cellule (taille en m) : [famille, coût] ou [] si rien ne va.
static func _fit(size: Vector2, lo: float = 0.82, hi: float = 1.22) -> Array:
	var best := []
	var bc := INF
	for fam in BLOCK.keys():
		var d: Vector3 = CATALOG[BLOCK[fam][0][0]]
		for turn in [false, true]:
			var kx := size.x / (d.z if turn else d.x)
			var kz := size.y / (d.x if turn else d.z)
			if fam == "cellule":
				# ronde : cellule à peu près carrée seulement
				if turn or absf(size.x - size.y) > 0.12:
					continue
				kx = minf(kx, kz)
				kz = kx
			if kx < lo or kx > hi or kz < lo or kz > hi:
				continue
			var cost := absf(log(kx)) + absf(log(kz)) + float(BLOCK[fam][1]) + float(_jit.get(fam, 0.0)) + (0.03 if turn else 0.0)
			if cost < bc:
				bc = cost
				best = [fam, cost]
	return best

## Découpe optimale d'une cellule : [coût, plan], plan = ["fit", famille] ou ["cut", selon_x, coupe, planA, planB].
static func _solve(size: Vector2, depth: int) -> Array:
	var key := "%d,%d,%d" % [roundi(size.x * 50.0), roundi(size.y * 50.0), depth]
	if _memo.has(key):
		return _memo[key]
	var best := [INF, []]
	var f := _fit(size)
	if not f.is_empty():
		best = [float(f[1]) + ITEM, ["fit", f[0]]]
	if depth > 0:
		for along_x in [true, false]:
			var L: float = size.x if along_x else size.y
			for cut in _cuts(L):
				var a := Vector2(cut, size.y) if along_x else Vector2(size.x, cut)
				var b := Vector2(L - cut, size.y) if along_x else Vector2(size.x, L - cut)
				var ra := _solve(a, depth - 1)
				if float(ra[0]) >= float(best[0]):
					continue
				var rb := _solve(b, depth - 1)
				var cost := float(ra[0]) + float(rb[0])
				if cost < float(best[0]):
					best = [cost, ["cut", along_x, cut, ra[1], rb[1]]]
	if best[1].is_empty():
		# rien ne va : le modèle le moins déformé, quitte à l'étirer
		var f2 := _fit(size, 0.5, 2.0)
		best = [5.0, ["fit", f2[0] if not f2.is_empty() else "caisse_m"]]
	_memo[key] = best
	return best

static func _cuts(L: float) -> Array:
	var out := []
	for l in [0.58, 0.6, 0.7, 0.75, 0.9, 0.95, 1.0, 1.2, 1.35]:
		for k in [0.93, 1.07]:
			var cut: float = l * k
			if cut >= 0.5 and L - cut >= 0.5:
				out.append(cut)
	return out

## Déroule un plan en cellules (le morceau coupé va au début ou à la fin, au hasard).
static func _emit(r: Rect2, plan: Array, out: Array, rng: RandomNumberGenerator) -> void:
	if plan[0] == "fit":
		out.append([r, plan[1]])
		return
	var along_x: bool = plan[1]
	var cut: float = plan[2]
	var L: float = r.size.x if along_x else r.size.y
	var first := cut if rng.randf() < 0.5 else L - cut
	var pa: Array = plan[3] if first == cut else plan[4]
	var pb: Array = plan[4] if first == cut else plan[3]
	if along_x:
		_emit(Rect2(r.position.x, r.position.y, first, r.size.y), pa, out, rng)
		_emit(Rect2(r.position.x + first, r.position.y, L - first, r.size.y), pb, out, rng)
	else:
		_emit(Rect2(r.position.x, r.position.y, r.size.x, first), pa, out, rng)
		_emit(Rect2(r.position.x, r.position.y + first, r.size.x, L - first), pb, out, rng)

## Pose le modèle d'une cellule (repère local du bloc, centre c), avec un joint de quelques centimètres.
static func _place(v: Node, c: Vector3, cell: Rect2, fam: String, rng: RandomNumberGenerator) -> void:
	var vars: Array = BLOCK[fam][0]
	var nm: String = vars[rng.randi() % vars.size()]
	if nm == _last and vars.size() > 1:
		nm = vars[(vars.find(nm) + 1) % vars.size()]  # deux voisines de même teinte : on change
	_last = nm
	var d: Vector3 = CATALOG[nm]
	var size := cell.size - Vector2(0.04, 0.04)
	var turn := false
	if fam != "cellule":
		var a := absf(log(size.x / d.x)) + absf(log(size.y / d.z))
		var b := absf(log(size.x / d.z)) + absf(log(size.y / d.x))
		turn = b < a
	var fx := d.z if turn else d.x
	var fz := d.x if turn else d.z
	var kx := size.x / fx
	var kz := size.y / fz
	if fam == "cellule":
		kx = minf(kx, kz)
		kz = kx
	var ky := clampf((kx + kz) * 0.5, 0.9, 1.08)
	ky = minf(ky, HMAX / d.y)
	var rot := (PI * 0.5 if turn else 0.0) + (PI if rng.randf() < 0.25 else 0.0) + rng.randf_range(-0.012, 0.012)
	if fam == "cellule":
		rot = rng.randf() * TAU
	var pos := c + Vector3(cell.get_center().x, 0, cell.get_center().y)
	var scl := Vector3(kz, ky, kx) if turn else Vector3(kx, ky, kz)
	put(v, nm, pos, rot, scl)
	# petite caisse empilée sur les modèles bas (la pile reste sous HMAX)
	var top := d.y * ky
	if (fam == "caisse_longue" or fam == "caisse_s") and rng.randf() < 0.25:
		var s: Vector3 = CATALOG["caisse_s_a"]
		var k := minf(minf(size.x, size.y) / s.x * 0.8, (HMAX - top) / s.y)
		if k > 0.62:
			var sv: Array = BLOCK["caisse_s"][0]
			var off := Vector3(rng.randf_range(-0.12, 0.12) * maxf(size.x - s.x * k, 0.0), top, rng.randf_range(-0.12, 0.12) * maxf(size.y - s.z * k, 0.0))
			put(v, sv[rng.randi() % sv.size()], pos + off, rot + rng.randf_range(-0.25, 0.25), Vector3.ONE * minf(k, 0.85))

# ---------------------------------------------------------------- accessoires (non bloquants)
## Accessoires au ras des murs ouest, est et sud (à moins de ~0,7 m), ou à plat au sol ; jamais au nord
## de TOP (quai), jamais devant un sas.
static func _wall_props(v: Node, rng: RandomNumberGenerator) -> void:
	var K: float = v.K
	var W: float = v.arena.W * K
	var H: float = v.arena.H * K
	var WALL: float = v.arena.WALL * K
	var xw := WALL + 0.08  # pied du mur ouest
	var xe := W - WALL - 0.08
	var zs := H - WALL - 0.08
	var items := [
		# mur ouest (dos au mur, face vers +x)
		["robot", Vector3(xw + 0.32, 0, 8.2), PI * 0.5 - 0.25],
		["servante", Vector3(xw + 0.25, 0, 9.4), PI * 0.5],
		["cellule_a", Vector3(xw + 0.3, 0, 16.1), 0.4],
		["cellule_b", Vector3(xw + 0.3, 0, 16.75), 1.9],
		["cables", Vector3(xw + 0.2, 0, 15.0), -PI * 0.5],
		# mur est (face vers -x)
		["bobine", Vector3(xe - 0.42, 0, 7.6), -PI * 0.5],
		["caisse_s_b", Vector3(xe - 0.32, 0, 9.0), 0.08],
		["caisse_s_a", Vector3(xe - 0.32, 0.45, 9.02), -0.2],
		["plot", Vector3(xe - 0.55, 0, 9.85), 0.3],
		["cellule_b", Vector3(xe - 0.3, 0, 16.3), 0.7],
		["trappe", Vector3(xe - 0.7, 0, 17.6), PI * 0.5],
		# mur sud (face vers -z, marquages vers la caméra : on montre l'arrière, d'où PI)
		["caisse_longue_a", Vector3(8.0, 0, zs - 0.3), 0.0],
		["caisse_s_c", Vector3(9.05, 0, zs - 0.32), 0.1],
		["bobine", Vector3(12.0, 0, zs - 0.45), 0.0],
		["plot", Vector3(12.8, 0, zs - 0.5), 0.0],
		["cables", Vector3(26.5, 0, zs - 0.2), 0.0],
		["servante", Vector3(29.2, 0, zs - 0.25), 0.0],
		["cellule_a", Vector3(31.0, 0, zs - 0.3), 2.2],
		["trappe", Vector3(23.0, 0, zs - 0.75), 0.0],
	]
	for it in items:
		var p: Vector3 = it[1]
		if p.z < v.arena.TOP * K + 0.4 or _near_pad(v, p, 1.25):
			continue
		put(v, it[0], p, it[2])

static func _near_pad(v: Node, p: Vector3, r: float) -> bool:
	for pd in v.arena.pads:
		var q: Vector3 = v.p3(pd)
		if Vector2(q.x - p.x, q.z - p.z).length() < r:
			return true
	return false
