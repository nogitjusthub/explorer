class_name PauseOverlay
extends CanvasLayer
## Пауза (GDD §8): Esc / Start останавливает забег — всё дерево на паузе, звук тоже. Меню челнока
## паузы не даёт (оно поверх игры). Работает, только пока идёт забег (enabled ставит GameFlow). На паузе —
## меню настроек (SettingsPanel: громкость, управление, вид сзади): W / S — пункт, A / D — значение, мышь.

var enabled := false
var settings: SettingsPanel

var _shade: ColorRect


func _ready() -> void:
	name = "PauseOverlay"
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shade = ColorRect.new()
	_shade.color = Color(0.06, 0.04, 0.1, 0.55)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_line("ПАУЗА", 92, UiKit.TITLE, UiKit.COLOR_TEXT)
	settings = SettingsPanel.new()
	add_child(settings)
	settings.position = Vector2(roundf((480.0 - settings.size.x) * 0.5), 124)
	_line("Esc — продолжить", 124 + settings.size.y + 10.0, UiKit.TEXT, UiKit.COLOR_DIM)
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
	# Справка поверх паузы: клавиши меню настроек не трогают.
	if visible and not HelpScreen.shown(get_tree()):
		for action: StringName in [&"move_up", &"move_down", &"move_left", &"move_right"]:
			if event.is_action_pressed(action) and settings.handle(action):
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
