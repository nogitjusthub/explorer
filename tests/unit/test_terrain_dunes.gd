extends TestCase
## Дюнные поля (GDD §3.4): детерминизм, только песок посреди части пустынь, без стенок, площадки ровные.


## Чанк, где больше всего дюнного поля (грубый поиск по сетке вокруг начала координат).
func _dune_chunk(gen: TerrainGenerator) -> Vector2i:
	var counts := {}
	for z in range(-1200, 1200, 16):
		for x in range(-1200, 1200, 16):
			if gen.dune_field(x + 0.5, z + 0.5) > 0.5:
				var c := Grid.chunk_of_tile(x, z)
				counts[c] = counts.get(c, 0) + 1
	var best := Vector2i.ZERO
	var best_n := 0
	for c: Vector2i in counts:
		if counts[c] > best_n or (counts[c] == best_n and (c.x < best.x or (c.x == best.x and c.y < best.y))):
			best = c
			best_n = counts[c]
	return best


func _no_dunes(run_seed: int) -> TerrainGenerator:
	var params := TerrainParams.new()
	params.dunes_enabled = false
	return TerrainGenerator.new(run_seed, params)


## Есть ли у тайла стенка (перепад на общем ребре) с соседом по ребру; i — тайл не на краю окна.
func _walled(d: ChunkData, i: int) -> bool:
	var n := ChunkData.N
	return d.get_corner(i, 1) != d.get_corner(i + 1, 0) or d.get_corner(i, 2) != d.get_corner(i + 1, 3) \
			or d.get_corner(i, 3) != d.get_corner(i + n, 0) or d.get_corner(i, 2) != d.get_corner(i + n, 1) \
			or d.get_corner(i, 0) != d.get_corner(i - 1, 1) or d.get_corner(i, 3) != d.get_corner(i - 1, 2) \
			or d.get_corner(i, 0) != d.get_corner(i - n, 3) or d.get_corner(i, 1) != d.get_corner(i - n, 2)


func test_dunes_deterministic() -> void:
	var a := TerrainGenerator.new(1, TerrainParams.new())
	var b := TerrainGenerator.new(1, TerrainParams.new())
	var c := TerrainGenerator.new(2, TerrainParams.new())
	var coord := _dune_chunk(a)
	assert_eq(_dune_chunk(b), coord, "same seed → same dune chunk")
	var da := a.generate(coord)
	var db := b.generate(coord)
	assert_true(da.corners == db.corners and da.material == db.material and da.flags == db.flags, "same seed → same dunes")
	var same := 0
	var total := 0
	var diff := 0
	for z in range(-600, 600, 7):
		for x in range(-600, 600, 7):
			var h1 := a.dune_height(x + 0.5, z + 0.5)
			if h1 != b.dune_height(x + 0.5, z + 0.5):
				diff += 1
			if h1 > 0.0:
				total += 1
				if c.dune_height(x + 0.5, z + 0.5) > 0.0:
					same += 1
	assert_eq(diff, 0, "dune heights differ for the same seed")
	assert_true(total > 0 and same < total, "another seed → other dune fields (%d of %d coincide)" % [same, total])
	# Без дюн маска пустая везде.
	var off := _no_dunes(1)
	assert_eq(off.dune_field(coord.x * Grid.CHUNK + 16.5, coord.y * Grid.CHUNK + 16.5), 0.0, "dunes disabled")


