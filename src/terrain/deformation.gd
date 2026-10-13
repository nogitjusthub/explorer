class_name Deformation
extends RefCounted
## Деформации рельефа (GDD §3.5) поверх загруженных чанков: воронка, борозда, разлом.
## Работают по углам тайлов; результат пишется через TerrainData.write_tile — во все окна чанков,
## в DiffStore (правка переживает выгрузку) и в dirty-секции (меши пересоберёт стример).
##
## - Воронка и борозда — без стенок: общие вершины опускаются вместе, затем соседние углы
##   релаксируют, пока разница внутри каждого тайла не станет ≤ 1. Получаются чаши из склонов.
## - Разлом — единственная операция со стенками: полоса тайлов по одну сторону линии поднимается,
##   по другую опускается, к краям полосы — плавный спад. Каждые RAMP_EVERY тайлов вдоль линии
##   остаётся пандус шириной RAMP_WIDTH — стенки там нет.
## - Площадки (FLAG_PAD) и тайлы незагруженных чанков не меняются; вершины на их границе неподвижны,
##   соседи релаксируют к их краю.
## - Вода: тайл, поднятый над своей водой целиком, осушается; сухой тайл, опустившийся ниже уровня
##   соседней воды, затапливается (волна идёт дальше по таким же тайлам, но не дальше FLOOD_LIMIT).
## - Временный подъём (вал червя) возвращается по записям исходных высот; угол тайла незагруженного
##   чанка вернуть нельзя — запись уходит в TerrainData.pending_restores и возвращается, когда чанк
##   загрузится снова (restore_pending из WorldStreamer).

const LOWER := -1
const RAISE := 1
const RAMP_EVERY := 5
const RAMP_WIDTH := 2
const END_TAPER := 3.0              ## тайлов: к концам разлома сдвиг сходит на нет
const FLOOD_LIMIT := 400
const RELAX_LIMIT := 20000
const DIRTY_WATER := 1 << 4

## Тайлы вокруг вершины: (dx, dz, угол) — у вершины (vx, vz) это NW-угол тайла (vx, vz) и т. д.
const VERTEX_TILES: Array[Vector3i] = [Vector3i(-1, -1, 2), Vector3i(0, -1, 3), Vector3i(-1, 0, 1), Vector3i(0, 0, 0)]
const CORNER_OFFSETS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]

## Тайлов с разбросом углов ≥ 2, оставшихся после релаксации (за всё время; тесты сбрасывают в 0).
## Не ноль — релаксация упёрлась в неподвижные вершины с обеих сторон или в RELAX_LIMIT.
static var relax_leftovers := 0


## Рабочая копия углов и воды затронутых тайлов.
class Work:
	extends RefCounted
	var terrain: TerrainData
	var cur: Dictionary[int, PackedInt32Array] = {}
	var orig: Dictionary[int, PackedInt32Array] = {}
	var water: Dictionary[int, int] = {}          ## байт уровня воды (0 — нет)
	var orig_water: Dictionary[int, int] = {}
	var locked: Dictionary[int, bool] = {}

	func _init(t: TerrainData) -> void:
		terrain = t

	## Тайл в работе (загружается по требованию). false — неподвижен: площадка или не загружен.
	func load_tile(tx: int, tz: int) -> bool:
		var k := DiffStore.key(tx, tz)
		if cur.has(k):
			return true
		if locked.has(k):
			return false
		var d := terrain.owner_of(tx, tz)
		if d == null:
			locked[k] = true
			return false
		var i := d.local_index(tx, tz)
		if (d.flags[i] & ChunkData.FLAG_PAD) != 0:
			locked[k] = true
			return false
		var c := PackedInt32Array([d.get_corner(i, 0), d.get_corner(i, 1), d.get_corner(i, 2), d.get_corner(i, 3)])
		cur[k] = c
		orig[k] = c.duplicate()
		water[k] = d.water_level[i]
		orig_water[k] = d.water_level[i]
		return true

	func corner(tx: int, tz: int, c: int) -> int:
		return cur[DiffStore.key(tx, tz)][c]

	func set_corner(tx: int, tz: int, c: int, v: int) -> void:
		var k := DiffStore.key(tx, tz)
		var arr: PackedInt32Array = cur[k]
		arr[c] = v
		cur[k] = arr

	## Вершина неподвижна, если её делит хоть один неподвижный тайл.
	func vertex_fixed(v: Vector2i) -> bool:
		for o in VERTEX_TILES:
			if not load_tile(v.x + o.x, v.y + o.y):
				return true
		return false

	## Уровень воды соседа (байт) — из работы или из рельефа; 0 — нет воды или не загружен.
	func water_at(tx: int, tz: int) -> int:
		var k := DiffStore.key(tx, tz)
		if water.has(k):
			return water[k]
		var d := terrain.owner_of(tx, tz)
		return 0 if d == null else d.water_level[d.local_index(tx, tz)]


