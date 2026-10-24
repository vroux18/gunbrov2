extends RefCounted
## Talents permanents du Relais : la progression entre les parties. Cinq branches, trente talents à niveaux,
## achetés avec les tickets gagnés en partie ; deux nœuds clés coûtent aussi un éclat du Cœur.
## Sauvegarde : profile["talents"] = {id: niveau}. Les éclats dépensés se déduisent des niveaux achetés.
##
## Lu ailleurs : value(profile, id) (cartes, relances, pouvoir de départ, recharge de l'esquive) et
## apply(hero), appelé par hero.recalc() : bonus de stats, plus un petit nœud « Talents » sous le héros pour
## ce qui se joue en partie (régénération, seconde chance, blindage, tickets en plus, coffres…).

## Branches, de gauche à droite dans l'arbre. `x` : colonne de la branche.
const BRANCHES := [
	{"id": "survie", "name": "SURVIE", "col": Color("#5BE37A"), "x": -2},
	{"id": "puissance", "name": "PUISSANCE", "col": Color("#FF5468"), "x": -1},
	{"id": "pouvoirs", "name": "POUVOIRS", "col": Color("#C77DFF"), "x": 0},
	{"id": "fortune", "name": "FORTUNE", "col": Color("#FFB347"), "x": 1},
	{"id": "mouvement", "name": "MOUVEMENT", "col": Color("#3CF2D8"), "x": 2},
]

