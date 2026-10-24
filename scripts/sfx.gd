extends Node
## Bruitages : sons Kenney (CC0), sons synthétisés au lancement en secours.
## Mixage par type : nombre de voix simultanées limité (la plus ancienne cède sa place), intervalle minimal,
## variation de hauteur aléatoire, gain propre, et atténuation quand plusieurs sons du même type se superposent
## (25 ennemis à l'écran ne font pas un mur de bruit). Les variantes d'un même son sont égalisées.

const RATE := 22050
const VOICES := 18
## type : [voix simultanées max, intervalle minimal (ms), variation de hauteur (±), gain (dB)]
const MIX := {
	"shoot": [2, 70, 0.05, -3.0],
	"eshoot": [3, 90, 0.08, -5.0],
	"bigshoot": [2, 120, 0.05, -2.0],
	"hit": [3, 55, 0.10, -3.0],
	"kill": [4, 60, 0.08, -1.0],
	"boom": [3, 110, 0.06, -3.0],
	"hurt": [2, 120, 0.04, 0.0],
	"portal": [1, 250, 0.03, -7.0],
	"spawn": [2, 140, 0.08, 0.0],
	"pick": [3, 45, 0.05, 0.0],
	"chest": [1, 200, 0.0, -1.0],
	"level": [1, 200, 0.0, -1.0],
	"click": [2, 50, 0.04, 0.0],
	"drop": [2, 80, 0.06, -2.0],
}
const DEFAULT_MIX := [3, 40, 0.05, 0.0]
## chaque voix de plus du même type déjà en cours baisse la nouvelle de ce nombre de dB
const STACK_DB := -2.5
## égalisation des variantes (dB) : mesuré sur le niveau des 50 ms les plus fortes
const TRIM := {
	"laserRetro_000": -6.0, "laserRetro_001": -6.0,
	"laserSmall_001": -1.0,
	"confirmation_004": -2.5,
	"impactMetal_light_003": -1.0,
	"lowFrequency_explosion_001": -0.8,
}

var muted := false
var _streams := {}
var _variants := {}   # type -> [[stream, trim_db], ...]
var _players: Array = []
var _owner: Array = []    # type joué par chaque voix
var _started: Array = []  # instant de départ de chaque voix (ms)
var _last := {}
var _last_variant := {}

