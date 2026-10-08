extends TestCase
## Деформации рельефа (GDD §3.5): воронка без стенок, площадки неподвижны, вода затапливает
## опустившееся, разлом со стенкой и пандусами, на скалах борозды нет, правки в DiffStore.


func _max_delta(f: TerrainFixture, x0: int, z0: int, x1: int, z1: int) -> int:
	var worst := 0
	for tz in range(z0, z1 + 1):
		for tx in range(x0, x1 + 1):
			var c := [f.query.corner(tx, tz, 0), f.query.corner(tx, tz, 1), f.query.corner(tx, tz, 2), f.query.corner(tx, tz, 3)]
			worst = maxi(worst, c.max() - c.min())
	return worst


func _walls(f: TerrainFixture, x0: int, z0: int, x1: int, z1: int) -> int:
	var n := 0
	for tz in range(z0, z1 + 1):
		for tx in range(x0, x1 + 1):
			for dir in 4:
				if f.query.edge_rise(tx, tz, dir) != 0:
					n += 1
	return n


func test_crater_is_a_bowl_without_walls() -> void:
	var f := TerrainFixture.new(6)
	var changed := Deformation.crater(f.terrain, Vector2(10.5, 10.5), 1.5, 1)
	assert_true(changed.size() >= 9, "crater changed %d tiles" % changed.size())
	for c in 4:
		assert_eq(f.query.corner(10, 10, c), 5, "center lowered by a tier")
	assert_eq(_max_delta(f, 5, 5, 15, 15), 1, "tiles stay valid")
	assert_eq(_walls(f, 5, 5, 15, 15), 0, "no walls in a crater")
	assert_true(f.terrain.diffs.get_record(10, 10).size() == 8, "change persisted in DiffStore")


func test_deep_crater_relaxes_into_slopes() -> void:
	var f := TerrainFixture.new(6)
	Deformation.crater(f.terrain, Vector2(10.5, 10.5), 2.0, 3)
	assert_eq(f.query.corner(10, 10, 0), 3)
	assert_true(_max_delta(f, 3, 3, 18, 18) <= 1, "relaxed to Δ ≤ 1")
	assert_eq(_walls(f, 3, 3, 18, 18), 0)


func test_pads_do_not_move() -> void:
	var f := TerrainFixture.new(6)
	for tz in range(8, 13):
		for tx in range(11, 16):
			var d := f.terrain.owner_of(tx, tz)
			var record := d.read_record(d.local_index(tx, tz))
			record[7] = ChunkData.FLAG_PAD
			f.terrain.write_tile(tx, tz, record, false, false)
	Deformation.crater(f.terrain, Vector2(10.5, 10.5), 2.0, 2)
	for tz in range(8, 13):
		for tx in range(11, 16):
			for c in 4:
				assert_eq(f.query.corner(tx, tz, c), 6, "pad tile (%d, %d) untouched" % [tx, tz])
	assert_true(_max_delta(f, 5, 5, 16, 16) <= 1)


func test_crater_next_to_water_floods() -> void:
	var f := TerrainFixture.new(4)
	f.set_flat(12, 10, 3)
	f.set_water(12, 10, 4)          # вода вровень с берегом
	Deformation.crater(f.terrain, Vector2(11.5, 10.5), 1.5, 1)
	assert_eq(f.query.water_tier(11, 10), 4, "lowered shore tile filled with water")


func test_fault_has_wall_and_ramps() -> void:
	var f := TerrainFixture.new(10)
	Deformation.fault(f.terrain, Vector2i(0, 10), true, 20, 2, 1)
	assert_eq(f.query.corner(10, 10, 0), 12, "plus side raised")
	assert_eq(f.query.corner(10, 9, 3), 9, "minus side lowered")
	assert_eq(f.query.edge_rise(10, 9, Grid.DIR_S), 3, "wall along the line")
	assert_eq(f.query.edge_rise(12, 9, Grid.DIR_S), 0, "ramp column has no wall")
	assert_true(_max_delta(f, -3, 0, 23, 20) <= 1, "tiles stay valid")
	# От дальнего края нижней стороны до дальнего края верхней — без подъёма на стенку.
	var seen := {Vector2i(10, 3): true}
	var queue: Array[Vector2i] = [Vector2i(10, 3)]
	while not queue.is_empty():
		var t: Vector2i = queue.pop_back()
		for dir in 4:
			var n: Vector2i = t + Grid.DIR_OFFSETS[dir]
			if n.x < -3 or n.x > 23 or n.y < 0 or n.y > 20 or seen.has(n):
				continue
			if f.query.edge_rise(t.x, t.y, dir) <= 0:
				seen[n] = true
				queue.append(n)
	assert_true(seen.has(Vector2i(10, 17)), "upper side reachable via a ramp")


func test_furrow_leaves_no_trace_on_rock() -> void:
	var f := TerrainFixture.new(6)
	for tz in range(0, 20):
		for tx in range(0, 10):
			var d := f.terrain.owner_of(tx, tz)
			d.material[d.local_index(tx, tz)] = ChunkData.Mat.ROCK
	Deformation.furrow(f.terrain, Vector2(2.0, 10.0), Vector2(18.0, 10.0), 0.6)
	assert_eq(f.query.corner(4, 10, 0), 6, "rock untouched")
	assert_eq(f.query.corner(15, 10, 0), 5, "soil furrowed")
	assert_true(_max_delta(f, 0, 5, 20, 15) <= 1)


func test_on_generated_terrain_keeps_seams_and_valid_tiles() -> void:
	var terrain := TerrainData.new()
	var gen := TerrainGenerator.new(11, TerrainParams.new())
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			terrain.add_chunk(gen.generate(Vector2i(cx, cz)))
	var q := TerrainQuery.new(terrain)
	Deformation.fault(terrain, Vector2i(-10, 3), true, 20, 3, 2)
	Deformation.crater(terrain, Vector2(20.5, -12.5), 2.0, 2)
	Deformation.furrow(terrain, Vector2(-20.0, -20.0), Vector2(5.0, 25.0), 0.6)
	var bad := 0
	for tz in range(-32, 64):
		for tx in range(-32, 64):
			var c := [q.corner(tx, tz, 0), q.corner(tx, tz, 1), q.corner(tx, tz, 2), q.corner(tx, tz, 3)]
			if c.max() - c.min() > 1:
				bad += 1
	assert_eq(bad, 0, "Δ ≤ 1 everywhere")
	# Фартук каждого окна совпадает с данными владельца тайла.
	var mismatch := 0
	for coord: Vector2i in terrain.chunks:
		var data: ChunkData = terrain.chunks[coord]
		var o := data.window_origin()
		for lz in ChunkData.N:
			for lx in ChunkData.N:
				var owner := terrain.owner_of(o.x + lx, o.y + lz)
				if owner == null or owner == data:
					continue
				if data.read_record(lz * ChunkData.N + lx) != owner.read_record(owner.local_index(o.x + lx, o.y + lz)):
					mismatch += 1
	assert_eq(mismatch, 0, "apron windows match owners")
