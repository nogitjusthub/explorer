class_name HelpScreen
extends CanvasLayer
## Справка (F1 или кнопка «?»): цель игры, намёк на угрозы, управление. Вся справочная информация —
## здесь, на остальных экранах только кнопки. Во время вылазки ставит игру на паузу и снимает её при
## закрытии (если паузу ставила сама). Пока справка открыта, другие экраны ввод не берут (is_open).

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
	["Аварийный челнок", "F", "X"],
	["Меню челнока", "W / S, F", "стик, X"],
	["Поворот камеры", "Q / E", "LB / RB"],
	["Пауза", "Esc", "Start"],
	["Справка", "F1", ""],
]

static var is_open := false

var pause_game := false                ## во время вылазки — ставить игру на паузу
var _paused_here := false
var _canvas: Control
var _close: Button


func _ready() -> void:
	name = "HelpScreen"
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
	_add_block(Rect2(14, 24, 250, 90), "ЦЕЛЬ", GOAL)
	_add_block(Rect2(14, 128, 250, 80), "УГРОЗЫ", THREATS)
	_close = UiKit.button("ЗАКРЫТЬ", "Esc")
	_close.pressed.connect(close)
	add_child(_close)
	_close.reset_size()
	_close.position = Vector2(480 - _close.size.x - 14, 320 - _close.size.y - 10)
	visible = false


func _add_block(r: Rect2, title: String, body: String) -> void:
	var head := Label.new()
	head.text = title
	head.position = r.position
	head.add_theme_font_size_override(&"font_size", 8)
	head.add_theme_color_override(&"font_color", UiKit.COLOR_MARK)
	add_child(head)
	var label := Label.new()
	label.text = body
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", 8)
	label.add_theme_color_override(&"font_color", UiKit.COLOR_TEXT)
	label.add_theme_constant_override(&"line_spacing", -1)
	add_child(label)
	label.position = r.position + Vector2(0, 13)
	label.custom_minimum_size = Vector2(r.size.x, 0)
	label.size = Vector2(r.size.x, r.size.y - 13)


func _draw_help() -> void:
	var x := 284.0
	var y := 30.0
	UiKit.text(_canvas, Vector2(x, y), "УПРАВЛЕНИЕ", 8, UiKit.COLOR_MARK)
	UiKit.text(_canvas, Vector2(x + 96, y), "клавиши", 8, UiKit.COLOR_DIM)
	UiKit.text(_canvas, Vector2(x + 144, y), "геймпад", 8, UiKit.COLOR_DIM)
	y += 16.0
	for row: Array in CONTROLS:
		UiKit.text(_canvas, Vector2(x, y), row[0], 8, UiKit.COLOR_DIM)
		UiKit.text(_canvas, Vector2(x + 96, y), row[1], 8, UiKit.COLOR_TEXT)
		UiKit.text(_canvas, Vector2(x + 144, y), row[2], 8, UiKit.COLOR_TEXT)
		y += 13.0
	_canvas.draw_line(Vector2(274, 24), Vector2(274, 296), Color(1, 1, 1, 0.12), 1.0)


func open() -> void:
	if visible:
		return
	visible = true
	is_open = true
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
	# Сбросить флаг кадром позже: Esc, закрывший справку, не должен дойти до экрана под ней.
	(func() -> void: is_open = visible).call_deferred()


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


func _exit_tree() -> void:
	is_open = false
