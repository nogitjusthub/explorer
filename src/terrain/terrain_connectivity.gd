class_name TerrainConnectivity
extends RefCounted
## Проверка «ям без выхода» (GDD §3.2): из какого тайла окна можно доехать до его границы.
## Ход в соседа разрешён, если ребро не поднимается (склон, ровно или обрыв вниз).
## Учитывается только рельеф; вода зависит от класса машины и проверяется отдельно.


## Маска окна w×h (1 — до границы окна доехать можно). Обратный обход от граничных тайлов.
static func reachable_to_border(q: TerrainQuery, x0: int, z0: int, w: int, h: int) -> PackedByteArray:
	var can := PackedByteArray()
	can.resize(w * h)
	var queue := PackedInt32Array()
	for z in h:
		for x in w:
			if x == 0 or z == 0 or x == w - 1 or z == h - 1:
				can[z * w + x] = 1
				queue.append(z * w + x)
	var head := 0
	while head < queue.size():
		var v := queue[head]
		head += 1
		var vx := v % w
		var vz := v / w
		for d in 4:
			var o := Grid.DIR_OFFSETS[d]
			var ux := vx + o.x
			var uz := vz + o.y
			if ux < 0 or uz < 0 or ux >= w or uz >= h:
				continue
			var u := uz * w + ux
			if can[u] == 1:
				continue
			# Из u в v ведёт направление, противоположное d.
			if q.edge_rise(x0 + ux, z0 + uz, (d + 2) % 4) <= 0:
				can[u] = 1
				queue.append(u)
	return can


## Число «запертых» тайлов, не ближе margin тайлов к границе окна.
static func trapped_count(q: TerrainQuery, x0: int, z0: int, w: int, h: int, margin: int) -> int:
	var can := reachable_to_border(q, x0, z0, w, h)
	var count := 0
	for z in range(margin, h - margin):
		for x in range(margin, w - margin):
			if can[z * w + x] == 0:
				count += 1
	return count
