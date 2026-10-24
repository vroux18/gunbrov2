extends RefCounted
## Monde 2 — Cité Néon : obstacles du toit-terrasse (BOXES) et leur habillage, accessoires non bloquants
## le long des parapets ouest, est et sud ou à plat au sol. Appelé par neon_world.gd (build) avec la vue `v`.
## Modèles sculptés en SDF : tools/decor/neon_props.py -> assets/decor/neon/props/*.glb (couleurs par sommet,
## marquages sur la planche decals.png). Tout le décor statique part dans le lot de la vue (v._batch, fusionné
## par matériau). Les hélices des climatiseurs tournent dans le shader (aucun nœud animé).

const Models = preload("res://scripts/models.gd")
const PR := "res://assets/decor/neon/props/"
const NOISE := "res://assets/decor/props/noise.png"  # bruit de peinture partagé avec Nébuleuse 7
const HMAX := 0.85  # hauteur maximale d'un obstacle (Jo visible derrière, caméra à 56°), sauf contre le bord nord

## Obstacles de l'arène (Rect2 en px ; 1 m = 64 px). Aire de jeu 2400 x 1400, murs 36, quai nord TOP = 250 :
## rien au nord de TOP + 40, rien à moins de 140 px d'un sas, le centre (départ de Jo, 1200 x 825) dégagé.
## Deux éléments plus hauts adossés au bord nord (réservoir sur pieds, kiosque à ramen : 1,6 et 1,8 m, parties
## hautes en retrait du bord pour que Jo reste visible dans la bande de 40 px derrière eux), des îlots de
## machines aux quatre coins, des murets bas autour du centre : couloirs nord-sud et est-ouest, abris.
const BOXES := [
	Rect2(800, 290, 128, 132),    # A : grand réservoir sur pieds (haut, contre le bord nord)
	Rect2(1460, 290, 242, 123),   # B : kiosque à ramen (haut, contre le bord nord)
	Rect2(330, 470, 211, 87),     # C : gros climatiseur et armoire (nord-ouest)
	Rect2(1880, 420, 95, 218),    # D : climatiseur en long et tas de câbles (nord-est)
	Rect2(880, 610, 122, 36),     # E : muret d'armoires électriques
	Rect2(1440, 600, 95, 95),     # F : antenne parabolique
	Rect2(360, 734, 87, 182),     # G : deux réservoirs bas (ouest)
	Rect2(1960, 765, 83, 115),    # H : climatiseur moyen, boîtier, caisse (est)
	Rect2(880, 960, 102, 74),     # I : caisses de livraison PAKKU
	Rect2(1370, 975, 123, 55),    # J : deux distributeurs lumineux
	Rect2(420, 1050, 147, 86),    # K : gros climatiseur (sud-ouest)
	Rect2(1780, 1080, 138, 58),   # L : climatiseur moyen et caisses (sud-est)
]

## Habillage de chaque obstacle (même ordre que BOXES) : [modèle, x, z, rotation (degrés), hauteur de pose],
## en mètres depuis le centre du rectangle (face avant des modèles vers +z, la caméra). Sous chaque obstacle,
## une dalle de béton aux dimensions exactes du rectangle (« socle ») couvre les jours entre les objets.
const DRESS := [
	[["reservoir_haut", 0.0, 0.06, 0.0]],
	[["kiosque", 0.0, -0.095, 0.0]],
	[["clim_l_a", -0.55, 0.0, 0.0], ["boitier_a", 1.15, 0.4, 0.0], ["caisse_s_b", 1.2, -0.37, 90.0]],
	[["clim_l_b", 0.0, -0.6, -90.0], ["tas_cables", 0.045, 1.17, 0.0]],
	[["boitier_a", -0.48, -0.01, 0.0], ["boitier_b", 0.48, -0.01, 0.0]],
	[["parabole", 0.0, 0.0, 0.0]],
	[["reservoir_a", 0.0, -0.77, 20.0], ["reservoir_b", 0.0, 0.71, -35.0]],
	[["clim_m_b", -0.045, -0.47, 0.0], ["boitier_s", -0.36, 0.54, 0.0], ["caisse_s_a", 0.32, 0.45, 90.0]],
	[["caisse_m_a", -0.38, -0.25, 0.0], ["caisse_m_b", -0.37, -0.25, 6.0, 0.415], ["caisse_s_a", 0.47, -0.27, 90.0],
		["carton", 0.45, 0.33, -8.0], ["caisse_s_b", -0.42, 0.32, 0.0]],
	[["distributeur_a", -0.48, -0.045, 0.0], ["distributeur_b", 0.48, -0.045, 0.0]],
	[["clim_l_a", -0.035, 0.0, 0.0]],
	[["clim_m_a", -0.495, -0.015, 0.0], ["caisse_m_b", 0.675, 0.0, 0.0], ["caisse_s_b", 0.66, 0.02, -7.0, 0.415]],
]
const TALL := [0, 1]  # obstacles adossés au bord nord, autorisés au-dessus de HMAX

