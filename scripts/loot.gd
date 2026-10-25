extends RefCounted
## Box de butin et collection : quatre raretés de box (Bronze, Argent, Or, Légendaire) gagnées en partie
## (boss, élites, route Trésor), leur contenu tiré au sort (tickets, objets d'équipement, apparences de Jo,
## traînées de tir) et la collection des cosmétiques. Pas de doublon de cosmétique : il devient des tickets.
## Profil : « boxes » (box à ouvrir, dans l'ordre de gain), « skins » / « skin », « trails » / « trail ».

const Data = preload("res://scripts/data.gd")
const Rig3D = preload("res://scripts/rig3d.gd")

# ---------------------------------------------------------------- box
const BOXES := ["bronze", "argent", "or", "legendaire"]
const BOX_NAMES := {"bronze": "Bronze", "argent": "Argent", "or": "Or", "legendaire": "Légendaire"}
const BOX_COLORS := {"bronze": Color("#E39A5C"), "argent": Color("#BFD6F0"), "or": Color("#FFC23D"), "legendaire": Color("#C77DFF")}
## Lumière de la box (nappe, voyant), comme dans tools/chars/box_loot.py.
const BOX_GLOW := {"bronze": Color("#FFB45E"), "argent": Color("#5CF0FF"), "or": Color("#FFF2A0"), "legendaire": Color("#FF8AF2")}
## Nombre de coups pour l'ouvrir (la Légendaire se fait désirer).
const BOX_TAPS := {"bronze": 1, "argent": 2, "or": 2, "legendaire": 3}
const BOX_HINT := {
	"bronze": "Tickets, un objet, parfois un cosmétique",
	"argent": "Tickets, objets, souvent un cosmétique",
	"or": "Tickets, objet rare, un cosmétique garanti",
	"legendaire": "Gros tickets, objets de collection, deux cosmétiques dont un épique",
}

# ---------------------------------------------------------------- raretés des cosmétiques
const TIER_NAMES := ["COMMUNE", "RARE", "ÉPIQUE", "LÉGENDAIRE"]
const TIER_COLORS := [Color("#9FB3C8"), Color("#3CF2D8"), Color("#C77DFF"), Color("#FFB347")]
## Coffres où un cosmétique de chaque rareté a une vraie chance de sortir (au moins 5 % par coffre, d'après
## les tirages de roll() : à garder d'accord). Affiché sur l'écran APPARENCES (« Dans les coffres OR, LÉGENDAIRE »).
const TIER_BOXES := [["bronze", "argent", "or"], ["argent", "or", "legendaire"], ["or", "legendaire"], ["or", "legendaire"]]
## Un doublon rapporte des tickets selon sa rareté.
const DUP_TICKETS := [30, 80, 200, 500]