## Воронка: вершины в радиусе от центра опускаются на depth, затем релаксация. Возвращает ключи
## изменённых тайлов.
static func crater(terrain: TerrainData, center: Vector2, radius: float, depth: int) -> PackedInt64Array:
	var w := Work.new(terrain)
	var queue: Array[Vector3i] = []
	var r := ceili(radius) + 1
	for vz in range(floori(center.y) - r, floori(center.y) + r + 2):
		for vx in range(floori(center.x) - r, floori(center.x) + r + 2):
			if Vector2(vx, vz).distance_to(center) <= radius:
				_shift_vertex(w, Vector2i(vx, vz), -depth, LOWER, queue)
	_relax(w, queue)
	return _commit(w)


## Борозда вдоль отрезка: вершины ближе half_width к отрезку опускаются на ярус. На скалах
## (материал ROCK у любого тайла вокруг вершины) следа не остаётся. done — вершины, уже опущенные этим
## же источником (смерч): их не трогаем, иначе медленный смерч выкопал бы каньон. Вершина попадает
## в done, только когда действительно сдвинулась: неподвижную (сосед не загружен) возьмёт следующий проход.
## height — сдвиг вершин: −1 — борозда (смерч), +1 — вал (червь под песком).
static func furrow(terrain: TerrainData, from: Vector2, to: Vector2, half_width: float, done: Dictionary = {},
		height: int = -1) -> PackedInt64Array:
	var w := Work.new(terrain)
	var queue: Array[Vector3i] = []
	var lo := Vector2i(floori(minf(from.x, to.x) - half_width) - 1, floori(minf(from.y, to.y) - half_width) - 1)
	var hi := Vector2i(ceili(maxf(from.x, to.x) + half_width) + 1, ceili(maxf(from.y, to.y) + half_width) + 1)
	for vz in range(lo.y, hi.y + 1):
		for vx in range(lo.x, hi.x + 1):
			var p := Vector2(vx, vz)
			if Geometry2D.get_closest_point_to_segment(p, from, to).distance_to(p) > half_width:
				continue
			var v := Vector2i(vx, vz)
			if done.has(v) or _vertex_on_rock(terrain, v):
				continue
			if _shift_vertex(w, v, height, LOWER if height < 0 else RAISE, queue):
				done[v] = true
	_relax(w, queue)
	return _commit(w)


