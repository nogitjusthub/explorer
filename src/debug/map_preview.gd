extends SceneTree
## Рисует карту рельефа в PNG для подбора параметров генератора.
## Запуск: godot --headless --path . --script res://src/debug/map_preview.gd -- --seed=1 --chunks=8
## Картинка: build/preview/map_<seed>.png, 3 пикселя на тайл.
## Цвета: материал × высота; синий — вода; тёмно-зелёный — дерево; пурпурный — площадка челнока;
## чёрная линия — стенка ≥ 2 яруса, оранжевая — уступ в 1 ярус; красный — тайл без выхода.

const S := 3
const MATERIAL_COLORS: Array[Color] = [
	Color(0.62, 0.38, 0.27),   # грунт
	Color(0.74, 0.66, 0.78),   # песок
	Color(0.36, 0.42, 0.52),   # камень
	Color(0.30, 0.85, 0.80),   # кристалл
]


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

	var img := Image.create(size * S, size * S, false, Image.FORMAT_RGB8)
	var stats := {"water": 0, "trees": 0, "pad": 0, "ledge_edges": 0, "cliff_edges": 0, "trapped": 0}
	var biomes := PackedInt32Array()
	biomes.resize(7)
	for lz in size:
		for lx in size:
			var tx := x0 + lx
			var tz := z0 + lz
			var d := terrain.owner_of(tx, tz)
			var i := d.local_index(tx, tz)
			var c0 := d.get_corner(i, 0)
			var c1 := d.get_corner(i, 1)
			var c2 := d.get_corner(i, 2)
			var c3 := d.get_corner(i, 3)
			var avg := (c0 + c1 + c2 + c3) / 4.0
			var col: Color = MATERIAL_COLORS[d.material[i]]
			col = col * clampf(0.45 + avg * 0.045, 0.3, 1.25)
			var gx := (c1 + c2 - c0 - c3) * 0.5
			var gz := (c2 + c3 - c0 - c1) * 0.5
			col = col * clampf(1.0 - 0.18 * (gx + gz), 0.6, 1.4)
			biomes[d.biome[i]] += 1
			var water := d.get_water(i)
			if water != TerrainQuery.NO_WATER:
				stats.water += 1
				col = col.lerp(Color(0.08, 0.42, 0.45), clampf(0.55 + (water - avg) * 0.12, 0.5, 0.95))
			if d.flags[i] & ChunkData.FLAG_PAD:
				stats.pad += 1
				col = Color(0.9, 0.2, 0.85)
			var trapped := can[lz * size + lx] == 0 and lx >= 32 and lz >= 32 and lx < size - 32 and lz < size - 32
			if trapped:
				stats.trapped += 1
				col = Color(1, 0, 0)
			for py in S:
				for px in S:
					img.set_pixel(lx * S + px, lz * S + py, col)
			if d.trees[i] != ChunkData.TREE_NONE:
				stats.trees += 1
				img.set_pixel(lx * S + 1, lz * S + 1, Color(0.1, 0.3, 0.15))
			# Стенки на восточном и южном рёбрах (каждое ребро рисуется один раз).
			for dir in [Grid.DIR_E, Grid.DIR_S]:
				var step := maxi(q.edge_rise(tx, tz, dir), q.edge_drop(tx, tz, dir))
				if step <= 0 or step >= TerrainQuery.WALL:
					continue
				if step == 1:
					stats.ledge_edges += 1
				else:
					stats.cliff_edges += 1
				var wall_col := Color(0.95, 0.55, 0.1) if step == 1 else Color(0, 0, 0)
				for k in S:
					if dir == Grid.DIR_E:
						img.set_pixel(lx * S + S - 1, lz * S + k, wall_col)
					else:
						img.set_pixel(lx * S + k, lz * S + S - 1, wall_col)

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
	print("saved " + path)
	quit()


func _args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv := arg.trim_prefix("--").split("=", true, 1)
			result[kv[0]] = kv[1]
	return result
