class_name Toast
extends CanvasLayer
## Короткое сообщение внизу экрана (например, «снимок сохранён»), гаснет само.

var _label: Label
var _time_left := 0.0


func _ready() -> void:
	layer = 15
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 8)
	_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_label.add_theme_constant_override(&"shadow_offset_y", 1)
	_label.position = Vector2(4, get_viewport().get_visible_rect().size.y - 14)
	add_child(_label)
	visible = false


func show_message(text: String, seconds: float = 4.0) -> void:
	_label.text = text
	_time_left = seconds
	visible = true


func _process(dt: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left -= dt
	if _time_left <= 0.0:
		visible = false