## Apparences de Jo. Une apparence est une TENUE COMPLÈTE : « model » = assets/chars3d/<model>.glb, un modèle entier
## de Jo (mêmes parts que jo.glb) sculpté par tools/blender/jo_skins.py (voir l'en-tête de ce fichier pour en
## ajouter une), chargé par Rig3D.apply_skin à la place de jo.glb.
## Les apparences pas encore converties n'ont qu'une palette provisoire : leurs couleurs (« suit » : blanc du
## sweat, « accent » : rouge, « light » : lumières, « hair » : cheveux) remplacent celles de jo.glb (Rig3D._recolor,
## sans matériau en plus). À remplacer chacune par une tenue (« model ») : c'est le travail qui reste.
## suit / accent / light servent aussi au dessin 2D de la carte (scripts/ui/boxes_art.gd).
## Correspondance avec les anciennes apparences (les ids et la sauvegarde ne changent pas) :
##   eclat (Éclat d'or, légendaire) -> Chevalière d'or (jo_chevalier) ; nebuleuse (Nébuleuse, épique) -> Mage
##   Nébuleuse (jo_magicienne) ; neon (Cité Néon, épique) -> Ronin Néon (jo_samourai) ; les autres : palette.
const SKINS := [
	{"id": "passeuse", "name": "Passeuse", "tier": 0, "suit": Color("#F4F4F1"), "accent": Color("#F0262E"), "light": Color("#9FF6FF")},
	{"id": "cargo", "name": "Cargo", "tier": 0, "suit": Color("#E6D7AE"), "accent": Color("#5E8A3C"), "light": Color("#F2E14C")},
	{"id": "glacier", "name": "Glacier", "tier": 0, "suit": Color("#EAF4FF"), "accent": Color("#3E86FF"), "light": Color("#9FE8FF")},
	{"id": "ardoise", "name": "Ardoise", "tier": 0, "suit": Color("#6A7488"), "accent": Color("#FFB347"), "light": Color("#FFE08A")},
	{"id": "menthe", "name": "Menthe", "tier": 0, "suit": Color("#E2FFF2"), "accent": Color("#22B585"), "light": Color("#B8FF6A")},
	{"id": "corail", "name": "Corail", "tier": 1, "suit": Color("#FFE4DC"), "accent": Color("#FF5C6E"), "light": Color("#FFC94D"), "hair": Color("#6E1F3C")},
	{"id": "lagon", "name": "Lagon", "tier": 1, "suit": Color("#DDF6FF"), "accent": Color("#00A0C6"), "light": Color("#FF8AE8")},
	{"id": "sentinelle", "name": "Sentinelle", "tier": 1, "suit": Color("#C8CEDC"), "accent": Color("#2C3350"), "light": Color("#FF4D6D")},
	{"id": "agrume", "name": "Agrume", "tier": 1, "suit": Color("#FFF5D2"), "accent": Color("#FFBE0B"), "light": Color("#7CFF4D"), "hair": Color("#B5521C")},
	{"id": "lavande", "name": "Lavande", "tier": 1, "suit": Color("#EEE6FF"), "accent": Color("#8A5CFF"), "light": Color("#5CF0FF"), "hair": Color("#4B3A9E")},
	{"id": "nebuleuse", "name": "Mage Nébuleuse", "tier": 2, "suit": Color("#3A2A78"), "accent": Color("#FFC23D"), "light": Color("#7AE7FF"), "model": "jo_magicienne"},
	{"id": "neon", "name": "Ronin Néon", "tier": 2, "suit": Color("#222840"), "accent": Color("#FF3CAC"), "light": Color("#2EE6FF"), "model": "jo_samourai"},
	{"id": "braise", "name": "Braise", "tier": 2, "suit": Color("#3C2C2C"), "accent": Color("#FF5A1F"), "light": Color("#FFD34D"), "hair": Color("#B3241A")},
	{"id": "aurore", "name": "Aurore", "tier": 2, "suit": Color("#FFF0F8"), "accent": Color("#FF7AD0"), "light": Color("#8AF0FF"), "hair": Color("#FF9A7A")},
	{"id": "eclat", "name": "Chevalière d'or", "tier": 3, "suit": Color("#E8EDF4"), "accent": Color("#F2B33D"), "light": Color("#FFF2B8"), "model": "jo_chevalier"},
	{"id": "prisme", "name": "Prisme", "tier": 3, "suit": Color("#1E2234"), "accent": Color("#F4F1EA"), "light": Color("#FFFFFF"), "rainbow": true, "hair": Color("#DDE3FF")},
]
## Couleurs de jo.glb (tools/blender/jo.py) que remplace une palette provisoire.
const JO_WHITE := "#F4F4F1"
const JO_RIB := "#C9CED6"
const JO_POCKET := "#E4E5E8"
const JO_RED := "#F0262E"
const JO_GLOW := "#9FF6FF"
const JO_HAIR := "#2A1E2A"

