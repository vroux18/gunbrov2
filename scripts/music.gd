extends Node
## Musique et ambiance (autoload « Music »). Trois pistes en boucle, Relais, combat et boss, en fondu enchaîné.
## La musique baisse tant que le jeu est en pause : choix de pouvoir, objet trouvé, portails, pause, écran de fin.
## Jingle de fin de salle, fond sonore de hangar. « Musique coupée » est gardé sur l'appareil (user://audio.cfg).
## Les boucles sont activées ici : les fichiers .import ne sont pas versionnés.

## piste : [fichier, gain (dB)] ; fichiers normalisés (Relais -17 LUFS, combat et boss -14 LUFS)
const TRACKS := {
	"relais": ["res://assets/music/relais.ogg", -2.0],
	"combat": ["res://assets/music/combat.ogg", -5.0],
	"boss": ["res://assets/music/boss.ogg", -4.0],
}
const STINGER := "res://assets/music/stinger_clear.ogg"
const STINGER_DB := -4.0
const AMBIENCE := "res://assets/sfx/hangar_ambience.ogg"
const AMBIENCE_DB := -8.0
const FADE := 1.8          # fondu enchaîné entre deux pistes (s)
const DUCK_DB := -9.0      # jeu en pause
const STINGER_DUCK_DB := -10.0  # sous le jingle
const CFG := "user://audio.cfg"

var enabled := true
var current := ""
var _streams := {}
var _pl: Array = []          # deux lecteurs : l'un monte pendant que l'autre descend
var _track := ["", ""]
var _level := [0.0, 0.0]     # niveau de fondu (0..1) de chaque lecteur
var _active := 0
var _duck := 0.0             # 0..1, suit la pause
var _sting_t := 0.0          # temps restant du jingle
var _sduck := 0.0            # 0..1, effacement sous le jingle
var _stinger: AudioStreamPlayer
var _amb: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_load_cfg()
	for k in TRACKS.keys():
		_streams[k] = _load_loop(String(TRACKS[k][0]))
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_pl.append(p)
	_stinger = AudioStreamPlayer.new()
	_stinger.bus = "Music"
	_stinger.volume_db = STINGER_DB
	if ResourceLoader.exists(STINGER):
		_stinger.stream = load(STINGER)
	add_child(_stinger)
	_amb = AudioStreamPlayer.new()
	_amb.bus = "SFX"
	_amb.volume_db = AMBIENCE_DB
	_amb.stream = _load_loop(AMBIENCE)
	add_child(_amb)
	if _amb.stream != null:
		_amb.play()

## Bus « Music » et « SFX » sous le Master, limiteur sur le Master (aucune saturation à 25 ennemis).
func _setup_buses() -> void:
	for b in ["Music", "SFX"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	if AudioServer.get_bus_effect_count(0) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(0, lim)

## À la fermeture : tous les sons du jeu s'arrêtent, puis le moteur audio a le temps d'un cycle de mixage
## pour libérer les lectures en cours (sinon : « resources still in use at exit »).
func _exit_tree() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	for n in tree.root.find_children("*", "AudioStreamPlayer", true, false):
		n.stop()
	OS.delay_msec(60)

func _load_loop(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s

## Passe à la piste `name` (« relais », « combat », « boss ») en fondu enchaîné ; "" fait taire la musique.
func play(name: String) -> void:
	if name == current:
		return
	current = name
	if enabled:
		_switch(name)

func _switch(name: String) -> void:
	var old := _active
	_active = 1 - _active
	_level[old] = minf(_level[old], 1.0)
	var p: AudioStreamPlayer = _pl[_active]
	p.stop()
	_track[_active] = name
	_level[_active] = 0.0
	if _streams.get(name) != null:
		p.stream = _streams[name]
		p.volume_db = -80.0
		p.play()

## Jingle de victoire de fin de salle : la musique s'efface dessous, puis revient.
func stinger() -> void:
	if not enabled or _stinger.stream == null:
		return
	_stinger.play()
	_sting_t = _stinger.stream.get_length()

func set_enabled(on: bool) -> void:
	enabled = on
	_save_cfg()
	if on:
		var want := current
		current = ""
		_track = ["", ""]
		play(want)
	else:
		_stinger.stop()
		_sting_t = 0.0

func _process(dt: float) -> void:
	# fondus : la piste active monte, l'autre descend ; tout descend si la musique est coupée
	for i in range(2):
		var target := 1.0 if (enabled and i == _active and _track[i] != "") else 0.0
		_level[i] = move_toward(_level[i], target, dt / FADE)
		var p: AudioStreamPlayer = _pl[i]
		if _level[i] <= 0.0:
			if p.playing:
				p.stop()
			continue
		var base: float = TRACKS[_track[i]][1] if TRACKS.has(_track[i]) else 0.0
		p.volume_db = base + linear_to_db(_level[i] * _level[i] * (3.0 - 2.0 * _level[i])) + _duck_db()
	_duck = move_toward(_duck, 1.0 if get_tree().paused else 0.0, dt / 0.4)
	# sous le jingle : la musique s'efface en 0,15 s, remonte pendant sa dernière seconde
	_sting_t = maxf(0.0, _sting_t - dt)
	if _sting_t > 1.0:
		_sduck = move_toward(_sduck, 1.0, dt / 0.15)
	else:
		_sduck = move_toward(_sduck, 0.0, dt / 1.0)

func _duck_db() -> float:
	return DUCK_DB * _duck + STINGER_DUCK_DB * _sduck

func _load_cfg() -> void:
	var c := ConfigFile.new()
	if c.load(CFG) == OK:
		enabled = bool(c.get_value("audio", "music", true))

func _save_cfg() -> void:
	var c := ConfigFile.new()
	c.set_value("audio", "music", enabled)
	c.save(CFG)
