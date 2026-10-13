extends TestCase
## Стриминг чанков: предзагрузка вокруг точки, готовность мешей, выгрузка дальних после переезда.


func test_preload_and_move() -> void:
	var terrain := TerrainData.new()
	var gen := TerrainGenerator.new(3, TerrainParams.new())
	var q := TerrainQuery.new(terrain)
	var jobs := JobScheduler.new()
	var streamer := WorldStreamer.new(terrain, gen, q, jobs, TerrainMaterials.new())

	streamer.preload_around(Vector2(16, 16))
	assert_true(streamer.loaded_count() >= 9, "chunks loaded around the start: %d" % streamer.loaded_count())
	for coord: Vector2i in terrain.chunks:
		assert_true(streamer.is_ready(coord), "chunk %s meshed" % coord)
	assert_eq(jobs.pending(), 0, "no jobs left after preload")

	streamer.preload_around(Vector2(216, 16))
	assert_false(terrain.chunks.has(Vector2i(0, 0)), "far chunk unloaded")
	assert_true(streamer.is_ready(Grid.chunk_of_world(216, 16)), "chunk under the new focus ready")
	assert_true(streamer.loaded_count() <= 49, "loaded set stays bounded: %d" % streamer.loaded_count())

	streamer.free()
	jobs.free()


func test_pit_fill_around_new_chunks() -> void:
	# Заливка ям после подгрузки идёт в окрестности новых чанков, а не по всему кругу загрузки; ям без
	# выхода в загруженном не остаётся.
	var terrain := TerrainData.new()
	var gen := TerrainGenerator.new(3, TerrainParams.new())
	var q := TerrainQuery.new(terrain)
	var jobs := JobScheduler.new()
	var streamer := WorldStreamer.new(terrain, gen, q, jobs, TerrainMaterials.new())
	streamer.preload_around(Vector2(16, 16))
	var full := streamer._pit_rect
	var x := 16.0
	var smaller := 0
	for _i in 6:                                   # едем на восток по полчанка
		x += 16.0
		var before := streamer.loaded_count()
		streamer.preload_around(Vector2(x, 16))
		if streamer.loaded_count() > before and streamer._pit_rect.get_area() < full.get_area():
			smaller += 1
	assert_true(smaller > 0, "pit checks limited to the new chunks' neighbourhood")
	# Полностью загруженный прямоугольник вокруг машины: ям без выхода нет.
	var c := Grid.chunk_of_world(x, 16)
	var x0 := (c.x - 1) * Grid.CHUNK
	var z0 := (c.y - 1) * Grid.CHUNK
	for cz in range(c.y - 1, c.y + 2):
		for cx in range(c.x - 1, c.x + 2):
			assert_true(terrain.chunks.has(Vector2i(cx, cz)), "chunk %d,%d loaded" % [cx, cz])
	assert_eq(TerrainConnectivity.trapped_count(q, x0, z0, 3 * Grid.CHUNK, 3 * Grid.CHUNK, 0), 0, "trapped tiles")
	streamer.free()
	jobs.free()


func test_ridge_settles_after_chunk_reload() -> void:
	# Вал червя не успел осесть, пока чанк был выгружен: возврат откладывается и выполняется, когда
	# стример загрузит чанк снова.
	var terrain := TerrainData.new()
	var gen := TerrainGenerator.new(3, TerrainParams.new())
	var q := TerrainQuery.new(terrain)
	var jobs := JobScheduler.new()
	var streamer := WorldStreamer.new(terrain, gen, q, jobs, TerrainMaterials.new())
	streamer.preload_around(Vector2(16, 16))
	var before := {}
	for tz in range(4, 18):
		for tx in range(4, 26):
			for c in 4:
				before[Vector3i(tx, tz, c)] = q.corner(tx, tz, c)
	var originals := {}
	Deformation.raise_vertices(terrain, Deformation.vertices_near_segment(Vector2(8.0, 10.0), Vector2(22.0, 12.0), 0.7), originals)
	assert_false(originals.is_empty(), "ridge raised")
	var verts: Array[Vector2i] = []
	for key: Vector3i in originals:
		verts.append(Deformation.recorded_vertex(key))
	streamer.preload_around(Vector2(216, 16))
	assert_false(terrain.chunks.has(Vector2i(0, 0)), "ridge chunk unloaded")
	Deformation.restore_vertices(terrain, verts, originals)
	assert_true(originals.is_empty() and not terrain.pending_restores.is_empty(), "restore deferred")
	streamer.preload_around(Vector2(16, 16))
	assert_true(terrain.pending_restores.is_empty(), "deferred restore done on reload")
	var diff := 0
	for key: Vector3i in before:
		if q.corner(key.x, key.y, key.z) != before[key]:
			diff += 1
	assert_eq(diff, 0, "ridge settled back after the reload")
	streamer.free()
	jobs.free()