## Traînées de tir : couleur des projectiles de Jo. « alt » alterne les couleurs d'un tir à l'autre,
## « rainbow » fait le tour des teintes. Pas de rouge ni de magenta : ce sont les tirs ennemis.
const TRAILS := [
	{"id": "turquoise", "name": "Turquoise", "tier": 0, "cols": [Color("#3CF2D8")]},
	{"id": "citron", "name": "Citron", "tier": 0, "cols": [Color("#E8FF4D")]},
	{"id": "menthe", "name": "Menthe", "tier": 0, "cols": [Color("#5DFF9B")]},
	{"id": "azur", "name": "Azur", "tier": 0, "cols": [Color("#4DB8FF")]},
	{"id": "ambre", "name": "Ambre", "tier": 0, "cols": [Color("#FFC94D")]},
	{"id": "glace", "name": "Glace", "tier": 1, "cols": [Color("#D8F8FF")]},
	{"id": "lilas", "name": "Lilas", "tier": 1, "cols": [Color("#B48CFF")]},
	{"id": "lime", "name": "Lime", "tier": 1, "cols": [Color("#A6FF2E")]},
	{"id": "lagon", "name": "Lagon", "tier": 1, "cols": [Color("#00C8FF")]},
	{"id": "arc", "name": "Arc électrique", "tier": 2, "cols": [Color("#7AE7FF"), Color("#FFFFFF")], "mode": "alt"},
	{"id": "follet", "name": "Feu follet", "tier": 2, "cols": [Color("#9BFF6A"), Color("#3CF2D8")], "mode": "alt"},
	{"id": "orfondu", "name": "Or fondu", "tier": 2, "cols": [Color("#FFC23D"), Color("#FFF2B8")], "mode": "alt"},
	{"id": "comete", "name": "Comète", "tier": 3, "cols": [Color("#FFFFFF"), Color("#FFC23D"), Color("#7AE7FF")], "mode": "alt"},
	{"id": "spectre", "name": "Spectre", "tier": 3, "cols": [Color("#3CF2D8")], "mode": "rainbow"},
]
const DEFAULT_SKIN := "passeuse"
const DEFAULT_TRAIL := "turquoise"

static func skin(id: String) -> Dictionary:
	for s in SKINS:
		if s["id"] == id:
			return s
	return SKINS[0]

static func trail(id: String) -> Dictionary:
	for s in TRAILS:
		if s["id"] == id:
			return s
	return TRAILS[0]

static func cosmetic(kind: String, id: String) -> Dictionary:
	return skin(id) if kind == "skin" else trail(id)

static func total_count() -> int:
	return SKINS.size() + TRAILS.size()

static func owned_count(p: Dictionary) -> int:
	return (p["skins"] as Array).size() + (p["trails"] as Array).size()

# ---------------------------------------------------------------- sauvegarde
## Champs du profil (ajoutés à Save.default_profile).
static func default_fields() -> Dictionary:
	return {"boxes": [], "skins": [DEFAULT_SKIN], "skin": DEFAULT_SKIN, "trails": [DEFAULT_TRAIL], "trail": DEFAULT_TRAIL, "boxes_opened": 0}

## Ancienne sauvegarde ou fichier abîmé : box connues seulement, cosmétiques connus, l'équipé est possédé.
static func sanitize(p: Dictionary) -> void:
	var bx := []
	for b in p.get("boxes", []):
		if String(b) in BOXES:
			bx.append(String(b))
	p["boxes"] = bx
	for pair in [["skins", "skin", SKINS, DEFAULT_SKIN], ["trails", "trail", TRAILS, DEFAULT_TRAIL]]:
		var known := {}
		for s in pair[2]:
			known[s["id"]] = true
		var own := [pair[3]]
		for id in p.get(pair[0], []):
			if known.has(String(id)) and not own.has(String(id)):
				own.append(String(id))
		p[pair[0]] = own
		if not own.has(String(p.get(pair[1], ""))):
			p[pair[1]] = pair[3]
	p["boxes_opened"] = int(p.get("boxes_opened", 0))

# ---------------------------------------------------------------- gains
static func add_box(p: Dictionary, box: String) -> void:
	(p["boxes"] as Array).append(box)

static func count(p: Dictionary, box: String) -> int:
	return (p["boxes"] as Array).count(box)

