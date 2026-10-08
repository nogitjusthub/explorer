class_name Radar
extends Control
## Комбинированный радар (GDD §2.2, §8): находки, канистры, ремкомплекты и площадка челнока в радиусе
## rules.radar_range; площадка дальше — стрелкой на краю. Ориентирован по экрану: «вверх» на радаре —
## от камеры в глубину кадра, как и управление. Фауну не показывает.

const R := 30.0                        ## радиус круга, пикселей рендера
const REFRESH_S := 0.1
const COLOR_BG := Color(0.06, 0.04, 0.09, 0.62)
const COLOR_GRID := Color(0.5, 0.9, 0.85, 0.18)
const COLOR_SELF := Color(1, 1, 1)
const COLOR_PAD := Color(0.45, 1.0, 0.95)

var pickups: PickupField
var vehicle: Vehicle
var camera: Camera3D
var range_tiles := 40.0

var _blips: Array[Dictionary] = []     ## {pos: Vector2 (тайлы мира), color: Color, big: bool}
var _pad := Vector3.INF
var _pad_landed := false
var _refresh := 0.0
var _time := 0.0
var _colors: Dictionary[StringName, Color] = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id in Balance.pickup_ids():
		_colors[id] = Balance.pickup(id).color
	EventBus.shuttle_state_changed.connect(_on_shuttle_state)


func _on_shuttle_state(state: StringName, _seconds: float, pad: Vector3) -> void:
	_pad = pad
	_pad_landed = state == &"landed"


func _process(dt: float) -> void:
	_time += dt
	_refresh -= dt
	if _refresh <= 0.0 and pickups != null and vehicle != null:
		_refresh = REFRESH_S
		_blips.clear()
		for p in pickups.within(vehicle.state.pos, range_tiles):
			var kind: StringName = p["kind"]
			_blips.append({"pos": p["pos"], "color": _colors.get(kind, Color.WHITE), "big": kind == &"core"})
	queue_redraw()


func _draw() -> void:
	if vehicle == null or camera == null:
		return
	var c := Vector2(R, R)
	draw_circle(c, R + 1.0, COLOR_BG)
	draw_arc(c, R, 0.0, TAU, 32, COLOR_GRID, 1.0)
	draw_arc(c, R * 0.5, 0.0, TAU, 24, COLOR_GRID, 1.0)
	draw_line(c - Vector2(R, 0), c + Vector2(R, 0), COLOR_GRID)
	draw_line(c - Vector2(0, R), c + Vector2(0, R), COLOR_GRID)
	var b := camera.global_transform.basis
	var right := Vector2(b.x.x, b.x.z).normalized()
	var up := Vector2(-b.z.x, -b.z.z).normalized()
	var origin := vehicle.state.pos
	var scale := R / range_tiles
	for blip in _blips:
		var d: Vector2 = blip["pos"] - origin
		var p := c + Vector2(d.dot(right), -d.dot(up)) * scale
		var s := 3.0 if blip["big"] else 2.0
		draw_rect(Rect2((p - Vector2(s, s) * 0.5).floor(), Vector2(s, s)), blip["color"])
	if _pad != Vector3.INF:
		var d := Vector2(_pad.x, _pad.z) - origin
		var p := Vector2(d.dot(right), -d.dot(up)) * scale
		var on := _pad_landed or fmod(_time, 0.8) < 0.55
		if p.length() <= R - 3.0:
			if on:
				draw_rect(Rect2((c + p - Vector2(2, 2)).floor(), Vector2(5, 5)), COLOR_PAD, false, 1.0)
		elif on:
			var dir := p.normalized()
			var tip := c + dir * (R - 1.0)
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([tip, tip - dir * 5.0 + side * 3.0, tip - dir * 5.0 - side * 3.0]),
					COLOR_PAD)
	# Машина — треугольник по курсу.
	var f := Vector2.from_angle(vehicle.state.heading)
	var fs := Vector2(f.dot(right), -f.dot(up))
	var ss := Vector2(-fs.y, fs.x)
	draw_colored_polygon(PackedVector2Array([c + fs * 3.5, c - fs * 2.0 + ss * 2.5, c - fs * 2.0 - ss * 2.5]),
			COLOR_SELF)
