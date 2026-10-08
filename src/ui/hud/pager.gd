class_name Pager
extends Control
## Пейджер (GDD §8): под радаром — до трёх сообщений об активных угрозах: тип, стрелка направления
## относительно экрана (как радар и управление) и секунды до события. Сообщение держится, пока
## угроза шлёт телеграф, и исчезает с её концом. Звука у большинства угроз нет — это главный канал.

const LINES := 3
const LINE_H := 10.0
const STALE_S := 1.0                   ## телеграф не обновлялся столько — угроза ушла
const NEAR := 6.0                      ## ближе — без стрелки, «рядом»
const NAMES := {
	&"storm": "ГРОЗА", &"quake": "СЕЙСМИКА", &"fog": "ТУМАН", &"acid": "КИСЛОТНЫЙ ГАЗ",
	&"dust": "ПЫЛЕВАЯ БУРЯ", &"tornado": "СМЕРЧ",
}
const COLOR_TEXT := Color(1.0, 0.55, 0.3)
const COLOR_NEW := Color(1.0, 0.9, 0.6)
const COLOR_BG := Color(0.06, 0.04, 0.09, 0.62)

var vehicle: Vehicle
var camera: Camera3D

var _entries: Array[Dictionary] = []   ## {kind, at: Vector3, seconds, stale, age}
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	EventBus.threat_telegraphed.connect(_on_telegraphed)
	EventBus.threat_ended.connect(_on_ended)


func _on_telegraphed(kind: StringName, at: Vector3, seconds: float, _dir_hint: Vector2) -> void:
	if not NAMES.has(kind):
		return
	for e in _entries:
		if e["kind"] == kind:
			e["at"] = at
			e["seconds"] = seconds
			e["stale"] = 0.0
			return
	_entries.push_front({"kind": kind, "at": at, "seconds": seconds, "stale": 0.0, "age": 0.0})
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
	if _entries.is_empty() or vehicle == null or camera == null:
		return
	draw_rect(Rect2(Vector2(size.x - 120.0, 0.0), Vector2(120.0, LINE_H * _entries.size() + 2.0)), COLOR_BG)
	var b := camera.global_transform.basis
	var right := Vector2(b.x.x, b.x.z).normalized()
	var up := Vector2(-b.z.x, -b.z.z).normalized()
	var y := LINE_H - 1.0
	for e in _entries:
		var at: Vector3 = e["at"]
		var d := Vector2(at.x, at.z) - vehicle.state.pos
		var text: String = NAMES[e["kind"]]
		var seconds: float = e["seconds"]
		if seconds > 0.0:
			text += "  %d" % ceili(seconds)
		var near := d.length() < NEAR
		if near:
			text += "  рядом"
		var col := COLOR_NEW if e["age"] < 1.0 and fmod(e["age"], 0.3) < 0.15 else COLOR_TEXT
		var text_right := size.x - (4.0 if near else 14.0)
		draw_string(_font, Vector2(0, y) + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_RIGHT, text_right, 8, Color(0, 0, 0, 0.85))
		draw_string(_font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_RIGHT, text_right, 8, col)
		if not near:
			var s := Vector2(d.dot(right), -d.dot(up)).normalized()
			var c := Vector2(size.x - 7.0, y - 3.0)
			var side := Vector2(-s.y, s.x)
			draw_colored_polygon(PackedVector2Array([c + s * 4.0, c - s * 3.0 + side * 3.0, c - s * 3.0 - side * 3.0]), col)
		y += LINE_H
