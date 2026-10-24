extends RefCounted
## Données fixes du jeu : arbre des pouvoirs de partie, objets de loot, ennemis, plan des salles.

# ---------------------------------------------------------------- pouvoirs
## Arbre des pouvoirs d'une partie : cinq branches, trois paliers chacune. Le palier 2 d'une branche s'ouvre après
## 2 choix dans cette branche, le palier 3 après 4. Chaque pouvoir se cumule jusqu'à « max » niveaux (I, II, III…).
## « lv » : texte propre à chaque niveau, sinon « desc ». Quand deux pouvoirs précis sont au maximum, leur
## évolution (EVOLUTIONS) peut sortir : une carte légendaire qui transforme le jeu.
const BRANCHES := {
	"canon": {"name": "Canon", "col": Color("#3CF2D8"), "icon": "b_canon"},
	"elem": {"name": "Éléments", "col": Color("#C77DFF"), "icon": "b_elem"},
	"def": {"name": "Défense", "col": Color("#5AA8FF"), "icon": "shield"},
	"mach": {"name": "Machines", "col": Color("#9BE15D"), "icon": "gear"},
	"move": {"name": "Mouvement", "col": Color("#FF7A2F"), "icon": "dash"},
}
const BRANCH_ORDER := ["canon", "elem", "def", "mach", "move"]
const TIER_NEED := [0, 0, 2, 4]  # choix déjà faits dans la branche pour ouvrir le palier 1, 2, 3
const EVO_COL := Color("#FFB347")

