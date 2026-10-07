extends SceneTree
## Рисует карту рельефа в PNG для подбора параметров генератора.
## Запуск: godot --headless --path . --script res://src/debug/map_preview.gd -- --seed=1 --chunks=8
## Картинка: build/preview/map_<seed>.png, 3 пикселя на тайл.
## Легенда цветов — в MapRender.

const S := 3


func _initialize() -> void:
	var args := _args()
	var run_seed := int(args.get("seed", "1"))
	var n := int(args.get("chunks", "8"))
	var gen := TerrainGenerator.new(run_seed, TerrainParams.new())
	var terrain := TerrainData.new()
	var half := n / 2
	var t0 := Time.get_ticks_usec()
	for cz in range(-half, n - half):
		for cx in range(-half, n - half):
			terrain.add_chunk(gen.generate(Vector2i(cx, cz)))
	var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var q := TerrainQuery.new(terrain)
	var x0 := -half * Grid.CHUNK
	var z0 := x0
	var size := n * Grid.CHUNK
	var pits_before := TerrainConnectivity.trapped_count(q, x0, z0, size, size, 32)
	var t1 := Time.get_ticks_usec()
	var filled := TerrainRepair.fill_pits(terrain, x0, z0, size, size)
	var fill_ms := (Time.get_ticks_usec() - t1) / 1000.0
	var can := TerrainConnectivity.reachable_to_border(q, x0, z0, size, size)

	var trapped := PackedByteArray(can)
	for lz in size:
		for lx in size:
			if lx < 32 or lz < 32 or lx >= size - 32 or lz >= size - 32:
				trapped[lz * size + lx] = 1   # у края окна выход неизвестен — не считаем
	var img := MapRender.render(q, x0, z0, size, size, S, trapped)

	var stats := {"water": 0, "trees": 0, "pad": 0, "ledge_edges": 0, "cliff_edges": 0, "trapped": 0}
	var biomes := PackedInt32Array()
	biomes.resize(7)
	for lz in size:
		for lx in size:
			var tx := x0 + lx
			var tz := z0 + lz
			var d := terrain.owner_of(tx, tz)
			var i := d.local_index(tx, tz)
			biomes[d.biome[i]] += 1
			if d.get_water(i) != TerrainQuery.NO_WATER:
				stats.water += 1
			if d.flags[i] & ChunkData.FLAG_PAD:
				stats.pad += 1
			if d.trees[i] != ChunkData.TREE_NONE:
				stats.trees += 1
			if trapped[lz * size + lx] == 0:
				stats.trapped += 1
			for dir in [Grid.DIR_E, Grid.DIR_S]:
				var step := maxi(q.edge_rise(tx, tz, dir), q.edge_drop(tx, tz, dir))
				if step == 1:
					stats.ledge_edges += 1
				elif step > 1 and step < TerrainQuery.WALL:
					stats.cliff_edges += 1

	var dir_path := ProjectSettings.globalize_path("res://build/preview")
	DirAccess.make_dir_recursive_absolute(dir_path)
	var path := dir_path.path_join("map_%d.png" % run_seed)
	img.save_png(path)
	var tiles := size * size
	print("seed %d: %d chunks, %.1f ms/chunk" % [run_seed, n * n, gen_ms / (n * n)])
	print("pits before repair: %d tiles; filled %d tiles in %.0f ms" % [pits_before, filled, fill_ms])
	print("water %.1f%%, trees %d, pad tiles %d, ledge edges %d, cliff edges %d, trapped tiles %d" % [
			100.0 * stats.water / tiles, stats.trees, stats.pad, stats.ledge_edges, stats.cliff_edges, stats.trapped])
	var names := ["plains", "plateau", "mountains", "canyon", "lakeside", "craters", "forest"]
	var parts := PackedStringArray()
	for b in 7:
		parts.append("%s %.0f%%" % [names[b], 100.0 * biomes[b] / tiles])
	print("biomes: " + ", ".join(parts))
	print("saddle tiles %d, hanging water edges %d" % [TerrainChecks.saddle_count(q, x0, z0, size, size),
			TerrainChecks.hanging_water_count(q, x0, z0, size, size)])
	print("saved " + path)
	quit()


func _args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv := arg.trim_prefix("--").split("=", true, 1)
			result[kv[0]] = kv[1]
	return result
