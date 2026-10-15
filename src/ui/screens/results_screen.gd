class_name ResultsScreen
extends CanvasLayer
## Экран итога (GDD §6): причина конца, разбор счёта, ввод имени при попадании в топ-10 класса
## (до Leaderboard.NAME_MAX знаков — всё, что есть на обычной клавиатуре: латиница, кириллица, цифры, пробел,
## знаки; ввод всегда с пустого поля и первой позиции; с клавиатуры набирается прямо, Backspace стирает;
## аркадный выбор для геймпада и стрелок: ↑/↓ — знак, ←/→ — позиция; Enter — готово; на телефоне — тап по
## стрелкам над и под знаком и кнопка «Готово»; пустые позиции — пробел, по краям обрезается),
## затем таблица рекордов и две кнопки с хоткеями:
## «Заново» (R) — сразу новый забег на той же машине, «Выход» (Esc) — в трюм челнока к выбору машины.
## Класс машины показан портретом — названий классов игроку не показываем.

signal restart_requested
signal exit_requested

## Знаки имени — всё, что есть на обычной клавиатуре (латиница, кириллица, цифры, знаки ASCII): первый — пусто
## (пробел); буквы заглавные — набор переводится в них.
const LETTERS := " ABCDEFGHIJKLMNOPQRSTUVWXYZАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ0123456789-_.,!?#@$%&*+=/\\|:;'\"()[]{}<>^~`"
const LETTERS_Y := 166.0
const SLOT_W := 18.0                     ## шаг позиций имени: знак кеглем 20 — до 16 пикселей
const LINE_H := 11.0                     ## шаг строк таблиц: шрифт 10 px и пиксель зазора
const INPUT_DELAY_S := 0.8             ## нажатия в первые доли секунды игнорируются (палец ещё на газе)
const CAUSE_TEXT := {
	"evacuated": "ВОЗВРАЩЕНИЕ НА ОРБИТУ",
	"drowned": "МАШИНА УТОНУЛА",
	"fall": "РАЗБИТА ПРИ ПАДЕНИИ",
	"tree": "РАЗБИТА О ДЕРЕВЬЯ",
	"ram": "РАЗБИТА О ЗВЕРЕЙ",
	"wall": "РАЗБИТА О СКАЛЫ",
	"lightning": "СГОРЕЛА ОТ МОЛНИИ",
	"quake": "РАЗБИТА ЗЕМЛЕТРЯСЕНИЕМ",
	"acid": "РАЗЪЕДЕНА КИСЛОТНЫМ ГАЗОМ",
	"tornado": "РАЗБИТА СМЕРЧЕМ",
	"hopper": "ЗАГРЫЗЛИ СКАКУНЫ",
	"worm": "ПРОГЛОЧЕНА ЧЕРВЁМ",
	"shellback": "РАЗБИТА ПАНЦИРНИКОМ",
	"empty_tank": "КОНЧИЛОСЬ ТОПЛИВО",
	"shuttle": "РАЗДАВЛЕНА ЧЕЛНОКОМ",
	"whirlpool": "УТОНУЛА В ВОДОВОРОТЕ",
	"ray": "УБИТА ТРОЕГЛАЗКОЙ",
	"shark": "РАЗОРВАНА ИЛОЗУБОМ",
	"nessie": "РАЗБИТА ОЗЁРНЫМ ЧУДОВИЩЕМ",
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
var _letters := PackedInt32Array()       ## индексы знаков в LETTERS по позициям имени
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
	_font = UiKit.FONT
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
	_letters = letters_of("")                # ввод — всегда с пустого поля
	_cursor = 0


## Имя → индексы знаков (до NAME_MAX позиций, незнакомые знаки и хвост — пусто).
static func letters_of(player_name: String) -> PackedInt32Array:
	var up := player_name.to_upper()
	var out := PackedInt32Array()
	out.resize(Leaderboard.NAME_MAX)
	for i in Leaderboard.NAME_MAX:
		out[i] = maxi(LETTERS.find(up[i]), 0) if i < up.length() else 0
	return out


## Ширина знака кеглем имени (UiKit.TITLE), пикселей.
static func glyph_width(font: Font, ch: String) -> float:
	return font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TITLE).x


## Индексы знаков → имя: пустые позиции — пробелы, по краям обрезаются; совсем пусто — «???».
static func compose_name(letters: PackedInt32Array) -> String:
	var s := ""
	for i in letters:
		s += LETTERS[i]
	s = s.strip_edges()
	return s if not s.is_empty() else "???"


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
	if _age >= INPUT_DELAY_S and not HelpScreen.shown(get_tree()):
		action.call()


func _update_buttons() -> void:
	_done.visible = _entering
	_restart.visible = not _entering
	_exit.visible = not _entering


