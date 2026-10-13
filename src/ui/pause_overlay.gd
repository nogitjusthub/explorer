class_name PauseOverlay
extends CanvasLayer
## Пауза (GDD §8): Esc / Start останавливает забег — всё дерево на паузе, звук тоже. Меню челнока
## паузы не даёт (оно поверх игры). Работает, только пока идёт забег (enabled ставит GameFlow). На паузе —
## регулятор громкости: мышью или A / D (стиком).

var enabled := false

var _shade: ColorRect
var _volume: VolumeSlider


func _ready() -> void:
	name = "PauseOverlay"
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shade = ColorRect.new()
	_shade.color = Color(0.06, 0.04, 0.1, 0.55)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_line("ПАУЗА", 112, UiKit.TITLE, UiKit.COLOR_TEXT)
	# Громкость: подпись и регулятор одной строкой по центру.
	var caption := "ГРОМКОСТЬ"
	_volume = VolumeSlider.new()
	add_child(_volume)
	var cap_w := ceilf(UiKit.FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT).x)
	var x0 := roundf((480.0 - cap_w - 8.0 - _volume.size.x) * 0.5)
	var cap := _line(caption, 148, UiKit.TEXT, UiKit.COLOR_DIM)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cap.position.x = x0
	_volume.position = Vector2(x0 + cap_w + 8.0, 150)
	_line("A / D — громкость      Esc — продолжить", 182, UiKit.TEXT, UiKit.COLOR_DIM)
	visible = false


## Строка по центру экрана на высоте y.
func _line(text: String, y: float, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, y)
	l.size = Vector2(480, font_size + 4)
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _unhandled_input(event: InputEvent) -> void:
	# Справка поверх паузы: A / D громкость не трогают.
	if visible and not HelpScreen.shown(get_tree()) \
			and (event.is_action_pressed(&"move_left") or event.is_action_pressed(&"move_right")):
		_volume.nudge(-1 if event.is_action_pressed(&"move_left") else 1)
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(&"pause"):
		return
	if not enabled and not get_tree().paused:
		return
	get_viewport().set_input_as_handled()
	var paused := not get_tree().paused
	get_tree().paused = paused
	visible = paused
