class_name TerrainGenerator
extends RefCounted
## Генератор рельефа: seed + координаты чанка → ChunkData (GDD §3.4).
##
## Высота вершины — чистая функция f(x, z) от мировых координат, округлённая до яруса.
## Тайл берёт углы из вершин; если разброс углов ≥ 2, тайл уплощается до минимума — так
## на крутых местах появляются стенки (обрывы). Часть тайлов с разбросом 1 тоже уплощается
## (уступы). Все решения зависят только от seed и мировых координат, поэтому соседние чанки
## независимо получают одинаковые данные на общей границе — швов нет.
##
## Характер рельефа:
## - обрывы и уступы — в основном на скалах (горы, края ущелий, выходы скал); на грунте полки
##   соединены пологими склонами;
## - седловидные тайлы («песочные часы», противоположные углы равны) убираются подъёмом низкой
##   пары углов — решение по вершине зависит только от соседних вершин, поэтому без швов;
## - вода: у каждой области свой уровень, между областями с разными уровнями — пологая дамба;
##   на ровных полках — лужи вровень с краем. Вода нигде не «висит» над сухим соседом.
##
## Против ям без выхода (стенку вверх не проезжает никто):
## - сеть «проездов» — решётка коридоров, где рельеф пологий; любая замкнутая стена крупнее
##   ячейки решётки пересекает проезд;
## - внутри ячейки обрывы только на выпуклостях: во впадинах, на дне ущелий и в долинах между
##   гребнями переходы пологие. Остаток добивает TerrainRepair (заливка ям).

const VERTS := Grid.WINDOW + 1      ## вершин на сторону окна
const EXT := VERTS + 2              ## вершины окна + по одной с каждой стороны (для правки седловин)
const NO_PAD := -999                ## ярус-маркер: в блоке нет годной площадки
const NO_NEST := Vector2i(-999999, -999999)
const NO_PUDDLE := Vector4(0, 0, 0, -999)

var seed: int
var p: TerrainParams

var _n_coarse: FastNoiseLite
var _n_detail: FastNoiseLite
var _n_plateau: FastNoiseLite
var _n_ramp: FastNoiseLite
var _n_mountain: FastNoiseLite
var _n_ridge: FastNoiseLite
var _n_canyon: FastNoiseLite
var _n_rock: FastNoiseLite
var _n_ledge: FastNoiseLite
var _n_forest: FastNoiseLite
var _n_crater: FastNoiseLite
var _n_mineral: FastNoiseLite
var _n_warp: FastNoiseLite
var _n_water_warp: FastNoiseLite

var _pads: Dictionary[Vector2i, Vector3i] = {}       ## блок → (центр x, центр z, ярус), кэш
var _nests: Dictionary[Vector2i, Vector2i] = {}      ## блок → тайл гнезда (или NO_NEST), кэш
var _puddles: Dictionary[Vector2i, Vector4] = {}     ## ячейка → (центр x, центр z, радиус, ярус полки)


## Задача генерации одного чанка, выполняется порциями (по рядам) под бюджет времени.
class GenJob:
	extends RefCounted
	var data: ChunkData
	var ext := PackedInt32Array()       ## высоты вершин окна с запасом в одну вершину (EXT × EXT)
	var verts := PackedInt32Array()     ## после правки седловин (VERTS × VERTS)
	var pads: Array[Vector3i] = []      ## площадки рядом с окном — чтобы не искать их на каждый тайл
	var nests: Array[Vector2i] = []     ## гнёзда рядом с окном
	var puddles: Array[Vector4] = []    ## лужи рядом с окном
	var pad_blocks: Array[Vector2i] = []      ## что проверить на этапе подготовки
	var puddle_cells: Array[Vector2i] = []
	var stage: int = 0
	var row: int = 0