const POWERS := [
	# Canon
	{"id": "rate", "b": "canon", "tier": 1, "max": 4, "name": "Cadence", "desc": "+20 % de cadence de tir."},
	{"id": "dmg", "b": "canon", "tier": 1, "max": 4, "name": "Puissance", "desc": "+20 % de dégâts."},
	{"id": "crit", "b": "canon", "tier": 1, "max": 3, "name": "Critique", "desc": "+10 % de chances de coup critique (dégâts doublés)."},
	{"id": "range", "b": "canon", "tier": 1, "max": 2, "name": "Longue portée", "desc": "+25 % de portée, tirs plus rapides."},
	{"id": "double", "b": "canon", "tier": 2, "max": 2, "name": "Tir multiple", "lv": ["Tir double : un projectile de plus à chaque tir.", "Tir triple : encore un projectile de plus."]},
	{"id": "pierce", "b": "canon", "tier": 2, "max": 3, "name": "Perforant", "desc": "Les tirs traversent un ennemi de plus."},
	{"id": "bounce", "b": "canon", "tier": 2, "max": 2, "name": "Ricochet", "lv": ["Les tirs rebondissent deux fois sur les murs et les caisses.", "Un tir qui touche rebondit vers l'ennemi suivant."]},
	{"id": "back", "b": "canon", "tier": 2, "max": 2, "name": "Tir arrière", "lv": ["Un tir part aussi derrière toi.", "Plus deux tirs sur les côtés."]},
	{"id": "fan", "b": "canon", "tier": 3, "max": 2, "name": "Salve en éventail", "lv": ["Un tir sur quatre part en éventail de 5.", "Un tir sur trois, éventail de 7."]},
	{"id": "giant", "b": "canon", "tier": 3, "max": 2, "name": "Obus géants", "desc": "Tirs 40 % plus gros, +30 % de dégâts, ils font reculer."},
	{"id": "fatal", "b": "canon", "tier": 3, "max": 2, "name": "Coup fatal", "lv": ["Critiques ×3 et +5 % de critique.", "Critiques ×4 et +5 % de critique."]},
	# Éléments
	{"id": "fire", "b": "elem", "tier": 1, "max": 3, "name": "Balles incendiaires", "desc": "Les ennemis touchés brûlent 3 s. Plus fort à chaque niveau."},
	{"id": "frost", "b": "elem", "tier": 1, "max": 3, "name": "Balles givrantes", "desc": "Les touchés ralentissent ; à force de coups, ils gèlent sur place."},
	{"id": "shock", "b": "elem", "tier": 1, "max": 3, "name": "Foudre", "desc": "1 tir sur 4 lance un arc qui saute d'ennemi en ennemi (+1 saut par niveau)."},
	{"id": "venom", "b": "elem", "tier": 1, "max": 3, "name": "Venin", "desc": "Les ennemis tués laissent un nuage toxique. Plus grand à chaque niveau."},
	{"id": "boom", "b": "elem", "tier": 2, "max": 3, "name": "Détonation", "desc": "Les ennemis tués explosent et blessent leurs voisins."},
	{"id": "aura", "b": "elem", "tier": 2, "max": 2, "name": "Aura glaciale", "desc": "Les ennemis proches de toi sont ralentis et se couvrent de givre."},
	{"id": "spread", "b": "elem", "tier": 2, "max": 1, "name": "Contagion", "desc": "Un ennemi qui meurt en brûlant ou empoisonné contamine ses voisins."},
	{"id": "meteor", "b": "elem", "tier": 3, "max": 2, "name": "Météores", "lv": ["Toutes les 5 s, un météore s'écrase sur le plus gros groupe.", "Deux météores à chaque fois."]},
	{"id": "storm", "b": "elem", "tier": 3, "max": 2, "name": "Orage", "lv": ["Toutes les 2,5 s, la foudre tombe sur un ennemi et rebondit.", "La foudre tombe toutes les 1,5 s."]},
	{"id": "shatter", "b": "elem", "tier": 3, "max": 1, "name": "Zéro absolu", "desc": "Un ennemi gelé qui meurt éclate : ses éclats gèlent et blessent autour."},
	# Défense
	{"id": "heal", "b": "def", "tier": 1, "max": 5, "name": "Vitalité", "desc": "+20 PV max et 30 PV soignés tout de suite."},
	{"id": "shield", "b": "def", "tier": 1, "max": 3, "name": "Bouclier", "desc": "Absorbe un coup, se recharge en 8 s (plus vite à chaque niveau)."},
	{"id": "vamp", "b": "def", "tier": 1, "max": 3, "name": "Vampirisme", "desc": "+1 PV par ennemi tué (par niveau)."},
	{"id": "armor", "b": "def", "tier": 1, "max": 3, "name": "Blindage", "desc": "-12 % de dégâts reçus."},
	{"id": "thorns", "b": "def", "tier": 2, "max": 2, "name": "Épines", "desc": "Qui te frappe au corps à corps prend 4× tes dégâts et recule."},
	{"id": "reflex", "b": "def", "tier": 2, "max": 2, "name": "Réflexes", "desc": "Après un coup, invulnérable 0,5 s de plus."},
	{"id": "regen", "b": "def", "tier": 2, "max": 2, "name": "Nanites", "desc": "Régénère 1 PV par seconde (par niveau)."},
	{"id": "repulse", "b": "def", "tier": 3, "max": 2, "name": "Onde de choc", "lv": ["Toutes les 6 s, une onde repousse les ennemis, les blesse et efface les tirs proches.", "Une onde toutes les 4 s, plus large."]},
	{"id": "deflect", "b": "def", "tier": 3, "max": 2, "name": "Déflecteur", "lv": ["25 % des tirs ennemis qui te touchent sont renvoyés.", "45 % des tirs renvoyés."]},
	{"id": "phoenix", "b": "def", "tier": 3, "max": 1, "name": "Seconde chance", "desc": "Une fois par partie, un coup fatal te laisse à 50 % de PV et déclenche une onde."},
	# Machines
	{"id": "turret", "b": "mach", "tier": 1, "max": 3, "name": "Tourelle", "desc": "Pose une tourelle qui tire sur les ennemis."},
	{"id": "ally", "b": "mach", "tier": 1, "max": 3, "name": "Drone allié", "desc": "Un drone orbite autour de toi et tire avec toi."},
	{"id": "blades", "b": "mach", "tier": 1, "max": 3, "name": "Lames orbitales", "desc": "Deux lames tournent autour de toi et tranchent (+1 lame par niveau)."},
	{"id": "missile", "b": "mach", "tier": 2, "max": 3, "name": "Missiles", "desc": "Toutes les 2 s, des missiles à tête chercheuse (+1 par niveau)."},
	{"id": "mine", "b": "mach", "tier": 2, "max": 3, "name": "Mines", "desc": "En marchant, tu sèmes des mines (plus souvent à chaque niveau)."},
	{"id": "overclock", "b": "mach", "tier": 2, "max": 2, "name": "Surcharge", "desc": "Tourelles, drones, missiles, lames : +30 % de cadence, +25 % de dégâts."},
	{"id": "saw", "b": "mach", "tier": 3, "max": 2, "name": "Scie volante", "lv": ["Toutes les 3 s, une scie file d'ennemi en ennemi (6 rebonds).", "Deux scies à la fois."]},
	{"id": "swarm", "b": "mach", "tier": 3, "max": 2, "name": "Nuée", "lv": ["Un ennemi tué sur quatre lâche un mini-drone kamikaze.", "Presque un sur deux."]},
	# Mouvement
	{"id": "speed", "b": "move", "tier": 1, "max": 3, "name": "Vitesse", "desc": "+12 % de vitesse de déplacement."},
	{"id": "magnet", "b": "move", "tier": 1, "max": 2, "name": "Aimant", "desc": "Ramasse de bien plus loin, +15 % d'énergie par ennemi."},
	{"id": "turbo", "b": "move", "tier": 1, "max": 3, "name": "Turbo", "desc": "Esquive : recharge 20 % plus rapide."},
	{"id": "charges", "b": "move", "tier": 2, "max": 2, "name": "Double ruée", "desc": "Esquive : une charge de plus, à enchaîner."},
	{"id": "trail", "b": "move", "tier": 2, "max": 2, "name": "Traînée ardente", "lv": ["La ruée laisse une traînée de feu.", "La course aussi laisse du feu."]},
	{"id": "dashboom", "b": "move", "tier": 2, "max": 2, "name": "Ruée explosive", "desc": "La ruée finit par une explosion (plus forte au niveau II)."},
	{"id": "phantom", "b": "move", "tier": 2, "max": 2, "name": "Fantôme", "desc": "La ruée va plus loin, traverse les ennemis et les blesse."},
	{"id": "momentum", "b": "move", "tier": 3, "max": 2, "name": "Élan", "lv": ["Après une ruée : +60 % de cadence pendant 2 s.", "+100 % de cadence après une ruée."]},
	{"id": "impulse", "b": "move", "tier": 3, "max": 2, "name": "Impulsion", "lv": ["Chaque ennemi tué recharge l'esquive de 0,25 s.", "0,4 s par ennemi tué."]},
]

