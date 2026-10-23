extends Node
## Sons synthétisés au lancement (aucun fichier audio) : tir, impact, mort, ramassage, niveau, portail.

const RATE := 22050
var _streams := {}
var _players: Array = []
var _next := 0
var muted := false

func _ready() -> void:
	_streams["shoot"] = _make(0.07, func(t: float, p: float): return _sq(t, 520.0 - 300.0 * p) * (1.0 - p) * 0.25)
	_streams["hit"] = _make(0.06, func(t: float, p: float): return _noise() * (1.0 - p) * 0.35)
	_streams["kill"] = _make(0.22, func(t: float, p: float): return (_sq(t, 220.0 - 150.0 * p) * 0.5 + _noise() * 0.5) * (1.0 - p) * 0.5)
	_streams["hurt"] = _make(0.18, func(t: float, p: float): return _sq(t, 110.0) * (1.0 - p) * 0.6)
	_streams["pick"] = _make(0.09, func(t: float, p: float): return sin(TAU * t * (880.0 + 660.0 * p)) * (1.0 - p) * 0.35)
	_streams["level"] = _make(0.5, func(t: float, p: float): return sin(TAU * t * (440.0 * pow(2.0, floor(p * 4.0) / 4.0 * 1.0))) * (1.0 - p) * 0.4)
	_streams["portal"] = _make(0.6, func(t: float, p: float): return sin(TAU * t * (200.0 + 900.0 * p * p)) * sin(p * PI) * 0.4)
	_streams["boom"] = _make(0.35, func(t: float, p: float): return _noise() * (1.0 - p) * (1.0 - p) * 0.7)
	_streams["chest"] = _make(0.4, func(t: float, p: float): return (sin(TAU * t * 660.0) + sin(TAU * t * 990.0)) * 0.3 * (1.0 - p))
	for i in range(10):
		var pl := AudioStreamPlayer.new()
		pl.bus = "Master"
		add_child(pl)
		_players.append(pl)

func play(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if muted or not _streams.has(name):
		return
	var pl: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	pl.stream = _streams[name]
	pl.pitch_scale = pitch
	pl.volume_db = volume_db
	pl.play()

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
