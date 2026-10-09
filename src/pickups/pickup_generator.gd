class_name PickupGenerator
extends RefCounted
## Расстановка находок в чанке (GDD §6) — чистая функция от seed и данных чанка.
## Не на воде, не на площадке челнока, не под деревом; не больше одной находки на тайл.
## У гнёзд — дополнительные образцы и ядра.
## Канистры здесь не ставятся: их плотность зависит от времени забега (PickupField).


const NEST_CORE_CHANCE := 0.35


## Список находок чанка: [{tile: Vector2i, kind: StringName}, ...].
static func for_chunk(data: ChunkData, run_seed: int, rules: BalanceRules) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var origin := Grid.chunk_origin(data.coord)
	# Один генератор на чанк и бросок на каждый тайл в фиксированном порядке: детерминированно
	# и на порядок дешевле хэша на тайл (важно — работа идёт внутри бюджета кадра).
	var rng := DetRng.rng_for(run_seed, data.coord.x, data.coord.y, 600)
	var max_chance := maxf(maxf(rules.crystal_chance_on_crystal, rules.crystal_chance_elsewhere),
			maxf(maxf(rules.sample_chance_lakeside, rules.sample_chance_forest), rules.core_chance_rocky))
	for lz in range(Grid.APRON, Grid.APRON + Grid.CHUNK):
		for lx in range(Grid.APRON, Grid.APRON + Grid.CHUNK):
			var roll := rng.randf()
			var i := lz * ChunkData.N + lx
			if (data.flags[i] & ChunkData.FLAG_ROUGH) != 0:
				roll /= rules.rough_pickup_mult
			if roll >= max_chance:
				continue
			if not free_tile(data, i):
				continue
			var kind := _tile_kind(data, i, roll, rules)
			if kind != &"":
				result.append({"tile": Vector2i(origin.x + lx - Grid.APRON, origin.y + lz - Grid.APRON), "kind": kind})
	_add_nest_loot(data, run_seed, result)
	if DetRng.unit(run_seed, data.coord.x, data.coord.y, 610) < rules.repair_per_chunk:
		var tile := random_free_tile(data, run_seed, 611)
		if tile.x != -999999 and not _has_tile(result, tile):
			result.append({"tile": tile, "kind": &"repair"})
	return result


## Тайл годится под находку: сухо, не площадка, нет стоящего дерева.
static func free_tile(data: ChunkData, i: int) -> bool:
	if data.water_level[i] != 0 or (data.flags[i] & ChunkData.FLAG_PAD) != 0:
		return false
	var tree := data.trees[i]
	return tree == ChunkData.TREE_NONE or (tree & ChunkData.TREE_FELLED) != 0


## Случайный свободный тайл чанка по хэшу (stream — номер потока); (-999999, ...) — не нашёлся.
static func random_free_tile(data: ChunkData, run_seed: int, stream: int) -> Vector2i:
	var origin := Grid.chunk_origin(data.coord)
	for attempt in 24:
		var h := DetRng.hash4(run_seed, data.coord.x, data.coord.y, stream * 100 + attempt)
		var lx := Grid.APRON + h % Grid.CHUNK
		var lz := Grid.APRON + (h >> 8) % Grid.CHUNK
		if free_tile(data, lz * ChunkData.N + lx):
			return Vector2i(origin.x + lx - Grid.APRON, origin.y + lz - Grid.APRON)
	return Vector2i(-999999, -999999)


static func _tile_kind(data: ChunkData, i: int, roll: float, rules: BalanceRules) -> StringName:
	var biome := data.biome[i]
	if (biome == ChunkData.Biome.MOUNTAINS or biome == ChunkData.Biome.CANYON) and roll < rules.core_chance_rocky:
		return &"core"
	if biome == ChunkData.Biome.LAKESIDE and roll < rules.sample_chance_lakeside:
		return &"sample"
	if biome == ChunkData.Biome.FOREST and roll < rules.sample_chance_forest:
		return &"sample"
	var crystal_chance := rules.crystal_chance_on_crystal if data.material[i] == ChunkData.Mat.CRYSTAL \
			else rules.crystal_chance_elsewhere
	if roll < crystal_chance:
		return &"crystal"
	return &""


## У гнезда (тайлы с FLAG_NEST в этом чанке) — пара образцов и иногда ядро, в 2–5 тайлах от него.
static func _add_nest_loot(data: ChunkData, run_seed: int, result: Array[Dictionary]) -> void:
	var origin := Grid.chunk_origin(data.coord)
	var sum := Vector2.ZERO
	var count := 0
	for lz in range(Grid.APRON, Grid.APRON + Grid.CHUNK):
		for lx in range(Grid.APRON, Grid.APRON + Grid.CHUNK):
			if (data.flags[lz * ChunkData.N + lx] & ChunkData.FLAG_NEST) != 0:
				sum += Vector2(lx, lz)
				count += 1
	if count == 0:
		return
	var c := Vector2i((sum / count).round())
	var rng := DetRng.rng_for(run_seed, data.coord.x, data.coord.y, 640)
	var kinds: Array[StringName] = [&"sample", &"sample"]
	if rng.randf() < NEST_CORE_CHANCE:
		kinds.append(&"core")
	for kind in kinds:
		for _attempt in 12:
			var l := c + Vector2i(rng.randi_range(-5, 5), rng.randi_range(-5, 5))
			if maxi(absi(l.x - c.x), absi(l.y - c.y)) < 2:
				continue
			if l.x < Grid.APRON or l.y < Grid.APRON or l.x >= Grid.APRON + Grid.CHUNK or l.y >= Grid.APRON + Grid.CHUNK:
				continue
			if not free_tile(data, l.y * ChunkData.N + l.x):
				continue
			var tile := Vector2i(origin.x + l.x - Grid.APRON, origin.y + l.y - Grid.APRON)
			if _has_tile(result, tile):
				continue
			result.append({"tile": tile, "kind": kind})
			break


static func _has_tile(list: Array[Dictionary], tile: Vector2i) -> bool:
	for p in list:
		if p["tile"] == tile:
			return true
	return false
