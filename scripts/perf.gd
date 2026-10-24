extends Node
## Qualité adaptative (téléphone et web seulement) : mesure les images par seconde en partie et, si le jeu
## passe durablement sous 50, baisse d'un cran la résolution 3D, puis coupe les ombres du soleil.
## Ne remonte jamais en cours de partie (pas d'oscillation) ; le niveau trouvé est mémorisé.

const SAVE := "user://perf.cfg"
## Paliers : [échelle de la 3D, ombres du soleil]
const LEVELS := [[1.0, true], [0.85, true], [0.75, false], [0.62, false]]
const WINDOW := 2.0  # secondes par mesure
const LOW_FPS := 50.0

var level := 0
var enabled := false
var _t := 0.0
var _frames := 0
var _low := 0
var _warmup := 6.0

func _ready() -> void:
	var movie := "--write-movie" in OS.get_cmdline_args()
	enabled = (OS.has_feature("mobile") or OS.has_feature("web")) and DisplayServer.get_name() != "headless" and not movie
	if not enabled:
		return
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		level = clampi(int(cf.get_value("perf", "level", 0)), 0, LEVELS.size() - 1)
	get_tree().node_added.connect(_on_node_added)
	_apply()

func _process(dt: float) -> void:
	if not enabled or level >= LEVELS.size() - 1:
		return
	# on ne mesure qu'en partie (le soleil du hangar existe et le jeu n'est pas en pause)
	if get_tree().paused or get_tree().get_nodes_in_group("sun").is_empty():
		_t = 0.0
		_frames = 0
		return
	if _warmup > 0.0:
		_warmup -= dt
		return
	_t += dt
	_frames += 1
	if _t < WINDOW:
		return
	var fps := _frames / _t
	_t = 0.0
	_frames = 0
	_low = _low + 1 if fps < LOW_FPS else 0
	if _low >= 2:
		_low = 0
		level += 1
		_apply()
		_warmup = 3.0
		var cf := ConfigFile.new()
		cf.set_value("perf", "level", level)
		cf.save(SAVE)

func _apply() -> void:
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = float(LEVELS[level][0])
	for n in get_tree().get_nodes_in_group("sun"):
		(n as DirectionalLight3D).shadow_enabled = bool(LEVELS[level][1])

func _on_node_added(n: Node) -> void:
	if n is DirectionalLight3D and n.is_in_group("sun") and not bool(LEVELS[level][1]):
		(n as DirectionalLight3D).shadow_enabled = false
