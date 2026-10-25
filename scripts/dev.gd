extends Node
## Réglages du joueur et du mode développeur, gardés sur l'appareil (user://dev.cfg) :
## caméra de jeu (recul, inclinaison, champ), taille de Jo et des ennemis, cadence visée (60 / 120 i/s),
## compteur d'images par seconde. La vue (view3d.gd) lit ces valeurs à chaque image.

const CFG := "user://dev.cfg"
const VERSION := 6  # 2 : Jo à 1,15 ; 3 : Jo à 0,95 ; 4 : nouvelle Jo (1,26 de haut) à 0,65 ; 5 : caméra plus proche (9) et Jo à 0,8
## Valeurs par défaut (et bornes des curseurs du mode développeur). all_worlds : version de démo, le monde 2
## est ouvert sans finir le monde 1 (le mode développeur le referme).
const DEFAULTS := {"cam_dist": 9.0, "cam_pitch": 56.0, "cam_fov": 38.0, "hero_scale": 0.8, "mob_scale": 1.0, "fps": 60, "show_fps": false, "dev": false, "all_worlds": true, "quality": 1, "sticks_free": true, "jo_twos": true, "comic": true, "bd_fx": true}
const RANGES := {"cam_dist": [6.0, 24.0], "cam_pitch": [30.0, 85.0], "cam_fov": [24.0, 70.0], "hero_scale": [0.6, 2.2], "mob_scale": [0.6, 1.4]}
## Préréglages du menu pause (boutons VUE et ANGLE).
const ZOOMS := [["PROCHE", 8.0], ["NORMALE", 9.0], ["LARGE", 11.5], ["TRÈS LARGE", 14.0]]
const ANGLES := [["PLONGÉE", 66.0], ["STANDARD", 56.0], ["RASANTE", 46.0]]
## Qualité (téléphone) : [nom, échelle de la 3D, ombres du soleil, images par seconde au plus en partie].
## La 3D est calculée en dessous de la résolution de l'écran (l'interface reste nette) : c'est ce qui chauffe
## le plus. Hors partie (Relais, écrans), le jeu tourne à MENU_FPS.
const QUALITY := [["ÉCO", 0.6, false, 30], ["NORMALE", 0.75, true, 60], ["MAX", 1.0, true, 120]]
const MENU_FPS := 30

var v := DEFAULTS.duplicate()
var _label: Label
var _layer: CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		for k in DEFAULTS.keys():
			v[k] = cf.get_value("dev", k, DEFAULTS[k])
		# réglages enregistrés avant un changement de valeur par défaut : la nouvelle valeur l'emporte
		if int(cf.get_value("dev", "version", 1)) < VERSION:
			v["hero_scale"] = DEFAULTS["hero_scale"]
			v["cam_dist"] = DEFAULTS["cam_dist"]
	# « --devset=clé:valeur » (planches, mesures) : réglage pour ce lancement, non enregistré
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--devset=") and ":" in a:
			var kv := a.trim_prefix("--devset=").split(":")
			if DEFAULTS.has(kv[0]):
				v[kv[0]] = str_to_var(kv[1])
				_no_save = true
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

var _no_save := false
func save() -> void:
	if _no_save:
		return
	var cf := ConfigFile.new()
	cf.set_value("dev", "version", VERSION)
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
	return "recul %.1f · angle %d° · champ %d° · Jo ×%.2f · ennemis ×%.2f · %d i/s · qualité %s" % [get_f("cam_dist"), int(get_f("cam_pitch")), int(get_f("cam_fov")), get_f("hero_scale"), get_f("mob_scale"), int(v["fps"]), String(quality()[0])]

func quality() -> Array:
	return QUALITY[clampi(int(v["quality"]), 0, QUALITY.size() - 1)]

func _apply() -> void:
	_in_run = _playing()
	if Perf.enabled:  # téléphone et web
		Engine.max_fps = mini(int(v["fps"]), int(quality()[3])) if _in_run else menu_fps()
	else:
		Engine.max_fps = int(v["fps"])
	_label.visible = bool(v["show_fps"])
	Perf.apply_quality()

func menu_fps() -> int:
	return mini(MENU_FPS, int(quality()[3]))

## En partie (arène) : sinon Relais et écrans, à cadence réduite.
var _in_run := false
var _poll := 0.0
func _playing() -> bool:
	var sc := get_tree().current_scene
	return sc != null and str(sc.get("state")) == "arena"

func _process(dt: float) -> void:
	_poll -= dt
	if _poll <= 0.0:
		_poll = 0.5
		if _playing() != _in_run:
			_apply()
	if _perf_stats:
		_perf_tick(dt)
	if _label.visible:
		_label.text = "%d i/s · %d appels · %dk tri" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)]

## « --perfstats » : en partie (ou dans une scène d'outil, tools/), toutes les 2 s, moyenne du temps par image,
## appels de dessin, objets et primitives (sortie standard), cadence libre. Pour comparer deux versions sur la même
## machine.
var _perf_stats := "--perfstats" in OS.get_cmdline_user_args()
var _ps_t := 0.0
var _ps_n := 0
var _ps_dc := 0.0
var _ps_pr := 0.0
var _ps_ob := 0.0
func _perf_tick(dt: float) -> void:
	var sc := get_tree().current_scene
	if get_tree().paused or sc == null or not (_in_run or sc.scene_file_path.begins_with("res://tools/")):
		return
	Engine.max_fps = 0
	_ps_t += dt
	_ps_n += 1
	_ps_dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_ps_ob += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_ps_pr += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	if _ps_t < 2.0:
		return
	print("PERFSTATS %.2f ms/image · %d appels · %d objets · %dk tri" % [_ps_t * 1000.0 / _ps_n, int(_ps_dc / _ps_n), int(_ps_ob / _ps_n), int(_ps_pr / _ps_n / 1000.0)])
	_ps_t = 0.0
	_ps_n = 0
	_ps_dc = 0.0
	_ps_ob = 0.0
	_ps_pr = 0.0