static var _parts := {}
static var _mats := {}
static var tris := 0  # triangles posés (contrôle du budget)
static var _placed := []  # [indice d'obstacle, maillage, transformation] pour --props-check
static var _flat := {}  # Mesh -> Array[Transform3D] : objets à plat, sans ombre projetée

# ---------------------------------------------------------------- matériaux
## Peinture et plastique usés sous la pluie : couleur par sommet (occlusion cuite), marbrures et salissure en
## bruit projeté dans le monde, éclats de métal nu sur les arêtes (alpha des sommets = facteur d'arête),
## dessus mouillés (plus sombres, brillants : ils prennent les reflets des néons), traînées d'eau sur les
## flancs. `spin` : hélice de ventilateur tournée autour de son moyeu (Y, ou Z si spin_z), une sur huit à l'arrêt.
const BODY_SHADER := """
shader_type spatial;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 bare = vec3(0.44, 0.46, 0.5);
uniform float spin = 0.0;
uniform bool spin_z = false;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	if (spin != 0.0) {
		vec3 o = MODEL_MATRIX[3].xyz;
		float h = fract(sin(dot(o.xz, vec2(12.9898, 78.233))) * 43758.5453);
		float a = h * 6.2832 + TIME * spin * (0.75 + 0.5 * h) * step(0.125, h);
		mat2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
		if (spin_z) {
			VERTEX.xy = r * VERTEX.xy;
			NORMAL.xy = r * NORMAL.xy;
		} else {
			VERTEX.xz = r * VERTEX.xz;
			NORMAL.xz = r * NORMAL.xz;
		}
	}
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
vec3 tri(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(noise, p.zy).rgb * w.x + texture(noise, p.xz).rgb * w.y + texture(noise, p.xy).rgb * w.z;
}
void fragment() {
	vec3 c = COLOR.rgb;
	vec3 nf = tri(wp * 1.7, wn);
	vec3 nl = tri(wp * 0.31 + vec3(0.37), wn);
	float e = COLOR.a;
	float chip = smoothstep(0.6, 0.66, nf.r * 0.7 + e * 0.62 + nl.g * 0.12) * step(0.04, e);
	c *= 0.9 + 0.2 * mix(nf.g, nl.g, 0.5);
	float grime = (1.0 - smoothstep(0.0, 0.3, wp.y)) * smoothstep(0.35, 0.7, nl.b);
	c *= 1.0 - 0.3 * grime;
	float up = smoothstep(0.55, 0.95, wn.y);
	float streak = smoothstep(0.5, 0.78, texture(noise, vec2((wp.x + wp.z) * 2.1, wp.y * 0.3)).g);
	float wet = max(up * (0.55 + 0.45 * smoothstep(0.3, 0.6, nl.g)), (1.0 - up) * streak * 0.6);
	vec3 col = mix(c, bare * (0.75 + 0.35 * nf.b), chip);
	ALBEDO = col * (1.0 - 0.28 * wet);
	ROUGHNESS = mix(mix(0.72, 0.42, chip), 0.2, wet);
	SPECULAR = mix(0.4, 0.62, max(chip, wet));
	RIM = 0.25;
	RIM_TINT = 0.5;
}
"""