## Talents, dans l'ordre des prérequis (un talent ne dépend que de talents placés avant lui).
## per : gain par niveau (unité du texte `fmt`) ; per2 : second effet (coffre) ; cost : tickets par niveau ;
## shards : éclats du Cœur à dépenser ; req : {id: niveau minimum} ; pos : (décalage dans la branche, rang).
const TALENTS := [
	# ---------------- SURVIE
	{"id": "vie", "branch": "survie", "name": "PV MAX", "icon": "heart", "max": 5, "per": 12.0,
		"fmt": "+%s PV max", "desc": "Jo encaisse plus avant de tomber.",
		"cost": [15, 25, 35, 50, 65], "req": {}, "pos": Vector2(0, 1)},
	{"id": "regen", "branch": "survie", "name": "RÉGÉNÉRATION", "icon": "regen", "max": 3, "per": 0.5,
		"fmt": "+%s PV par seconde", "desc": "Les blessures se referment lentement pendant les combats.",
		"cost": [45, 70, 100], "req": {"vie": 1}, "pos": Vector2(0.5, 2)},
	{"id": "armure", "branch": "survie", "name": "BLINDAGE", "icon": "plate", "max": 4, "per": 5.0,
		"fmt": "-%s %% de dégâts reçus", "desc": "Chaque coup reçu fait moins mal.",
		"cost": [35, 55, 80, 110], "req": {"vie": 2}, "pos": Vector2(-0.5, 2)},
	{"id": "soin", "branch": "survie", "name": "PREMIERS SOINS", "icon": "kit", "max": 3, "per": 8.0,
		"fmt": "+%s %% PV à chaque salle vidée", "desc": "Jo se soigne à la fin de chaque salle.",
		"cost": [40, 65, 90], "req": {"regen": 1}, "pos": Vector2(0.5, 3)},
	{"id": "bouclier", "branch": "survie", "name": "BOUCLIER", "icon": "shield", "max": 1, "per": 1.0,
		"fmt": "+%s bouclier qui se recharge", "desc": "Un champ de force absorbe un coup entier, puis se recharge.",
		"cost": [180], "req": {"armure": 2}, "pos": Vector2(-0.5, 3)},
	{"id": "releve", "branch": "survie", "name": "SECONDE CHANCE", "icon": "revive", "max": 1, "per": 1.0,
		"fmt": "Relevée %s fois par partie", "desc": "Au K.O., Jo se relève avec la moitié de ses PV. Une fois par partie.",
		"cost": [220], "shards": 1, "req": {"soin": 1, "bouclier": 1}, "pos": Vector2(0, 4)},
	# ---------------- PUISSANCE
	{"id": "degats", "branch": "puissance", "name": "DÉGÂTS", "icon": "dmg", "max": 5, "per": 6.0,
		"fmt": "+%s %% de dégâts", "desc": "Chaque tir de Jo frappe plus fort.",
		"cost": [15, 25, 35, 50, 65], "req": {}, "pos": Vector2(0, 1)},
	{"id": "cadence", "branch": "puissance", "name": "CADENCE", "icon": "rate", "max": 4, "per": 5.0,
		"fmt": "+%s %% de cadence de tir", "desc": "Le blaster crache plus vite.",
		"cost": [35, 55, 80, 110], "req": {"degats": 1}, "pos": Vector2(-0.5, 2)},
	{"id": "critique", "branch": "puissance", "name": "CRITIQUE", "icon": "crit", "max": 4, "per": 4.0,
		"fmt": "+%s %% de coups critiques", "desc": "Un coup critique fait double dégâts.",
		"cost": [35, 55, 80, 110], "req": {"degats": 2}, "pos": Vector2(0.5, 2)},
	{"id": "portee", "branch": "puissance", "name": "PORTÉE", "icon": "range", "max": 3, "per": 10.0,
		"fmt": "+%s %% de portée de tir", "desc": "Les tirs vont plus loin : on vise de plus loin.",
		"cost": [40, 65, 90], "req": {"cadence": 1}, "pos": Vector2(-0.5, 3)},
	{"id": "chasseur", "branch": "puissance", "name": "CHASSEUR", "icon": "crown", "max": 3, "per": 12.0,
		"fmt": "+%s %% de dégâts aux élites et aux boss", "desc": "Les gros morceaux tombent plus vite.",
		"cost": [50, 80, 110], "req": {"critique": 1}, "pos": Vector2(0.5, 3)},
	{"id": "canon", "branch": "puissance", "name": "CANON JUMEAU", "icon": "double", "max": 1, "per": 1.0,
		"fmt": "+%s projectile à chaque tir", "desc": "Le blaster tire en double, dès la première salle.",
		"cost": [260], "req": {"portee": 1, "chasseur": 1}, "pos": Vector2(0, 4)},
	# ---------------- POUVOIRS
	{"id": "energie", "branch": "pouvoirs", "name": "ÉNERGIE", "icon": "bolt", "max": 5, "per": 6.0,
		"fmt": "+%s %% d'énergie gagnée", "desc": "La barre d'énergie se remplit plus vite : plus de pouvoirs.",
		"cost": [15, 25, 35, 50, 65], "req": {}, "pos": Vector2(0, 1)},
	{"id": "reroll", "branch": "pouvoirs", "name": "RELANCE", "icon": "reroll", "max": 3, "per": 1.0,
		"fmt": "%s relance(s) par partie", "desc": "Les cartes ne plaisent pas ? On en tire d'autres.",
		"cost": [50, 90, 140], "req": {"energie": 1}, "pos": Vector2(-0.5, 2)},
	{"id": "amorce", "branch": "pouvoirs", "name": "AMORCE", "icon": "battery", "max": 2, "per": 25.0,
		"fmt": "Partie lancée avec %s %% d'énergie", "desc": "La barre d'énergie n'est pas vide au départ.",
		"cost": [50, 90], "req": {"energie": 2}, "pos": Vector2(0.5, 2)},
	{"id": "resonance", "branch": "pouvoirs", "name": "RÉSONANCE", "icon": "wave", "max": 3, "per": 2.0,
		"fmt": "+%s %% de dégâts par pouvoir pris", "desc": "Plus Jo cumule de pouvoirs, plus elle cogne.",
		"cost": [60, 95, 135], "req": {"reroll": 1}, "pos": Vector2(-0.5, 3)},
	{"id": "start_power", "branch": "pouvoirs", "name": "DÉPART LANCÉ", "icon": "launch", "max": 2, "per": 1.0,
		"fmt": "Commence avec %s pouvoir(s)", "desc": "Un pouvoir au choix avant même la première vague.",
		"cost": [90, 160], "req": {"amorce": 1}, "pos": Vector2(0.5, 3)},
	{"id": "extra_card", "branch": "pouvoirs", "name": "QUATRIÈME CARTE", "icon": "cards", "max": 1, "per": 1.0,
		"fmt": "+%s carte à chaque choix de pouvoir", "desc": "Quatre cartes au lieu de trois quand l'énergie est pleine.",
		"cost": [240], "shards": 1, "req": {"resonance": 1, "start_power": 1}, "pos": Vector2(0, 4)},
	# ---------------- FORTUNE
	{"id": "butin", "branch": "fortune", "name": "BUTIN", "icon": "coins", "max": 5, "per": 6.0,
		"fmt": "+%s %% de tickets", "desc": "Chaque ticket ramassé en rapporte un peu plus.",
		"cost": [10, 20, 30, 40, 55], "req": {}, "pos": Vector2(0, 1)},
	{"id": "aimant", "branch": "fortune", "name": "AIMANT", "icon": "magnet", "max": 3, "per": 30.0,
		"fmt": "+%s %% de portée d'aimant", "desc": "Tickets et soins filent vers Jo de plus loin.",
		"cost": [25, 40, 60], "req": {"butin": 1}, "pos": Vector2(-0.5, 2)},
	{"id": "chance", "branch": "fortune", "name": "CHANCE", "icon": "luck", "max": 4, "per": 6.0,
		"fmt": "%s %% de chances qu'un objet monte d'une rareté", "desc": "Les objets trouvés sortent plus souvent rares.",
		"cost": [35, 55, 80, 110], "req": {"butin": 2}, "pos": Vector2(0.5, 2)},
	{"id": "prime", "branch": "fortune", "name": "PRIME", "icon": "bounty", "max": 3, "per": 6.0,
		"fmt": "+%s tickets par élite ou boss abattu", "desc": "Les cibles de valeur paient en plus.",
		"cost": [35, 55, 80], "req": {"aimant": 1}, "pos": Vector2(-0.5, 3)},
	{"id": "coffre", "branch": "fortune", "name": "COFFRE DORÉ", "icon": "chest", "max": 3, "per": 15.0, "per2": 5.0,
		"fmt": "+%s %% de rareté au coffre, +%s tickets", "desc": "Le coffre de fin de salle donne mieux, et crache des tickets.",
		"cost": [45, 70, 100], "req": {"chance": 1}, "pos": Vector2(0.5, 3)},
	{"id": "pactole", "branch": "fortune", "name": "PACTOLE", "icon": "bag", "max": 2, "per": 8.0,
		"fmt": "+%s tickets par salle vidée", "desc": "Une prime à chaque salle nettoyée.",
		"cost": [120, 200], "req": {"prime": 1, "coffre": 1}, "pos": Vector2(0, 4)},
	# ---------------- MOUVEMENT
	{"id": "vitesse", "branch": "mouvement", "name": "VITESSE", "icon": "speed", "max": 5, "per": 4.0,
		"fmt": "+%s %% de vitesse", "desc": "Jo court plus vite.",
		"cost": [15, 25, 35, 50, 65], "req": {}, "pos": Vector2(0, 1)},
	{"id": "dash_cd", "branch": "mouvement", "name": "ESQUIVE VIVE", "icon": "dash", "max": 4, "per": 8.0,
		"fmt": "-%s %% de recharge de l'esquive", "desc": "L'esquive revient plus vite.",
		"cost": [35, 55, 80, 110], "req": {"vitesse": 1}, "pos": Vector2(-0.5, 2)},
	{"id": "reflexes", "branch": "mouvement", "name": "RÉFLEXES", "icon": "eye", "max": 3, "per": 0.15,
		"fmt": "+%s s d'invulnérabilité après un coup", "desc": "Après un coup, Jo a le temps de se remettre.",
		"cost": [40, 65, 90], "req": {"vitesse": 2}, "pos": Vector2(0.5, 2)},
	{"id": "evasion", "branch": "mouvement", "name": "ÉVASION", "icon": "dodge", "max": 3, "per": 5.0,
		"fmt": "%s %% de chances d'éviter un coup", "desc": "Parfois, le coup passe à côté.",
		"cost": [55, 85, 120], "req": {"dash_cd": 1}, "pos": Vector2(-0.5, 3)},
	{"id": "pressee", "branch": "mouvement", "name": "PRESSÉE", "icon": "rush", "max": 1, "per": 40.0,
		"fmt": "+%s %% de vitesse quand la salle est vidée", "desc": "Le butin et le portail, en deux enjambées.",
		"cost": [60], "req": {"reflexes": 1}, "pos": Vector2(0.5, 3)},
	{"id": "adrenaline", "branch": "mouvement", "name": "ADRÉNALINE", "icon": "pulse", "max": 2, "per": 15.0,
		"fmt": "Sous 40 %% PV : +%s %% de vitesse et de cadence", "desc": "Acculée, Jo se déchaîne.",
		"cost": [150, 240], "req": {"evasion": 1, "pressee": 1}, "pos": Vector2(0, 4)},
]

