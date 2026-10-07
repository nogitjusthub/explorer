class_name ChunkData
extends RefCounted
## Данные одного чанка: окно 34×34 тайла — свои 32×32 плюс по ряду тайлов соседей (фартук).
## Фартук совпадает с данными соседей, поэтому мешер рисует стенки на границе без доступа к ним.
## Локальные индексы окна: lx, lz ∈ [0, 34); тайл (tx, tz) ↔ lx = tx − origin.x + APRON.

const N := Grid.WINDOW

enum Mat { GROUND, SAND, ROCK, CRYSTAL }
enum Biome { PLAINS, PLATEAU, MOUNTAINS, CANYON, LAKESIDE, CRATERS, FOREST }

const TREE_NONE := 0
const TREE_TYPE_MASK := 0x3F
const TREE_FELLED := 0x40

const FLAG_PAD := 1
const FLAG_NEST := 2
const FLAG_WRECK := 4

var coord: Vector2i
var corners := PackedByteArray()        ## N*N*4: ярус + HEIGHT_OFFSET
var material := PackedByteArray()       ## N*N: Mat
var water_level := PackedByteArray()    ## N*N: 0 — нет воды, иначе ярус зеркала + HEIGHT_OFFSET
var trees := PackedByteArray()          ## N*N: 0 — нет; биты 0–5 — тип + 1, бит 6 — повален
var tree_offset := PackedByteArray()    ## N*N: старшие 4 бита — x, младшие — z (доли тайла)
var flags := PackedByteArray()          ## N*N: FLAG_*
var biome := PackedByteArray()          ## N*N: Biome
var dirty_sections: int = 0             ## биты 0–3 — секции меша, 4 — вода, 5 — деревья


func _init(chunk_coord: Vector2i = Vector2i.ZERO) -> void:
	coord = chunk_coord
	corners.resize(N * N * 4)
	material.resize(N * N)
	water_level.resize(N * N)
	trees.resize(N * N)
	tree_offset.resize(N * N)
	flags.resize(N * N)
	biome.resize(N * N)


## Мировой тайл в углу окна (lx = 0, lz = 0).
func window_origin() -> Vector2i:
	return coord * Grid.CHUNK - Vector2i(Grid.APRON, Grid.APRON)


func contains_tile(tx: int, tz: int) -> bool:
	var o := window_origin()
	return tx >= o.x and tz >= o.y and tx < o.x + N and tz < o.y + N


func local_index(tx: int, tz: int) -> int:
	var o := window_origin()
	return (tz - o.y) * N + (tx - o.x)


func get_corner(i: int, c: int) -> int:
	return corners[i * 4 + c] - Grid.HEIGHT_OFFSET


func set_corner(i: int, c: int, tier: int) -> void:
	corners[i * 4 + c] = tier + Grid.HEIGHT_OFFSET


## Ярус воды или -1000, если воды нет.
func get_water(i: int) -> int:
	var w := water_level[i]
	return -1000 if w == 0 else w - Grid.HEIGHT_OFFSET


## Полная запись тайла (8 байт) — единица хранения в DiffStore.
func read_record(i: int) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(8)
	for c in 4:
		r[c] = corners[i * 4 + c]
	r[4] = material[i]
	r[5] = water_level[i]
	r[6] = trees[i]
	r[7] = flags[i]
	return r


func write_record(i: int, r: PackedByteArray) -> void:
	for c in 4:
		corners[i * 4 + c] = r[c]
	material[i] = r[4]
	water_level[i] = r[5]
	trees[i] = r[6]
	flags[i] = r[7]
