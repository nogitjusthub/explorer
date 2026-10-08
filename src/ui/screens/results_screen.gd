class_name ResultsScreen
extends CanvasLayer
## Экран итога (GDD §6): причина конца, разбор счёта, ввод имени при попадании в топ-10 класса
## (3 знака, аркадный выбор: W/S — знак, A/D — позиция, F/Enter — готово; на телефоне — тап по
## стрелкам над и под буквой и кнопка «Готово»), затем таблица рекордов и две кнопки с хоткеями:
## «Заново» (R) — сразу новый забег на той же машине, «Выход» (Esc) — в трюм челнока к выбору машины.
## Класс машины показан портретом — названий классов игроку не показываем.

signal restart_requested
signal exit_requested

const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
const LETTERS_Y := 166.0
const INPUT_DELAY_S := 0.8             ## нажатия в первые доли секунды игнорируются (палец ещё на газе)
const CAUSE_TEXT := {
	"evacuated": "ВОЗВРАЩЕНИЕ НА ОРБИТУ",
	"drowned": "МАШИНА УТОНУЛА",
	"fall": "РАЗБИТА ПРИ ПАДЕНИИ",
	"tree": "РАЗБИТА О ДЕРЕВЬЯ",
	"wall": "РАЗБИТА О СКАЛЫ",
	"lightning": "СГОРЕЛА ОТ МОЛНИИ",
	"quake": "РАЗБИТА ЗЕМЛЕТРЯСЕНИЕМ",
	"acid": "РАЗЪЕДЕНА КИСЛОТНЫМ ГАЗОМ",
	"tornado": "РАЗБИТА СМЕРЧЕМ",
	"hopper": "ЗАГРЫЗЛИ СКАКУНЫ",
	"worm": "ПРОГЛОЧЕНА ЧЕРВЁМ",
	"shellback": "РАЗБИТА ПАНЦИРНИКОМ",
	"empty_tank": "КОНЧИЛОСЬ ТОПЛИВО",
}
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.62, 0.58, 0.66)
const COLOR_GOOD := Color(0.46, 0.9, 0.4)
const COLOR_BAD := Color(0.95, 0.4, 0.3)
const COLOR_MARK := Color(1.0, 0.8, 0.3)

var result: Dictionary
var board: Leaderboard

var _rank := -1
var _entering := false
var _highlight := -1
var _letters := PackedInt32Array([0, 0, 0])
var _cursor := 0
var _age := 0.0
var _canvas: Control
var _font: Font
var _done: Button
var _restart: Button
var _exit: Button


func _init(run_result: Dictionary, leaderboard: Leaderboard) -> void:
	result = run_result
	board = leaderboard
	name = "ResultsScreen"


func _ready() -> void:
	layer = 20
	_font = ThemeDB.fallback_font
	var shade := ColorRect.new()
	shade.color = Color(0.06, 0.04, 0.1, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_screen)
	add_child(_canvas)
	var portrait := VehiclePortrait.new(StringName(result["class"]))
	portrait.position = Vector2(34, 46)
	add_child(portrait)
	_done = _button("ГОТОВО", "Enter", _save_entry, Vector2(240, 214), true)
	_restart = _button("ЗАНОВО", "R", restart_requested.emit, Vector2(232, 296), false, true)
	_exit = _button("ВЫХОД", "Esc", exit_requested.emit, Vector2(248, 296), false)
	var score := int(result["score"])
	_rank = board.rank_for(StringName(result["class"]), score) if score > 0 else -1
	_entering = _rank >= 0
	_update_buttons()
	var last := Settings.player_name.to_upper()
	for i in 3:
		var idx := LETTERS.find(last[i]) if i < last.length() else 0
		_letters[i] = maxi(idx, 0)


func _process(dt: float) -> void:
	_age += dt
	_canvas.queue_redraw()


## Кнопка с хоткеем: центр по x (center) или край — правый (from_right) или левый — в точке at.
func _button(text: String, hotkey: String, action: Callable, at: Vector2, center: bool,
		from_right: bool = false) -> Button:
	var b := UiKit.button(text, hotkey)
	b.pressed.connect(_on_button.bind(action))
	add_child(b)
	b.reset_size()
	var x := at.x - b.size.x * 0.5 if center else (at.x - b.size.x if from_right else at.x)
	b.position = Vector2(x, at.y - b.size.y * 0.5)
	return b


func _on_button(action: Callable) -> void:
	if _age >= INPUT_DELAY_S and not HelpScreen.is_open:
		action.call()


func _update_buttons() -> void:
	_done.visible = _entering
	_restart.visible = not _entering
	_exit.visible = not _entering


## Стрелки над и под буквой (тап меняет знак): прямоугольники для попадания.
func _letter_arrow(i: int, up: bool) -> Rect2:
	var x := _canvas.size.x * 0.5 - 27.0 + i * 20.0
	return Rect2(x, LETTERS_Y - (25.0 if up else -3.0), 14, 10)