## Évolutions : légendaires, une seule fois par partie, quand les deux pouvoirs `need` sont au maximum.
const EVOLUTIONS := [
	{"id": "rafale", "name": "Rafale perforante", "need": ["double", "pierce"], "icon": "pierce", "desc": "Un projectile de plus, et tous les tirs traversent tout."},
	{"id": "pyro", "name": "Pyromane", "need": ["boom", "fire"], "icon": "fire", "desc": "Détonations deux fois plus grandes qui enflamment tout ce qu'elles touchent."},
	{"id": "essaim", "name": "Essaim orageux", "need": ["ally", "shock"], "icon": "ally", "desc": "Deux drones de plus ; chacun de leurs tirs lance un arc de foudre."},
	{"id": "moulinette", "name": "Tempête de lames", "need": ["blades", "speed"], "icon": "blades", "desc": "Deux fois plus de lames, en cercle qui respire ; elles coupent les tirs ennemis."},
	{"id": "blizzard", "name": "Blizzard", "need": ["frost", "aura"], "icon": "frost", "desc": "L'aura gèle net toutes les 3 s ; les gelés prennent double dégâts."},
	{"id": "salve", "name": "Salve infinie", "need": ["rate", "fan"], "icon": "fan", "desc": "Chaque tir part en éventail."},
	{"id": "forteresse", "name": "Forteresse", "need": ["shield", "armor"], "icon": "shield", "desc": "Bouclier rechargé en 3 s ; quand il cède, une onde de choc repousse tout."},
	{"id": "comete", "name": "Comète", "need": ["dashboom", "charges"], "icon": "dash", "desc": "Ruée : une charge de plus, recharge deux fois plus vite, explosion géante qui enflamme."},
	{"id": "artillerie", "name": "Arsenal volant", "need": ["missile", "turret"], "icon": "missile", "desc": "Les tourelles tirent des missiles ; deux fois plus de missiles."},
	{"id": "sangfroid", "name": "Sang d'acier", "need": ["vamp", "crit"], "icon": "vamp", "desc": "+15 % de critique ; chaque critique soigne 1 PV."},
]

