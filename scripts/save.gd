extends RefCounted
## Profil du joueur, gardé sur l'appareil (user://passeurs.json).
## Le loot et l'arsenal survivent aux parties ; les pouvoirs d'une partie non.

const PATH := "user://passeurs.json"
const Data = preload("res://scripts/data.gd")
const Loot = preload("res://scripts/loot.gd")

static func default_profile() -> Dictionary:
	var p := {
		"version": 1,
		"inventory": [],  # instances d'objets {id, rarity, uid}
		"equipped": {},  # slot -> uid
		"arsenal": Data.DEFAULT_ARSENAL.duplicate(),
		"shards": 0,  # éclats du Cœur : un par monde terminé
		"worlds_done": [],  # indices des mondes terminés (boss vaincu)
		"world": 0,  # dernier monde choisi au Relais
		"tickets": 0,
		"best_room": 0,
		"runs": 0,
		"kills": 0,
		"seen_enemies": [],  # genres déjà présentés par la carte « NOUVEL ENNEMI »
		"tutorial_done": false,  # tutoriel des deux pouces fait
	}
	# box à ouvrir, apparences et traînées de tir (scripts/loot.gd)
	p.merge(Loot.default_fields())
	return p

## `--fresh` (captures, essais) : profil neuf, écrit à part pour ne pas toucher la vraie sauvegarde.
static func _path() -> String:
	return "user://passeurs_fresh.json" if "--fresh" in OS.get_cmdline_user_args() else PATH

static func load_profile() -> Dictionary:
	var p := default_profile()
	if "--fresh" in OS.get_cmdline_user_args() or not FileAccess.file_exists(PATH):
		return p
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return p
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return p
	for k in p.keys():
		if parsed.has(k):
			p[k] = parsed[k]
	# ancienne sauvegarde : les éclats comptaient chaque victoire ; un éclat = un monde terminé
	if not parsed.has("worlds_done") and int(p["shards"]) > 0:
		p["worlds_done"] = [0]
	p["shards"] = (p["worlds_done"] as Array).size()
	# ancienne sauvegarde : qui a déjà joué n'a pas besoin du tutoriel
	if not parsed.has("tutorial_done") and int(p["runs"]) > 0:
		p["tutorial_done"] = true
	# sécurité : arsenal borné et connu
	var ars := []
	for id in p["arsenal"]:
		if not Data.power(String(id)).is_empty() and ars.size() < Data.ARSENAL_SIZE:
			ars.append(String(id))
	if ars.is_empty():
		ars = Data.DEFAULT_ARSENAL.duplicate()
	p["arsenal"] = ars
	Loot.sanitize(p)  # ancienne sauvegarde : pas de box, apparence et traînée d'origine
	return p

static func save_profile(p: Dictionary) -> void:
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f == null:
		push_warning("Passeurs : impossible d'écrire la sauvegarde")
		return
	f.store_string(JSON.stringify(p))

static func find_item(p: Dictionary, uid: String) -> Dictionary:
	for it in p["inventory"]:
		if String(it["uid"]) == uid:
			return it
	return {}

## Objets équipés, par slot (instances), pour calculer les stats du héros.
static func equipped_items(p: Dictionary) -> Array:
	var out := []
	for slot in p["equipped"].keys():
		var it := find_item(p, String(p["equipped"][slot]))
		if not it.is_empty():
			out.append(it)
	return out

static func equip(p: Dictionary, uid: String) -> void:
	var it := find_item(p, uid)
	if it.is_empty():
		return
	var slot: String = Data.item_template(it["id"])["slot"]
	p["equipped"][slot] = uid

static func unequip(p: Dictionary, slot: String) -> void:
	p["equipped"].erase(slot)
