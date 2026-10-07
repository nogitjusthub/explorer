extends TestCase
## Изменения рельефа переживают выгрузку чанка.


func test_felled_tree_survives_reload() -> void:
	var gen := TerrainGenerator.new(7, TerrainParams.new())
	var terrain := TerrainData.new()
	var q := TerrainQuery.new(terrain)
	var coord := Vector2i(1, 1)
	terrain.add_chunk(gen.generate(coord))
	var data: ChunkData = terrain.chunks[coord]
	var tree := Vector2i(-1, -1)
	var o := Grid.chunk_origin(coord)
	for tz in range(o.y, o.y + Grid.CHUNK):
		for tx in range(o.x, o.x + Grid.CHUNK):
			if q.has_standing_tree(tx, tz):
				tree = Vector2i(tx, tz)
				break
		if tree.x != -1:
			break
	if tree.x == -1:
		fail("no tree in chunk (1, 1) for seed 7")
		return
	q.fell_tree(tree.x, tree.y)
	assert_true(data.dirty_sections & TerrainData.DIRTY_TREES != 0, "trees marked dirty")
	terrain.remove_chunk(coord)
	terrain.add_chunk(gen.generate(coord))
	assert_false(q.has_standing_tree(tree.x, tree.y), "tree stays felled after reload")


func test_key_roundtrip() -> void:
	for t in [Vector2i(0, 0), Vector2i(-1, 5), Vector2i(100000, -100000), Vector2i(-7, -7)]:
		assert_eq(DiffStore.key_tile(DiffStore.key(t.x, t.y)), t)
