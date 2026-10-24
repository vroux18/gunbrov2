extends Control
## Essai du défilement au doigt (scripts/ui/touch_scroll.gd) : un toucher clique, un glissé défile sans cliquer.
## godot --headless --path . res://tools/touch_scroll_test.tscn
const TouchScroll = preload("res://scripts/ui/touch_scroll.gd")
var sc: ScrollContainer
var clicks := []
var f := 0

func _ready() -> void:
	size = Vector2(1280, 720)
	sc = ScrollContainer.new()
	sc.position = Vector2(100, 100)
	sc.size = Vector2(400, 400)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var v := VBoxContainer.new()
	sc.add_child(v)
	for i in range(20):
		var b := Button.new()
		b.text = "b%d" % i
		b.custom_minimum_size = Vector2(380, 80)
		b.pressed.connect(func(): clicks.append(i))
		v.add_child(b)
	TouchScroll.attach(sc)

func _touch(p: Vector2, on: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = get_viewport().get_final_transform() * p  # coordonnées de la fenêtre
	e.pressed = on
	Input.parse_input_event(e)

func _dragto(p: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = get_viewport().get_final_transform() * p
	Input.parse_input_event(e)

func _process(_dt: float) -> void:
	f += 1
	match f:
		5: _touch(Vector2(200, 140), true)
		7: _touch(Vector2(200, 140), false)
		10: print("TAP clics=", clicks, " scroll=", sc.scroll_vertical)
		12: _touch(Vector2(200, 450), true)
		13: _dragto(Vector2(200, 440))
		14: _dragto(Vector2(200, 400))
		15: _dragto(Vector2(200, 300))
		16: _dragto(Vector2(200, 250))
		17: _touch(Vector2(200, 250), false)
		20: print("DRAG clics=", clicks, " scroll=", sc.scroll_vertical)
		40: print("ELAN scroll=", sc.scroll_vertical)
		42: _touch(Vector2(200, 300), true)
		44: _touch(Vector2(200, 300), false)
		46: print("TAP2 clics=", clicks); get_tree().quit()
