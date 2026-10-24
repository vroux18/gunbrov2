extends RefCounted
## Icônes des objets, rendues une fois pour toutes depuis leurs modèles 3D (tools/item_icons.tscn) :
## assets/icons/items/<id>.png (l'objet, fond transparent) et <id>_glow.png (ses parts lumineuses, en blanc),
## que l'on teinte ici à la couleur de rareté, comme les lumières de l'objet porté par Jo en partie.
## Aucun rendu 3D au moment de jouer : deux textures superposées.
## Sans icône (objet ajouté depuis le dernier rendu), repli sur le pictogramme de l'emplacement (icon.gd).

const Icon = preload("res://scripts/icon.gd")
const Data = preload("res://scripts/data.gd")

const DIR := "res://assets/icons/items/"
const TICKETS_COL := Color("#FFC23D")

static var _tex := {}  # nom -> Texture2D (ou null : pas d'icône)

## Texture de l'icône, avec ses mipmaps, calculées ici une fois (les fichiers .import ne sont pas versionnés :
## l'import par défaut n'en fait pas, et une icône de 256 px réduite à 60 px scintillerait).
static func texture(name: String) -> Texture2D:
	if not _tex.has(name):
		var p := DIR + name + ".png"
		var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
		if t != null:
			var img := t.get_image()
			if img != null and not img.has_mipmaps():
				img.generate_mipmaps()
				t = ImageTexture.create_from_image(img)
		_tex[name] = t
	return _tex[name]

static func has_icon(id: String) -> bool:
	return texture(id) != null

## Icône de l'objet `item` ({id, rarity}) dans un carré de `size_px`. Repli : pictogramme de l'emplacement,
## couleur `fallback_col` (par défaut celle de la rareté), à `fallback_scale` du carré.
static func make(item: Dictionary, size_px: float, fallback_col: Color = Color(0, 0, 0, 0), fallback_scale: float = 0.62) -> Control:
	var id := String(item.get("id", ""))
	var rc: Color = Data.RARITY_COLORS[clampi(int(item.get("rarity", 0)), 0, 3)]
	var base := texture(id)
	if base == null:
		var slot := String(Data.item_template(id)["slot"])
		return _fallback(slot, rc if fallback_col.a == 0.0 else fallback_col, size_px, fallback_scale)
	var c := _box(size_px)
	c.add_child(_rect(base))
	var glow := texture(id + "_glow")
	if glow != null:
		var g := _rect(glow)
		g.self_modulate = rc.lightened(0.12)
		c.add_child(g)
	return c

## Icône des tickets (pile de pièces), repli : le disque doré d'icon.gd.
static func tickets(size_px: float, fallback_scale: float = 0.8) -> Control:
	var t := texture("tickets")
	if t == null:
		return _fallback("coin", TICKETS_COL, size_px, fallback_scale)
	var c := _box(size_px)
	c.add_child(_rect(t))
	return c

static func _box(size_px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(size_px, size_px)
	c.size = Vector2(size_px, size_px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func _rect(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # 256 px affichés à 60–120 px : net
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Ancien pictogramme, centré dans le même carré (même encombrement que l'icône).
static func _fallback(kind: String, col: Color, size_px: float, k: float) -> Control:
	var c := _box(size_px)
	var ic := Icon.new(kind, col, size_px * k)
	ic.position = Vector2.ONE * size_px * (1.0 - k) * 0.5
	ic.size = Vector2.ONE * size_px * k
	c.add_child(ic)
	return c