func _init(run_seed: int, params: TerrainParams) -> void:
	seed = run_seed
	p = params
	_n_coarse = _make_noise(1, p.coarse_freq, 1)
	_n_detail = _make_noise(2, p.detail_freq, 2)
	_n_plateau = _make_noise(3, p.plateau_freq, 1)
	_n_ramp = _make_noise(4, p.ramp_freq, 2)
	_n_mountain = _make_noise(5, p.mountain_freq, 2)
	_n_ridge = _make_noise(6, p.ridge_freq, 2)
	_n_canyon = _make_noise(7, p.canyon_freq, 1)
	_n_canyon.domain_warp_enabled = true
	_n_canyon.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_n_canyon.domain_warp_amplitude = p.canyon_warp_amp
	_n_canyon.domain_warp_frequency = p.canyon_freq * 3.0
	_n_rock = _make_noise(8, p.rock_freq, 2)
	_n_ledge = _make_noise(9, p.ledge_freq, 1)
	_n_forest = _make_noise(10, p.forest_freq, 2)
	_n_crater = _make_noise(11, p.crater_freq, 1)
	_n_mineral = _make_noise(12, p.mineral_freq, 2)
	_n_warp = _make_noise(13, p.avenue_warp_freq, 1)
	_n_water_warp = _make_noise(14, 1.0 / 150.0, 1)


## Полная генерация за один вызов (тесты, предзагрузка).
func generate(coord: Vector2i) -> ChunkData:
	var job := begin(coord)
	while not step(job, Time.get_ticks_usec() + 3_600_000_000):
		pass
	return job.data


func begin(coord: Vector2i) -> GenJob:
	var job := GenJob.new()
	job.data = ChunkData.new(coord)
	job.ext.resize(EXT * EXT)
	job.verts.resize(VERTS * VERTS)
	# Площадки и лужи считаются в step() (этап 0): поиск места под них — десятки проб высоты,
	# в begin() это ушло бы мимо бюджета кадра.
	var o := job.data.window_origin()
	var reach := maxi(p.pad_half + p.pad_clear_r, p.pad_half + 2 + ceili(p.pad_blend))
	var b0 := Vector2i(floori((o.x - reach) / float(p.pad_block)), floori((o.y - reach) / float(p.pad_block)))
	var b1 := Vector2i(floori((o.x + Grid.WINDOW + reach) / float(p.pad_block)), floori((o.y + Grid.WINDOW + reach) / float(p.pad_block)))
	for bz in range(b0.y, b1.y + 1):
		for bx in range(b0.x, b1.x + 1):
			job.pad_blocks.append(Vector2i(bx, bz))
	var c0 := Vector2i(floori((o.x - 8.0) / p.puddle_cell), floori((o.y - 8.0) / p.puddle_cell))
	var c1 := Vector2i(floori((o.x + Grid.WINDOW + 8.0) / p.puddle_cell), floori((o.y + Grid.WINDOW + 8.0) / p.puddle_cell))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			job.puddle_cells.append(Vector2i(cx, cz))
	return job


## Выполняет работу до дедлайна (Time.get_ticks_usec()). Возвращает true, когда чанк готов.
func step(job: GenJob, deadline_usec: int) -> bool:
	var origin := job.data.window_origin()
	while job.stage == 0:
		# Подготовка: площадки (сначала — лужи от них зависят) и лужи вокруг окна, по одной за шаг.
		if job.row < job.pad_blocks.size():
			var pad := pad_of_block(job.pad_blocks[job.row])
			if pad.z != NO_PAD:
				job.pads.append(pad)
			var nest := nest_of_block(job.pad_blocks[job.row])
			if nest != NO_NEST:
				job.nests.append(nest)
		else:
			var puddle := puddle_of_cell(job.puddle_cells[job.row - job.pad_blocks.size()])
			if puddle.w != NO_PUDDLE.w:
				job.puddles.append(puddle)
		job.row += 1
		if job.row >= job.pad_blocks.size() + job.puddle_cells.size():
			job.stage = 1
			job.row = 0
		if Time.get_ticks_usec() >= deadline_usec:
			return false
	while job.stage == 1:
		# Высоты вершин окна и по одной вершине за его краем.
		var ez := job.row
		for ex in EXT:
			var x := float(origin.x + ex - 1)
			var z := float(origin.y + ez - 1)
			var h := _blend_pads(job.pads, x, z, height_raw(x, z))
			job.ext[ez * EXT + ex] = roundi(_carve_puddles(job.puddles, x, z, h))
		job.row += 1
		if job.row >= EXT:
			job.stage = 2
			job.row = 0
		if Time.get_ticks_usec() >= deadline_usec:
			return false
	while job.stage == 2:
		for vx in VERTS:
			job.verts[job.row * VERTS + vx] = _fix_saddle_vertex(job.ext, vx + 1, job.row + 1)
		job.row += 1
		if job.row >= VERTS:
			job.stage = 3
			job.row = 0
		if Time.get_ticks_usec() >= deadline_usec:
			return false
	while job.stage == 3:
		for lx in Grid.WINDOW:
			_build_tile(job, lx, job.row, origin)
		job.row += 1
		if job.row >= Grid.WINDOW:
			job.stage = 4
			return true
		if Time.get_ticks_usec() >= deadline_usec:
			return false
	return true


