class_name PauseOverlay
extends CanvasLayer
## Пауза (GDD §8): Esc / Start останавливает забег — всё дерево на паузе, звук тоже. Меню челнока
## паузы не даёт (оно поверх игры). Работает, только пока идёт забег (enabled ставит GameFlow).

var enabled := false

var _label: Label
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
	_label = Label.new()
	_label.text = "ПАУЗА\n\nEsc — продолжить"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override(&"font_size", 16)
	add_child(_label)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if not enabled and not get_tree().paused:
		return
	get_viewport().set_input_as_handled()
	var paused := not get_tree().paused
	get_tree().paused = paused
	visible = paused