## Flaque : miroir sombre (reflet simulé du ciel rose et violet selon l'angle, pas de vraie réflexion),
## ronds de pluie qui s'élargissent (normale perturbée, petits éclats).
const PUDDLE_SHADER := """
shader_type spatial;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 sky_a = vec3(0.32, 0.1, 0.36);
uniform vec3 sky_b = vec3(0.08, 0.14, 0.4);
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 g = vec2(0.0);
	float spark = 0.0;
	for (int k = 0; k < 2; k++) {
		vec2 p = wp.xz * 2.6 + float(k) * vec2(0.37, 0.71);
		vec2 cell = floor(p);
		vec2 c = cell + 0.25 + 0.5 * vec2(hash(cell), hash(cell + 7.3));
		float t = fract(TIME * 0.7 + hash(cell + 3.1));
		vec2 d = p - c;
		float r = length(d);
		float w = (1.0 - t) * smoothstep(0.06, 0.0, abs(r - t * 0.42));
		g += normalize(d + 1e-4) * w;
		spark += w;
	}
	vec3 n = normalize(vec3(-g.x * 0.5, 1.0, -g.y * 0.5));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float m = texture(noise, wp.xz * 0.12).g;
	ALBEDO = vec3(0.012, 0.014, 0.02);
	ROUGHNESS = 0.06;
	SPECULAR = 0.9;
	EMISSION = mix(sky_a, sky_b, m) * (0.3 + 0.7 * fres) + vec3(0.5, 0.45, 0.6) * spark * 0.12;
}
"""

static func _body(key: String, spin: float = 0.0, spin_z: bool = false) -> Material:
	if not _mats.has(key):
		var sh := Shader.new()
		sh.code = BODY_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("noise", load(NOISE))
		m.set_shader_parameter("spin", spin)
		m.set_shader_parameter("spin_z", spin_z)
		# hélice : le moyeu est l'origine de l'instance, elle garde son MultiMesh ; sinon le lot peut la fusionner
		# (view3d._flush_batch : MODEL_MATRIX[3] n'est lu que si spin != 0)
		m.set_meta("per_instance", spin != 0.0)
		_mats[key] = m
	return _mats[key]

static func _puddle() -> Material:
	if not _mats.has("puddle"):
		var sh := Shader.new()
		sh.code = PUDDLE_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("noise", load(NOISE))
		_mats["puddle"] = m
	return _mats["puddle"]

## Marquages : « decal » (peints, éclairés), « lit » (vitrines, menus : lumineux), « graf » (graffitis fondus).
static func _decal(kind: String) -> Material:
	var key := "decal_" + kind
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(PR + "decals.png")
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if kind == "graf":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.75, 0.75, 0.75, 0.38)
			m.roughness = 0.35
			m.metallic_specular = 0.6
		else:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.45
			m.roughness = 0.6
			m.metallic_specular = 0.4
		if kind == "lit":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(0.9, 0.9, 0.9)
		_mats[key] = m
	return _mats[key]

## Néons (forts, avec halo) et parties lumineuses douces (écrans, lanternes) : couleur par sommet, sans ombrage.
static func _glow(energy: float) -> Material:
	var key := "glow_%.2f" % energy
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.albedo_color = Color(energy, energy, energy)
		_mats[key] = m
	return _mats[key]

static func _mat_for(part: String) -> Material:
	if "_decallit" in part:
		return _decal("lit")
	if "_graf" in part:
		return _decal("graf")
	if "_decal" in part:
		return _decal("decal")
	if "_glowlit" in part:
		return _glow(0.95)
	if "_glow" in part:
		return _glow(1.5)
	if "_fanz" in part:
		return _body("fanz", 9.0, true)
	if "_fan" in part:
		return _body("fan", 7.0)
	if "_puddle" in part:
		return _puddle()
	return _body("body")

# ---------------------------------------------------------------- maillages
## Maillages d'un modèle (avec son matériau) et leur transformation locale.
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
		var mat := _mat_for(String(n.name))
		for i in range(m.get_surface_count()):
			m.surface_set_material(i, mat)
		out.append([m, xf, String(n.name)])
	for c in n.get_children():
		if c is Node3D:
			_collect(c, xf * (c as Node3D).transform, out)

## Pose un modèle dans le lot statique de la vue (fusionné par matériau, voir view3d._flush_batch) ; les objets
## à plat (flaques, graffitis, plaques d'égout) vont dans un lot sans ombre, monté à la fin de build().
static func put(v: Node, name: String, pos: Vector3, rot: float, scl: Vector3 = Vector3.ONE, box_i: int = -1) -> void:
	var xf := Transform3D(Basis(Vector3.UP, rot) * Basis.from_scale(scl), pos)
	var batch: Dictionary = _flat if name.begins_with("flaque") or name.begins_with("graf") or name == "egout" else v._batch
	for part in parts(name):
		var m: Mesh = part[0]
		var x2: Transform3D = xf * (part[1] as Transform3D)
		if not batch.has(m):
			batch[m] = []
		(batch[m] as Array).append(x2)
		for i in range(m.get_surface_count()):
			tris += (m.surface_get_array_index_len(i) / 3) if m.surface_get_format(i) & Mesh.ARRAY_FORMAT_INDEX else (m.surface_get_array_len(i) / 3)
		if box_i >= 0 and _checking():
			_placed.append([box_i, m, x2, String(part[2])])

