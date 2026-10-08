class_name FlowField
extends RefCounted
## Поле расстояний до цели по сетке тайлов (поиск пути фауны, ARCHITECTURE §3.1): обход в ширину от
## тайла цели в квадратном окне радиусом R по рёбрам, проходимым для вида. Одно поле обслуживает
## всю стаю: каждый зверь шагает в соседний тайл с меньшим расстоянием. Строится задачей
## JobScheduler порциями под бюджет кадра; готовое поле заменяет прежнее.
##
## Проходимость:
## - HOPPER (скакуны) — только склоны: ни стенки вверх, ни обрыва вниз; в воду не заходят;
## - SHELLBACK (панцирник) — как танк: без стенок в обе стороны, вброд до 2 ярусов.

enum Mode { HOPPER, SHELLBACK }

const R := 30
const SIZE := 2 * R + 1
const UNREACHED := -1

var mode := Mode.HOPPER
var center := Vector2i.ZERO
var dist := PackedInt32Array()
var ready := false


## Задача построения: по готовности вызывает done(поле).
class BuildJob:
	extends Job
	var field: FlowField
	var query: TerrainQuery
	var done: Callable
	var _queue := PackedInt32Array()
	var _head := 0

	func start() -> void:
		field.dist.resize(SIZE * SIZE)
		field.dist.fill(UNREACHED)
		var c := R * SIZE + R
		field.dist[c] = 0
		_queue.append(c)

	func step(deadline_usec: int) -> bool:
		while _head < _queue.size():
			var idx := _queue[_head]
			_head += 1
			var lx := idx % SIZE
			var lz := idx / SIZE
			var t := field.center + Vector2i(lx - R, lz - R)
			var d := field.dist[idx]
			for dir in 4:
				var o := Grid.DIR_OFFSETS[dir]
				var nx := lx + o.x
				var nz := lz + o.y
				if nx < 0 or nz < 0 or nx >= SIZE or nz >= SIZE:
					continue
				var nidx := nz * SIZE + nx
				if field.dist[nidx] != UNREACHED:
					continue
				# Зверь пойдёт из соседа к нам — проверяем ребро в его сторону.
				if not FlowField.passable(query, field.mode, t + o, (dir + 2) % 4):
					continue
				field.dist[nidx] = d + 1
				_queue.append(nidx)
			if (_head & 31) == 0 and Time.get_ticks_usec() >= deadline_usec:
				return false
		return true

	func on_done() -> void:
		field.ready = true
		done.call(field)


## Задача на поле с центром в target; done(field) — когда готово.
static func build(query: TerrainQuery, field_mode: Mode, target: Vector2i, done: Callable) -> BuildJob:
	var f := FlowField.new()
	f.mode = field_mode
	f.center = target
	var job := BuildJob.new()
	job.field = f
	job.query = query
	job.done = done
	job.start()
	return job


## Ребро из тайла from в направлении dir проходимо для вида.
static func passable(q: TerrainQuery, field_mode: Mode, from: Vector2i, dir: int) -> bool:
	var to := from + Grid.DIR_OFFSETS[dir]
	if not q.is_loaded(to.x, to.y):
		return false
	if q.edge_rise(from.x, from.y, dir) > 0 or q.edge_drop(from.x, from.y, dir) > 0:
		return false
	var w := q.water_tier(to.x, to.y)
	if w == TerrainQuery.NO_WATER:
		return true
	if field_mode == Mode.HOPPER:
		return false
	return w - q.surface_tier(to.x + 0.5, to.y + 0.5) <= 2.0


## Расстояние (в тайлах пути) от тайла до цели; UNREACHED — не дойти или вне окна.
func distance(t: Vector2i) -> int:
	var l := t - center + Vector2i(R, R)
	if not ready or l.x < 0 or l.y < 0 or l.x >= SIZE or l.y >= SIZE:
		return UNREACHED
	return dist[l.y * SIZE + l.x]


## Следующий тайл пути к цели (соседний с меньшим расстоянием) или сам тайл, если пути нет.
func next_tile(q: TerrainQuery, t: Vector2i) -> Vector2i:
	var d := distance(t)
	if d <= 0:
		return t
	for dir in 4:
		var n := t + Grid.DIR_OFFSETS[dir]
		var nd := distance(n)
		if nd != UNREACHED and nd < d and passable(q, mode, t, dir):
			return n
	return t