func test_dune_fields_optional_and_inside_deserts() -> void:
	# Поле — только посреди пустыни (порог кратеров с запасом) и не во всех пустынях (шум выбора).
	var gen := TerrainGenerator.new(7, TerrainParams.new())
	var p := gen.p
	var core := 0
	var core_with := 0
	var field := 0
	var samples := 0
	for z in range(-1500, 1500, 12):
		for x in range(-1500, 1500, 12):
			samples += 1
			var fx := x + 0.5
			var fz := z + 0.5
			var crater := gen._n_crater.get_noise_2d(fx, fz)
			var m := gen.dune_field(fx, fz)
			if m > 0.0:
				field += 1
				assert_true(crater > p.crater_threshold + p.dune_core_from, "field inside a desert core at %d,%d" % [x, z])
				assert_true(gen._n_dune.get_noise_2d(fx, fz) > p.dune_field_threshold, "field picked by the noise at %d,%d" % [x, z])
				assert_eq(gen._canyon_t(fx, fz), 0.0, "no dunes in canyons")
				assert_eq(gen._mountain_mask(fx, fz), 0.0, "no dunes in mountains")
			if crater > p.crater_threshold + p.dune_core_to:
				core += 1
				if m > 0.0:
					core_with += 1
	var share := float(core_with) / maxi(core, 1)
	assert_true(share > 0.1 and share < 0.7, "only some desert cores have dunes: %.2f" % share)
	var cover := float(field) / samples
	assert_true(cover > 0.01 and cover < 0.06, "dune fields cover %.3f of the world" % cover)


func test_dunes_sand_no_walls_seamless() -> void:
	# В дюнном поле: песок, без воды, деревьев, россыпей и гнёзд; стенок дюны не добавляют; швов между
	# чанками нет (правка вершин и признаки тайлов считаются по мировым координатам).
	for run_seed: int in [1, 7]:
		var gen := TerrainGenerator.new(run_seed, TerrainParams.new())
		var off := _no_dunes(run_seed)
		var center := _dune_chunk(gen)
		var chunks := {}
		var dune_tiles := 0
		var raised := 0
		var new_walls := 0
		var steep := 0
		for cz in range(center.y - 1, center.y + 1):
			for cx in range(center.x - 1, center.x + 1):
				var coord := Vector2i(cx, cz)
				var d := gen.generate(coord)
				var d_off := off.generate(coord)
				chunks[coord] = d
				var o := d.window_origin()
				for lz in range(Grid.APRON, Grid.APRON + Grid.CHUNK):
					for lx in range(Grid.APRON, Grid.APRON + Grid.CHUNK):
						var i := lz * ChunkData.N + lx
						var tx := o.x + lx
						var tz := o.y + lz
						if not gen.dune_tile(tx, tz):
							continue
						dune_tiles += 1
						assert_eq(d.material[i], ChunkData.Mat.SAND, "dune tile %d,%d is sand" % [tx, tz])
						assert_eq(d.biome[i], ChunkData.Biome.CRATERS, "dune tile %d,%d biome" % [tx, tz])
						assert_eq(d.water_level[i], 0, "no water on dunes")
						assert_eq(d.trees[i], ChunkData.TREE_NONE, "no trees on dunes")
						assert_eq(d.flags[i] & (ChunkData.FLAG_ROUGH | ChunkData.FLAG_MIRE | ChunkData.FLAG_NEST), 0, "plain sand")
						var lo := 1 << 20
						var hi := -(1 << 20)
						for c in 4:
							lo = mini(lo, d.get_corner(i, c))
							hi = maxi(hi, d.get_corner(i, c))
							if d.get_corner(i, c) != d_off.get_corner(i, c):
								raised += 1
						if hi - lo > 1:
							steep += 1
						if _walled(d, i) and not _walled(d_off, i):
							new_walls += 1
		assert_true(dune_tiles > 500, "seed %d: dune tiles near %s: %d" % [run_seed, str(center), dune_tiles])
		assert_true(raised > dune_tiles / 4, "seed %d: dunes change the relief (%d corners)" % [run_seed, raised])
		assert_eq(steep, 0, "seed %d: dune tiles with corner range > 1" % run_seed)
		assert_eq(new_walls, 0, "seed %d: walls added by dunes" % run_seed)
		var mismatches := 0
		for coord: Vector2i in chunks:
			var data: ChunkData = chunks[coord]
			var o := data.window_origin()
			for lz in ChunkData.N:
				for lx in ChunkData.N:
					var owner := Grid.chunk_of_tile(o.x + lx, o.y + lz)
					if owner == coord or not chunks.has(owner):
						continue
					var other: ChunkData = chunks[owner]
					# Байт флагов не сравнивается: осыпь у тайла фартука считается без соседей за окном.
					var mine := data.read_record(lz * ChunkData.N + lx).slice(0, 7)
					if mine != other.read_record(other.local_index(o.x + lx, o.y + lz)).slice(0, 7):
						mismatches += 1
		assert_eq(mismatches, 0, "seed %d: apron tiles differ in a dune field" % run_seed)


