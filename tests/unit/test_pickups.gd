extends TestCase
## Находки (GDD §6): детерминированная расстановка только на сухих свободных тайлах,
## собранное не возвращается после перезагрузки чанка, вытесненное выпадает рядом.

const SEED := 5


func test_generator_deterministic_and_on_free_tiles() -> void:
	var gen := TerrainGenerator.new(SEED, TerrainParams.new())
	var rules := BalanceRules.new()
	var total := 0
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			var coord := Vector2i(cx, cz)
			var data := gen.generate(coord)
			var a := PickupGenerator.for_chunk(data, SEED, rules)
			var b := PickupGenerator.for_chunk(data, SEED, rules)
			assert_eq(str(a), str(b), "same seed, same pickups in %s" % coord)
			var seen := {}
			for p in a:
				var tile: Vector2i = p["tile"]
				assert_eq(Grid.chunk_of_tile(tile.x, tile.y), coord, "pickup inside its chunk")
				assert_true(PickupGenerator.free_tile(data, data.local_index(tile.x, tile.y)),
						"%s at %s: dry, not a pad, no tree" % [p["kind"], tile])
				assert_false(seen.has(tile), "one pickup per tile")
				seen[tile] = true
			total += a.size()
	assert_true(total > 0, "some pickups in 3×3 chunks")


func test_taken_pickups_stay_taken_after_reload() -> void:
	var rules := BalanceRules.new()
	rules.canister_d0 = 1.0
	var terrain := TerrainData.new()
	var gen := TerrainGenerator.new(SEED, TerrainParams.new())
	var field := PickupField.new(terrain, TerrainQuery.new(terrain), SEED, rules)
	var coord := Vector2i(0, 0)
	terrain.add_chunk(gen.generate(coord))
	field.on_chunk_built(coord)
	var all := field.within(Vector2(16, 16), 100.0)
	var n := all.size()
	assert_true(n > 0)
	assert_eq(n, field.active_count())
	var kinds := all.map(func(p: Dictionary) -> StringName: return p["kind"])
	assert_true(kinds.has(&"canister"), "canister placed when density is 1")

	var taken: Dictionary = all[0]
	field.take(taken["key"])
	assert_eq(field.active_count(), n - 1)
	assert_true(field.near(taken["pos"], 0.3).is_empty(), "taken pickup is gone")

	field.on_chunk_removed(coord)
	terrain.remove_chunk(coord)
	assert_eq(field.active_count(), 0, "unloaded with the chunk")
	field.run_time = 1e6
	terrain.add_chunk(gen.generate(coord))
	field.on_chunk_built(coord)
	assert_eq(field.active_count(), n - 1, "taken one does not come back; canister decision remembered")
	field.free()


func test_drop_lands_nearby_and_survives_reload() -> void:
	var terrain := TerrainData.new()
	var gen := TerrainGenerator.new(SEED, TerrainParams.new())
	var field := PickupField.new(terrain, TerrainQuery.new(terrain), SEED, BalanceRules.new())
	var coord := Vector2i(0, 0)
	terrain.add_chunk(gen.generate(coord))
	field.on_chunk_built(coord)
	var n := field.active_count()
	var at := Vector2(16.5, 16.5)
	assert_true(field.drop(&"crystal", at))
	assert_eq(field.active_count(), n + 1)
	var dropped := field.near(at, 4.5).filter(func(p: Dictionary) -> bool: return p["kind"] == &"crystal")
	assert_false(dropped.is_empty(), "dropped crystal within 3 tiles")

	field.on_chunk_removed(coord)
	terrain.remove_chunk(coord)
	terrain.add_chunk(gen.generate(coord))
	field.on_chunk_built(coord)
	assert_eq(field.active_count(), n + 1, "dropped item persists")
	field.free()