static func _checking() -> bool:
	return "--props-check" in OS.get_cmdline_user_args()

# ---------------------------------------------------------------- salle
static func build(v: Node, rng: RandomNumberGenerator) -> void:
	tris = 0
	_placed.clear()
	_flat.clear()
	var K: float = v.K
	for i in range(v.arena.obstacles.size()):
		var r: Rect2 = v.arena.obstacles[i]
		var c: Vector3 = v.p3(r.get_center())
		# dalle de béton aux dimensions du rectangle (débord de 2 cm), sous les objets
		put(v, "socle", c, 0.0, Vector3(r.size.x * K + 0.04, 1.0, r.size.y * K + 0.04), i)
		if i >= DRESS.size():
			continue
		for it in DRESS[i]:
			var y: float = it[4] if (it as Array).size() > 4 else 0.0
			put(v, it[0], c + Vector3(it[1], y, it[2]), deg_to_rad(it[3]), Vector3.ONE, i)
	var t_obst := tris
	_accessories(v, rng)
	for m in _flat.keys():
		v._mm(m, _flat[m], false)
	_flat.clear()
	if "--props-stats" in OS.get_cmdline_user_args() or _checking():
		print("neon_props : obstacles %d triangles, accessoires %d" % [t_obst, tris - t_obst])
	if _checking():
		_check(v)

# ---------------------------------------------------------------- accessoires (non bloquants)
## Le long des parapets ouest, est et sud (à moins de ~0,6 m du pied du mur), ou à plat au sol ; jamais au
## nord de TOP, jamais sur un sas. Les objets du parapet sud restent bas (ils sont entre la caméra et le jeu).
static func _accessories(v: Node, rng: RandomNumberGenerator) -> void:
	var K: float = v.K
	var W: float = v.arena.W * K
	var H: float = v.arena.H * K
	var WALL: float = v.arena.WALL * K
	var xw := WALL + 0.3   # contre le parapet ouest
	var xe := W - WALL - 0.3
	var zs := H - WALL - 0.3
	var items := [
		# parapet ouest (face vers +x)
		["pot_a", Vector3(xw, 0, 7.6), 0.3],
		["neon_pied_v", Vector3(xw - 0.05, 0, 8.4), 0.0],
		["cone", Vector3(xw + 0.1, 0, 10.4), 0.4],
		["cables_sol", Vector3(xw - 0.1, 0, 16.4), PI * 0.5],
		["neon_tube_o", Vector3(xw + 0.25, 0, 18.0), PI * 0.5],
		# parapet est (face vers -x)
		["neon_tube_v", Vector3(xe - 0.25, 0, 7.4), -PI * 0.5],
		["pot_a", Vector3(xe, 0, 8.5), 1.2],
		["caisse_s_b", Vector3(xe - 0.05, 0, 16.2), PI * 0.5 + 0.06],
		["carton", Vector3(xe - 0.05, 0.35, 16.25), PI * 0.5 - 0.2],
		["neon_pied_g", Vector3(xe + 0.05, 0, 17.3), 0.0],
		["pot_b", Vector3(xe, 0, 10.6), 2.0],
		# parapet sud (bas)
		["cables_sol", Vector3(9.0, 0, zs + 0.1), 0.0],
		["cone", Vector3(12.3, 0, zs - 0.1), 0.2],
		["pot_b", Vector3(14.6, 0, zs), 0.6],
		["neon_tube_v", Vector3(23.4, 0, zs - 0.25), PI],
		["pot_b", Vector3(27.0, 0, zs), 2.6],
		["cone", Vector3(27.8, 0, zs - 0.15), 1.1],
		# à plat au sol : flaques, plaques d'égout, graffitis
		["flaque_c", Vector3(10.2, 0, 15.2), 0.4],
		["flaque_a", Vector3(26.4, 0, 9.2), 1.9],
		["flaque_b", Vector3(21.6, 0, 18.4), 0.2],
		["flaque_a", Vector3(5.4, 0, 18.9), 3.0],
		["flaque_b", Vector3(31.8, 0, 13.6), 4.1],
		["flaque_c", Vector3(17.6, 0, 7.6), 2.3],
		["egout", Vector3(15.6, 0, 8.4), 0.0],
		["egout", Vector3(25.2, 0, 15.6), 0.7],
		["graf_a", Vector3(12.4, 0, 17.8), 0.3],
		["graf_b", Vector3(28.6, 0, 12.6), -0.5],
		["graf_c", Vector3(7.6, 0, 9.4), 2.6],
	]
	for it in items:
		var p: Vector3 = it[1]
		if p.z < v.arena.TOP * K + 0.4 or _near_pad(v, p, 1.3):
			continue
		put(v, it[0], p, it[2])