const ARSENAL_SIZE := 8  # ancien arsenal (sauvegardes) : n'est plus utilisé en partie
const DEFAULT_ARSENAL := ["turret", "rate", "dmg", "speed", "double", "heal", "shield", "boom"]

static func power(id: String) -> Dictionary:
	for p in POWERS:
		if p["id"] == id:
			return p
	return {}

static func evolution(id: String) -> Dictionary:
	for p in EVOLUTIONS:
		if p["id"] == id:
			return p
	return {}

static func branch(id: String) -> Dictionary:
	return BRANCHES.get(id, BRANCHES["canon"])

const ROMAN := ["", "I", "II", "III", "IV", "V", "VI"]
static func roman(n: int) -> String:
	return ROMAN[clampi(n, 0, ROMAN.size() - 1)]

## Texte d'un pouvoir pour son niveau `level` (1 = premier).
static func power_text(p: Dictionary, level: int) -> String:
	if p.has("lv"):
		var lv: Array = p["lv"]
		return String(lv[clampi(level - 1, 0, lv.size() - 1)])
	return String(p.get("desc", ""))

# ---------------------------------------------------------------- talents (Relais)
## Talents permanents du Relais (scripts/talents.gd, livré à part) : tolère son absence.
const TALENTS_PATH := "res://scripts/talents.gd"
static var _talents: Script = null
static var _talents_tried := false

static func talents_script() -> Script:
	if not _talents_tried:
		_talents_tried = true
		if ResourceLoader.exists(TALENTS_PATH):
			_talents = load(TALENTS_PATH)
	return _talents

## Valeur d'un talent (0 si les talents ne sont pas là).
static func talent(profile: Dictionary, id: String) -> float:
	var t := talents_script()
	if t == null or profile.is_empty():
		return 0.0
	return float(t.value(profile, id))

# ---------------------------------------------------------------- loot
const SLOTS := ["arme", "arme2", "tete", "torse", "jambes", "gadget"]
const SLOT_NAMES := {"arme": "Arme", "arme2": "Module", "tete": "Tête", "torse": "Torse", "jambes": "Jambes", "gadget": "Gadget"}
const RARITY_NAMES := ["Accessoire", "Pièce de costume", "Pièce de collection", "Pièce culte"]
const RARITY_COLORS := [Color("#9FB3C8"), Color("#3CF2D8"), Color("#C77DFF"), Color("#FFB347")]
const RARITY_MULT := [1.0, 1.6, 2.4, 3.5]

# stat : dmg, rate, speed, range, energy, pickup (multiplicateurs, en fraction) ; hp (points) ; crit (fraction)
const ITEMS := [
	{"id": "blaster_garde", "slot": "arme", "name": "Blaster de garde", "stat": "dmg", "val": 0.10},
	{"id": "fusil_impulsion", "slot": "arme", "name": "Fusil à impulsion", "stat": "rate", "val": 0.12},
	{"id": "module_canon", "slot": "arme2", "name": "Module double canon", "stat": "dmg", "val": 0.08},
	{"id": "cellule", "slot": "arme2", "name": "Cellule de visée", "stat": "crit", "val": 0.05},
	{"id": "visiere", "slot": "tete", "name": "Visière de pilote", "stat": "range", "val": 0.10},
	{"id": "casque_garde", "slot": "tete", "name": "Casque de garde", "stat": "hp", "val": 10.0},
	{"id": "plastron", "slot": "torse", "name": "Plastron cargo", "stat": "hp", "val": 15.0},
	{"id": "veste", "slot": "torse", "name": "Veste de pilote", "stat": "speed", "val": 0.06},
	{"id": "bottes", "slot": "jambes", "name": "Bottes magnétiques", "stat": "speed", "val": 0.08},
	{"id": "jambieres", "slot": "jambes", "name": "Jambières de garde", "stat": "hp", "val": 8.0},
	{"id": "pile", "slot": "gadget", "name": "Pile de secours", "stat": "energy", "val": 0.15},
	{"id": "aimant", "slot": "gadget", "name": "Aimant à ferraille", "stat": "pickup", "val": 0.5},
]

static func item_template(id: String) -> Dictionary:
	for it in ITEMS:
		if it["id"] == id:
			return it
	return ITEMS[0]