static var _by_id: Dictionary = {}

static func talent(id: String) -> Dictionary:
	if _by_id.is_empty():
		for t in TALENTS:
			_by_id[String(t["id"])] = t
	return _by_id.get(id, {})

static func branch(id: String) -> Dictionary:
	for b in BRANCHES:
		if b["id"] == id:
			return b
	return BRANCHES[0]

static func color(id: String) -> Color:
	var t := talent(id)
	return branch(String(t.get("branch", ""))).get("col", Color.WHITE)

# ---------------------------------------------------------------- profil
static func levels(profile: Dictionary) -> Dictionary:
	var t = profile.get("talents", {})
	return t if typeof(t) == TYPE_DICTIONARY else {}

static func level(profile: Dictionary, id: String) -> int:
	return int(levels(profile).get(id, 0))

## Valeur cumulée d'un talent (unité du texte : PV, %, secondes, nombre de cartes…). 0 si non pris.
static func value(profile: Dictionary, id: String) -> float:
	var t := talent(id)
	if t.is_empty():
		return 0.0
	return float(t["per"]) * mini(level(profile, id), int(t["max"]))

## Second effet (coffre : tickets en plus).
static func value2(profile: Dictionary, id: String) -> float:
	var t := talent(id)
	if t.is_empty():
		return 0.0
	return float(t.get("per2", 0.0)) * mini(level(profile, id), int(t["max"]))

