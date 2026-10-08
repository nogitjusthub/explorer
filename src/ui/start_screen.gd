class_name StartScreen
extends CanvasLayer
## Экран перед забегом: выбор машины (A/D или стрелки) и старт любой другой клавишей. Нужен и для
## веба — браузер включает звук только после действия пользователя. Машина видна за экраном крупно.

signal started
signal vehicle_changed(id: StringName)

const TITLE := "EXPLORER\nСобирайте находки и сдавайте груз челноку: остановитесь в круге на площадке.\nТопливо кончается — канистры редки, аварийный челнок дорог."
const CONTROLS := "A / D — выбор машины,  любая другая клавиша — старт\nW / A / S / D — движение,  F — аварийный челнок,  Q / E — камера,  F3 — отладка"

var vehicle_ids: Array[StringName] = []
var selected := 0

var _done := false
var _name: Label
var _info: Label


func _ready() -> void:
	layer = 20
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.05, 0.12, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var title := _label(10, Control.PRESET_TOP_WIDE)
	title.offset_top = 14
	title.offset_bottom = 70
	title.text = TITLE
	_name = _label(16, Control.PRESET_BOTTOM_WIDE)
	_name.offset_top = -122
	_name.offset_bottom = -100
	_info = _label(10, Control.PRESET_BOTTOM_WIDE)
	_info.offset_top = -100
	_info.offset_bottom = -6
	_refresh()


func _label(font_size: int, preset: Control.LayoutPreset) -> Label:
	var label := Label.new()
	label.set_anchors_preset(preset)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override(&"shadow_offset_x", 1)
	label.add_theme_constant_override(&"shadow_offset_y", 1)
	add_child(label)
	return label


func _refresh() -> void:
	if vehicle_ids.is_empty():
		_name.text = ""
		_info.text = CONTROLS
		return
	var cls := Balance.vehicle(vehicle_ids[selected])
	var minutes := cls.fuel_max / (VehicleKinematics.fuel_per_second(cls, 1.0) * 60.0)
	_name.text = "<   %s   >" % cls.display_name.to_upper()
	_info.text = "%s\nHP %d  ·  скорость %s  ·  бак %d (%.0f мин хода)  ·  трюм %d\n\n%s" % [
		cls.blurb, cls.hp_max, _number(cls.max_speed), roundi(cls.fuel_max), minutes, cls.cargo_slots, CONTROLS]


## 6.5 → «6,5», 4.0 → «4».
static func _number(v: float) -> String:
	return ("%.1f" % v).trim_suffix(".0").replace(".", ",")


func _input(event: InputEvent) -> void:
	if _done:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.is_echo()) \
			or (event is InputEventJoypadButton and event.pressed) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventAction and event.pressed)
	if not pressed and not (event is InputEventJoypadMotion):
		return
	get_viewport().set_input_as_handled()
	var step := 0
	if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		step = -1
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		step = 1
	if step != 0:
		if vehicle_ids.size() > 1:
			selected = wrapi(selected + step, 0, vehicle_ids.size())
			_refresh()
			vehicle_changed.emit(vehicle_ids[selected])
		return
	if not pressed:
		return
	_done = true
	started.emit()
	queue_free()
