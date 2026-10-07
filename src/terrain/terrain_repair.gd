class_name TerrainRepair
extends RefCounted
## Заливка ям без выхода (GDD §3.2): стенку вверх не проезжает никто, поэтому замкнутая
## впадина — ловушка. Генератор делает такие ямы редкими, остаток добивается здесь.
##
## Яма — тайлы окна, из которых нельзя доехать до выхода: границы окна или тайла рядом с
## незагруженным чанком (о нём ещё ничего не известно). Пол ямы поднимается до уровня самого
## низкого края: углы = max(угол, уровень выхода). Тайлы вне ямы не меняются, поэтому новых
## ям не появляется. Правки идут через TerrainData — во все окна чанков и в DiffStore.


## Один проход заливки окна, порциями под бюджет кадра.
class PitFillJob:
	extends Job
	var terrain: TerrainData
	var x0: int
	var z0: int
	var w: int
	var h: int
	var changed := 0                     ## сколько тайлов поднято (после завершения)

	var _phase := 0
	var _row := 0
	var _head := 0
	var _start := 0
	var _corners := PackedInt32Array()
	var _loaded := PackedByteArray()
	var _can := PackedByteArray()
	var _label := PackedByteArray()
	var _queue := PackedInt32Array()

	func _init(t: TerrainData, wx0: int, wz0: int, width: int, height: int) -> void:
		terrain = t
		x0 = wx0
		z0 = wz0
		w = width
		h = height
		_corners.resize(w * h * 4)
		_loaded.resize(w * h)
		_can.resize(w * h)
		_label.resize(w * h)

	func step(deadline_usec: int) -> bool:
		while true:
			match _phase:
				0:
					_copy_row(_row)
					_row += 1
					if _row >= h:
						_phase = 1
						_row = 0
				1:
					_seed_exits_row(_row)
					_row += 1
					if _row >= h:
						_phase = 2
				2:
					var budget := 512
					while _head < _queue.size() and budget > 0:
						_expand(_queue[_head])
						_head += 1
						budget -= 1
					if _head >= _queue.size():
						_phase = 3
				3:
					var budget := 4096
					while _start < w * h and budget > 0:
						if _loaded[_start] == 1 and _can[_start] == 0 and _label[_start] == 0:
							_fill_component(_start)
						_start += 1
						budget -= 1
					if _start >= w * h:
						return true
			if Time.get_ticks_usec() >= deadline_usec:
				return false
		return true

	func _copy_row(z: int) -> void:
		for x in w:
			var d := terrain.owner_of(x0 + x, z0 + z)
			if d == null:
				continue
			var i := z * w + x
			var li := d.local_index(x0 + x, z0 + z)
			_loaded[i] = 1
			for c in 4:
				_corners[i * 4 + c] = d.get_corner(li, c)

	## Выходы: граница окна и тайлы рядом с незагруженными.
	func _seed_exits_row(z: int) -> void:
		for x in w:
			var i := z * w + x
			if _loaded[i] == 0:
				continue
			var exit := x == 0 or z == 0 or x == w - 1 or z == h - 1
			if not exit:
				for d in 4:
					var o := Grid.DIR_OFFSETS[d]
					if _loaded[(z + o.y) * w + x + o.x] == 0:
						exit = true
						break
			if exit:
				_can[i] = 1
				_queue.append(i)

	## Обратный обход: в v можно попасть из соседа u, если ребро u→v не поднимается.
	func _expand(v: int) -> void:
		var vx := v % w
		var vz := v / w
		for d in 4:
			var o := Grid.DIR_OFFSETS[d]
			var ux := vx + o.x
			var uz := vz + o.y
			if ux < 0 or uz < 0 or ux >= w or uz >= h:
				continue
			var u := uz * w + ux
			if _can[u] == 1 or _loaded[u] == 0:
				continue
			if TerrainRepair.rise(_corners, u, v, (d + 2) % 4) <= 0:
				_can[u] = 1
				_queue.append(u)

	## Компонента ямы и её уровень выхода — минимум высоты края соседа по рёбрам наружу.
	func _fill_component(start: int) -> void:
		var comp := PackedInt32Array([start])
		_label[start] = 1
		var exit_level := 1 << 20
		var k := 0
		while k < comp.size():
			var u := comp[k]
			k += 1
			var ux := u % w
			var uz := u / w
			for d in 4:
				var o := Grid.DIR_OFFSETS[d]
				var vx := ux + o.x
				var vz := uz + o.y
				if vx < 0 or vz < 0 or vx >= w or vz >= h:
					continue
				var v := vz * w + vx
				if _can[v] == 1:
					var nb := Grid.EDGE_NEIGHBOR[d]
					exit_level = mini(exit_level, maxi(_corners[v * 4 + nb.x], _corners[v * 4 + nb.y]))
				elif _label[v] == 0 and _loaded[v] == 1:
					_label[v] = 1
					comp.append(v)
		for u in comp:
			changed += TerrainRepair.raise_tile(terrain, x0 + u % w, z0 + u / w, exit_level)


## Полная заливка окна (несколько проходов, пока есть изменения). Возвращает число поднятых тайлов.
static func fill_pits(terrain: TerrainData, x0: int, z0: int, w: int, h: int) -> int:
	var total := 0
	for _pass in 4:
		var job := PitFillJob.new(terrain, x0, z0, w, h)
		while not job.step(Time.get_ticks_usec() + 3_600_000_000):
			pass
		total += job.changed
		if job.changed == 0:
			break
	return total


## Подъём ребра при ходе из u в v (dir — направление из u в v).
static func rise(corners: PackedInt32Array, u: int, v: int, dir: int) -> int:
	var own := Grid.EDGE_OWN[dir]
	var nb := Grid.EDGE_NEIGHBOR[dir]
	return maxi(corners[v * 4 + nb.x] - corners[u * 4 + own.x], corners[v * 4 + nb.y] - corners[u * 4 + own.y])


## Поднимает углы тайла до level. Возвращает 1, если тайл изменился.
static func raise_tile(terrain: TerrainData, tx: int, tz: int, level: int) -> int:
	var d := terrain.owner_of(tx, tz)
	if d == null:
		return 0   # чанк успели выгрузить
	var record := d.read_record(d.local_index(tx, tz))
	var raised := false
	var lowest := 1 << 20
	for c in 4:
		var tier := record[c] - Grid.HEIGHT_OFFSET
		if tier < level:
			tier = level
			raised = true
		record[c] = tier + Grid.HEIGHT_OFFSET
		lowest = mini(lowest, tier)
	if not raised:
		return 0
	# Вода остаётся, только если зеркало выше нового дна.
	if record[5] != 0 and record[5] - Grid.HEIGHT_OFFSET <= lowest:
		record[5] = 0
	terrain.write_tile(tx, tz, record, true, false)
	return 1