## Box gagnées en battant le boss : une Or, plus une Légendaire à la première victoire du monde.
static func boss_boxes(first_win: bool) -> Array:
	return ["or", "legendaire"] if first_win else ["or"]

const ELITE_BOX_CHANCE := 0.18

# ---------------------------------------------------------------- tirage
## Ouvre une box du profil : la retire, tire son contenu, l'ajoute au profil. Les récompenses arrivent
## dans l'ordre de présentation (la meilleure à la fin). Le profil est à sauvegarder ensuite.
static func open_box(p: Dictionary, box: String) -> Array:
	var bx: Array = p["boxes"]
	var i := bx.find(box)
	if i < 0:
		return []
	bx.remove_at(i)
	var rewards := roll(box, p)
	grant(p, rewards)
	p["boxes_opened"] = int(p.get("boxes_opened", 0)) + 1
	return rewards

## Contenu d'une box : [{kind: tickets|item|skin|trail, tier, n?, item?, id?, dup?}]
static func roll(box: String, p: Dictionary) -> Array:
	var out := []
	var taken := {}  # cosmétiques déjà tirés dans cette box (pas deux fois le même)
	match box:
		"bronze":
			out.append(_tickets(randi_range(25, 45)))
			if randf() < 0.7:
				out.append(_item(0))
			else:
				out[0]["n"] += randi_range(15, 30)
			if randf() < 0.25:
				out.append(_cosmetic(p, [0.85, 0.15, 0.0, 0.0], taken))
		"argent":
			out.append(_tickets(randi_range(60, 100)))
			out.append(_item(0))
			if randf() < 0.6:
				out.append(_cosmetic(p, [0.6, 0.32, 0.08, 0.0], taken))
			else:
				out.append(_item(0))
		"or":
			out.append(_tickets(randi_range(140, 220)))
			out.append(_item(1))
			if randf() < 0.5:
				out.append(_item(0))
			out.append(_cosmetic(p, [0.3, 0.45, 0.2, 0.05], taken))
		"legendaire":
			out.append(_tickets(randi_range(350, 500)))
			out.append(_item(1))
			out.append(_item(2))
			out.append(_cosmetic(p, [0.0, 0.35, 0.5, 0.15], taken))
			out.append(_cosmetic(p, [0.0, 0.0, 0.7, 0.3], taken))
	# du moins bon au meilleur : le clou du spectacle en dernier
	out.sort_custom(func(a, b): return _rank(a) < _rank(b))
	return out

static func _rank(r: Dictionary) -> float:
	var k := {"tickets": 0.0, "item": 1.0, "trail": 2.0, "skin": 2.5}
	return float(r["tier"]) * 10.0 + float(k.get(r["kind"], 0.0)) - (5.0 if bool(r.get("dup", false)) else 0.0)

static func _tickets(n: int) -> Dictionary:
	return {"kind": "tickets", "tier": 0, "n": n}

static func _item(bonus: int) -> Dictionary:
	var it := Data.roll_item(bonus)
	return {"kind": "item", "tier": int(it["rarity"]), "item": it}

static func _pick_tier(w: Array) -> int:
	var r := randf()
	for i in range(w.size()):
		r -= float(w[i])
		if r <= 0.0:
			return i
	return w.size() - 1

