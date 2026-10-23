extends RefCounted
## Données fixes du jeu : pouvoirs de l'arsenal, objets de loot, ennemis, plan des salles.

# ---------------------------------------------------------------- pouvoirs
# Chaque pouvoir se cumule jusqu'à « max » fois dans une partie.
const POWERS := [
	{"id": "turret", "name": "Tourelle", "desc": "Pose une tourelle qui tire sur les ennemis.", "max": 3},
	{"id": "rate", "name": "Cadence", "desc": "+25 % de cadence de tir.", "max": 4},
	{"id": "dmg", "name": "Dégâts", "desc": "+20 % de dégâts.", "max": 4},
	{"id": "speed", "name": "Vitesse", "desc": "+15 % de vitesse de déplacement.", "max": 3},
	{"id": "double", "name": "Tir double", "desc": "Un projectile de plus par tir.", "max": 2},
	{"id": "bounce", "name": "Rebond", "desc": "Les tirs rebondissent sur les murs.", "max": 2},
	{"id": "pierce", "name": "Perforant", "desc": "Les tirs traversent un ennemi de plus.", "max": 2},
	{"id": "heal", "name": "Soin", "desc": "+30 PV maintenant, +10 PV max.", "max": 5},
	{"id": "shield", "name": "Bouclier", "desc": "Absorbe un coup toutes les 8 s.", "max": 2},
	{"id": "magnet", "name": "Aimant", "desc": "Ramasse les tickets de plus loin.", "max": 2},
	{"id": "boom", "name": "Détonation", "desc": "Les ennemis tués explosent.", "max": 2},
	{"id": "ally", "name": "Drone allié", "desc": "Un drone orbite et tire avec toi.", "max": 2},
	{"id": "slow", "name": "Ralenti", "desc": "Les ennemis sont 10 % plus lents.", "max": 3},
	{"id": "crit", "name": "Critique", "desc": "15 % de chances de dégâts doublés.", "max": 3},
	{"id": "range", "name": "Portée", "desc": "+25 % de portée.", "max": 2},
	{"id": "vamp", "name": "Vampirisme", "desc": "+1 PV par ennemi tué.", "max": 2},
]
const ARSENAL_SIZE := 8
const DEFAULT_ARSENAL := ["turret", "rate", "dmg", "speed", "double", "heal", "shield", "boom"]

static func power(id: String) -> Dictionary:
	for p in POWERS:
		if p["id"] == id:
			return p
	return {}

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
	"boss": {"name": "Le Portique", "hp": 1700.0, "speed": 70.0, "radius": 58.0, "dmg": 25.0, "energy": 0, "tickets": 40},
}

# ---------------------------------------------------------------- salles
const ROOMS := 10
const WORLD_NAME := "Nébuleuse 7"

## Vagues d'une salle : tableau de vagues, chaque vague = liste de genres ("elite:brute" = élite).
static func waves_for(room: int, modifier: String) -> Array:
	if room >= ROOMS:
		return [["boss"]]
	var n_waves := 3 if room < 5 else 4
	var out := []
	for w in range(n_waves):
		var count := 4 + int(room * 1.4) + w
		if modifier == "tresor":
			count = maxi(3, int(count * 0.6))
		var wave := []
		for i in range(count):
			var r := randf()
			var kind := "drone"
			if room >= 2 and r < 0.38:
				kind = "trooper"
			if room >= 3 and r < 0.10 + room * 0.012:
				kind = "brute"
			wave.append(kind)
		if w == n_waves - 1:
			if modifier == "elite":
				wave.append("elite:brute" if room >= 3 else "elite:trooper")
			if room == 5 or room == 8:
				wave.append("elite:trooper")
		out.append(wave)
	return out
