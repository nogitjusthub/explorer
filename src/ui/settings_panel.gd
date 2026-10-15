class_name SettingsPanel
extends Control
## Меню настроек (GDD §8): открывается шестерёнкой в трюме и показано на паузе. Строки: громкость (регулятор
## VolumeSlider), режим управления («относительно мира» / «относительно машины»), «камера: вид сзади» (только
## в режиме «относительно машины»). Клавиши — через handle(action) у владельца экрана: W / S — строка, A / D —
## значение; мышь — клик по значению. Всё сразу сохраняется (Settings); changed — после смены управления.

signal changed

const W := 232.0
const ROW_H := 16.0
const VALUE_X := 92.0
const ROWS := 3
const MODE_TEXT := ["относительно мира", "относительно машины"]

var selected := 0

var _volume: VolumeSlider


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(W, 26.0 + ROWS * ROW_H + 14.0)
	custom_minimum_size = size
	_volume = VolumeSlider.new()
	add_child(_volume)
	_volume.position = Vector2(VALUE_X, _row_y(0) - 9.0)
	_volume.changed.connect(func(_v: float) -> void: queue_redraw())


## Клавиша владельца экрана: move_up / move_down — строка, move_left / move_right — значение. true — съедено.
func handle(action: StringName) -> bool:
	match action:
		&"move_up", &"ui_up":
			selected = (selected + ROWS - 1) % ROWS
		&"move_down", &"ui_down":
			selected = (selected + 1) % ROWS
		&"move_left", &"ui_left", &"move_right", &"ui_right":
			_change(selected, -1 if action == &"move_left" or action == &"ui_left" else 1)
		_:
			return false
	queue_redraw()
	return true


## Какую из handle-клавиш нажали в этом кадре (для экранов, что опрашивают Input), или &"".
static func pressed_action() -> StringName:
	for a: StringName in [&"move_up", &"move_down", &"move_left", &"move_right", &"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		if Input.is_action_just_pressed(a):
			return a
	return &""


func _change(row: int, d: int) -> void:
	match row:
		0:
			_volume.nudge(d)
		1:
			Settings.control_mode = Settings.ControlMode.VEHICLE if Settings.control_mode == Settings.ControlMode.WORLD \
					else Settings.ControlMode.WORLD
			Settings.save_settings()
			changed.emit()
		2:
			if Settings.control_mode == Settings.ControlMode.VEHICLE:
				Settings.chase_camera = not Settings.chase_camera
				Settings.save_settings()
				changed.emit()


func _gui_input(event: InputEvent) -> void:
	if not UiKit.is_click(event):
		return
	var p := (event as InputEventMouseButton).position
	for row in ROWS:
		if absf(p.y - (_row_y(row) - 4.0)) <= ROW_H * 0.5:
			selected = row
			if row > 0:
				_change(row, 1)
			queue_redraw()
			accept_event()
			return


func _row_y(row: int) -> float:
	return 30.0 + row * ROW_H


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, UiKit.COLOR_PANEL)
	draw_rect(r, UiKit.COLOR_EDGE, false, 1.0)
	UiKit.text(self, Vector2(8, 14), "НАСТРОЙКИ", UiKit.TEXT, UiKit.COLOR_MARK)
	var captions := ["ГРОМКОСТЬ", "УПРАВЛЕНИЕ", "КАМЕРА"]
	var vehicle_mode := Settings.control_mode == Settings.ControlMode.VEHICLE
	for row in ROWS:
		var y := _row_y(row)
		var on := row == selected
		if on:
			UiKit.text(self, Vector2(4, y), ">", UiKit.TEXT, UiKit.COLOR_MARK)
		UiKit.text(self, Vector2(12, y), captions[row], UiKit.TEXT, UiKit.COLOR_MARK if on else UiKit.COLOR_DIM)
	UiKit.text(self, Vector2(VALUE_X, _row_y(1)), "< %s >" % MODE_TEXT[Settings.control_mode], UiKit.TEXT, UiKit.COLOR_TEXT)
	# Рамка 7×7 — четырьмя полосками: контурный draw_rect кладёт линию по центру края, на полпикселя мимо
	# сетки, и отметка 3×3 внутри выходила не по центру.
	var box := Rect2(VALUE_X, _row_y(2) - 7.0, 7.0, 7.0)
	var c := UiKit.COLOR_TEXT if vehicle_mode else UiKit.COLOR_PIP_EMPTY
	for side in [Rect2(0, 0, 7, 1), Rect2(0, 6, 7, 1), Rect2(0, 1, 1, 5), Rect2(6, 1, 1, 5)]:
		draw_rect(Rect2(box.position + side.position, side.size), c)
	if vehicle_mode and Settings.chase_camera:
		draw_rect(box.grow(-2.0), UiKit.COLOR_MARK)
	UiKit.text(self, Vector2(VALUE_X + 12.0, _row_y(2)), "вид сзади", UiKit.TEXT, c)
	UiKit.text(self, Vector2(8, size.y - 5.0), "W / S, A / D, Esc", UiKit.TEXT, UiKit.COLOR_DIM)
