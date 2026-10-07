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
## Против ям без выхода (стенку вверх не проезжает никто):
## - сеть «проездов» — решётка коридоров, где рельеф пологий; любая замкнутая стена крупнее
##   ячейки решётки пересекает проезд;
## - внутри ячейки обрывы только на выпуклостях: во впадинах, на дне ущелий и в долинах между
##   гребнями переходы пологие. Остаток проверяется тестом связности.

const VERTS := Grid.WINDOW + 1      ## вершин на сторону окна
const NO_PAD := -999                ## ярус-маркер: в блоке нет годной площадки

var seed: int
var p: TerrainParams

var _n_coarse: FastNoiseLite
var _n_detail: FastNoiseLite
var _n_plateau: FastNoiseLite
var _n_ramp: FastNoiseLite
var _n_mountain: FastNoiseLite
var _n_ridge: FastNoiseLite
var _n_canyon: FastNoiseLite
var _n_water: FastNoiseLite
var _n_ledge: FastNoiseLite
var _n_forest: FastNoiseLite
var _n_crater: FastNoiseLite
var _n_mineral: FastNoiseLite
var _n_warp: FastNoiseLite

var _pads: Dictionary[Vector2i, Vector3i] = {}   ## блок → (центр x, центр z, ярус), кэш


## Задача генерации одного чанка, выполняется порциями (по рядам) под бюджет времени.
class GenJob:
	extends RefCounted
	var data: ChunkData
	var verts := PackedInt32Array()
	var pads: Array[Vector3i] = []      ## площадки рядом с окном — чтобы не искать их на каждый тайл
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
	_n_water = _make_noise(8, p.water_freq, 1)
	_n_ledge = _make_noise(9, p.ledge_freq, 1)
	_n_forest = _make_noise(10, p.forest_freq, 2)
	_n_crater = _make_noise(11, p.crater_freq, 1)
	_n_mineral = _make_noise(12, p.mineral_freq, 2)
	_n_warp = _make_noise(13, p.avenue_warp_freq, 1)


## Полная генерация за один вызов (тесты, предзагрузка).
func generate(coord: Vector2i) -> ChunkData:
	var job := begin(coord)
	while not step(job, Time.get_ticks_usec() + 3_600_000_000):
		pass
	return job.data


func begin(coord: Vector2i) -> GenJob:
	var job := GenJob.new()
	job.data = ChunkData.new(coord)
	job.verts.resize(VERTS * VERTS)
	var o := job.data.window_origin()
	var reach := maxi(p.pad_half + p.pad_clear_r, p.pad_half + 2 + ceili(p.pad_blend))
	var b0 := Vector2i(floori((o.x - reach) / float(p.pad_block)), floori((o.y - reach) / float(p.pad_block)))
	var b1 := Vector2i(floori((o.x + Grid.WINDOW + reach) / float(p.pad_block)), floori((o.y + Grid.WINDOW + reach) / float(p.pad_block)))
	for bz in range(b0.y, b1.y + 1):
		for bx in range(b0.x, b1.x + 1):
			var pad := pad_of_block(Vector2i(bx, bz))
			if pad.z != NO_PAD:
				job.pads.append(pad)
	return job


## Выполняет работу до дедлайна (Time.get_ticks_usec()). Возвращает true, когда чанк готов.
func step(job: GenJob, deadline_usec: int) -> bool:
	var origin := job.data.window_origin()
	while job.stage == 0:
		var vz := job.row
		for vx in VERTS:
			var x := float(origin.x + vx)
			var z := float(origin.y + vz)
			job.verts[vz * VERTS + vx] = roundi(_blend_pads(job.pads, x, z, height_raw(x, z)))
		job.row += 1
		if job.row >= VERTS:
			job.stage = 1
			job.row = 0
		if Time.get_ticks_usec() >= deadline_usec:
			return false
	while job.stage == 1:
		for lx in Grid.WINDOW:
			_build_tile(job, lx, job.row, origin)
		job.row += 1
		if job.row >= Grid.WINDOW:
			job.stage = 2
			return true
		if Time.get_ticks_usec() >= deadline_usec:
			return false
	return true


## Высота вершины (ярусы, до округления) с учётом площадок челнока.
func height_at(x: float, z: float) -> float:
	return _apply_pads(x, z, height_raw(x, z))


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


