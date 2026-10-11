class_name Pager
extends Control
## Пейджер (GDD §8): под радаром, той же ширины, — до трёх сообщений об активных угрозах: только
## название, без направления и без отсчёта (направление на угрозы — апгрейд «продвинутый радар», §12).
## Кислотный туман подписан просто «ТУМАН» — его выдаёт только цвет. Кроме угроз — «МАЛО ТОПЛИВА»
## (меньше 20% бака, GameFlow). Новое сообщение мигает;
## держится, пока угроза шлёт телеграф.

const LINES := 3
const LINE_H := 10.0
const STALE_S := 1.0                   ## телеграф не обновлялся столько — угроза ушла
const NAMES := {
	&"storm": "ГРОЗА", &"quake": "ЗЕМЛЕТРЯСЕНИЕ", &"fog": "ТУМАН", &"acid": "ТУМАН",
	&"dust": "ПЫЛЕВАЯ БУРЯ", &"tornado": "СМЕРЧ", &"low_fuel": "МАЛО ТОПЛИВА",
}
const COLOR_TEXT := Color(1.0, 0.55, 0.3)
const COLOR_NEW := Color(1.0, 0.9, 0.6)
const COLOR_BG := Color(0.06, 0.04, 0.09, 0.62)

var _entries: Array[Dictionary] = []   ## {kind, stale, age}
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	EventBus.threat_telegraphed.connect(_on_telegraphed)
	EventBus.threat_ended.connect(_on_ended)


func _on_telegraphed(kind: StringName, _at: Vector3, _seconds: float, _dir_hint: Vector2) -> void:
	if not NAMES.has(kind):
		return
	for e in _entries:
		if e["kind"] == kind:
			e["stale"] = 0.0
			return
	_entries.push_front({"kind": kind, "stale": 0.0, "age": 0.0})
	if _entries.size() > LINES:
		_entries.pop_back()


func _on_ended(kind: StringName) -> void:
	_entries = _entries.filter(func(e: Dictionary) -> bool: return e["kind"] != kind)


func _process(dt: float) -> void:
	for e in _entries:
		e["stale"] += dt
		e["age"] += dt
	_entries = _entries.filter(func(e: Dictionary) -> bool: return e["stale"] < STALE_S)
	queue_redraw()


func _draw() -> void:
	if _entries.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, LINE_H * _entries.size() + 2.0)), COLOR_BG)
	var y := LINE_H - 1.0
	for e in _entries:
		var text: String = NAMES[e["kind"]]
		var col := COLOR_NEW if e["age"] < 1.0 and fmod(e["age"], 0.3) < 0.15 else COLOR_TEXT
		draw_string(_font, Vector2(0, y) + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4.0, 8, Color(0, 0, 0, 0.85))
		draw_string(_font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4.0, 8, col)
		y += LINE_H
