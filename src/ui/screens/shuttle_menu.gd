class_name ShuttleMenu
extends CanvasLayer
## Меню основного челнока (GDD §2.3): открывается, когда машина остановилась в зоне. Поверх игры,
## без паузы. Два пункта столбиком: «Сдать груз» (челнок сразу улетает, забег продолжается) и
## «Вернуться на орбиту» (конец забега).
## W / S — выбор, F / Enter — подтвердить, тап по пункту — выбрать и подтвердить. Закрывается по Esc,
## при выезде из зоны (ShuttleController) или по A / D — тогда машина сразу трогается.

signal ship_requested
signal evacuate_requested
signal closed

enum Item { SHIP, EVACUATE }

const ITEMS := ["Сдать груз", "Вернуться на орбиту"]
const COLOR_PANEL := Color(0.06, 0.04, 0.1, 0.82)
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.5, 0.47, 0.55)
const COLOR_MARK := Color(1.0, 0.8, 0.3)
const COLOR_ROW := Color(1.0, 0.8, 0.3, 0.14)
const INPUT_DELAY_S := 0.25
const PANEL := Rect2(150, 186, 180, 76)
const ROW_H := 16.0

var cargo_value := 0               ## стоимость груза в трюме (обновляет GameFlow)
var bonus := 0                     ## бонус за возвращение на орбиту прямо сейчас
var window_left := 0.0

var _selected := Item.SHIP
var _age := 0.0
var _canvas: Control


func _ready() -> void:
	layer = 12
	name = "ShuttleMenu"
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_menu)
	add_child(_canvas)
	if cargo_value == 0:
		_selected = Item.EVACUATE


func _process(dt: float) -> void:
	_age += dt
	# Выбор — опросом: стик шлёт поток событий, а нужен один шаг на нажатие. Пунктов два — любое направление.
	if _age >= INPUT_DELAY_S and not HelpScreen.shown(get_tree()):
		for action: StringName in [&"move_up", &"move_down", &"ui_up", &"ui_down"]:
			if Input.is_action_just_pressed(action):
				_selected = wrapi(_selected + 1, 0, ITEMS.size()) as Item
				break
	_canvas.queue_redraw()


func _row(i: int) -> Rect2:
	return Rect2(PANEL.position.x + 6, PANEL.position.y + 20 + i * ROW_H, PANEL.size.x - 12, ROW_H - 2)


func _input(event: InputEvent) -> void:
	if _age < INPUT_DELAY_S or HelpScreen.shown(get_tree()):
		return
	if UiKit.is_click(event):
		for i in ITEMS.size():
			if _row(i).has_point((event as InputEventMouseButton).position):
				_selected = i as Item
				_confirm()
				get_viewport().set_input_as_handled()
				return
		return
	if event.is_action_pressed(&"radio") or event.is_action_pressed(&"ui_accept"):
		_confirm()
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		closed.emit()
	elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"move_right"):
		closed.emit()     # клавишу не съедаем: машина сразу трогается
		return
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


func _draw_menu() -> void:
	_canvas.draw_rect(PANEL, COLOR_PANEL)
	UiKit.text(_canvas, Vector2(PANEL.position.x, PANEL.position.y + 12), "ЧЕЛНОК — окно %d с" % ceili(window_left),
			UiKit.TEXT, COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER, PANEL.size.x)
	for i in ITEMS.size():
		var r := _row(i)
		var enabled := i != Item.SHIP or cargo_value > 0
		if i == _selected:
			_canvas.draw_rect(r, COLOR_ROW)
			_canvas.draw_rect(r, COLOR_MARK, false, 1.0)
		var col := COLOR_MARK if i == _selected else (COLOR_TEXT if enabled else COLOR_DIM)
		UiKit.text(_canvas, Vector2(r.position.x, r.position.y + 11), ITEMS[i], UiKit.TEXT, col,
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var hint := ""
	match _selected:
		Item.SHIP:
			hint = "+%d очков, челнок улетит" % cargo_value if cargo_value > 0 else "трюм пуст"
		Item.EVACUATE:
			hint = "груз %d + бонус %d, конец забега" % [cargo_value, bonus]
	UiKit.text(_canvas, Vector2(PANEL.position.x, PANEL.end.y - 6), hint, UiKit.TEXT, COLOR_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, PANEL.size.x)
