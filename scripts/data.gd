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