## Высота вершины (ярусы, до округления) с учётом площадок челнока и луж.
func height_at(x: float, z: float) -> float:
	var h := _apply_pads(x, z, height_raw(x, z))
	var cell := Vector2i(floori(x / p.puddle_cell), floori(z / p.puddle_cell))
	var near: Array[Vector4] = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var puddle := puddle_of_cell(cell + Vector2i(dx, dz))
			if puddle.w != NO_PUDDLE.w:
				near.append(puddle)
	return _carve_puddles(near, x, z, h)


## Высота без площадок и луж: (база + горы) → одна ступенчатая функция → − ущелья → дамбы.
## Террасы считаются один раз по сумме: если ступенчатыми делать отдельно базу и горы, их ступени
## накладываются и превращают горы в лабиринт мелких стенок.
func height_raw(x: float, z: float) -> float:
	var avenue_d := _avenue_distance(x, z)
	var avenue := 1.0 - _smooth(p.avenue_width, p.avenue_width + p.avenue_fade, avenue_d)
	var detail := _n_detail.get_noise_2d(x, z)
	var canyon_raw := _canyon_t(x, z)
	# Ущелье мелеет к проезду на длинном участке, чтобы дно выходило наверх склоном, а не стенкой.
	var canyon := canyon_raw * _smooth(p.avenue_width, p.avenue_width + p.avenue_canyon_fade, avenue_d)
	var h := p.base_level + _n_coarse.get_noise_2d(x, z) * p.coarse_amp + detail * p.detail_amp
	# Пологость: зоны пандусов, впадины, проезды, дно ущелий.
	var gentle := maxf(maxf(_ramp_zone(x, z), _smooth(-0.02, -0.25, detail)), maxf(avenue, _smooth(0.0, 0.3, canyon)))
	var plateau := _smooth(-0.05, 0.25, _n_plateau.get_noise_2d(x, z))
	var step_h := lerpf(p.terrace_low, p.terrace_high, plateau)
	var mountain := _mountain_mask(x, z) * (1.0 - avenue)
	var rocky := _rockiness(mountain, canyon_raw, x, z) * (1.0 - avenue)

	if mountain > 0.0:
		var ridge := 1.0 - absf(_n_ridge.get_noise_2d(x, z))
		h += mountain * p.mountain_height * (0.5 + 0.5 * ridge * ridge)
		# В горах ступени по 2 яруса; обрывы только у самых гребней, ниже — пологие склоны.
		step_h = lerpf(step_h, 2.0, mountain)
		gentle = maxf(gentle, mountain * _smooth(0.8, 0.55, ridge))
	# Резкие ступени (обрывы) — на скалах; на грунте подъём между полками пологий.
	var w := lerpf(lerpf(p.step_soil_w, p.step_sharp_w, rocky), p.step_gentle_w, gentle)
	h = _terrace(h, step_h, w)

	if canyon > 0.0:
		# Края резкие, кроме зон пандусов: там стенка ущелья становится склоном.
		var shape := lerpf(clampf(canyon / 0.35, 0.0, 1.0), canyon, _ramp_zone(x, z))
		h -= p.canyon_depth * shape
	return _apply_dams(x, z, h)


## Ярус воды для тайла: уровень его области; в луже — уровень полки, если он выше.
func water_tier(tx: int, tz: int) -> int:
	var level := _region_level(_water_region_of(tx + 0.5, tz + 0.5))
	var cell := Vector2i(floori((tx + 0.5) / p.puddle_cell), floori((tz + 0.5) / p.puddle_cell))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var puddle := puddle_of_cell(cell + Vector2i(dx, dz))
			if puddle.w != NO_PUDDLE.w and Vector2(tx + 0.5 - puddle.x, tz + 0.5 - puddle.y).length() < puddle.z + 1.0:
				level = maxi(level, int(puddle.w))
	return level