## Левый край позиции i имени (позиции — по центру экрана).
func _slot_x(i: int) -> float:
	return _canvas.size.x * 0.5 - SLOT_W * Leaderboard.NAME_MAX * 0.5 + i * SLOT_W


## Стрелки над и под знаком выбранной позиции (тап меняет знак): прямоугольники для попадания.

## Позиция i имени целиком (тап по знаку — выбрать позицию).
func _letter_slot(i: int) -> Rect2:
	return Rect2(_slot_x(i), LETTERS_Y - 16.0, SLOT_W, 20.0)


func _letter_arrow(i: int, up: bool) -> Rect2:
	return Rect2(_slot_x(i) + 2.0, LETTERS_Y - (25.0 if up else -3.0), 14, 10)


func _input(event: InputEvent) -> void:
	if _age < INPUT_DELAY_S or HelpScreen.shown(get_tree()):
		return
	if _entering and UiKit.is_click(event):
		var p: Vector2 = (event as InputEventMouseButton).position
		for up: bool in [true, false]:                 # стрелки — только у выбранной позиции
			if _letter_arrow(_cursor, up).grow(2.0).has_point(p):
				_letters[_cursor] = (_letters[_cursor] + (1 if up else LETTERS.length() - 1)) % LETTERS.length()
				get_viewport().set_input_as_handled()
				return
		for i in Leaderboard.NAME_MAX:
			if _letter_slot(i).has_point(p):
				_cursor = i
				get_viewport().set_input_as_handled()
				return
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion \
			or event is InputEventAction):
		return
	if _entering and event is InputEventKey and _type_key(event as InputEventKey):
		get_viewport().set_input_as_handled()
		return
	var confirm := event.is_action_pressed(&"radio") or event.is_action_pressed(&"ui_accept")
	if _entering:
		if _arcade(event):
			get_viewport().set_input_as_handled()
		elif confirm:
			_save_entry()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"restart"):
		get_viewport().set_input_as_handled()
		restart_requested.emit()
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		exit_requested.emit()


## Аркадный выбор: ↑ / ↓ — знак выбранной позиции, ← / → — позиция. Стрелки клавиатуры и крестовина (ui_*, с
## автоповтором) и стик (move_*; W / A / S / D клавиатуры сюда не доходят — при наборе имени это буквы).
## true — событие съедено.
func _arcade(event: InputEvent) -> bool:
	if _pressed(event, &"ui_up", &"move_up"):
		_letters[_cursor] = (_letters[_cursor] + 1) % LETTERS.length()
	elif _pressed(event, &"ui_down", &"move_down"):
		_letters[_cursor] = (_letters[_cursor] + LETTERS.length() - 1) % LETTERS.length()
	elif _pressed(event, &"ui_left", &"move_left"):
		_cursor = maxi(_cursor - 1, 0)
	elif _pressed(event, &"ui_right", &"move_right"):
		_cursor = mini(_cursor + 1, Leaderboard.NAME_MAX - 1)
	else:
		return false
	return true


static func _pressed(event: InputEvent, a: StringName, b: StringName) -> bool:
	return event.is_action_pressed(a, true) or event.is_action_pressed(b, true)


## Набор с клавиатуры: знак из LETTERS (всё с обычной клавиатуры; W/A/S/D при наборе имени — тоже буквы)
## встаёт в позицию, курсор идёт дальше; Backspace стирает назад. true — клавиша съедена.
func _type_key(k: InputEventKey) -> bool:
	if not k.pressed:
		return false
	if k.keycode == KEY_BACKSPACE:
		if _letters[_cursor] == 0 and _cursor > 0:
			_cursor -= 1
		_letters[_cursor] = 0
		return true
	if k.echo or k.unicode == 0 or k.ctrl_pressed or k.alt_pressed:
		return false
	var idx := LETTERS.find(String.chr(k.unicode).to_upper())
	if idx < 0:
		return false
	_letters[_cursor] = idx
	_cursor = mini(_cursor + 1, Leaderboard.NAME_MAX - 1)
	return true


func _save_entry() -> void:
	var entry_name := compose_name(_letters)
	_highlight = board.add(StringName(result["class"]), {
		"name": entry_name, "score": int(result["score"]), "time": snappedf(float(result["time"]), 0.1),
		"shipments": int(result["shipments"]), "cause": String(result["cause"]),
		"date": Time.get_date_string_from_system(),
	})
	_entering = false
	_update_buttons()


