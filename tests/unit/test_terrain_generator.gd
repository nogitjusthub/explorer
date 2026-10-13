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


func test_prep_stage_reads_cached_pads() -> void:
	# Этап 0 генерации: сначала площадки всех нужных блоков (по одной за шаг), потом гнёзда и лужи —
	# они только читают кэш площадок (иначе одна проба считала бы до 9 площадок — шип кадра в вебе).
	# Порции не меняют результат.
	var dune_chunks := {1: Vector2i(-25, 7), 7: Vector2i(-35, 32)}     # гряды ищут площадки рядом
	for run_seed: int in [1, 7]:
		var gen := TerrainGenerator.new(run_seed, TerrainParams.new())
		for coord: Vector2i in [Vector2i(0, 0), Vector2i(2, -3), dune_chunks[run_seed]]:
			var job := gen.begin(coord)
			while job.stage == 0 and job.row < job.prep_blocks.size():
				gen.step(job, 0)                  # дедлайн прошёл: одна единица работы за шаг
			var cached := gen._pads.size()
			while job.stage == 0:
				gen.step(job, 0)
			assert_eq(gen._pads.size(), cached, "seed %d chunk %s: pads computed after the prep steps" % [run_seed, coord])
			while not gen.step(job, 0):
				pass
			var whole := TerrainGenerator.new(run_seed, TerrainParams.new()).generate(coord)
			assert_true(job.data.corners == whole.corners and job.data.flags == whole.flags \
					and job.data.water_level == whole.water_level, "seed %d chunk %s: sliced == whole" % [run_seed, coord])


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


func test_ground_flags_placement() -> void:
	# Неровный и зыбучий грунт (GDD §3.5a, §5.6): не на воде (кроме кромки), не на площадках;
	# зыбучий — только песок или грунт у воды; оба вместе не бывают.
	var gen := TerrainGenerator.new(7, TerrainParams.new())
	var rough := 0
	var mire := 0
	for coord in [Vector2i(0, 0), Vector2i(-2, 1), Vector2i(1, -1)]:
		var d := gen.generate(coord)
		var n := ChunkData.N
		for lz in range(1, 33):
			for lx in range(1, 33):
				var i := lz * n + lx
				var f := d.flags[i]
				assert_false((f & ChunkData.FLAG_ROUGH) != 0 and (f & ChunkData.FLAG_MIRE) != 0, "exclusive")
				if (f & ChunkData.FLAG_ROUGH) != 0:
					rough += 1
					assert_eq(d.water_level[i], 0, "rough is dry")
				if (f & ChunkData.FLAG_MIRE) != 0:
					mire += 1
					assert_true(d.material[i] == ChunkData.Mat.SAND or d.material[i] == ChunkData.Mat.GROUND, "mire on sand or ground")
					# У самой воды: вода в тайле или соседнем, и нижний угол не выше её уровня (не над обрывом).
					var level := -1000
					for dz in range(-1, 2):
						for dx in range(-1, 2):
							var j := (lz + dz) * n + lx + dx
							if d.water_level[j] != 0:
								level = maxi(level, d.water_level[j] - Grid.HEIGHT_OFFSET)
					var lo := mini(mini(d.get_corner(i, 0), d.get_corner(i, 1)), mini(d.get_corner(i, 2), d.get_corner(i, 3)))
					assert_true(level > -1000 and lo <= level, "mire at the water's edge, not above a cliff")
				if (f & ChunkData.FLAG_PAD) != 0:
					assert_eq(f & ChunkData.GROUND_FLAGS, 0, "pads stay plain")
	assert_true(rough > 0 and mire > 0, "both kinds present: rough %d, mire %d" % [rough, mire])