## Лужа ячейки: (центр x, центр z, радиус, ярус полки) или NO_PUDDLE. Лужа ставится только на ровную
## полку выше воды области — иначе вода повисла бы над соседним тайлом.
func puddle_of_cell(cell: Vector2i) -> Vector4:
	if _puddles.has(cell):
		return _puddles[cell]
	var result := NO_PUDDLE
	if DetRng.unit(seed, cell.x, cell.y, 400) < p.puddle_chance:
		var r := lerpf(p.puddle_r_min, p.puddle_r_max, DetRng.unit(seed, cell.x, cell.y, 401))
		var margin := r + 3.0
		var span := p.puddle_cell - 2.0 * margin
		var cx := cell.x * p.puddle_cell + margin + DetRng.unit(seed, cell.x, cell.y, 402) * span
		var cz := cell.y * p.puddle_cell + margin + DetRng.unit(seed, cell.x, cell.y, 403) * span
		if _puddle_site_ok(cx, cz, r):
			result = Vector4(cx, cz, r, roundf(height_at_no_puddles(cx, cz)))
	_puddles[cell] = result
	return result


## Высота с площадками, без луж (проверка места под лужу).
func height_at_no_puddles(x: float, z: float) -> float:
	return _apply_pads(x, z, height_raw(x, z))


## Площадка челнока блока: (центр x, центр z, ярус). Площадка — тайлы центр ± pad_half.
func pad_of_block(block: Vector2i) -> Vector3i:
	if _pads.has(block):
		return _pads[block]
	var best := Vector3i(0, 0, NO_PAD)
	var best_score := INF
	var margin := p.pad_half + int(p.pad_blend) + 2
	var span := p.pad_block - 2 * margin
	for i in 12:
		var cx := block.x * p.pad_block + margin + DetRng.hash4(seed, block.x, block.y, 100 + i) % span
		var cz := block.y * p.pad_block + margin + DetRng.hash4(seed, block.x, block.y, 200 + i) % span
		var h := height_raw(cx + 0.5, cz + 0.5)
		var lo := h
		var hi := h
		for o: Vector2i in [Vector2i(-4, -4), Vector2i(4, -4), Vector2i(-4, 4), Vector2i(4, 4)]:
			var s := height_raw(cx + 0.5 + o.x, cz + 0.5 + o.y)
			lo = minf(lo, s)
			hi = maxf(hi, s)
		var water := _region_level(_water_region_of(cx + 0.5, cz + 0.5))
		if h < water + 1.5 or _canyon_t(cx + 0.5, cz + 0.5) > 0.0:
			continue   # в воде и в ущелье площадку не ставим
		var score := hi - lo
		if _mountain_mask(cx + 0.5, cz + 0.5) > 0.05:
			score += 20.0
		if score < best_score:
			best_score = score
			best = Vector3i(cx, cz, maxi(roundi(h), water + 1))
	_pads[block] = best
	return best


## Гнездо блока 2×2 чанка (GDD §3.4): в ущельях и озёрном крае, не в воде, не ближе nest_pad_dist
## к площадкам этого и соседних блоков. NO_NEST — в блоке гнезда нет.
func nest_of_block(block: Vector2i) -> Vector2i:
	if _nests.has(block):
		return _nests[block]
	var best := NO_NEST
	var margin := 6
	var span := p.pad_block - 2 * margin
	for i in 10:
		var cx := block.x * p.pad_block + margin + DetRng.hash4(seed, block.x, block.y, 400 + i) % span
		var cz := block.y * p.pad_block + margin + DetRng.hash4(seed, block.x, block.y, 500 + i) % span
		var x := cx + 0.5
		var z := cz + 0.5
		var h := height_raw(x, z)
		var water := _region_level(_water_region_of(x, z))
		if h < water + 1.0:
			continue
		var biome := _biome(x, z, roundi(h), water, _canyon_t(x, z), _mountain_mask(x, z))
		if biome != ChunkData.Biome.CANYON and biome != ChunkData.Biome.LAKESIDE:
			continue
		if _pad_near(Vector2(x, z), p.nest_pad_dist):
			continue
		best = Vector2i(cx, cz)
		break
	_nests[block] = best
	return best


