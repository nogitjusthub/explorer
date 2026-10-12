class_name Radar
extends Control
## Комбинированный радар (GDD §2.2, §8): находки, канистры, ремкомплекты и площадка челнока в радиусе
## rules.radar_range; площадка дальше — стрелкой на краю. Ориентирован по экрану: «вверх» на радаре —
## от камеры в глубину кадра, как и управление. Фауну не показывает.
## Гроза над машиной (jammed): дальность вдвое меньше, и почти всё время на экране только «снег» и полосы
## помех — настоящая картинка проскакивает изредка (BURST_*) с глитчами: строки сдвинуты, цвет двоится.

const R := 40.0                        ## радиус круга, пикселей рендера (пейджер под радаром — той же ширины)
const REFRESH_S := 0.1
const COLOR_BG := Color(0.06, 0.04, 0.09, 0.62)
const COLOR_GRID := Color(0.5, 0.9, 0.85, 0.18)
const COLOR_SELF := Color(1, 1, 1)
const COLOR_PAD := Color(0.45, 1.0, 0.95)
const BURST_MIN_S := 0.15              ## в грозу картинка проскакивает на столько…
const BURST_MAX_S := 0.35
const BURST_GAP_MIN_S := 1.2           ## …раз в столько секунд
const BURST_GAP_MAX_S := 3.0
const SNOW := 70                       ## точек «снега» на кадр

var pickups: PickupField
var vehicle: Vehicle
var camera: Camera3D
var range_tiles := 40.0
var jammed := false                    ## гроза над машиной: дальность вдвое меньше, сквозь помехи — изредка

var _blips: Array[Dictionary] = []     ## {pos: Vector2 (тайлы мира), color: Color, big: bool}
var _pad := Vector3.INF
var _pad_landed := false
var _refresh := 0.0
var _time := 0.0
var _colors: Dictionary[StringName, Color] = {}
var _noise := RandomNumberGenerator.new()   ## мерцание помех — только картинка, не геймплей
var _burst := 0.0                      ## картинка проскакивает сквозь помехи ещё столько секунд
var _burst_wait := 0.0


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
	_burst = maxf(_burst - dt, 0.0)
	if jammed:
		_burst_wait -= dt
		if _burst_wait <= 0.0:
			_burst = _noise.randf_range(BURST_MIN_S, BURST_MAX_S)
			_burst_wait = _burst + _noise.randf_range(BURST_GAP_MIN_S, BURST_GAP_MAX_S)
	_refresh -= dt
	if _refresh <= 0.0 and pickups != null and vehicle != null:
		_refresh = REFRESH_S
		_blips.clear()
		for p in pickups.within(vehicle.state.pos, range_tiles * (0.5 if jammed else 1.0)):
			if jammed and _noise.randf() < 0.25:
				continue
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
	var reach := R * (0.5 if jammed else 1.0)
	if jammed:
		_draw_snow(c)
	var visible_now := not jammed or _burst > 0.0
	for blip in _blips if visible_now else []:
		var d: Vector2 = blip["pos"] - origin
		var p := c + Vector2(d.dot(right), -d.dot(up)) * scale
		var s := 3.0 if blip["big"] else 2.0
		var r := Rect2((p - Vector2(s, s) * 0.5).floor(), Vector2(s, s))
		if jammed:
			r.position.x += _row_shift(r.position.y)
			draw_rect(Rect2(r.position + Vector2(1, 0), r.size), Color(1.0, 0.2, 0.3, 0.6))   # цвет двоится
		draw_rect(r, blip["color"])
	if _pad != Vector3.INF and visible_now:
		var d := Vector2(_pad.x, _pad.z) - origin
		var p := Vector2(d.dot(right), -d.dot(up)) * scale
		var on := _pad_landed or fmod(_time, 0.8) < 0.55
		if p.length() <= reach - 3.0:
			if on:
				draw_rect(Rect2((c + p - Vector2(2, 2)).floor(), Vector2(5, 5)), COLOR_PAD, false, 1.0)
		elif on:
			var dir := p.normalized()
			var tip := c + dir * (reach - 1.0)
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([tip, tip - dir * 5.0 + side * 3.0, tip - dir * 5.0 - side * 3.0]),
					COLOR_PAD)
	if jammed and not visible_now:
		_draw_bars(c)
	# Машина — треугольник по курсу (видна и сквозь помехи — чтобы не потерять направление).
	var f := Vector2.from_angle(vehicle.state.heading)
	var fs := Vector2(f.dot(right), -f.dot(up))
	var ss := Vector2(-fs.y, fs.x)
	draw_colored_polygon(PackedVector2Array([c + fs * 3.5, c - fs * 2.0 + ss * 2.5, c - fs * 2.0 - ss * 2.5]),
			COLOR_SELF)


## Помехи: «снег» по кругу радара.
func _draw_snow(c: Vector2) -> void:
	for _i in SNOW:
		var n := Vector2.from_angle(_noise.randf() * TAU) * sqrt(_noise.randf()) * R
		var v := _noise.randf_range(0.35, 1.0)
		draw_rect(Rect2((c + n).floor(), Vector2.ONE), Color(v * 0.8, v * 0.9, v, 0.35 + 0.4 * v))


## Помехи без картинки: пара бегущих горизонтальных полос.
func _draw_bars(c: Vector2) -> void:
	for i in 2:
		var y := fmod(_time * (23.0 + 17.0 * i) + i * 31.0, 2.0 * R) - R
		var half := sqrt(maxf(R * R - y * y, 0.0))
		draw_rect(Rect2(Vector2(c.x - half, c.y + y).floor(), Vector2(half * 2.0, 1.0 + i)), Color(0.75, 0.85, 1.0, 0.25))


## Глитч картинки: строки сдвинуты в стороны, сдвиг меняется скачками.
func _row_shift(y: float) -> float:
	var h := hash(Vector2i(int(y) / 3, int(_time * 12.0)))
	return float(h % 7) - 3.0 if h % 3 == 0 else 0.0
