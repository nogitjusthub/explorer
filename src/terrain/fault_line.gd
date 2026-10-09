class_name FaultLine
extends RefCounted
## Линия разлома (GDD §5.3) — ломаная в мировых координатах: координаты точек относительно неё
## (вдоль линии и поперёк со знаком) и кэш таких координат для зоны разлома — центры тайлов и вершины
## по полуцелой сетке. Кэш считается лениво или заранее порциями (prepare), пока идёт телеграф, —
## в момент толчка Deformation.fault_path берёт готовое. На Deformation не ссылается (иначе — цикл
## ссылок между скриптами и утечка при выходе).

const CORNERS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]

var path: PackedVector2Array
var lengths: PackedFloat32Array
var total: float
var band: int
var box: Rect2

var _done: Dictionary[Vector2i, Vector2] = {}
var _row := 0


func _init(line: PackedVector2Array, up: int, down: int) -> void:
	path = line
	lengths = path_lengths(line)
	total = lengths[lengths.size() - 1]
	band = maxi(up, down) + 4
	box = path_bounds(line).grow(band + 1.0)


func at_center(tx: int, tz: int) -> Vector2:
	return _at(Vector2i(2 * tx + 1, 2 * tz + 1), band + 1.0)


func at_vertex(vx: int, vz: int) -> Vector2:
	return _at(Vector2i(2 * vx, 2 * vz), band + 2.0)


func _at(key: Vector2i, max_d: float) -> Vector2:
	var got: Variant = _done.get(key)
	if got != null:
		return got
	var c := path_coords(path, lengths, Vector2(key) * 0.5, max_d)
	var v := Vector2(c.x, c.y)
	_done[key] = v
	return v


## Досчитать следующие rows рядов тайлов зоны (центры и вершины). true — всё готово.
func prepare(rows: int) -> bool:
	var z0 := floori(box.position.y)
	var z1 := ceili(box.end.y)
	for _r in rows:
		var tz := z0 + _row
		if tz >= z1:
			return true
		for tx in range(floori(box.position.x), ceili(box.end.x)):
			if absf(at_center(tx, tz).y) <= band + 1.0:
				for o in CORNERS:
					at_vertex(tx + o.x, tz + o.y)
		_row += 1
	return _row >= z1 - z0


## Накопленная длина ломаной в каждой её точке.
static func path_lengths(line: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	for i in range(1, line.size()):
		out.append(out[i - 1] + line[i - 1].distance_to(line[i]))
	return out


static func path_bounds(line: PackedVector2Array) -> Rect2:
	var r := Rect2(line[0], Vector2.ZERO)
	for p in line:
		r = r.expand(p)
	return r


## Координаты точки p относительно ломаной: x — длина вдоль от начала до ближайшей точки, y — расстояние
## со знаком (> 0 — слева от направления, сторона «+»), (z, w) — нормаль в сторону «+». На изломе
## нормаль — средняя соседних отрезков, чтобы знак не прыгал у выпуклого угла. max_d — дальше линия
## не интересна: отрезки, чья рамка дальше max_d, отсекаются без расчёта; не нашлось — y = INF.
static func path_coords(line: PackedVector2Array, lens: PackedFloat32Array, p: Vector2, max_d: float = INF) -> Vector4:
	var best_d := INF
	var best := Vector4(0.0, INF, 0.0, 0.0)
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		if p.x < minf(a.x, b.x) - max_d or p.x > maxf(a.x, b.x) + max_d \
				or p.y < minf(a.y, b.y) - max_d or p.y > maxf(a.y, b.y) + max_d:
			continue
		var seg := b - a
		var seg_len := seg.length()
		if seg_len < 1e-6:
			continue
		var t := clampf((p - a).dot(seg) / (seg_len * seg_len), 0.0, 1.0)
		var q := a + seg * t
		var d := p.distance_to(q)
		if d < best_d:
			best_d = d
			var n := Vector2(-seg.y, seg.x) / seg_len
			if t <= 0.0 and i > 0:
				var prev := line[i] - line[i - 1]
				n = (n + Vector2(-prev.y, prev.x).normalized()).normalized()
			elif t >= 1.0 and i < line.size() - 2:
				var nxt := line[i + 2] - line[i + 1]
				n = (n + Vector2(-nxt.y, nxt.x).normalized()).normalized()
			var s := d * (1.0 if (p - q).dot(n) >= 0.0 else -1.0)
			best = Vector4(lens[i] + seg_len * t, s, n.x, n.y)
	return best
