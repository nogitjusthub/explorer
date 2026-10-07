class_name StartScreen
extends CanvasLayer
## Стартовый экран «нажмите любую клавишу». Нужен и для веба: браузер включает звук
## только после действия пользователя.

signal started

var _done := false


func _ready() -> void:
	layer = 20
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.05, 0.12, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var label := Label.new()
	label.text = "EXPLORER\n\nW / A / S / D — движение, Q / E — поворот камеры, F3 — отладка\n\nНажмите любую клавишу"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override(&"font_size", 22)
	add_child(label)


func _input(event: InputEvent) -> void:
	if _done:
		return
	var pressed: bool = (event is InputEventKey and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed) \
			or (event is InputEventMouseButton and event.pressed)
	if pressed:
		_done = true
		get_viewport().set_input_as_handled()
		started.emit()
		queue_free()
