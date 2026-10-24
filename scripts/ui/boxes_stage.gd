extends SubViewportContainer
## Box de butin en 3D dans l'interface (écran COFFRES, ouverture) : petit monde à part (SubViewport à fond
## transparent), modèle sculpté assets/loot/box_<rareté>.glb, une lumière clé, un contre-jour, une lumière
## dans la box. Animations en code : chute et rebond, attente qui se balance, secousse au toucher (la box
## se charge de lumière), ouverture (le couvercle saute, la nappe de lumière éclate).
## Léger pour le mobile : un modèle d'environ 5 000 triangles, trois lumières sans ombre, pas de post-effet.

const Rig3D = preload("res://scripts/rig3d.gd")
const Models = preload("res://scripts/models.gd")
const Loot = preload("res://scripts/loot.gd")

var vp: SubViewport
var cam: Camera3D
var root3: Node3D  # chute, secousse, écrasement
var spin3: Node3D  # balancement
var box: Node3D
var lid: Node3D
var lid_rest := Transform3D.IDENTITY
var glow_mats: Array = []
var inner: OmniLight3D
var rarity := "or"
var t := 0.0
var charge := 0.0  # 0..1 : lumière qui monte à chaque toucher
var _charge_shown := 0.0
var _shake := 0.0
var _squash := 0.0
var open_k := -1.0  # >= 0 : ouverture en cours (secondes)
var drop_k := -1.0  # >= 0 : chute en cours (secondes)
var idle_spin := true
var yaw := 0.0  # orientation de base (écran COFFRES : de trois quarts)
signal landed

func setup(r: String, px: Vector2) -> void:
	custom_minimum_size = px
	size = px
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(px)
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.95)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	we.environment = env
	vp.add_child(we)
	cam = Camera3D.new()
	cam.fov = 30.0
	var cp := Vector3(0, 1.55, 3.9)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.42, 0) - cp, Vector3.UP), cp)
	vp.add_child(cam)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-48, 28, 0)
	vp.add_child(key)
	var back := DirectionalLight3D.new()
	back.light_color = Color(0.6, 0.75, 1.0)
	back.light_energy = 0.7
	back.rotation_degrees = Vector3(-20, 200, 0)
	vp.add_child(back)
	inner = OmniLight3D.new()
	inner.position = Vector3(0, 0.9, 0.2)
	inner.omni_range = 3.0
	inner.light_energy = 0.0
	vp.add_child(inner)
	root3 = Node3D.new()
	vp.add_child(root3)
	spin3 = Node3D.new()
	root3.add_child(spin3)
	set_rarity(r)

func set_rarity(r: String) -> void:
	rarity = r
	if box != null:
		box.queue_free()
	glow_mats.clear()
	box = Models.scene("res://assets/loot/box_%s.glb" % r).instantiate()
	spin3.add_child(box)
	for mi in Models.meshes(box):
		var m: MeshInstance3D = mi
		var nm := String(m.name) + String(m.get_parent().name)
		if "_glow" in nm:
			var g: StandardMaterial3D = Rig3D.glow_mat(1.6).duplicate()
			m.material_override = g
			glow_mats.append(g)
		else:
			m.material_override = Rig3D.body_mat(Color(1, 1, 1))
	lid = box.find_child("lid", true, false)
	if lid != null:
		lid_rest = lid.transform
	inner.light_color = Loot.BOX_GLOW[r]
	box.scale = Vector3.ONE * (1.12 if r == "legendaire" else 1.0)
	charge = 0.0
	_charge_shown = 0.0
	open_k = -1.0

## Chute depuis le haut de l'écran, rebond, écrasement à l'atterrissage.
func drop() -> void:
	drop_k = 0.0
	root3.position = Vector3(0, 3.0, 0)

## Toucher : secousse, écrasement, la box se charge de lumière.
func shake(amount: float = 1.0) -> void:
	_shake = maxf(_shake, amount)
	_squash = maxf(_squash, amount)

## Ouverture : le couvercle saute en arrière, la lumière éclate.
func open() -> void:
	open_k = 0.0
	_shake = 1.2
	_squash = 1.0

## Saute à la fin de l'animation en cours (accélération d'un toucher).
func skip() -> void:
	if drop_k >= 0.0:
		drop_k = 10.0
	if open_k >= 0.0:
		open_k = maxf(open_k, 0.6)

func _process(dt: float) -> void:
	if vp == null:
		return
	t += dt
	# chute : gravité, rebond amorti
	if drop_k >= 0.0:
		drop_k += dt
		var k := drop_k
		var y := 0.0
		if k < 0.32:
			y = 3.0 * (1.0 - (k / 0.32) * (k / 0.32))
		elif k < 0.56:
			var u := (k - 0.32) / 0.24
			y = 0.28 * sin(u * PI)
		root3.position.y = y
		if k >= 0.32 and k - dt < 0.32:
			_squash = 1.0
			landed.emit()
		if k >= 0.56:
			drop_k = -1.0
			root3.position.y = 0.0
	# secousse et écrasement
	_shake = maxf(0.0, _shake - dt * 3.2)
	_squash = maxf(0.0, _squash - dt * 4.5)
	var sh := _shake * _shake
	root3.rotation = Vector3(sin(t * 47.0) * 0.07 * sh, 0, sin(t * 53.0 + 1.0) * 0.12 * sh)
	var sq := sin(_squash * PI) * 0.16 * _squash
	root3.scale = Vector3(1.0 + sq, 1.0 - sq, 1.0 + sq)
	# balancement d'attente
	var sway := 0.0
	if idle_spin and open_k < 0.0:
		sway = sin(t * 1.1) * 0.22
	spin3.rotation.y = lerp_angle(spin3.rotation.y, yaw + sway, clampf(dt * 6.0, 0.0, 1.0))
	if idle_spin and open_k < 0.0 and drop_k < 0.0:
		spin3.position.y = 0.04 + sin(t * 2.2) * 0.04
	# lumière : charge, palpitation, éclat d'ouverture
	_charge_shown = lerpf(_charge_shown, charge, clampf(dt * 8.0, 0.0, 1.0))
	var e := 1.4 + 2.2 * _charge_shown + 0.3 * sin(t * (3.0 + 9.0 * _charge_shown))
	inner.light_energy = 0.4 * _charge_shown + 0.25 * _charge_shown * sin(t * 14.0)
	if open_k >= 0.0:
		open_k += dt
		var u := clampf(open_k / 0.35, 0.0, 1.0)
		var ek := 1.0 - pow(1.0 - u, 3.0)
		if lid != null:
			# le couvercle bascule en arrière et monte, avec un petit rebond
			var ang := -2.1 * ek + 0.12 * sin(clampf((open_k - 0.35) / 0.4, 0.0, 1.0) * PI)
			lid.transform = Transform3D(lid_rest.basis * Basis(Vector3.RIGHT, ang), lid_rest.origin + Vector3(0, 0.18 * ek, -0.06 * ek))
		e = 4.5 * (1.0 - 0.45 * clampf((open_k - 0.3) / 0.8, 0.0, 1.0))
		inner.light_energy = 3.0 * (1.0 - 0.6 * clampf(open_k / 1.0, 0.0, 1.0))
	for g in glow_mats:
		(g as StandardMaterial3D).albedo_color = Color(e, e, e)

## Remet la box fermée (ouverture suivante).
func reset_box() -> void:
	open_k = -1.0
	charge = 0.0
	_charge_shown = 0.0
	if lid != null:
		lid.transform = lid_rest