## Tire un objet : rareté selon un bonus (0 = coffre normal, +1 élite, +2 boss).
static func roll_item(bonus: int) -> Dictionary:
	var r := randf()
	var rarity := 0
	if r < 0.08:
		rarity = 2
	elif r < 0.35:
		rarity = 1
	rarity = mini(rarity + bonus, 3)
	var tpl: Dictionary = ITEMS[randi() % ITEMS.size()]
	return {"id": tpl["id"], "rarity": rarity, "uid": str(Time.get_ticks_usec()) + "_" + str(randi() % 10000)}

static func item_value(inst: Dictionary) -> float:
	var tpl := item_template(inst["id"])
	return float(tpl["val"]) * RARITY_MULT[int(inst["rarity"])]

static func item_label(inst: Dictionary) -> String:
	var tpl := item_template(inst["id"])
	return String(tpl["name"])

static func item_stat_text(inst: Dictionary) -> String:
	var tpl := item_template(inst["id"])
	var v := item_value(inst)
	match String(tpl["stat"]):
		"hp":
			return "+%d PV max" % int(round(v))
		"crit":
			return "+%d %% critique" % int(round(v * 100))
		"dmg":
			return "+%d %% dégâts" % int(round(v * 100))
		"rate":
			return "+%d %% cadence" % int(round(v * 100))
		"speed":
			return "+%d %% vitesse" % int(round(v * 100))
		"range":
			return "+%d %% portée" % int(round(v * 100))
		"energy":
			return "+%d %% énergie par kill" % int(round(v * 100))
		"pickup":
			return "+%d %% rayon de ramassage" % int(round(v * 100))
	return ""

# ---------------------------------------------------------------- ennemis
const ENEMIES := {
	"drone": {"name": "Sentinelle", "hp": 22.0, "speed": 185.0, "radius": 15.0, "dmg": 8.0, "energy": 1, "tickets": 1},
	"trooper": {"name": "Garde", "hp": 48.0, "speed": 120.0, "radius": 18.0, "dmg": 8.0, "energy": 2, "tickets": 2},
	"brute": {"name": "Colosse", "hp": 170.0, "speed": 78.0, "radius": 30.0, "dmg": 22.0, "energy": 4, "tickets": 4},
	"bomber": {"name": "Pétard", "hp": 16.0, "speed": 175.0, "radius": 14.0, "dmg": 20.0, "energy": 1, "tickets": 1},
	"sniper": {"name": "Vigie", "hp": 34.0, "speed": 95.0, "radius": 16.0, "dmg": 16.0, "energy": 2, "tickets": 2},
	"shield": {"name": "Rempart", "hp": 110.0, "speed": 70.0, "radius": 24.0, "dmg": 14.0, "energy": 3, "tickets": 3},
	"mortar": {"name": "Mortier", "hp": 60.0, "speed": 60.0, "radius": 22.0, "dmg": 18.0, "energy": 3, "tickets": 3},
	"roller": {"name": "Patineur", "hp": 20.0, "speed": 230.0, "radius": 15.0, "dmg": 9.0, "energy": 1, "tickets": 1},
	"hacker": {"name": "Pirate", "hp": 38.0, "speed": 105.0, "radius": 16.0, "dmg": 8.0, "energy": 2, "tickets": 2},
	"copter": {"name": "Gyro", "hp": 44.0, "speed": 130.0, "radius": 18.0, "dmg": 7.0, "energy": 2, "tickets": 2},
	"bouncer": {"name": "Videur", "hp": 190.0, "speed": 74.0, "radius": 28.0, "dmg": 20.0, "energy": 4, "tickets": 4},
	"boss2": {"name": "L'Enseigne", "hp": 2100.0, "speed": 75.0, "radius": 60.0, "dmg": 24.0, "energy": 0, "tickets": 50},
	"boss": {"name": "Le Portique", "hp": 1700.0, "speed": 70.0, "radius": 58.0, "dmg": 25.0, "energy": 0, "tickets": 40},
}

# ---------------------------------------------------------------- salles
const ROOMS := 10

