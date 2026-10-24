extends Node
## Réglages du joueur et du mode développeur, gardés sur l'appareil (user://dev.cfg) :
## caméra de jeu (recul, inclinaison, champ), taille de Jo et des ennemis, cadence visée (60 / 120 i/s),
## compteur d'images par seconde. La vue (view3d.gd) lit ces valeurs à chaque image.

const CFG := "user://dev.cfg"
## Valeurs par défaut (et bornes des curseurs du mode développeur).
const DEFAULTS := {"cam_dist": 11.5, "cam_pitch": 56.0, "cam_fov": 38.0, "hero_scale": 1.35, "mob_scale": 1.0, "fps": 60, "show_fps": false, "dev": false}
const RANGES := {"cam_dist": [6.0, 24.0], "cam_pitch": [30.0, 85.0], "cam_fov": [24.0, 70.0], "hero_scale": [0.9, 2.2], "mob_scale": [0.6, 1.4]}
## Préréglages du menu pause (boutons VUE et ANGLE).
const ZOOMS := [["PROCHE", 9.0], ["NORMALE", 11.5], ["LARGE", 14.0], ["TRÈS LARGE", 16.5]]
const ANGLES := [["PLONGÉE", 66.0], ["STANDARD", 56.0], ["RASANTE", 46.0]]

var v := DEFAULTS.duplicate()
var _label: Label
var _layer: CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		for k in DEFAULTS.keys():
			v[k] = cf.get_value("dev", k, DEFAULTS[k])
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_label = Label.new()
	_label.position = Vector2(14, 92)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.9))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 6)
	_layer.add_child(_label)
	_apply()

func get_f(key: String) -> float:
	return float(v[key])

func set_value(key: String, value) -> void:
	if RANGES.has(key):
		value = clampf(float(value), RANGES[key][0], RANGES[key][1])
	v[key] = value
	_apply()
	save()

func reset() -> void:
	var keep_dev: bool = v["dev"]
	v = DEFAULTS.duplicate()
	v["dev"] = keep_dev
	_apply()
	save()

func save() -> void:
	var cf := ConfigFile.new()
	for k in v.keys():
		cf.set_value("dev", k, v[k])
	cf.save(CFG)

## Préréglage le plus proche de la valeur courante (pour l'affichage des boutons VUE et ANGLE).
func nearest(presets: Array, value: float) -> int:
	var best := 0
	for i in range(presets.size()):
		if absf(float(presets[i][1]) - value) < absf(float(presets[best][1]) - value):
			best = i
	return best

## Résumé des réglages, à recopier pour les retenir comme valeurs par défaut du jeu.
func summary() -> String:
	return "recul %.1f · angle %d° · champ %d° · Jo ×%.2f · ennemis ×%.2f · %d i/s" % [get_f("cam_dist"), int(get_f("cam_pitch")), int(get_f("cam_fov")), get_f("hero_scale"), get_f("mob_scale"), int(v["fps"])]

func _apply() -> void:
	Engine.max_fps = int(v["fps"])
	_label.visible = bool(v["show_fps"])

func _process(_dt: float) -> void:
	if _label.visible:
		_label.text = "%d i/s · %d appels · %dk tri" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)]
