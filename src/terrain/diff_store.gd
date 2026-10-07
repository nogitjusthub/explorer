class_name DiffStore
extends RefCounted
## Изменения рельефа поверх процедурной базы: полная запись тайла (8 байт, см. ChunkData)
## по мировым координатам. При повторной загрузке чанка база генерируется из seed,
## затем сверху накладываются записи отсюда.

const _BIAS := 1 << 20

var _records: Dictionary[int, PackedByteArray] = {}
var _by_chunk: Dictionary[Vector2i, PackedInt64Array] = {}   ## чанк-владелец → ключи его тайлов


static func key(tx: int, tz: int) -> int:
	return ((tx + _BIAS) << 21) | (tz + _BIAS)


static func key_tile(k: int) -> Vector2i:
	return Vector2i((k >> 21) - _BIAS, (k & ((1 << 21) - 1)) - _BIAS)


func set_record(tx: int, tz: int, record: PackedByteArray) -> void:
	var k := key(tx, tz)
	if not _records.has(k):
		var owner := Grid.chunk_of_tile(tx, tz)
		var keys: PackedInt64Array = _by_chunk.get(owner, PackedInt64Array())
		keys.append(k)
		_by_chunk[owner] = keys
	_records[k] = record


func get_record(tx: int, tz: int) -> PackedByteArray:
	return _records.get(key(tx, tz), PackedByteArray())


func size() -> int:
	return _records.size()


## Накладывает записи на окно чанка (свои тайлы и фартук).
func apply_to(data: ChunkData) -> void:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var keys: PackedInt64Array = _by_chunk.get(data.coord + Vector2i(dx, dz), PackedInt64Array())
			for k in keys:
				var t := key_tile(k)
				if data.contains_tile(t.x, t.y):
					data.write_record(data.local_index(t.x, t.y), _records[k])
