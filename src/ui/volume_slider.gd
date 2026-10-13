class_name VolumeSlider
extends Control
## Регулятор общей громкости (Settings.master_volume): значок динамика, шкала из STEPS делений и проценты.
## Мышь (и тап): клик или протяжка по шкале — уровень, колесо — на деление, клик по значку — выключить
## звук и вернуть прежний уровень. Клавиши — через nudge (A / D у владельца экрана). Каждое изменение
## отзывается коротким щелчком — слышно, какой уровень — и сразу сохраняется; при протяжке громкость
## меняется на ходу, а в файл (в браузере — IndexedDB) пишется один раз, по отпусканию.

signal changed(volume: float)

const STEPS := 10
const SEG_W := 5                         ## деление шкалы и зазор между делениями — в пикселях
const SEG_H := 7
const ICON_W := 11
const BAR_X := ICON_W + 4.0
const BAR_W := STEPS * (SEG_W + 1) - 1

var _restore := 1.0                      ## уровень, к которому вернёт клик по значку
var _dragging := false
var _unsaved := false                    ## протяжка поменяла уровень — сохранить по отпусканию
var _tick: AudioStreamPlayer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(BAR_X + BAR_W + 6.0 + _percent_w(), 11.0)
	size = custom_minimum_size
	_tick = AudioStreamPlayer.new()                  # щелчок тумблера — звук берётся при первом щелчке
	_tick.volume_db = -12.0
	_tick.process_mode = Node.PROCESS_MODE_ALWAYS   # слышно и на паузе
	add_child(_tick)


## Сдвинуть на d делений (клавиши).
func nudge(d: int) -> void:
	_set_level(Settings.master_volume + d / float(STEPS))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			nudge(1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			nudge(-1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed and mb.position.x >= BAR_X - 2.0
			if mb.pressed and mb.position.x < BAR_X - 2.0:
				_toggle_mute()
			elif _dragging:
				_set_from_x(mb.position.x)
			elif not mb.pressed:
				_end_drag()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x((event as InputEventMouseMotion).position.x)
		accept_event()


## Отпустили кнопку (или регулятор пропал из дерева посреди протяжки): сохранить, если уровень менялся.
func _end_drag() -> void:
	_dragging = false
	if _unsaved:
		_unsaved = false
		Settings.save_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		_end_drag()


## Уровень по точке шкалы; при протяжке — на ходу, без записи в файл.
func _set_from_x(x: float) -> void:
	_set_level(ceilf(clampf((x - BAR_X) / (BAR_W + 1.0), 0.0, 1.0) * STEPS) / STEPS, not _dragging)


func _toggle_mute() -> void:
	if Settings.master_volume > 0.0:
		_restore = Settings.master_volume
		_set_level(0.0)
	else:
		_set_level(maxf(_restore, 1.0 / STEPS))


## Новый уровень. Тот же, что был, — ничего не делаем (протяжка шлёт движение мыши на каждый пиксель).
func _set_level(v: float, persist: bool = true) -> void:
	if not Settings.set_master_volume(v, persist):
		return
	_unsaved = _unsaved or not persist
	queue_redraw()
	changed.emit(Settings.master_volume)
	_tick.stream = Sfx.toggle()
	_tick.play()


func _percent_w() -> float:
	return ceilf(UiKit.FONT.get_string_size("100%", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT).x)


func _draw() -> void:
	var v := Settings.master_volume
	var level := roundi(v * STEPS)
	_draw_speaker(Vector2(0, 1), level)
	for i in STEPS:
		var r := Rect2(BAR_X + i * (SEG_W + 1), 2, SEG_W, SEG_H)
		if i < level:
			draw_rect(r, UiKit.COLOR_MARK)
		else:
			draw_rect(r, UiKit.COLOR_PIP_EMPTY, false, 1.0)
	UiKit.text(self, Vector2(BAR_X + BAR_W + 6.0, 9), "%d%%" % roundi(v * 100.0), UiKit.TEXT,
			UiKit.COLOR_TEXT if level > 0 else UiKit.COLOR_DIM)


## Динамик 11×9: корпус и раструб; волны по уровню, без звука — крестик.
func _draw_speaker(o: Vector2, level: int) -> void:
	var c := UiKit.COLOR_TEXT if level > 0 else UiKit.COLOR_DIM
	draw_rect(Rect2(o + Vector2(0, 3), Vector2(2, 3)), c)
	draw_colored_polygon(PackedVector2Array([o + Vector2(2, 3), o + Vector2(5, 0), o + Vector2(5, 9),
			o + Vector2(2, 6)]), c)
	if level == 0:
		for i in 4:
			draw_rect(Rect2(o + Vector2(7 + i, 2 + i), Vector2.ONE), UiKit.COLOR_DIM)
			draw_rect(Rect2(o + Vector2(10 - i, 2 + i), Vector2.ONE), UiKit.COLOR_DIM)
		return
	draw_rect(Rect2(o + Vector2(7, 3), Vector2(1, 3)), c)
	if level > STEPS / 2:
		draw_rect(Rect2(o + Vector2(9, 1), Vector2(1, 7)), c)
