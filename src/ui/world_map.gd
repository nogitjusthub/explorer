class_name WorldMap
extends CanvasLayer
## Карта мира (GDD §8): [M] (геймпад — крестовина вверх) открывает её на весь экран и закрывает; игра идёт
## дальше, не пауза. Поверх карты — HUD (кроме радара): урон и сообщения видны. По центру — машина; карта
## ориентирована по экрану, как радар и управление: тайл — ромб 4×2 пикселя (изометрия 2:1 сверху), поворот
## камеры — поворот карты. Разведанное (MapMemory: что машина видела — видимость по погоде) — в цвете;
## подгруженное, но не виденное — полутёмным; где чанки не грузились — темнота. Находки — все, что хоть раз
## засёк радар (его дальность, в грозу — вдвое меньше) и ещё не собраны, — и там, где машина не была. Площадка
## челнока — мигающей рамкой, за краем — стрелкой. Память пишется весь забег, открыта карта или нет.

const BG := Color(0.03, 0.025, 0.06)
const COLOR_SELF := Color(1, 1, 1)
const COLOR_PAD := Color(0.45, 1.0, 0.95)
const COLOR_OUTLINE := Color(0, 0, 0, 0.85)
const REFRESH_S := 0.25
const RENDER_USEC := 1000                ## бюджет отрисовки памяти карты за кадр
const EDGE := 6.0                        ## стрелка на площадку — у края экрана

var memory: MapMemory
var pickups: PickupField
var vehicle: Vehicle
var rig: IsoCameraRig
var hud: Hud
var threats: ThreatDirector
var enabled := false                     ## во время вылазки: память пишется, M работает

var _canvas: Control
var _textures: Dictionary[Vector2i, ImageTexture] = {}
var _blips: Array[Dictionary] = []       ## {pos: Vector2 (тайлы мира), color, big}
var _refresh := 0.0
var _detect := 0.0
var _detected: Dictionary[int, bool] = {}   ## ключи находок, которые засёк радар (собранные выпадут из known())
var _time := 0.0
var _pad := Vector3.INF
var _pad_landed := false
var _colors: Dictionary[StringName, Color] = {}


func _ready() -> void:
	name = "WorldMap"
	layer = 5                            # над непогодой (4), под HUD (6)
	visible = false
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)
	for id in Balance.pickup_ids():
		_colors[id] = Balance.pickup(id).color
	EventBus.shuttle_state_changed.connect(func(state: StringName, _s: float, pad: Vector3) -> void:
		_pad = pad
		_pad_landed = state == &"landed")


func is_open() -> bool:
	return visible


func set_open(open: bool) -> void:
	visible = open
	if hud != null:
		hud.radar.visible = not open
	if open:
		_refresh = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"map") and (enabled or visible):
		get_viewport().set_input_as_handled()
		set_open(not visible)


func _process(dt: float) -> void:
	_time += dt
	if memory == null:
		return
	memory.render_step(RENDER_USEC)
	if enabled and vehicle != null:
		var s := vehicle.state
		var see := MapMemory.SEEN_R if threats == null else threats.visibility(s.pos, s.y, MapMemory.SEEN_R)
		memory.mark_seen(s.pos, see)
		_detect -= dt
		if _detect <= 0.0 and pickups != null and hud != null:
			_detect = REFRESH_S
			var radar := hud.radar
			for p in pickups.within(s.pos, radar.range_tiles * (0.5 if radar.jammed else 1.0)):
				_detected[p["key"]] = true
	if not visible:
		return
	for coord in memory.take_dirty():
		var tex: ImageTexture = _textures.get(coord)
		if tex == null:
			_textures[coord] = ImageTexture.create_from_image(memory.image(coord))
		else:
			tex.update(memory.image(coord))
	_refresh -= dt
	if _refresh <= 0.0:
		_refresh = REFRESH_S
		_blips.clear()
		for p in pickups.known():
			if _detected.has(p["key"]):
				var pos: Vector2 = p["pos"]
				var kind: StringName = p["kind"]
				_blips.append({"pos": pos, "color": _colors.get(kind, Color.WHITE), "big": kind == &"core"})
	_canvas.queue_redraw()


## Оси карты на экране: куда сдвигается картинка на тайл по X и по Z мира. Из поворота камеры (четверть, а не
## текущий угол — без перекоса в повороте): экранные «право» и «вверх» как у радара, тайл — ромб 4×2.
func axes() -> Array[Vector2]:
	var yaw := deg_to_rad(45.0) + (rig.quarter() if rig != null else 0) * PI * 0.5
	var c := signf(cos(yaw))
	var s := signf(sin(yaw))
	return [Vector2(2.0 * c, s), Vector2(-2.0 * s, c)]