## Гнёзда, чей блок может задеть прямоугольник [x0, x1] × [z0, z1].
func nests_in_rect(x0: int, z0: int, x1: int, z1: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var b0 := Vector2i(floori(x0 / float(p.pad_block)), floori(z0 / float(p.pad_block)))
	var b1 := Vector2i(floori(x1 / float(p.pad_block)), floori(z1 / float(p.pad_block)))
	for bz in range(b0.y, b1.y + 1):
		for bx in range(b0.x, b1.x + 1):
			var n := nest_of_block(Vector2i(bx, bz))
			if n != NO_NEST and n.x >= x0 and n.x <= x1 and n.y >= z0 and n.y <= z1:
				result.append(n)
	return result


func _pad_near(pos: Vector2, dist: float) -> bool:
	var block := Vector2i(floori(pos.x / float(p.pad_block)), floori(pos.y / float(p.pad_block)))
	for bz in range(block.y - 1, block.y + 2):
		for bx in range(block.x - 1, block.x + 2):
			var pad := pad_of_block(Vector2i(bx, bz))
			if pad.z != NO_PAD and pos.distance_to(Vector2(pad.x + 0.5, pad.y + 0.5)) < dist:
				return true
	return false


## Чебышёвское расстояние до ближайшего гнезда окна (большое — гнёзд рядом нет).
func _nest_distance(nests: Array[Vector2i], tx: int, tz: int) -> int:
	var best := 1 << 20
	for n in nests:
		best = mini(best, maxi(absi(tx - n.x), absi(tz - n.y)))
	return best


## Площадка, в прямоугольник которой (с запасом extra тайлов) попадает тайл, или null.
## Если годного места в блоке нет (всё под водой или в ущелье), площадки в блоке нет.
func pad_near_tile(tx: int, tz: int, extra: int = 0) -> Variant:
	var block := Vector2i(floori(tx / float(p.pad_block)), floori(tz / float(p.pad_block)))
	for bz in range(block.y - 1, block.y + 2):
		for bx in range(block.x - 1, block.x + 2):
			var pad := pad_of_block(Vector2i(bx, bz))
			if pad.z == NO_PAD:
				continue
			var r := p.pad_half + extra
			if absi(tx - pad.x) <= r and absi(tz - pad.y) <= r:
				return pad
	return null


## Вершина (ex, ez) в сетке EXT после правки седловин: если вершина — нижний угол седловидного
## тайла («песочные часы»: противоположные углы равны, пары разные), она поднимается на ярус,
## когда это не делает ни один из четырёх соседних тайлов круче яруса. Решение использует только
## вершины на расстоянии 1, поэтому одинаково во всех окнах (швов нет).
func _fix_saddle_vertex(ext: PackedInt32Array, ex: int, ez: int) -> int:
	var v := ext[ez * EXT + ex]
	var low_of_saddle := false
	for t: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(0, 0), Vector2i(-1, 0)]:
		var a := ext[(ez + t.y) * EXT + ex + t.x]
		var b := ext[(ez + t.y) * EXT + ex + t.x + 1]
		var c := ext[(ez + t.y + 1) * EXT + ex + t.x + 1]
		var d := ext[(ez + t.y + 1) * EXT + ex + t.x]
		if a == c and b == d and a != b and v == mini(a, b):
			low_of_saddle = true
			break
	if not low_of_saddle:
		return v
	for t: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(0, 0), Vector2i(-1, 0)]:
		var lo := v + 1
		var hi := v + 1
		for k: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
			var px := ex + t.x + k.x
			var pz := ez + t.y + k.y
			if px == ex and pz == ez:
				continue
			var u := ext[pz * EXT + px]
			lo = mini(lo, u)
			hi = maxi(hi, u)
		if hi - lo > 1:
			return v
	return v + 1


