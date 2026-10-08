class_name ShuttleMenu
extends CanvasLayer
## Меню основного челнока (GDD §2.3): открывается, когда машина остановилась в зоне. Поверх игры,
## без паузы. A/D — выбор, F/Enter — подтвердить, W/S — уехать (меню закрывается, машина трогается).

signal ship_requested
signal evacuate_requested
signal closed

enum Item { SHIP, EVACUATE, LEAVE }

const ITEMS := ["Сдать груз", "Завершить забег", "Уехать"]
const COLOR_PANEL := Color(0.06, 0.04, 0.1, 0.82)
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.5, 0.47, 0.55)
const COLOR_MARK := Color(1.0, 0.8, 0.3)
const INPUT_DELAY_S := 0.25

var cargo_value := 0               ## стоимость груза в трюме (обновляет GameFlow)
var bonus := 0                     ## бонус за эвакуацию прямо сейчас
var window_left := 0.0

var _selected := Item.SHIP
var _age := 0.0
var _canvas: Control
var _font: Font


func _ready() -> void:
	layer = 12
	name = "ShuttleMenu"
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_menu)
	add_child(_canvas)
	if cargo_value == 0:
		_selected = Item.EVACUATE


func _process(dt: float) -> void:
	_age += dt
	_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if _age < INPUT_DELAY_S:
		return
	if event.is_action_pressed(&"move_left", true):
		_selected = wrapi(_selected - 1, 0, ITEMS.size()) as Item
	elif event.is_action_pressed(&"move_right", true):
		_selected = wrapi(_selected + 1, 0, ITEMS.size()) as Item
	elif event.is_action_pressed(&"move_up") or event.is_action_pressed(&"move_down"):
		closed.emit()     # клавишу не съедаем: машина сразу трогается
		return
	elif event.is_action_pressed(&"radio") or event.is_action_pressed(&"ui_accept"):
		_confirm()
	else:
		return
	get_viewport().set_input_as_handled()


func _confirm() -> void:
	match _selected:
		Item.SHIP:
			if cargo_value > 0:
				ship_requested.emit()
				_selected = Item.EVACUATE
		Item.EVACUATE:
			evacuate_requested.emit()
		Item.LEAVE:
			closed.emit()


func _draw_menu() -> void:
	var w := _canvas.size.x
	var panel := Rect2(w * 0.5 - 150, 196, 300, 58)
	_canvas.draw_rect(panel, COLOR_PANEL)
	_text(Vector2(panel.position.x, 208), "ЧЕЛНОК — окно %d с" % ceili(window_left), 8, COLOR_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, panel.size.x)
	var x := panel.position.x + 10.0
	var slot := (panel.size.x - 20.0) / ITEMS.size()
	for i in ITEMS.size():
		var enabled := i != Item.SHIP or cargo_value > 0
		var col := COLOR_MARK if i == _selected else (COLOR_TEXT if enabled else COLOR_DIM)
		var label: String = ITEMS[i]
		if i == _selected:
			label = "> " + label + " <"
		_text(Vector2(x + slot * i, 226), label, 8, col, HORIZONTAL_ALIGNMENT_CENTER, slot)
	var hint := ""
	match _selected:
		Item.SHIP:
			hint = "груз %d очков в счёт, забег продолжается" % cargo_value if cargo_value > 0 else "трюм пуст"
		Item.EVACUATE:
			hint = "груз %d + бонус %d, конец забега" % [cargo_value, bonus]
		Item.LEAVE:
			hint = "челнок ждёт, пока не кончится окно"
	_text(Vector2(panel.position.x, 244), hint, 8, COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x)
	_text(Vector2(0, 268), "A / D — выбор,  F / Enter — подтвердить,  W / S — уехать", 8, COLOR_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, w)


func _text(pos: Vector2, s: String, font_size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	_canvas.draw_string(_font, pos + Vector2.ONE, s, align, width, font_size, Color(0, 0, 0, 0.85))
	_canvas.draw_string(_font, pos, s, align, width, font_size, color)
