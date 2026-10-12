class_name GroundSprites
extends RefCounted
## Мелочь на земле (M5): пиксельные спрайты травы, кустиков, камней и осколков в MultiMesh чанка
## (ChunkNode.sprites). Раскладка детерминирована (seed, тайл): по тайлу — шанс по материалу и биому,
## вид и цвет — по жребию; место — случайное внутри тайла, высота — поверхность в этой точке.
## Не на воде, площадках, зыбуне и под деревьями (стоящими и поваленными). Неровный грунт — почти в каждом тайле
## камни. Пересобирается вместе с рельефом тайла (часть PART_SPRITES).

enum Kind { GRASS, TALL_GRASS, BUSH, STONE, PEBBLES, ROCK, SHARDS, BULB }

const PLANT_TINTS: Array[Color] = [Color(0.3, 0.52, 0.44), Color(0.5, 0.36, 0.48), Color(0.42, 0.5, 0.36)]
const DRY_TINT := Color(0.66, 0.58, 0.4)          ## сухая трава на песке
const STONE_TINTS: Array[Color] = [
	Color(0.56, 0.42, 0.36),   # грунт
	Color(0.7, 0.62, 0.48),    # песок
	Color(0.44, 0.47, 0.55),   # камень
	Color(0.5, 0.34, 0.56),    # кристаллическая порода
]
const SHARD_TINT := Color(0.64, 0.42, 0.74)


const STRIDE := 20                       ## floats на экземпляр в буфере MultiMesh: 12 — Transform3D, 4 — цвет, 4 — custom


## Горячий цикл (браузер!): всё — прямо из массивов чанка (без запросов к миру), случайности — из
## целочисленного хэша тайла, MultiMesh заливается одним буфером.
static func build(node: ChunkNode, data: ChunkData, _q: TerrainQuery, run_seed: int) -> void:
	var origin := Grid.chunk_origin(data.coord)
	var n := ChunkData.N
	var cs := data.corners
	var off := Grid.HEIGHT_OFFSET
	var skip := ChunkData.FLAG_PAD | ChunkData.FLAG_MIRE
	var buf := PackedFloat32Array()
	buf.resize(Grid.CHUNK * Grid.CHUNK * 2 * STRIDE)
	var count := 0
	for lz in range(Grid.APRON, Grid.APRON + Grid.CHUNK):
		for lx in range(Grid.APRON, Grid.APRON + Grid.CHUNK):
			var i := lz * n + lx
			var flags: int = data.flags[i]
			if (flags & skip) != 0 or data.trees[i] != 0 or data.water_level[i] != 0:
				continue
			var tx := origin.x + lx - Grid.APRON
			var tz := origin.y + lz - Grid.APRON
			var h := _hash(tx, tz, run_seed)
			var mat: int = data.material[i]
			var rough := (flags & ChunkData.FLAG_ROUGH) != 0
			var sprites := 0
			if rough:
				if (h & 0xFF) < 217:                     # 85%
					sprites = 1 + int(((h >> 8) & 0xFF) < 102)   # +1 с шансом 40%
			elif (h & 0xFF) < int(_chance(mat, data.biome[i]) * 256.0):
				sprites = 1
			var b := i * 4
			for k in sprites:
				var r := _hash(tx, tz, run_seed + 7919 * (k + 1))
				var kind := _kind(mat, rough, (r & 0xFF) / 255.0)
				var fx := 0.25 + 0.5 * ((r >> 8) & 0xFF) / 255.0
				var fz := 0.25 + 0.5 * ((r >> 16) & 0xFF) / 255.0
				var y := TerrainRules.height_in_tile(cs[b] - off, cs[b + 1] - off, cs[b + 2] - off, cs[b + 3] - off,
						fx, fz) * Grid.TIER_H
				var col := _tint(kind, mat, ((r >> 24) & 0x7F) / 127.0)
				var o := count * STRIDE
				buf[o] = 1.0
				buf[o + 3] = tx + fx - origin.x
				buf[o + 5] = 1.0
				buf[o + 7] = y
				buf[o + 10] = 1.0
				buf[o + 11] = tz + fz - origin.y
				buf[o + 12] = col.r
				buf[o + 13] = col.g
				buf[o + 14] = col.b
				buf[o + 15] = 1.0
				buf[o + 16] = kind
				buf[o + 17] = float((h >> (16 + k)) & 1)          # зеркало
				count += 1
	var mm := node.sprites.multimesh
	mm.instance_count = count
	if count > 0:
		mm.buffer = buf.slice(0, count * STRIDE)


## Целочисленный хэш тайла (детерминирован по seed).
static func _hash(tx: int, tz: int, s: int) -> int:
	var h := (tx * 374761393 + tz * 668265263 + s * 1013904223) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return h ^ (h >> 16)


## Шанс мелочи в тайле: трава на грунте (в лесу гуще), редкие камни на песке и камне, осколки на
## кристаллической породе.
static func _chance(mat: int, biome: int) -> float:
	match mat:
		ChunkData.Mat.GROUND:
			return 0.45 if biome == ChunkData.Biome.FOREST else 0.3
		ChunkData.Mat.SAND:
			return 0.07
		ChunkData.Mat.ROCK:
			return 0.1
		ChunkData.Mat.CRYSTAL:
			return 0.14
	return 0.0


static func _kind(mat: int, rough: bool, r: float) -> int:
	if rough:
		return Kind.ROCK if r < 0.3 else (Kind.STONE if r < 0.7 else Kind.PEBBLES)
	match mat:
		ChunkData.Mat.GROUND:
			return Kind.GRASS if r < 0.45 else (Kind.TALL_GRASS if r < 0.7 else (Kind.BUSH if r < 0.9 else Kind.BULB))
		ChunkData.Mat.SAND:
			return Kind.PEBBLES if r < 0.4 else (Kind.STONE if r < 0.7 else Kind.GRASS)
		ChunkData.Mat.ROCK:
			return Kind.STONE if r < 0.5 else (Kind.ROCK if r < 0.8 else Kind.PEBBLES)
		_:
			return Kind.SHARDS if r < 0.7 else Kind.PEBBLES


static func _tint(kind: int, mat: int, r: float) -> Color:
	match kind:
		Kind.GRASS, Kind.TALL_GRASS, Kind.BUSH, Kind.BULB:
			if mat == ChunkData.Mat.SAND:
				return DRY_TINT
			return PLANT_TINTS[mini(int(r * PLANT_TINTS.size()), PLANT_TINTS.size() - 1)]
		Kind.SHARDS:
			return SHARD_TINT
	return STONE_TINTS[clampi(mat, 0, STONE_TINTS.size() - 1)] * (0.92 + 0.16 * r)