func _build_tile(job: GenJob, lx: int, lz: int, origin: Vector2i) -> void:
	var data := job.data
	var i := lz * Grid.WINDOW + lx
	var c0 := job.verts[lz * VERTS + lx]
	var c1 := job.verts[lz * VERTS + lx + 1]
	var c2 := job.verts[(lz + 1) * VERTS + lx + 1]
	var c3 := job.verts[(lz + 1) * VERTS + lx]
	var lo := mini(mini(c0, c1), mini(c2, c3))
	var hi := maxi(maxi(c0, c1), maxi(c2, c3))
	var tx := origin.x + lx
	var tz := origin.y + lz
	var cx := tx + 0.5
	var cz := tz + 0.5

	var is_pad := _near_pad(job.pads, tx, tz, 0)
	var water := _tile_water(job.puddles, tx, tz)
	var canyon_raw := _canyon_t(cx, cz)
	var mountain := _mountain_mask(cx, cz)
	var rocky := _rockiness(mountain, canyon_raw, cx, cz) * (1.0 - _avenue(cx, cz))
	var biome := _biome(cx, cz, lo, water, canyon_raw, mountain)

	# Крутой тайл уплощается до минимума — на его высоких рёбрах появляются стенки.
	# Тайл с разбросом 1 иногда тоже уплощается — уступ (на скалах часто, на грунте редко).
	if hi - lo >= 2 or (hi - lo == 1 and not is_pad and _is_ledge(cx, cz, rocky)):
		c0 = lo
		c1 = lo
		c2 = lo
		c3 = lo
	data.set_corner(i, 0, c0)
	data.set_corner(i, 1, c1)
	data.set_corner(i, 2, c2)
	data.set_corner(i, 3, c3)
	data.biome[i] = biome
	data.material[i] = _material(tx, tz, biome, lo, water, rocky)
	data.water_level[i] = water + Grid.HEIGHT_OFFSET if water > lo else 0
	data.flags[i] = ChunkData.FLAG_PAD if is_pad else 0
	var nest_d := _nest_distance(job.nests, tx, tz)
	if nest_d <= 1:
		data.flags[i] |= ChunkData.FLAG_NEST

	data.trees[i] = ChunkData.TREE_NONE
	if water <= lo and not _near_pad(job.pads, tx, tz, p.pad_clear_r) and nest_d > p.nest_clear_r:
		if DetRng.unit(seed, tx, tz, 300) < _tree_density(biome):
			data.trees[i] = 1 + DetRng.hash4(seed, tx, tz, 301) % 2
			data.tree_offset[i] = DetRng.hash4(seed, tx, tz, 302) & 0xFF


## Уровень воды тайла по заранее найденным лужам окна (горячий путь; иначе — water_tier).
func _tile_water(puddles: Array[Vector4], tx: int, tz: int) -> int:
	var level := _region_level(_water_region_of(tx + 0.5, tz + 0.5))
	for puddle in puddles:
		if Vector2(tx + 0.5 - puddle.x, tz + 0.5 - puddle.y).length() < puddle.z + 1.0:
			level = maxi(level, int(puddle.w))
	return level


func _near_pad(pads: Array[Vector3i], tx: int, tz: int, extra: int) -> bool:
	var r := p.pad_half + extra
	for pad in pads:
		if absi(tx - pad.x) <= r and absi(tz - pad.y) <= r:
			return true
	return false


func _biome(x: float, z: float, lowest: int, water: int, canyon_raw: float, mountain: float) -> int:
	if canyon_raw > 0.2:
		return ChunkData.Biome.CANYON
	if mountain > 0.15:
		return ChunkData.Biome.MOUNTAINS
	if lowest <= water:
		return ChunkData.Biome.LAKESIDE
	if _n_forest.get_noise_2d(x, z) > p.forest_threshold:
		return ChunkData.Biome.FOREST
	if _n_crater.get_noise_2d(x, z) > p.crater_threshold:
		return ChunkData.Biome.CRATERS
	if _n_plateau.get_noise_2d(x, z) > 0.1:
		return ChunkData.Biome.PLATEAU
	return ChunkData.Biome.PLAINS


func _is_ledge(x: float, z: float, rocky: float) -> bool:
	if _ramp_zone(x, z) > 0.0 or _avenue(x, z) > 0.0:
		return false   # в зонах пандусов и в проездах уступов нет, иначе путь наверх оборвётся
	return (_n_ledge.get_noise_2d(x, z) + 1.0) * 0.5 < lerpf(p.ledge_p_soil, p.ledge_p_rock, rocky)


