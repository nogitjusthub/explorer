class_name TerrainData
extends RefCounted
## Реестр загруженных чанков. Чтение тайла идёт из чанка-владельца; запись — во все
## загруженные окна, содержащие тайл (владелец и фартуки соседей), и в DiffStore,
## чтобы правка пережила выгрузку чанка.

const DIRTY_TREES := 1 << 5
const DIRTY_SPRITES := 1 << 6           ## мелочь на земле — стоит на высоте тайла

var chunks: Dictionary[Vector2i, ChunkData] = {}
var diffs := DiffStore.new()
## Временные подъёмы (вал червя), которые не удалось вернуть: чанк тайла был выгружен.
## Vector3i(tx, tz, угол) → исходный ярус; Deformation.restore_pending вернёт их после загрузки чанка.
var pending_restores: Dictionary = {}


func add_chunk(data: ChunkData) -> void:
	diffs.apply_to(data)
	chunks[data.coord] = data
	_sync_ground_flags(data)


## Свойства грунта (неровный, зыбучий) генератор считает по соседям в окне чанка — у тайлов фартука
## соседей не хватает. Поэтому фартук берёт их у чанка-владельца, а свои тайлы чанк отдаёт в фартуки
## уже загруженных соседей: копии тайла во всех окнах совпадают.
func _sync_ground_flags(data: ChunkData) -> void:
	var n := ChunkData.N
	var o := data.window_origin()
	for lz in n:
		for lx in n:
			if lx > 0 and lz > 0 and lx < n - 1 and lz < n - 1:
				continue
			var tx := o.x + lx
			var tz := o.y + lz
			var owner := owner_of(tx, tz)
			if owner == null or owner == data:
				continue
			_copy_ground(owner, owner.local_index(tx, tz), data, lz * n + lx)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nb: ChunkData = chunks.get(data.coord + Vector2i(dx, dz))
			if nb == null or nb == data:
				continue
			var no := nb.window_origin()
			for lz in n:
				for lx in n:
					if lx > 0 and lz > 0 and lx < n - 1 and lz < n - 1:
						continue
					var tx := no.x + lx
					var tz := no.y + lz
					if Grid.chunk_of_tile(tx, tz) == data.coord:
						_copy_ground(data, data.local_index(tx, tz), nb, lz * n + lx)


static func _copy_ground(src: ChunkData, i: int, dst: ChunkData, j: int) -> void:
	dst.flags[j] = (dst.flags[j] & ~ChunkData.GROUND_FLAGS) | (src.flags[i] & ChunkData.GROUND_FLAGS)


func remove_chunk(coord: Vector2i) -> void:
	chunks.erase(coord)


func owner_of(tx: int, tz: int) -> ChunkData:
	return chunks.get(Grid.chunk_of_tile(tx, tz))


func is_loaded(tx: int, tz: int) -> bool:
	return chunks.has(Grid.chunk_of_tile(tx, tz))


## Записывает тайл во все окна и в DiffStore. sections_dirty — пересобрать меш вокруг тайла.
func write_tile(tx: int, tz: int, record: PackedByteArray, mesh_dirty: bool, trees_dirty: bool) -> void:
	diffs.set_record(tx, tz, record)
	var owner := Grid.chunk_of_tile(tx, tz)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var data: ChunkData = chunks.get(owner + Vector2i(dx, dz))
			if data == null or not data.contains_tile(tx, tz):
				continue
			data.write_record(data.local_index(tx, tz), record)
			if mesh_dirty:
				data.dirty_sections |= _sections_touching(data, tx, tz)
				if data.coord == owner:
					data.dirty_sections |= DIRTY_SPRITES
			if trees_dirty and data.coord == owner:
				data.dirty_sections |= DIRTY_TREES


## Помечает части для пересборки (биты ChunkData.dirty_sections) во всех окнах, где есть тайл.
func mark_dirty(tx: int, tz: int, bits: int) -> void:
	var owner := Grid.chunk_of_tile(tx, tz)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var data: ChunkData = chunks.get(owner + Vector2i(dx, dz))
			if data != null and data.contains_tile(tx, tz):
				data.dirty_sections |= bits


## Секции меша (биты 0–3), которые рисуют тайл или стенки рядом с ним.
static func _sections_touching(data: ChunkData, tx: int, tz: int) -> int:
	var origin := Grid.chunk_origin(data.coord)
	var bits := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var ix := tx + dx - origin.x
			var iz := tz + dz - origin.y
			if ix < 0 or iz < 0 or ix >= Grid.CHUNK or iz >= Grid.CHUNK:
				continue
			bits |= 1 << ((iz / 16) * 2 + (ix / 16))
	return bits
