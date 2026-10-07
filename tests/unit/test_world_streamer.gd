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
