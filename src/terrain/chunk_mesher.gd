class_name ChunkMesher
extends RefCounted
## Меши чанка: 4 секции 16×16 тайлов (верх тайлов + стенки) и отдельный меш воды.
## Вершины — в координатах чанка (узел чанка стоит в его мировом углу).
## Нормалей нет: плоское освещение считает шейдер. COLOR.a = 1 помечает стенку.
## Стенку на ребре рисует только более высокая сторона — без дублей и без соседних чанков.

const SECTION := 16
const MATERIAL_COLORS: Array[Color] = [
	Color(0.50, 0.30, 0.24),   # грунт
	Color(0.60, 0.52, 0.66),   # песок
	Color(0.32, 0.37, 0.47),   # камень
	Color(0.22, 0.66, 0.64),   # кристалл
]


## Массивы поверхности секции s (0..3: x — s % 2, z — s / 2).
## Горячий цикл: углы читаются прямо из байтов (сдвиг яруса сокращается в сравнениях),
## оттенок тайла — дешёвый целочисленный хэш мировых координат.
static func build_section(data: ChunkData, s: int, _run_seed: int = 0) -> Array:
	var i0 := (s % 2) * SECTION + Grid.APRON
	var j0 := (s / 2) * SECTION + Grid.APRON
	var n := ChunkData.N
	var cs := data.corners
	var mats := data.material

	var walls := 0
	for lz in range(j0, j0 + SECTION):
		for lx in range(i0, i0 + SECTION):
			var b := (lz * n + lx) * 4
			var bn := b - n * 4
			var bs := b + n * 4
			if cs[b] > cs[bn + 3] or cs[b + 1] > cs[bn + 2]:
				walls += 1
			if cs[b + 1] > cs[b + 4] or cs[b + 2] > cs[b + 7]:
				walls += 1
			if cs[b + 3] > cs[bs] or cs[b + 2] > cs[bs + 1]:
				walls += 1
			if cs[b] > cs[b - 3] or cs[b + 3] > cs[b - 2]:
				walls += 1

	var quads := SECTION * SECTION + walls
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(quads * 4)
	colors.resize(quads * 4)
	indices.resize(quads * 6)
	var vi := 0
	var ii := 0
	var origin := data.window_origin()
	var wall_color := Color(0.4, 0.38, 0.42, 1.0)
	var h := Grid.TIER_H
	var off := Grid.HEIGHT_OFFSET

	for lz in range(j0, j0 + SECTION):
		var z := float(lz - Grid.APRON)
		for lx in range(i0, i0 + SECTION):
			var i := lz * n + lx
			var b := i * 4
			var c0 := cs[b] - off
			var c1 := cs[b + 1] - off
			var c2 := cs[b + 2] - off
			var c3 := cs[b + 3] - off
			var x := float(lx - Grid.APRON)
			verts[vi] = Vector3(x, c0 * h, z)
			verts[vi + 1] = Vector3(x + 1.0, c1 * h, z)
			verts[vi + 2] = Vector3(x + 1.0, c2 * h, z + 1.0)
			verts[vi + 3] = Vector3(x, c3 * h, z + 1.0)
			var hsh := (((origin.x + lx) * 374761393) ^ ((origin.y + lz) * 668265263)) & 0xFFFF
			var col := MATERIAL_COLORS[mats[i]] * (0.94 + 0.12 * hsh / 65535.0)
			col.a = 0.0
			colors[vi] = col
			colors[vi + 1] = col
			colors[vi + 2] = col
			colors[vi + 3] = col
			# Обход по часовой стрелке при взгляде сверху — лицевая сторона в Godot.
			if c1 == c3 and c0 != c2:
				_tri(indices, ii, vi, 0, 1, 3)
				_tri(indices, ii + 3, vi, 1, 2, 3)
			else:
				_tri(indices, ii, vi, 0, 1, 2)
				_tri(indices, ii + 3, vi, 0, 2, 3)
			vi += 4
			ii += 6

			# Стенки рисует более высокая сторона ребра. Углы ребра — в порядке «слева направо»
			# для наблюдателя снаружи, чтобы обход тоже шёл по часовой стрелке.
			var bn := b - n * 4
			var bs := b + n * 4
			if cs[b] > cs[bn + 3] or cs[b + 1] > cs[bn + 2]:   # север: слева NE, справа NW
				vi = _wall(verts, colors, indices, vi, ii, wall_color, Vector2(x + 1.0, z), c1, mini(c1, cs[bn + 2] - off), Vector2(x, z), c0, mini(c0, cs[bn + 3] - off))
				ii += 6
			if cs[b + 1] > cs[b + 4] or cs[b + 2] > cs[b + 7]:  # восток: слева SE, справа NE
				vi = _wall(verts, colors, indices, vi, ii, wall_color, Vector2(x + 1.0, z + 1.0), c2, mini(c2, cs[b + 7] - off), Vector2(x + 1.0, z), c1, mini(c1, cs[b + 4] - off))
				ii += 6
			if cs[b + 3] > cs[bs] or cs[b + 2] > cs[bs + 1]:    # юг: слева SW, справа SE
				vi = _wall(verts, colors, indices, vi, ii, wall_color, Vector2(x, z + 1.0), c3, mini(c3, cs[bs] - off), Vector2(x + 1.0, z + 1.0), c2, mini(c2, cs[bs + 1] - off))
				ii += 6
			if cs[b] > cs[b - 3] or cs[b + 3] > cs[b - 2]:      # запад: слева NW, справа SW
				vi = _wall(verts, colors, indices, vi, ii, wall_color, Vector2(x, z), c0, mini(c0, cs[b - 3] - off), Vector2(x, z + 1.0), c3, mini(c3, cs[b - 2] - off))
				ii += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Квад стенки: p1 — левый край для наблюдателя снаружи, p2 — правый. Возвращает новый vi.