## Coût du prochain niveau : {tickets, shards}.
static func cost(id: String, lvl: int) -> Dictionary:
	var t := talent(id)
	if t.is_empty() or lvl >= int(t["max"]):
		return {"tickets": 0, "shards": 0}
	var c: Array = t["cost"]
	return {"tickets": int(c[mini(lvl, c.size() - 1)]), "shards": int(t.get("shards", 0)) if lvl == 0 else 0}

static func shards_spent(profile: Dictionary) -> int:
	var n := 0
	for id in levels(profile).keys():
		var t := talent(String(id))
		if not t.is_empty() and int(levels(profile)[id]) > 0:
			n += int(t.get("shards", 0))
	return n

static func shards_free(profile: Dictionary) -> int:
	return maxi(0, int(profile.get("shards", 0)) - shards_spent(profile))

static func unlocked(profile: Dictionary, id: String) -> bool:
	var req: Dictionary = talent(id).get("req", {})
	for r in req.keys():
		if level(profile, String(r)) < int(req[r]):
			return false
	return true

## Prérequis manquants, en texte (« BLINDAGE niv. 2 »).
static func missing(profile: Dictionary, id: String) -> Array:
	var out := []
	var req: Dictionary = talent(id).get("req", {})
	for r in req.keys():
		if level(profile, String(r)) < int(req[r]):
			out.append("%s niv. %d" % [String(talent(String(r))["name"]), int(req[r])])
	return out