func test_dune_height_matches_generation() -> void:
	# Вершины чанка (горячий путь: площадки — списком задачи) совпадают с height_at (площадки — из кэша
	# по блокам) с точностью до правки седловин и крутизны (±1). Сравниваются углы неплоских тайлов —
	# уплощённые до минимума тайлы своих вершин не хранят.
	var gen := TerrainGenerator.new(1, TerrainParams.new())
	var d := gen.generate(_dune_chunk(gen))
	var o := d.window_origin()
	var checked := 0
	var off_by_one := 0
	var dunes := 0
	for lz in ChunkData.N:
		for lx in ChunkData.N:
			var i := lz * ChunkData.N + lx
			var c0 := d.get_corner(i, 0)
			if c0 == d.get_corner(i, 1) and c0 == d.get_corner(i, 2) and c0 == d.get_corner(i, 3):
				continue
			var h := gen.height_at(o.x + lx, o.y + lz)
			if gen.dune_height(o.x + lx, o.y + lz) > 0.0:
				dunes += 1
			checked += 1
			var delta := absi(c0 - roundi(h))
			assert_true(delta <= 1, "vertex %d,%d: %d vs height_at %.2f" % [o.x + lx, o.y + lz, c0, h])
			if delta == 1:
				off_by_one += 1
	assert_true(dunes > 50, "dune vertices on slopes in the chunk: %d" % dunes)
	assert_true(off_by_one * 10 < checked, "vertices off by one: %d of %d" % [off_by_one, checked])


func test_pads_in_dune_fields_flat() -> void:
	# Площадка посреди дюн ровная; гряды гаснут к ней и в её пологом кольце их нет.
	var found := 0
	for run_seed: int in [1, 7]:
		var gen := TerrainGenerator.new(run_seed, TerrainParams.new())
		for bz in range(-8, 0):
			for bx in range(-8, 8):
				var pad := gen.pad_of_block(Vector2i(bx, bz))
				if pad.z == TerrainGenerator.NO_PAD or gen.dune_field(pad.x + 0.5, pad.y + 0.5) <= 0.0:
					continue
				found += 1
				var reach := gen.p.pad_half + int(gen.p.pad_blend)
				for dz in range(-reach, reach + 2):
					for dx in range(-reach, reach + 2):
						assert_eq(gen.dune_height(pad.x + dx, pad.y + dz), 0.0, "no dunes in the pad ring")
				var terrain := TerrainData.new()
				terrain.add_chunk(gen.generate(Grid.chunk_of_tile(pad.x, pad.y)))
				for dz in range(-gen.p.pad_half, gen.p.pad_half + 1):
					for dx in range(-gen.p.pad_half, gen.p.pad_half + 1):
						var d := terrain.owner_of(pad.x + dx, pad.y + dz)
						if d == null:
							continue
						var i := d.local_index(pad.x + dx, pad.y + dz)
						for c in 4:
							assert_eq(d.get_corner(i, c), pad.z, "seed %d pad %d,%d corner" % [run_seed, pad.x, pad.y])
						assert_true(d.flags[i] & ChunkData.FLAG_PAD != 0, "pad flag")
						assert_eq(d.water_level[i], 0, "pad under water")
	assert_true(found > 0, "some pads inside dune fields")