func _ready() -> void:
	# les sons d'interface (choix de pouvoir, objet trouvé) se jouent aussi quand le jeu est en pause
	process_mode = Node.PROCESS_MODE_ALWAYS
	_streams["shoot"] = _make(0.07, func(t: float, p: float): return _sq(t, 520.0 - 300.0 * p) * (1.0 - p) * 0.25)
	_streams["hit"] = _make(0.06, func(t: float, p: float): return _noise() * (1.0 - p) * 0.35)
	_streams["kill"] = _make(0.22, func(t: float, p: float): return (_sq(t, 220.0 - 150.0 * p) * 0.5 + _noise() * 0.5) * (1.0 - p) * 0.5)
	_streams["hurt"] = _make(0.18, func(t: float, p: float): return _sq(t, 110.0) * (1.0 - p) * 0.6)
	_streams["pick"] = _make(0.09, func(t: float, p: float): return sin(TAU * t * (880.0 + 660.0 * p)) * (1.0 - p) * 0.35)
	_streams["level"] = _make(0.5, func(t: float, p: float): return sin(TAU * t * (440.0 * pow(2.0, floor(p * 4.0) / 4.0 * 1.0))) * (1.0 - p) * 0.4)
	_streams["portal"] = _make(0.6, func(t: float, p: float): return sin(TAU * t * (200.0 + 900.0 * p * p)) * sin(p * PI) * 0.4)
	_streams["boom"] = _make(0.35, func(t: float, p: float): return _noise() * (1.0 - p) * (1.0 - p) * 0.7)
	_streams["chest"] = _make(0.4, func(t: float, p: float): return (sin(TAU * t * 660.0) + sin(TAU * t * 990.0)) * 0.3 * (1.0 - p))
	# sons Kenney (CC0) : remplacent les sons synthétisés quand ils existent ; plusieurs variantes par son
	var files := {
		"shoot": ["laserSmall_000", "laserSmall_001", "laserSmall_002", "laserSmall_003"],
		"eshoot": ["laserRetro_000", "laserRetro_001", "laserRetro_002"],
		"bigshoot": ["laserLarge_000", "laserLarge_001"],
		"hit": ["impactMetal_light_000", "impactMetal_light_001", "impactMetal_light_002", "impactMetal_light_003"],
		"kill": ["explosionCrunch_000", "explosionCrunch_001", "explosionCrunch_002", "explosionCrunch_003"],
		"boom": ["lowFrequency_explosion_000", "lowFrequency_explosion_001"],
		"hurt": ["impactPunch_heavy_000", "impactPunch_heavy_001"],
		"portal": ["forceField_000", "forceField_001"],
		"spawn": ["doorOpen_000"],
		"pick": ["select_002", "select_004"],
		"chest": ["confirmation_002", "confirmation_004"],
		"level": ["maximize_006", "maximize_008"],
		"click": ["click_002"],
		"drop": ["drop_002"],
	}
	for k in files.keys():
		var arr := []
		for f in files[k]:
			var path := "res://assets/sfx/%s.ogg" % f
			if ResourceLoader.exists(path):
				arr.append([load(path), float(TRIM.get(f, 0.0))])
		if not arr.is_empty():
			_variants[k] = arr
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	for i in range(VOICES):
		var pl := AudioStreamPlayer.new()
		pl.bus = bus
		add_child(pl)
		_players.append(pl)
		_owner.append("")
		_started.append(0)

func play(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if muted:
		return
	var stream: AudioStream = null
	var trim := 0.0
	if _variants.has(name):
		var arr: Array = _variants[name]
		# jamais deux fois de suite la même variante
		var vi := randi() % arr.size()
		if arr.size() > 1 and vi == int(_last_variant.get(name, -1)):
			vi = (vi + 1 + randi() % (arr.size() - 1)) % arr.size()
		_last_variant[name] = vi
		stream = arr[vi][0]
		trim = arr[vi][1]
	elif _streams.has(name):
		stream = _streams[name]
	if stream == null:
		return
	var mix: Array = MIX.get(name, DEFAULT_MIX)
	var now := Time.get_ticks_msec()
	if now - int(_last.get(name, -100000)) < int(mix[1]):
		return
	_last[name] = now
	# voix déjà prises par ce type ; au-delà du plafond, la plus ancienne est coupée et réutilisée
	var same := 0
	var oldest_same := -1
	var free := -1
	var oldest := 0
	for i in range(VOICES):
		var pl: AudioStreamPlayer = _players[i]
		if not pl.playing:
			_owner[i] = ""
			if free < 0:
				free = i
			continue
		if _owner[i] == name:
			same += 1
			if oldest_same < 0 or _started[i] < _started[oldest_same]:
				oldest_same = i
		if _started[i] < _started[oldest]:
			oldest = i
	var slot := free
	if same >= int(mix[0]):
		slot = oldest_same
		same -= 1
	elif slot < 0:
		slot = oldest
	var p: AudioStreamPlayer = _players[slot]
	p.stop()
	p.stream = stream
	var jitter: float = mix[2]
	p.pitch_scale = maxf(0.05, pitch * (1.0 + randf_range(-jitter, jitter)))
	p.volume_db = volume_db + float(mix[3]) + trim + STACK_DB * same
	p.play()
	_owner[slot] = name
	_started[slot] = now

func _sq(t: float, f: float) -> float:
	return 1.0 if fmod(t * f, 1.0) < 0.5 else -1.0

func _noise() -> float:
	return randf() * 2.0 - 1.0

func _make(dur: float, fn: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / RATE
		var p := float(i) / n
		var v: float = clampf(fn.call(t, p), -1.0, 1.0)
		var s := int(v * 32767.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