static func _wall(verts: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, vi: int, ii: int,
		color: Color, p1: Vector2, top1: int, bot1: int, p2: Vector2, top2: int, bot2: int) -> int:
	var h := Grid.TIER_H
	verts[vi] = Vector3(p1.x, top1 * h, p1.y)
	verts[vi + 1] = Vector3(p2.x, top2 * h, p2.y)
	verts[vi + 2] = Vector3(p2.x, bot2 * h, p2.y)
	verts[vi + 3] = Vector3(p1.x, bot1 * h, p1.y)
	colors[vi] = color
	colors[vi + 1] = color
	colors[vi + 2] = color
	colors[vi + 3] = color
	_tri(indices, ii, vi, 0, 1, 2)
	_tri(indices, ii + 3, vi, 0, 2, 3)
	return vi + 4


## Массивы поверхности воды чанка или пустой массив, если воды нет.
## В COLOR.r — глубина (доля от 4 ярусов) для цвета в шейдере.
static func build_water(data: ChunkData) -> Array:
	var n := ChunkData.N
	var count := 0
	for lz in range(Grid.APRON, Grid.APRON + Grid.CHUNK):
		for lx in range(Grid.APRON, Grid.APRON + Grid.CHUNK):
			if data.water_level[lz * n + lx] != 0:
				count += 1
	if count == 0:
		return []
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(count * 4)
	colors.resize(count * 4)
	indices.resize(count * 6)
	var vi := 0
	var ii := 0
	for lz in range(Grid.APRON, Grid.APRON + Grid.CHUNK):
		for lx in range(Grid.APRON, Grid.APRON + Grid.CHUNK):
			var i := lz * n + lx
			var w := data.get_water(i)
			if w == TerrainQuery.NO_WATER:
				continue
			var x := float(lx - Grid.APRON)
			var z := float(lz - Grid.APRON)
			var y := w * Grid.TIER_H - 0.06
			verts[vi] = Vector3(x, y, z)
			verts[vi + 1] = Vector3(x + 1.0, y, z)
			verts[vi + 2] = Vector3(x + 1.0, y, z + 1.0)
			verts[vi + 3] = Vector3(x, y, z + 1.0)
			for k in 4:
				var depth := w - data.get_corner(i, k)
				colors[vi + k] = Color(clampf(depth / 4.0, 0.0, 1.0), 0.0, 0.0, 1.0)
			_tri(indices, ii, vi, 0, 1, 2)
			_tri(indices, ii + 3, vi, 0, 2, 3)
			vi += 4
			ii += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


static func _tri(indices: PackedInt32Array, at: int, base: int, a: int, b: int, c: int) -> void:
	indices[at] = base + a
	indices[at + 1] = base + b
	indices[at + 2] = base + c