## Pourquoi on ne peut pas acheter ("" si possible) : max, locked, tickets, shards.
static func block_reason(profile: Dictionary, id: String) -> String:
	var t := talent(id)
	var lv := level(profile, id)
	if lv >= int(t["max"]):
		return "max"
	if not unlocked(profile, id):
		return "locked"
	var c := cost(id, lv)
	if shards_free(profile) < int(c["shards"]):
		return "shards"
	if int(profile.get("tickets", 0)) < int(c["tickets"]):
		return "tickets"
	return ""

static func buy(profile: Dictionary, id: String) -> bool:
	if block_reason(profile, id) != "":
		return false
	var lv := level(profile, id)
	var c := cost(id, lv)
	profile["tickets"] = int(profile["tickets"]) - int(c["tickets"])
	var lv_map := levels(profile)
	lv_map[id] = lv + 1
	profile["talents"] = lv_map
	return true

## Nettoyage au chargement : talents connus, niveaux entiers bornés.
static func sanitize(raw) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for k in raw.keys():
		var t := talent(String(k))
		if t.is_empty():
			continue
		var lv := clampi(int(raw[k]), 0, int(t["max"]))
		if lv > 0:
			out[String(k)] = lv
	return out

static func total_levels() -> int:
	var n := 0
	for t in TALENTS:
		n += int(t["max"])
	return n

static func owned_levels(profile: Dictionary) -> int:
	var n := 0
	for t in TALENTS:
		n += mini(level(profile, String(t["id"])), int(t["max"]))
	return n

static func total_cost() -> int:
	var n := 0
	for t in TALENTS:
		for c in t["cost"]:
			n += int(c)
	return n

## Nombre lisible : 12, 0.5, 0.15.
static func num(v: float) -> String:
	if is_equal_approx(v, round(v)):
		return str(int(round(v)))
	var s := "%.2f" % v
	return s.rstrip("0").rstrip(".")

## Effet d'un talent au niveau `lvl` (texte), « — » au niveau 0.
static func effect_text(id: String, lvl: int) -> String:
	var t := talent(id)
	if lvl <= 0:
		return "—"
	var v := float(t["per"]) * lvl
	if t.has("per2"):
		return String(t["fmt"]) % [num(v), num(float(t["per2"]) * lvl)]
	return String(t["fmt"]) % num(v)

# ---------------------------------------------------------------- en partie
static func _profile_of(hero: Object) -> Dictionary:
	if hero != null and hero.has_meta("profile"):
		var p = hero.get_meta("profile")
		if typeof(p) == TYPE_DICTIONARY:
			return p
	return {}

static func _mul(o: Object, prop: String, f: float) -> void:
	if prop in o:
		o.set(prop, float(o.get(prop)) * f)

static func _add(o: Object, prop: String, v: float) -> void:
	if prop in o:
		if typeof(o.get(prop)) == TYPE_INT:
			o.set(prop, int(o.get(prop)) + int(round(v)))
		else:
			o.set(prop, float(o.get(prop)) + v)

## Bonus de stats des talents, appliqués par-dessus objets et pouvoirs (hero.recalc()).
static func apply(hero: Object) -> void:
	var p := _profile_of(hero)
	if p.is_empty() or levels(p).is_empty():
		return
	var vals := {}
	for t in TALENTS:
		var id := String(t["id"])
		if level(p, id) > 0:
			vals[id] = value(p, id)
	vals["coffre2"] = value2(p, "coffre")
	var v := func(id: String) -> float: return float(vals.get(id, 0.0))
	_add(hero, "hp_max", v.call("vie"))
	var npow := 0
	var pw = hero.get("powers")
	if typeof(pw) == TYPE_DICTIONARY:
		for k in pw.keys():
			npow += int(pw[k])
	_mul(hero, "dmg", (1.0 + v.call("degats") / 100.0) * (1.0 + v.call("resonance") / 100.0 * npow))
	_mul(hero, "rate", 1.0 + v.call("cadence") / 100.0)
	_add(hero, "crit", v.call("critique") / 100.0)
	_mul(hero, "rng", 1.0 + v.call("portee") / 100.0)
	_add(hero, "projectiles", v.call("canon"))
	_mul(hero, "energy_mult", 1.0 + v.call("energie") / 100.0)
	_mul(hero, "magnet", 1.0 + v.call("aimant") / 100.0)
	_mul(hero, "speed", 1.0 + v.call("vitesse") / 100.0)
	_add(hero, "shield_max", v.call("bouclier"))
	# les bonus variables (adrénaline, pressée) repartent de zéro : recalc() vient de tout recalculer
	hero.set_meta("tal_fs", 1.0)
	hero.set_meta("tal_fr", 1.0)
	if hero is Node and not (hero as Node).has_node("Talents"):
		var tk := Ticker.new()
		tk.name = "Talents"
		tk.hero = hero
		(hero as Node).add_child(tk)
	if hero is Node and (hero as Node).has_node("Talents"):
		(hero as Node).get_node("Talents").set("vals", vals)