## Вершины ближе half_width к отрезку from–to.
static func vertices_near_segment(from: Vector2, to: Vector2, half_width: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var lo := Vector2i(floori(minf(from.x, to.x) - half_width) - 1, floori(minf(from.y, to.y) - half_width) - 1)
	var hi := Vector2i(ceili(maxf(from.x, to.x) + half_width) + 1, ceili(maxf(from.y, to.y) + half_width) + 1)
	for vz in range(lo.y, hi.y + 1):
		for vx in range(lo.x, hi.x + 1):
			var p := Vector2(vx, vz)
			if Geometry2D.get_closest_point_to_segment(p, from, to).distance_to(p) <= half_width:
				result.append(Vector2i(vx, vz))
	return result


## Временный подъём (вал червя): вершины поднимаются на ярус, релаксация поднимает соседей; исходные
## высоты всех изменённых углов запоминаются в originals (Vector3i(tx, tz, угол) → ярус). Вершины, у
## которых угол уже записан (здесь или в отложенных возвратах), не трогаем — вал не растёт выше яруса.
static func raise_vertices(terrain: TerrainData, verts: Array[Vector2i], originals: Dictionary) -> PackedInt64Array:
	var w := Work.new(terrain)
	var queue: Array[Vector3i] = []
	for v in verts:
		if _vertex_recorded(v, originals) or _vertex_recorded(v, terrain.pending_restores):
			continue
		_shift_vertex(w, v, 1, RAISE, queue)
	_relax(w, queue)
	for k in w.cur:
		var c := w.cur[k]
		var o := w.orig[k]
		var t := DiffStore.key_tile(k)
		for ci in 4:
			if c[ci] != o[ci]:
				var key := Vector3i(t.x, t.y, ci)
				if not originals.has(key):
					originals[key] = o[ci]
	return _commit(w)


## Возврат временного подъёма: у вершин из verts углы получают исходные высоты из originals (и
## забываются), соседи релаксируют вниз — без стенок, не ниже исходного рельефа.
## Вершина возвращается целиком или никак: если хоть один её записанный тайл в незагруженном чанке,
## все её записи уходят в terrain.pending_restores (и из originals) — их вернёт restore_pending, когда
## чанк загрузится снова. Иначе подъём остался бы в DiffStore навсегда, а на шве — стенка.
static func restore_vertices(terrain: TerrainData, verts: Array[Vector2i], originals: Dictionary) -> PackedInt64Array:
	var w := Work.new(terrain)
	var queue: Array[Vector3i] = []
	var pending := is_same(originals, terrain.pending_restores)
	var keys: Array[Vector3i] = []
	for v in verts:
		keys.clear()
		var ready := true
		for o in VERTEX_TILES:
			var key := Vector3i(v.x + o.x, v.y + o.y, o.z)
			if originals.has(key):
				keys.append(key)
				if not terrain.is_loaded(key.x, key.y):
					ready = false
		if not ready:
			if not pending:
				for key in keys:
					terrain.pending_restores[key] = originals[key]
					originals.erase(key)
			continue
		for key in keys:
			var target: int = originals[key]
			originals.erase(key)
			if not w.load_tile(key.x, key.y):
				continue            # площадка: подъём её не трогает, записи у неё не бывает
			w.set_corner(key.x, key.y, key.z, target)
			queue.append(Vector3i(key.x, key.y, LOWER))
	if queue.is_empty():
		return PackedInt64Array()
	_relax(w, queue)
	return _commit(w)


## Отложенные возвраты подъёмов (terrain.pending_restores): возвращает вершины, чьи тайлы снова
## загружены. Зовётся после загрузки чанка; пока записей нет — ничего не стоит.
static func restore_pending(terrain: TerrainData) -> PackedInt64Array:
	if terrain.pending_restores.is_empty():
		return PackedInt64Array()
	var verts: Array[Vector2i] = []
	var seen := {}
	for key: Vector3i in terrain.pending_restores:
		var v := recorded_vertex(key)
		if not seen.has(v):
			seen[v] = true
			verts.append(v)
	return restore_vertices(terrain, verts, terrain.pending_restores)


## Вершина записанного угла (обратное к VERTEX_TILES).
static func recorded_vertex(key: Vector3i) -> Vector2i:
	return Vector2i(key.x, key.y) + CORNER_OFFSETS[key.z]


static func _vertex_recorded(v: Vector2i, originals: Dictionary) -> bool:
	for o in VERTEX_TILES:
		if originals.has(Vector3i(v.x + o.x, v.y + o.y, o.z)):
			return true
	return false


## Разлом длиной length вдоль линии из вершины start (по x, если along_x, иначе по z).
## Сторона «+» (тайлы с большей координатой поперёк линии) поднимается на up, сторона «−»
## опускается на down. Возвращает ключи изменённых тайлов.
static func fault(terrain: TerrainData, start: Vector2i, along_x: bool, length: int, up: int, down: int) -> PackedInt64Array:
	var w := Work.new(terrain)
	var queue: Array[Vector3i] = []
	var band := maxi(up, down) + 4
	for a in range(-1, length + 1):
		for p in range(-band, band):
			var tile := start + (Vector2i(a, p) if along_x else Vector2i(p, a))
			if not w.load_tile(tile.x, tile.y):
				continue
			var plus := p >= 0
			var ramp := posmod(a, RAMP_EVERY) >= 2 and posmod(a, RAMP_EVERY) < 2 + RAMP_WIDTH
			var moved := false
			for c in 4:
				var v := tile + CORNER_OFFSETS[c]
				var va := (v.x - start.x) if along_x else (v.y - start.y)
				var vs := (v.y - start.y) if along_x else (v.x - start.x)
				var delta := fault_delta(va, vs, plus, ramp, length, up, down)
				if delta == 0 or w.vertex_fixed(v):
					continue
				w.set_corner(tile.x, tile.y, c, w.corner(tile.x, tile.y, c) + delta)
				moved = true
			if moved:
				queue.append(Vector3i(tile.x, tile.y, RAISE if plus else LOWER))
	_relax(w, queue)
	return _commit(w)


## Разлом по ломаной path (мировые точки): то же, что fault, но линия — любая кривая (дуга,
## полумесяц, зигзаг). Сторона тайла — по знаку расстояния от его центра до линии; стенка ложится
## по рёбрам тайлов вдоль кривой «лесенкой». Пандус — каждые ramp_every тайлов вдоль линии.
## coords — координаты точек относительно линии (FaultLine): можно посчитать заранее, пока идёт
## телеграф; чего там нет — досчитается здесь.
static func fault_path(terrain: TerrainData, path: PackedVector2Array, up: int, down: int,
		ramp_every: int = RAMP_EVERY, coords: FaultLine = null) -> PackedInt64Array:
	if coords == null:
		coords = FaultLine.new(path, up, down)
	var w := Work.new(terrain)
	var queue: Array[Vector3i] = []
	var total := coords.total
	var box := coords.box
	for tz in range(floori(box.position.y), ceili(box.end.y)):
		for tx in range(floori(box.position.x), ceili(box.end.x)):
			var cc := coords.at_center(tx, tz)
			if absf(cc.y) > coords.band + 1.0 or not w.load_tile(tx, tz):
				continue
			var plus := cc.y >= 0.0
			var ia := floori(cc.x)
			var ramp := ramp_every > 0 and posmod(ia, ramp_every) >= 2 and posmod(ia, ramp_every) < 2 + RAMP_WIDTH
			var moved := false
			for c in 4:
				var v := Vector2i(tx, tz) + CORNER_OFFSETS[c]
				var av := coords.at_vertex(v.x, v.y)
				var delta := fault_delta(av.x, av.y, plus, ramp, total, up, down)
				if delta == 0 or w.vertex_fixed(v):
					continue
				w.set_corner(tx, tz, c, w.corner(tx, tz, c) + delta)
				moved = true
			if moved:
				queue.append(Vector3i(tx, tz, RAISE if plus else LOWER))
	_relax(w, queue)
	return _commit(w)


## Свойство грунта (неровный / зыбучий) на тайлах: россыпь после землетрясения, молнии, смерча на скалах.
## Вода, площадки и гнёзда не меняются. Пишется через write_tile — переживает выгрузку, меш пересоберётся.
static func mark_ground(terrain: TerrainData, tiles: Array[Vector2i], flag: int) -> void:
	for t in tiles:
		var d := terrain.owner_of(t.x, t.y)
		if d == null:
			continue
		var i := d.local_index(t.x, t.y)
		if d.water_level[i] != 0 or (d.flags[i] & (ChunkData.FLAG_PAD | ChunkData.FLAG_NEST)) != 0:
			continue
		var r := d.read_record(i)
		var f := (r[7] & ~ChunkData.GROUND_FLAGS) | flag
		if f == r[7]:
			continue
		r[7] = f
		terrain.write_tile(t.x, t.y, r, true, false)


## Сдвиг вершины разлома: va — вдоль линии (0…length), vs — поперёк (0 — на линии, > 0 — сторона «+»).
## У вершины на линии сдвиг зависит от стороны тайла — так получается стенка; на пандусе — нет.
static func fault_delta(va: float, vs: float, plus: bool, ramp: bool, length: float, up: int, down: int) -> int:
	var endf := clampf(minf(va, length - va) / END_TAPER, 0.0, 1.0)
	if endf <= 0.0:
		return 0
	var s := vs
	var step_up := up * clampf(1.0 - (s - 2.0) / (up + 1.0), 0.0, 1.0)
	var step_down := -down * clampf(1.0 - (-s - 2.0) / (down + 1.0), 0.0, 1.0)
	var v: float
	if ramp:
		var r := clampf(s, -down, up)    # пандус: ярус на тайл через линию
		v = minf(r, step_up) if s >= 0.0 else maxf(r, step_down)
	else:
		v = step_up if plus else step_down
	return roundi(v * endf)


static func _vertex_on_rock(terrain: TerrainData, v: Vector2i) -> bool:
	for o in VERTEX_TILES:
		var d := terrain.owner_of(v.x + o.x, v.y + o.y)
		if d != null and d.material[d.local_index(v.x + o.x, v.y + o.y)] == ChunkData.Mat.ROCK:
			return true
	return false


## Сдвиг общей вершины у всех подвижных тайлов вокруг неё (поверхность остаётся непрерывной).
## false — вершина неподвижна (площадка или незагруженный сосед), ничего не сдвинуто.
static func _shift_vertex(w: Work, v: Vector2i, delta: int, mode: int, queue: Array[Vector3i]) -> bool:
	if w.vertex_fixed(v):
		return false
	for o in VERTEX_TILES:
		var tx := v.x + o.x
		var tz := v.y + o.y
		w.set_corner(tx, tz, o.z, w.corner(tx, tz, o.z) + delta)
		queue.append(Vector3i(tx, tz, mode))
	return true


## Релаксация до Δ ≤ 1 внутри каждого тайла. LOWER — опускаем высокие углы, RAISE — поднимаем
## низкие; неподвижную вершину не трогаем, тогда двигаем другую сторону. Если неподвижные вершины
## есть с обеих сторон — углы сводятся к ним (_relax_to_fixed). Сдвиг угла переносится на соседей,
## у которых в этой вершине та же высота (непрерывная поверхность); стенки остаются стенками.
static func _relax(w: Work, queue: Array[Vector3i]) -> void:
	var guard := 0
	while not queue.is_empty() and guard < RELAX_LIMIT:
		guard += 1
		var item: Vector3i = queue.pop_back()
		if not w.load_tile(item.x, item.y):
			continue
		var c: PackedInt32Array = w.cur[DiffStore.key(item.x, item.y)]
		var lo := mini(mini(c[0], c[1]), mini(c[2], c[3]))
		var hi := maxi(maxi(c[0], c[1]), maxi(c[2], c[3]))
		if hi - lo <= 1:
			continue
		var mode := item.z
		var moved := false
		for attempt in 2:
			var target := lo + 1 if mode == LOWER else hi - 1
			var blocked := false
			for ci in 4:
				var off := c[ci] > target if mode == LOWER else c[ci] < target
				if off and w.vertex_fixed(Vector2i(item.x, item.y) + CORNER_OFFSETS[ci]):
					blocked = true
			if blocked:
				mode = -mode
				continue
			for ci in 4:
				var value := w.corner(item.x, item.y, ci)
				var off := value > target if mode == LOWER else value < target
				if off:
					_move_corner(w, Vector2i(item.x, item.y), ci, target, mode, queue)
			moved = true
			break
		if not moved:
			_relax_to_fixed(w, Vector2i(item.x, item.y), item.z, queue)


## Обе попытки упёрлись в неподвижные вершины (площадка, край загруженного) — высокие с одной стороны,
## низкие с другой. Неподвижные углы не менялись, их разброс ≤ 1, поэтому есть окно [a, a + 1], которое
## их вмещает (при LOWER — нижнее из возможных, при RAISE — верхнее): подвижные углы выше окна
## опускаются в него, ниже — поднимаются.
static func _relax_to_fixed(w: Work, tile: Vector2i, mode: int, queue: Array[Vector3i]) -> void:
	var f_lo := 1 << 20
	var f_hi := -(1 << 20)
	for ci in 4:
		if w.vertex_fixed(tile + CORNER_OFFSETS[ci]):
			var value := w.corner(tile.x, tile.y, ci)
			f_lo = mini(f_lo, value)
			f_hi = maxi(f_hi, value)
	if f_hi - f_lo > 1:
		return      # неподвижные углы сами круче яруса — поправить нечем (учтёт relax_leftovers)
	var a := f_hi - 1 if mode == LOWER else f_lo
	for ci in 4:
		var value := w.corner(tile.x, tile.y, ci)
		if value > a + 1:
			_move_corner(w, tile, ci, a + 1, LOWER, queue)
		elif value < a:
			_move_corner(w, tile, ci, a, RAISE, queue)


static func _move_corner(w: Work, tile: Vector2i, ci: int, target: int, mode: int, queue: Array[Vector3i]) -> void:
	var v := tile + CORNER_OFFSETS[ci]
	var old := w.corner(tile.x, tile.y, ci)
	for o in VERTEX_TILES:
		var t := Vector2i(v.x + o.x, v.y + o.y)
		if not w.load_tile(t.x, t.y):
			continue
		if t == tile:
			w.set_corner(t.x, t.y, o.z, target)
		elif w.corner(t.x, t.y, o.z) == old:
			w.set_corner(t.x, t.y, o.z, target)
			queue.append(Vector3i(t.x, t.y, mode))


## Вода после сдвига: осушение поднятых, затопление опустившихся ниже соседней воды.
static func _fix_water(w: Work) -> void:
	var changed: Array[int] = []
	for k in w.cur:
		if w.cur[k] != w.orig[k]:
			changed.append(k)
	for k in changed:
		var level := w.water[k]
		if level != 0:
			var c := w.cur[k]
			if mini(mini(c[0], c[1]), mini(c[2], c[3])) + Grid.HEIGHT_OFFSET >= level:
				w.water[k] = 0
	var queue := changed.duplicate()
	var flooded := 0
	while not queue.is_empty() and flooded < FLOOD_LIMIT:
		var k: int = queue.pop_back()
		if w.water[k] != 0:
			continue
		var t := DiffStore.key_tile(k)
		var c := w.cur[k]
		var lo := mini(mini(c[0], c[1]), mini(c[2], c[3])) + Grid.HEIGHT_OFFSET
		for o in Grid.DIR_OFFSETS:
			var level := w.water_at(t.x + o.x, t.y + o.y)
			if level != 0 and lo < level:
				w.water[k] = level
				flooded += 1
				for o2 in Grid.DIR_OFFSETS:
					var n := t + o2
					if w.load_tile(n.x, n.y) and w.water[DiffStore.key(n.x, n.y)] == 0:
						queue.append(DiffStore.key(n.x, n.y))
				break


static func _commit(w: Work) -> PackedInt64Array:
	_fix_water(w)
	var changed := PackedInt64Array()
	for k in w.cur:
		var c := w.cur[k]
		if c == w.orig[k] and w.water[k] == w.orig_water[k]:
			continue
		if maxi(maxi(c[0], c[1]), maxi(c[2], c[3])) - mini(mini(c[0], c[1]), mini(c[2], c[3])) > 1:
			relax_leftovers += 1
		var t := DiffStore.key_tile(k)
		var d := w.terrain.owner_of(t.x, t.y)
		var record := d.read_record(d.local_index(t.x, t.y))
		for ci in 4:
			record[ci] = c[ci] + Grid.HEIGHT_OFFSET
		record[5] = w.water[k]
		w.terrain.write_tile(t.x, t.y, record, true, record[6] != 0)
		if record[5] != 0 or w.orig_water[k] != 0:
			w.terrain.mark_dirty(t.x, t.y, DIRTY_WATER)
		changed.append(k)
	return changed
