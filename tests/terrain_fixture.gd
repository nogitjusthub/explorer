class_name TerrainFixture
extends RefCounted
## Рукотворный рельеф для тестов: плоские чанки заданного яруса и правка отдельных тайлов.

var terrain := TerrainData.new()
var query: TerrainQuery


func _init(tier: int = 4, radius: int = 1) -> void:
	query = TerrainQuery.new(terrain)
	for cz in range(-radius, radius + 1):
		for cx in range(-radius, radius + 1):
			var data := ChunkData.new(Vector2i(cx, cz))
			for i in ChunkData.N * ChunkData.N:
				for c in 4:
					data.set_corner(i, c, tier)
			terrain.add_chunk(data)


## Задаёт углы тайла во всех окнах, где он есть.
func set_tile(tx: int, tz: int, c0: int, c1: int, c2: int, c3: int) -> void:
	var d := terrain.owner_of(tx, tz)
	var record := d.read_record(d.local_index(tx, tz))
	record[0] = c0 + Grid.HEIGHT_OFFSET
	record[1] = c1 + Grid.HEIGHT_OFFSET
	record[2] = c2 + Grid.HEIGHT_OFFSET
	record[3] = c3 + Grid.HEIGHT_OFFSET
	terrain.write_tile(tx, tz, record, false, false)


func set_flat(tx: int, tz: int, tier: int) -> void:
	set_tile(tx, tz, tier, tier, tier, tier)


## Прямоугольник плоских тайлов [x0, x1] × [z0, z1].
func set_block(x0: int, z0: int, x1: int, z1: int, tier: int) -> void:
	for tz in range(z0, z1 + 1):
		for tx in range(x0, x1 + 1):
			set_flat(tx, tz, tier)


func set_water(tx: int, tz: int, level: int) -> void:
	var d := terrain.owner_of(tx, tz)
	var record := d.read_record(d.local_index(tx, tz))
	record[5] = level + Grid.HEIGHT_OFFSET
	terrain.write_tile(tx, tz, record, false, false)


## Дерево в центре тайла (смещение 0x77 ≈ середина).
func set_flags(tx: int, tz: int, flags: int) -> void:
	var d := terrain.owner_of(tx, tz)
	d.flags[d.local_index(tx, tz)] = flags


func set_tree(tx: int, tz: int) -> void:
	var d := terrain.owner_of(tx, tz)
	var i := d.local_index(tx, tz)
	d.tree_offset[i] = 0x77
	var record := d.read_record(i)
	record[6] = 1
	terrain.write_tile(tx, tz, record, false, false)