## Ce qui se joue pendant la partie : régénération, tickets en plus, coups encaissés, seconde chance,
## fin de salle, coffres, élites. Branché sur les signaux de l'arène et du héros, sans toucher à leur code.
class Ticker extends Node:
	var hero = null  # non typés : propriétés du script du héros et de l'arène
	var vals := {}
	var arena = null
	var _run := -1
	var _hp_ref := 0.0
	var _last_tickets := 0
	var _acc := 0.0
	var _revived := false
	var _chest := false
	var _kills := 0

	func _v(id: String) -> float:
		return float(vals.get(id, 0.0))

	func _ready() -> void:
		if hero.has_signal("damaged"):
			hero.damaged.connect(_on_damaged)
		_hp_ref = float(hero.get("hp"))

	func _connect_arena() -> void:
		arena = hero.get("arena")
		if arena == null:
			return
		if arena.has_signal("enemy_spawned"):
			arena.enemy_spawned.connect(_on_spawn)
		if arena.has_signal("room_cleared"):
			arena.room_cleared.connect(_on_cleared)
		if arena.has_signal("chest_opened"):
			arena.chest_opened.connect(_on_chest)
		if arena.has_signal("enemy_killed"):
			arena.enemy_killed.connect(_on_killed)
		if arena.has_signal("item_found"):
			# la rareté se décide avant que l'écran « OBJET TROUVÉ » ne l'affiche : on passe en premier
			var others: Array = arena.item_found.get_connections()
			for c in others:
				arena.item_found.disconnect(c["callable"])
			arena.item_found.connect(_on_item)
			for c in others:
				arena.item_found.connect(c["callable"], int(c["flags"]))

	func _process(dt: float) -> void:
		if bool(hero.get("preview")):
			return
		if arena == null:
			_connect_arena()
			if arena == null:
				return
		if not bool(arena.get("running")) or bool(hero.get("dead")):
			_hp_ref = float(hero.hp)
			return
		var p: Dictionary = hero.get_meta("profile", {})
		var runs := int(p.get("runs", 0))
		if runs != _run:
			# nouvelle partie
			_run = runs
			_revived = false
			_acc = 0.0
			_last_tickets = int(arena.tickets)
			_kills = int(arena.kills)
			if _v("amorce") > 0.0 and int(arena.room) <= 1:
				arena.energy = maxf(float(arena.energy), float(arena.energy_need) * _v("amorce") / 100.0)
		if _v("regen") > 0.0 and hero.hp < hero.hp_max:
			hero.heal(_v("regen") * dt)
		# tickets en plus : un reste fractionnaire s'accumule
		if int(arena.tickets) < _last_tickets:
			_last_tickets = int(arena.tickets)
		var d := int(arena.tickets) - _last_tickets
		if d > 0 and _v("butin") > 0.0:
			_acc += d * _v("butin") / 100.0
			var n := int(_acc)
			_acc -= n
			arena.tickets += n
		_last_tickets = int(arena.tickets)
		# vitesse et cadence variables : appliquées en facteur, retirées dès que la condition tombe
		var fs := 1.0
		var fr := 1.0
		if _v("pressee") > 0.0 and bool(arena.get("cleared")):
			fs *= 1.0 + _v("pressee") / 100.0
		if _v("adrenaline") > 0.0 and hero.hp < hero.hp_max * 0.4:
			fs *= 1.0 + _v("adrenaline") / 100.0
			fr *= 1.0 + _v("adrenaline") / 100.0
		var ofs := float(hero.get_meta("tal_fs", 1.0))
		if not is_equal_approx(fs, ofs):
			hero.speed *= fs / ofs
			hero.set_meta("tal_fs", fs)
		var ofr := float(hero.get_meta("tal_fr", 1.0))
		if not is_equal_approx(fr, ofr):
			hero.rate *= fr / ofr
			hero.set_meta("tal_fr", fr)
		_hp_ref = float(hero.hp)

	func _main():
		return arena.get_parent() if arena != null else null

	## Appelé juste après la perte de PV, avant le test de K.O. : on rend une part du coup, on peut relever Jo.
	func _on_damaged() -> void:
		if bool(hero.get("preview")):
			return
		var loss := _hp_ref - float(hero.hp)
		if loss > 0.0:
			if _v("evasion") > 0.0 and randf() < _v("evasion") / 100.0:
				hero.hp += loss
				_say("ESQUIVÉ", Color("#3CF2D8"), 0.6)
			elif _v("armure") > 0.0:
				hero.hp += loss * _v("armure") / 100.0
		if _v("reflexes") > 0.0:
			hero.invuln += _v("reflexes")
		if hero.hp <= 0.0 and _v("releve") > 0.0 and not _revived:
			_revived = true
			hero.hp = hero.hp_max * 0.5
			hero.invuln = maxf(float(hero.invuln), 2.5)
			_say("SECONDE CHANCE", Color("#5BE37A"), 1.6)
			if arena != null and arena.get("sfx") != null:
				arena.sfx.play("level", 1.2)
			var m = _main()
			if m != null and m.get("view") != null and m.view.has_method("power_fx"):
				m.view.power_fx()
		_hp_ref = float(hero.hp)

	func _say(text: String, col: Color, t: float) -> void:
		var m = _main()
		if m != null and m.get("hud") != null and m.hud.has_method("flash"):
			m.hud.flash(text, t, col)

	func _on_spawn(e) -> void:
		var ch := _v("chasseur")
		if ch <= 0.0:
			return
		if bool(e.get("elite")) or String(e.get("kind")).begins_with("boss"):
			# dégâts en plus contre elle = moins de PV, pour le même effet
			var f := 1.0 + ch / 100.0
			e.hp_max = float(e.hp_max) / f
			e.hp = float(e.hp) / f

	func _on_cleared() -> void:
		if _v("soin") > 0.0:
			hero.heal(hero.hp_max * _v("soin") / 100.0)
		if _v("pactole") > 0.0:
			arena.tickets += int(_v("pactole"))

	func _on_chest(pos: Vector2) -> void:
		_chest = true
		_spill(pos, int(_v("coffre2")))

	func _on_item(item: Dictionary) -> void:
		var ch := _v("chance") / 100.0
		if _chest:
			ch += _v("coffre") / 100.0
		_chest = false
		if ch > 0.0 and int(item.get("rarity", 0)) < 3 and randf() < ch:
			item["rarity"] = int(item["rarity"]) + 1

	func _on_killed(e) -> void:
		if int(arena.kills) == _kills:
			return  # ennemi retiré sans récompense
		_kills = int(arena.kills)
		if _v("prime") > 0.0 and (bool(e.get("elite")) or String(e.get("kind")).begins_with("boss")):
			_spill(e.position, int(_v("prime")))

	## Tickets qui jaillissent au sol (ramassés comme les autres).
	func _spill(pos: Vector2, n: int) -> void:
		if n <= 0 or not ("pickups" in arena):
			return
		for i in range(n):
			arena.pickups.append({"pos": pos, "kind": "ticket", "vel": Vector2.RIGHT.rotated(randf() * TAU) * randf_range(80, 240), "t": 0.0})
