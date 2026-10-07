class_name Grid
extends RefCounted
## Константы сетки и преобразования координат: тайл ↔ чанк ↔ мир.
## Тайл — квадрат 1×1 мировой единицы; тайл (tx, tz) занимает [tx, tx+1] × [tz, tz+1].
## Углы тайла: 0 = NW (x0, z0), 1 = NE (x1, z0), 2 = SE (x1, z1), 3 = SW (x0, z1).

const CHUNK := 32                       ## тайлов на сторону чанка
const APRON := 1                        ## тайлов фартука с каждой стороны окна чанка
const WINDOW := CHUNK + 2 * APRON       ## сторона окна чанка в тайлах (34)
const TIER_H := 0.5                     ## высота яруса в мировых единицах
const HEIGHT_OFFSET := 64               ## сдвиг яруса при хранении в байте

# Направления рёбер тайла: север (-z), восток (+x), юг (+z), запад (-x).
const DIR_N := 0
const DIR_E := 1
const DIR_S := 2
const DIR_W := 3
const DIR_OFFSETS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## Углы ребра в направлении d: [свой угол 1, свой угол 2] и соответствующие им углы соседа.
const EDGE_OWN: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(3, 2), Vector2i(0, 3)]
const EDGE_NEIGHBOR: Array[Vector2i] = [Vector2i(3, 2), Vector2i(0, 3), Vector2i(0, 1), Vector2i(1, 2)]


static func chunk_of_tile(tx: int, tz: int) -> Vector2i:
	return Vector2i(floori(tx / float(CHUNK)), floori(tz / float(CHUNK)))


static func chunk_of_world(x: float, z: float) -> Vector2i:
	return chunk_of_tile(floori(x), floori(z))


static func chunk_origin(coord: Vector2i) -> Vector2i:
	return coord * CHUNK


static func tile_of_world(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x), floori(z))


static func tier_to_y(tier: float) -> float:
	return tier * TIER_H


static func y_to_tier(y: float) -> float:
	return y / TIER_H
