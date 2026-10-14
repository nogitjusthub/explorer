class_name MapMemory
extends RefCounted
## Память карты мира (GDD §8): цвет тайлов всех чанков, что подгружались за забег, и туман войны — три уровня:
## темнота (радар туда не доставал); SCANNED — рельеф полутёмным (был в дальности радара); SEEN — в полный цвет
## (машина видела: в ясную погоду SEEN_R, в непогоду меньше). Картинка чанка — CHUNK×CHUNK RGB, пиксель на тайл;
## туман — отдельная картинка поверх (цвет фона карты с прозрачностью уровня): отметка закрашивает отрезки строк
## (fill_rect), а не пиксели по одному — дальность радара велика. Переживает выгрузку чанка; пересборка (правка
## рельефа) рисует цвет заново. Цвет — порциями по строкам в бюджете кадра (render_step), не в обработчике
## сигнала: в браузере чанк целиком — заметный кусок кадра.

const SEEN_R := 12.0                     ## в ясную погоду машина видит вокруг себя столько тайлов (кадр)
const SCANNED := 1
const SEEN := 2
const FOG_COLOR := Color(0.03, 0.025, 0.06)   ## фон карты: туман — он же
const FOG_A: Array[float] = [1.0, 0.6, 0.0]   ## непрозрачность тумана по уровню: темно, полутёмно, видно
const FOREST := Color(0.1, 0.27, 0.13)   ## стоящее дерево — тёмной зеленью поверх цвета тайла

var terrain: TerrainData

var _images: Dictionary[Vector2i, Image] = {}             ## цвет рельефа
var _fog: Dictionary[Vector2i, Image] = {}                ## туман войны поверх
var _state: Dictionary[Vector2i, PackedByteArray] = {}    ## чанк → CHUNK² байт: уровень тайла 0…SEEN
var _dirty: Dictionary[Vector2i, bool] = {}               ## картинки изменились — обновить текстуры
var _queue: Array[Vector2i] = []                          ## чанки к отрисовке, по порядку
var _queued: Dictionary[Vector2i, bool] = {}
var _row := 0                                             ## следующая строка первого чанка очереди
var _last: Dictionary[int, Array] = {}                    ## уровень → [центр-тайл, радиус] прошлой отметки


func _init(t: TerrainData) -> void:
	terrain = t


## Чанк собран или пересобран: нарисовать (заново) — в очередь.
func chunk_built(coord: Vector2i) -> void:
	if _queued.has(coord):
		if not _queue.is_empty() and _queue[0] == coord:
			_row = 0                          # уже рисуется — данные новые, с начала
		return
	_queue.append(coord)
	_queued[coord] = true


## Рисует строки очереди, пока не выйдет бюджет (мкс). Выгруженный до отрисовки чанк пропускается.
func render_step(budget_usec: int) -> void:
	var deadline := Time.get_ticks_usec() + budget_usec
	while not _queue.is_empty() and Time.get_ticks_usec() < deadline:
		var coord := _queue[0]
		var d: ChunkData = terrain.chunks.get(coord)
		if d == null:
			_pop()
			continue
		if not _images.has(coord):
			_images[coord] = Image.create(Grid.CHUNK, Grid.CHUNK, false, Image.FORMAT_RGB8)
		_render_row(coord, d, _row)
		_row += 1
		_dirty[coord] = true
		if _row >= Grid.CHUNK:
			_pop()


func pending() -> int:
	return _queue.size()


## Машина в pos (тайлы мира) видит radius тайлов: в полный цвет.
func mark_seen(pos: Vector2, radius: float = SEEN_R) -> void:
	_mark(pos, radius, SEEN)


## Радар машины в pos достаёт на radius тайлов: из темноты — полутёмным.
func mark_scanned(pos: Vector2, radius: float) -> void:
	_mark(pos, radius, SCANNED)


func level(tx: int, tz: int) -> int:
	var st: PackedByteArray = _state.get(Grid.chunk_of_tile(tx, tz), PackedByteArray())
	return 0 if st.is_empty() else st[_local(tx, tz)]


func is_seen(tx: int, tz: int) -> bool:
	return level(tx, tz) >= SEEN


func image(coord: Vector2i) -> Image:
	return _images.get(coord)


