extends RefCounted
## Chargement des modèles 3D (Kenney, CC0) et petites briques : pivot recentré, maillages pour MultiMesh,
## matériaux émissifs et toon partagés.

const CHARS := "res://assets/models/chars/"
const STATION := "res://assets/models/station/"
const SPACE := "res://assets/models/space/"
const BLASTER := "res://assets/models/blaster/"

static var _scenes := {}
static var _mesh_cache := {}
static var _mat_cache := {}

static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]

## Instance du modèle ; `center` ramène le centre de la base sous l'origine (les modèles du Space Kit sont décalés).
static func inst(path: String, center: bool = false) -> Node3D:
	var n: Node3D = scene(path).instantiate()
	if center:
		var a := aabb(n)
		var holder := Node3D.new()
		n.position = Vector3(-(a.position.x + a.size.x * 0.5), -a.position.y, -(a.position.z + a.size.z * 0.5))
		holder.add_child(n)
		return holder
	return n

static func aabb(n: Node, xf: Transform3D = Transform3D.IDENTITY) -> AABB:
	var out := AABB()
	var first := true
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out = here * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var b := aabb(c, here)
		if b.size != Vector3.ZERO:
			out = b if first else out.merge(b)
			first = false
	return out

## Premier maillage d'un modèle (avec ses matériaux de surface), pour un MultiMesh.
static func mesh_of(path: String) -> Mesh:
	if _mesh_cache.has(path):
		return _mesh_cache[path]
	var n: Node = scene(path).instantiate()
	var mi: MeshInstance3D = n if n is MeshInstance3D else n.find_children("*", "MeshInstance3D", true, false)[0]
	var m: Mesh = mi.mesh
	n.free()
	_mesh_cache[path] = m
	return m

## Tous les maillages d'un modèle avec leur transformation locale (pour regrouper en MultiMesh).
static var _parts_cache := {}
static func parts_of(path: String, center: bool = false) -> Array:
	var key := path + ("#c" if center else "")
	if _parts_cache.has(key):
		return _parts_cache[key]
	var n: Node3D = scene(path).instantiate()
	var off := Transform3D.IDENTITY
	if center:
		var a := aabb(n)
		off = Transform3D(Basis(), Vector3(-(a.position.x + a.size.x * 0.5), -a.position.y, -(a.position.z + a.size.z * 0.5)))
	var out := []
	_collect(n, off * n.transform, out)
	n.free()
	_parts_cache[key] = out
	return out

static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([(n as MeshInstance3D).mesh, xf])
	for c in n.get_children():
		if c is Node3D:
			_collect(c, xf * (c as Node3D).transform, out)

## Copie d'un maillage dont les matériaux de surface sont assombris (les modèles du Space Kit sortent trop clairs).
static var _tinted := {}
static func tinted_mesh(m: Mesh, k: float) -> Mesh:
	var key := str(m.get_instance_id()) + ":" + str(k)
	if _tinted.has(key):
		return _tinted[key]
	var d: Mesh = m.duplicate()
	for i in range(d.get_surface_count()):
		var mat := d.surface_get_material(i)
		if mat is StandardMaterial3D:
			var dm: StandardMaterial3D = mat.duplicate()
			dm.albedo_color = Color(dm.albedo_color.r * k, dm.albedo_color.g * k, dm.albedo_color.b * k * 1.08, dm.albedo_color.a)
			d.surface_set_material(i, dm)
	_tinted[key] = d
	return d

## Assombrit tous les maillages d'une instance (matériaux dupliqués).
static func tint_node(n: Node, k: float) -> void:
	for mi in meshes(n):
		var m: MeshInstance3D = mi
		if m.mesh != null:
			m.mesh = tinted_mesh(m.mesh, k)

## Matériau émissif simple (projectiles, lueurs) : couleur > 1 pour passer le seuil du glow.
static func glow_mat(col: Color, energy: float = 3.0, alpha: float = 1.0) -> StandardMaterial3D:
	var key := "g%s%.2f%.2f" % [col.to_html(), energy, alpha]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r * energy, col.g * energy, col.b * energy, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.disable_receive_shadows = true
	_mat_cache[key] = m
	return m

## Matériau additif (halos, faisceaux), avec une texture de dégradé facultative.
static func add_mat(col: Color, energy: float = 1.5, tex: Texture2D = null, billboard: bool = false) -> StandardMaterial3D:
	var key := "a%s%.2f%s%s" % [col.to_html(), energy, str(tex.get_rid().get_id()) if tex else "-", str(billboard)]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(col.r * energy, col.g * energy, col.b * energy, col.a)
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	if tex:
		m.albedo_texture = tex
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat_cache[key] = m
	return m

## Matériau mat coloré (pièces faites en code) : ombrage toon doux, liseré de lumière.
static func toon(col: Color, rim: float = 0.35, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var key := "t%s%.2f%s%.2f" % [col.to_html(), rim, emission.to_html(), emission_energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	m.metallic_specular = 0.4
	m.rim_enabled = rim > 0.0
	m.rim = rim
	m.rim_tint = 0.3
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	_mat_cache[key] = m
	return m

## Dégradé radial (blanc au centre, transparent au bord) pour halos et ombres portées.
static var _radial: GradientTexture2D = null
static func radial() -> GradientTexture2D:
	if _radial == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		_radial = GradientTexture2D.new()
		_radial.gradient = g
		_radial.fill = GradientTexture2D.FILL_RADIAL
		_radial.fill_from = Vector2(0.5, 0.5)
		_radial.fill_to = Vector2(1.0, 0.5)
		_radial.width = 128
		_radial.height = 128
	return _radial

## Dégradé vertical (opaque en bas, transparent en haut) pour les faisceaux de loot.
static var _beam: GradientTexture2D = null
static func beam() -> GradientTexture2D:
	if _beam == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0))
		g.set_color(1, Color(1, 1, 1, 1))
		_beam = GradientTexture2D.new()
		_beam.gradient = g
		_beam.fill_from = Vector2(0.5, 0.0)
		_beam.fill_to = Vector2(0.5, 1.0)
		_beam.width = 8
		_beam.height = 64
	return _beam

## Ombre portée douce (disque sombre au sol), partagée.
static var _shadow_mat: StandardMaterial3D = null
static func shadow_mat() -> StandardMaterial3D:
	if _shadow_mat == null:
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_mat.albedo_color = Color(0, 0, 0.05, 0.45)
		_shadow_mat.albedo_texture = radial()
		_shadow_mat.disable_receive_shadows = true
	return _shadow_mat

static func shadow_blob(size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	mi.material_override = shadow_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.02
	return mi

static func box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	return mi

static func sphere(r: float, mat: Material, h: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0 if h < 0.0 else h
	sm.radial_segments = 20
	sm.rings = 10
	mi.mesh = sm
	mi.material_override = mat
	return mi

static func cyl(r_top: float, r_bot: float, h: float, mat: Material, seg: int = 20) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	return mi

static func capsule(r: float, h: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	cm.radial_segments = 16
	cm.rings = 6
	mi.mesh = cm
	mi.material_override = mat
	return mi

static func torus(inner: float, outer: float, mat: Material, rings: int = 32) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = rings
	tm.ring_segments = 10
	mi.mesh = tm
	mi.material_override = mat
	return mi

## Toutes les MeshInstance3D d'un nœud (pour le flash de coup, les ombres, la teinte).
static func meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(meshes(c))
	return out