func _input(event: InputEvent) -> void:
	if _age < INPUT_DELAY_S or HelpScreen.is_open:
		return
	if _entering and UiKit.is_click(event):
		var p: Vector2 = (event as InputEventMouseButton).position
		for i in 3:
			for up: bool in [true, false]:
				if _letter_arrow(i, up).grow(3.0).has_point(p):
					_cursor = i
					_letters[i] = (_letters[i] + (1 if up else LETTERS.length() - 1)) % LETTERS.length()
					get_viewport().set_input_as_handled()
					return
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion \
			or event is InputEventAction):
		return
	var confirm := event.is_action_pressed(&"radio") or event.is_action_pressed(&"ui_accept")
	if _entering:
		if event.is_action_pressed(&"move_up", true):
			_letters[_cursor] = (_letters[_cursor] + 1) % LETTERS.length()
		elif event.is_action_pressed(&"move_down", true):
			_letters[_cursor] = (_letters[_cursor] + LETTERS.length() - 1) % LETTERS.length()
		elif event.is_action_pressed(&"move_left", true):
			_cursor = maxi(_cursor - 1, 0)
		elif event.is_action_pressed(&"move_right", true):
			_cursor = mini(_cursor + 1, 2)
		elif confirm:
			_save_entry()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"restart"):
		get_viewport().set_input_as_handled()
		restart_requested.emit()
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		exit_requested.emit()


func _player_name() -> String:
	var s := ""
	for i in 3:
		s += LETTERS[_letters[i]]
	return s


func _save_entry() -> void:
	var entry_name := _player_name()
	_highlight = board.add(StringName(result["class"]), {
		"name": entry_name, "score": int(result["score"]), "time": snappedf(float(result["time"]), 0.1),
		"shipments": int(result["shipments"]), "cause": String(result["cause"]),
		"date": Time.get_date_string_from_system(),
	})
	_entering = false
	_update_buttons()
	Settings.player_name = entry_name
	Settings.save_settings()


func _draw_screen() -> void:
	var w := _canvas.size.x
	var cause := String(result["cause"])
	var evacuated := cause == String(RunState.CAUSE_EVACUATED)
	_text(Vector2(0, 30), CAUSE_TEXT.get(cause, "МАШИНА УНИЧТОЖЕНА"), 16,
			COLOR_GOOD if evacuated else COLOR_BAD, HORIZONTAL_ALIGNMENT_CENTER, w)

	var lines: Array[Array] = []
	lines.append(["Сдано челнокам", str(int(result["banked"]))])
	if int(result["emergency_calls"]) > 0:
		lines.append(["  в т. ч. аварийных вызовов", str(int(result["emergency_calls"]))])
	if evacuated:
		lines.append(["Бонус (броня × 3 + топливо × 2)", "+%d" % int(result["bonus"])])
	else:
		lines.append(["Груз в трюме", "потерян"])
	lines.append(["Время забега", _format_time(float(result["time"]))])
	lines.append(["Рейсов челнока", str(int(result["shipments"]))])
	var y := 52.0
	for line in lines:
		_text(Vector2(w * 0.5 - 130, y), line[0], 8, COLOR_DIM)
		_text(Vector2(w * 0.5 - 130, y), line[1], 8, COLOR_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 260)
		y += 10.0
	y += 6.0
	_text(Vector2(0, y + 6), "ИТОГ  %d" % int(result["score"]), 16, COLOR_MARK, HORIZONTAL_ALIGNMENT_CENTER, w)
	y += 26.0

	if _entering:
		_text(Vector2(0, y), "НОВЫЙ РЕКОРД — %d-е место" % (_rank + 1), 8, COLOR_GOOD, HORIZONTAL_ALIGNMENT_CENTER, w)
		y = LETTERS_Y
		var x0 := w * 0.5 - 27.0
		for i in 3:
			var x := x0 + i * 20.0
			var col := COLOR_MARK if i == _cursor else COLOR_TEXT
			_text(Vector2(x, y), LETTERS[_letters[i]], 16, col, HORIZONTAL_ALIGNMENT_CENTER, 14)
			if i == _cursor and fmod(_age, 0.6) < 0.4:
				_canvas.draw_rect(Rect2(x + 1, y + 3, 12, 2), COLOR_MARK)
			for up: bool in [true, false]:
				var c := _letter_arrow(i, up).get_center()
				var s := -1.0 if up else 1.0
				_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -2 * s), c + Vector2(4, -2 * s),
						c + Vector2(0, 3 * s)]), COLOR_MARK if i == _cursor else COLOR_DIM)
		_text(Vector2(0, y + 24), "W / S — буква,  A / D — позиция", 8, COLOR_DIM,
				HORIZONTAL_ALIGNMENT_CENTER, w)
		return

	var list := board.entries(StringName(result["class"]))
	_text(Vector2(0, y), "РЕКОРДЫ", 8, COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
	y += 11.0
	for i in list.size():
		var e: Dictionary = list[i]
		var col := COLOR_MARK if i == _highlight else COLOR_TEXT
		var x := w * 0.5 - 100
		_text(Vector2(x, y), "%2d." % (i + 1), 8, COLOR_DIM)
		_text(Vector2(x + 18, y), String(e.get("name", "???")), 8, col)
		_text(Vector2(x + 50, y), str(int(e.get("score", 0))), 8, col, HORIZONTAL_ALIGNMENT_RIGHT, 60)
		_text(Vector2(x + 120, y), _format_time(float(e.get("time", 0.0))), 8, COLOR_DIM)
		var saved: bool = e.get("cause", "") == String(RunState.CAUSE_EVACUATED)
		_text(Vector2(x + 152, y), "возврат" if saved else "гибель", 8, COLOR_GOOD if saved else COLOR_BAD)
		y += 10.0
	if list.is_empty():
		_text(Vector2(0, y), "пока пусто", 8, COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)


static func _format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


func _text(pos: Vector2, s: String, font_size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	_canvas.draw_string(_font, pos + Vector2.ONE, s, align, width, font_size, Color(0, 0, 0, 0.85))
	_canvas.draw_string(_font, pos, s, align, width, font_size, color)