func fog(coord: Vector2i) -> Image:
	return _fog.get(coord)


## Чанки, чьи картинки (цвет или туман) изменились с прошлого вызова.
func take_dirty() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_dirty.keys())
	_dirty.clear()
	return out


## Отметка круга уровня lvl вокруг тайла машины. Повторно — только когда машина перешла на другой тайл или
## радиус вырос; тайлы прошлого круга того же уровня пропускаются (новые — только серп по краю).
func _mark(pos: Vector2, radius: float, lvl: int) -> void:
	var c := Vector2i(floori(pos.x), floori(pos.y))
	var prev: Array = _last.get(lvl, [Vector2i.ZERO, -1.0])
	var pc: Vector2i = prev[0]
	var pr: float = prev[1]
	if c == pc and radius <= pr + 0.5:
		return
	_last[lvl] = [c, radius]
	if radius < pr:
		pr = -1.0                             # круг сжался (гроза, туман) — прошлый не вычитаем, он шире
	var r := ceili(radius)
	var prr := ceili(pr) if pr >= 0.0 else -1
	for dz in range(-r, r + 1):
		var tz := c.y + dz
		var half := floori(sqrt(maxf(radius * radius - dz * dz, 0.0)))
		var x0 := c.x - half
		var x1 := c.x + half
		var pdz := tz - pc.y
		if prr < 0 or absi(pdz) > prr:
			_mark_run(tz, x0, x1, lvl)
			continue
		var ph := floori(sqrt(maxf(pr * pr - pdz * pdz, 0.0)))
		_mark_run(tz, x0, mini(x1, pc.x - ph - 1), lvl)
		_mark_run(tz, maxi(x0, pc.x + ph + 1), x1, lvl)


## Отрезок строки tz [x0, x1] — не ниже уровня lvl: туман над ним закрашивается отрезками подряд идущих тайлов.
func _mark_run(tz: int, x0: int, x1: int, lvl: int) -> void:
	var x := x0
	while x <= x1:
		var coord := Grid.chunk_of_tile(x, tz)
		var end := mini(x1, coord.x * Grid.CHUNK + Grid.CHUNK - 1)
		var st: PackedByteArray = _state.get(coord, PackedByteArray())
		if st.is_empty():
			st.resize(Grid.CHUNK * Grid.CHUNK)
		var img: Image = _fog.get(coord)
		if img == null:
			img = Image.create(Grid.CHUNK, Grid.CHUNK, false, Image.FORMAT_RGBA8)
			img.fill(Color(FOG_COLOR, FOG_A[0]))
			_fog[coord] = img
		var lz := posmod(tz, Grid.CHUNK)
		var col := Color(FOG_COLOR, FOG_A[lvl])
		var changed := false
		var run := -1                         # начало отрезка тайлов, поднятых до lvl
		for tx in range(x, end + 2):
			var lx := posmod(tx, Grid.CHUNK)
			var up := tx <= end and st[lz * Grid.CHUNK + lx] < lvl
			if up:
				st[lz * Grid.CHUNK + lx] = lvl
				if run < 0:
					run = lx
			elif run >= 0:
				img.fill_rect(Rect2i(run, lz, (lx if tx <= end else posmod(end, Grid.CHUNK) + 1) - run, 1), col)
				run = -1
				changed = true
		if changed:
			_state[coord] = st                # PackedByteArray из словаря — копия: вернуть изменённую
			_dirty[coord] = true
		x = end + 1


func _pop() -> void:
	_queued.erase(_queue.pop_front())
	_row = 0


func _render_row(coord: Vector2i, d: ChunkData, lz: int) -> void:
	var img := _images[coord]
	var tz := coord.y * Grid.CHUNK + lz
	for lx in Grid.CHUNK:
		var i := d.local_index(coord.x * Grid.CHUNK + lx, tz)
		var col := MapRender.tile_color(d, i)
		var tree := d.trees[i]
		if tree != ChunkData.TREE_NONE and not (tree & ChunkData.TREE_FELLED):
			col = col.lerp(FOREST, 0.55)
		img.set_pixel(lx, lz, col)


static func _local(tx: int, tz: int) -> int:
	return posmod(tz, Grid.CHUNK) * Grid.CHUNK + posmod(tx, Grid.CHUNK)