func _material(tx: int, tz: int, biome: int, lowest: int, water: int, rocky: float) -> int:
	var mineral := _n_mineral.get_noise_2d(tx + 0.5, tz + 0.5)
	match biome:
		ChunkData.Biome.MOUNTAINS:
			return ChunkData.Mat.CRYSTAL if mineral > p.crystal_threshold else ChunkData.Mat.ROCK
		ChunkData.Biome.CANYON:
			return ChunkData.Mat.SAND if lowest <= water + 1 else ChunkData.Mat.ROCK
		ChunkData.Biome.LAKESIDE:
			return ChunkData.Mat.SAND
	# Выходы скал — камень: обрывы на них ожидаемы и читаются по цвету.
	if rocky > 0.5:
		return ChunkData.Mat.CRYSTAL if mineral > p.crystal_threshold + 0.1 else ChunkData.Mat.ROCK
	match biome:
		ChunkData.Biome.CRATERS:
			return ChunkData.Mat.CRYSTAL if mineral > p.crystal_threshold + 0.1 else ChunkData.Mat.SAND
		ChunkData.Biome.PLATEAU:
			return ChunkData.Mat.CRYSTAL if mineral > p.crystal_threshold + 0.15 else ChunkData.Mat.GROUND
	return ChunkData.Mat.GROUND


func _tree_density(biome: int) -> float:
	match biome:
		ChunkData.Biome.FOREST:
			return p.tree_density_forest
		ChunkData.Biome.LAKESIDE:
			return p.tree_density_lakeside
		ChunkData.Biome.PLAINS, ChunkData.Biome.PLATEAU:
			return p.tree_density_plain
		ChunkData.Biome.CRATERS:
			return 0.0
	return p.tree_density_rocky


## Скалистость 0..1: горы, края и дно ущелий, отдельные выходы скал.
func _rockiness(mountain: float, canyon_raw: float, x: float, z: float) -> float:
	var outcrop := _smooth(p.rock_threshold, p.rock_threshold + 0.15, _n_rock.get_noise_2d(x, z))
	return maxf(maxf(mountain, _smooth(0.0, 0.15, canyon_raw)), outcrop)


## Зона пандусов: 1 — переходы пологие, 0 — резкие.
func _ramp_zone(x: float, z: float) -> float:
	return _smooth(p.ramp_threshold - 0.08, p.ramp_threshold + 0.08, _n_ramp.get_noise_2d(x, z))


## Проезд: 1 — внутри коридора решётки, 0 — вне.
func _avenue(x: float, z: float) -> float:
	return 1.0 - _smooth(p.avenue_width, p.avenue_width + p.avenue_fade, _avenue_distance(x, z))


## Расстояние (в тайлах) до ближайшей линии решётки проездов. Решётка искривлена шумом.
func _avenue_distance(x: float, z: float) -> float:
	var wx := x + _n_warp.get_noise_2d(x, z) * p.avenue_warp
	var wz := z + _n_warp.get_noise_2d(z + 1000.0, x - 1000.0) * p.avenue_warp
	var half := p.avenue_spacing * 0.5
	return minf(absf(fposmod(wx + half, p.avenue_spacing) - half), absf(fposmod(wz + half, p.avenue_spacing) - half))


func _mountain_mask(x: float, z: float) -> float:
	return _smooth(p.mountain_threshold, p.mountain_threshold + 0.2, _n_mountain.get_noise_2d(x, z))


## Положение в полосе ущелья: 0 — вне или на краю, 1 — по центру.
func _canyon_t(x: float, z: float) -> float:
	var c := absf(_n_canyon.get_noise_2d(x, z))
	return 0.0 if c >= p.canyon_width else 1.0 - c / p.canyon_width


## Координаты точки в искривлённой решётке водных областей.
func _water_warped(x: float, z: float) -> Vector2:
	return Vector2(x + _n_water_warp.get_noise_2d(x, z) * p.water_region_warp,
			z + _n_water_warp.get_noise_2d(z - 3000.0, x + 3000.0) * p.water_region_warp)


func _water_region_of(x: float, z: float) -> Vector2i:
	var w := _water_warped(x, z)
	return Vector2i(floori(w.x / p.water_region), floori(w.y / p.water_region))


func _region_level(region: Vector2i) -> int:
	var spread := p.water_spread
	return roundi(p.water_level) + DetRng.hash4(seed, region.x, region.y, 500) % (2 * spread + 1) - spread


