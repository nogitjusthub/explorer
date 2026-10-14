class_name HelpScreen
extends CanvasLayer
## Справка (F1 или кнопка «?»): цель игры, намёк на угрозы, управление. Вся справочная информация —
## здесь, на остальных экранах только кнопки. Во время вылазки ставит игру на паузу и снимает её при
## закрытии (если паузу ставила сама). Пока справка открыта, другие экраны ввод не берут (shown()).

const GOAL := "Вас высадили на чужую планету! Собирайте находки и попытайтесь довезти их до челнока — " \
		+ "он садится на площадку по расписанию.\n" \
		+ "Если чувствуете уверенность — можете продолжить экспедицию. Но помните: аварийный челнок — " \
		+ "дорог, машина — одна, а груз сам себя не довезёт.\n" \
		+ "Скучно не будет."
const THREATS := "Погода здесь меняется без спроса: темнеет небо, затягивает горизонт. Земля не всегда " \
		+ "стоит на месте. И вы здесь не одни — особенно в песках.\nПейджер скажет, что надвигается. " \
		+ "Но не скажет откуда."
const CONTROLS := [
	["Движение", "W A S D", "левый стик"],
	["Аварийный челнок", "F, A / D", "X, стик"],
	["Меню челнока", "W / S, F", "стик, X"],
	["Поворот камеры", "Q / E", "LB / RB"],
	["Карта мира", "M", "крестовина ↑"],
	["Пауза", "Esc", "Start"],
	["Громкость (пауза)", "A / D", "стик"],
	["Справка", "F1", ""],
]

const GROUP := &"help_screen"
const MARGIN := 14.0                   ## поля экрана
const COL_GAP := 8.0                   ## зазор между колонками таблицы управления
const ROW_H := 13.0

var pause_game := false                ## во время вылазки — ставить игру на паузу
var _paused_here := false
var _canvas: Control
var _closed_frame := -1
var _close: Button
var _table_x := 0.0                    ## левый край таблицы управления (справа, по ширине текста)
var _col: Array[float] = []            ## отступы колонок таблицы от _table_x


func _ready() -> void:
	name = "HelpScreen"
	add_to_group(GROUP)
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.03, 0.07, 0.96)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_help)
	add_child(_canvas)
	_layout_table()
	var text_w := _table_x - MARGIN * 2.0 - 1.0     # слева — текст, до разделителя перед таблицей
	var y := _add_block(Vector2(MARGIN, 20), text_w, "ЦЕЛЬ", GOAL)
	_add_block(Vector2(MARGIN, y + 10.0), text_w, "УГРОЗЫ", THREATS)
	_close = UiKit.button("ЗАКРЫТЬ", "Esc")
	_close.pressed.connect(close)
	add_child(_close)
	_close.reset_size()
	_close.position = Vector2(480 - _close.size.x - 14, 320 - _close.size.y - 10)
	visible = false


## Колонки таблицы управления — по самому широкому тексту в каждой; таблица прижата к правому полю.
func _layout_table() -> void:
	var widths: Array[float] = [0.0, 0.0, 0.0]
	var rows: Array = [["УПРАВЛЕНИЕ", "клавиши", "геймпад"]]
	rows.append_array(CONTROLS)
	for row: Array in rows:
		for c in 3:
			var w := UiKit.FONT.get_string_size(row[c], HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT).x
			widths[c] = maxf(widths[c], ceilf(w))
	_col = [0.0, widths[0] + COL_GAP, widths[0] + widths[1] + COL_GAP * 2.0]
	_table_x = 480.0 - MARGIN - (_col[2] + widths[2])


## Блок текста: заголовок и абзац шириной width от pos; возвращает нижний край абзаца.
func _add_block(pos: Vector2, width: float, title: String, body: String) -> float:
	var head := Label.new()
	head.text = title
	head.position = pos
	head.add_theme_font_size_override(&"font_size", UiKit.TEXT)
	head.add_theme_color_override(&"font_color", UiKit.COLOR_MARK)
	add_child(head)
	var label := Label.new()
	label.text = body
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", UiKit.TEXT)
	label.add_theme_color_override(&"font_color", UiKit.COLOR_TEXT)
	label.add_theme_constant_override(&"line_spacing", -1)
	add_child(label)
	label.position = pos + Vector2(0, ROW_H)
	label.custom_minimum_size = Vector2(width, 0)
	label.size = Vector2(width, 0)
	return label.position.y + label.get_combined_minimum_size().y


func _draw_help() -> void:
	var x := _table_x
	var y := 30.0
	UiKit.text(_canvas, Vector2(x, y), "УПРАВЛЕНИЕ", UiKit.TEXT, UiKit.COLOR_MARK)
	UiKit.text(_canvas, Vector2(x + _col[1], y), "клавиши", UiKit.TEXT, UiKit.COLOR_DIM)
	UiKit.text(_canvas, Vector2(x + _col[2], y), "геймпад", UiKit.TEXT, UiKit.COLOR_DIM)
	y += 16.0
	for row: Array in CONTROLS:
		UiKit.text(_canvas, Vector2(x, y), row[0], UiKit.TEXT, UiKit.COLOR_DIM)
		UiKit.text(_canvas, Vector2(x + _col[1], y), row[1], UiKit.TEXT, UiKit.COLOR_TEXT)
		UiKit.text(_canvas, Vector2(x + _col[2], y), row[2], UiKit.TEXT, UiKit.COLOR_TEXT)
		y += ROW_H
	var line_x := _table_x - MARGIN * 0.5 - 1.0
	_canvas.draw_line(Vector2(line_x, 24), Vector2(line_x, 296), Color(1, 1, 1, 0.12), 1.0)


func open() -> void:
	if visible:
		return
	visible = true
	if pause_game and not get_tree().paused:
		get_tree().paused = true
		_paused_here = true


func close() -> void:
	if not visible:
		return
	visible = false
	if _paused_here:
		get_tree().paused = false
		_paused_here = false
	_closed_frame = Engine.get_process_frames()   # в этом кадре экраны под справкой ввод ещё не берут


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"help"):
		get_viewport().set_input_as_handled()
		if visible:
			close()
		else:
			open()
	elif visible and (event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel")):
		get_viewport().set_input_as_handled()
		close()


## Открыта ли справка (или закрылась в этом кадре — Esc, закрывший её, не должен дойти до экрана под ней).
static func shown(tree: SceneTree) -> bool:
	for n in tree.get_nodes_in_group(GROUP):
		# Без «as HelpScreen»: ссылка скрипта на собственный класс держит его в памяти — утечка при выходе.
		if (n as CanvasLayer).visible or int(n.get(&"_closed_frame")) == Engine.get_process_frames():
			return true
	return false
