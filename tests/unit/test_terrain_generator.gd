extends TestCase
## Генератор рельефа: детерминизм, швы между чанками, валидность тайлов, связность.

const SEEDS := [1, 7, 12345]


func test_determinism() -> void:
	var a := TerrainGenerator.new(1, TerrainParams.new()).generate(Vector2i(2, -3))
	var b := TerrainGenerator.new(1, TerrainParams.new()).generate(Vector2i(2, -3))
	var c := TerrainGenerator.new(2, TerrainParams.new()).generate(Vector2i(2, -3))
	assert_true(a.corners == b.corners, "same seed → same corners")
	assert_true(a.trees == b.trees and a.material == b.material and a.water_level == b.water_level, "same seed → same layers")
	assert_true(a.corners != c.corners, "different seed → different corners")


func test_seams_between_chunks() -> void:
	# Фартук чанка совпадает с данными соседа — швов нет.
	var gen := TerrainGenerator.new(7, TerrainParams.new())
	var chunks := {}
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			chunks[Vector2i(cx, cz)] = gen.generate(Vector2i(cx, cz))
	var mismatches := 0
	for coord: Vector2i in chunks:
		var data: ChunkData = chunks[coord]
		var o := data.window_origin()
		for lz in ChunkData.N:
			for lx in ChunkData.N:
				var tx := o.x + lx
				var tz := o.y + lz
				var owner := Grid.chunk_of_tile(tx, tz)
				if owner == coord or not chunks.has(owner):
					continue
				var other: ChunkData = chunks[owner]
				if data.read_record(lz * ChunkData.N + lx) != other.read_record(other.local_index(tx, tz)):
					mismatches += 1
	assert_eq(mismatches, 0, "apron tiles differ from neighbour data")


func test_tiles_valid() -> void:
	# Внутри тайла разброс углов ≤ 1; на рёбрах нет «крестов».
	var gen := TerrainGenerator.new(12345, TerrainParams.new())
	var data := gen.generate(Vector2i(0, 0))
	var bad := 0
	var crosses := 0
	for lz in ChunkData.N:
		for lx in ChunkData.N:
			var i := lz * ChunkData.N + lx
			var lo := 1 << 20
			var hi := -(1 << 20)
			for c in 4:
				lo = mini(lo, data.get_corner(i, c))
				hi = maxi(hi, data.get_corner(i, c))
			if hi - lo > 1:
				bad += 1
			if lx + 1 < ChunkData.N:
				var j := i + 1
				var d1 := data.get_corner(j, 0) - data.get_corner(i, 1)
				var d2 := data.get_corner(j, 3) - data.get_corner(i, 2)
				if d1 * d2 < 0:
					crosses += 1
	assert_eq(bad, 0, "tiles with corner range > 1")
	assert_eq(crosses, 0, "cross edges")


func test_no_pits_after_repair() -> void:
	# После заливки из любого тайла в глубине окна можно доехать до его границы.
	for run_seed: int in SEEDS:
		var gen := TerrainGenerator.new(run_seed, TerrainParams.new())
		var terrain := TerrainData.new()
		for cz in range(-2, 3):
			for cx in range(-2, 3):
				terrain.add_chunk(gen.generate(Vector2i(cx, cz)))
		var q := TerrainQuery.new(terrain)
		var x0 := -2 * Grid.CHUNK
		var size := 5 * Grid.CHUNK
		var filled := TerrainRepair.fill_pits(terrain, x0, x0, size, size)
		assert_true(filled < size * size / 50, "seed %d: too many filled tiles (%d)" % [run_seed, filled])
		assert_eq(TerrainConnectivity.trapped_count(q, x0, x0, size, size, Grid.CHUNK), 0, "seed %d: trapped tiles" % run_seed)


func test_no_hanging_water_and_few_saddles() -> void:
	# Вода не висит над сухим соседом, разные уровни не соприкасаются; седловин почти нет.
	for run_seed: int in SEEDS:
		var gen := TerrainGenerator.new(run_seed, TerrainParams.new())
		var terrain := TerrainData.new()
		for cz in range(-2, 2):
			for cx in range(-2, 2):
				terrain.add_chunk(gen.generate(Vector2i(cx, cz)))
		var q := TerrainQuery.new(terrain)
		var x0 := -2 * Grid.CHUNK
		var size := 4 * Grid.CHUNK
		assert_eq(TerrainChecks.hanging_water_count(q, x0, x0, size, size), 0, "seed %d: hanging water" % run_seed)
		var saddles := TerrainChecks.saddle_count(q, x0, x0, size, size)
		# Седловину, которую нельзя выровнять без обрыва по соседству, генератор оставляет — таких единицы.
		assert_true(saddles <= size * size / 500, "seed %d: saddle tiles %d" % [run_seed, saddles])


func test_pads_flat_and_dry() -> void:
	# В блоке может не найтись места (всё под водой или в ущелье) — берём ближайший блок с площадкой.
	var gen := TerrainGenerator.new(1, TerrainParams.new())
	var pad := Vector3i(0, 0, TerrainGenerator.NO_PAD)
	for b in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1)]:
		pad = gen.pad_of_block(b)
		if pad.z != TerrainGenerator.NO_PAD:
			break
	if pad.z == TerrainGenerator.NO_PAD:
		fail("no pad in 6 blocks around the origin for seed 1")
		return
	var terrain := TerrainData.new()
	terrain.add_chunk(gen.generate(Grid.chunk_of_tile(pad.x, pad.y)))
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var tx := pad.x + dx
			var tz := pad.y + dz
			var d := terrain.owner_of(tx, tz)
			if d == null:
				continue
			var i := d.local_index(tx, tz)
			for c in 4:
				assert_eq(d.get_corner(i, c), pad.z, "pad tile %d,%d corner %d" % [tx, tz, c])
			assert_eq(d.water_level[i], 0, "pad tile under water")
			assert_true(d.flags[i] & ChunkData.FLAG_PAD != 0, "pad flag")


func test_nests_in_canyons_and_lakes_away_from_pads() -> void:
	var gen := TerrainGenerator.new(3, TerrainParams.new())
	var found := 0
	for bz in range(-4, 4):
		for bx in range(-4, 4):
			var n := gen.nest_of_block(Vector2i(bx, bz))
			if n == TerrainGenerator.NO_NEST:
				continue
			found += 1
			var data := gen.generate(Grid.chunk_of_tile(n.x, n.y))
			var i := data.local_index(n.x, n.y)
			assert_true((data.flags[i] & ChunkData.FLAG_NEST) != 0, "nest tile flagged")
			var b: int = data.biome[i]
			assert_true(b == ChunkData.Biome.CANYON or b == ChunkData.Biome.LAKESIDE, "nest biome %d" % b)
			assert_eq(data.trees[i], ChunkData.TREE_NONE, "no tree on a nest")
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var pad := gen.pad_of_block(Vector2i(bx + dx, bz + dz))
					if pad.z != TerrainGenerator.NO_PAD:
						assert_true(Vector2(n).distance_to(Vector2(pad.x, pad.y)) >= 14.0, "nest away from pads")
	assert_true(found > 0, "some nests in 8×8 blocks: %d" % found)