func _draw_screen() -> void:
	var w := _canvas.size.x
	var cause := String(result["cause"])
	var evacuated := cause == String(RunState.CAUSE_EVACUATED)
	_text(Vector2(0, 30), CAUSE_TEXT.get(cause, "МАШИНА УНИЧТОЖЕНА"), UiKit.TITLE,
			COLOR_GOOD if evacuated else COLOR_BAD, HORIZONTAL_ALIGNMENT_CENTER, w)

	var lines: Array[Array] = []
	lines.append(["Сдано челнокам", str(int(result["banked"]))])
	if int(result["emergency_calls"]) > 0:
		lines.append(["  в т. ч. аварийных вызовов", str(int(result["emergency_calls"]))])
	if evacuated:
		lines.append(["Бонус (корпус × 3 + топливо × 2)", "+%d" % int(result["bonus"])])
	else:
		lines.append(["Груз", "потерян"])
	lines.append(["Время забега", _format_time(float(result["time"]))])
	lines.append(["Рейсов челнока", str(int(result["shipments"]))])
	var y := 52.0
	for line in lines:
		_text(Vector2(w * 0.5 - 130, y), line[0], UiKit.TEXT, COLOR_DIM)
		_text(Vector2(w * 0.5 - 130, y), line[1], UiKit.TEXT, COLOR_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 260)
		y += LINE_H
	y += 6.0
	_text(Vector2(0, y + 6), "ИТОГ  %d" % int(result["score"]), UiKit.TITLE, COLOR_MARK, HORIZONTAL_ALIGNMENT_CENTER, w)
	y += 26.0

	if _entering:
		_text(Vector2(0, y), "НОВЫЙ РЕКОРД — %d-е место" % (_rank + 1), UiKit.TEXT, COLOR_GOOD, HORIZONTAL_ALIGNMENT_CENTER, w)
		y = LETTERS_Y
		for i in Leaderboard.NAME_MAX:
			var x := _slot_x(i) + 2.0
			var col := COLOR_MARK if i == _cursor else COLOR_TEXT
			# По центру позиции по своей ширине: с пределом ширины широкий знак (W, Ж, Ш, @) шире предела
			# выбрасывался целиком — набранный, но невидимый.
			var ch := LETTERS[_letters[i]]
			_text(Vector2(_slot_x(i) + floorf((SLOT_W - glyph_width(_font, ch)) * 0.5), y), ch, UiKit.TITLE, col)
			if i == _cursor and fmod(_age, 0.6) < 0.4:
				_canvas.draw_rect(Rect2(x + 1, y + 3, 12, 2), COLOR_MARK)
			elif i != _cursor and _letters[i] == 0:
				_canvas.draw_rect(Rect2(x + 3, y + 3, 8, 1), COLOR_DIM)      # пустая позиция — черта
			if i != _cursor:
				continue
			for up: bool in [true, false]:
				var c := _letter_arrow(i, up).get_center()
				var s := -1.0 if up else 1.0
				_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -2 * s), c + Vector2(4, -2 * s),
						c + Vector2(0, 3 * s)]), COLOR_MARK)
		_text(Vector2(0, y + 24), "Набери имя (до %d знаков), Backspace — стереть" % Leaderboard.NAME_MAX,
				UiKit.TEXT, COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
		_text(Vector2(0, y + 24 + LINE_H), "↑ ↓ — знак,  ← → — позиция,  Enter — готово", UiKit.TEXT, COLOR_DIM,
				HORIZONTAL_ALIGNMENT_CENTER, w)
		return

	var list := board.entries(StringName(result["class"]))
	_text(Vector2(0, y), "РЕКОРДЫ", UiKit.TEXT, COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
	y += 11.0
	for i in list.size():
		var e: Dictionary = list[i]
		var col := COLOR_MARK if i == _highlight else COLOR_TEXT
		var x := w * 0.5 - 104
		_text(Vector2(x, y), "%2d." % (i + 1), UiKit.TEXT, COLOR_DIM)
		_text(Vector2(x + 18, y), String(e.get("name", "???")), UiKit.TEXT, col)      # 8 знаков — до 64 пикселей
		_text(Vector2(x + 84, y), str(int(e.get("score", 0))), UiKit.TEXT, col, HORIZONTAL_ALIGNMENT_RIGHT, 44)
		_text(Vector2(x + 136, y), _format_time(float(e.get("time", 0.0))), UiKit.TEXT, COLOR_DIM)
		var saved: bool = e.get("cause", "") == String(RunState.CAUSE_EVACUATED)
		_text(Vector2(x + 166, y), "возврат" if saved else "гибель", UiKit.TEXT, COLOR_GOOD if saved else COLOR_BAD)
		y += LINE_H
	if list.is_empty():
		_text(Vector2(0, y), "пока пусто", UiKit.TEXT, COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)


static func _format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


func _text(pos: Vector2, s: String, font_size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	_canvas.draw_string(_font, pos + Vector2.ONE, s, align, width, font_size, Color(0, 0, 0, 0.85))
	_canvas.draw_string(_font, pos, s, align, width, font_size, color)