## Высота без площадок: база + террасы + горы − ущелья.
func height_raw(x: float, z: float) -> float:
	var avenue_d := _avenue_distance(x, z)
	var avenue := 1.0 - _smooth(p.avenue_width, p.avenue_width + p.avenue_fade, avenue_d)
	var detail := _n_detail.get_noise_2d(x, z)
	# Ущелье мелеет к проезду на длинном участке, чтобы дно выходило наверх склоном, а не стенкой.
	var canyon := _canyon_t(x, z) * _smooth(p.avenue_width, p.avenue_width + p.avenue_canyon_fade, avenue_d)
	var h := p.base_level + _n_coarse.get_noise_2d(x, z) * p.coarse_amp + detail * p.detail_amp
	# Пологость: зоны пандусов, впадины, проезды, дно ущелий.
	var gentle := maxf(maxf(_ramp_zone(x, z), _smooth(-0.02, -0.25, detail)), maxf(avenue, _smooth(0.0, 0.3, canyon)))
	var plateau := _smooth(-0.05, 0.25, _n_plateau.get_noise_2d(x, z))
	h = _terrace(h, lerpf(p.terrace_low, p.terrace_high, plateau), lerpf(p.step_sharp_w, p.step_gentle_w, gentle))

	var mountain := _mountain_mask(x, z) * (1.0 - avenue)
	if mountain > 0.0:
		var ridge := 1.0 - absf(_n_ridge.get_noise_2d(x, z))
		# Обрывы только у гребней; в долинах между ними — пологие склоны.
		var mountain_gentle := maxf(gentle, _smooth(0.7, 0.45, ridge))
		var mh := mountain * p.mountain_height * (0.35 + 0.65 * ridge * ridge)
		h += _terrace(mh, 2.0, lerpf(p.step_sharp_w, p.step_gentle_w, mountain_gentle))

	if canyon > 0.0:
		# Края резкие, кроме зон пандусов: там стенка ущелья становится склоном.
		var shape := lerpf(clampf(canyon / 0.35, 0.0, 1.0), canyon, _ramp_zone(x, z))
		h -= p.canyon_depth * shape
	return h


## Ярус воды для тайла.
func water_tier(tx: int, tz: int) -> int:
	return roundi(p.water_level + _n_water.get_noise_2d(tx + 0.5, tz + 0.5) * p.water_amp)


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
		var water := water_tier(cx, cz)
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
	var water := water_tier(tx, tz)
	var biome := _biome(cx, cz, lo, water)

	# Крутой тайл уплощается до минимума — на его высоких рёбрах появляются стенки.
	# Тайл с разбросом 1 иногда тоже уплощается — получается уступ.
	if hi - lo >= 2 or (hi - lo == 1 and not is_pad and _is_ledge(cx, cz, biome)):
		c0 = lo
		c1 = lo
		c2 = lo
		c3 = lo
	data.set_corner(i, 0, c0)
	data.set_corner(i, 1, c1)
	data.set_corner(i, 2, c2)
	data.set_corner(i, 3, c3)
	data.biome[i] = biome
	data.material[i] = _material(tx, tz, biome, lo, water)
	data.water_level[i] = water + Grid.HEIGHT_OFFSET if water > lo else 0
	data.flags[i] = ChunkData.FLAG_PAD if is_pad else 0

	data.trees[i] = ChunkData.TREE_NONE
	if water <= lo and not _near_pad(job.pads, tx, tz, p.pad_clear_r):
		if DetRng.unit(seed, tx, tz, 300) < _tree_density(biome):
			data.trees[i] = 1 + DetRng.hash4(seed, tx, tz, 301) % 2
			data.tree_offset[i] = DetRng.hash4(seed, tx, tz, 302) & 0xFF


func _near_pad(pads: Array[Vector3i], tx: int, tz: int, extra: int) -> bool:
	var r := p.pad_half + extra
	for pad in pads:
		if absi(tx - pad.x) <= r and absi(tz - pad.y) <= r:
			return true
	return false


func _biome(x: float, z: float, lowest: int, water: int) -> int:
	if _canyon_t(x, z) > 0.2:
		return ChunkData.Biome.CANYON
	if _mountain_mask(x, z) > 0.15:
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


func _is_ledge(x: float, z: float, biome: int) -> bool:
	if _ramp_zone(x, z) > 0.0 or _avenue(x, z) > 0.0:
		return false   # в зонах пандусов и в проездах уступов нет, иначе путь наверх оборвётся
	var chance := p.ledge_p_plateau if biome == ChunkData.Biome.PLATEAU else p.ledge_p_plain
	return (_n_ledge.get_noise_2d(x, z) + 1.0) * 0.5 < chance


func _material(tx: int, tz: int, biome: int, lowest: int, water: int) -> int:
	var mineral := _n_mineral.get_noise_2d(tx + 0.5, tz + 0.5)
	match biome:
		ChunkData.Biome.MOUNTAINS:
			return ChunkData.Mat.CRYSTAL if mineral > p.crystal_threshold else ChunkData.Mat.ROCK
		ChunkData.Biome.CANYON:
			return ChunkData.Mat.SAND if lowest <= water + 1 else ChunkData.Mat.ROCK
		ChunkData.Biome.CRATERS:
			return ChunkData.Mat.CRYSTAL if mineral > p.crystal_threshold + 0.1 else ChunkData.Mat.SAND
		ChunkData.Biome.LAKESIDE:
			return ChunkData.Mat.SAND
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