static func _near_pad(v: Node, p: Vector3, r: float) -> bool:
	for pd in v.arena.pads:
		var q: Vector3 = v.p3(pd)
		if Vector2(q.x - p.x, q.z - p.z).length() < r:
			return true
	return false

# ---------------------------------------------------------------- contrôle (--props-check)
## Pour chaque obstacle : part du rectangle couverte vue de dessus (grille de 4 cm, bord de 3 cm toléré),
## débord maximal hors du rectangle, hauteur maximale, triangles. Imprimé au montage du décor.
static func _check(v: Node) -> void:
	var K: float = v.K
	for i in range(v.arena.obstacles.size()):
		var r: Rect2 = v.arena.obstacles[i]
		var x0 := r.position.x * K
		var z0 := r.position.y * K
		var sx := r.size.x * K
		var sz := r.size.y * K
		var step := 0.04
		var nx := int(sx / step)
		var nz := int(sz / step)
		var cov := PackedByteArray()
		cov.resize(nx * nz)
		var over := 0.0
		var top_obj := 0.0  # hauteur hors socle
		var t := 0
		for pl in _placed:
			if pl[0] != i:
				continue
			var m: Mesh = pl[1]
			var xf: Transform3D = pl[2]
			var nm := String(pl[3])
			var solid := not "_decal" in nm and not "socle" in nm  # couverture : objets seuls, sans la dalle
			for s in range(m.get_surface_count()):
				var arr := m.surface_get_arrays(s)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var w := PackedVector3Array()
				w.resize(vs.size())
				for k in range(vs.size()):
					var q: Vector3 = xf * vs[k]
					w[k] = q
					over = maxf(over, maxf(maxf(x0 - q.x, q.x - (x0 + sx)), maxf(z0 - q.z, q.z - (z0 + sz))))
					if solid:
						top_obj = maxf(top_obj, q.y)
				var n := idx.size() if idx.size() > 0 else w.size()
				t += n / 3
				if not solid:
					continue
				for k in range(0, n, 3):
					var a: Vector3 = w[idx[k] if idx.size() > 0 else k]
					var b: Vector3 = w[idx[k + 1] if idx.size() > 0 else k + 1]
					var c: Vector3 = w[idx[k + 2] if idx.size() > 0 else k + 2]
					_raster(cov, nx, nz, x0, z0, step, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z))
		var filled := 0
		var inner := 0
		for zi in range(1, nz - 1):
			for xi in range(1, nx - 1):
				inner += 1
				filled += cov[zi * nx + xi]
		print("obstacle %s %s : objets couvrant %.1f %% (dalle 100 %%), débord %.3f m, hauteur %.2f m, %d triangles" % [
			char(65 + i), r, 100.0 * filled / maxf(inner, 1), maxf(over, 0.0), top_obj, t])

static func _raster(cov: PackedByteArray, nx: int, nz: int, x0: float, z0: float, step: float, a: Vector2, b: Vector2, c: Vector2) -> void:
	var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)))
	var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)))
	var i0 := maxi(0, int(floor((lo.x - x0) / step)))
	var i1 := mini(nx - 1, int(ceil((hi.x - x0) / step)))
	var j0 := maxi(0, int(floor((lo.y - z0) / step)))
	var j1 := mini(nz - 1, int(ceil((hi.y - z0) / step)))
	var d := (b - a).cross(c - a)
	if absf(d) < 1e-9:
		return
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := Vector2(x0 + (i + 0.5) * step, z0 + (j + 0.5) * step)
			var w0 := (b - p).cross(c - p) / d
			var w1 := (c - p).cross(a - p) / d
			if w0 >= -1e-4 and w1 >= -1e-4 and 1.0 - w0 - w1 >= -1e-4:
				cov[j * nx + i] = 1
