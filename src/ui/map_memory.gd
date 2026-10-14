class_name MapMemory
extends RefCounted
## Память карты мира (GDD §8): цвет тайлов всех чанков, что подгружались за забег, и туман войны — какие тайлы
## машина видела (в радиусе видимости от пути: в ясную погоду SEEN_R, в тумане и пыли — меньше). Картинка чанка — CHUNK×CHUNK RGBA, пиксель на тайл: виденный — в полный
## цвет, остальной — с прозрачностью DIM_A (на тёмном фоне карты — полутёмный). Переживает выгрузку чанка;
## пересборка (правка рельефа) рисует его заново. Рисование — порциями по строкам в бюджете кадра (render_step),
## а не в обработчике сигнала: в браузере чанк целиком — заметный кусок кадра.

const SEEN_R := 12.0                     ## в ясную погоду машина видит вокруг себя столько тайлов (кадр)
const MARK_STEP := 1.0                   ## заново отмечать виденное — машина сдвинулась или видимость выросла на столько
const DIM_A := 0.4                       ## не виденное — полупрозрачным
const FOREST := Color(0.1, 0.27, 0.13)   ## стоящее дерево — тёмной зеленью поверх цвета тайла

var terrain: TerrainData

var _images: Dictionary[Vector2i, Image] = {}
var _seen: Dictionary[Vector2i, PackedByteArray] = {}     ## чанк → CHUNK² байт: 1 — тайл виден
var _dirty: Dictionary[Vector2i, bool] = {}               ## картинка изменилась — обновить текстуру
var _queue: Array[Vector2i] = []                          ## чанки к отрисовке, по порядку
var _queued: Dictionary[Vector2i, bool] = {}
var _row := 0                                             ## следующая строка первого чанка очереди
var _last_mark := Vector2.INF
var _last_r := 0.0


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
			_images[coord] = Image.create(Grid.CHUNK, Grid.CHUNK, false, Image.FORMAT_RGBA8)
		_render_row(coord, d, _row)
		_row += 1
		_dirty[coord] = true
		if _row >= Grid.CHUNK:
			_pop()


func pending() -> int:
	return _queue.size()


## Машина в pos (тайлы мира) видит radius тайлов: они — виденные. Заново — раз в MARK_STEP пути или когда
## видимость выросла (туман рассеялся).
func mark_seen(pos: Vector2, radius: float = SEEN_R) -> void:
	if pos.distance_to(_last_mark) < MARK_STEP and radius < _last_r + MARK_STEP:
		return
	_last_mark = pos
	_last_r = radius
	var r := ceili(radius)
	var c := Vector2i(floori(pos.x), floori(pos.y))
	for dz in range(-r, r + 1):
		var half := floori(sqrt(maxf(radius * radius - dz * dz, 0.0)))
		var tz := c.y + dz
		for tx in range(c.x - half, c.x + half + 1):
			_see(tx, tz)


func is_seen(tx: int, tz: int) -> bool:
	var seen: PackedByteArray = _seen.get(Grid.chunk_of_tile(tx, tz), PackedByteArray())
	return not seen.is_empty() and seen[_local(tx, tz)] == 1


func image(coord: Vector2i) -> Image:
	return _images.get(coord)


func coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_images.keys())
	return out


## Чанки, чьи картинки изменились с прошлого вызова.
func take_dirty() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_dirty.keys())
	_dirty.clear()
	return out


func _pop() -> void:
	_queued.erase(_queue.pop_front())
	_row = 0


func _render_row(coord: Vector2i, d: ChunkData, lz: int) -> void:
	var img := _images[coord]
	var seen: PackedByteArray = _seen.get(coord, PackedByteArray())
	var tz := coord.y * Grid.CHUNK + lz
	for lx in Grid.CHUNK:
		var i := d.local_index(coord.x * Grid.CHUNK + lx, tz)
		var col := MapRender.tile_color(d, i)
		var tree := d.trees[i]
		if tree != ChunkData.TREE_NONE and not (tree & ChunkData.TREE_FELLED):
			col = col.lerp(FOREST, 0.55)
		col.a = 1.0 if not seen.is_empty() and seen[lz * Grid.CHUNK + lx] == 1 else DIM_A
		img.set_pixel(lx, lz, col)


func _see(tx: int, tz: int) -> void:
	var coord := Grid.chunk_of_tile(tx, tz)
	var seen: PackedByteArray = _seen.get(coord, PackedByteArray())
	if seen.is_empty():
		seen.resize(Grid.CHUNK * Grid.CHUNK)
		_seen[coord] = seen
	var li := _local(tx, tz)
	if seen[li] == 1:
		return
	seen[li] = 1
	_seen[coord] = seen                       # PackedByteArray в словаре — копия: вернуть изменённую
	var img: Image = _images.get(coord)
	if img != null:
		var lx := li % Grid.CHUNK
		var lz := li / Grid.CHUNK
		var col := img.get_pixel(lx, lz)
		if col.a > 0.0:                       # строка уже нарисована
			col.a = 1.0
			img.set_pixel(lx, lz, col)
			_dirty[coord] = true


static func _local(tx: int, tz: int) -> int:
	return posmod(tz, Grid.CHUNK) * Grid.CHUNK + posmod(tx, Grid.CHUNK)