func _draw_map() -> void:
	var size := _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), BG)
	if vehicle == null or memory == null:
		return
	var ax := axes()
	var vp := vehicle.state.pos
	var origin := ((size * 0.5).floor() - (ax[0] * vp.x + ax[1] * vp.y)).round()
	var xf := Transform2D(ax[0], ax[1], origin)
	# Видимые чанки: углы экрана в тайлах мира.
	var inv := xf.affine_inverse()
	var lo := Vector2(INF, INF)
	var hi := -lo
	for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		var t: Vector2 = inv * corner
		lo = lo.min(t)
		hi = hi.max(t)
	var c0 := Vector2i(floori(lo.x / Grid.CHUNK), floori(lo.y / Grid.CHUNK))
	var c1 := Vector2i(floori(hi.x / Grid.CHUNK), floori(hi.y / Grid.CHUNK))
	_canvas.draw_set_transform_matrix(xf)
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var tex: ImageTexture = _textures.get(Vector2i(cx, cz))
			if tex != null:
				_canvas.draw_texture(tex, Vector2(cx * Grid.CHUNK, cz * Grid.CHUNK))
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	for blip in _blips:
		var p: Vector2 = (xf * (blip["pos"] as Vector2)).floor()
		var s := 3.0 if blip["big"] else 2.0
		_canvas.draw_rect(Rect2(p - Vector2(1, 1), Vector2(s + 2.0, s + 2.0)), COLOR_OUTLINE)
		_canvas.draw_rect(Rect2(p, Vector2(s, s)), blip["color"])
	_draw_pad(xf, size)
	# Машина — треугольник по курсу.
	var c: Vector2 = xf * vp
	var f := Vector2.from_angle(vehicle.state.heading)
	var fs := (ax[0] * f.x + ax[1] * f.y).normalized()
	var ss := Vector2(-fs.y, fs.x)
	var tri := PackedVector2Array([c + fs * 5.0, c - fs * 3.0 + ss * 3.5, c - fs * 3.0 - ss * 3.5])
	_canvas.draw_colored_polygon(tri, COLOR_OUTLINE)
	_canvas.draw_colored_polygon(PackedVector2Array([c + fs * 3.5, c - fs * 2.0 + ss * 2.5, c - fs * 2.0 - ss * 2.5]), COLOR_SELF)
	_draw_legend(size)


## Площадка челнока: на карте — мигающая рамка (села — горит ровно), за краем экрана — стрелка к ней.
func _draw_pad(xf: Transform2D, size: Vector2) -> void:
	if _pad == Vector3.INF or not (_pad_landed or fmod(_time, 0.8) < 0.55):
		return
	var p: Vector2 = xf * Vector2(_pad.x, _pad.z)
	var inner := Rect2(Vector2(EDGE, EDGE), size - Vector2(EDGE, EDGE) * 2.0)
	if inner.has_point(p):
		_canvas.draw_rect(Rect2((p - Vector2(4, 3)).floor(), Vector2(9, 7)), COLOR_PAD, false, 1.0)
		return
	var center := size * 0.5
	var dir := (p - center).normalized()
	# Точка на краю внутреннего прямоугольника по направлению к площадке.
	var k := INF
	if absf(dir.x) > 1e-4:
		k = minf(k, (inner.size.x * 0.5) / absf(dir.x))
	if absf(dir.y) > 1e-4:
		k = minf(k, (inner.size.y * 0.5) / absf(dir.y))
	var tip := center + dir * k
	var side := Vector2(-dir.y, dir.x)
	_canvas.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 6.0 + side * 3.5, tip - dir * 6.0 - side * 3.5]),
			COLOR_PAD)


## Легенда находок и подсказка — внизу слева.
func _draw_legend(size: Vector2) -> void:
	var ids := Balance.pickup_ids()
	var y := size.y - 6.0 - 11.0 * ids.size()
	for id in ids:
		_canvas.draw_rect(Rect2(Vector2(6, y - 6), Vector2(4, 4)), COLOR_OUTLINE)
		_canvas.draw_rect(Rect2(Vector2(7, y - 5), Vector2(2, 2)), _colors[id])
		UiKit.text(_canvas, Vector2(14, y), Balance.pickup(id).display_name, UiKit.TEXT, UiKit.COLOR_DIM)
		y += 11.0
	UiKit.text(_canvas, Vector2(6, y), "КАРТА  [M]", UiKit.TEXT, UiKit.COLOR_TEXT)