## Cosmétique d'une rareté tirée selon `w` : apparence ou traînée ; de préférence un qu'on n'a pas.
## Un doublon devient des tickets (dup = true, n = tickets).
static func _cosmetic(p: Dictionary, w: Array, taken: Dictionary) -> Dictionary:
	var tier := _pick_tier(w)
	var kind := "skin" if randf() < 0.55 else "trail"
	var pool := []
	var fresh := []
	for k in [kind, "trail" if kind == "skin" else "skin"]:
		pool = []
		fresh = []
		for c in (SKINS if k == "skin" else TRAILS):
			if int(c["tier"]) != tier or taken.has(k + String(c["id"])) or c["id"] in [DEFAULT_SKIN, DEFAULT_TRAIL]:
				continue
			pool.append(c)
			if not (p["skins" if k == "skin" else "trails"] as Array).has(c["id"]):
				fresh.append(c)
		kind = k
		if not fresh.is_empty():
			break
	if pool.is_empty():
		return _tickets(DUP_TICKETS[tier])
	var c: Dictionary = fresh.pick_random() if not fresh.is_empty() and randf() < 0.7 else pool.pick_random()
	taken[kind + String(c["id"])] = true
	var dup := (p["skins" if kind == "skin" else "trails"] as Array).has(c["id"])
	return {"kind": kind, "tier": tier, "id": String(c["id"]), "dup": dup, "n": DUP_TICKETS[tier] if dup else 0}

## Ajoute les récompenses au profil.
static func grant(p: Dictionary, rewards: Array) -> void:
	for r in rewards:
		match String(r["kind"]):
			"tickets":
				p["tickets"] = int(p["tickets"]) + int(r["n"])
			"item":
				(p["inventory"] as Array).append(r["item"])
			"skin", "trail":
				if bool(r.get("dup", false)):
					p["tickets"] = int(p["tickets"]) + int(r["n"])
				else:
					(p["skins" if r["kind"] == "skin" else "trails"] as Array).append(String(r["id"]))

## Texte d'une récompense : [titre, sous-titre, nom de rareté, couleur].
static func describe(r: Dictionary) -> Array:
	match String(r["kind"]):
		"tickets":
			return ["+%d" % int(r["n"]), "Tickets", "TICKETS", Color("#FFB347")]
		"item":
			var it: Dictionary = r["item"]
			var tpl := Data.item_template(String(it["id"]))
			return [Data.item_label(it), Data.SLOT_NAMES[tpl["slot"]] + "  ·  " + Data.item_stat_text(it), Data.RARITY_NAMES[int(it["rarity"])].to_upper(), Data.RARITY_COLORS[int(it["rarity"])]]
		"skin", "trail":
			var c := cosmetic(String(r["kind"]), String(r["id"]))
			var what := "Apparence" if r["kind"] == "skin" else "Traînée de tir"
			if bool(r.get("dup", false)):
				what = "Doublon  ·  +%d tickets" % int(r["n"])
			return [String(c["name"]), what, TIER_NAMES[int(c["tier"])], TIER_COLORS[int(c["tier"])]]
	return ["", "", "", Color.WHITE]

# ---------------------------------------------------------------- application
## Palette de l'apparence pour Rig3D (vide : couleurs d'origine, matériaux d'origine).
static func skin_palette(id: String) -> Dictionary:
	if id == DEFAULT_SKIN:
		return {}
	var s := skin(id)
	if s.has("model"):
		return {"id": id, "model": String(s["model"])}
	var suit: Color = s["suit"]
	var acc: Color = s["accent"]
	var cols := {JO_WHITE: suit, JO_RIB: suit.darkened(0.16), JO_POCKET: suit.darkened(0.06), JO_RED: acc, JO_GLOW: s["light"]}
	if s.has("hair"):
		cols[JO_HAIR] = s["hair"]
	return {"id": id, "colors": cols}

## Apparence équipée du profil, appliquée à tous les modèles de Jo (Relais, partie).
static func apply_skin(p: Dictionary) -> void:
	Rig3D.set_hero_skin(skin_palette(String(p.get("skin", DEFAULT_SKIN))))

## Couleur du tir n° `i` avec la traînée `id`.
static func trail_color(id: String, i: int) -> Color:
	var t := trail(id)
	var cols: Array = t["cols"]
	match String(t.get("mode", "")):
		"alt":
			return cols[i % cols.size()]
		"rainbow":
			# du jaune au violet et retour : jamais le rouge ni le magenta des tirs ennemis
			return Color.from_hsv(0.13 + 0.6 * (0.5 - 0.5 * cos(i * 0.3)), 0.62, 1.0)
	return cols[0]