# ---------------------------------------------------------------- mondes
## Un monde par éclat du Cœur. Chaque monde a son décor (scripts/decor/<id>_world.gd, sauf Nébuleuse 7 dont le
## hangar est construit par view3d.gd), ses ennemis, son boss et ses musiques (suffixe ajouté aux pistes).
const WORLDS := [
	{"id": "n7", "name": "Nébuleuse 7", "genre": "Station de fret spatiale", "boss": "boss", "music": "", "accent": Color("#3CF2D8")},
	{"id": "neon", "name": "Cité Néon", "genre": "Mégapole cyberpunk", "boss": "boss2", "music": "_neon", "accent": Color("#FF3CAC")},
]
static var world := 0  # monde de la partie en cours

static func world_id() -> String:
	return String(WORLDS[world]["id"])

static func world_name() -> String:
	return String(WORLDS[world]["name"])

static func boss_kind() -> String:
	return String(WORLDS[world]["boss"])

## Un monde est jouable quand son décor et son boss sont livrés.
static func world_ready(i: int) -> bool:
	if i <= 0:
		return true
	var id := String(WORLDS[i]["id"])
	return ResourceLoader.exists("res://scripts/decor/%s_world.gd" % id) and has_model(String(WORLDS[i]["boss"]))

## Poids d'apparition par genre selon la salle : les nouveaux ennemis arrivent un par un.
static func _weights(room: int) -> Dictionary:
	if world_id() == "neon":
		return _weights_neon(room)
	var w := {"drone": 1.0, "bomber": 0.35}
	if room >= 2:
		w["trooper"] = 0.8
	if room >= 3:
		w["brute"] = 0.16 + room * 0.015
		w["shield"] = 0.26 + room * 0.02
	if room >= 4:
		w["sniper"] = 0.3
	if room >= 5:
		w["mortar"] = 0.26
	for k in w.keys():
		if not has_model(k):
			w.erase(k)
	return w

## Cité Néon : patineurs en meute dès le début, puis pirates, gyros, videurs ; quelques pétards de N7 en renfort.
static func _weights_neon(room: int) -> Dictionary:
	var w := {"roller": 1.0, "bomber": 0.2}
	if room >= 2:
		w["hacker"] = 0.55
	if room >= 3:
		w["copter"] = 0.5
	if room >= 4:
		w["bouncer"] = 0.2 + room * 0.015
	if room >= 6:
		w["sniper"] = 0.18
	for k in w.keys():
		if not has_model(k):
			w.erase(k)
	if w.is_empty():
		w["drone"] = 1.0
	return w

## Un genre n'entre dans les vagues que si son modèle sculpté est livré.
static func has_model(kind: String) -> bool:
	return kind in ["drone", "trooper", "brute", "boss"] or ResourceLoader.exists("res://assets/chars3d/%s.glb" % kind)

static func _pick(w: Dictionary) -> String:
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return String(k)
	return "drone"

## Vagues d'une salle : tableau de vagues, chaque vague = liste de genres ("elite:brute" = élite).
static func waves_for(room: int, modifier: String) -> Array:
	if room >= ROOMS:
		return [[boss_kind()]]
	var n_waves := 3 if room < 5 else 4
	var w := _weights(room)
	var out := []
	for wi in range(n_waves):
		var count := 6 + int(room * 1.9) + wi * 2
		if modifier == "tresor":
			count = maxi(3, int(count * 0.6))
		var wave := []
		for i in range(count):
			wave.append(_pick(w))
		if wi == n_waves - 1 and world_id() == "neon":
			var pool := ["roller", "hacker", "copter", "bouncer"].filter(func(k): return has_model(k))
			if pool.is_empty():
				pool = ["trooper"]
			if modifier == "elite" or room == 5 or room == 8 or (room >= 6 and randf() < 0.5):
				wave.append("elite:" + String(pool.pick_random()))
		elif wi == n_waves - 1:
			if modifier == "elite":
				wave.append("elite:brute" if room >= 3 else "elite:trooper")
			if room == 5:
				wave.append("elite:shield" if has_model("shield") else "elite:trooper")
			if room == 8:
				wave.append("elite:sniper" if has_model("sniper") else "elite:trooper")
			if room >= 6 and randf() < 0.5:
				var ek: String = ["trooper", "shield", "sniper", "mortar"].pick_random()
				wave.append("elite:" + (ek if has_model(ek) else "trooper"))
		out.append(wave)
	return out
