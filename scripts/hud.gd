extends CanvasLayer
## HUD de combat : vie en haut à gauche, énergie et salle au centre, tickets et pause à droite,
## barre de boss en bas, message au milieu. Tout est dessiné dans un seul Control.

const UI = preload("res://scripts/ui.gd")

signal pause_pressed

var hp := 1.0
var hp_text := "100"
var shield := false
var energy := 0.0
var room := 1
var wave := 1
var waves := 3
var world := ""
var tickets := 0
var enemies_left := 0
var boss_hp := -1.0
var boss_name := ""
var message := ""
var _message_t := 0.0
var _c: Control
var _pause: Button
var _font: Font

func _ready() -> void:
	layer = 5
	_c = Control.new()
	_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.draw.connect(_draw_hud)
	add_child(_c)
	_font = ThemeDB.fallback_font
	_pause = UI.button("❚❚", 22, UI.MUTED)
	_pause.anchor_left = 1.0
	_pause.anchor_right = 1.0
	_pause.offset_left = -78
	_pause.offset_right = -16
	_pause.offset_top = 14
	_pause.offset_bottom = 64
	_pause.pressed.connect(func(): pause_pressed.emit())
	add_child(_pause)

func flash(text: String, t: float = 2.2) -> void:
	message = text
	_message_t = t

func _process(dt: float) -> void:
	if _message_t > 0.0:
		_message_t -= dt
	_c.queue_redraw()

func _bar(pos: Vector2, size: Vector2, ratio: float, col: Color, back: Color = Color(0, 0, 0, 0.45)) -> void:
	_c.draw_rect(Rect2(pos, size), back)
	_c.draw_rect(Rect2(pos, Vector2(size.x * clampf(ratio, 0.0, 1.0), size.y)), col)
	_c.draw_rect(Rect2(pos, size), Color(1, 1, 1, 0.25), false, 2.0)

func _text(pos: Vector2, s: String, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void:
	_c.draw_string(_font, pos + Vector2(1, 2), s, align, w, size, Color(0, 0, 0, 0.6))
	_c.draw_string(_font, pos, s, align, w, size, col)

func _draw_hud() -> void:
	var W := _c.size.x
	# vie
	_bar(Vector2(24, 22), Vector2(300, 24), hp, UI.ORANGE if hp > 0.3 else UI.DANGER)
	_text(Vector2(34, 41), "PV " + hp_text, 18, UI.TEXT)
	if shield:
		_c.draw_circle(Vector2(344, 34), 10, UI.ACCENT)
	# énergie et salle
	var ex := W * 0.5 - 220.0
	_bar(Vector2(ex, 22), Vector2(440, 16), energy, UI.ACCENT)
	var wave_txt := "SALLE %d · VAGUE %d/%d" % [room, wave, waves]
	if boss_hp >= 0.0:
		wave_txt = "SALLE %d · BOSS" % room
	_text(Vector2(ex, 62), world.to_upper() + "   " + wave_txt, 17, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 440)
	if energy >= 1.0:
		_text(Vector2(ex, 90), "ÉNERGIE PLEINE", 18, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 440)
	# tickets
	_c.draw_circle(Vector2(W - 150, 36), 9, UI.GOLD)
	_text(Vector2(W - 134, 43), str(tickets), 20, UI.TEXT)
	# ennemis restants
	if enemies_left > 0 and boss_hp < 0.0:
		_text(Vector2(W - 160, 72), "%d restants" % enemies_left, 15, UI.MUTED)
	# boss
	if boss_hp >= 0.0:
		var bw := minf(680.0, W - 80.0)
		_bar(Vector2((W - bw) * 0.5, _c.size.y - 44), Vector2(bw, 18), boss_hp, UI.DANGER)
		_text(Vector2((W - bw) * 0.5, _c.size.y - 52), boss_name.to_upper(), 16, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, bw)
	# message
	if _message_t > 0.0 and message != "":
		var a := clampf(_message_t * 2.0, 0.0, 1.0)
		_text(Vector2(0, _c.size.y * 0.32), message, 40, Color(UI.TEXT, a), HORIZONTAL_ALIGNMENT_CENTER, W)
