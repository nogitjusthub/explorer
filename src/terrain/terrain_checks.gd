class_name TerrainChecks
extends RefCounted
## Проверки качества рельефа для тестов и предпросмотра карты.


## Седловидные тайлы («песочные часы»): противоположные углы равны, пары разные.
static func saddle_count(q: TerrainQuery, x0: int, z0: int, w: int, h: int) -> int:
	var count := 0
	for tz in range(z0, z0 + h):
		for tx in range(x0, x0 + w):
			var a := q.corner(tx, tz, 0)
			var b := q.corner(tx, tz, 1)
			var c := q.corner(tx, tz, 2)
			var d := q.corner(tx, tz, 3)
			if a == c and b == d and a != b:
				count += 1
	return count


## «Висящая вода»: соседние тайлы с водой разного уровня или вода рядом с сухим тайлом,
## у которого земля на общем ребре ниже зеркала. Считаются пары соседей по ребру.
static func hanging_water_count(q: TerrainQuery, x0: int, z0: int, w: int, h: int) -> int:
	var count := 0
	for tz in range(z0, z0 + h):
		for tx in range(x0, x0 + w):
			var level := q.water_tier(tx, tz)
			if level == TerrainQuery.NO_WATER:
				continue
			for d in 4:
				var o := Grid.DIR_OFFSETS[d]
				var nx := tx + o.x
				var nz := tz + o.y
				if not q.is_loaded(nx, nz):
					continue
				var other := q.water_tier(nx, nz)
				if other != TerrainQuery.NO_WATER:
					if other != level:
						count += 1
					continue
				var nb := Grid.EDGE_NEIGHBOR[d]
				if mini(q.corner(nx, nz, nb.x), q.corner(nx, nz, nb.y)) < level:
					count += 1
	return count