## Дамбы: у границы областей с разными уровнями рельеф поднимается выше обоих уровней и плавно
## (dam_slope ярусов на тайл) спускается вглубь области — вода разных уровней не соприкасается.
func _apply_dams(x: float, z: float, h: float) -> float:
	var w := _water_warped(x, z)
	var region := Vector2i(floori(w.x / p.water_region), floori(w.y / p.water_region))
	var level := _region_level(region)
	var fx := w.x - region.x * p.water_region
	var fz := w.y - region.y * p.water_region
	var borders: Array[Vector3] = [
		Vector3(-1, 0, fx), Vector3(1, 0, p.water_region - fx),
		Vector3(0, -1, fz), Vector3(0, 1, p.water_region - fz),
	]
	for b in borders:
		if b.z >= p.dam_width:
			continue
		var other := _region_level(region + Vector2i(int(b.x), int(b.y)))
		if other != level:
			h = maxf(h, maxi(level, other) + 1.0 - p.dam_slope * b.z)
	return h


## Место под лужу: ровная полка (все пробы в кольцах вокруг на одном ярусе), выше воды области,
## не у площадки челнока и не на скалах.
func _puddle_site_ok(cx: float, cz: float, r: float) -> bool:
	var shelf := height_at_no_puddles(cx, cz)
	var level := roundf(shelf)
	if absf(shelf - level) > 0.2 or level <= _region_level(_water_region_of(cx, cz)) + 1:
		return false
	if _rockiness(_mountain_mask(cx, cz), _canyon_t(cx, cz), cx, cz) > 0.3:
		return false
	for ring in [r, r + 1.0, r + 2.0]:
		for k in 12:
			var a := TAU * k / 12.0
			var s := height_at_no_puddles(cx + cos(a) * ring, cz + sin(a) * ring)
			if absf(s - level) > 0.2:
				return false
	return true


## Чаша лужи: внутри радиуса рельеф на ярус ниже полки.
func _carve_puddles(puddles: Array[Vector4], x: float, z: float, h: float) -> float:
	for puddle in puddles:
		if Vector2(x - puddle.x, z - puddle.y).length() < puddle.z:
			return puddle.w - 1.0
	return h


## То же по заранее найденному списку площадок окна (горячий путь генерации).
func _blend_pads(pads: Array[Vector3i], x: float, z: float, h: float) -> float:
	for pad in pads:
		var dx := maxf(maxf(pad.x - p.pad_half - x, x - (pad.x + p.pad_half + 1)), 0.0)
		var dz := maxf(maxf(pad.y - p.pad_half - z, z - (pad.y + p.pad_half + 1)), 0.0)
		var d := maxf(dx, dz)
		if d <= 0.0:
			return float(pad.z)
		if d < p.pad_blend:
			h = lerpf(float(pad.z), h, _smooth(0.0, p.pad_blend, d))
	return h


func _apply_pads(x: float, z: float, h: float) -> float:
	var reach := p.pad_half + 1 + p.pad_blend
	var b0x := floori((x - reach) / p.pad_block)
	var b1x := floori((x + reach) / p.pad_block)
	var b0z := floori((z - reach) / p.pad_block)
	var b1z := floori((z + reach) / p.pad_block)
	for bz in range(b0z, b1z + 1):
		for bx in range(b0x, b1x + 1):
			var pad := pad_of_block(Vector2i(bx, bz))
			if pad.z == NO_PAD:
				continue
			# Прямоугольник площадки в координатах вершин: [x − half, x + half + 1].
			var dx := maxf(maxf(pad.x - p.pad_half - x, x - (pad.x + p.pad_half + 1)), 0.0)
			var dz := maxf(maxf(pad.y - p.pad_half - z, z - (pad.y + p.pad_half + 1)), 0.0)
			var d := maxf(dx, dz)
			if d <= 0.0:
				return float(pad.z)
			if d < p.pad_blend:
				h = lerpf(float(pad.z), h, _smooth(0.0, p.pad_blend, d))
	return h


## Ступенчатая функция: плоские полки высотой step, подъём занимает долю w интервала.
static func _terrace(h: float, step_h: float, w: float) -> float:
	var k := h / step_h
	var fl := floorf(k)
	var s := clampf((k - fl - (1.0 - w)) / w, 0.0, 1.0)
	return (fl + s) * step_h


static func _smooth(from: float, to: float, x: float) -> float:
	var t := clampf((x - from) / (to - from), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _make_noise(stream: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = DetRng.hash4(seed, stream, 0) & 0x7FFFFFFF
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	if octaves > 1:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n
